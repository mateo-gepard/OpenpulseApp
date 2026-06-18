# OpenPulse BLE Contract

This is the initial shared contract for the mobile app and Zephyr firmware.

All multi-byte numeric fields are little-endian. Timestamps use `device_uptime_ms` on the device and are mapped to wall time by the app after time sync.

## Standard Services

| Service | UUID | Characteristic | Properties |
|---|---:|---|---|
| Device Information | `0x180A` | Firmware, hardware, serial | Read |
| Battery | `0x180F` | Battery Level | Read, Notify |

## OpenPulse Custom Service

Base UUID:

```text
f04d0000-57f5-4f5a-9b80-4f6f2f1d0001
```

Characteristics:

| Name | UUID | Properties |
|---|---|---|
| Control | `f04d0001-57f5-4f5a-9b80-4f6f2f1d0001` | Read, Write, Notify |
| Live Stream | `f04d0002-57f5-4f5a-9b80-4f6f2f1d0001` | Notify |
| Bulk Backfill | `f04d0003-57f5-4f5a-9b80-4f6f2f1d0001` | Notify, Indicate |
| Raw PPG | `f04d0004-57f5-4f5a-9b80-4f6f2f1d0001` | Notify |
| Puck Status | `f04d0005-57f5-4f5a-9b80-4f6f2f1d0001` | Read, Notify |

## Control Commands

Control write frame:

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint8` | command |
| 1 | `uint8` | payload length |
| 2..n | bytes | payload |

Commands:

| ID | Name | Payload |
|---:|---|---|
| `0x01` | Time Sync | `uint64 unix_ms`, `uint64 device_uptime_ms_seen_by_app` |
| `0x02` | Set Mode | `uint8 mode` |
| `0x03` | Set PPG Sampling | `uint16 hz` |
| `0x04` | Set LED Current | `uint8 green_ma`, `uint8 red_ma`, `uint8 ir_ma` |
| `0x05` | Request Backfill | `uint64 from_device_uptime_ms` |
| `0x06` | Request Raw PPG Window | `uint16 seconds` |
| `0x07` | Enter Ship Mode | empty |

Modes:

| Value | Mode |
|---:|---|
| `0` | Standby |
| `1` | Active |
| `2` | Low Power |
| `3` | HR-only |
| `4` | Ship Mode |

## Live Stream Frame

The firmware batches one or more live records into a notification.

Notification frame:

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint8` | frame type = `0x10` |
| 1 | `uint8` | record count |
| 2 | `uint16` | sequence |
| 4..n | records | live records |

Live record:

| Type | Field |
|---|---|
| `uint32` | uptime delta ms from previous record |
| `uint16` | heart rate x10 bpm |
| `uint16` | ibi ms |
| `int16` | accel magnitude milli-g |
| `uint8` | spo2 percent, `0xFF` if unavailable |
| `uint8` | quality flags |
| `uint32` | step count from onboard IMU, optional activity extension |
| `uint8` | motion status, optional activity extension |

Firmware built after the activity extension sends 17-byte live records. The
first 12 bytes remain the original live record. Apps should accept both the
legacy 12-byte record and the extended 17-byte record.

Motion status:

| Value | Meaning |
|---:|---|
| `0` | OK |
| `1` | unavailable |

Quality flags:

| Bit | Meaning |
|---:|---|
| 0 | skin contact |
| 1 | motion artifact |
| 2 | low perfusion |
| 3 | puck changed |
| 4 | battery low |

## Bulk Backfill Frame

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint8` | frame type = `0x20` |
| 1 | `uint8` | record kind |
| 2 | `uint16` | sequence |
| 4 | `uint16` | payload length |
| 6..n | bytes | compressed or packed records |

Record kinds:

| Value | Kind |
|---:|---|
| `1` | 1-minute aggregate |
| `2` | IBI night window |
| `3` | clean shutdown marker |
| `4` | gap marker |

## Raw PPG Frame

The firmware sends this frame in response to `Request Raw PPG Window`.
If the sensor is unavailable or no FIFO samples are ready, `payload length`
is `0`; the status bytes still report the real hardware state.

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint8` | frame type = `0x30` |
| 1 | `uint16` | sequence |
| 3 | `uint16` | requested window seconds |
| 5 | `uint8` | attached |
| 6 | `uint8` | sensor status |
| 7 | `uint8` | payload length |
| 8..n | bytes | raw MAXM86161 FIFO bytes, 3 bytes per FIFO item |

## Puck Status

Puck status notification:

| Offset | Type | Field |
|---:|---|---|
| 0 | `uint8` | event type |
| 1 | `uint8` | puck kind |
| 2 | `uint8` | attached |
| 3 | `uint8` | sensor status |

Event types:

| Value | Event |
|---:|---|
| `1` | Attached |
| `2` | Removed |
| `3` | Calibration started |
| `4` | Calibration complete |
| `5` | Fault |

Puck kinds:

| Value | Puck |
|---:|---|
| `1` | PPG MAXM86161 |
| `2` | EDA + temperature |
| `3` | ECG spot |

## Firmware Requirements

- Advertise as `OpenPulse`.
- Negotiate MTU up to 247 bytes when available.
- Time sync before streaming/backfill.
- Backfill before live stream when a gap exists.
- Persist clean shutdown marker before entering ship mode.
- Report Puck 1 by probing MAXM86161 at I2C address `0x62`.
