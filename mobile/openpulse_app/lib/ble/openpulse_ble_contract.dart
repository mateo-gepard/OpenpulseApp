import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/openpulse_models.dart';

class OpenPulseBleContract {
  static const advertisedName = 'OpenPulse';

  static final serviceUuid = Guid('f04d0000-57f5-4f5a-9b80-4f6f2f1d0001');
  static final controlUuid = Guid('f04d0001-57f5-4f5a-9b80-4f6f2f1d0001');
  static final liveStreamUuid = Guid('f04d0002-57f5-4f5a-9b80-4f6f2f1d0001');
  static final bulkBackfillUuid = Guid('f04d0003-57f5-4f5a-9b80-4f6f2f1d0001');
  static final rawPpgUuid = Guid('f04d0004-57f5-4f5a-9b80-4f6f2f1d0001');
  static final puckStatusUuid = Guid('f04d0005-57f5-4f5a-9b80-4f6f2f1d0001');

  static const deviceInformationService = '180a';
  static const batteryService = '180f';
  static const batteryLevelCharacteristic = '2a19';
  static const manufacturerCharacteristic = '2a29';
  static const modelCharacteristic = '2a24';
  static const firmwareCharacteristic = '2a26';
  static const hardwareCharacteristic = '2a27';

  static bool uuidMatches(Guid uuid, Object expected) {
    final actual = uuid.toString().toLowerCase();
    final value = expected is Guid
        ? expected.toString().toLowerCase()
        : expected.toString().toLowerCase();
    if (actual == value) {
      return true;
    }
    if (value.length == 4) {
      return actual == value ||
          actual == '0000$value-0000-1000-8000-00805f9b34fb';
    }
    return false;
  }

  static List<int> buildTimeSync({
    required int unixMs,
    required int deviceUptimeMsSeenByApp,
  }) {
    final data = ByteData(18);
    data.setUint8(0, 0x01);
    data.setUint8(1, 16);
    data.setUint64(2, unixMs, Endian.little);
    data.setUint64(10, deviceUptimeMsSeenByApp, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildSetMode(DeviceMode mode) => [0x02, 1, mode.value];

  static List<int> buildSetSampling(int hz) {
    final data = ByteData(4);
    data.setUint8(0, 0x03);
    data.setUint8(1, 2);
    data.setUint16(2, hz, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildSetLedCurrent({
    required int greenMa,
    required int redMa,
    required int irMa,
  }) => [0x04, 3, greenMa & 0xff, redMa & 0xff, irMa & 0xff];

  static List<int> buildRequestBackfill(int fromDeviceUptimeMs) {
    final data = ByteData(10);
    data.setUint8(0, 0x05);
    data.setUint8(1, 8);
    data.setUint64(2, fromDeviceUptimeMs, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildRequestRawWindow(int seconds) {
    final data = ByteData(4);
    data.setUint8(0, 0x06);
    data.setUint8(1, 2);
    data.setUint16(2, seconds, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildEnterShipMode() => [0x07, 0];

  static int? parseBattery(List<int> bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    final level = bytes.first;
    return level <= 100 ? level : null;
  }

  static int parseControlDeviceUptime(List<int> bytes) {
    if (bytes.length < 12) {
      return 0;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return data.getUint64(4, Endian.little);
  }

  static PuckStatus? parsePuckStatus(List<int> bytes, DateTime receivedAt) {
    if (bytes.length < 4) {
      return null;
    }
    return PuckStatus(
      receivedAt: receivedAt,
      eventType: bytes[0],
      puckKind: bytes[1],
      attached: bytes[2] == 1,
      sensorStatus: bytes[3],
    );
  }

  static ParsedLiveFrame? parseLiveFrame({
    required List<int> bytes,
    required int previousDeviceUptimeMs,
    required int syncedUnixMs,
    required int syncedDeviceUptimeMs,
    required DateTime receivedAt,
  }) {
    if (bytes.length < 4 || bytes[0] != 0x10) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final count = data.getUint8(1);
    final sequence = data.getUint16(2, Endian.little);
    var offset = 4;
    var deviceUptime = previousDeviceUptimeMs;
    final records = <LiveRecord>[];

    for (var i = 0; i < count; i++) {
      if (offset + 12 > bytes.length) {
        break;
      }
      final delta = data.getUint32(offset, Endian.little);
      final hrX10 = data.getUint16(offset + 4, Endian.little);
      final ibiMs = data.getUint16(offset + 6, Endian.little);
      final accel = data.getInt16(offset + 8, Endian.little);
      final spo2 = data.getUint8(offset + 10);
      final quality = data.getUint8(offset + 11);
      deviceUptime += delta;

      final wallTimeMs = syncedUnixMs + (deviceUptime - syncedDeviceUptimeMs);
      records.add(
        LiveRecord(
          receivedAt: receivedAt,
          wallTime: DateTime.fromMillisecondsSinceEpoch(wallTimeMs),
          deviceUptimeMs: deviceUptime,
          sequence: sequence,
          heartRateBpm: hrX10 == 0 ? null : hrX10 / 10.0,
          ibiMs: ibiMs == 0 ? null : ibiMs,
          accelMilliG: accel == 0 ? null : accel,
          spo2Percent: spo2 == 0xff ? null : spo2,
          qualityFlags: quality,
        ),
      );
      offset += 12;
    }

    return ParsedLiveFrame(
      sequence: sequence,
      records: records,
      lastDeviceUptimeMs: deviceUptime,
    );
  }
}
