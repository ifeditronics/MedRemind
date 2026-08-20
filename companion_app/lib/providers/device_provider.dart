import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';

class HistoryRecord {
  final String id; // scheduleId_YYYY-MM-DD_HH_MM
  final int scheduleId;
  final int hour;
  final int minute;
  final int dose;
  final DateTime scheduledTime;
  DateTime? actualTakenTime;
  String status; // 'PENDING', 'TAKEN', 'MISSED', 'CANCELLED', 'RESCHEDULED'
  String source; // 'APP', 'DEVICE'
  final DateTime createdAt;
  DateTime updatedAt;

  HistoryRecord({
    required this.id,
    required this.scheduleId,
    required this.hour,
    required this.minute,
    required this.dose,
    required this.scheduledTime,
    this.actualTakenTime,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleId': scheduleId,
    'hour': hour,
    'minute': minute,
    'dose': dose,
    'scheduledTime': scheduledTime.toIso8601String(),
    'actualTakenTime': actualTakenTime?.toIso8601String(),
    'status': status,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) => HistoryRecord(
    id: json['id'],
    scheduleId: json['scheduleId'],
    hour: json['hour'],
    minute: json['minute'],
    dose: json['dose'],
    scheduledTime: DateTime.parse(json['scheduledTime']),
    actualTakenTime: json['actualTakenTime'] != null ? DateTime.parse(json['actualTakenTime']) : null,
    status: json['status'],
    source: json['source'] ?? 'DEVICE',
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}

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

  // History List
  List<HistoryRecord> _history = [];
  DateTime _historyStartTime = DateTime.now().subtract(const Duration(days: 3));

  DateTime get currentPhoneTime => _currentPhoneTime;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get scheduleHour => _scheduleHour;
  int get scheduleMinute => _scheduleMinute;
  int get scheduleDose => _scheduleDose;
  bool get scheduleActive => _scheduleActive;
  List<HistoryRecord> get history => _history;

  Future<void> updateSchedule(int hour, int minute, int dose, bool active) async {
    _handleScheduleTransition(
      oldHour: _scheduleHour,
      oldMinute: _scheduleMinute,
      oldActive: _scheduleActive,
      newHour: hour,
      newMinute: minute,
      newActive: active,
      changeSource: 'APP',
    );
    _scheduleDose = dose;
    notifyListeners();
    
    if (bleService.state == DeviceConnectionState.connected) {
      await bleService.sendMedicationConfig(0, hour, minute, dose, active);
    }
  }

  DeviceProvider(this.bleService) {
    _startTimer();
    _loadHistory().then((_) {
      _generateOccurrences();
      _checkAndExpirePendingOccurrences();
    });
    bleService.addListener(_onBleServiceChanged);
  }

  void _startTimer() {
    int ticks = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentPhoneTime = DateTime.now();
      
      ticks++;
      if (ticks % 10 == 0) { // Run every 10 seconds
        _checkAndExpirePendingOccurrences();
        _generateOccurrences();
      }
      
      notifyListeners();
    });
  }

  void _onBleServiceChanged() {
    if (bleService.timeSyncAcked && !_wasSyncAcked) {
      _lastSyncTime = DateTime.now();
    }
    _wasSyncAcked = bleService.timeSyncAcked;

    // Check received schedule config from device (0x02)
    if (bleService.receivedScheduleHour != null) {
      _handleScheduleTransition(
        oldHour: _scheduleHour,
        oldMinute: _scheduleMinute,
        oldActive: _scheduleActive,
        newHour: bleService.receivedScheduleHour!,
        newMinute: bleService.receivedScheduleMinute!,
        newActive: bleService.receivedScheduleActive!,
        changeSource: 'DEVICE',
      );
      _scheduleDose = bleService.receivedScheduleDose!;
      bleService.clearReceivedSchedule();
      notifyListeners();
    }

    // Check received medication event from device (0x04 0x03)
    if (bleService.receivedEventId != null) {
      _handleBleMedicationEvent(
        eventId: bleService.receivedEventId!,
        scheduleId: bleService.receivedEventScheduleId!,
        scheduledYear: bleService.receivedEventScheduledYear!,
        scheduledMonth: bleService.receivedEventScheduledMonth!,
        scheduledDay: bleService.receivedEventScheduledDay!,
        scheduledHour: bleService.receivedEventScheduledHour!,
        scheduledMinute: bleService.receivedEventScheduledMinute!,
        dose: bleService.receivedEventDose!,
        sourceVal: bleService.receivedEventSource!,
      );
      bleService.clearReceivedEvent();
      notifyListeners();
    }

    notifyListeners();
  }

  void _handleScheduleTransition({
    required int oldHour,
    required int oldMinute,
    required bool oldActive,
    required int newHour,
    required int newMinute,
    required bool newActive,
    required String changeSource,
  }) {
    final now = DateTime.now();
    bool timeChanged = oldHour != newHour || oldMinute != newMinute;
    bool activeChanged = oldActive != newActive;

    if (activeChanged || timeChanged) {
      // Find all PENDING occurrences for schedule ID 0 scheduled in the future
      final pendingOccurrences = _history.where((rec) =>
          rec.scheduleId == 0 &&
          rec.status == 'PENDING' &&
          rec.scheduledTime.isAfter(now)
      ).toList();

      for (var rec in pendingOccurrences) {
        if (activeChanged && !newActive) {
          rec.status = 'CANCELLED';
          rec.updatedAt = now;
        } else if (timeChanged) {
          rec.status = 'RESCHEDULED';
          rec.updatedAt = now;
        }
      }
    }

    _scheduleHour = newHour;
    _scheduleMinute = newMinute;
    _scheduleActive = newActive;

    _generateOccurrences();
    _saveHistory();
  }

  void _generateOccurrences() {
    if (!_scheduleActive) return;

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    // Generate occurrences for today and the last 3 days
    for (int d = -3; d <= 0; d++) {
      final targetDate = now.add(Duration(days: d));
      final dateStr = "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final occurrenceId = "0_${dateStr}_${_scheduleHour.toString().padLeft(2, '0')}_${_scheduleMinute.toString().padLeft(2, '0')}";

      bool exists = _history.any((rec) => rec.id == occurrenceId);
      if (!exists) {
        final scheduledTime = DateTime(targetDate.year, targetDate.month, targetDate.day, _scheduleHour, _scheduleMinute);
        
        if (scheduledTime.isBefore(_historyStartTime)) {
          continue;
        }

        // A pending occurrence is only MISSED initially if its date has already ended (i.e. strictly before today)
        final schedMidnight = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day);
        String initialStatus = 'PENDING';
        if (schedMidnight.isBefore(todayMidnight)) {
          initialStatus = 'MISSED';
        }

        final record = HistoryRecord(
          id: occurrenceId,
          scheduleId: 0,
          hour: _scheduleHour,
          minute: _scheduleMinute,
          dose: _scheduleDose,
          scheduledTime: scheduledTime,
          status: initialStatus,
          source: 'DEVICE',
          createdAt: now,
          updatedAt: now,
        );
        _history.add(record);
      }
    }
    _saveHistory();
  }

  void _checkAndExpirePendingOccurrences() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    bool changed = false;

    for (var rec in _history) {
      if (rec.status == 'PENDING') {
        // Occurrence date has strictly ended (i.e. is before today's date)
        final schedMidnight = DateTime(rec.scheduledTime.year, rec.scheduledTime.month, rec.scheduledTime.day);
        if (schedMidnight.isBefore(todayMidnight)) {
          rec.status = 'MISSED';
          rec.updatedAt = now;
          changed = true;
        }
      }
    }

    if (changed) {
      _saveHistory();
      notifyListeners();
    }
  }

  void _handleBleMedicationEvent({
    required int eventId,
    required int scheduleId,
    required int scheduledYear,
    required int scheduledMonth,
    required int scheduledDay,
    required int scheduledHour,
    required int scheduledMinute,
    required int dose,
    required int sourceVal,
  }) {
    final now = DateTime.now();
    final dateStr = "$scheduledYear-${scheduledMonth.toString().padLeft(2, '0')}-${scheduledDay.toString().padLeft(2, '0')}";
    final occurrenceId = "${scheduleId}_${dateStr}_${scheduledHour.toString().padLeft(2, '0')}_${scheduledMinute.toString().padLeft(2, '0')}";

    final actualTakenTime = DateTime.fromMillisecondsSinceEpoch(eventId * 1000);
    final scheduledTime = DateTime(scheduledYear, scheduledMonth, scheduledDay, scheduledHour, scheduledMinute);

    // Deduplication check using unique occurrence IDs and event timestamps
    bool alreadyTaken = _history.any((rec) => rec.id == occurrenceId && rec.status == 'TAKEN');
    bool duplicateEvent = _history.any((rec) => rec.actualTakenTime?.millisecondsSinceEpoch == eventId * 1000);

    if (alreadyTaken || duplicateEvent) {
      bleService.sendEventAck(eventId);
      return;
    }

    int existingIdx = _history.indexWhere((rec) => rec.id == occurrenceId);
    if (existingIdx != -1) {
      final rec = _history[existingIdx];
      rec.status = 'TAKEN';
      rec.actualTakenTime = actualTakenTime;
      rec.updatedAt = now;
    } else {
      final record = HistoryRecord(
        id: occurrenceId,
        scheduleId: scheduleId,
        hour: scheduledHour,
        minute: scheduledMinute,
        dose: dose,
        scheduledTime: scheduledTime,
        actualTakenTime: actualTakenTime,
        status: 'TAKEN',
        source: sourceVal == 2 ? 'APP' : 'DEVICE',
        createdAt: now,
        updatedAt: now,
      );
      _history.add(record);
    }

    _saveHistory();
    notifyListeners();

    // Acknowledge receipt to clear ESP32 queue
    bleService.sendEventAck(eventId);
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _scheduleHour = prefs.getInt('schedule_hour') ?? 8;
      _scheduleMinute = prefs.getInt('schedule_minute') ?? 0;
      _scheduleDose = prefs.getInt('schedule_dose') ?? 4;
      _scheduleActive = prefs.getBool('schedule_active') ?? true;
      
      final startStr = prefs.getString('medremind_history_start');
      if (startStr != null) {
        _historyStartTime = DateTime.parse(startStr);
      } else {
        _historyStartTime = DateTime.now().subtract(const Duration(days: 3));
        await prefs.setString('medremind_history_start', _historyStartTime.toIso8601String());
      }

      final historyStr = prefs.getString('medremind_history');
      if (historyStr != null) {
        final List<dynamic> decoded = jsonDecode(historyStr);
        _history = decoded.map((item) => HistoryRecord.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint("Error loading history: $e");
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setInt('schedule_hour', _scheduleHour);
      await prefs.setInt('schedule_minute', _scheduleMinute);
      await prefs.setInt('schedule_dose', _scheduleDose);
      await prefs.setBool('schedule_active', _scheduleActive);
      
      final historyStr = jsonEncode(_history.map((rec) => rec.toJson()).toList());
      await prefs.setString('medremind_history', historyStr);
    } catch (e) {
      debugPrint("Error saving history: $e");
    }
  }

  // UI Mapped Getters
  bool get scanning => bleService.state == DeviceConnectionState.scanning;
  bool get connecting => bleService.state == DeviceConnectionState.connecting;
  bool get connected => bleService.state == DeviceConnectionState.connected;
  bool get synchronized => bleService.timeSyncAcked;
  String get deviceName => bleService.connectedDevice?.platformName.isEmpty ?? true
      ? "MedRemind"
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

  Future<void> clearHistory() async {
    _history.clear();
    _historyStartTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('medremind_history');
      await prefs.setString('medremind_history_start', _historyStartTime.toIso8601String());
    } catch (e) {
      debugPrint("Error clearing history: $e");
    }
    _generateOccurrences();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    bleService.removeListener(_onBleServiceChanged);
    super.dispose();
  }
}
