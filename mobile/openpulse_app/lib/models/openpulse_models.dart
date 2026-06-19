enum ConnectionPhase {
  disconnected,
  scanning,
  connecting,
  discovering,
  timeSyncing,
  streaming,
  reconnecting,
  bluetoothUnavailable,
  error,
}

extension ConnectionPhaseLabel on ConnectionPhase {
  String get label {
    switch (this) {
      case ConnectionPhase.disconnected:
        return 'Disconnected';
      case ConnectionPhase.scanning:
        return 'Scanning';
      case ConnectionPhase.connecting:
        return 'Connecting';
      case ConnectionPhase.discovering:
        return 'Discovering GATT';
      case ConnectionPhase.timeSyncing:
        return 'Time sync';
      case ConnectionPhase.streaming:
        return 'Live';
      case ConnectionPhase.reconnecting:
        return 'Reconnect';
      case ConnectionPhase.bluetoothUnavailable:
        return 'Bluetooth unavailable';
      case ConnectionPhase.error:
        return 'Error';
    }
  }
}

enum DeviceMode {
  standby(0, 'Standby'),
  active(1, 'Active'),
  lowPower(2, 'Low Power'),
  hrOnly(3, 'HR only'),
  shipMode(4, 'Ship');

  const DeviceMode(this.value, this.label);

  final int value;
  final String label;
}

class DeviceInformation {
  const DeviceInformation({
    this.manufacturer,
    this.model,
    this.firmware,
    this.hardware,
  });

  final String? manufacturer;
  final String? model;
  final String? firmware;
  final String? hardware;
}

class BatterySample {
  const BatterySample({
    required this.receivedAt,
    required this.level,
    required this.available,
  });

  final DateTime receivedAt;
  final int? level;
  final bool available;

  String get display => available && level != null ? '$level%' : 'Unavailable';
}

class DaySummary {
  const DaySummary({
    required this.day,
    required this.liveRecords,
    required this.rawPpgFrames,
    required this.puckEvents,
    required this.controlWrites,
    required this.maxSteps,
    required this.lastLiveAt,
    required this.lastRawAt,
  });

  final DateTime day;
  final int liveRecords;
  final int rawPpgFrames;
  final int puckEvents;
  final int controlWrites;
  final int? maxSteps;
  final DateTime? lastLiveAt;
  final DateTime? lastRawAt;

  bool get hasData => liveRecords > 0 || rawPpgFrames > 0 || puckEvents > 0;
}

class HrvSummary {
  const HrvSummary({
    required this.rmssdMs,
    required this.sdnnMs,
    required this.cleanIbiCount,
    required this.rejectedIbiCount,
    required this.windowDuration,
    required this.confidence,
    required this.calibrationProgress,
    required this.status,
  });

  final double? rmssdMs;
  final double? sdnnMs;
  final int cleanIbiCount;
  final int rejectedIbiCount;
  final Duration windowDuration;
  final int confidence;
  final int calibrationProgress;
  final String status;

  bool get available => rmssdMs != null && cleanIbiCount >= 8;
}

class PuckStatus {
  const PuckStatus({
    required this.receivedAt,
    required this.eventType,
    required this.puckKind,
    required this.attached,
    required this.sensorStatus,
  });

  final DateTime receivedAt;
  final int eventType;
  final int puckKind;
  final bool attached;
  final int sensorStatus;

  String get puckLabel {
    switch (puckKind) {
      case 1:
        return 'PPG MAXM86161';
      case 2:
        return 'EDA + temperature';
      case 3:
        return 'ECG spot';
      default:
        return 'Unknown puck';
    }
  }

  String get eventLabel {
    switch (eventType) {
      case 1:
        return 'Attached';
      case 2:
        return 'Removed';
      case 3:
        return 'Calibration started';
      case 4:
        return 'Calibration complete';
      case 5:
        return 'Fault';
      default:
        return 'Unknown';
    }
  }

  String get sensorLabel {
    switch (sensorStatus) {
      case 0:
        return 'OK';
      case 1:
        return 'Unavailable';
      case 2:
        return 'I2C not ready';
      case 3:
        return 'Unexpected part ID';
      default:
        return 'Status $sensorStatus';
    }
  }
}

class LiveRecord {
  const LiveRecord({
    required this.receivedAt,
    required this.wallTime,
    required this.deviceUptimeMs,
    required this.sequence,
    required this.heartRateBpm,
    required this.ibiMs,
    required this.accelMilliG,
    required this.spo2Percent,
    required this.qualityFlags,
    required this.stepCount,
    required this.motionStatus,
    required this.hrConfidence,
    required this.spo2Confidence,
    required this.calibrationProgress,
  });

  final DateTime receivedAt;
  final DateTime wallTime;
  final int deviceUptimeMs;
  final int sequence;
  final double? heartRateBpm;
  final int? ibiMs;
  final int? accelMilliG;
  final int? spo2Percent;
  final int qualityFlags;
  final int? stepCount;
  final int? motionStatus;
  final int? hrConfidence;
  final int? spo2Confidence;
  final int? calibrationProgress;

  bool get hasSkinContact => qualityFlags & 0x01 != 0;
  bool get hasMotionArtifact => qualityFlags & 0x02 != 0;
  bool get hasLowPerfusion => qualityFlags & 0x04 != 0;
  bool get puckChanged => qualityFlags & 0x08 != 0;
  bool get batteryLow => qualityFlags & 0x10 != 0;
  bool get hasPpgClipping => qualityFlags & 0x20 != 0;
  bool get isUncalibrated => qualityFlags & 0x40 != 0;
  bool get motionAvailable => motionStatus == 0;

  String get hrConfidenceLabel => _confidenceLabel(hrConfidence);
  String get spo2ConfidenceLabel => _confidenceLabel(spo2Confidence);

  String get motionLabel {
    switch (motionStatus) {
      case 0:
        return 'OK';
      case 1:
        return 'Unavailable';
      case null:
        return 'Not reported';
      default:
        return 'Status $motionStatus';
    }
  }

  String get qualityLabel {
    if (puckChanged) {
      return 'Puck changed';
    }
    if (hasMotionArtifact) {
      return 'Motion artifact';
    }
    if (hasLowPerfusion) {
      return 'Low perfusion';
    }
    if (hasPpgClipping) {
      return 'PPG clipping';
    }
    if (isUncalibrated) {
      return 'Calibrating';
    }
    if (hasSkinContact) {
      return 'Skin contact';
    }
    return 'No quality flag';
  }

  static String _confidenceLabel(int? confidence) {
    if (confidence == null || confidence <= 0) {
      return 'No confidence';
    }
    if (confidence >= 90) {
      return '$confidence% high';
    }
    if (confidence >= 65) {
      return '$confidence% medium';
    }
    return '$confidence% low';
  }
}

class ParsedLiveFrame {
  const ParsedLiveFrame({
    required this.sequence,
    required this.records,
    required this.lastDeviceUptimeMs,
  });

  final int sequence;
  final List<LiveRecord> records;
  final int lastDeviceUptimeMs;
}

class ControlAck {
  const ControlAck({
    required this.receivedAt,
    required this.command,
    required this.status,
    required this.mode,
  });

  final DateTime receivedAt;
  final int command;
  final int status;
  final int mode;

  bool get ok => status == 0;

  String get commandLabel {
    switch (command) {
      case 0x01:
        return 'Time sync';
      case 0x02:
        return 'Set mode';
      case 0x03:
        return 'Set sampling';
      case 0x04:
        return 'Set LED';
      case 0x05:
        return 'Request backfill';
      case 0x06:
        return 'Request raw PPG';
      case 0x07:
        return 'Ship mode';
      default:
        return 'Command 0x${command.toRadixString(16).padLeft(2, '0')}';
    }
  }

  String get statusLabel => ok ? 'OK' : 'Rejected';
}

class BulkBackfillFrame {
  const BulkBackfillFrame({
    required this.receivedAt,
    required this.recordKind,
    required this.sequence,
    required this.payloadLength,
    required this.payloadHex,
  });

  final DateTime receivedAt;
  final int recordKind;
  final int sequence;
  final int payloadLength;
  final String payloadHex;

  String get kindLabel {
    switch (recordKind) {
      case 1:
        return '1-minute aggregate';
      case 2:
        return 'IBI night window';
      case 3:
        return 'Clean shutdown marker';
      case 4:
        return 'Gap marker';
      default:
        return 'Kind $recordKind';
    }
  }
}

class RawPpgFrame {
  const RawPpgFrame({
    required this.receivedAt,
    required this.sequence,
    required this.requestedSeconds,
    required this.attached,
    required this.sensorStatus,
    required this.payloadLength,
    required this.payloadHex,
    required this.samples,
  });

  final DateTime receivedAt;
  final int sequence;
  final int? requestedSeconds;
  final bool? attached;
  final int? sensorStatus;
  final int payloadLength;
  final String payloadHex;
  final List<int> samples;

  String get sensorLabel {
    switch (sensorStatus) {
      case null:
        return 'Raw payload';
      case 0:
        return 'OK';
      case 1:
        return 'Unavailable';
      case 2:
        return 'I2C not ready';
      case 3:
        return 'Unexpected part ID';
      default:
        return 'Status $sensorStatus';
    }
  }

  String get previewHex {
    if (payloadHex.length <= 48) {
      return payloadHex;
    }
    return '${payloadHex.substring(0, 48)}...';
  }
}
