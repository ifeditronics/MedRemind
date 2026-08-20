import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'time_sync_service.dart';

enum DeviceConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
}

class BLEService extends ChangeNotifier {
  // UUID Definitions
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String timeSyncCharUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String statusConfigCharUuid = "d866a2e2-9b24-44cf-a87d-41a451d6c8b5";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _timeSyncChar;
  BluetoothCharacteristic? _statusConfigChar;
  
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  String _statusMessage = "Idle";
  String _deviceStatus = "Normal Clock Mode";
  List<ScanResult> _scanResults = [];
  bool _timeSyncAcked = false;
  
  StreamSubscription? _scanSub;
  StreamSubscription? _connSub;
  StreamSubscription? _statusSub;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  DeviceConnectionState get state => _state;
  String get statusMessage => _statusMessage;
  String get deviceStatus => _deviceStatus;
  List<ScanResult> get scanResults => _scanResults;
  bool get timeSyncAcked => _timeSyncAcked;

  // Received Schedule Config from Device (0x02)
  int? receivedScheduleHour;
  int? receivedScheduleMinute;
  int? receivedScheduleDose;
  bool? receivedScheduleActive;

  void clearReceivedSchedule() {
    receivedScheduleHour = null;
    receivedScheduleMinute = null;
    receivedScheduleDose = null;
    receivedScheduleActive = null;
  }

  // Received Medication Event from Device (0x04 0x03)
  int? receivedEventId;
  int? receivedEventScheduleId;
  int? receivedEventScheduledYear;
  int? receivedEventScheduledMonth;
  int? receivedEventScheduledDay;
  int? receivedEventScheduledHour;
  int? receivedEventScheduledMinute;
  int? receivedEventDose;
  int? receivedEventSource;

  void clearReceivedEvent() {
    receivedEventId = null;
    receivedEventScheduleId = null;
    receivedEventScheduledYear = null;
    receivedEventScheduledMonth = null;
    receivedEventScheduledDay = null;
    receivedEventScheduledHour = null;
    receivedEventScheduledMinute = null;
    receivedEventDose = null;
    receivedEventSource = null;
  }

  BLEService() {
    _initBLE();
  }

  void _initBLE() {
    FlutterBluePlus.adapterState.listen((state) {
      if (kDebugMode) print("Bluetooth adapter state: $state");
    });
  }

  Future<void> startScan() async {
    if (_state == DeviceConnectionState.connected || _state == DeviceConnectionState.connecting) {
      return;
    }
    
    _state = DeviceConnectionState.scanning;
    _statusMessage = "Scanning for MedRemind...";
    _scanResults.clear();
    notifyListeners();

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 8),
      );

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
        
        for (var result in results) {
          final name = result.device.platformName.isEmpty 
              ? result.advertisementData.advName 
              : result.device.platformName;
          if (name == "MedRemind") {
            connectToDevice(result.device);
            break;
          }
        }
      }, onError: (e) {
        _statusMessage = "Scan error: $e";
        _state = DeviceConnectionState.disconnected;
        notifyListeners();
      });

      // Wait for scan to stop
      await FlutterBluePlus.isScanning.where((val) => val == false).first;
      if (_state == DeviceConnectionState.scanning) {
        _state = DeviceConnectionState.disconnected;
        _statusMessage = _scanResults.isEmpty ? "No device found" : "Scan completed";
        notifyListeners();
      }
    } catch (e) {
      _statusMessage = "Scan error: $e";
      _state = DeviceConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    _state = DeviceConnectionState.connecting;
    _statusMessage = "Connecting to ${device.platformName.isEmpty ? 'Device' : device.platformName}...";
    notifyListeners();

    try {
      await FlutterBluePlus.stopScan();
      await device.connect(autoConnect: false);
      _connectedDevice = device;

      _connSub?.cancel();
      _connSub = device.connectionState.listen((connState) async {
        if (connState == BluetoothConnectionState.connected) {
          _state = DeviceConnectionState.connected;
          _statusMessage = "Connected to ${device.platformName}";
          notifyListeners();
          
          await _discoverServices(device);
          
          // Auto sync time on connection
          await syncTimeWithDevice();
        } else if (connState == BluetoothConnectionState.disconnected) {
          _cleanupConnection();
          _state = DeviceConnectionState.disconnected;
          _statusMessage = "Disconnected";
          notifyListeners();
        }
      });
    } catch (e) {
      _cleanupConnection();
      _state = DeviceConnectionState.disconnected;
      _statusMessage = "Connection failed: $e";
      notifyListeners();
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == timeSyncCharUuid.toLowerCase()) {
              _timeSyncChar = char;
            } else if (char.uuid.toString().toLowerCase() == statusConfigCharUuid.toLowerCase()) {
              _statusConfigChar = char;
              await _setupStatusNotifications(char);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error discovering services: $e");
    }
  }

  Future<void> _setupStatusNotifications(BluetoothCharacteristic char) async {
    try {
      await char.setNotifyValue(true);
      _statusSub?.cancel();
      _statusSub = char.lastValueStream.listen((value) {
        if (value.isEmpty) return;

        if (value.length >= 6 && value[0] == 0x02) {
          // Parse schedule update from device: [0x02, id, hour, minute, dose, active]
          receivedScheduleHour = value[2];
          receivedScheduleMinute = value[3];
          receivedScheduleDose = value[4];
          receivedScheduleActive = value[5] != 0;
          if (kDebugMode) {
            print("BLE received schedule sync: $receivedScheduleHour:$receivedScheduleMinute");
          }
          notifyListeners();
        } else if (value.length >= 14 && value[0] == 0x04 && value[1] == 0x03) {
          // Parse detailed medication event from device
          receivedEventId = value[2] | (value[3] << 8) | (value[4] << 16) | (value[5] << 24);
          receivedEventScheduleId = value[6];
          receivedEventScheduledYear = 2000 + value[7];
          receivedEventScheduledMonth = value[8];
          receivedEventScheduledDay = value[9];
          receivedEventScheduledHour = value[10];
          receivedEventScheduledMinute = value[11];
          receivedEventDose = value[12];
          receivedEventSource = value[13];
          _deviceStatus = "Medication Taken Successfully";
          if (kDebugMode) {
            print("BLE received medication event ID: $receivedEventId");
          }
          notifyListeners();
        } else if (value.length >= 2 && value[0] == 0x04) {
          final statusCode = value[1];
          switch (statusCode) {
            case 0x00:
              _deviceStatus = "Standby (Normal Clock)";
              break;
            case 0x01:
              _deviceStatus = "MEDICATION ALARM ACTIVE (Ringing!)";
              break;
            case 0x02:
              _deviceStatus = "Alarm Acknowledged (Buzzer Muted)";
              break;
            case 0x03:
              _deviceStatus = "Medication Taken Successfully";
              break;
            case 0x05:
              _timeSyncAcked = true;
              _deviceStatus = "Time Synchronized ✓";
              break;
            default:
              _deviceStatus = "Unknown Event (0x${statusCode.toRadixString(16)})";
          }
          notifyListeners();
        }
      });
    } catch (e) {
      if (kDebugMode) print("Error setting notifications: $e");
    }
  }

  Future<void> syncTimeWithDevice() async {
    if (_timeSyncChar == null) {
      _statusMessage = "Cannot sync: Time sync characteristic not found";
      notifyListeners();
      return;
    }

    try {
      _timeSyncAcked = false;
      notifyListeners();
      final packet = TimeSyncService.createSyncPacket();
      await _timeSyncChar!.write(packet, withoutResponse: false);
      _statusMessage = "Synchronizing time...";
      notifyListeners();
    } catch (e) {
      _statusMessage = "Sync failed: $e";
      notifyListeners();
    }
  }

  Future<void> sendMedicationConfig(int id, int hour, int minute, int dose, bool active) async {
    if (_statusConfigChar == null) {
      _statusMessage = "Cannot configure: Config characteristic not found";
      notifyListeners();
      return;
    }

    try {
      // 6-byte config packet: [0x02, id, hour, minute, dose, active ? 1 : 0]
      final packet = [
        0x02,
        id & 0xFF,
        hour & 0xFF,
        minute & 0xFF,
        dose & 0xFF,
        active ? 1 : 0,
      ];
      await _statusConfigChar!.write(packet, withoutResponse: false);
      _statusMessage = "Medication schedule updated";
      notifyListeners();
    } catch (e) {
      _statusMessage = "Config failed: $e";
      notifyListeners();
    }
  }

  Future<void> sendEventAck(int eventId) async {
    if (_statusConfigChar == null) return;
    try {
      // 5-byte ack packet: [0x06, eventId_b0, eventId_b1, eventId_b2, eventId_b3]
      final packet = [
        0x06,
        eventId & 0xFF,
        (eventId >> 8) & 0xFF,
        (eventId >> 16) & 0xFF,
        (eventId >> 24) & 0xFF,
      ];
      await _statusConfigChar!.write(packet, withoutResponse: false);
      if (kDebugMode) print("Sent Event Ack for event $eventId");
    } catch (e) {
      if (kDebugMode) print("Error sending event ack: $e");
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _cleanupConnection();
    _state = DeviceConnectionState.disconnected;
    _statusMessage = "Disconnected";
    notifyListeners();
  }

  void _cleanupConnection() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _connectedDevice = null;
    _timeSyncChar = null;
    _statusConfigChar = null;
    _deviceStatus = "Normal Clock Mode";
    _timeSyncAcked = false;
  }

  @override
  void dispose() {
    _cleanupConnection();
    super.dispose();
  }
}
