import 'package:flutter_test/flutter_test.dart';
import 'package:openpulse_app/ble/openpulse_ble_contract.dart';

void main() {
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
}
