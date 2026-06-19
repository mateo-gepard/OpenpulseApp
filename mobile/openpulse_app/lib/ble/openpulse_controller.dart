import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/openpulse_models.dart';
import '../notifications/openpulse_notifications.dart';
import '../storage/openpulse_storage.dart';
import 'openpulse_ble_contract.dart';

class OpenPulseController extends ChangeNotifier {
  OpenPulseController(this.storage, {OpenPulseNotifications? notifications})
    : notifications = notifications ?? OpenPulseNotifications();

  static const _connectTimeout = Duration(seconds: 16);
  static const _reconnectDelay = Duration(seconds: 2);
  static const _scanDuration = Duration(seconds: 10);

  final OpenPulseStorage storage;
  final OpenPulseNotifications notifications;

  ConnectionPhase phase = ConnectionPhase.disconnected;
  String statusMessage = 'Ready to scan for real OpenPulse hardware.';
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  DeviceInformation deviceInformation = const DeviceInformation();
  BatterySample? latestBattery;
  PuckStatus? latestPuckStatus;
  LiveRecord? latestLiveRecord;
  ControlAck? latestControlAck;
  BulkBackfillFrame? latestBackfillFrame;
  RawPpgFrame? latestRawPpgFrame;
  int livePacketCount = 0;
  int rawPpgPacketCount = 0;
  int latestLiveFrameByteCount = 0;
  String? latestLiveFrameHex;
  List<LiveRecord> recentLiveRecords = const [];
  List<int> recentRawPpgSamples = const [];
  DateTime selectedDay = DateTime.now();
  DaySummary? selectedDaySummary;
  HrvSummary? latestHrvSummary;
  CalibrationTimeline? calibrationTimeline;
  DeviceMode selectedMode = DeviceMode.active;
  int samplingHz = 64;
  int ledGreenMa = 12;
  int ledRedMa = 8;
  int ledIrMa = 8;
  int stepGoal = 10000;
  bool rawPpgDiagnosticEnabled = false;
  bool storageReady = false;
  bool notificationsReady = false;
  bool notificationPermissionGranted = false;
  bool gattReady = false;
  bool customServiceReady = false;
  bool batteryServiceReady = false;
  bool deviceInfoReady = false;
  bool controlNotifyReady = false;
  bool bulkBackfillReady = false;
  bool rawPpgReady = false;
  bool stepGoalNotified = false;
  bool deviceRestoreInProgress = false;
  int deviceRestoreRecordCount = 0;
  DateTime? lastDeviceRestoreAt;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _live;
  BluetoothCharacteristic? _bulk;
  BluetoothCharacteristic? _raw;
  BluetoothCharacteristic? _puck;
  BluetoothCharacteristic? _battery;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _valueSubscriptions = [];
  bool _intentionalDisconnect = false;
  bool _connectInFlight = false;
  bool _gattSetupInFlight = false;
  int? _sessionId;
  int _lastDeviceUptimeMs = 0;
  int _syncedUnixMs = 0;
  int _syncedDeviceUptimeMs = 0;
  Timer? _rawPollTimer;
  Timer? _autoScanRetryTimer;
  int? _savedSamplingHzBeforeRaw;
  int? _savedLedGreenMaBeforeRaw;
  int? _savedLedRedMaBeforeRaw;
  int? _savedLedIrMaBeforeRaw;

  int? get currentStepCount => latestLiveRecord?.stepCount;

  bool get stepGoalReached {
    final steps = currentStepCount;
    return steps != null && steps >= stepGoal;
  }

  String? get deviceName {
    final device = _device;
    if (device == null) {
      return null;
    }
    final platformName = device.platformName;
    if (platformName.isNotEmpty) {
      return platformName;
    }
    final advName = device.advName;
    return advName.isNotEmpty ? advName : OpenPulseBleContract.advertisedName;
  }

  Future<void> initialize() async {
    try {
      await storage.open();
      storageReady = true;
      _refreshSelectedDay();
      _refreshHrvSummary();
      _refreshCalibrationTimeline();
      try {
        await notifications.initialize();
        notificationsReady = notifications.ready;
        notificationPermissionGranted = notifications.permissionGranted;
      } catch (_) {
        notificationsReady = false;
        notificationPermissionGranted = false;
      }
      await FlutterBluePlus.setOptions(
        showPowerAlert: true,
        restoreState: false,
      );
      adapterState = FlutterBluePlus.adapterStateNow;
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        adapterState = state;
        if (state == BluetoothAdapterState.on &&
            phase == ConnectionPhase.disconnected &&
            !_intentionalDisconnect) {
          unawaited(
            _restoreExistingConnection().then((restored) {
              if (!restored) {
                _scheduleScanRetry(Duration.zero);
              }
            }),
          );
        }
        notifyListeners();
      });
      notifyListeners();
      if (adapterState == BluetoothAdapterState.on) {
        final restored = await _restoreExistingConnection();
        if (!restored) {
          _scheduleScanRetry(Duration.zero);
        }
      }
    } catch (error) {
      _setPhase(
        ConnectionPhase.error,
        'Storage/BLE initialization failed: $error',
      );
    }
  }

  Future<void> scanAndConnect() async {
    if (_connectInFlight) {
      return;
    }
    _autoScanRetryTimer?.cancel();
    _autoScanRetryTimer = null;
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _setPhase(
        ConnectionPhase.bluetoothUnavailable,
        'This device does not report Bluetooth LE support.',
      );
      return;
    }
    final state = FlutterBluePlus.adapterStateNow;
    if (state != BluetoothAdapterState.on) {
      _setPhase(
        ConnectionPhase.bluetoothUnavailable,
        'Bluetooth is ${state.name}. Turn it on and grant permission.',
      );
      _scheduleScanRetry();
      return;
    }

    _intentionalDisconnect = false;
    _setPhase(ConnectionPhase.scanning, 'Scanning for OpenPulse advertising.');
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // A stale platform scan should not block a fresh foreground scan.
    }
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      _handleScanResults,
      onError: (Object error) {
        _setPhase(ConnectionPhase.error, 'BLE scan failed: $error');
        _scheduleScanRetry();
      },
    );

    try {
      await FlutterBluePlus.startScan(timeout: _scanDuration);
    } catch (error) {
      _setPhase(ConnectionPhase.error, 'BLE scan failed: $error');
      _scheduleScanRetry();
      return;
    }
    await Future<void>.delayed(
      _scanDuration + const Duration(milliseconds: 300),
    );
    if (phase == ConnectionPhase.scanning) {
      _setPhase(
        ConnectionPhase.disconnected,
        'No OpenPulse advertisement found yet.',
      );
      _scheduleScanRetry();
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _autoScanRetryTimer?.cancel();
    _autoScanRetryTimer = null;
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _device?.disconnect();
    _clearGatt();
    _setPhase(ConnectionPhase.disconnected, 'Disconnected.');
  }

  Future<void> writeMode(DeviceMode mode) async {
    selectedMode = mode;
    await _writeControl(OpenPulseBleContract.buildSetMode(mode));
    notifyListeners();
  }

  Future<void> writeSampling(int hz) async {
    samplingHz = hz;
    await _writeControl(OpenPulseBleContract.buildSetSampling(hz));
    notifyListeners();
  }

  Future<void> writeLed({
    required int greenMa,
    required int redMa,
    required int irMa,
  }) async {
    ledGreenMa = greenMa;
    ledRedMa = redMa;
    ledIrMa = irMa;
    await _writeControl(
      OpenPulseBleContract.buildSetLedCurrent(
        greenMa: greenMa,
        redMa: redMa,
        irMa: irMa,
      ),
    );
    notifyListeners();
  }

  void setStepGoal(int goal) {
    stepGoal = goal.clamp(10, 100000).toInt();
    final steps = currentStepCount;
    if (steps == null || steps < stepGoal) {
      stepGoalNotified = false;
    } else {
      _notifyStepGoalIfNeeded(steps);
    }
    notifyListeners();
  }

  void selectPreviousDay() {
    selectedDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day - 1,
    );
    _refreshSelectedDay();
    _refreshHrvSummary();
    notifyListeners();
  }

  void selectNextDay() {
    final today = DateTime.now();
    final next = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day + 1,
    );
    if (DateTime(
      next.year,
      next.month,
      next.day,
    ).isAfter(DateTime(today.year, today.month, today.day))) {
      return;
    }
    selectedDay = next;
    _refreshSelectedDay();
    notifyListeners();
  }

  Future<void> requestBackfill({bool fullDeviceRestore = false}) async {
    if (fullDeviceRestore) {
      deviceRestoreInProgress = true;
      deviceRestoreRecordCount = 0;
      statusMessage = 'Restoring phone cache from OpenPulse.';
      notifyListeners();
    }
    await _writeControl(
      OpenPulseBleContract.buildRequestBackfill(
        fullDeviceRestore ? 0 : _lastDeviceUptimeMs,
      ),
    );
  }

  Future<void> restoreDeviceLocalData() async {
    if (!bulkBackfillReady) {
      return;
    }
    await requestBackfill(fullDeviceRestore: true);
  }

  Future<void> requestRawPpgWindow({int seconds = 1}) async {
    await _writeControl(OpenPulseBleContract.buildRequestRawWindow(seconds));
  }

  Future<void> startRawPpgDiagnostics() async {
    if (!customServiceReady || !rawPpgReady) {
      return;
    }
    if (rawPpgDiagnosticEnabled) {
      return;
    }

    _savedSamplingHzBeforeRaw = samplingHz;
    _savedLedGreenMaBeforeRaw = ledGreenMa;
    _savedLedRedMaBeforeRaw = ledRedMa;
    _savedLedIrMaBeforeRaw = ledIrMa;
    rawPpgDiagnosticEnabled = true;
    recentRawPpgSamples = const [];
    latestRawPpgFrame = null;
    notifyListeners();

    try {
      final diagnosticGreenMa = ledGreenMa < 16 ? 16 : ledGreenMa;
      final diagnosticRedMa = ledRedMa < 8 ? 8 : ledRedMa;
      final diagnosticIrMa = ledIrMa < 8 ? 8 : ledIrMa;
      await writeSampling(128);
      await writeLed(
        greenMa: diagnosticGreenMa,
        redMa: diagnosticRedMa,
        irMa: diagnosticIrMa,
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await requestRawPpgWindow(seconds: 1);
      _rawPollTimer?.cancel();
      _rawPollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (rawPpgDiagnosticEnabled &&
            phase == ConnectionPhase.streaming &&
            customServiceReady) {
          unawaited(requestRawPpgWindow(seconds: 1));
        }
      });
    } catch (error) {
      rawPpgDiagnosticEnabled = false;
      statusMessage = 'Raw PPG diagnostic could not start: $error';
      notifyListeners();
    }
  }

  Future<void> stopRawPpgDiagnostics() async {
    if (!rawPpgDiagnosticEnabled && _rawPollTimer == null) {
      return;
    }
    _rawPollTimer?.cancel();
    _rawPollTimer = null;
    rawPpgDiagnosticEnabled = false;
    notifyListeners();

    if (!customServiceReady) {
      _clearSavedRawSettings();
      return;
    }

    try {
      await requestRawPpgWindow(seconds: 0);
      final previousSamplingHz = _savedSamplingHzBeforeRaw;
      final previousGreenMa = _savedLedGreenMaBeforeRaw;
      final previousRedMa = _savedLedRedMaBeforeRaw;
      final previousIrMa = _savedLedIrMaBeforeRaw;
      if (previousSamplingHz != null) {
        await writeSampling(previousSamplingHz);
      }
      if (previousGreenMa != null &&
          previousRedMa != null &&
          previousIrMa != null) {
        await writeLed(
          greenMa: previousGreenMa,
          redMa: previousRedMa,
          irMa: previousIrMa,
        );
      }
      statusMessage = 'Raw PPG diagnostic stopped.';
    } catch (_) {
      // Raw PPG can fail independently; puck status remains the hardware truth.
    } finally {
      _clearSavedRawSettings();
      notifyListeners();
    }
  }

  Future<void> enterShipMode() async {
    selectedMode = DeviceMode.shipMode;
    await _writeControl(OpenPulseBleContract.buildEnterShipMode());
    notifyListeners();
  }

  void _handleScanResults(List<ScanResult> results) {
    if (_connectInFlight || phase != ConnectionPhase.scanning) {
      return;
    }
    for (final result in results) {
      final advName = result.advertisementData.advName;
      final serviceUuids = result.advertisementData.serviceUuids;
      final device = result.device;
      final isOpenPulse =
          advName == OpenPulseBleContract.advertisedName ||
          device.advName == OpenPulseBleContract.advertisedName ||
          device.platformName == OpenPulseBleContract.advertisedName ||
          serviceUuids.any(
            (uuid) => OpenPulseBleContract.uuidMatches(
              uuid,
              OpenPulseBleContract.serviceUuid,
            ),
          );
      if (isOpenPulse) {
        _autoScanRetryTimer?.cancel();
        _autoScanRetryTimer = null;
        unawaited(FlutterBluePlus.stopScan());
        unawaited(_connect(result.device));
        return;
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    _connectInFlight = true;
    _device = device;
    _setPhase(ConnectionPhase.connecting, 'Connecting to OpenPulse.');
    var retryNeeded = false;
    try {
      await _listenToDeviceConnection(device);

      await device.connect(
        license: License.nonprofit,
        timeout: _connectTimeout,
        mtu: null,
      );
      await device.connectionState
          .where((state) => state == BluetoothConnectionState.connected)
          .first
          .timeout(
            _connectTimeout,
            onTimeout: () =>
                throw TimeoutException('OpenPulse did not connect in time.'),
          );
      retryNeeded = !await _setupConnectedDevice(device);
    } catch (error) {
      _clearGatt();
      _setPhase(ConnectionPhase.error, 'BLE connection failed: $error');
      retryNeeded = true;
    } finally {
      _connectInFlight = false;
      if (retryNeeded && !_intentionalDisconnect) {
        _scheduleScanRetry();
      }
    }
  }

  Future<void> _listenToDeviceConnection(BluetoothDevice device) async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected &&
          !_intentionalDisconnect &&
          !_connectInFlight &&
          !_gattSetupInFlight &&
          phase != ConnectionPhase.streaming) {
        unawaited(_setupConnectedDevice(device, restored: true));
      } else if (state == BluetoothConnectionState.disconnected &&
          !_intentionalDisconnect &&
          !_connectInFlight) {
        _handleUnexpectedDisconnect();
      }
    });
  }

  Future<bool> _restoreExistingConnection() async {
    if (_intentionalDisconnect ||
        _connectInFlight ||
        _gattSetupInFlight ||
        phase == ConnectionPhase.streaming) {
      return phase == ConnectionPhase.streaming;
    }

    final candidates = <String, BluetoothDevice>{};
    for (final device in FlutterBluePlus.connectedDevices) {
      candidates[device.remoteId.toString()] = device;
    }
    try {
      final systemDevices = await FlutterBluePlus.systemDevices([
        OpenPulseBleContract.serviceUuid,
      ]);
      for (final device in systemDevices) {
        candidates[device.remoteId.toString()] = device;
      }
    } catch (_) {
      // Some iOS restoration paths only expose app-connected devices.
    }

    for (final device in candidates.values) {
      final likelyOpenPulse =
          device.advName == OpenPulseBleContract.advertisedName ||
          device.platformName == OpenPulseBleContract.advertisedName ||
          candidates.length == 1;
      if (!likelyOpenPulse) {
        continue;
      }
      _intentionalDisconnect = false;
      _device = device;
      await _listenToDeviceConnection(device);
      if (await device.connectionState.first ==
          BluetoothConnectionState.connected) {
        return _setupConnectedDevice(device, restored: true);
      }
    }

    return false;
  }

  Future<bool> _setupConnectedDevice(
    BluetoothDevice device, {
    bool restored = false,
  }) async {
    if (_gattSetupInFlight || _intentionalDisconnect) {
      return false;
    }
    _gattSetupInFlight = true;
    _device = device;
    try {
      await FlutterBluePlus.stopScan();
      _setPhase(
        ConnectionPhase.discovering,
        restored
            ? 'OpenPulse reconnected. Restoring GATT.'
            : 'Discovering OpenPulse GATT.',
      );
      try {
        await device.requestMtu(247);
      } catch (_) {
        // iOS negotiates MTU internally; Android may honor this request.
      }

      final services = await device.discoverServices();
      _bindServices(services);
      gattReady = true;

      deviceInformation = await _readDeviceInformation(services);
      deviceInfoReady = true;
      _sessionId = storage.insertSession(
        remoteId: device.remoteId.toString(),
        deviceName: deviceName ?? OpenPulseBleContract.advertisedName,
        information: deviceInformation,
      );

      await _readInitialControlState();
      await _readInitialBattery();
      await _readInitialPuckStatus();
      await _subscribeToNotifications();
      await _timeSync();
      await restoreDeviceLocalData();

      _setPhase(ConnectionPhase.streaming, 'OpenPulse is connected and live.');
      return true;
    } catch (error) {
      _clearGatt();
      _setPhase(
        ConnectionPhase.error,
        restored ? 'BLE resume failed: $error' : 'BLE setup failed: $error',
      );
      if (!_connectInFlight) {
        _scheduleScanRetry();
      }
      return false;
    } finally {
      _gattSetupInFlight = false;
    }
  }

  void _bindServices(List<BluetoothService> services) {
    customServiceReady = false;
    batteryServiceReady = false;
    _control = null;
    _live = null;
    _bulk = null;
    _raw = null;
    _puck = null;
    _battery = null;
    controlNotifyReady = false;
    bulkBackfillReady = false;
    rawPpgReady = false;

    for (final service in services) {
      if (OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.serviceUuid,
      )) {
        customServiceReady = true;
        for (final characteristic in service.characteristics) {
          if (OpenPulseBleContract.uuidMatches(
            characteristic.uuid,
            OpenPulseBleContract.controlUuid,
          )) {
            _control = characteristic;
          } else if (OpenPulseBleContract.uuidMatches(
            characteristic.uuid,
            OpenPulseBleContract.liveStreamUuid,
          )) {
            _live = characteristic;
          } else if (OpenPulseBleContract.uuidMatches(
            characteristic.uuid,
            OpenPulseBleContract.bulkBackfillUuid,
          )) {
            _bulk = characteristic;
            bulkBackfillReady =
                characteristic.properties.notify ||
                characteristic.properties.indicate;
          } else if (OpenPulseBleContract.uuidMatches(
            characteristic.uuid,
            OpenPulseBleContract.rawPpgUuid,
          )) {
            _raw = characteristic;
            rawPpgReady = characteristic.properties.notify;
          } else if (OpenPulseBleContract.uuidMatches(
            characteristic.uuid,
            OpenPulseBleContract.puckStatusUuid,
          )) {
            _puck = characteristic;
          }
        }
      } else if (OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.batteryService,
      )) {
        batteryServiceReady = true;
        _battery = _findCharacteristic(
          service,
          OpenPulseBleContract.batteryLevelCharacteristic,
        );
      }
    }

    if (_control == null || _live == null || _puck == null) {
      throw StateError('OpenPulse custom service is incomplete.');
    }
  }

  BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    String uuid,
  ) {
    for (final characteristic in service.characteristics) {
      if (OpenPulseBleContract.uuidMatches(characteristic.uuid, uuid)) {
        return characteristic;
      }
    }
    return null;
  }

  Future<DeviceInformation> _readDeviceInformation(
    List<BluetoothService> services,
  ) async {
    String? manufacturer;
    String? model;
    String? firmware;
    String? hardware;

    for (final service in services) {
      if (!OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.deviceInformationService,
      )) {
        continue;
      }
      Future<String?> readCharacteristic(String uuid) async {
        final characteristic = _findCharacteristic(service, uuid);
        if (characteristic == null || !characteristic.properties.read) {
          return null;
        }
        final bytes = await characteristic.read();
        return utf8.decode(bytes, allowMalformed: true);
      }

      manufacturer = await readCharacteristic(
        OpenPulseBleContract.manufacturerCharacteristic,
      );
      model = await readCharacteristic(
        OpenPulseBleContract.modelCharacteristic,
      );
      firmware = await readCharacteristic(
        OpenPulseBleContract.firmwareCharacteristic,
      );
      hardware = await readCharacteristic(
        OpenPulseBleContract.hardwareCharacteristic,
      );
      break;
    }

    return DeviceInformation(
      manufacturer: manufacturer,
      model: model,
      firmware: firmware,
      hardware: hardware,
    );
  }

  Future<void> _readInitialControlState() async {
    final control = _control;
    if (control == null || !control.properties.read) {
      return;
    }
    final bytes = await control.read();
    _lastDeviceUptimeMs = OpenPulseBleContract.parseControlDeviceUptime(bytes);
  }

  Future<void> _readInitialBattery() async {
    final battery = _battery;
    if (battery == null || !battery.properties.read) {
      latestBattery = BatterySample(
        receivedAt: DateTime.now(),
        level: null,
        available: false,
      );
      storage.insertBatterySample(_sessionId, latestBattery!);
      notifyListeners();
      return;
    }
    final level = OpenPulseBleContract.parseBattery(await battery.read());
    latestBattery = BatterySample(
      receivedAt: DateTime.now(),
      level: level,
      available: level != null,
    );
    storage.insertBatterySample(_sessionId, latestBattery!);
    notifyListeners();
  }

  Future<void> _readInitialPuckStatus() async {
    final puck = _puck;
    if (puck == null || !puck.properties.read) {
      return;
    }
    final status = OpenPulseBleContract.parsePuckStatus(
      await puck.read(),
      DateTime.now(),
    );
    if (status != null) {
      latestPuckStatus = status;
      storage.insertPuckStatus(_sessionId, status);
      notifyListeners();
    }
  }

  Future<void> _subscribeToNotifications() async {
    for (final subscription in _valueSubscriptions) {
      await subscription.cancel();
    }
    _valueSubscriptions.clear();

    final control = _control;
    if (control != null && control.properties.notify) {
      controlNotifyReady = true;
      _valueSubscriptions.add(
        control.onValueReceived.listen((bytes) {
          final ack = OpenPulseBleContract.parseControlAck(
            bytes,
            DateTime.now(),
          );
          if (ack != null) {
            latestControlAck = ack;
            storage.insertControlAck(_sessionId, ack);
            notifyListeners();
          }
        }),
      );
      await control.setNotifyValue(true);
    }

    final battery = _battery;
    if (battery != null && battery.properties.notify) {
      _valueSubscriptions.add(
        battery.onValueReceived.listen((bytes) {
          final level = OpenPulseBleContract.parseBattery(bytes);
          final sample = BatterySample(
            receivedAt: DateTime.now(),
            level: level,
            available: level != null,
          );
          latestBattery = sample;
          storage.insertBatterySample(_sessionId, sample);
          notifyListeners();
        }),
      );
      await battery.setNotifyValue(true);
    }

    final puck = _puck;
    if (puck != null && puck.properties.notify) {
      _valueSubscriptions.add(
        puck.onValueReceived.listen((bytes) {
          final status = OpenPulseBleContract.parsePuckStatus(
            bytes,
            DateTime.now(),
          );
          if (status != null) {
            latestPuckStatus = status;
            storage.insertPuckStatus(_sessionId, status);
            notifyListeners();
          }
        }),
      );
      await puck.setNotifyValue(true);
    }

    final live = _live;
    if (live != null && live.properties.notify) {
      _valueSubscriptions.add(live.onValueReceived.listen(_handleLiveFrame));
      await live.setNotifyValue(true);
    }

    final bulk = _bulk;
    if (bulk != null && (bulk.properties.notify || bulk.properties.indicate)) {
      _valueSubscriptions.add(bulk.onValueReceived.listen(_handleBulkFrame));
      await bulk.setNotifyValue(true);
    }

    final raw = _raw;
    if (raw != null && raw.properties.notify) {
      _valueSubscriptions.add(raw.onValueReceived.listen(_handleRawPpgFrame));
      await raw.setNotifyValue(true);
    }
  }

  Future<void> _timeSync() async {
    _setPhase(ConnectionPhase.timeSyncing, 'Writing phone time to OpenPulse.');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _syncedUnixMs = nowMs;
    _syncedDeviceUptimeMs = _lastDeviceUptimeMs;
    final frame = OpenPulseBleContract.buildTimeSync(
      unixMs: nowMs,
      deviceUptimeMsSeenByApp: _lastDeviceUptimeMs,
    );
    await _writeControl(frame);
    storage.insertTimeSync(
      sessionId: _sessionId,
      unixMs: nowMs,
      deviceUptimeMsSeen: _lastDeviceUptimeMs,
    );
  }

  void _handleLiveFrame(List<int> bytes) {
    latestLiveFrameByteCount = bytes.length;
    latestLiveFrameHex = OpenPulseBleContract.bytesToHex(bytes);
    final parsed = OpenPulseBleContract.parseLiveFrame(
      bytes: bytes,
      previousDeviceUptimeMs: _lastDeviceUptimeMs,
      syncedUnixMs: _syncedUnixMs,
      syncedDeviceUptimeMs: _syncedDeviceUptimeMs,
      receivedAt: DateTime.now(),
    );
    if (parsed == null || parsed.records.isEmpty) {
      return;
    }
    livePacketCount++;
    _lastDeviceUptimeMs = parsed.lastDeviceUptimeMs;
    for (final record in parsed.records) {
      latestLiveRecord = record;
      storage.insertLiveRecord(_sessionId, record);
    }
    recentLiveRecords = [
      ...recentLiveRecords,
      ...parsed.records,
    ].takeLast(90).toList(growable: false);
    _refreshSelectedDay();
    _refreshHrvSummary();
    _refreshCalibrationTimeline();
    final steps = latestLiveRecord?.stepCount;
    if (steps != null) {
      if (steps < stepGoal) {
        stepGoalNotified = false;
      } else {
        _notifyStepGoalIfNeeded(steps);
      }
    }
    statusMessage = 'Live BLE packet #${parsed.sequence} received.';
    notifyListeners();
  }

  void _handleBulkFrame(List<int> bytes) {
    final frame = OpenPulseBleContract.parseBulkFrame(bytes, DateTime.now());
    if (frame == null) {
      return;
    }
    latestBackfillFrame = frame;
    storage.insertBackfillFrame(_sessionId, frame);
    if (frame.isLiveBackfill) {
      if (frame.isRestoreComplete) {
        final wasRestoring = deviceRestoreInProgress;
        deviceRestoreInProgress = false;
        lastDeviceRestoreAt = frame.receivedAt;
        statusMessage = wasRestoring
            ? deviceRestoreRecordCount == 0
                  ? 'OpenPulse had no newer device-local records.'
                  : 'OpenPulse restored $deviceRestoreRecordCount device records.'
            : 'OpenPulse backfill complete.';
        notifyListeners();
        return;
      }

      final records = OpenPulseBleContract.parseBackfillLiveRecords(
        frame: frame,
        syncedUnixMs: _syncedUnixMs,
        syncedDeviceUptimeMs: _syncedDeviceUptimeMs,
      );
      if (records.isNotEmpty) {
        final replaced = storage.replaceLiveRecordsFromDeviceBackfill(
          _sessionId,
          records,
        );
        if (deviceRestoreInProgress) {
          deviceRestoreRecordCount += replaced;
        }
        _lastDeviceUptimeMs = records.last.deviceUptimeMs > _lastDeviceUptimeMs
            ? records.last.deviceUptimeMs
            : _lastDeviceUptimeMs;
        latestLiveRecord = records.last;
        recentLiveRecords = [...recentLiveRecords, ...records]
          ..sort((a, b) => a.wallTime.compareTo(b.wallTime));
        recentLiveRecords = recentLiveRecords
            .takeLast(90)
            .toList(growable: false);
        _refreshSelectedDay();
        _refreshHrvSummary();
        _refreshCalibrationTimeline();
        statusMessage = deviceRestoreInProgress
            ? 'Restoring OpenPulse device records: $deviceRestoreRecordCount.'
            : 'Backfilled $replaced OpenPulse device records.';
      }
    }
    notifyListeners();
  }

  void _handleRawPpgFrame(List<int> bytes) {
    final frame = OpenPulseBleContract.parseRawPpgFrame(bytes, DateTime.now());
    if (frame == null) {
      return;
    }
    rawPpgPacketCount++;
    latestRawPpgFrame = frame;
    storage.insertRawPpgFrame(_sessionId, frame);
    if (frame.samples.isNotEmpty) {
      recentRawPpgSamples = [
        ...recentRawPpgSamples,
        ...frame.samples,
      ].takeLast(420).toList(growable: false);
    }
    _refreshSelectedDay();
    statusMessage = frame.payloadLength > 0
        ? 'Raw PPG packet #${frame.sequence}: ${frame.payloadLength} bytes.'
        : 'Raw PPG packet #${frame.sequence}: ${frame.sensorLabel}.';
    notifyListeners();
  }

  Future<void> _writeControl(List<int> frame) async {
    final control = _control;
    if (control == null) {
      throw StateError('OpenPulse control characteristic is unavailable.');
    }
    await control.write(frame, withoutResponse: false);
    storage.insertControlWrite(
      sessionId: _sessionId,
      command: frame.isEmpty ? -1 : frame.first,
      frame: frame,
    );
  }

  void _handleUnexpectedDisconnect() {
    final device = _device;
    unawaited(notifications.connectionDropped());
    storage.closeSession(_sessionId);
    _clearGatt(closeSession: false);
    _setPhase(ConnectionPhase.reconnecting, 'BLE link lost. Reconnecting.');
    if (device != null) {
      unawaited(_reconnectKnownDevice(device));
    }
    _scheduleScanRetry(_reconnectDelay);
  }

  Future<void> _reconnectKnownDevice(BluetoothDevice device) async {
    if (_intentionalDisconnect || _connectInFlight || _gattSetupInFlight) {
      return;
    }
    _connectInFlight = true;
    _device = device;
    var retryNeeded = false;
    try {
      await _listenToDeviceConnection(device);
      await device.connect(
        license: License.nonprofit,
        timeout: _connectTimeout,
        mtu: null,
      );
      retryNeeded = !await _setupConnectedDevice(device, restored: true);
    } catch (_) {
      retryNeeded = true;
    } finally {
      _connectInFlight = false;
      if (retryNeeded &&
          !_intentionalDisconnect &&
          phase != ConnectionPhase.streaming) {
        _scheduleScanRetry(Duration.zero);
      }
    }
  }

  void _scheduleScanRetry([Duration delay = const Duration(seconds: 3)]) {
    if (_intentionalDisconnect ||
        _connectInFlight ||
        phase == ConnectionPhase.streaming) {
      return;
    }
    _autoScanRetryTimer?.cancel();
    _autoScanRetryTimer = Timer(delay, () {
      if (!_intentionalDisconnect &&
          !_connectInFlight &&
          phase != ConnectionPhase.streaming) {
        unawaited(scanAndConnect());
      }
    });
  }

  void _clearGatt({bool closeSession = true}) {
    _rawPollTimer?.cancel();
    _rawPollTimer = null;
    rawPpgDiagnosticEnabled = false;
    _clearSavedRawSettings();
    if (closeSession) {
      storage.closeSession(_sessionId);
    }
    _sessionId = null;
    gattReady = false;
    customServiceReady = false;
    batteryServiceReady = false;
    deviceInfoReady = false;
    controlNotifyReady = false;
    bulkBackfillReady = false;
    rawPpgReady = false;
    _control = null;
    _live = null;
    _bulk = null;
    _raw = null;
    _puck = null;
    _battery = null;
    _lastDeviceUptimeMs = 0;
    livePacketCount = 0;
    rawPpgPacketCount = 0;
    latestLiveFrameByteCount = 0;
    latestLiveFrameHex = null;
    recentLiveRecords = const [];
    recentRawPpgSamples = const [];
    stepGoalNotified = false;
    deviceRestoreInProgress = false;
    latestLiveRecord = null;
    latestRawPpgFrame = null;
    for (final subscription in _valueSubscriptions) {
      unawaited(subscription.cancel());
    }
    _valueSubscriptions.clear();
  }

  void _setPhase(ConnectionPhase next, String message) {
    phase = next;
    statusMessage = message;
    notifyListeners();
  }

  void _refreshSelectedDay() {
    if (!storageReady) {
      return;
    }
    selectedDaySummary = storage.fetchDaySummary(selectedDay);
  }

  void _refreshHrvSummary() {
    if (!storageReady) {
      return;
    }
    latestHrvSummary = storage.fetchHrvSummary();
  }

  void _refreshCalibrationTimeline() {
    if (!storageReady) {
      return;
    }
    calibrationTimeline = storage.fetchCalibrationTimeline();
  }

  void _notifyStepGoalIfNeeded(int steps) {
    if (stepGoalNotified) {
      return;
    }
    stepGoalNotified = true;
    unawaited(notifications.stepGoalReached(steps: steps, goal: stepGoal));
  }

  void _clearSavedRawSettings() {
    _savedSamplingHzBeforeRaw = null;
    _savedLedGreenMaBeforeRaw = null;
    _savedLedRedMaBeforeRaw = null;
    _savedLedIrMaBeforeRaw = null;
  }

  @override
  void dispose() {
    _rawPollTimer?.cancel();
    _autoScanRetryTimer?.cancel();
    unawaited(_adapterSubscription?.cancel());
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    for (final subscription in _valueSubscriptions) {
      unawaited(subscription.cancel());
    }
    storage.closeSession(_sessionId);
    storage.dispose();
    super.dispose();
  }
}

extension _RecentWindow<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    if (list.length <= count) {
      return list;
    }
    return list.sublist(list.length - count);
  }
}
