import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/openpulse_models.dart';
import '../storage/openpulse_storage.dart';
import 'openpulse_ble_contract.dart';

class OpenPulseController extends ChangeNotifier {
  OpenPulseController(this.storage);

  final OpenPulseStorage storage;

  ConnectionPhase phase = ConnectionPhase.disconnected;
  String statusMessage = 'Ready to scan for real OpenPulse hardware.';
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  DeviceInformation deviceInformation = const DeviceInformation();
  BatterySample? latestBattery;
  PuckStatus? latestPuckStatus;
  LiveRecord? latestLiveRecord;
  DeviceMode selectedMode = DeviceMode.active;
  int samplingHz = 25;
  int ledGreenMa = 8;
  int ledRedMa = 0;
  int ledIrMa = 0;
  bool storageReady = false;
  bool gattReady = false;
  bool customServiceReady = false;
  bool batteryServiceReady = false;
  bool deviceInfoReady = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _live;
  BluetoothCharacteristic? _puck;
  BluetoothCharacteristic? _battery;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _valueSubscriptions = [];
  bool _intentionalDisconnect = false;
  bool _connectInFlight = false;
  int? _sessionId;
  int _lastDeviceUptimeMs = 0;
  int _syncedUnixMs = 0;
  int _syncedDeviceUptimeMs = 0;

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
      adapterState = FlutterBluePlus.adapterStateNow;
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        adapterState = state;
        notifyListeners();
      });
      await FlutterBluePlus.setOptions(
        showPowerAlert: true,
        restoreState: true,
      );
      notifyListeners();
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
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _setPhase(
        ConnectionPhase.bluetoothUnavailable,
        'This device does not report Bluetooth LE support.',
      );
      return;
    }
    final state = FlutterBluePlus.adapterStateNow;
    if (state != BluetoothAdapterState.on &&
        state != BluetoothAdapterState.unknown) {
      _setPhase(
        ConnectionPhase.bluetoothUnavailable,
        'Bluetooth is ${state.name}. Turn it on and grant permission.',
      );
      return;
    }

    _intentionalDisconnect = false;
    _setPhase(ConnectionPhase.scanning, 'Scanning for OpenPulse advertising.');
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      _handleScanResults,
    );

    const scanDuration = Duration(seconds: 10);
    await FlutterBluePlus.startScan(
      withNames: const [OpenPulseBleContract.advertisedName],
      withServices: [OpenPulseBleContract.serviceUuid],
      timeout: scanDuration,
    );
    await Future<void>.delayed(
      scanDuration + const Duration(milliseconds: 300),
    );
    if (phase == ConnectionPhase.scanning) {
      _setPhase(
        ConnectionPhase.disconnected,
        'No OpenPulse advertisement found yet.',
      );
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
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

  Future<void> requestBackfill() async {
    await _writeControl(
      OpenPulseBleContract.buildRequestBackfill(_lastDeviceUptimeMs),
    );
  }

  Future<void> requestRawPpgWindow() async {
    await _writeControl(OpenPulseBleContract.buildRequestRawWindow(10));
  }

  Future<void> enterShipMode() async {
    selectedMode = DeviceMode.shipMode;
    await _writeControl(OpenPulseBleContract.buildEnterShipMode());
    notifyListeners();
  }

  void _handleScanResults(List<ScanResult> results) {
    if (_connectInFlight) {
      return;
    }
    for (final result in results) {
      final advName = result.advertisementData.advName;
      final device = result.device;
      final isOpenPulse =
          advName == OpenPulseBleContract.advertisedName ||
          device.advName == OpenPulseBleContract.advertisedName ||
          device.platformName == OpenPulseBleContract.advertisedName;
      if (isOpenPulse) {
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
    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            !_intentionalDisconnect) {
          _handleUnexpectedDisconnect();
        }
      });

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 25),
      );
      try {
        await device.requestMtu(247);
      } catch (_) {
        // iOS negotiates MTU internally; Android may honor this request.
      }

      _setPhase(ConnectionPhase.discovering, 'Discovering OpenPulse GATT.');
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

      _setPhase(ConnectionPhase.streaming, 'OpenPulse is connected and live.');
    } catch (error) {
      _clearGatt();
      _setPhase(ConnectionPhase.error, 'BLE connection failed: $error');
    } finally {
      _connectInFlight = false;
    }
  }

  void _bindServices(List<BluetoothService> services) {
    customServiceReady = false;
    batteryServiceReady = false;
    _control = null;
    _live = null;
    _puck = null;
    _battery = null;

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
    _lastDeviceUptimeMs = parsed.lastDeviceUptimeMs;
    for (final record in parsed.records) {
      latestLiveRecord = record;
      storage.insertLiveRecord(_sessionId, record);
    }
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
    storage.closeSession(_sessionId);
    _clearGatt(closeSession: false);
    _setPhase(ConnectionPhase.reconnecting, 'BLE link lost. Reconnecting.');
    Future<void>(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!_intentionalDisconnect) {
        await scanAndConnect();
      }
    });
  }

  void _clearGatt({bool closeSession = true}) {
    if (closeSession) {
      storage.closeSession(_sessionId);
    }
    _sessionId = null;
    gattReady = false;
    customServiceReady = false;
    batteryServiceReady = false;
    deviceInfoReady = false;
    _control = null;
    _live = null;
    _puck = null;
    _battery = null;
    _lastDeviceUptimeMs = 0;
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

  @override
  void dispose() {
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
