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
        FOREIGN KEY(session_id) REFERENCES device_sessions(id)
      );
    ''');
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
        quality_flags
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
