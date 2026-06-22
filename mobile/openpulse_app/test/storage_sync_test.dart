import 'package:flutter_test/flutter_test.dart';
import 'package:openpulse_app/models/openpulse_models.dart';
import 'package:openpulse_app/storage/openpulse_storage.dart';

void main() {
  test('incremental backfill cursor only resumes the current board boot', () {
    final storage = OpenPulseStorage.inMemoryForTests();
    final now = DateTime.fromMillisecondsSinceEpoch(1_000_000);

    try {
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: now.subtract(const Duration(minutes: 8)),
          uptimeMs: 520000,
          sequence: 1,
        ),
      );
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: now.subtract(const Duration(minutes: 2)),
          uptimeMs: 880000,
          sequence: 2,
        ),
      );
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: now.subtract(const Duration(seconds: 5)),
          uptimeMs: 40000,
          sequence: 3,
        ),
      );

      expect(
        storage.latestDeviceUptimeForCurrentBoot(
          currentDeviceUptimeMs: 900000,
          now: now,
        ),
        880000,
      );
      expect(
        storage.latestDeviceUptimeForCurrentBoot(
          currentDeviceUptimeMs: 45000,
          now: now,
        ),
        40000,
      );
    } finally {
      storage.dispose();
    }
  });
}

LiveRecord _record({
  required DateTime wallTime,
  required int uptimeMs,
  required int sequence,
}) {
  return LiveRecord(
    receivedAt: wallTime,
    wallTime: wallTime,
    deviceUptimeMs: uptimeMs,
    sequence: sequence,
    heartRateBpm: null,
    ibiMs: null,
    accelMilliG: null,
    spo2Percent: null,
    qualityFlags: 0,
    stepCount: null,
    motionStatus: null,
    hrConfidence: null,
    spo2Confidence: null,
    calibrationProgress: null,
  );
}
