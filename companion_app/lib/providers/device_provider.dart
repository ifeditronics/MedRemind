import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class DeviceProvider extends ChangeNotifier {
  final BLEService bleService;
  DateTime _currentPhoneTime = DateTime.now();
  DateTime? _lastSyncTime;
  Timer? _timer;
  bool _wasSyncAcked = false;

  // Medication Schedule State
  int _scheduleHour = 8;
  int _scheduleMinute = 0;
  int _scheduleDose = 4;
  bool _scheduleActive = true;

  DateTime get currentPhoneTime => _currentPhoneTime;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get scheduleHour => _scheduleHour;
  int get scheduleMinute => _scheduleMinute;
  int get scheduleDose => _scheduleDose;
  bool get scheduleActive => _scheduleActive;

  Future<void> updateSchedule(int hour, int minute, int dose, bool active) async {
    _scheduleHour = hour;
    _scheduleMinute = minute;
    _scheduleDose = dose;
    _scheduleActive = active;
    notifyListeners();
    
    if (bleService.state == DeviceConnectionState.connected) {
      await bleService.sendMedicationConfig(0, hour, minute, dose, active);
    }
  }

  DeviceProvider(this.bleService) {
    _startTimer();
    bleService.addListener(_onBleServiceChanged);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentPhoneTime = DateTime.now();
      notifyListeners();
    });
  }

  void _onBleServiceChanged() {
    if (bleService.timeSyncAcked && !_wasSyncAcked) {
      _lastSyncTime = DateTime.now();
    }
    _wasSyncAcked = bleService.timeSyncAcked;
    notifyListeners();
  }

  // Mapped Getters for UI binding
  bool get scanning => bleService.state == DeviceConnectionState.scanning;
  bool get connecting => bleService.state == DeviceConnectionState.connecting;
  bool get connected => bleService.state == DeviceConnectionState.connected;
  bool get synchronized => bleService.timeSyncAcked;
  String get deviceName => bleService.connectedDevice?.platformName.isEmpty ?? true
      ? "Gozie-MedReminder"
      : bleService.connectedDevice!.platformName;

  String get connectionStatusText {
    switch (bleService.state) {
      case DeviceConnectionState.scanning:
        return "Searching...";
      case DeviceConnectionState.connecting:
        return "Connecting...";
      case DeviceConnectionState.connected:
        return "Connected";
      case DeviceConnectionState.disconnected:
        return "Disconnected";
    }
  }

  String get syncStatusText {
    if (synchronized) {
      return "Time synchronized ✓";
    } else if (connected) {
      return "Synchronizing time...";
    } else {
      return "Not synchronized";
    }
  }

  String get connectionErrors => bleService.statusMessage.contains("failed") || 
                                 bleService.statusMessage.contains("error")
      ? bleService.statusMessage
      : "";

  Future<void> scanAndConnect() async {
    await bleService.startScan();
  }

  Future<void> syncTime() async {
    await bleService.syncTimeWithDevice();
  }

  Future<void> disconnect() async {
    await bleService.disconnect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    bleService.removeListener(_onBleServiceChanged);
    super.dispose();
  }
}
