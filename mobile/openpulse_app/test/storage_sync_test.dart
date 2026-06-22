import 'package:flutter_test/flutter_test.dart';
import 'package:openpulse_app/models/openpulse_models.dart';
import 'package:openpulse_app/storage/openpulse_storage.dart';

void main() {
  test('day summaries use Europe/Berlin midnight boundaries', () {
    final storage = OpenPulseStorage.inMemoryForTests();
    final beforeBerlinMidnight = DateTime.utc(2026, 6, 21, 21, 59, 59);
    final atBerlinMidnight = DateTime.utc(2026, 6, 21, 22);

    try {
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: beforeBerlinMidnight,
          uptimeMs: 1000,
          sequence: 1,
          steps: 10,
        ),
      );
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: atBerlinMidnight,
          uptimeMs: 2000,
          sequence: 2,
          steps: 20,
        ),
      );
      storage.insertLiveRecord(
        null,
        _record(
          wallTime: atBerlinMidnight.add(const Duration(minutes: 5)),
          uptimeMs: 3000,
          sequence: 3,
          steps: 70,
        ),
      );

      final summary = storage.fetchDaySummary(DateTime.utc(2026, 6, 22, 12));

      expect(summary.liveRecords, 2);
      expect(summary.stepCount, 50);
      expect(summary.maxSteps, 70);
      expect(
        summary.lastLiveAt?.millisecondsSinceEpoch,
        atBerlinMidnight.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
    } finally {
      storage.dispose();
    }
  });

  test('step goal persists in local storage', () {
    final storage = OpenPulseStorage.inMemoryForTests();

    try {
      expect(storage.loadStepGoal(), 10000);
      storage.saveStepGoal(12500);
      expect(storage.loadStepGoal(), 12500);
    } finally {
      storage.dispose();
    }
  });

  test('backfill storage skips records already present locally', () {
    final storage = OpenPulseStorage.inMemoryForTests();
    final now = DateTime.fromMillisecondsSinceEpoch(2_000_000);
    final existing = _record(wallTime: now, uptimeMs: 100000, sequence: 1);
    final newRecord = _record(
      wallTime: now.add(const Duration(seconds: 1)),
      uptimeMs: 101000,
      sequence: 2,
    );

    try {
      storage.insertLiveRecord(null, existing);

      expect(
        storage.replaceLiveRecordsFromDeviceBackfill(null, [
          existing,
          newRecord,
        ]),
        1,
      );

      final summary = storage.fetchDaySummary(now);
      expect(summary.liveRecords, 2);
    } finally {
      storage.dispose();
    }
  });

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
  int? steps,
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
    stepCount: steps,
    motionStatus: null,
    hrConfidence: null,
    spo2Confidence: null,
    calibrationProgress: null,
  );
}
