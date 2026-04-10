import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/background_worker.dart';
import 'core/local_db.dart';
import 'core/local_notification_service.dart';
import 'pages/home_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // เรียก UI ให้แสดงก่อน แล้วทำ initialization ที่ไม่จำเป็นต้อง block
  runApp(const MyApp());
  
  // Background init เพื่อไม่เกาะการแสดง UI
  _backgroundInit();
}

Future<void> _backgroundInit() async {
  try {
    await Permission.notification.request();
  } catch (_) {}
  
  try {
    await LocalNotificationService.init();
  } catch (_) {}
  
  try {
    await LocalDb.init();
  } catch (_) {}
  
  try {
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.periodic(
      const Duration(hours: 6),
      kAlarmId,
      bgNotificationCheck,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: false,
    );
  } catch (_) {}
}

String _getThaiPos(String pos) {
  switch (pos) {
    case 'FL':
      return 'หน้าซ้าย';
    case 'FR':
      return 'หน้าขวา';
    case 'RL':
      return 'หลังซ้าย';
    case 'RR':
      return 'หลังขวา';
    case 'SPARE':
      return 'อะไหล่';
    default:
      return pos;
  }
}

Future<void> _checkTireNotifications() async {
  int notifId = 100;
  try {
    final cars = await LocalDb.getCars();

    for (final car in cars) {
      final carId = (car["id"] ?? "").toString();
      if (carId.isEmpty) continue;

      final tires = await LocalDb.getTires(carId);

      for (final tire in tires) {
        final pos = (tire["position"] ?? "").toString();
        final thaiPos = _getThaiPos(pos);
        final dot = (tire["tireCode"] ?? "").toString().trim();
        final updatedAt = tire["updatedAt"];

        // เช็คอายุยาง ≥ 5 ปี
        if (dot.length >= 4) {
          final last4 = dot.substring(dot.length - 4);
          final yy = int.tryParse(last4.substring(2, 4));
          if (yy != null) {
            final year = 2000 + yy;
            final age = DateTime.now().year - year;
            if (age >= 5) {
              final alreadyNotified = await LocalDb.hasRecentNotification(
                "tire_age_expired",
                carId,
                pos,
              );
              if (!alreadyNotified) {
                await LocalDb.addNotification(
                  type: "tire_age_expired",
                  title: "⚠️ ยางหมดอายุ!",
                  body:
                      "ยางตำแหน่ง $thaiPos (DOT: $dot) อายุเกิน 5 ปี ควรเปลี่ยนยางใหม่",
                  carId: carId,
                  position: pos,
                );
                await LocalNotificationService.show(
                  id: notifId++,
                  title: "⚠️ ยางหมดอายุ!",
                  body:
                      "ยางตำแหน่ง $thaiPos (DOT: $dot) อายุเกิน 5 ปี ควรเปลี่ยนยางใหม่",
                );
              }
            }
          }
        }

        // เช็คข้อมูลดอกยางเก่ากว่า 3 เดือน
        if (updatedAt != null) {
          try {
            final dt = DateTime.parse(updatedAt.toString());
            if (DateTime.now().difference(dt).inDays > 90) {
              final alreadyNotified = await LocalDb.hasRecentNotification(
                "tread_depth_reminder",
                carId,
                pos,
              );
              if (!alreadyNotified) {
                await LocalDb.addNotification(
                  type: "tread_depth_reminder",
                  title: "📸 อัพเดตดอกยาง",
                  body: "ข้อมูลดอกยางตำแหน่ง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน",
                  carId: carId,
                  position: pos,
                );
                await LocalNotificationService.show(
                  id: notifId++,
                  title: "📸 อัพเดตดอกยาง",
                  body: "ข้อมูลดอกยางตำแหน่ง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน",
                );
              }
            }
          } catch (_) {}
        }
      }
    }
  } catch (_) {
    // Silent fail
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLocked = false;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    // Check if lock enabled
    final enabled = await LocalDb.getSetting("app_lock_enabled");
    if (enabled == "true") {
      // Show lock screen immediately
      if (mounted) setState(() => _isLocked = true);

      // Authenticate
      try {
        final success = await auth.authenticate(
          localizedReason: 'กรุณาสแกนเพื่อปลดล็อค',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (success) {
          if (mounted) setState(() => _isLocked = false);
        }
      } catch (e) {
        // If error, keep locked or retry?
        // For now, keep locked.
        debugPrint("Auth error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'TireAI',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      ),
      home: _isLocked
          ? const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 64, color: Colors.white),
                    SizedBox(height: 16),
                    Text("App Locked", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            )
          : const HomePage(),
    );
  }
}
