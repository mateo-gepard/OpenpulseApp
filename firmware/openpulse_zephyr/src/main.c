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

#define OPENPULSE_FW_VERSION "0.1.0-real-ble"
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

#define OP_FRAME_LIVE 0x10
#define OP_FRAME_BACKFILL 0x20
#define OP_FRAME_RAW_PPG 0x30
#define OP_RECORD_KIND_GAP_MARKER 4
#define OP_LIVE_RECORD_BASE_LEN 12
#define OP_LIVE_RECORD_ACTIVITY_LEN 17
#define OP_RAW_FRAME_HEADER_LEN 8
#define OP_RAW_MAX_PAYLOAD_BYTES 12

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
#define OP_STEP_ARM_THRESHOLD_MG 90
#define OP_STEP_TRIGGER_THRESHOLD_MG 180
#define OP_STEP_REFRACTORY_MS 300

#define OP_QUALITY_SKIN_CONTACT BIT(0)
#define OP_QUALITY_LOW_PERFUSION BIT(2)
#define OP_QUALITY_PUCK_CHANGED BIT(3)
#define OP_QUALITY_BATTERY_LOW BIT(4)

enum op_mode {
	OP_MODE_STANDBY = 0,
	OP_MODE_ACTIVE = 1,
	OP_MODE_LOW_POWER = 2,
	OP_MODE_HR_ONLY = 3,
	OP_MODE_SHIP = 4,
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
static int64_t connected_at_ms;
static int64_t last_app_activity_ms;
static bool stale_connection_disconnect_requested;
static enum op_mode current_mode = OP_MODE_STANDBY;
static uint16_t live_sequence;
static uint16_t bulk_sequence;
static uint16_t raw_sequence;
static uint16_t sampling_hz = 25;
static uint8_t led_green_ma = 8;
static uint8_t led_red_ma = 4;
static uint8_t led_ir_ma = 4;
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
static bool step_peak_armed = true;
static int64_t last_step_ms;

static uint8_t battery_level = 0xff;
static bool battery_level_known;
static bool battery_adc_ready;
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
static uint8_t prepare_maxm86161(void);

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
		pending_raw_sensor_status = prepare_maxm86161();
		if (pending_raw_sensor_status == OP_SENSOR_STATUS_OK) {
			k_work_reschedule(&raw_window_work, K_MSEC(750));
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
		k_work_reschedule(&stream_work, K_NO_WAIT);
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

static void update_steps_from_accel(int16_t accel_milli_g)
{
	int32_t dynamic_mg = accel_milli_g >= 1000 ?
			    accel_milli_g - 1000 : 1000 - accel_milli_g;
	int64_t now_ms = k_uptime_get();

	if (dynamic_mg < OP_STEP_ARM_THRESHOLD_MG) {
		step_peak_armed = true;
	}

	if (step_peak_armed &&
	    dynamic_mg > OP_STEP_TRIGGER_THRESHOLD_MG &&
	    now_ms - last_step_ms > OP_STEP_REFRACTORY_MS) {
		step_count++;
		last_step_ms = now_ms;
		step_peak_armed = false;
	}
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
	motion_status = OP_MOTION_STATUS_OK;
	LOG_INF("LSM6DSL accelerometer ready for steps");
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
	motion_status = OP_MOTION_STATUS_OK;
	update_steps_from_accel(latest_accel_milli_g);
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
	update_puck_status(prepare_maxm86161());

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

	if (current_conn) {
		if (connected_at_ms > 0 &&
		    last_app_activity_ms > 0 &&
		    k_uptime_get() - last_app_activity_ms > 20000 &&
		    !stale_connection_disconnect_requested) {
			stale_connection_disconnect_requested = true;
			LOG_WRN("BLE connection has no recent app activity; disconnecting");
			(void)bt_conn_disconnect(current_conn, BT_HCI_ERR_REMOTE_USER_TERM_CONN);
		}
	} else {
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
	uint8_t frame[4 + OP_LIVE_RECORD_ACTIVITY_LEN];
	uint8_t quality = 0;

	if (!current_conn || !live_notify_enabled || !time_synced || current_mode == OP_MODE_SHIP) {
		return;
	}

	sample_motion();

	if (last_puck_status[2]) {
		quality |= OP_QUALITY_LOW_PERFUSION;
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
	sys_put_le16(0, &frame[8]);
	sys_put_le16(0, &frame[10]);
	sys_put_le16((uint16_t)latest_accel_milli_g, &frame[12]);
	frame[14] = 0xff;
	frame[15] = quality;
	sys_put_le32(step_count, &frame[16]);
	frame[20] = motion_status;

	(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[5], frame, sizeof(frame));

	k_work_reschedule(&stream_work, K_SECONDS(1));
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
	connected_at_ms = k_uptime_get();
	last_app_activity_ms = connected_at_ms;
	stale_connection_disconnect_requested = false;
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
	connected_at_ms = 0;
	last_app_activity_ms = 0;
	stale_connection_disconnect_requested = false;

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
	update_puck_status(prepare_maxm86161());

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
