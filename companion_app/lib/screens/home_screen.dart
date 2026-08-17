import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

enum ActiveField {
  time,
  dose,
  activeStatus,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTabIndex = 0;
  
  // Local input buffer state (initialized from provider on tab entry)
  bool _hasInitializedScheduleState = false;
  String _typedTime = "0800"; // Represents HHMM
  bool _isPM = true;
  String _typedDose = "4";
  bool _isActiveStatus = true;
  
  ActiveField _activeField = ActiveField.time;
  bool _showSavedSuccess = false;

  // Format Helper: Day Month Year (e.g. Mon, 17 Aug, 2026)
  String _formatDate(DateTime dt) {
    const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return "${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  String _formatLastSync(DateTime? dt) {
    if (dt == null) return "Never";
    final hr = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "Today, ${hr.toString().padLeft(2, '0')}:$min $ampm";
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);

    // Initialize local keypad buffers from global provider state once on tab entry
    if (_selectedTabIndex == 1 && !_hasInitializedScheduleState) {
      final hour = deviceProvider.scheduleHour;
      final minute = deviceProvider.scheduleMinute;
      int hr12 = hour % 12;
      if (hr12 == 0) hr12 = 12;
      
      _typedTime = hr12.toString().padLeft(2, '0') + minute.toString().padLeft(2, '0');
      _isPM = hour >= 12;
      _typedDose = deviceProvider.scheduleDose.toString();
      _isActiveStatus = deviceProvider.scheduleActive;
      _activeField = ActiveField.time;
      _hasInitializedScheduleState = true;
    }

    Widget activeBody;
    switch (_selectedTabIndex) {
      case 0:
        activeBody = _buildHomeTab(deviceProvider);
        break;
      case 1:
        activeBody = _buildScheduleTab(deviceProvider);
        break;
      case 2:
        activeBody = _buildSettingsTab(deviceProvider);
        break;
      case 3:
        activeBody = _buildAboutTab();
        break;
      default:
        activeBody = _buildHomeTab(deviceProvider);
    }

    return Scaffold(
      body: activeBody,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0EA272),
        unselectedItemColor: const Color(0xFF64748B),
        backgroundColor: Colors.white,
        elevation: 8,
        onTap: (index) {
          setState(() {
            _selectedTabIndex = index;
            // Force re-initialization of values if entering/leaving Schedule tab
            _hasInitializedScheduleState = false;
            _showSavedSuccess = false;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.medication_outlined),
            activeIcon: Icon(Icons.medication),
            label: "Schedule",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: "Settings",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            activeIcon: Icon(Icons.info),
            label: "About",
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(DeviceProvider provider) {
    final isScheduleActive = provider.scheduleActive;
    final hour = provider.scheduleHour;
    final minute = provider.scheduleMinute;
    final dose = provider.scheduleDose;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Gozie MedReminder",
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: provider.connected ? const Color(0xFF0EA272) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  provider.connected ? "Connected" : "Disconnected",
                  style: TextStyle(
                    color: provider.connected ? const Color(0xFF0EA272) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor: provider.connected ? const Color(0x1F0EA272) : const Color(0x1F94A3B8),
              child: Icon(
                provider.connected ? Icons.link_rounded : Icons.link_off_rounded,
                color: provider.connected ? const Color(0xFF0EA272) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Scan button when disconnected
                  if (!provider.connected) _buildScanButton(provider),

                  // Next Medication card
                  _buildNextMedicationCard(provider, isScheduleActive, hour, minute, dose),

                  // Medication Schedule Header & Card
                  _buildScheduleSection(provider, isScheduleActive, hour, minute, dose),

                  // Device status card
                  _buildStatusSection(provider, isScheduleActive),
                  
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton(DeviceProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: provider.scanning ? null : provider.scanAndConnect,
          icon: provider.scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.bluetooth_searching_rounded, color: Colors.white),
          label: Text(
            provider.scanning ? "Scanning for Gozie..." : "Scan & Connect Device",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0EA272),
            disabledBackgroundColor: Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextMedicationCard(
    DeviceProvider provider,
    bool isScheduleActive,
    int hour,
    int minute,
    int dose,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF0EA272),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA272).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Stylized illustration painter background
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 150,
            child: CustomPaint(
              painter: MedicationIllustrationPainter(),
            ),
          ),
          // Card Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.link_rounded, color: Colors.white70, size: 16),
                    SizedBox(width: 6),
                    Text(
                      "NEXT MEDICATION",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isScheduleActive 
                          ? "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}"
                          : "--:-- --",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(provider.currentPhoneTime),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("DOSES", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text(
                          isScheduleActive ? "$dose Pill(s)" : "-",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("STATUS", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text(
                          isScheduleActive ? "Scheduled" : "Inactive",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(
    DeviceProvider provider,
    bool isScheduleActive,
    int hour,
    int minute,
    int dose,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Medication Schedule",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              TextButton(
                onPressed: () {
                  // Switch bottom navigation tab directly to Schedule keypad tab
                  setState(() {
                    _selectedTabIndex = 1;
                    _hasInitializedScheduleState = false;
                  });
                },
                child: const Text(
                  "Edit Schedule >",
                  style: TextStyle(color: Color(0xFF0EA272), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0x1F0EA272),
              child: const Icon(Icons.watch_later_outlined, color: Color(0xFF0EA272)),
            ),
            title: Text(
              isScheduleActive 
                  ? "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}"
                  : "No active schedule",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(isScheduleActive ? "Every Day" : "Enable in schedule tab"),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x1F0EA272),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isScheduleActive ? "$dose Pill(s)" : "-",
                style: const TextStyle(color: Color(0xFF0EA272), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection(DeviceProvider provider, bool isScheduleActive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Device Status",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (provider.connected)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF0EA272), size: 16),
                    SizedBox(width: 4),
                    Text(
                      "All Good",
                      style: TextStyle(color: Color(0xFF0EA272), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusIndicator(Icons.battery_std_rounded, "Battery", "N/A"),
                _buildStatusIndicator(Icons.notifications_active_outlined, "Alarm", isScheduleActive ? "Enabled" : "Disabled"),
                _buildStatusIndicator(Icons.wb_sunny_outlined, "Night Light", "N/A"),
                _buildStatusIndicator(Icons.storage_rounded, "Storage", "Good"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleTab(DeviceProvider provider) {
    // Check validation filters
    final parsedHour = int.tryParse(_typedTime.substring(0, 2)) ?? 0;
    final parsedMinute = int.tryParse(_typedTime.substring(2, 4)) ?? 0;
    final isTimeValid = (parsedHour >= 1 && parsedHour <= 12) && (parsedMinute >= 0 && parsedMinute <= 59);

    final parsedDose = int.tryParse(_typedDose) ?? 0;
    final isDoseValid = parsedDose >= 1 && parsedDose <= 99;

    final isFormValid = isTimeValid && isDoseValid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Schedule Reminders"),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Input fields display row
              Row(
                children: [
                  // Medication Time Box
                  Expanded(
                    flex: 3,
                    child: _buildTactileInputBox(
                      label: "Medication Time",
                      isActive: _activeField == ActiveField.time,
                      isError: !isTimeValid,
                      onTap: () => setState(() => _activeField = ActiveField.time),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${_typedTime.substring(0, 2)}:${_typedTime.substring(2, 4)}",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: !isTimeValid 
                                  ? Colors.red 
                                  : (_activeField == ActiveField.time ? const Color(0xFF0EA272) : const Color(0xFF1E293B)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPM = !_isPM;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA272).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isPM ? "PM" : "AM",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0EA272),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dose Box
                  Expanded(
                    flex: 1,
                    child: _buildTactileInputBox(
                      label: "Dose",
                      value: _typedDose,
                      isActive: _activeField == ActiveField.dose,
                      isError: !isDoseValid,
                      onTap: () => setState(() => _activeField = ActiveField.dose),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Active Box
                  Expanded(
                    flex: 1,
                    child: _buildTactileInputBox(
                      label: "Active",
                      isActive: _activeField == ActiveField.activeStatus,
                      isError: false,
                      onTap: () => setState(() => _activeField = ActiveField.activeStatus),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isActiveStatus = !_isActiveStatus;
                          });
                        },
                        child: Text(
                          _isActiveStatus ? "ON" : "OFF",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _isActiveStatus ? const Color(0xFF0EA272) : Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 10),
              
              // Input helper instructions
              Center(
                child: Text(
                  _activeField == ActiveField.time 
                      ? "Time Active: Type 4 digits. Tap AM/PM badge to toggle period." 
                      : _activeField == ActiveField.dose 
                          ? "Dose Active: Type dose value using keypad."
                          : "Active Box Selected: Tap value above to toggle ON/OFF.",
                  style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                ),
              ),
              
              const SizedBox(height: 12),

              // 3x4 Circular Tactile Grid
              Table(
                children: [
                  TableRow(
                    children: [
                      _buildKeypadButton("1"),
                      _buildKeypadButton("2"),
                      _buildKeypadButton("3"),
                    ],
                  ),
                  TableRow(
                    children: [
                      _buildKeypadButton("4"),
                      _buildKeypadButton("5"),
                      _buildKeypadButton("6"),
                    ],
                  ),
                  TableRow(
                    children: [
                      _buildKeypadButton("7"),
                      _buildKeypadButton("8"),
                      _buildKeypadButton("9"),
                    ],
                  ),
                  TableRow(
                    children: [
                      _buildKeypadButton("C", isRed: true),
                      _buildKeypadButton("0"),
                      _buildKeypadButton("←"),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 16),

              // Save Section / Success confirmation indicator
              if (_showSavedSuccess)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF0EA272), size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Schedule Saved ✓",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0EA272),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isFormValid ? () => _saveAndSyncSchedule(provider) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA272),
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "SAVE SCHEDULE",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTactileInputBox({
    required String label,
    Widget? child,
    String? value,
    required bool isActive,
    required bool isError,
    required VoidCallback onTap,
    Color? valueColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x0C0EA272) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError 
                ? Colors.red 
                : isActive 
                    ? const Color(0xFF0EA272) 
                    : const Color(0xFFE2E8F0),
            width: isActive ? 2.0 : 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF0EA272).withValues(alpha: 0.1),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isError ? Colors.red : Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            child ?? Text(
              value ?? "",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isError 
                    ? Colors.red 
                    : valueColor ?? (isActive ? const Color(0xFF0EA272) : const Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadButton(String key, {bool isRed = false}) {
    Color buttonColor;
    Color textColor;

    if (isRed) {
      buttonColor = const Color(0xFFFCA5A5); // Soft tactile medical red
      textColor = const Color(0xFFB91C1C);
    } else {
      buttonColor = const Color(0xFFE2EAF4); // Soft medical tactile blue
      textColor = const Color(0xFF1E293B);
    }

    return TactileButton(
      label: key,
      color: buttonColor,
      textColor: textColor,
      onTap: () => _handleKeypadPress(key),
    );
  }

  void _handleKeypadPress(String key) {
    setState(() {
      _showSavedSuccess = false; // Hide checkmark success label on typing
      
      switch (key) {
        case "C":
          if (_activeField == ActiveField.time) {
            _typedTime = "1200";
          } else if (_activeField == ActiveField.dose) {
            _typedDose = "1";
          }
          break;

        case "←":
          if (_activeField == ActiveField.time) {
            _typedTime = "0${_typedTime.substring(0, 3)}";
          } else if (_activeField == ActiveField.dose) {
            if (_typedDose.length > 1) {
              _typedDose = _typedDose.substring(0, _typedDose.length - 1);
            } else {
              _typedDose = "1";
            }
          }
          break;

        default: // Numeric values 0-9
          if (_activeField == ActiveField.time) {
            _typedTime = (_typedTime + key).substring((_typedTime + key).length - 4);
          } else if (_activeField == ActiveField.dose) {
            if (_typedDose == "0") {
              _typedDose = key;
            } else if (_typedDose.length < 2) {
              _typedDose += key;
            }
          }
      }
    });
  }

  void _saveAndSyncSchedule(DeviceProvider provider) {
    int hour = int.parse(_typedTime.substring(0, 2));
    final minute = int.parse(_typedTime.substring(2, 4));
    final dose = int.parse(_typedDose);

    // Convert 12-hour values back to 24-hour hour for hardware syncing
    if (_isPM && hour < 12) {
      hour += 12;
    } else if (!_isPM && hour == 12) {
      hour = 0;
    }

    provider.updateSchedule(hour, minute, dose, _isActiveStatus);

    setState(() {
      _showSavedSuccess = true;
    });

    // Automatically navigate back to Home Dashboard tab after 800ms to simulate device confirmation
    Timer(const Duration(milliseconds: 800), () {
      if (mounted && _selectedTabIndex == 1) {
        setState(() {
          _selectedTabIndex = 0;
          _showSavedSuccess = false;
        });
      }
    });
  }

  Widget _buildSettingsTab(DeviceProvider provider) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Time Synchronization Card
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF0EA272).withValues(alpha: 0.1),
                    child: const Icon(Icons.watch_later_outlined, color: Color(0xFF0EA272)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Update device time",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0EA272),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Last Time Updated",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          _formatLastSync(provider.lastSyncTime),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider.synchronized ? "Phone time is synced with device." : "Not in sync",
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: provider.connected ? provider.syncTime : null,
                    icon: const Icon(Icons.sync_rounded, size: 14, color: Colors.white),
                    label: const Text(
                      "Update Time",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA272),
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Bluetooth Section
          const Text("Bluetooth", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth, color: Color(0xFF0EA272)),
                  title: const Text("Auto Reconnect"),
                  subtitle: const Text("Automatically reconnect to device"),
                  trailing: Switch(
                    value: true,
                    activeThumbColor: const Color(0xFF0EA272),
                    onChanged: (val) {},
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.search, color: Color(0xFF0EA272)),
                  title: const Text("Scan for Device"),
                  subtitle: const Text("Search for Gozie-MedReminder"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          // 3. Device Section
          const Text("Device", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Color(0xFF0EA272)),
                  title: const Text("Device Information"),
                  subtitle: const Text("View device details"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.branding_watermark_outlined, color: Color(0xFF0EA272)),
                  title: const Text("Device Name"),
                  subtitle: Text(provider.deviceName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          // 4. Medication Section
          const Text("Medication", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link_rounded, color: Color(0xFF0EA272)),
              title: const Text("Default Dose"),
              subtitle: Text("${provider.scheduleDose} Pill(s)"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("About this app"),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Color(0x1F0EA272),
              child: Icon(Icons.local_hospital_rounded, size: 40, color: Color(0xFF0EA272)),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              "Medication Reminder",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Instructions",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildInstructionStep("1", "Turn on Bluetooth on your mobile device."),
          _buildInstructionStep("2", "Turn on the Medication Reminder device."),
          _buildInstructionStep("3", "Tap 'Scan & Connect' on the home tab to link the device."),
          _buildInstructionStep("4", "Select 'Settings' and press 'Update Time' to update the device internal clock."),
          _buildInstructionStep("5", "Select the 'Schedule' tab to set medication reminders and alarms."),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF0EA272),
            child: Text(
              num,
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(IconData icon, String label, String status) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF0EA272), size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }
}

class TactileButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const TactileButton({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isRedButton = widget.color == const Color(0xFFFCA5A5);
    final gradientColors = isRedButton
        ? [
            _isPressed ? widget.color : const Color(0xFFFFD1D1),
            widget.color,
            _isPressed ? widget.color : const Color(0xFFE58787),
          ]
        : [
            _isPressed ? widget.color : const Color(0xFFF1F7FC),
            widget.color,
            _isPressed ? widget.color : const Color(0xFFC8DAE9),
          ];

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        margin: const EdgeInsets.all(9),
        transform: Matrix4.translationValues(0, _isPressed ? 3.0 : 0.0, 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 5,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.4),
                    blurRadius: 1,
                    offset: const Offset(0, -1),
                  ),
                ],
          border: Border.all(
            color: Color.alphaBlend(Colors.black.withValues(alpha: 0.15), widget.color),
            width: 1.5,
          ),
        ),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MedicationIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw clock circle
    final center = Offset(size.width * 0.7, size.height * 0.5);
    final radius = size.height * 0.45;
    canvas.drawCircle(center, radius, paint);
    // Draw clock hands
    canvas.drawLine(center, Offset(center.dx, center.dy - radius * 0.6), paint);
    canvas.drawLine(center, Offset(center.dx + radius * 0.4, center.dy), paint);

    // Draw pill bottle
    final bottlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final bottleOutline = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Cap
    final capRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.25, size.height * 0.22, size.width * 0.22, size.height * 0.08),
      const Radius.circular(3),
    );
    canvas.drawRRect(capRect, bottlePaint);
    canvas.drawRRect(capRect, bottleOutline);

    // Body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.21, size.height * 0.3, size.width * 0.3, size.height * 0.45),
      const Radius.circular(8),
    );
    canvas.drawRRect(bodyRect, bottlePaint);
    canvas.drawRRect(bodyRect, bottleOutline);

    // Label/Cross on bottle
    final labelPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final crossX = size.width * 0.36;
    final crossY = size.height * 0.52;
    canvas.drawLine(Offset(crossX - 6, crossY), Offset(crossX + 6, crossY), labelPaint);
    canvas.drawLine(Offset(crossX, crossY - 6), Offset(crossX, crossY + 6), labelPaint);

    // Draw a pill capsule next to bottle
    final pillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final pillOutline = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.46, size.height * 0.65, size.width * 0.2, size.height * 0.12),
      const Radius.circular(8),
    );
    canvas.drawRRect(pillRect, pillPaint);
    canvas.drawRRect(pillRect, pillOutline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
