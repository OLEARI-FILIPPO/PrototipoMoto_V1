import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceTelemetryMessage {
  DeviceTelemetryMessage({required this.payload, required this.timestamp});

  final List<int> payload;
  final DateTime timestamp;
}

class DeviceConnectionInfo {
  const DeviceConnectionInfo({
    required this.device,
    required this.telemetryReady,
  });

  const DeviceConnectionInfo.empty() : device = null, telemetryReady = false;

  final BluetoothDevice? device;
  final bool telemetryReady;
}

class ExternalDeviceService {
  static final ExternalDeviceService _instance =
      ExternalDeviceService._internal();
  factory ExternalDeviceService() => _instance;

  ExternalDeviceService._internal() {
    _publishConnection();
  }

  final Guid serviceUuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  final Guid telemetryCharUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  _DeviceConnection? _connection;

  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController.broadcast();
  final StreamController<DeviceConnectionInfo> _connectionController =
      StreamController.broadcast();
  final StreamController<DeviceTelemetryMessage> _telemetryController =
      StreamController.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _reconnectTimer;

  Stream<List<ScanResult>> get scanResultsStream =>
      _scanResultsController.stream;
  Stream<DeviceConnectionInfo> get connectionStream =>
      _connectionController.stream;
  Stream<DeviceTelemetryMessage> get telemetryStream =>
      _telemetryController.stream;

  DeviceConnectionInfo get currentConnection => DeviceConnectionInfo(
    device: _connection?.device,
    telemetryReady: _connection?.telemetryCharacteristic != null,
  );

  bool get isConnected => _connection?.device != null;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await stopScan();
    // Start scanning
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) {
        // Filter: Keep only devices with "ESP" in their name
        // This removes "Unknown Device" and other irrelevant Bluetooth devices
        return r.device.platformName.isNotEmpty && 
               r.device.platformName.toUpperCase().contains("ESP");
      }).toList();
      _scanResultsController.add(filtered);
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanResultsController.add(const []);
  }

  Future<void> connectTo(ScanResult scanResult) async {
    await stopScan();
    await disconnect();

    final device = scanResult.device;
    debugPrint(
      '[BLE] Connecting to ${device.platformName} (${device.remoteId})...',
    );

    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      debugPrint('[BLE] Connected to ${device.platformName}');

      final services = await device.discoverServices();
      BluetoothService? service;

      try {
        service = services.firstWhere((s) => s.uuid == serviceUuid);
      } catch (_) {
        throw Exception(
          'Service BLE compatibile non trovato (UUID: $serviceUuid)',
        );
      }

      BluetoothCharacteristic? telemetryCharacteristic;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == telemetryCharUuid) {
          telemetryCharacteristic = characteristic;
          break;
        }
      }

      final connection = _DeviceConnection(
        device: device,
        telemetryCharacteristic: telemetryCharacteristic,
      );

      if (telemetryCharacteristic != null &&
          telemetryCharacteristic.properties.notify) {
        await telemetryCharacteristic.setNotifyValue(true);
        connection.telemetrySubscription = telemetryCharacteristic
            .onValueReceived
            .listen((payload) {
              _telemetryController.add(
                DeviceTelemetryMessage(
                  payload: List<int>.from(payload),
                  timestamp: DateTime.now(),
                ),
              );
            });
      }

      _connection = connection;
      _publishConnection();
      _ensureReconnectTimer();
      debugPrint('[BLE] Connection setup complete');
    } catch (e) {
      debugPrint('[BLE] Connection failed: $e');
      await device.disconnect();
      _connection = null;
      _publishConnection();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_connection != null) {
      await _connection!.dispose();
      _connection = null;
      _publishConnection();
    }
  }

  Future<void> startPairingMode() async {
    await _sendCommand('STARTPAIRING');
  }

  Future<void> startSearchingMode() async {
    await _sendCommand('STARTSEARCHING');
  }

  Future<void> stopMode() async {
    await _sendCommand('STOPMODE');
  }

  /// Forza la modalità di comunicazione: 'UWB', 'LoRa', o 'AUTO'
  Future<void> setCommMode(String mode) async {
    // mode: 'UWB' | 'LoRa' | 'AUTO'
    await _sendCommand('COMM_$mode');
  }

  Future<void> _sendCommand(String cmd) async {
    if (_connection == null || !_connection!.isReadyForTelemetry) {
      debugPrint('[BLE CMD] ⚠️ Cannot send command "$cmd" - device not ready');
      return;
    }
    debugPrint('[BLE CMD] 📤 Sending command: $cmd');
    final char = _connection!.telemetryCharacteristic!;
    await char.write(ascii.encode(cmd));
    debugPrint('[BLE CMD] ✅ Command sent successfully');
  }

  void _publishConnection() {
    _connectionController.add(currentConnection);
  }

  void _ensureReconnectTimer() {
    _reconnectTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkReconnect(),
    );
  }

  Future<void> _checkReconnect() async {
    if (_connection == null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }
    // If disconnected but _connection object exists, try to reuse or reconnect logic
    try {
      if (await _connection!.device.connectionState.first ==
          BluetoothConnectionState.disconnected) {
        // Logic for auto-reconnect needed?
        // For now let's just observe.
      }
    } catch (_) {}
  }
}

class _DeviceConnection {
  _DeviceConnection({
    required this.device,
    required this.telemetryCharacteristic,
  });

  final BluetoothDevice device;
  final BluetoothCharacteristic? telemetryCharacteristic;
  StreamSubscription<List<int>>? telemetrySubscription;

  bool get isReadyForTelemetry => telemetryCharacteristic != null;

  Future<void> dispose() async {
    await telemetrySubscription?.cancel();
    try {
      if (telemetryCharacteristic != null &&
          telemetryCharacteristic!.isNotifying) {
        await telemetryCharacteristic!.setNotifyValue(false);
      }
    } catch (_) {}
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
