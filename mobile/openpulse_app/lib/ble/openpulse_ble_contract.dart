import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/openpulse_models.dart';

class OpenPulseBleContract {
  static const advertisedName = 'OpenPulse';
  static const secondaryAdvertisedName = 'OpenPulse Nova';
  static const legacyLiveRecordLength = 12;
  static const activityLiveRecordLength = 17;
  static const metricsLiveRecordLength = 20;
  static const extendedLiveRecordLength = 26;
  static const backfillLiveRecordLength = 24;

  static final serviceUuid = Guid('f04d0000-57f5-4f5a-9b80-4f6f2f1d0001');
  static final controlUuid = Guid('f04d0001-57f5-4f5a-9b80-4f6f2f1d0001');
  static final liveStreamUuid = Guid('f04d0002-57f5-4f5a-9b80-4f6f2f1d0001');
  static final bulkBackfillUuid = Guid('f04d0003-57f5-4f5a-9b80-4f6f2f1d0001');
  static final rawPpgUuid = Guid('f04d0004-57f5-4f5a-9b80-4f6f2f1d0001');
  static final puckStatusUuid = Guid('f04d0005-57f5-4f5a-9b80-4f6f2f1d0001');

  static bool isOpenPulseName(String? name) {
    final trimmed = name?.trim();
    return trimmed != null &&
        trimmed.isNotEmpty &&
        (trimmed == advertisedName || trimmed.startsWith('$advertisedName '));
  }

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

  static ControlAck? parseControlAck(List<int> bytes, DateTime receivedAt) {
    if (bytes.length < 4 || bytes[0] != 0x80) {
      return null;
    }
    return ControlAck(
      receivedAt: receivedAt,
      command: bytes[1],
      status: bytes[2],
      mode: bytes[3],
    );
  }

  static BulkBackfillFrame? parseBulkFrame(
    List<int> bytes,
    DateTime receivedAt,
  ) {
    if (bytes.length < 6 || bytes[0] != 0x20) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final payloadLength = data.getUint16(4, Endian.little);
    final payload = bytes.skip(6).take(payloadLength).toList(growable: false);
    return BulkBackfillFrame(
      receivedAt: receivedAt,
      recordKind: bytes[1],
      sequence: data.getUint16(2, Endian.little),
      payloadLength: payloadLength,
      payloadHex: bytesToHex(payload),
      payloadBytes: payload,
    );
  }

  static List<LiveRecord> parseBackfillLiveRecords({
    required BulkBackfillFrame frame,
    required int syncedUnixMs,
    required int syncedDeviceUptimeMs,
  }) {
    if (!frame.isLiveBackfill ||
        frame.payloadLength < backfillLiveRecordLength ||
        frame.payloadBytes.length < backfillLiveRecordLength) {
      return const [];
    }

    final payload = Uint8List.fromList(frame.payloadBytes);
    final data = ByteData.sublistView(payload);
    final records = <LiveRecord>[];
    for (
      var offset = 0;
      offset + backfillLiveRecordLength <= frame.payloadBytes.length;
      offset += backfillLiveRecordLength
    ) {
      final wallTimeSeconds = data.getUint32(offset, Endian.little);
      final deviceUptime = data.getUint32(offset + 4, Endian.little);
      final hrX10 = data.getUint16(offset + 8, Endian.little);
      final ibiMs = data.getUint16(offset + 10, Endian.little);
      final accel = data.getInt16(offset + 12, Endian.little);
      final spo2 = data.getUint8(offset + 14);
      final quality = data.getUint8(offset + 15);
      final stepCount = data.getUint32(offset + 16, Endian.little);
      final motionStatus = data.getUint8(offset + 20);
      final hrConfidence = data.getUint8(offset + 21);
      final spo2Confidence = data.getUint8(offset + 22);
      final calibrationProgress = data.getUint8(offset + 23);
      final wallTimeMs = wallTimeSeconds == 0
          ? syncedUnixMs + (deviceUptime - syncedDeviceUptimeMs)
          : wallTimeSeconds * 1000;

      records.add(
        LiveRecord(
          receivedAt: frame.receivedAt,
          wallTime: DateTime.fromMillisecondsSinceEpoch(wallTimeMs),
          deviceUptimeMs: deviceUptime,
          sequence: frame.sequence,
          heartRateBpm: hrX10 == 0 ? null : hrX10 / 10.0,
          ibiMs: ibiMs == 0 ? null : ibiMs,
          accelMilliG: accel == 0 ? null : accel,
          spo2Percent: spo2 == 0xff ? null : spo2,
          qualityFlags: quality,
          stepCount: stepCount,
          motionStatus: motionStatus,
          hrConfidence: hrConfidence,
          spo2Confidence: spo2Confidence,
          calibrationProgress: calibrationProgress,
          hrvRmssdMs: null,
        ),
      );
    }
    return records;
  }

  static RawPpgFrame? parseRawPpgFrame(List<int> bytes, DateTime receivedAt) {
    if (bytes.isEmpty) {
      return null;
    }
    if (bytes[0] == 0x30 && bytes.length >= 8) {
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      final declaredPayloadLength = bytes[7];
      final availablePayloadLength = bytes.length > 8 ? bytes.length - 8 : 0;
      final payloadLength = declaredPayloadLength <= availablePayloadLength
          ? declaredPayloadLength
          : availablePayloadLength;
      final payload = bytes.skip(8).take(payloadLength).toList(growable: false);
      return RawPpgFrame(
        receivedAt: receivedAt,
        sequence: data.getUint16(1, Endian.little),
        requestedSeconds: data.getUint16(3, Endian.little),
        attached: bytes[5] == 1,
        sensorStatus: bytes[6],
        payloadLength: payloadLength,
        payloadHex: bytesToHex(payload),
        samples: parseRawPpgSamples(payload),
      );
    }
    return RawPpgFrame(
      receivedAt: receivedAt,
      sequence: 0,
      requestedSeconds: null,
      attached: null,
      sensorStatus: null,
      payloadLength: bytes.length,
      payloadHex: bytesToHex(bytes),
      samples: parseRawPpgSamples(bytes),
    );
  }

  static List<int> parseRawPpgSamples(List<int> payload) {
    final samples = <int>[];
    final legacySamples = <int>[];
    var sawTaggedSamples = false;
    for (var i = 0; i + 2 < payload.length; i += 3) {
      final tag = payload[i] >> 3;
      final value =
          ((payload[i] & 0x07) << 16) | (payload[i + 1] << 8) | payload[i + 2];
      if (tag == 0) {
        legacySamples.add(value);
      } else {
        sawTaggedSamples = true;
        if (tag == 1) {
          samples.add(value);
        }
      }
    }
    return sawTaggedSamples ? samples : legacySamples;
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
    final availableRecordBytes = bytes.length - 4;
    final recordLength =
        count > 0 && availableRecordBytes >= count * extendedLiveRecordLength
        ? extendedLiveRecordLength
        : count > 0 && availableRecordBytes >= count * metricsLiveRecordLength
        ? metricsLiveRecordLength
        : count > 0 && availableRecordBytes >= count * activityLiveRecordLength
        ? activityLiveRecordLength
        : legacyLiveRecordLength;
    var offset = 4;
    var deviceUptime = previousDeviceUptimeMs;
    final records = <LiveRecord>[];

    for (var i = 0; i < count; i++) {
      if (offset + recordLength > bytes.length) {
        break;
      }
      final delta = data.getUint32(offset, Endian.little);
      final hrX10 = data.getUint16(offset + 4, Endian.little);
      final ibiMs = data.getUint16(offset + 6, Endian.little);
      final accel = data.getInt16(offset + 8, Endian.little);
      final spo2 = data.getUint8(offset + 10);
      final quality = data.getUint8(offset + 11);
      final stepCount = recordLength >= activityLiveRecordLength
          ? data.getUint32(offset + 12, Endian.little)
          : null;
      final motionStatus = recordLength >= activityLiveRecordLength
          ? data.getUint8(offset + 16)
          : null;
      final hrConfidence = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 17)
          : null;
      final spo2Confidence = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 18)
          : null;
      final calibrationProgress = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 19)
          : null;
      final absoluteUptime = recordLength >= extendedLiveRecordLength
          ? data.getUint32(offset + 20, Endian.little)
          : null;
      final hrvRmssd = recordLength >= extendedLiveRecordLength
          ? data.getUint16(offset + 24, Endian.little)
          : null;
      // Absolute uptime, when present, prevents permanent wall-clock drift if a
      // live notification is dropped; older records fall back to delta sums.
      if (absoluteUptime != null) {
        deviceUptime = absoluteUptime;
      } else {
        deviceUptime += delta;
      }

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
          stepCount: stepCount,
          motionStatus: motionStatus,
          hrConfidence: hrConfidence,
          spo2Confidence: spo2Confidence,
          calibrationProgress: calibrationProgress,
          hrvRmssdMs: hrvRmssd == null || hrvRmssd == 0
              ? null
              : hrvRmssd.toDouble(),
        ),
      );
      offset += recordLength;
    }

    return ParsedLiveFrame(
      sequence: sequence,
      records: records,
      lastDeviceUptimeMs: deviceUptime,
    );
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
