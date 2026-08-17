import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'providers/device_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BLEService>(
          create: (_) => BLEService(),
        ),
        ChangeNotifierProxyProvider<BLEService, DeviceProvider>(
          create: (context) => DeviceProvider(
            Provider.of<BLEService>(context, listen: false),
          ),
          update: (_, ble, previous) => previous ?? DeviceProvider(ble),
        ),
      ],
      child: const GozieMedicationApp(),
    ),
  );
}

class GozieMedicationApp extends StatelessWidget {
  const GozieMedicationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gozie Medication Reminder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA272),
          brightness: Brightness.light,
          primary: const Color(0xFF0EA272),
          secondary: const Color(0xFF00B0FF),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1E293B)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
