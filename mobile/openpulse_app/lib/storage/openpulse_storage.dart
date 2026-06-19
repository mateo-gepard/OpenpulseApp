import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/openpulse_models.dart';

class OpenPulseStorage {
  Database? _db;

  Future<void> open() async {
    if (_db != null) {
      return;
    }
    final supportDir = await getApplicationSupportDirectory();
    if (!supportDir.existsSync()) {
      supportDir.createSync(recursive: true);
    }
    final dbPath = path.join(supportDir.path, 'openpulse.sqlite');
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _db = db;
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS device_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        connected_at_ms INTEGER NOT NULL,
        disconnected_at_ms INTEGER,
        firmware TEXT,
        hardware TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS time_syncs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        unix_ms INTEGER NOT NULL,
        device_uptime_ms_seen INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS battery_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        level INTEGER,
        available INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS puck_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        event_type INTEGER NOT NULL,
        puck_kind INTEGER NOT NULL,
        attached INTEGER NOT NULL,
        sensor_status INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS live_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        wall_time_ms INTEGER NOT NULL,
        device_uptime_ms INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        heart_rate_x10 INTEGER,
        ibi_ms INTEGER,
        accel_milli_g INTEGER,
        spo2_percent INTEGER,
        quality_flags INTEGER NOT NULL,
        step_count INTEGER,
        motion_status INTEGER,
        hr_confidence INTEGER,
        spo2_confidence INTEGER,
        calibration_progress INTEGER,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    _addColumnIfMissing(
      db,
      table: 'live_records',
      column: 'step_count',
      definition: 'INTEGER',
    );
    _addColumnIfMissing(
      db,
      table: 'live_records',
      column: 'motion_status',
      definition: 'INTEGER',
    );
    _addColumnIfMissing(
      db,
      table: 'live_records',
      column: 'hr_confidence',
      definition: 'INTEGER',
    );
    _addColumnIfMissing(
      db,
      table: 'live_records',
      column: 'spo2_confidence',
      definition: 'INTEGER',
    );
    _addColumnIfMissing(
      db,
      table: 'live_records',
      column: 'calibration_progress',
      definition: 'INTEGER',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS control_writes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        written_at_ms INTEGER NOT NULL,
        command INTEGER NOT NULL,
        payload_hex TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS control_acks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        command INTEGER NOT NULL,
        status INTEGER NOT NULL,
        mode INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS backfill_frames (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        record_kind INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        payload_length INTEGER NOT NULL,
        payload_hex TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS raw_ppg_frames (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        received_at_ms INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        requested_seconds INTEGER,
        attached INTEGER,
        sensor_status INTEGER,
        payload_length INTEGER NOT NULL,
        payload_hex TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
    _addColumnIfMissing(
      db,
      table: 'raw_ppg_frames',
      column: 'payload_length',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  void _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) {
    final columns = db.select('PRAGMA table_info($table);');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $definition;');
    }
  }

  int insertSession({
    required String remoteId,
    required String deviceName,
    DeviceInformation? information,
  }) {
    final db = _requireDb();
    final statement = db.prepare('''
      INSERT INTO device_sessions (
        remote_id, device_name, connected_at_ms, firmware, hardware
      ) VALUES (?, ?, ?, ?, ?)
    ''');
    try {
      statement.execute([
        remoteId,
        deviceName,
        DateTime.now().millisecondsSinceEpoch,
        information?.firmware,
        information?.hardware,
      ]);
      return db.lastInsertRowId;
    } finally {
      statement.dispose();
    }
  }

  void closeSession(int? sessionId) {
    if (sessionId == null) {
      return;
    }
    _requireDb().execute(
      'UPDATE device_sessions SET disconnected_at_ms = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, sessionId],
    );
  }

  void insertTimeSync({
    required int? sessionId,
    required int unixMs,
    required int deviceUptimeMsSeen,
  }) {
    _requireDb().execute(
      '''
      INSERT INTO time_syncs (
        session_id, unix_ms, device_uptime_ms_seen, created_at_ms
      ) VALUES (?, ?, ?, ?)
      ''',
      [
        sessionId,
        unixMs,
        deviceUptimeMsSeen,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  void insertBatterySample(int? sessionId, BatterySample sample) {
    _requireDb().execute(
      '''
      INSERT INTO battery_samples (
        session_id, received_at_ms, level, available
      ) VALUES (?, ?, ?, ?)
      ''',
      [
        sessionId,
        sample.receivedAt.millisecondsSinceEpoch,
        sample.level,
        sample.available ? 1 : 0,
      ],
    );
  }

  void insertPuckStatus(int? sessionId, PuckStatus status) {
    _requireDb().execute(
      '''
      INSERT INTO puck_events (
        session_id, received_at_ms, event_type, puck_kind, attached, sensor_status
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        status.receivedAt.millisecondsSinceEpoch,
        status.eventType,
        status.puckKind,
        status.attached ? 1 : 0,
        status.sensorStatus,
      ],
    );
  }

  void insertLiveRecord(int? sessionId, LiveRecord record) {
    _requireDb().execute(
      '''
      INSERT INTO live_records (
        session_id,
        received_at_ms,
        wall_time_ms,
        device_uptime_ms,
        sequence,
        heart_rate_x10,
        ibi_ms,
        accel_milli_g,
        spo2_percent,
        quality_flags,
        step_count,
        motion_status,
        hr_confidence,
        spo2_confidence,
        calibration_progress
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        record.receivedAt.millisecondsSinceEpoch,
        record.wallTime.millisecondsSinceEpoch,
        record.deviceUptimeMs,
        record.sequence,
        record.heartRateBpm == null
            ? null
            : (record.heartRateBpm! * 10).round(),
        record.ibiMs,
        record.accelMilliG,
        record.spo2Percent,
        record.qualityFlags,
        record.stepCount,
        record.motionStatus,
        record.hrConfidence,
        record.spo2Confidence,
        record.calibrationProgress,
      ],
    );
  }

  void insertControlWrite({
    required int? sessionId,
    required int command,
    required List<int> frame,
  }) {
    _requireDb().execute(
      '''
      INSERT INTO control_writes (
        session_id, written_at_ms, command, payload_hex
      ) VALUES (?, ?, ?, ?)
      ''',
      [
        sessionId,
        DateTime.now().millisecondsSinceEpoch,
        command,
        frame.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      ],
    );
  }

  void insertControlAck(int? sessionId, ControlAck ack) {
    _requireDb().execute(
      '''
      INSERT INTO control_acks (
        session_id, received_at_ms, command, status, mode
      ) VALUES (?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        ack.receivedAt.millisecondsSinceEpoch,
        ack.command,
        ack.status,
        ack.mode,
      ],
    );
  }

  void insertBackfillFrame(int? sessionId, BulkBackfillFrame frame) {
    _requireDb().execute(
      '''
      INSERT INTO backfill_frames (
        session_id, received_at_ms, record_kind, sequence, payload_length, payload_hex
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        frame.receivedAt.millisecondsSinceEpoch,
        frame.recordKind,
        frame.sequence,
        frame.payloadLength,
        frame.payloadHex,
      ],
    );
  }

  void insertRawPpgFrame(int? sessionId, RawPpgFrame frame) {
    _requireDb().execute(
      '''
      INSERT INTO raw_ppg_frames (
        session_id, received_at_ms, sequence, requested_seconds, attached, sensor_status, payload_length, payload_hex
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sessionId,
        frame.receivedAt.millisecondsSinceEpoch,
        frame.sequence,
        frame.requestedSeconds,
        frame.attached == null ? null : (frame.attached! ? 1 : 0),
        frame.sensorStatus,
        frame.payloadLength,
        frame.payloadHex,
      ],
    );
  }

  DaySummary fetchDaySummary(DateTime day) {
    final db = _requireDb();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    int scalar(String sql) {
      final rows = db.select(sql, [startMs, endMs]);
      if (rows.isEmpty || rows.first.values.first == null) {
        return 0;
      }
      return rows.first.values.first as int;
    }

    int? nullableInt(String sql) {
      final rows = db.select(sql, [startMs, endMs]);
      if (rows.isEmpty || rows.first.values.first == null) {
        return null;
      }
      return rows.first.values.first as int;
    }

    DateTime? nullableDate(String sql) {
      final ms = nullableInt(sql);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return DaySummary(
      day: start,
      liveRecords: scalar(
        'SELECT COUNT(*) FROM live_records WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
      rawPpgFrames: scalar(
        'SELECT COUNT(*) FROM raw_ppg_frames WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
      puckEvents: scalar(
        'SELECT COUNT(*) FROM puck_events WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
      controlWrites: scalar(
        'SELECT COUNT(*) FROM control_writes WHERE written_at_ms >= ? AND written_at_ms < ?',
      ),
      maxSteps: nullableInt(
        'SELECT MAX(step_count) FROM live_records WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
      lastLiveAt: nullableDate(
        'SELECT MAX(received_at_ms) FROM live_records WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
      lastRawAt: nullableDate(
        'SELECT MAX(received_at_ms) FROM raw_ppg_frames WHERE received_at_ms >= ? AND received_at_ms < ?',
      ),
    );
  }

  HrvSummary fetchHrvSummary({Duration window = const Duration(minutes: 5)}) {
    final db = _requireDb();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = nowMs - window.inMilliseconds;
    final rows = db.select(
      '''
      SELECT ibi_ms, hr_confidence, quality_flags, wall_time_ms
      FROM live_records
      WHERE wall_time_ms >= ?
        AND ibi_ms IS NOT NULL
      ORDER BY wall_time_ms ASC
      ''',
      [startMs],
    );

    final clean = <int>[];
    var rejected = 0;
    for (final row in rows) {
      final ibi = row['ibi_ms'] as int;
      final hrConfidence = row['hr_confidence'] as int?;
      final quality = row['quality_flags'] as int? ?? 0;
      final motionArtifact = quality & 0x02 != 0;
      final lowPerfusion = quality & 0x04 != 0;
      final clipping = quality & 0x20 != 0;
      final trusted =
          (hrConfidence ?? 0) >= 55 &&
          !motionArtifact &&
          !lowPerfusion &&
          !clipping &&
          ibi >= 333 &&
          ibi <= 2000;
      if (trusted) {
        clean.add(ibi);
      } else {
        rejected++;
      }
    }

    if (clean.length < 8) {
      return HrvSummary(
        rmssdMs: null,
        sdnnMs: null,
        cleanIbiCount: clean.length,
        rejectedIbiCount: rejected,
        windowDuration: window,
        confidence: clean.isEmpty ? 0 : (clean.length * 4).clamp(0, 35),
        calibrationProgress: (clean.length * 2).clamp(0, 25),
        status: 'Needs clean IBI',
      );
    }

    final filtered = <int>[];
    for (final ibi in clean) {
      if (filtered.isEmpty) {
        filtered.add(ibi);
        continue;
      }
      final previous = filtered.last;
      final diff = (ibi - previous).abs();
      if (diff > 350 || diff > previous * 0.28) {
        rejected++;
        continue;
      }
      filtered.add(ibi);
    }

    if (filtered.length < 8) {
      return HrvSummary(
        rmssdMs: null,
        sdnnMs: null,
        cleanIbiCount: filtered.length,
        rejectedIbiCount: rejected,
        windowDuration: window,
        confidence: 20,
        calibrationProgress: 20,
        status: 'Artifact-heavy',
      );
    }

    var diffSquares = 0.0;
    for (var i = 1; i < filtered.length; i++) {
      final diff = filtered[i] - filtered[i - 1];
      diffSquares += diff * diff;
    }
    final rmssd = math.sqrt(diffSquares / (filtered.length - 1));
    final mean = filtered.reduce((a, b) => a + b) / filtered.length;
    final variance =
        filtered.map((ibi) => math.pow(ibi - mean, 2)).reduce((a, b) => a + b) /
        filtered.length;
    final sdnn = math.sqrt(variance);
    final coverage = (filtered.length / 300).clamp(0.0, 1.0);
    final artifactRatio = rejected / (filtered.length + rejected);
    final confidence = (45 + coverage * 45 - artifactRatio * 35).round().clamp(
      0,
      95,
    );
    final baselineDays = _countDaysWithCleanIbi(db);
    final calibrationProgress = ((baselineDays / 14.0) * 100).round().clamp(
      0,
      100,
    );

    return HrvSummary(
      rmssdMs: rmssd,
      sdnnMs: sdnn,
      cleanIbiCount: filtered.length,
      rejectedIbiCount: rejected,
      windowDuration: window,
      confidence: confidence,
      calibrationProgress: calibrationProgress,
      status: calibrationProgress >= 100
          ? 'Baseline ready'
          : 'Baseline building',
    );
  }

  int _countDaysWithCleanIbi(Database db) {
    final rows = db.select('''
      SELECT date(wall_time_ms / 1000, 'unixepoch') AS day, COUNT(*) AS count
      FROM live_records
      WHERE ibi_ms IS NOT NULL
        AND COALESCE(hr_confidence, 0) >= 55
        AND (quality_flags & 0x26) = 0
      GROUP BY day
      HAVING count >= 120
    ''');
    return rows.length;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('OpenPulseStorage.open() has not completed');
    }
    return db;
  }

  void dispose() {
    _db?.dispose();
    _db = null;
  }
}
