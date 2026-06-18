#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/reboot.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/uuid.h>
#include <string.h>

LOG_MODULE_REGISTER(openpulse, LOG_LEVEL_INF);

#define OPENPULSE_FW_VERSION "0.1.0-real-ble"
#define OPENPULSE_HW_VERSION "xiao_ble/nrf52840/sense"

#define MAXM86161_I2C_ADDR 0x62
#define MAXM86161_REG_PART_ID 0xff
#define MAXM86161_EXPECTED_PART_ID 0x36

#define OP_FRAME_LIVE 0x10
#define OP_FRAME_BACKFILL 0x20
#define OP_RECORD_KIND_GAP_MARKER 4

#define OP_EVENT_ATTACHED 1
#define OP_EVENT_REMOVED 2
#define OP_EVENT_FAULT 5
#define OP_PUCK_KIND_PPG 1
#define OP_SENSOR_STATUS_OK 0
#define OP_SENSOR_STATUS_UNAVAILABLE 1
#define OP_SENSOR_STATUS_I2C_NOT_READY 2
#define OP_SENSOR_STATUS_UNEXPECTED_PART_ID 3

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
static enum op_mode current_mode = OP_MODE_STANDBY;
static uint16_t live_sequence;
static uint16_t bulk_sequence;
static uint16_t raw_sequence;
static uint16_t sampling_hz = 25;
static uint8_t led_green_ma = 8;
static uint8_t led_red_ma = 0;
static uint8_t led_ir_ma = 0;

static uint8_t battery_level = 0xff;
static bool battery_level_known;
static uint8_t last_puck_status[4] = {
	OP_EVENT_REMOVED,
	OP_PUCK_KIND_PPG,
	0,
	OP_SENSOR_STATUS_UNAVAILABLE,
};

extern const struct bt_gatt_service_static openpulse_svc;

static void stream_work_handler(struct k_work *work);
static void sensor_work_handler(struct k_work *work);
static K_WORK_DELAYABLE_DEFINE(stream_work, stream_work_handler);
static K_WORK_DELAYABLE_DEFINE(sensor_work, sensor_work_handler);

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

static ssize_t read_battery_level(struct bt_conn *conn,
				  const struct bt_gatt_attr *attr,
				  void *buf,
				  uint16_t len,
				  uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, &battery_level, sizeof(battery_level));
}

static void battery_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
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

static int notify_puck_status(void);

static ssize_t read_control(struct bt_conn *conn,
			    const struct bt_gatt_attr *attr,
			    void *buf,
			    uint16_t len,
			    uint16_t offset)
{
	uint8_t status[12];

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

static void send_raw_unavailable(uint16_t seconds)
{
	uint8_t frame[8];

	frame[0] = 0x30;
	sys_put_le16(raw_sequence++, &frame[1]);
	sys_put_le16(seconds, &frame[3]);
	frame[5] = last_puck_status[2];
	frame[6] = last_puck_status[3];
	frame[7] = 0;

	if (raw_notify_enabled && current_conn) {
		(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[11], frame, sizeof(frame));
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
		notify_control_ack(command, 0);
		break;
	case 0x04:
		if (payload_len != 3) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
		}
		led_green_ma = payload[0];
		led_red_ma = payload[1];
		led_ir_ma = payload[2];
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
		send_raw_unavailable(sys_get_le16(payload));
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
	return bt_gatt_attr_read(conn, attr, buf, len, offset, last_puck_status, sizeof(last_puck_status));
}

static void control_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	control_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void live_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	live_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
	if (live_notify_enabled && time_synced) {
		k_work_reschedule(&stream_work, K_NO_WAIT);
	}
}

static void bulk_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	bulk_notify_enabled = (value == BT_GATT_CCC_NOTIFY || value == BT_GATT_CCC_INDICATE);
}

static void raw_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	raw_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void puck_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
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
#define OPENPULSE_HAS_I2C 1
static const struct device *const ppg_i2c = DEVICE_DT_GET(DT_NODELABEL(i2c0));
#else
#define OPENPULSE_HAS_I2C 0
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

	if (!adc_is_ready_dt(&vbat_adc)) {
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

static uint8_t probe_maxm86161(void)
{
#if OPENPULSE_HAS_I2C
	uint8_t part_id = 0;
	int err;

	if (!device_is_ready(ppg_i2c)) {
		return OP_SENSOR_STATUS_I2C_NOT_READY;
	}

	err = i2c_reg_read_byte(ppg_i2c, MAXM86161_I2C_ADDR, MAXM86161_REG_PART_ID, &part_id);
	if (err) {
		LOG_WRN("MAXM86161 probe failed: %d", err);
		return OP_SENSOR_STATUS_UNAVAILABLE;
	}

	if (part_id != MAXM86161_EXPECTED_PART_ID) {
		LOG_WRN("MAXM86161 unexpected part id: 0x%02x", part_id);
		return OP_SENSOR_STATUS_UNEXPECTED_PART_ID;
	}

	return OP_SENSOR_STATUS_OK;
#else
	return OP_SENSOR_STATUS_I2C_NOT_READY;
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

static void stream_work_handler(struct k_work *work)
{
	uint8_t frame[16];
	uint8_t quality = 0;

	if (!current_conn || !live_notify_enabled || !time_synced || current_mode == OP_MODE_SHIP) {
		return;
	}

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
	sys_put_le16(0, &frame[12]);
	frame[14] = 0xff;
	frame[15] = quality;

	(void)bt_gatt_notify(current_conn, &openpulse_svc.attrs[5], frame, sizeof(frame));

	k_work_reschedule(&stream_work, K_SECONDS(1));
}

static void connected(struct bt_conn *conn, uint8_t err)
{
	if (err) {
		LOG_ERR("BLE connection failed: %u", err);
		return;
	}

	current_conn = bt_conn_ref(conn);
	time_synced = false;
	LOG_INF("BLE connected");
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	LOG_INF("BLE disconnected: 0x%02x", reason);

	k_work_cancel_delayable(&stream_work);

	if (current_conn) {
		bt_conn_unref(current_conn);
		current_conn = NULL;
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
		}
	}
#endif

	read_battery();
	update_puck_status(probe_maxm86161());

	err = bt_enable(NULL);
	if (err) {
		LOG_ERR("Bluetooth init failed: %d", err);
		return 0;
	}

	err = start_advertising();
	if (err) {
		LOG_ERR("BLE advertising failed: %d", err);
		return 0;
	}

	LOG_INF("Advertising as OpenPulse");
	k_work_schedule(&sensor_work, K_NO_WAIT);

	return 0;
}
