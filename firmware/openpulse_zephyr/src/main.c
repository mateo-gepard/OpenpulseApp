#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/reboot.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/uuid.h>
#include <errno.h>
#include <limits.h>
#include <string.h>

LOG_MODULE_REGISTER(openpulse, LOG_LEVEL_INF);

#define OPENPULSE_FW_VERSION "0.1.1-hr-window"
#define OPENPULSE_HW_VERSION "xiao_ble/nrf52840/sense"

#define MAXM86161_I2C_ADDR 0x62
#define MAXM86161_REG_INT_STATUS1 0x00
#define MAXM86161_REG_INT_STATUS2 0x01
#define MAXM86161_REG_OVERFLOW_COUNTER 0x06
#define MAXM86161_REG_FIFO_DATA_COUNT 0x07
#define MAXM86161_REG_FIFO_DATA 0x08
#define MAXM86161_REG_FIFO_CONFIG2 0x0a
#define MAXM86161_REG_SYSTEM_CONTROL 0x0d
#define MAXM86161_REG_PPG_CONFIG1 0x11
#define MAXM86161_REG_PPG_CONFIG2 0x12
#define MAXM86161_REG_PPG_CONFIG3 0x13
#define MAXM86161_REG_PHOTODIODE_BIAS 0x15
#define MAXM86161_REG_LED_SEQ1 0x20
#define MAXM86161_REG_LED_SEQ2 0x21
#define MAXM86161_REG_LED_SEQ3 0x22
#define MAXM86161_REG_LED1_PA 0x23
#define MAXM86161_REG_LED2_PA 0x24
#define MAXM86161_REG_LED3_PA 0x25
#define MAXM86161_REG_LED_RANGE1 0x2a
#define MAXM86161_REG_PART_ID 0xff
#define MAXM86161_EXPECTED_PART_ID 0x36
#define MAXM86161_FIFO_ITEM_BYTES 3
#define MAXM86161_FIFO_FLUSH BIT(4)
#define MAXM86161_FIFO_RO BIT(1)
#define MAXM86161_SYSTEM_RESET BIT(0)
#define MAXM86161_SYSTEM_SHDN BIT(1)
#define MAXM86161_SYSTEM_SINGLE_PPG BIT(3)
#define MAXM86161_SYSTEM_LOW_POWER BIT(2)

#define LSM6DSL_I2C_ADDR 0x6a
#define LSM6DSL_REG_CTRL10_C 0x19
#define LSM6DSL_REG_STEP_COUNTER_L 0x4b
#define LSM6DSL_REG_STEP_COUNTER_H 0x4c
#define LSM6DSL_CTRL10_C_PEDO_EN BIT(4)
#define LSM6DSL_CTRL10_C_FUNC_EN BIT(2)
#define LSM6DSL_CTRL10_C_PEDO_RST_STEP BIT(1)

#define OP_FRAME_LIVE 0x10
#define OP_FRAME_BACKFILL 0x20
#define OP_FRAME_RAW_PPG 0x30
#define OP_RECORD_KIND_GAP_MARKER 4
#define OP_LIVE_RECORD_BASE_LEN 12
#define OP_LIVE_RECORD_ACTIVITY_LEN 17
#define OP_LIVE_RECORD_METRICS_LEN 20
#define OP_LIVE_RECORD_CALIBRATION_LEN 22
#define OP_RAW_FRAME_HEADER_LEN 8
#define OP_RAW_MAX_PAYLOAD_BYTES 180
#define OP_RAW_SETTLE_MS 120
#define OP_PPG_BUFFER_LEN 4096
#define OP_PPG_MIN_IBI_MS 333
#define OP_PPG_MAX_IBI_MS 2000
#define OP_PPG_HR_MIN_WINDOW_MS 10000
#define OP_PPG_HR_PROPER_WINDOW_MS 60000
#define OP_PPG_HR_CALIBRATION_MS 60000
#define OP_PPG_SPO2_CALIBRATION_MS 600000
#define OP_PPG_SPO2_WINDOW_MS 15000
#define OP_PPG_SPO2_MIN_WINDOW_MS 6000
#define OP_PPG_POLL_MS 250
#define OP_LIVE_NOTIFY_MS 1000
#define OP_OPTICAL_HOLD_MS 15000
#define OP_OPTICAL_FIRST_CAL_MS 120000
#define OP_OPTICAL_CAL_HOUR_MS 3600000
#define OP_OPTICAL_CAL_FULL_HOURS 24
#define OP_OPTICAL_MIN_GOOD_HOUR_WINDOWS 60

#define OP_EVENT_ATTACHED 1
#define OP_EVENT_REMOVED 2
#define OP_EVENT_FAULT 5
#define OP_PUCK_KIND_PPG 1
#define OP_SENSOR_STATUS_OK 0
#define OP_SENSOR_STATUS_UNAVAILABLE 1
#define OP_SENSOR_STATUS_I2C_NOT_READY 2
#define OP_SENSOR_STATUS_UNEXPECTED_PART_ID 3
#define OP_MOTION_STATUS_OK 0
#define OP_MOTION_STATUS_UNAVAILABLE 1
#define OP_MOTION_STATUS_PEDOMETER_UNAVAILABLE 2

#define OP_QUALITY_SKIN_CONTACT BIT(0)
#define OP_QUALITY_MOTION_ARTIFACT BIT(1)
#define OP_QUALITY_LOW_PERFUSION BIT(2)
#define OP_QUALITY_PUCK_CHANGED BIT(3)
#define OP_QUALITY_BATTERY_LOW BIT(4)
#define OP_QUALITY_PPG_CLIPPING BIT(5)
#define OP_QUALITY_PPG_UNCALIBRATED BIT(6)
#define OP_BATTERY_DIVIDER_NUM 3
#define OP_BATTERY_DIVIDER_DEN 1

enum op_mode {
	OP_MODE_STANDBY = 0,
	OP_MODE_ACTIVE = 1,
	OP_MODE_LOW_POWER = 2,
	OP_MODE_HR_ONLY = 3,
	OP_MODE_SHIP = 4,
};

struct ppg_window_stats {
	uint32_t green_min;
	uint32_t green_max;
	uint64_t green_sum;
	uint16_t green_count;
	uint32_t red_min;
	uint32_t red_max;
	uint64_t red_sum;
	uint16_t red_count;
	uint32_t ir_min;
	uint32_t ir_max;
	uint64_t ir_sum;
	uint16_t ir_count;
	uint32_t ratio_x1000;
};

struct ppg_ring {
	uint32_t samples[OP_PPG_BUFFER_LEN];
	uint16_t head;
	uint16_t count;
	uint32_t sample_index;
};

struct ppg_channel_stats {
	uint32_t min;
	uint32_t max;
	uint64_t sum;
	uint16_t count;
};

struct optical_calibration_state {
	bool initialized;
	uint32_t green_dc_ema;
	uint32_t green_ac_ema;
	uint32_t red_dc_ema;
	uint32_t red_ac_ema;
	uint32_t ir_dc_ema;
	uint32_t ir_ac_ema;
	uint32_t ratio_x1000_ema;
	uint64_t hour_green_dc_sum;
	uint64_t hour_green_ac_sum;
	uint64_t hour_red_dc_sum;
	uint64_t hour_red_ac_sum;
	uint64_t hour_ir_dc_sum;
	uint64_t hour_ir_ac_sum;
	uint64_t hour_ratio_sum;
	uint16_t hour_good_windows;
	uint16_t accepted_hr_windows;
	uint16_t accepted_spo2_windows;
	uint16_t rejected_windows;
	uint8_t hourly_updates;
	int64_t started_ms;
	int64_t last_hour_update_ms;
};

static struct bt_conn *current_conn;
static bool control_notify_enabled;
static bool live_notify_enabled;
static bool bulk_notify_enabled;
static bool raw_notify_enabled;
static bool puck_notify_enabled;
static bool battery_notify_enabled;

static bool time_synced;
static uint64_t synced_unix_ms;
static uint64_t synced_device_uptime_ms;
static int64_t last_app_activity_ms;
static enum op_mode current_mode = OP_MODE_STANDBY;
static uint16_t live_sequence;
static uint16_t bulk_sequence;
static uint16_t raw_sequence;
static uint16_t sampling_hz = 64;
static uint8_t led_green_ma = 12;
static uint8_t led_red_ma = 8;
static uint8_t led_ir_ma = 8;
static bool maxm86161_configured;
static uint16_t maxm86161_config_sampling_hz;
static uint8_t maxm86161_config_led_green_ma;
static uint8_t maxm86161_config_led_red_ma;
static uint8_t maxm86161_config_led_ir_ma;
static uint16_t pending_raw_seconds;
static uint8_t pending_raw_sensor_status = OP_SENSOR_STATUS_UNAVAILABLE;
static bool imu_ready;
static int16_t latest_accel_milli_g;
static uint32_t step_count;
static uint8_t motion_status = OP_MOTION_STATUS_UNAVAILABLE;
static bool lsm6dsl_pedometer_ready;
static bool lsm6dsl_step_baseline_ready;
static uint16_t lsm6dsl_last_step_counter;

static uint8_t battery_level = 0xff;
static bool battery_level_known;
static bool battery_adc_ready;
static struct ppg_ring ppg_green_ring;
static struct ppg_ring ppg_red_ring;
static struct ppg_ring ppg_ir_ring;
static int64_t ppg_metrics_started_ms;
static struct optical_calibration_state optical_cal;
static uint16_t latest_hr_x10;
static uint16_t latest_ibi_ms;
static uint8_t latest_spo2_percent = 0xff;
static uint8_t latest_hr_confidence;
static uint8_t latest_spo2_confidence;
static uint8_t latest_metric_calibration;
static int64_t latest_hr_valid_ms;
static int64_t latest_spo2_valid_ms;
static uint32_t spo2_ratio_filtered_x1000;
static int64_t last_live_notification_ms;
static uint8_t last_puck_status[4] = {
	OP_EVENT_REMOVED,
	OP_PUCK_KIND_PPG,
	0,
	OP_SENSOR_STATUS_UNAVAILABLE,
};

extern const struct bt_gatt_service_static openpulse_svc;

static void stream_work_handler(struct k_work *work);
static void sensor_work_handler(struct k_work *work);
static void motion_work_handler(struct k_work *work);
static void raw_window_work_handler(struct k_work *work);
static void advertising_work_handler(struct k_work *work);
static K_WORK_DELAYABLE_DEFINE(stream_work, stream_work_handler);
static K_WORK_DELAYABLE_DEFINE(sensor_work, sensor_work_handler);
static K_WORK_DELAYABLE_DEFINE(motion_work, motion_work_handler);
static K_WORK_DELAYABLE_DEFINE(raw_window_work, raw_window_work_handler);
static K_WORK_DELAYABLE_DEFINE(advertising_work, advertising_work_handler);

static struct bt_uuid_16 dis_service_uuid = BT_UUID_INIT_16(0x180a);
static struct bt_uuid_16 dis_manufacturer_uuid = BT_UUID_INIT_16(0x2a29);
static struct bt_uuid_16 dis_model_uuid = BT_UUID_INIT_16(0x2a24);
static struct bt_uuid_16 dis_firmware_uuid = BT_UUID_INIT_16(0x2a26);
static struct bt_uuid_16 dis_hardware_uuid = BT_UUID_INIT_16(0x2a27);
static struct bt_uuid_16 battery_service_uuid = BT_UUID_INIT_16(0x180f);
static struct bt_uuid_16 battery_level_uuid = BT_UUID_INIT_16(0x2a19);

static struct bt_uuid_128 op_service_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0000, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));
static struct bt_uuid_128 op_control_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0001, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));
static struct bt_uuid_128 op_live_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0002, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));
static struct bt_uuid_128 op_bulk_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0003, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));
static struct bt_uuid_128 op_raw_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0004, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));
static struct bt_uuid_128 op_puck_uuid = BT_UUID_INIT_128(
	BT_UUID_128_ENCODE(0xf04d0005, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001));

static const uint8_t adv_flags[] = {
	BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR,
};

static const uint8_t adv_openpulse_service[] = {
	BT_UUID_128_ENCODE(0xf04d0000, 0x57f5, 0x4f5a, 0x9b80, 0x4f6f2f1d0001),
};

static ssize_t read_static_string(struct bt_conn *conn,
				  const struct bt_gatt_attr *attr,
				  void *buf,
				  uint16_t len,
				  uint16_t offset)
{
	const char *value = attr->user_data;

	return bt_gatt_attr_read(conn, attr, buf, len, offset, value, strlen(value));
}

static void mark_app_activity(void)
{
	last_app_activity_ms = k_uptime_get();
}

static ssize_t read_battery_level(struct bt_conn *conn,
				  const struct bt_gatt_attr *attr,
				  void *buf,
				  uint16_t len,
				  uint16_t offset)
{
	mark_app_activity();
	return bt_gatt_attr_read(conn, attr, buf, len, offset, &battery_level, sizeof(battery_level));
}

static void battery_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	battery_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

BT_GATT_SERVICE_DEFINE(dis_svc,
	BT_GATT_PRIMARY_SERVICE(&dis_service_uuid.uuid),
	BT_GATT_CHARACTERISTIC(&dis_manufacturer_uuid.uuid,
			       BT_GATT_CHRC_READ,
			       BT_GATT_PERM_READ,
			       read_static_string, NULL, "OpenPulse"),
	BT_GATT_CHARACTERISTIC(&dis_model_uuid.uuid,
			       BT_GATT_CHRC_READ,
			       BT_GATT_PERM_READ,
			       read_static_string, NULL, "OpenPulse XIAO nRF52840 Sense"),
	BT_GATT_CHARACTERISTIC(&dis_firmware_uuid.uuid,
			       BT_GATT_CHRC_READ,
			       BT_GATT_PERM_READ,
			       read_static_string, NULL, OPENPULSE_FW_VERSION),
	BT_GATT_CHARACTERISTIC(&dis_hardware_uuid.uuid,
			       BT_GATT_CHRC_READ,
			       BT_GATT_PERM_READ,
			       read_static_string, NULL, OPENPULSE_HW_VERSION)
);

BT_GATT_SERVICE_DEFINE(battery_svc,
	BT_GATT_PRIMARY_SERVICE(&battery_service_uuid.uuid),
	BT_GATT_CHARACTERISTIC(&battery_level_uuid.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ,
			       read_battery_level, NULL, NULL),
	BT_GATT_CCC(battery_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE)
);

static int notify_battery(void)
{
	if (!battery_notify_enabled || !current_conn) {
		return 0;
	}

	return bt_gatt_notify(current_conn, &battery_svc.attrs[2], &battery_level, sizeof(battery_level));
}

static int start_advertising(void);
static int notify_puck_status(void);
static void update_puck_status(uint8_t sensor_status);
static uint8_t probe_maxm86161(void);
static uint8_t prepare_maxm86161(void);
static void stop_maxm86161(void);
static void ppg_buffer_reset(void);
static int read_maxm86161_fifo_payload(uint8_t *payload,
				       uint8_t max_payload_len,
				       uint8_t *payload_len);

static ssize_t read_control(struct bt_conn *conn,
			    const struct bt_gatt_attr *attr,
			    void *buf,
			    uint16_t len,
			    uint16_t offset)
{
	uint8_t status[12];

	mark_app_activity();
	status[0] = time_synced ? 1 : 0;
	status[1] = (uint8_t)current_mode;
	status[2] = battery_level_known ? battery_level : 0xff;
	status[3] = last_puck_status[3];
	sys_put_le64(k_uptime_get(), &status[4]);

	return bt_gatt_attr_read(conn, attr, buf, len, offset, status, sizeof(status));
}

static void notify_control_ack(uint8_t command, uint8_t status)
{
	uint8_t frame[4] = { 0x80, command, status, (uint8_t)current_mode };

	if (control_notify_enabled && current_conn) {
		(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[2], frame, sizeof(frame));
	}
}

static void send_gap_marker(uint64_t from_uptime_ms)
{
	uint8_t frame[14];

	frame[0] = OP_FRAME_BACKFILL;
	frame[1] = OP_RECORD_KIND_GAP_MARKER;
	sys_put_le16(bulk_sequence++, &frame[2]);
	sys_put_le16(sizeof(uint64_t), &frame[4]);
	sys_put_le64(from_uptime_ms, &frame[6]);

	if (bulk_notify_enabled && current_conn) {
		(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[8], frame, sizeof(frame));
	}
}

static void send_raw_frame(uint16_t seconds,
			   uint8_t sensor_status,
			   const uint8_t *payload,
			   uint8_t payload_len)
{
	uint8_t frame[OP_RAW_FRAME_HEADER_LEN + OP_RAW_MAX_PAYLOAD_BYTES];

	if (payload_len > OP_RAW_MAX_PAYLOAD_BYTES) {
		payload_len = OP_RAW_MAX_PAYLOAD_BYTES;
	}

	frame[0] = OP_FRAME_RAW_PPG;
	sys_put_le16(raw_sequence++, &frame[1]);
	sys_put_le16(seconds, &frame[3]);
	frame[5] = last_puck_status[2];
	frame[6] = sensor_status;
	frame[7] = payload_len;
	if (payload_len > 0 && payload != NULL) {
		memcpy(&frame[OP_RAW_FRAME_HEADER_LEN], payload, payload_len);
	}

	if (raw_notify_enabled && current_conn) {
		(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[11],
				     frame, OP_RAW_FRAME_HEADER_LEN + payload_len);
	}
}

static ssize_t write_control(struct bt_conn *conn,
			     const struct bt_gatt_attr *attr,
			     const void *buf,
			     uint16_t len,
			     uint16_t offset,
			     uint8_t flags)
{
	const uint8_t *bytes = buf;
	uint8_t command;
	uint8_t payload_len;
	const uint8_t *payload;

	mark_app_activity();
	if (offset != 0 || len < 2) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
	}

	command = bytes[0];
	payload_len = bytes[1];
	if ((uint16_t)payload_len + 2U != len) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	payload = &bytes[2];

	switch (command) {
	case 0x01:
		if (payload_len != 16) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		synced_unix_ms = sys_get_le64(&payload[0]);
		synced_device_uptime_ms = sys_get_le64(&payload[8]);
		time_synced = true;
		current_mode = OP_MODE_ACTIVE;
		last_live_notification_ms = 0;
		notify_control_ack(command, 0);
		k_work_reschedule(&stream_work, K_NO_WAIT);
		break;
	case 0x02:
		if (payload_len != 1 || payload[0] > OP_MODE_SHIP) {
			return BT_GATT_ERR(BT_ATT_ERR_VALUE_NOT_ALLOWED);
		}
		current_mode = (enum op_mode)payload[0];
		notify_control_ack(command, 0);
		break;
	case 0x03:
		if (payload_len != 2) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		sampling_hz = sys_get_le16(payload);
		maxm86161_configured = false;
		notify_control_ack(command, 0);
		break;
	case 0x04:
		if (payload_len != 3) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		led_green_ma = payload[0];
		led_red_ma = payload[1];
		led_ir_ma = payload[2];
		maxm86161_configured = false;
		notify_control_ack(command, 0);
		break;
	case 0x05:
		if (payload_len != 8) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		send_gap_marker(sys_get_le64(payload));
		notify_control_ack(command, 0);
		break;
	case 0x06:
		if (payload_len != 2) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		pending_raw_seconds = sys_get_le16(payload);
		if (pending_raw_seconds == 0) {
			k_work_cancel_delayable(&raw_window_work);
			stop_maxm86161();
			send_raw_frame(0, probe_maxm86161(), NULL, 0);
			notify_control_ack(command, 0);
			break;
		}
		pending_raw_sensor_status = prepare_maxm86161();
		if (pending_raw_sensor_status == OP_SENSOR_STATUS_OK) {
			k_work_reschedule(&raw_window_work, K_MSEC(OP_RAW_SETTLE_MS));
		} else {
			send_raw_frame(pending_raw_seconds, pending_raw_sensor_status, NULL, 0);
		}
		notify_control_ack(command, 0);
		break;
	case 0x07:
		if (payload_len != 0) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		current_mode = OP_MODE_SHIP;
		notify_control_ack(command, 0);
		break;
	default:
		notify_control_ack(command, 1);
		return BT_GATT_ERR(BT_ATT_ERR_VALUE_NOT_ALLOWED);
	}

	return len;
}

static ssize_t read_puck_status(struct bt_conn *conn,
				const struct bt_gatt_attr *attr,
				void *buf,
				uint16_t len,
				uint16_t offset)
{
	mark_app_activity();
	return bt_gatt_attr_read(conn, attr, buf, len, offset, last_puck_status, sizeof(last_puck_status));
}

static void control_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	control_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void live_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	live_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
	if (live_notify_enabled && time_synced) {
		last_live_notification_ms = 0;
		k_work_reschedule(&stream_work, K_NO_WAIT);
	} else if (!live_notify_enabled) {
		k_work_cancel_delayable(&stream_work);
		stop_maxm86161();
	}
}

static void bulk_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	bulk_notify_enabled = (value == BT_GATT_CCC_NOTIFY || value == BT_GATT_CCC_INDICATE);
}

static void raw_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	raw_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void puck_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	mark_app_activity();
	puck_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
	if (puck_notify_enabled) {
		(void)notify_puck_status();
	}
}

BT_GATT_SERVICE_DEFINE(openpulse_svc,
	BT_GATT_PRIMARY_SERVICE(&op_service_uuid),
	BT_GATT_CHARACTERISTIC(&op_control_uuid.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE,
			       read_control, write_control, NULL),
	BT_GATT_CCC(control_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&op_live_uuid.uuid,
			       BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_NONE,
			       NULL, NULL, NULL),
	BT_GATT_CCC(live_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&op_bulk_uuid.uuid,
			       BT_GATT_CHRC_NOTIFY | BT_GATT_CHRC_INDICATE,
			       BT_GATT_PERM_NONE,
			       NULL, NULL, NULL),
	BT_GATT_CCC(bulk_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&op_raw_uuid.uuid,
			       BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_NONE,
			       NULL, NULL, NULL),
	BT_GATT_CCC(raw_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&op_puck_uuid.uuid,
			       BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ,
			       read_puck_status, NULL, NULL),
	BT_GATT_CCC(puck_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE)
);

#if DT_NODE_HAS_STATUS(DT_NODELABEL(i2c0), okay)
#define OPENPULSE_HAS_I2C0 1
static const struct device *const ppg_i2c0 = DEVICE_DT_GET(DT_NODELABEL(i2c0));
#else
#define OPENPULSE_HAS_I2C0 0
#endif

#if DT_NODE_HAS_STATUS(DT_NODELABEL(i2c1), okay)
#define OPENPULSE_HAS_I2C1 1
static const struct device *const ppg_i2c1 = DEVICE_DT_GET(DT_NODELABEL(i2c1));
#else
#define OPENPULSE_HAS_I2C1 0
#endif

#define OPENPULSE_HAS_I2C (OPENPULSE_HAS_I2C0 || OPENPULSE_HAS_I2C1)

#if OPENPULSE_HAS_I2C
static const struct device *active_ppg_i2c;
static const char *active_ppg_i2c_name = "none";
static uint8_t last_probe_status = 0xff;
#endif

#if DT_NODE_HAS_STATUS(DT_NODELABEL(lsm6ds3tr_c), okay)
#define OPENPULSE_HAS_IMU 1
static const struct device *const imu_dev = DEVICE_DT_GET(DT_NODELABEL(lsm6ds3tr_c));
#else
#define OPENPULSE_HAS_IMU 0
#endif

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), io_channels)
#define OPENPULSE_HAS_ADC 1
static const struct adc_dt_spec vbat_adc = ADC_DT_SPEC_GET_BY_IDX(DT_PATH(zephyr_user), 0);
#else
#define OPENPULSE_HAS_ADC 0
#endif

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), battery_enable_gpios)
static const struct gpio_dt_spec battery_enable =
	GPIO_DT_SPEC_GET(DT_PATH(zephyr_user), battery_enable_gpios);
#endif

static uint8_t maxm86161_sample_rate_code(uint16_t hz)
{
	if (hz <= 8) {
		return 0x0a;
	}
	if (hz <= 16) {
		return 0x0b;
	}
	if (hz <= 25) {
		return 0x00;
	}
	if (hz <= 32) {
		return 0x0c;
	}
	if (hz <= 50) {
		return 0x01;
	}
	if (hz <= 64) {
		return 0x0d;
	}
	if (hz <= 84) {
		return 0x02;
	}
	if (hz <= 100) {
		return 0x03;
	}
	if (hz <= 128) {
		return 0x0e;
	}
	if (hz <= 256) {
		return 0x0f;
	}

	return 0x10;
}

static uint8_t maxm86161_led_current_code(uint8_t ma)
{
	uint32_t code = ((uint32_t)ma * 100U + 6U) / 12U;

	return code > 0xffU ? 0xff : (uint8_t)code;
}

static void maxm86161_led_sequence(uint8_t *seq1, uint8_t *seq2, uint8_t *seq3)
{
	uint8_t ledc[6] = { 0 };
	uint8_t count = 0;

	if (led_green_ma > 0) {
		ledc[count++] = 0x01;
	}
	if (led_ir_ma > 0) {
		ledc[count++] = 0x02;
	}
	if (led_red_ma > 0) {
		ledc[count++] = 0x03;
	}

	*seq1 = (ledc[1] << 4) | ledc[0];
	*seq2 = (ledc[3] << 4) | ledc[2];
	*seq3 = (ledc[5] << 4) | ledc[4];
}

static int maxm86161_write_reg(uint8_t reg, uint8_t value)
{
#if OPENPULSE_HAS_I2C
	if (active_ppg_i2c == NULL) {
		return -ENODEV;
	}

	return i2c_reg_write_byte(active_ppg_i2c, MAXM86161_I2C_ADDR, reg, value);
#else
	ARG_UNUSED(reg);
	ARG_UNUSED(value);
	return -ENODEV;
#endif
}

static int maxm86161_read_reg(uint8_t reg, uint8_t *value)
{
#if OPENPULSE_HAS_I2C
	if (active_ppg_i2c == NULL) {
		return -ENODEV;
	}

	return i2c_reg_read_byte(active_ppg_i2c, MAXM86161_I2C_ADDR, reg, value);
#else
	ARG_UNUSED(reg);
	ARG_UNUSED(value);
	return -ENODEV;
#endif
}

#if OPENPULSE_HAS_I2C
static uint8_t probe_maxm86161_bus(const struct device *bus,
				   const char *bus_name,
				   bool *saw_ready_bus)
{
	uint8_t part_id = 0;
	const struct device *previous_bus = active_ppg_i2c;
	int err;

	if (!device_is_ready(bus)) {
		return OP_SENSOR_STATUS_I2C_NOT_READY;
	}

	*saw_ready_bus = true;
	err = i2c_reg_read_byte(bus, MAXM86161_I2C_ADDR, MAXM86161_REG_PART_ID, &part_id);
	if (err) {
		return OP_SENSOR_STATUS_UNAVAILABLE;
	}

	if (part_id != MAXM86161_EXPECTED_PART_ID) {
		LOG_WRN("MAXM86161 unexpected part id on %s: 0x%02x", bus_name, part_id);
		return OP_SENSOR_STATUS_UNEXPECTED_PART_ID;
	}

	active_ppg_i2c = bus;
	active_ppg_i2c_name = bus_name;
	if (previous_bus != bus || last_probe_status != OP_SENSOR_STATUS_OK) {
		LOG_INF("MAXM86161 detected on %s", bus_name);
	}

	return OP_SENSOR_STATUS_OK;
}
#endif

static uint8_t probe_maxm86161(void)
{
#if OPENPULSE_HAS_I2C
	bool saw_ready_bus = false;
	bool saw_unexpected_part_id = false;
	uint8_t status;

	if (active_ppg_i2c != NULL) {
		status = probe_maxm86161_bus(active_ppg_i2c, active_ppg_i2c_name, &saw_ready_bus);
		if (status == OP_SENSOR_STATUS_OK) {
			last_probe_status = status;
			return status;
		}

		active_ppg_i2c = NULL;
		active_ppg_i2c_name = "none";
		maxm86161_configured = false;
		if (status == OP_SENSOR_STATUS_UNEXPECTED_PART_ID) {
			saw_unexpected_part_id = true;
		}
	}

#if OPENPULSE_HAS_I2C1
	status = probe_maxm86161_bus(ppg_i2c1, "i2c1/xiao-connector", &saw_ready_bus);
	if (status == OP_SENSOR_STATUS_OK) {
		last_probe_status = status;
		return status;
	}
	if (status == OP_SENSOR_STATUS_UNEXPECTED_PART_ID) {
		saw_unexpected_part_id = true;
	}
#endif

#if OPENPULSE_HAS_I2C0
	status = probe_maxm86161_bus(ppg_i2c0, "i2c0/onboard", &saw_ready_bus);
	if (status == OP_SENSOR_STATUS_OK) {
		last_probe_status = status;
		return status;
	}
	if (status == OP_SENSOR_STATUS_UNEXPECTED_PART_ID) {
		saw_unexpected_part_id = true;
	}
#endif

	status = saw_unexpected_part_id ? OP_SENSOR_STATUS_UNEXPECTED_PART_ID :
		 (saw_ready_bus ? OP_SENSOR_STATUS_UNAVAILABLE : OP_SENSOR_STATUS_I2C_NOT_READY);
	if (status != last_probe_status) {
		LOG_WRN("MAXM86161 unavailable on configured I2C buses, status %u", status);
		last_probe_status = status;
	}
	return status;
#else
	return OP_SENSOR_STATUS_I2C_NOT_READY;
#endif
}

static int configure_maxm86161(void)
{
	int err;
	uint8_t discard;
	uint8_t ppg_config2;
	uint8_t system_control = MAXM86161_SYSTEM_SINGLE_PPG;
	uint8_t led_seq1;
	uint8_t led_seq2;
	uint8_t led_seq3;

	if (maxm86161_configured &&
	    maxm86161_config_sampling_hz == sampling_hz &&
	    maxm86161_config_led_green_ma == led_green_ma &&
	    maxm86161_config_led_red_ma == led_red_ma &&
	    maxm86161_config_led_ir_ma == led_ir_ma) {
		return 0;
	}

	err = maxm86161_write_reg(MAXM86161_REG_SYSTEM_CONTROL, MAXM86161_SYSTEM_RESET);
	if (err) {
		LOG_WRN("MAXM86161 reset failed: %d", err);
		return err;
	}
	k_sleep(K_MSEC(5));

	err = maxm86161_write_reg(MAXM86161_REG_SYSTEM_CONTROL,
				  MAXM86161_SYSTEM_SINGLE_PPG | MAXM86161_SYSTEM_SHDN);
	if (err) {
		LOG_WRN("MAXM86161 shutdown before config failed: %d", err);
		return err;
	}

	(void)maxm86161_read_reg(MAXM86161_REG_INT_STATUS1, &discard);
	(void)maxm86161_read_reg(MAXM86161_REG_INT_STATUS2, &discard);
	maxm86161_led_sequence(&led_seq1, &led_seq2, &led_seq3);
	ppg_config2 = (maxm86161_sample_rate_code(sampling_hz) << 3);
	if (sampling_hz <= 256) {
		system_control |= MAXM86161_SYSTEM_LOW_POWER;
	}

	err = maxm86161_write_reg(MAXM86161_REG_FIFO_CONFIG2, MAXM86161_FIFO_FLUSH);
	if (err) {
		LOG_WRN("MAXM86161 FIFO flush failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_FIFO_CONFIG2, MAXM86161_FIFO_RO);
	if (err) {
		LOG_WRN("MAXM86161 FIFO rollover config failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_PPG_CONFIG1, 0x0b);
	if (err) {
		LOG_WRN("MAXM86161 PPG config 1 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_PPG_CONFIG2, ppg_config2);
	if (err) {
		LOG_WRN("MAXM86161 PPG config 2 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_PPG_CONFIG3, 0xc0);
	if (err) {
		LOG_WRN("MAXM86161 PPG config 3 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_PHOTODIODE_BIAS, 0x01);
	if (err) {
		LOG_WRN("MAXM86161 photodiode bias failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED_RANGE1, 0x00);
	if (err) {
		LOG_WRN("MAXM86161 LED range failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED1_PA,
				  maxm86161_led_current_code(led_green_ma));
	if (err) {
		LOG_WRN("MAXM86161 LED1 current failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED2_PA,
				  maxm86161_led_current_code(led_ir_ma));
	if (err) {
		LOG_WRN("MAXM86161 LED2 current failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED3_PA,
				  maxm86161_led_current_code(led_red_ma));
	if (err) {
		LOG_WRN("MAXM86161 LED3 current failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED_SEQ3, led_seq3);
	if (err) {
		LOG_WRN("MAXM86161 LED sequence 3 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED_SEQ2, led_seq2);
	if (err) {
		LOG_WRN("MAXM86161 LED sequence 2 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_LED_SEQ1, led_seq1);
	if (err) {
		LOG_WRN("MAXM86161 LED sequence 1 failed: %d", err);
		return err;
	}
	err = maxm86161_write_reg(MAXM86161_REG_SYSTEM_CONTROL, system_control);
	if (err) {
		LOG_WRN("MAXM86161 start failed: %d", err);
		return err;
	}

	maxm86161_configured = true;
	maxm86161_config_sampling_hz = sampling_hz;
	maxm86161_config_led_green_ma = led_green_ma;
	maxm86161_config_led_red_ma = led_red_ma;
	maxm86161_config_led_ir_ma = led_ir_ma;

	return 0;
}

static uint8_t prepare_maxm86161(void)
{
	uint8_t status = probe_maxm86161();

	if (status != OP_SENSOR_STATUS_OK) {
		maxm86161_configured = false;
		return status;
	}

	if (configure_maxm86161()) {
		maxm86161_configured = false;
		return OP_SENSOR_STATUS_UNAVAILABLE;
	}

	return OP_SENSOR_STATUS_OK;
}

static void stop_maxm86161(void)
{
#if OPENPULSE_HAS_I2C
	if (active_ppg_i2c == NULL && probe_maxm86161() != OP_SENSOR_STATUS_OK) {
		maxm86161_configured = false;
	} else {
		if (maxm86161_write_reg(MAXM86161_REG_SYSTEM_CONTROL,
					MAXM86161_SYSTEM_SINGLE_PPG | MAXM86161_SYSTEM_SHDN)) {
			LOG_WRN("MAXM86161 shutdown failed");
		}
		maxm86161_configured = false;
	}
#endif
	ppg_metrics_started_ms = 0;
	ppg_buffer_reset();
	latest_hr_x10 = 0;
	latest_ibi_ms = 0;
	latest_spo2_percent = 0xff;
	latest_hr_confidence = 0;
	latest_spo2_confidence = 0;
	latest_metric_calibration = 0;
	latest_hr_valid_ms = 0;
	latest_spo2_valid_ms = 0;
	spo2_ratio_filtered_x1000 = 0;
}

static uint8_t confidence_ramp(int64_t started_ms, uint32_t target_ms)
{
	int64_t elapsed_ms;

	if (started_ms <= 0) {
		return 0;
	}

	elapsed_ms = k_uptime_get() - started_ms;
	if (elapsed_ms <= 0) {
		return 0;
	}
	if ((uint64_t)elapsed_ms >= target_ms) {
		return 100;
	}

	return (uint8_t)(((uint64_t)elapsed_ms * 100U) / target_ms);
}

static uint32_t max_u32(uint32_t a, uint32_t b)
{
	return a > b ? a : b;
}

static uint32_t min_u32(uint32_t a, uint32_t b)
{
	return a < b ? a : b;
}

static uint32_t abs_i32(int32_t value)
{
	return value < 0 ? (uint32_t)-value : (uint32_t)value;
}

static uint32_t ema_u32(uint32_t current, uint32_t sample, uint8_t sample_weight)
{
	uint8_t keep_weight;

	if (current == 0) {
		return sample;
	}

	if (sample_weight > 16U) {
		sample_weight = 16U;
	}
	keep_weight = 16U - sample_weight;

	return (uint32_t)(((uint64_t)current * keep_weight +
			   (uint64_t)sample * sample_weight +
			   8U) / 16U);
}

static uint32_t stats_mean(uint64_t sum, uint16_t count)
{
	if (count == 0) {
		return 0;
	}

	return (uint32_t)(sum / count);
}

static uint32_t stats_range(uint32_t min, uint32_t max)
{
	return max > min ? max - min : 0;
}

static uint8_t decay_confidence(uint8_t confidence, int64_t age_ms, uint8_t floor)
{
	uint32_t decay;

	if (confidence <= floor) {
		return confidence;
	}

	if (age_ms < 0) {
		age_ms = 0;
	}

	decay = 12U + (uint32_t)(age_ms / 1000) * 4U;
	if (decay >= confidence - floor) {
		return floor;
	}

	return (uint8_t)(confidence - decay);
}

static void hold_hr_value(uint8_t *quality)
{
	int64_t age_ms = latest_hr_valid_ms > 0 ? k_uptime_get() - latest_hr_valid_ms :
						 OP_OPTICAL_HOLD_MS + 1;

	*quality |= OP_QUALITY_LOW_PERFUSION | OP_QUALITY_PPG_UNCALIBRATED;
	if (latest_hr_x10 != 0 && age_ms <= OP_OPTICAL_HOLD_MS) {
		latest_hr_confidence = decay_confidence(latest_hr_confidence, age_ms, 8);
		return;
	}

	latest_hr_x10 = 0;
	latest_ibi_ms = 0;
	latest_hr_confidence = 0;
}

static void hold_spo2_value(uint8_t *quality)
{
	int64_t age_ms = latest_spo2_valid_ms > 0 ? k_uptime_get() - latest_spo2_valid_ms :
						    OP_OPTICAL_HOLD_MS + 1;

	*quality |= OP_QUALITY_LOW_PERFUSION | OP_QUALITY_PPG_UNCALIBRATED;
	if (latest_spo2_percent != 0xff && age_ms <= OP_OPTICAL_HOLD_MS) {
		latest_spo2_confidence = decay_confidence(latest_spo2_confidence, age_ms, 8);
		return;
	}

	latest_spo2_percent = 0xff;
	latest_spo2_confidence = 0;
}

static void ppg_ring_reset(struct ppg_ring *ring)
{
	memset(ring, 0, sizeof(*ring));
}

static void ppg_buffer_reset(void)
{
	ppg_ring_reset(&ppg_green_ring);
	ppg_ring_reset(&ppg_red_ring);
	ppg_ring_reset(&ppg_ir_ring);
}

static void ppg_ring_push(struct ppg_ring *ring, uint32_t sample)
{
	ring->samples[ring->head] = sample;
	ring->head = (ring->head + 1U) % OP_PPG_BUFFER_LEN;
	if (ring->count < OP_PPG_BUFFER_LEN) {
		ring->count++;
	}
	ring->sample_index++;
}

static uint32_t ppg_ring_sample_at(const struct ppg_ring *ring, uint16_t chronological_index)
{
	uint16_t idx = (ring->head + OP_PPG_BUFFER_LEN - ring->count +
			chronological_index) % OP_PPG_BUFFER_LEN;

	return ring->samples[idx];
}

static uint32_t ppg_window_sample_limit(uint32_t window_ms)
{
	uint32_t samples;

	if (sampling_hz == 0) {
		return 0;
	}

	samples = (uint32_t)(((uint64_t)sampling_hz * window_ms + 999U) / 1000U);
	if (samples > OP_PPG_BUFFER_LEN) {
		samples = OP_PPG_BUFFER_LEN;
	}

	return samples;
}

static bool ppg_ring_stats_recent(const struct ppg_ring *ring,
				  uint32_t window_ms,
				  struct ppg_channel_stats *stats)
{
	uint32_t sample_limit = ppg_window_sample_limit(window_ms);
	uint16_t start;

	memset(stats, 0, sizeof(*stats));
	stats->min = UINT32_MAX;
	if (ring->count == 0 || sample_limit == 0) {
		return false;
	}

	start = ring->count > sample_limit ? ring->count - sample_limit : 0;
	for (uint16_t n = start; n < ring->count; n++) {
		uint32_t sample = ppg_ring_sample_at(ring, n);
		if (sample < stats->min) {
			stats->min = sample;
		}
		if (sample > stats->max) {
			stats->max = sample;
		}
		stats->sum += sample;
		stats->count++;
	}

	return stats->count > 0 && stats->max > stats->min && stats->sum > 0;
}

static uint16_t median_u16(uint16_t *values, uint8_t count)
{
	uint16_t tmp;

	if (count == 0) {
		return 0;
	}

	for (uint8_t i = 0; i + 1U < count; i++) {
		for (uint8_t j = i + 1U; j < count; j++) {
			if (values[j] < values[i]) {
				tmp = values[i];
				values[i] = values[j];
				values[j] = tmp;
			}
		}
	}

	return values[count / 2U];
}

static void ppg_stats_init(struct ppg_window_stats *stats)
{
	memset(stats, 0, sizeof(*stats));
	stats->green_min = UINT32_MAX;
	stats->red_min = UINT32_MAX;
	stats->ir_min = UINT32_MAX;
}

static void ppg_stats_add_green(struct ppg_window_stats *stats, uint32_t sample)
{
	if (sample < stats->green_min) {
		stats->green_min = sample;
	}
	if (sample > stats->green_max) {
		stats->green_max = sample;
	}
	stats->green_sum += sample;
	stats->green_count++;
}

static void ppg_stats_add_red(struct ppg_window_stats *stats, uint32_t sample)
{
	if (sample < stats->red_min) {
		stats->red_min = sample;
	}
	if (sample > stats->red_max) {
		stats->red_max = sample;
	}
	stats->red_sum += sample;
	stats->red_count++;
}

static void ppg_stats_add_ir(struct ppg_window_stats *stats, uint32_t sample)
{
	if (sample < stats->ir_min) {
		stats->ir_min = sample;
	}
	if (sample > stats->ir_max) {
		stats->ir_max = sample;
	}
	stats->ir_sum += sample;
	stats->ir_count++;
}

static uint8_t optical_calibration_progress(void)
{
	uint32_t initial_progress = 0;
	uint32_t hourly_progress;
	int64_t elapsed_ms;

	if (optical_cal.started_ms <= 0) {
		return 0;
	}

	elapsed_ms = k_uptime_get() - optical_cal.started_ms;
	if (elapsed_ms > 0) {
		initial_progress = (uint32_t)(((uint64_t)elapsed_ms * 30U) /
					      OP_OPTICAL_FIRST_CAL_MS);
		if (initial_progress > 30U) {
			initial_progress = 30U;
		}
	}

	hourly_progress = ((uint32_t)optical_cal.hourly_updates * 70U) /
			  OP_OPTICAL_CAL_FULL_HOURS;
	if (hourly_progress > 70U) {
		hourly_progress = 70U;
	}

	return (uint8_t)min_u32(100U, initial_progress + hourly_progress);
}

static void optical_calibration_commit_hour(uint32_t green_dc,
					    uint32_t green_ac,
					    uint32_t red_dc,
					    uint32_t red_ac,
					    uint32_t ir_dc,
					    uint32_t ir_ac,
					    uint32_t ratio_x1000)
{
	optical_cal.green_dc_ema = ema_u32(optical_cal.green_dc_ema, green_dc, 4);
	optical_cal.green_ac_ema = ema_u32(optical_cal.green_ac_ema, green_ac, 4);
	optical_cal.red_dc_ema = ema_u32(optical_cal.red_dc_ema, red_dc, 4);
	optical_cal.red_ac_ema = ema_u32(optical_cal.red_ac_ema, red_ac, 4);
	optical_cal.ir_dc_ema = ema_u32(optical_cal.ir_dc_ema, ir_dc, 4);
	optical_cal.ir_ac_ema = ema_u32(optical_cal.ir_ac_ema, ir_ac, 4);
	optical_cal.ratio_x1000_ema = ema_u32(optical_cal.ratio_x1000_ema, ratio_x1000, 4);
	if (optical_cal.hourly_updates < OP_OPTICAL_CAL_FULL_HOURS) {
		optical_cal.hourly_updates++;
	}
	LOG_INF("Optical calibration hour %u/%u committed",
		optical_cal.hourly_updates, OP_OPTICAL_CAL_FULL_HOURS);
}

static void update_optical_calibration(struct ppg_window_stats *stats,
				       uint8_t *quality)
{
	uint32_t green_dc = stats_mean(stats->green_sum, stats->green_count);
	uint32_t red_dc = stats_mean(stats->red_sum, stats->red_count);
	uint32_t ir_dc = stats_mean(stats->ir_sum, stats->ir_count);
	uint32_t green_ac = stats_range(stats->green_min, stats->green_max);
	uint32_t red_ac = stats_range(stats->red_min, stats->red_max);
	uint32_t ir_ac = stats_range(stats->ir_min, stats->ir_max);
	bool green_good = stats->green_count >= 8U && green_dc > 0 && green_ac >= 300U;
	bool red_ir_good = stats->red_count >= 8U && stats->ir_count >= 8U &&
			   red_dc > 0 && ir_dc > 0 && red_ac >= 120U && ir_ac >= 120U;
	int64_t now_ms = k_uptime_get();

	if (optical_cal.started_ms == 0) {
		optical_cal.started_ms = now_ms;
		optical_cal.last_hour_update_ms = now_ms;
	}

	if (green_good) {
		optical_cal.green_dc_ema = ema_u32(optical_cal.green_dc_ema, green_dc, 2);
		optical_cal.green_ac_ema = ema_u32(optical_cal.green_ac_ema, green_ac, 3);
	}

	if (red_ir_good) {
		uint32_t ratio_x1000 = (uint32_t)(((uint64_t)red_ac * ir_dc * 1000U) /
						  ((uint64_t)ir_ac * red_dc));
		if (ratio_x1000 >= 250U && ratio_x1000 <= 2200U) {
			optical_cal.ratio_x1000_ema =
				ema_u32(optical_cal.ratio_x1000_ema, ratio_x1000, 2);
			optical_cal.red_dc_ema = ema_u32(optical_cal.red_dc_ema, red_dc, 2);
			optical_cal.red_ac_ema = ema_u32(optical_cal.red_ac_ema, red_ac, 3);
			optical_cal.ir_dc_ema = ema_u32(optical_cal.ir_dc_ema, ir_dc, 2);
			optical_cal.ir_ac_ema = ema_u32(optical_cal.ir_ac_ema, ir_ac, 3);
			stats->ratio_x1000 = ratio_x1000;
		}
	}

	if (green_good && red_ir_good && stats->ratio_x1000 > 0 &&
	    (motion_status != OP_MOTION_STATUS_OK ||
	     (latest_accel_milli_g >= 850 && latest_accel_milli_g <= 1150))) {
		optical_cal.initialized = true;
		optical_cal.hour_green_dc_sum += green_dc;
		optical_cal.hour_green_ac_sum += green_ac;
		optical_cal.hour_red_dc_sum += red_dc;
		optical_cal.hour_red_ac_sum += red_ac;
		optical_cal.hour_ir_dc_sum += ir_dc;
		optical_cal.hour_ir_ac_sum += ir_ac;
		optical_cal.hour_ratio_sum += stats->ratio_x1000;
		optical_cal.hour_good_windows++;
	} else {
		optical_cal.rejected_windows++;
	}

	if (green_ac > 0x78000U || red_ac > 0x78000U || ir_ac > 0x78000U) {
		*quality |= OP_QUALITY_PPG_CLIPPING;
	}

	if (now_ms - optical_cal.last_hour_update_ms >= OP_OPTICAL_CAL_HOUR_MS) {
		if (optical_cal.hour_good_windows >= OP_OPTICAL_MIN_GOOD_HOUR_WINDOWS) {
			optical_calibration_commit_hour(
				(uint32_t)(optical_cal.hour_green_dc_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_green_ac_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_red_dc_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_red_ac_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_ir_dc_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_ir_ac_sum /
					   optical_cal.hour_good_windows),
				(uint32_t)(optical_cal.hour_ratio_sum /
					   optical_cal.hour_good_windows));
		}

		optical_cal.hour_green_dc_sum = 0;
		optical_cal.hour_green_ac_sum = 0;
		optical_cal.hour_red_dc_sum = 0;
		optical_cal.hour_red_ac_sum = 0;
		optical_cal.hour_ir_dc_sum = 0;
		optical_cal.hour_ir_ac_sum = 0;
		optical_cal.hour_ratio_sum = 0;
		optical_cal.hour_good_windows = 0;
		optical_cal.last_hour_update_ms = now_ms;
	}
}

static void compute_hr_from_green(uint8_t *quality)
{
	struct ppg_channel_stats stats;
	uint32_t min_samples;
	uint32_t window_samples;
	uint32_t start;
	uint32_t high_threshold;
	uint32_t low_threshold;
	uint32_t dynamic_range;
	uint32_t learned_min_range;
	uint32_t min_peak_gap_samples;
	uint32_t max_peak_gap_samples;
	uint32_t last_peak_sample = 0;
	uint32_t candidate_sample = 0;
	uint32_t candidate_value = 0;
	uint16_t intervals[96];
	uint16_t clean_intervals[96];
	uint8_t interval_count = 0;
	uint8_t clean_count = 0;
	uint8_t rejected_count = 0;
	uint32_t interval_sum = 0;
	uint16_t median_ibi_ms;
	uint16_t tolerance_ms;
	uint16_t confidence;
	uint16_t new_ibi_ms;
	uint16_t new_hr_x10;
	uint8_t calibration = optical_calibration_progress();
	bool in_peak = false;
	bool have_peak = false;
	int64_t elapsed_ms;
	int64_t now_ms = k_uptime_get();

	if (sampling_hz == 0) {
		hold_hr_value(quality);
		return;
	}

	min_samples = ppg_window_sample_limit(OP_PPG_HR_MIN_WINDOW_MS);
	window_samples = ppg_window_sample_limit(OP_PPG_HR_PROPER_WINDOW_MS);
	if (ppg_green_ring.count < min_samples ||
	    !ppg_ring_stats_recent(&ppg_green_ring, OP_PPG_HR_PROPER_WINDOW_MS, &stats)) {
		hold_hr_value(quality);
		return;
	}

	dynamic_range = stats.max - stats.min;
	learned_min_range = optical_cal.green_ac_ema > 0 ?
			    max_u32(250U, optical_cal.green_ac_ema / 7U) : 450U;
	if (dynamic_range < learned_min_range) {
		hold_hr_value(quality);
		return;
	}
	if (stats.max > 0x7a000U || stats.min < 200U) {
		*quality |= OP_QUALITY_PPG_CLIPPING;
	}

	high_threshold = stats.min + (dynamic_range * 62U) / 100U;
	low_threshold = stats.min + (dynamic_range * 38U) / 100U;
	min_peak_gap_samples = ((uint32_t)sampling_hz * OP_PPG_MIN_IBI_MS) / 1000U;
	max_peak_gap_samples = ((uint32_t)sampling_hz * OP_PPG_MAX_IBI_MS + 999U) / 1000U;
	if (min_peak_gap_samples == 0) {
		min_peak_gap_samples = 1;
	}
	if (window_samples > ppg_green_ring.count) {
		window_samples = ppg_green_ring.count;
	}
	start = ppg_green_ring.count - window_samples;

	for (uint32_t n = start; n < ppg_green_ring.count; n++) {
		uint32_t value = ppg_ring_sample_at(&ppg_green_ring, (uint16_t)n);
		uint32_t sample_number = ppg_green_ring.sample_index -
					 ppg_green_ring.count + n;

		if (!in_peak) {
			if (value >= high_threshold) {
				in_peak = true;
				candidate_sample = sample_number;
				candidate_value = value;
			}
			continue;
		}

		if (value > candidate_value) {
			candidate_sample = sample_number;
			candidate_value = value;
		}

		if (value > low_threshold && n + 1U < ppg_green_ring.count) {
			continue;
		}

		if (have_peak) {
			uint32_t interval_samples = candidate_sample - last_peak_sample;
			if (interval_samples < min_peak_gap_samples) {
				if (candidate_value > stats.min + (dynamic_range * 82U) / 100U) {
					last_peak_sample = candidate_sample;
				}
			} else if (interval_samples <= max_peak_gap_samples) {
				uint32_t ibi_ms = (interval_samples * 1000U +
						   sampling_hz / 2U) / sampling_hz;
				if (interval_count < (sizeof(intervals) / sizeof(intervals[0]))) {
					intervals[interval_count++] = (uint16_t)ibi_ms;
				}
				last_peak_sample = candidate_sample;
			} else {
				last_peak_sample = candidate_sample;
				rejected_count++;
			}
		} else {
			have_peak = true;
			last_peak_sample = candidate_sample;
		}

		in_peak = false;
		candidate_sample = 0;
		candidate_value = 0;
	}

	if (interval_count < 3) {
		hold_hr_value(quality);
		return;
	}

	median_ibi_ms = median_u16(intervals, interval_count);
	if (median_ibi_ms == 0) {
		hold_hr_value(quality);
		return;
	}

	tolerance_ms = max_u32(140U, median_ibi_ms / 4U);
	for (uint8_t i = 0; i < interval_count; i++) {
		uint16_t ibi = intervals[i];
		if (abs_i32((int32_t)ibi - (int32_t)median_ibi_ms) <= tolerance_ms) {
			clean_intervals[clean_count++] = ibi;
			interval_sum += ibi;
		} else {
			rejected_count++;
		}
	}

	if (clean_count < 3) {
		hold_hr_value(quality);
		return;
	}

	new_ibi_ms = (uint16_t)((interval_sum + clean_count / 2U) / clean_count);
	if (new_ibi_ms == 0) {
		new_ibi_ms = median_u16(clean_intervals, clean_count);
	}
	new_hr_x10 = (uint16_t)((600000U + (new_ibi_ms / 2U)) / new_ibi_ms);

	confidence = 8U;
	confidence += (uint16_t)((uint32_t)confidence_ramp(
					 ppg_metrics_started_ms,
					 OP_PPG_HR_CALIBRATION_MS) * 42U / 100U);
	confidence += (uint16_t)min_u32(24U, (uint32_t)clean_count * 3U);
	confidence += (uint16_t)min_u32(14U, (dynamic_range * 14U) /
					     max_u32(learned_min_range, 1U));
	if (interval_count > 0) {
		uint32_t clean_ratio = ((uint32_t)clean_count * 100U) / interval_count;
		confidence += (uint16_t)((clean_ratio * 12U) / 100U);
	}
	confidence += (uint16_t)calibration / 10U;
	if (confidence > 100U) {
		confidence = 100U;
	}

	elapsed_ms = ppg_metrics_started_ms > 0 ? now_ms - ppg_metrics_started_ms : 0;
	if (elapsed_ms < 15000) {
		confidence = min_u32(confidence, 35U);
	} else if (elapsed_ms < 30000) {
		confidence = min_u32(confidence, 55U);
	} else if (elapsed_ms < OP_PPG_HR_PROPER_WINDOW_MS) {
		confidence = min_u32(confidence, 75U);
	}

	if (motion_status == OP_MOTION_STATUS_OK &&
	    (latest_accel_milli_g > 1250 || latest_accel_milli_g < 750)) {
		*quality |= OP_QUALITY_MOTION_ARTIFACT;
		confidence = confidence > 30U ? confidence - 30U : 0U;
	}

	if (latest_hr_x10 != 0 && latest_hr_valid_ms > 0 &&
	    abs_i32((int32_t)new_hr_x10 - (int32_t)latest_hr_x10) > 320U &&
	    confidence < 70U) {
		*quality |= OP_QUALITY_MOTION_ARTIFACT | OP_QUALITY_PPG_UNCALIBRATED;
		optical_cal.rejected_windows++;
		hold_hr_value(quality);
		return;
	}

	if (latest_hr_x10 != 0 && latest_hr_valid_ms > 0) {
		latest_hr_x10 = (uint16_t)(((uint32_t)latest_hr_x10 * 3U +
					    (uint32_t)new_hr_x10 * 2U + 2U) / 5U);
		latest_ibi_ms = (uint16_t)(((uint32_t)latest_ibi_ms * 3U +
					    (uint32_t)new_ibi_ms * 2U + 2U) / 5U);
	} else {
		latest_hr_x10 = new_hr_x10;
		latest_ibi_ms = new_ibi_ms;
	}

	latest_hr_valid_ms = now_ms;
	if (confidence < 80U || elapsed_ms < OP_PPG_HR_PROPER_WINDOW_MS) {
		*quality |= OP_QUALITY_PPG_UNCALIBRATED;
	}
	*quality |= OP_QUALITY_SKIN_CONTACT;
	latest_hr_confidence = (uint8_t)confidence;
	optical_cal.accepted_hr_windows++;
	if (rejected_count > clean_count) {
		*quality |= OP_QUALITY_MOTION_ARTIFACT;
	}
}

static void compute_spo2_from_window(uint8_t *quality)
{
	struct ppg_channel_stats red_stats;
	struct ppg_channel_stats ir_stats;
	uint32_t red_dc;
	uint32_t ir_dc;
	uint32_t red_ac;
	uint32_t ir_ac;
	uint32_t ratio_x1000;
	uint32_t ratio_used_x1000;
	uint32_t profile_weight;
	int32_t spo2;
	uint16_t confidence;
	uint8_t calibration = optical_calibration_progress();
	int64_t elapsed_ms;
	int64_t now_ms = k_uptime_get();

	if (!ppg_ring_stats_recent(&ppg_red_ring, OP_PPG_SPO2_WINDOW_MS, &red_stats) ||
	    !ppg_ring_stats_recent(&ppg_ir_ring, OP_PPG_SPO2_WINDOW_MS, &ir_stats)) {
		hold_spo2_value(quality);
		return;
	}

	if (red_stats.count < ppg_window_sample_limit(OP_PPG_SPO2_MIN_WINDOW_MS) ||
	    ir_stats.count < ppg_window_sample_limit(OP_PPG_SPO2_MIN_WINDOW_MS)) {
		hold_spo2_value(quality);
		return;
	}

	red_dc = (uint32_t)(red_stats.sum / red_stats.count);
	ir_dc = (uint32_t)(ir_stats.sum / ir_stats.count);
	red_ac = red_stats.max > red_stats.min ? red_stats.max - red_stats.min : 0;
	ir_ac = ir_stats.max > ir_stats.min ? ir_stats.max - ir_stats.min : 0;

	if (red_dc == 0 || ir_dc == 0 || red_ac < 200U || ir_ac < 200U) {
		hold_spo2_value(quality);
		return;
	}

	ratio_x1000 = (uint32_t)(((uint64_t)red_ac * ir_dc * 1000U) /
				 ((uint64_t)ir_ac * red_dc));
	if (ratio_x1000 < 250U || ratio_x1000 > 2200U) {
		hold_spo2_value(quality);
		return;
	}

	confidence = 15U + (uint16_t)((uint32_t)confidence_ramp(
					      ppg_metrics_started_ms,
					      OP_PPG_SPO2_CALIBRATION_MS) * 20U / 100U);
	confidence += (uint16_t)((uint32_t)calibration * 45U / 100U);
	if (red_stats.count > sampling_hz * 6U && ir_stats.count > sampling_hz * 6U) {
		confidence += 12U;
	}
	if (red_stats.count > sampling_hz * 12U && ir_stats.count > sampling_hz * 12U) {
		confidence += 8U;
	}
	if (motion_status == OP_MOTION_STATUS_OK &&
	    (latest_accel_milli_g > 1150 || latest_accel_milli_g < 850)) {
		*quality |= OP_QUALITY_MOTION_ARTIFACT;
		confidence = confidence > 25U ? confidence - 25U : 0U;
	}

	if (spo2_ratio_filtered_x1000 != 0 &&
	    abs_i32((int32_t)ratio_x1000 - (int32_t)spo2_ratio_filtered_x1000) > 450U &&
	    confidence < 80U) {
		*quality |= OP_QUALITY_MOTION_ARTIFACT | OP_QUALITY_PPG_UNCALIBRATED;
		optical_cal.rejected_windows++;
		hold_spo2_value(quality);
		return;
	}

	if (spo2_ratio_filtered_x1000 == 0) {
		spo2_ratio_filtered_x1000 = ratio_x1000;
	} else {
		spo2_ratio_filtered_x1000 =
			ema_u32(spo2_ratio_filtered_x1000, ratio_x1000,
				calibration >= 50U ? 4U : 7U);
	}

	profile_weight = min_u32(25U, (uint32_t)optical_cal.hourly_updates);
	if (optical_cal.ratio_x1000_ema > 0 && profile_weight > 0) {
		ratio_used_x1000 =
			(uint32_t)(((uint64_t)spo2_ratio_filtered_x1000 *
				    (100U - profile_weight) +
				    (uint64_t)optical_cal.ratio_x1000_ema *
				    profile_weight) / 100U);
	} else {
		ratio_used_x1000 = spo2_ratio_filtered_x1000;
	}

	spo2 = 110 - (int32_t)((25U * ratio_used_x1000 + 500U) / 1000U);
	if (spo2 > 100) {
		spo2 = 100;
	}
	if (spo2 < 70) {
		spo2 = 70;
	}

	if (confidence > 95U) {
		confidence = 95U;
	}

	elapsed_ms = ppg_metrics_started_ms > 0 ? now_ms - ppg_metrics_started_ms : 0;
	if (elapsed_ms < 30000) {
		confidence = min_u32(confidence, 45U);
	} else if (elapsed_ms < OP_PPG_HR_PROPER_WINDOW_MS) {
		confidence = min_u32(confidence, 70U);
	}

	latest_spo2_percent = (uint8_t)spo2;
	latest_spo2_confidence = (uint8_t)confidence;
	latest_spo2_valid_ms = now_ms;
	optical_cal.accepted_spo2_windows++;
	if (confidence < 90U || calibration < 100U ||
	    elapsed_ms < OP_PPG_HR_PROPER_WINDOW_MS) {
		*quality |= OP_QUALITY_PPG_UNCALIBRATED;
	}
}

static void update_optical_metrics(uint8_t *quality)
{
	uint8_t payload[OP_RAW_MAX_PAYLOAD_BYTES];
	uint8_t payload_len = 0;
	struct ppg_window_stats stats;
	uint8_t sensor_status;

	ppg_stats_init(&stats);
	sensor_status = prepare_maxm86161();
	update_puck_status(sensor_status);
	if (sensor_status != OP_SENSOR_STATUS_OK) {
		*quality |= OP_QUALITY_PUCK_CHANGED;
		latest_hr_x10 = 0;
		latest_ibi_ms = 0;
		latest_spo2_percent = 0xff;
		latest_hr_confidence = 0;
		latest_spo2_confidence = 0;
		latest_metric_calibration = 0;
		return;
	}

	if (ppg_metrics_started_ms == 0) {
		ppg_metrics_started_ms = k_uptime_get();
		ppg_buffer_reset();
	}

	if (read_maxm86161_fifo_payload(payload, sizeof(payload), &payload_len)) {
		hold_hr_value(quality);
		hold_spo2_value(quality);
		return;
	}

	for (uint8_t i = 0; i + 2U < payload_len; i += MAXM86161_FIFO_ITEM_BYTES) {
		uint8_t tag = payload[i] >> 3;
		uint32_t sample = ((uint32_t)(payload[i] & 0x07U) << 16) |
				  ((uint32_t)payload[i + 1U] << 8) |
				  payload[i + 2U];

		switch (tag) {
		case 1:
			ppg_stats_add_green(&stats, sample);
			ppg_ring_push(&ppg_green_ring, sample);
			break;
		case 2:
			ppg_stats_add_ir(&stats, sample);
			ppg_ring_push(&ppg_ir_ring, sample);
			break;
		case 3:
			ppg_stats_add_red(&stats, sample);
			ppg_ring_push(&ppg_red_ring, sample);
			break;
		default:
			break;
		}
	}

	update_optical_calibration(&stats, quality);
	compute_hr_from_green(quality);
	compute_spo2_from_window(quality);
	latest_metric_calibration = optical_calibration_progress();
}

static int read_maxm86161_fifo_payload(uint8_t *payload,
				       uint8_t max_payload_len,
				       uint8_t *payload_len)
{
#if OPENPULSE_HAS_I2C
	uint8_t overflow_count = 0;
	uint8_t fifo_count = 0;
	uint8_t item_count;
	uint8_t max_items = max_payload_len / MAXM86161_FIFO_ITEM_BYTES;
	int err;

	*payload_len = 0;
	if (active_ppg_i2c == NULL) {
		return -ENODEV;
	}

	if (max_items == 0) {
		return 0;
	}

	err = maxm86161_read_reg(MAXM86161_REG_OVERFLOW_COUNTER, &overflow_count);
	if (err) {
		return err;
	}

	err = maxm86161_read_reg(MAXM86161_REG_FIFO_DATA_COUNT, &fifo_count);
	if (err) {
		return err;
	}

	item_count = overflow_count > 0 ? 128 : fifo_count;
	if (item_count > max_items) {
		item_count = max_items;
	}

	for (uint8_t i = 0; i < item_count; i++) {
		err = i2c_burst_read(active_ppg_i2c, MAXM86161_I2C_ADDR,
				     MAXM86161_REG_FIFO_DATA,
				     &payload[i * MAXM86161_FIFO_ITEM_BYTES],
				     MAXM86161_FIFO_ITEM_BYTES);
		if (err) {
			*payload_len = i * MAXM86161_FIFO_ITEM_BYTES;
			return err;
		}
	}

	*payload_len = item_count * MAXM86161_FIFO_ITEM_BYTES;
	return 0;
#else
	ARG_UNUSED(payload);
	ARG_UNUSED(max_payload_len);
	*payload_len = 0;
	return -ENODEV;
#endif
}

static void send_raw_window_from_fifo(uint16_t seconds, uint8_t status)
{
	uint8_t payload[OP_RAW_MAX_PAYLOAD_BYTES];
	uint8_t payload_len = 0;
	int err;

	if (status != OP_SENSOR_STATUS_OK) {
		send_raw_frame(seconds, status, NULL, 0);
		return;
	}

	err = read_maxm86161_fifo_payload(payload, sizeof(payload), &payload_len);
	if (err) {
		LOG_WRN("MAXM86161 FIFO read failed: %d", err);
		send_raw_frame(seconds, OP_SENSOR_STATUS_UNAVAILABLE, payload, payload_len);
		return;
	}

	send_raw_frame(seconds, OP_SENSOR_STATUS_OK, payload, payload_len);
}

static uint32_t isqrt_u64(uint64_t value)
{
	uint64_t root = 0;
	uint64_t bit = 1ULL << 62;

	while (bit > value) {
		bit >>= 2;
	}

	while (bit != 0) {
		if (value >= root + bit) {
			value -= root + bit;
			root = (root >> 1) + bit;
		} else {
			root >>= 1;
		}
		bit >>= 2;
	}

	return root > UINT32_MAX ? UINT32_MAX : (uint32_t)root;
}

static int32_t sensor_value_to_milli_g(const struct sensor_value *value)
{
	int64_t micro_ms2 = ((int64_t)value->val1 * 1000000LL) + value->val2;

	return (int32_t)((micro_ms2 * 1000LL) / 9806650LL);
}

static int lsm6dsl_write_reg(uint8_t reg, uint8_t value)
{
#if OPENPULSE_HAS_IMU
	return i2c_reg_write_byte(DEVICE_DT_GET(DT_BUS(DT_NODELABEL(lsm6ds3tr_c))),
				  LSM6DSL_I2C_ADDR, reg, value);
#else
	ARG_UNUSED(reg);
	ARG_UNUSED(value);
	return -ENODEV;
#endif
}

static int lsm6dsl_read_reg(uint8_t reg, uint8_t *value)
{
#if OPENPULSE_HAS_IMU
	return i2c_reg_read_byte(DEVICE_DT_GET(DT_BUS(DT_NODELABEL(lsm6ds3tr_c))),
				 LSM6DSL_I2C_ADDR, reg, value);
#else
	ARG_UNUSED(reg);
	ARG_UNUSED(value);
	return -ENODEV;
#endif
}

static int configure_lsm6dsl_pedometer(void)
{
#if OPENPULSE_HAS_IMU
	uint8_t ctrl10;
	int err;

	err = lsm6dsl_read_reg(LSM6DSL_REG_CTRL10_C, &ctrl10);
	if (err) {
		return err;
	}

	ctrl10 |= LSM6DSL_CTRL10_C_FUNC_EN | LSM6DSL_CTRL10_C_PEDO_EN;
	ctrl10 |= LSM6DSL_CTRL10_C_PEDO_RST_STEP;
	err = lsm6dsl_write_reg(LSM6DSL_REG_CTRL10_C, ctrl10);
	if (err) {
		return err;
	}

	k_sleep(K_MSEC(5));
	ctrl10 &= ~LSM6DSL_CTRL10_C_PEDO_RST_STEP;
	err = lsm6dsl_write_reg(LSM6DSL_REG_CTRL10_C, ctrl10);
	if (err) {
		return err;
	}

	step_count = 0;
	lsm6dsl_step_baseline_ready = false;
	lsm6dsl_last_step_counter = 0;
	lsm6dsl_pedometer_ready = true;

	return 0;
#else
	return -ENODEV;
#endif
}

static int read_lsm6dsl_step_counter(uint16_t *counter)
{
#if OPENPULSE_HAS_IMU
	uint8_t raw[2];
	int err;

	err = i2c_burst_read(DEVICE_DT_GET(DT_BUS(DT_NODELABEL(lsm6ds3tr_c))),
			     LSM6DSL_I2C_ADDR,
			     LSM6DSL_REG_STEP_COUNTER_L,
			     raw,
			     sizeof(raw));
	if (err) {
		return err;
	}

	*counter = sys_get_le16(raw);
	return 0;
#else
	ARG_UNUSED(counter);
	return -ENODEV;
#endif
}

static void update_steps_from_lsm6dsl(void)
{
	uint16_t hardware_steps;

	if (!lsm6dsl_pedometer_ready || read_lsm6dsl_step_counter(&hardware_steps)) {
		motion_status = OP_MOTION_STATUS_PEDOMETER_UNAVAILABLE;
		return;
	}

	if (!lsm6dsl_step_baseline_ready) {
		lsm6dsl_last_step_counter = hardware_steps;
		lsm6dsl_step_baseline_ready = true;
		motion_status = OP_MOTION_STATUS_OK;
		return;
	}

	step_count += (uint16_t)(hardware_steps - lsm6dsl_last_step_counter);
	lsm6dsl_last_step_counter = hardware_steps;
	motion_status = OP_MOTION_STATUS_OK;
}

static void configure_motion_sensor(void)
{
#if OPENPULSE_HAS_IMU
	struct sensor_value odr = {
		.val1 = 26,
		.val2 = 0,
	};
	int err;

	if (!device_is_ready(imu_dev)) {
		LOG_WRN("LSM6DSL accelerometer is not ready");
		imu_ready = false;
		motion_status = OP_MOTION_STATUS_UNAVAILABLE;
		return;
	}

	err = sensor_attr_set(imu_dev, SENSOR_CHAN_ACCEL_XYZ,
			      SENSOR_ATTR_SAMPLING_FREQUENCY, &odr);
	if (err) {
		LOG_WRN("LSM6DSL accelerometer ODR setup failed: %d", err);
	}

	imu_ready = true;
	if (configure_lsm6dsl_pedometer()) {
		motion_status = OP_MOTION_STATUS_PEDOMETER_UNAVAILABLE;
		LOG_WRN("LSM6DSL hardware pedometer setup failed");
	} else {
		motion_status = OP_MOTION_STATUS_OK;
		LOG_INF("LSM6DSL hardware pedometer ready for steps");
	}
#else
	imu_ready = false;
	motion_status = OP_MOTION_STATUS_UNAVAILABLE;
#endif
}

static void sample_motion(void)
{
#if OPENPULSE_HAS_IMU
	struct sensor_value accel[3];
	int32_t x_mg;
	int32_t y_mg;
	int32_t z_mg;
	int64_t x;
	int64_t y;
	int64_t z;
	uint64_t magnitude_sq;
	uint32_t magnitude_mg;

	if (!imu_ready) {
		motion_status = OP_MOTION_STATUS_UNAVAILABLE;
		latest_accel_milli_g = 0;
		return;
	}

	if (sensor_sample_fetch_chan(imu_dev, SENSOR_CHAN_ACCEL_XYZ) ||
	    sensor_channel_get(imu_dev, SENSOR_CHAN_ACCEL_X, &accel[0]) ||
	    sensor_channel_get(imu_dev, SENSOR_CHAN_ACCEL_Y, &accel[1]) ||
	    sensor_channel_get(imu_dev, SENSOR_CHAN_ACCEL_Z, &accel[2])) {
		motion_status = OP_MOTION_STATUS_UNAVAILABLE;
		latest_accel_milli_g = 0;
		return;
	}

	x_mg = sensor_value_to_milli_g(&accel[0]);
	y_mg = sensor_value_to_milli_g(&accel[1]);
	z_mg = sensor_value_to_milli_g(&accel[2]);
	x = x_mg;
	y = y_mg;
	z = z_mg;
	magnitude_sq = (uint64_t)((x * x) + (y * y) + (z * z));
	magnitude_mg = isqrt_u64(magnitude_sq);
	if (magnitude_mg > INT16_MAX) {
		magnitude_mg = INT16_MAX;
	}

	latest_accel_milli_g = (int16_t)magnitude_mg;
	update_steps_from_lsm6dsl();
#else
	motion_status = OP_MOTION_STATUS_UNAVAILABLE;
	latest_accel_milli_g = 0;
#endif
}

static uint8_t battery_soc_from_mv(int32_t mv)
{
	if (mv >= 4200) {
		return 100;
	}
	if (mv <= 3300) {
		return 0;
	}

	return (uint8_t)(((mv - 3300) * 100) / 900);
}

static void read_battery(void)
{
#if OPENPULSE_HAS_ADC
	int16_t sample = 0;
	struct adc_sequence sequence = {
		.buffer = &sample,
		.buffer_size = sizeof(sample),
	};
	int err;
	int32_t mv;

	if (!battery_adc_ready || !adc_is_ready_dt(&vbat_adc)) {
		battery_level = 0xff;
		battery_level_known = false;
		return;
	}

	(void)adc_sequence_init_dt(&vbat_adc, &sequence);
	err = adc_read_dt(&vbat_adc, &sequence);
	if (err) {
		LOG_WRN("Battery ADC read failed: %d", err);
		battery_level = 0xff;
		battery_level_known = false;
		return;
	}

	mv = sample;
	err = adc_raw_to_millivolts_dt(&vbat_adc, &mv);
	if (err) {
		LOG_WRN("Battery ADC conversion failed: %d", err);
		battery_level = 0xff;
		battery_level_known = false;
		return;
	}

	mv = (mv * OP_BATTERY_DIVIDER_NUM) / OP_BATTERY_DIVIDER_DEN;
	battery_level = battery_soc_from_mv(mv);
	battery_level_known = true;
#else
	battery_level = 0xff;
	battery_level_known = false;
#endif
}

static void update_puck_status(uint8_t sensor_status)
{
	bool attached = (sensor_status == OP_SENSOR_STATUS_OK);
	uint8_t event_type = attached ? OP_EVENT_ATTACHED : OP_EVENT_FAULT;

	if (!attached && last_puck_status[2]) {
		event_type = OP_EVENT_REMOVED;
	}

	last_puck_status[0] = event_type;
	last_puck_status[1] = OP_PUCK_KIND_PPG;
	last_puck_status[2] = attached ? 1 : 0;
	last_puck_status[3] = sensor_status;
}

static int notify_puck_status(void)
{
	if (!puck_notify_enabled || !current_conn) {
		return 0;
	}

	return bt_gatt_notify(current_conn, &openpulse_svc.attrs[14],
			      last_puck_status, sizeof(last_puck_status));
}

static void sensor_work_handler(struct k_work *work)
{
	uint8_t previous_attached = last_puck_status[2];

	read_battery();
	update_puck_status(probe_maxm86161());

	if (previous_attached != last_puck_status[2]) {
		last_puck_status[0] = last_puck_status[2] ? OP_EVENT_ATTACHED : OP_EVENT_REMOVED;
	}

	(void)notify_battery();
	(void)notify_puck_status();

	k_work_reschedule(&sensor_work, K_SECONDS(5));
}

static void motion_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	sample_motion();
	k_work_reschedule(&motion_work, K_MSEC(100));
}

static void raw_window_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	send_raw_window_from_fifo(pending_raw_seconds, pending_raw_sensor_status);
}

static void advertising_work_handler(struct k_work *work)
{
	int err;

	ARG_UNUSED(work);

	if (!current_conn) {
		err = start_advertising();
		if (err == 0) {
			LOG_INF("Advertising as OpenPulse");
		} else if (err != -EALREADY) {
			LOG_WRN("BLE advertising retry failed: %d", err);
		}
	}

	k_work_reschedule(&advertising_work, K_SECONDS(3));
}

static void stream_work_handler(struct k_work *work)
{
	uint8_t frame[4 + OP_LIVE_RECORD_METRICS_LEN];
	uint8_t quality = 0;
	int64_t now_ms;

	if (!current_conn || !live_notify_enabled || !time_synced || current_mode == OP_MODE_SHIP) {
		return;
	}

	now_ms = k_uptime_get();
	sample_motion();
	update_optical_metrics(&quality);

	if (last_live_notification_ms > 0 &&
	    now_ms - last_live_notification_ms < OP_LIVE_NOTIFY_MS) {
		k_work_reschedule(&stream_work, K_MSEC(OP_PPG_POLL_MS));
		return;
	}

	if (last_puck_status[2]) {
		quality |= OP_QUALITY_SKIN_CONTACT;
	} else {
		quality |= OP_QUALITY_PUCK_CHANGED;
	}

	if (battery_level_known && battery_level <= 10) {
		quality |= OP_QUALITY_BATTERY_LOW;
	}

	frame[0] = OP_FRAME_LIVE;
	frame[1] = 1;
	sys_put_le16(live_sequence++, &frame[2]);
	sys_put_le32(1000, &frame[4]);
	sys_put_le16(latest_hr_x10, &frame[8]);
	sys_put_le16(latest_ibi_ms, &frame[10]);
	sys_put_le16((uint16_t)latest_accel_milli_g, &frame[12]);
	frame[14] = latest_spo2_percent;
	frame[15] = quality;
	sys_put_le32(step_count, &frame[16]);
	frame[20] = motion_status;
	frame[21] = latest_hr_confidence;
	frame[22] = latest_spo2_confidence;
	frame[23] = latest_metric_calibration;

	(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[5], frame, sizeof(frame));

	last_live_notification_ms = now_ms;
	k_work_reschedule(&stream_work, K_MSEC(OP_PPG_POLL_MS));
}

static void connected(struct bt_conn *conn, uint8_t err)
{
	if (err) {
		LOG_ERR("BLE connection failed: %u", err);
		err = start_advertising();
		if (err && err != -EALREADY) {
			LOG_ERR("BLE advertising restart after failed connection failed: %d", err);
		}
		return;
	}

	current_conn = bt_conn_ref(conn);
	time_synced = false;
	last_app_activity_ms = k_uptime_get();
	LOG_INF("BLE connected");
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	int err;

	LOG_INF("BLE disconnected: 0x%02x", reason);

	k_work_cancel_delayable(&stream_work);
	k_work_cancel_delayable(&raw_window_work);
	control_notify_enabled = false;
	live_notify_enabled = false;
	bulk_notify_enabled = false;
	raw_notify_enabled = false;
	puck_notify_enabled = false;
	battery_notify_enabled = false;
	time_synced = false;
	last_app_activity_ms = 0;
	stop_maxm86161();

	if (current_conn) {
		bt_conn_unref(current_conn);
		current_conn = NULL;
	}

	err = start_advertising();
	if (err && err != -EALREADY) {
		LOG_ERR("BLE advertising restart failed: %d", err);
	} else {
		LOG_INF("Advertising as OpenPulse");
	}
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = connected,
	.disconnected = disconnected,
};

static int start_advertising(void)
{
	static const struct bt_data ad[] = {
		BT_DATA(BT_DATA_FLAGS, adv_flags, sizeof(adv_flags)),
		BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME,
			sizeof(CONFIG_BT_DEVICE_NAME) - 1),
	};
	static const struct bt_data sd[] = {
		BT_DATA(BT_DATA_UUID128_ALL, adv_openpulse_service,
			sizeof(adv_openpulse_service)),
	};

	return bt_le_adv_start(BT_LE_ADV_CONN_FAST_2, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
}

int main(void)
{
	int err;

	LOG_INF("OpenPulse firmware starting");

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), battery_enable_gpios)
	if (device_is_ready(battery_enable.port)) {
		(void)gpio_pin_configure_dt(&battery_enable, GPIO_OUTPUT_ACTIVE);
	}
#endif

#if OPENPULSE_HAS_ADC
	if (adc_is_ready_dt(&vbat_adc)) {
		err = adc_channel_setup_dt(&vbat_adc);
		if (err) {
			LOG_WRN("Battery ADC setup failed: %d", err);
		} else {
			battery_adc_ready = true;
		}
	}
#endif

	configure_motion_sensor();
	sample_motion();
	read_battery();
	update_puck_status(probe_maxm86161());

	err = bt_enable(NULL);
	if (err) {
		LOG_ERR("Bluetooth init failed: %d", err);
		return 0;
	}

	err = start_advertising();
	if (err && err != -EALREADY) {
		LOG_ERR("BLE advertising failed: %d", err);
	} else {
		LOG_INF("Advertising as OpenPulse");
	}

	k_work_schedule(&sensor_work, K_NO_WAIT);
	k_work_schedule(&motion_work, K_MSEC(100));
	k_work_schedule(&advertising_work, K_SECONDS(3));

	return 0;
}
