import 'package:flutter_test/flutter_test.dart';
import 'package:openpulse_app/ble/openpulse_ble_contract.dart';

void main() {
  test('recognizes named OpenPulse devices', () {
    expect(OpenPulseBleContract.isOpenPulseName('OpenPulse'), isTrue);
    expect(OpenPulseBleContract.isOpenPulseName('OpenPulse Nova'), isTrue);
    expect(OpenPulseBleContract.isOpenPulseName('Pulse'), isFalse);
  });

  test('parses control acknowledgement frames', () {
    final ack = OpenPulseBleContract.parseControlAck([
      0x80,
      0x01,
      0x00,
      0x01,
    ], DateTime.fromMillisecondsSinceEpoch(1000));

    expect(ack, isNotNull);
    expect(ack!.commandLabel, 'Time sync');
    expect(ack.ok, isTrue);
    expect(ack.mode, 1);
  });

  test('parses bulk gap marker frames', () {
    final frame = OpenPulseBleContract.parseBulkFrame([
      0x20,
      0x04,
      0x2a,
      0x00,
      0x08,
      0x00,
      0x10,
      0x27,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ], DateTime.fromMillisecondsSinceEpoch(1000));

    expect(frame, isNotNull);
    expect(frame!.kindLabel, 'Gap marker');
    expect(frame.sequence, 42);
    expect(frame.payloadLength, 8);
    expect(frame.payloadHex, '1027000000000000');
  });

  test('parses raw PPG unavailable diagnostic frames', () {
    final frame = OpenPulseBleContract.parseRawPpgFrame([
      0x30,
      0x03,
      0x00,
      0x0a,
      0x00,
      0x00,
      0x01,
      0x00,
    ], DateTime.fromMillisecondsSinceEpoch(1000));

    expect(frame, isNotNull);
    expect(frame!.sequence, 3);
    expect(frame.requestedSeconds, 10);
    expect(frame.attached, isFalse);
    expect(frame.sensorLabel, 'Unavailable');
    expect(frame.payloadLength, 0);
    expect(frame.payloadHex, isEmpty);
  });

  test('parses raw PPG FIFO payload frames', () {
    final frame = OpenPulseBleContract.parseRawPpgFrame([
      0x30,
      0x04,
      0x00,
      0x05,
      0x00,
      0x01,
      0x00,
      0x06,
      0x08,
      0x12,
      0x34,
      0x09,
      0x56,
      0x78,
    ], DateTime.fromMillisecondsSinceEpoch(1000));

    expect(frame, isNotNull);
    expect(frame!.sequence, 4);
    expect(frame.requestedSeconds, 5);
    expect(frame.attached, isTrue);
    expect(frame.sensorLabel, 'OK');
    expect(frame.payloadLength, 6);
    expect(frame.payloadHex, '081234095678');
    expect(frame.samples, [0x1234, 0x15678]);
  });

  test('plots only green samples from tagged raw PPG payloads', () {
    final frame = OpenPulseBleContract.parseRawPpgFrame([
      0x30,
      0x05,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x09,
      0x08,
      0x11,
      0x11,
      0x10,
      0x22,
      0x22,
      0x18,
      0x33,
      0x33,
    ], DateTime.fromMillisecondsSinceEpoch(1000));

    expect(frame, isNotNull);
    expect(frame!.samples, [0x1111]);
  });

  test('parses extended live frames with IMU steps', () {
    final frame = OpenPulseBleContract.parseLiveFrame(
      bytes: [
        0x10,
        0x01,
        0x07,
        0x00,
        0xe8,
        0x03,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xe9,
        0x03,
        0xff,
        0x04,
        0xd2,
        0x04,
        0x00,
        0x00,
        0x00,
      ],
      previousDeviceUptimeMs: 5000,
      syncedUnixMs: 100000,
      syncedDeviceUptimeMs: 5000,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    expect(frame, isNotNull);
    expect(frame!.sequence, 7);
    expect(frame.lastDeviceUptimeMs, 6000);
    expect(frame.records.single.accelMilliG, 1001);
    expect(frame.records.single.stepCount, 1234);
    expect(frame.records.single.motionLabel, 'OK');
    expect(frame.records.single.spo2Percent, isNull);
  });

  test('parses live metrics confidence extension', () {
    final frame = OpenPulseBleContract.parseLiveFrame(
      bytes: [
        0x10,
        0x01,
        0x08,
        0x00,
        0xe8,
        0x03,
        0x00,
        0x00,
        0x84,
        0x02,
        0xee,
        0x02,
        0xf4,
        0x03,
        0x62,
        0x41,
        0xd2,
        0x04,
        0x00,
        0x00,
        0x00,
        0x58,
        0x43,
        0x39,
      ],
      previousDeviceUptimeMs: 5000,
      syncedUnixMs: 100000,
      syncedDeviceUptimeMs: 5000,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final record = frame!.records.single;
    expect(frame.sequence, 8);
    expect(record.heartRateBpm, 64.4);
    expect(record.ibiMs, 750);
    expect(record.spo2Percent, 98);
    expect(record.hasSkinContact, isTrue);
    expect(record.isUncalibrated, isTrue);
    expect(record.stepCount, 1234);
    expect(record.hrConfidence, 88);
    expect(record.spo2Confidence, 67);
    expect(record.calibrationProgress, 57);
  });

  test('extended live frame uses absolute uptime and RMSSD', () {
    final frame = OpenPulseBleContract.parseLiveFrame(
      bytes: [
        0x10, 0x01, 0x09, 0x00,
        0xff, 0xff, 0xff, 0xff, // delta is ignored when absolute uptime present
        0x62, 0x02, // hr x10 = 610 -> 61.0 bpm
        0xee, 0x02, // ibi 750
        0xe9, 0x03, // accel 1001
        0x62, // spo2 98
        0x41, // quality: skin contact + uncalibrated
        0xd2, 0x04, 0x00, 0x00, // step 1234
        0x00, // motion ok
        0x58, // hr confidence 88
        0x43, // spo2 confidence 67
        0x39, // calibration 57
        0x70, 0x17, 0x00, 0x00, // absolute uptime 6000
        0x2a, 0x00, // rmssd 42 ms
      ],
      previousDeviceUptimeMs: 999999,
      syncedUnixMs: 100000,
      syncedDeviceUptimeMs: 5000,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final record = frame!.records.single;
    expect(frame.sequence, 9);
    // Absolute uptime wins over the previous-uptime + delta accumulation.
    expect(frame.lastDeviceUptimeMs, 6000);
    expect(record.deviceUptimeMs, 6000);
    expect(record.wallTime.millisecondsSinceEpoch, 101000);
    expect(record.heartRateBpm, 61.0);
    expect(record.stepCount, 1234);
    expect(record.calibrationProgress, 57);
    expect(record.hrvRmssdMs, 42.0);
  });
}
