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
    final enabled = await LocalDb.getSetting("app_lock_enabled");
    if (enabled == "true") {
      if (mounted) setState(() => _isLocked = true);

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
