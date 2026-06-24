import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/openpulse_models.dart';
import '../time/openpulse_time.dart';

class OpenPulseStorage {
  OpenPulseStorage();

  OpenPulseStorage.inMemoryForTests() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _db = db;
  }

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
        hrv_rmssd_ms REAL,
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
      column: 'hrv_rmssd_ms',
      definition: 'REAL',
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
    db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS device_profiles (
        remote_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        advertised_name TEXT NOT NULL,
        last_seen_ms INTEGER,
        last_connected_ms INTEGER
      );
    ''');
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

  List<OpenPulseDeviceProfile> fetchDeviceProfiles({
    String? selectedRemoteId,
    String? connectedRemoteId,
  }) {
    final rows = _requireDb().select('''
      SELECT remote_id, display_name, advertised_name, last_seen_ms, last_connected_ms
      FROM device_profiles
      ORDER BY COALESCE(last_connected_ms, last_seen_ms, 0) DESC, display_name ASC
    ''');
    return [
      for (final row in rows)
        OpenPulseDeviceProfile(
          remoteId: row['remote_id'] as String,
          displayName: row['display_name'] as String,
          advertisedName: row['advertised_name'] as String,
          lastSeenAt: _dateFromMs(row['last_seen_ms']),
          lastConnectedAt: _dateFromMs(row['last_connected_ms']),
          selected:
              selectedRemoteId != null && row['remote_id'] == selectedRemoteId,
          connected:
              connectedRemoteId != null &&
              row['remote_id'] == connectedRemoteId,
        ),
    ];
  }

  void upsertDeviceProfile({
    required String remoteId,
    required String advertisedName,
    bool connected = false,
  }) {
    final db = _requireDb();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existing = db.select(
      'SELECT display_name, advertised_name FROM device_profiles WHERE remote_id = ?',
      [remoteId],
    );
    final defaultName = _defaultDeviceDisplayName(advertisedName, remoteId);
    final displayName = existing.isEmpty
        ? defaultName
        : _updatedDeviceDisplayName(
            currentDisplayName: existing.first['display_name'] as String,
            currentAdvertisedName: existing.first['advertised_name'] as String,
            nextAdvertisedName: advertisedName,
            defaultName: defaultName,
          );

    db.execute(
      '''
      INSERT INTO device_profiles (
        remote_id, display_name, advertised_name, last_seen_ms, last_connected_ms
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(remote_id) DO UPDATE SET
        display_name = excluded.display_name,
        advertised_name = excluded.advertised_name,
        last_seen_ms = excluded.last_seen_ms,
        last_connected_ms = COALESCE(excluded.last_connected_ms, device_profiles.last_connected_ms)
      ''',
      [
        remoteId,
        displayName,
        advertisedName.isEmpty ? defaultName : advertisedName,
        nowMs,
        connected ? nowMs : null,
      ],
    );
  }

  String? loadSelectedDeviceRemoteId() {
    final rows = _requireDb().select(
      'SELECT value FROM app_settings WHERE key = ?',
      ['selected_device_remote_id'],
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.first['value'] as String?;
    return value == null || value.isEmpty ? null : value;
  }

  void saveSelectedDeviceRemoteId(String? remoteId) {
    final db = _requireDb();
    if (remoteId == null || remoteId.isEmpty) {
      db.execute('DELETE FROM app_settings WHERE key = ?', [
        'selected_device_remote_id',
      ]);
      return;
    }
    db.execute(
      '''
      INSERT INTO app_settings (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      [
        'selected_device_remote_id',
        remoteId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
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

  int loadStepGoal({int defaultValue = 10000}) {
    final rows = _requireDb().select(
      'SELECT value FROM app_settings WHERE key = ?',
      ['step_goal'],
    );
    if (rows.isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(rows.first['value'] as String? ?? '');
    return (parsed ?? defaultValue).clamp(500, 100000).toInt();
  }

  void saveStepGoal(int goal) {
    _requireDb().execute(
      '''
      INSERT INTO app_settings (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      [
        'step_goal',
        goal.clamp(500, 100000).toInt().toString(),
        DateTime.now().millisecondsSinceEpoch,
      ],
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
    _insertLiveRecord(_requireDb(), sessionId, record);
  }

  void _insertLiveRecord(Database db, int? sessionId, LiveRecord record) {
    db.execute(
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
        calibration_progress,
        hrv_rmssd_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        record.hrvRmssdMs,
      ],
    );
  }

  int replaceLiveRecordsFromDeviceBackfill(
    int? sessionId,
    List<LiveRecord> records, {
    String? remoteId,
  }) {
    if (records.isEmpty) {
      return 0;
    }

    final db = _requireDb();
    var stored = 0;

    db.execute('BEGIN IMMEDIATE;');
    try {
      for (final record in records) {
        if (_hasBackfilledLiveRecord(db, record, remoteId: remoteId)) {
          continue;
        }
        _deleteOverlappingBackfillRecord(db, record, remoteId: remoteId);
        _insertLiveRecord(db, sessionId, record);
        stored++;
      }
      db.execute('COMMIT;');
      return stored;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  bool _hasBackfilledLiveRecord(
    Database db,
    LiveRecord record, {
    String? remoteId,
  }) {
    final rows = db.select(
      '''
      SELECT 1
      FROM live_records lr
      WHERE lr.device_uptime_ms = ?
        AND ABS((lr.wall_time_ms - lr.device_uptime_ms) - ?) <= ?
        ${_remoteFilter('lr', remoteId)}
      LIMIT 1
      ''',
      [
        record.deviceUptimeMs,
        _recordBootStartMs(record),
        const Duration(minutes: 10).inMilliseconds,
        ?remoteId,
      ],
    );
    return rows.isNotEmpty;
  }

  void _deleteOverlappingBackfillRecord(
    Database db,
    LiveRecord record, {
    String? remoteId,
  }) {
    db.execute(
      '''
      DELETE FROM live_records
      WHERE id IN (
        SELECT lr.id
        FROM live_records lr
        WHERE lr.device_uptime_ms = ?
          AND ABS((lr.wall_time_ms - lr.device_uptime_ms) - ?) <= ?
          ${_remoteFilter('lr', remoteId)}
      )
      ''',
      [
        record.deviceUptimeMs,
        _recordBootStartMs(record),
        const Duration(minutes: 10).inMilliseconds,
        ?remoteId,
      ],
    );
  }

  int _recordBootStartMs(LiveRecord record) {
    return record.wallTime.millisecondsSinceEpoch - record.deviceUptimeMs;
  }

  int latestDeviceUptimeForCurrentBoot({
    required int currentDeviceUptimeMs,
    String? remoteId,
    DateTime? now,
    Duration tolerance = const Duration(minutes: 10),
  }) {
    if (currentDeviceUptimeMs <= 0) {
      return 0;
    }

    final db = _requireDb();
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final estimatedBootStartMs = nowMs - currentDeviceUptimeMs;
    final toleranceMs = tolerance.inMilliseconds;
    final rows = db.select(
      '''
      SELECT MAX(device_uptime_ms) AS latest_uptime
      FROM live_records lr
      WHERE lr.device_uptime_ms > 0
        AND lr.device_uptime_ms <= ?
        AND ABS((lr.wall_time_ms - lr.device_uptime_ms) - ?) <= ?
        ${_remoteFilter('lr', remoteId)}
      ''',
      [currentDeviceUptimeMs, estimatedBootStartMs, toleranceMs, ?remoteId],
    );
    if (rows.isEmpty || rows.first['latest_uptime'] == null) {
      return 0;
    }
    return rows.first['latest_uptime'] as int;
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

  Future<DebugExportResult> exportDebugBundle({
    Duration window = const Duration(minutes: 30),
    Map<String, Object?> runtime = const {},
  }) async {
    final db = _requireDb();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final startMs = nowMs - window.inMilliseconds;
    final sessions = _selectMaps(
      db,
      '''
      SELECT *
      FROM device_sessions
      WHERE connected_at_ms >= ? OR disconnected_at_ms IS NULL OR disconnected_at_ms >= ?
      ORDER BY connected_at_ms ASC
      ''',
      [startMs, startMs],
    );
    final liveRecords = _selectMaps(
      db,
      '''
      SELECT *
      FROM live_records
      WHERE wall_time_ms >= ? OR received_at_ms >= ?
      ORDER BY wall_time_ms ASC, id ASC
      ''',
      [startMs, startMs],
    );
    final rawFrames = _selectMaps(
      db,
      '''
      SELECT *
      FROM raw_ppg_frames
      WHERE received_at_ms >= ?
      ORDER BY received_at_ms ASC, id ASC
      ''',
      [startMs],
    );
    final backfillFrames = _selectMaps(
      db,
      '''
      SELECT *
      FROM backfill_frames
      WHERE received_at_ms >= ?
      ORDER BY received_at_ms ASC, id ASC
      ''',
      [startMs],
    );
    final puckEvents = _selectMaps(
      db,
      '''
      SELECT *
      FROM puck_events
      WHERE received_at_ms >= ?
      ORDER BY received_at_ms ASC, id ASC
      ''',
      [startMs],
    );
    final batterySamples = _selectMaps(
      db,
      '''
      SELECT *
      FROM battery_samples
      WHERE received_at_ms >= ?
      ORDER BY received_at_ms ASC, id ASC
      ''',
      [startMs],
    );
    final controlWrites = _selectMaps(
      db,
      '''
      SELECT *
      FROM control_writes
      WHERE written_at_ms >= ?
      ORDER BY written_at_ms ASC, id ASC
      ''',
      [startMs],
    );
    final controlAcks = _selectMaps(
      db,
      '''
      SELECT *
      FROM control_acks
      WHERE received_at_ms >= ?
      ORDER BY received_at_ms ASC, id ASC
      ''',
      [startMs],
    );

    final export = <String, Object?>{
      'schema': 'openpulse-debug-export-v1',
      'created_at_ms': nowMs,
      'created_at_iso': now.toIso8601String(),
      'window_minutes': window.inMinutes,
      'window_start_ms': startMs,
      'runtime': runtime,
      'counts': {
        'sessions': sessions.length,
        'live_records': liveRecords.length,
        'raw_ppg_frames': rawFrames.length,
        'backfill_frames': backfillFrames.length,
        'puck_events': puckEvents.length,
        'battery_samples': batterySamples.length,
        'control_writes': controlWrites.length,
        'control_acks': controlAcks.length,
      },
      'sessions': sessions,
      'live_records': liveRecords.map(_decorateLiveRecord).toList(),
      'raw_ppg_frames': rawFrames.map(_decorateRawPpgFrame).toList(),
      'backfill_frames': backfillFrames,
      'puck_events': puckEvents,
      'battery_samples': batterySamples,
      'control_writes': controlWrites,
      'control_acks': controlAcks,
    };

    final documentsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(
      path.join(documentsDir.path, 'OpenPulse Debug Exports'),
    );
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final stamp = now
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .replaceAll('T', '_');
    final fileName = 'openpulse_debug_$stamp.json';
    final file = File(path.join(exportDir.path, fileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(export),
      flush: true,
    );

    return DebugExportResult(
      createdAt: now,
      fileName: fileName,
      path: file.path,
      liveRecords: liveRecords.length,
      rawPpgFrames: rawFrames.length,
      backfillFrames: backfillFrames.length,
    );
  }

  DaySummary fetchDaySummary(DateTime day, {String? remoteId}) {
    final db = _requireDb();
    final start = OpenPulseTime.dayStart(day);
    final end = OpenPulseTime.nextDayStart(start);
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    List<Object?> args() => [startMs, endMs, ?remoteId];

    int scalar(String sql) {
      final rows = db.select(sql, args());
      if (rows.isEmpty || rows.first.values.first == null) {
        return 0;
      }
      return rows.first.values.first as int;
    }

    int? nullableInt(String sql) {
      final rows = db.select(sql, args());
      if (rows.isEmpty || rows.first.values.first == null) {
        return null;
      }
      return rows.first.values.first as int;
    }

    DateTime? nullableDate(String sql) {
      final ms = nullableInt(sql);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    final stepRows = db.select('''
      SELECT step_count
      FROM live_records
      WHERE wall_time_ms >= ?
        AND wall_time_ms < ?
        AND step_count IS NOT NULL
        ${_remoteFilter('live_records', remoteId)}
      ORDER BY wall_time_ms ASC, id ASC
      ''', args());
    final stepSamples = [for (final row in stepRows) row['step_count'] as int];

    return DaySummary(
      day: start,
      liveRecords: scalar(
        'SELECT COUNT(*) FROM live_records lr WHERE lr.wall_time_ms >= ? AND lr.wall_time_ms < ? ${_remoteFilter('lr', remoteId)}',
      ),
      rawPpgFrames: scalar(
        'SELECT COUNT(*) FROM raw_ppg_frames rf WHERE rf.received_at_ms >= ? AND rf.received_at_ms < ? ${_remoteFilter('rf', remoteId)}',
      ),
      puckEvents: scalar(
        'SELECT COUNT(*) FROM puck_events pe WHERE pe.received_at_ms >= ? AND pe.received_at_ms < ? ${_remoteFilter('pe', remoteId)}',
      ),
      controlWrites: scalar(
        'SELECT COUNT(*) FROM control_writes cw WHERE cw.written_at_ms >= ? AND cw.written_at_ms < ? ${_remoteFilter('cw', remoteId)}',
      ),
      stepCount: _dailyStepCount(stepSamples),
      maxSteps: nullableInt(
        'SELECT MAX(step_count) FROM live_records lr WHERE lr.wall_time_ms >= ? AND lr.wall_time_ms < ? ${_remoteFilter('lr', remoteId)}',
      ),
      lastLiveAt: nullableDate(
        'SELECT MAX(wall_time_ms) FROM live_records lr WHERE lr.wall_time_ms >= ? AND lr.wall_time_ms < ? ${_remoteFilter('lr', remoteId)}',
      ),
      lastRawAt: nullableDate(
        'SELECT MAX(received_at_ms) FROM raw_ppg_frames rf WHERE rf.received_at_ms >= ? AND rf.received_at_ms < ? ${_remoteFilter('rf', remoteId)}',
      ),
    );
  }

  int? _dailyStepCount(List<int> samples) {
    if (samples.isEmpty) {
      return null;
    }
    if (samples.length == 1) {
      return samples.single;
    }

    var total = 0;
    var segmentStart = samples.first;
    var previous = samples.first;
    for (final sample in samples.skip(1)) {
      if (sample < previous) {
        total += math.max(0, previous - segmentStart);
        segmentStart = sample;
      }
      previous = sample;
    }
    total += math.max(0, previous - segmentStart);
    return total;
  }

  HrvSummary fetchHrvSummary({
    Duration window = const Duration(minutes: 5),
    String? remoteId,
  }) {
    final db = _requireDb();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = nowMs - window.inMilliseconds;
    final rows = db.select(
      '''
      SELECT ibi_ms, hrv_rmssd_ms, hr_confidence, quality_flags, wall_time_ms
      FROM live_records lr
      WHERE lr.wall_time_ms >= ?
        ${_remoteFilter('lr', remoteId)}
      ORDER BY wall_time_ms ASC
      ''',
      [startMs, ?remoteId],
    );

    // RMSSD comes from the firmware, which computes it over true consecutive
    // beat intervals. The app must not derive RMSSD from the once-per-second
    // smoothed IBI, which has the beat-to-beat variability averaged out.
    final trustedRmssd = <double>[];
    final trustedIbi = <int>[];
    var rejected = 0;
    for (final row in rows) {
      final ibi = row['ibi_ms'] as int?;
      final rmssd = (row['hrv_rmssd_ms'] as num?)?.toDouble();
      final hrConfidence = row['hr_confidence'] as int?;
      final quality = row['quality_flags'] as int? ?? 0;
      final motionArtifact = quality & 0x02 != 0;
      final lowPerfusion = quality & 0x04 != 0;
      final clipping = quality & 0x20 != 0;
      final trusted =
          (hrConfidence ?? 0) >= 55 &&
          !motionArtifact &&
          !lowPerfusion &&
          !clipping;
      if (!trusted) {
        rejected++;
        continue;
      }
      if (rmssd != null && rmssd > 0) {
        trustedRmssd.add(rmssd);
      }
      if (ibi != null && ibi >= 333 && ibi <= 2000) {
        trustedIbi.add(ibi);
      }
    }

    if (trustedRmssd.length < 8) {
      return HrvSummary(
        rmssdMs: null,
        sdnnMs: null,
        cleanIbiCount: trustedRmssd.length,
        rejectedIbiCount: rejected,
        windowDuration: window,
        confidence: trustedRmssd.isEmpty
            ? 0
            : (trustedRmssd.length * 4).clamp(0, 35),
        calibrationProgress: (trustedRmssd.length * 2).clamp(0, 25),
        status: 'Needs clean beats',
      );
    }

    final rmssd = _median(trustedRmssd);
    // SDNN is a secondary metric derived from the reported IBI trend; the
    // firmware does not stream a beat-accurate SDNN.
    final sdnn = trustedIbi.length >= 8 ? _standardDeviation(trustedIbi) : null;
    final coverage = (trustedRmssd.length / 300).clamp(0.0, 1.0);
    final artifactRatio = rejected / (trustedRmssd.length + rejected);
    final confidence = (45 + coverage * 45 - artifactRatio * 35).round().clamp(
      0,
      95,
    );
    final baselineDays = _countDaysWithCleanIbi(db, remoteId: remoteId);
    final calibrationProgress = ((baselineDays / 14.0) * 100).round().clamp(
      0,
      100,
    );

    return HrvSummary(
      rmssdMs: rmssd,
      sdnnMs: sdnn,
      cleanIbiCount: trustedRmssd.length,
      rejectedIbiCount: rejected,
      windowDuration: window,
      confidence: confidence,
      calibrationProgress: calibrationProgress,
      status: calibrationProgress >= 100
          ? 'Baseline ready'
          : 'Baseline building',
    );
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double _standardDeviation(List<int> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  CalibrationTimeline fetchCalibrationTimeline({
    Duration window = const Duration(hours: 3),
    String? remoteId,
  }) {
    final db = _requireDb();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final startMs = nowMs - window.inMilliseconds;
    final rows = db.select(
      '''
      SELECT wall_time_ms,
             heart_rate_x10,
             hrv_rmssd_ms,
             spo2_percent,
             quality_flags,
             hr_confidence,
             calibration_progress
      FROM live_records lr
      WHERE lr.wall_time_ms >= ?
        ${_remoteFilter('lr', remoteId)}
      ORDER BY wall_time_ms ASC
      ''',
      [startMs, ?remoteId],
    );

    final points = <CalibrationTimelinePoint>[];
    final marks = <CalibrationUpdateMark>[];
    int? previousProgress;
    int? latestProgress;

    for (final row in rows) {
      final timeMs = row['wall_time_ms'] as int;
      final hrX10 = row['heart_rate_x10'] as int?;
      final rmssd = (row['hrv_rmssd_ms'] as num?)?.toDouble();
      final spo2 = row['spo2_percent'] as int?;
      final quality = row['quality_flags'] as int? ?? 0;
      final hrConfidence = row['hr_confidence'] as int?;
      final progress = row['calibration_progress'] as int?;
      final motionArtifact = quality & 0x02 != 0;
      final lowPerfusion = quality & 0x04 != 0;
      final clipping = quality & 0x20 != 0;
      final trusted =
          (hrConfidence ?? 0) >= 55 &&
          !motionArtifact &&
          !lowPerfusion &&
          !clipping;
      // Use the firmware's beat-to-beat RMSSD directly rather than deriving it
      // from the smoothed once-per-second IBI trend.
      final hrvRmssd = trusted && rmssd != null && rmssd > 0 ? rmssd : null;

      if (progress != null) {
        latestProgress = progress;
        final warmupCompleted =
            previousProgress != null && previousProgress < 30 && progress >= 30;
        final hourlyUpdate =
            previousProgress != null &&
            previousProgress >= 30 &&
            progress > previousProgress;
        if (warmupCompleted || hourlyUpdate) {
          marks.add(
            CalibrationUpdateMark(
              time: DateTime.fromMillisecondsSinceEpoch(timeMs),
              progress: progress,
            ),
          );
        }
        previousProgress = progress;
      }

      points.add(
        CalibrationTimelinePoint(
          time: DateTime.fromMillisecondsSinceEpoch(timeMs),
          heartRateBpm: hrX10 == null ? null : hrX10 / 10.0,
          spo2Percent: spo2,
          hrvRmssdMs: hrvRmssd,
          calibrationProgress: progress,
        ),
      );
    }

    final sampledPoints = _downsampleCalibrationPoints(points, maxPoints: 360);
    final nextUpdateAt = _estimateNextCalibrationUpdate(
      points: points,
      marks: marks,
      latestProgress: latestProgress,
    );
    final nextUpdateRemaining = nextUpdateAt == null
        ? null
        : nextUpdateAt.isBefore(now)
        ? Duration.zero
        : nextUpdateAt.difference(now);

    return CalibrationTimeline(
      points: sampledPoints,
      updateMarks: marks,
      nextUpdateAt: nextUpdateAt,
      nextUpdateRemaining: nextUpdateRemaining,
      latestProgress: latestProgress,
    );
  }

  List<CalibrationTimelinePoint> _downsampleCalibrationPoints(
    List<CalibrationTimelinePoint> points, {
    required int maxPoints,
  }) {
    if (points.length <= maxPoints) {
      return List.unmodifiable(points);
    }
    final stride = (points.length / maxPoints).ceil();
    final sampled = <CalibrationTimelinePoint>[];
    for (var i = 0; i < points.length; i += stride) {
      sampled.add(points[i]);
    }
    if (sampled.last.time != points.last.time) {
      sampled.add(points.last);
    }
    return List.unmodifiable(sampled);
  }

  DateTime? _estimateNextCalibrationUpdate({
    required List<CalibrationTimelinePoint> points,
    required List<CalibrationUpdateMark> marks,
    required int? latestProgress,
  }) {
    if (points.isEmpty || latestProgress == null || latestProgress >= 100) {
      return null;
    }

    final latestTime = points.last.time;
    if (latestProgress < 30) {
      final elapsedMs =
          (latestProgress / 30.0) * const Duration(minutes: 2).inMilliseconds;
      final estimatedStart = latestTime.subtract(
        Duration(milliseconds: elapsedMs.round()),
      );
      return estimatedStart.add(const Duration(minutes: 2));
    }

    return null;
  }

  List<Map<String, Object?>> _selectMaps(
    Database db,
    String sql,
    List<Object?> args,
  ) {
    final rows = db.select(sql, args);
    return [
      for (final row in rows) {for (final key in row.keys) key: row[key]},
    ];
  }

  Map<String, Object?> _decorateLiveRecord(Map<String, Object?> row) {
    final qualityFlags = row['quality_flags'] as int? ?? 0;
    final hrX10 = row['heart_rate_x10'] as int?;
    return {
      ...row,
      'received_at_iso': _isoFromMs(row['received_at_ms']),
      'wall_time_iso': _isoFromMs(row['wall_time_ms']),
      'heart_rate_bpm': hrX10 == null ? null : hrX10 / 10.0,
      'quality_labels': _qualityLabels(qualityFlags),
    };
  }

  Map<String, Object?> _decorateRawPpgFrame(Map<String, Object?> row) {
    final payloadHex = row['payload_hex'] as String? ?? '';
    return {
      ...row,
      'received_at_iso': _isoFromMs(row['received_at_ms']),
      'payload_summary': _ppgPayloadSummary(payloadHex),
    };
  }

  String? _isoFromMs(Object? value) {
    if (value is! int) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
  }

  List<String> _qualityLabels(int flags) {
    final labels = <String>[];
    if (flags & 0x01 != 0) {
      labels.add('skin_contact');
    }
    if (flags & 0x02 != 0) {
      labels.add('motion_artifact');
    }
    if (flags & 0x04 != 0) {
      labels.add('low_perfusion');
    }
    if (flags & 0x08 != 0) {
      labels.add('puck_changed');
    }
    if (flags & 0x10 != 0) {
      labels.add('battery_low');
    }
    if (flags & 0x20 != 0) {
      labels.add('ppg_clipping');
    }
    if (flags & 0x40 != 0) {
      labels.add('uncalibrated');
    }
    return labels;
  }

  Map<String, Object?> _ppgPayloadSummary(String payloadHex) {
    final bytes = _hexToBytes(payloadHex);
    final channels = <int, _PpgChannelStats>{};
    var malformedTailBytes = bytes.length % 3;

    for (var i = 0; i + 2 < bytes.length; i += 3) {
      final tag = bytes[i] >> 3;
      final value =
          ((bytes[i] & 0x07) << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      channels.putIfAbsent(tag, _PpgChannelStats.new).add(value);
    }

    return {
      'payload_bytes': bytes.length,
      'malformed_tail_bytes': malformedTailBytes,
      'legacy': channels[0]?.toJson(),
      'green': channels[1]?.toJson(),
      'ir': channels[2]?.toJson(),
      'red': channels[3]?.toJson(),
      'unknown_tags': {
        for (final entry in channels.entries)
          if (entry.key > 3) entry.key.toString(): entry.value.toJson(),
      },
    };
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte != null) {
        bytes.add(byte);
      }
    }
    return bytes;
  }

  int _countDaysWithCleanIbi(Database db, {String? remoteId}) {
    final rows = db.select(
      '''
      SELECT date(wall_time_ms / 1000, 'unixepoch') AS day, COUNT(*) AS count
      FROM live_records lr
      WHERE lr.ibi_ms IS NOT NULL
        AND COALESCE(lr.hr_confidence, 0) >= 55
        AND (lr.quality_flags & 0x26) = 0
        ${_remoteFilter('lr', remoteId)}
      GROUP BY day
      HAVING count >= 120
    ''',
      [?remoteId],
    );
    return rows.length;
  }

  DateTime? _dateFromMs(Object? value) {
    if (value is! int) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  String _defaultDeviceDisplayName(String advertisedName, String remoteId) {
    final trimmed = advertisedName.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final suffix = remoteId.length <= 4
        ? remoteId
        : remoteId.substring(remoteId.length - 4);
    return 'OpenPulse $suffix';
  }

  String _updatedDeviceDisplayName({
    required String currentDisplayName,
    required String currentAdvertisedName,
    required String nextAdvertisedName,
    required String defaultName,
  }) {
    final next = nextAdvertisedName.trim();
    if (currentDisplayName.isEmpty ||
        currentDisplayName == currentAdvertisedName ||
        (currentDisplayName == 'OpenPulse' && next.startsWith('OpenPulse '))) {
      return defaultName;
    }
    return currentDisplayName;
  }

  String _remoteFilter(String tableAlias, String? remoteId) {
    if (remoteId == null || remoteId.isEmpty) {
      return '';
    }
    return '''
      AND EXISTS (
        SELECT 1
        FROM device_sessions ds
        WHERE ds.id = $tableAlias.session_id
          AND ds.remote_id = ?
      )
    ''';
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

class _PpgChannelStats {
  int count = 0;
  int? min;
  int? max;
  int sum = 0;
  final List<int> firstSamples = [];
  final List<int> lastSamples = [];

  void add(int value) {
    count++;
    min = min == null ? value : math.min(min!, value);
    max = max == null ? value : math.max(max!, value);
    sum += value;
    if (firstSamples.length < 12) {
      firstSamples.add(value);
    }
    lastSamples.add(value);
    if (lastSamples.length > 12) {
      lastSamples.removeAt(0);
    }
  }

  Map<String, Object?> toJson() {
    return {
      'count': count,
      'min': min,
      'max': max,
      'mean': count == 0 ? null : sum / count,
      'first_samples': firstSamples,
      'last_samples': lastSamples,
    };
  }
}
