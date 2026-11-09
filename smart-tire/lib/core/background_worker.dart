import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Alarm ID สำหรับ periodic check
const int kAlarmId = 999;

/// Top-level callback — android_alarm_manager_plus เรียกตอนแอปปิดอยู่
@pragma('vm:entry-point')
Future<void> bgNotificationCheck() async {
  try {
    // Background isolate ต้องเปิด DB ใหม่ (ไม่แชร์ instance กับ main isolate)
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'smart_tire.db');
    final db = await openDatabase(path, singleInstance: false);

    // Init local notification plugin
    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    await plugin.initialize(settings);

    int notifId = 500;

    // 1. เช็คยางหมดอายุ + ดอกยางเก่า
    final cars = await db.query('cars');
    for (final car in cars) {
      final carId = (car["id"] ?? "").toString();
      if (carId.isEmpty) continue;

      final tires = await db.query(
        'tires',
        where: 'carId = ?',
        whereArgs: [carId],
      );

      for (final tire in tires) {
        final pos = (tire["position"] ?? "").toString();
        final thaiPos = _getThaiPos(pos);
        final dot = (tire["tireCode"] ?? "").toString().trim();
        final updatedAt = tire["updatedAt"];

        // คำนวณวันสิ้นสุดอายุยางจาก DOT Code
        if (dot.length >= 4) {
          final last4 = dot.substring(dot.length - 4);
          final ww = int.tryParse(last4.substring(0, 2));
          final yy = int.tryParse(last4.substring(2, 4));

          if (ww != null && yy != null && ww >= 1 && ww <= 53) {
            final year = 2000 + yy;
            // ISO 8601: สัปดาห์แรกคือสัปดาห์ที่มีพฤหัสบดีแรก (วันที่ 4 ม.ค. อยู่สัปดาห์ 1 เสมอ)
            final jan4 = DateTime(year, 1, 4);
            // หาวันจันทร์ของสัปดาห์ที่ 1
            final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
            // หาวันแรกของสัปดาห์ ww
            final mfgDate = week1Monday.add(Duration(days: (ww - 1) * 7));

            // คำนวณวันหมดอายุ (5 ปี ระดับวัน)
            int expYear = mfgDate.year + 5;
            int expMonth = mfgDate.month;
            int expDay = mfgDate.day;
            if (expMonth == 2 && expDay == 29) {
              final isLeap = (expYear % 4 == 0) && (expYear % 100 != 0 || expYear % 400 == 0);
              if (!isLeap) expDay = 28;
            }
            final expiryDate = DateTime(expYear, expMonth, expDay);
            final now = DateTime.now();
            final daysLeft = expiryDate.difference(now).inDays;

            // แจ้งเตือนล่วงหน้า 1 สัปดาห์ (1-7 วัน)
            if (daysLeft >= 0 && daysLeft <= 7) {
              final cutoff = now.subtract(const Duration(hours: 24)).toIso8601String();
              final existingWarning = await db.query(
                'notifications',
                where: '(type = ? OR type = ?) AND carId = ? AND position = ? AND createdAt > ?',
                whereArgs: ['tire_expiring_soon', 'deleted_tire_expiring_soon', carId, pos, cutoff],
              );
              if (existingWarning.isEmpty) {
                await db.insert('notifications', {
                  'id': '${now.millisecondsSinceEpoch}_bg_$notifId',
                  'type': 'tire_expiring_soon',
                  'title': '⚠️ ใกล้หมดอายุยาง!',
                  'body': 'ยาง $thaiPos จะครบ 5 ปี ในอีก $daysLeft วัน (วันที่ $expDay/$expMonth/$expYear)',
                  'read': 0,
                  'carId': carId,
                  'position': pos,
                  'createdAt': now.toIso8601String(),
                });
                await _showNotif(
                  plugin, notifId++,
                  '⚠️ ยางใกล้หมดอายุ!',
                  'ยาง $thaiPos จะครบ 5 ปี ในอีก $daysLeft วัน',
                );
              }
            }

            // ยางหมดอายุ (now หลังวันหมดอายุ)
            if (now.isAfter(expiryDate)) {
              final cutoff = now.subtract(const Duration(hours: 24)).toIso8601String();
              final existing = await db.query(
                'notifications',
                where: '(type = ? OR type = ?) AND carId = ? AND position = ? AND createdAt > ?',
                whereArgs: ['tire_age_expired', 'deleted_tire_age_expired', carId, pos, cutoff],
              );
              if (existing.isEmpty) {
                await db.insert('notifications', {
                  'id': '${now.millisecondsSinceEpoch}_bg_$notifId',
                  'type': 'tire_age_expired',
                  'title': 'ยางหมดอายุ!',
                  'body': 'ยาง $thaiPos อายุเกิน 5 ปี ได้เวลาเปลี่ยนยางแล้ว',
                  'read': 0,
                  'carId': carId,
                  'position': pos,
                  'createdAt': now.toIso8601String(),
                });
                await _showNotif(
                  plugin, notifId++,
                  'ยางหมดอายุ!',
                  'ยาง $thaiPos อายุเกิน 5 ปี',
                );
              }
            }
          }
        }

        // ดอกยางเก่า > 90 วัน
        if (updatedAt != null) {
          try {
            final dt = DateTime.parse(updatedAt.toString());
            if (DateTime.now().difference(dt).inDays > 90) {
              final cutoff = DateTime.now()
                  .subtract(const Duration(hours: 24))
                  .toIso8601String();
              final existing = await db.query(
                'notifications',
                where:
                    '(type = ? OR type = ?) AND carId = ? AND position = ? AND createdAt > ?',
                whereArgs: [
                  'tread_depth_reminder',
                  'deleted_tread_depth_reminder',
                  carId,
                  pos,
                  cutoff,
                ],
              );

              if (existing.isEmpty) {
                final now = DateTime.now();
                await db.insert('notifications', {
                  'id': '${now.millisecondsSinceEpoch}_bg_$notifId',
                  'type': 'tread_depth_reminder',
                  'title': 'อัพเดตดอกยาง',
                  'body':
                      'ดอกยาง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน อัพเดตดอกยางเพื่อความปลอดภัย',
                  'read': 0,
                  'carId': carId,
                  'position': pos,
                  'createdAt': now.toIso8601String(),
                });
                await _showNotif(
                  plugin,
                  notifId++,
                  '📸 อัพเดตดอกยาง',
                  'ดอกยาง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน',
                );
              }
            }
          } catch (_) {}
        }

        // ดอกยางต่ำกว่า 1.6 mm
        final depthMm = (tire['lastDepthMm'] as num?)?.toDouble();
        if (depthMm != null && depthMm < 1.6) {
          final now = DateTime.now();
          final cutoff = now.subtract(const Duration(hours: 24)).toIso8601String();
          final existing = await db.query(
            'notifications',
            where: '(type = ? OR type = ?) AND carId = ? AND position = ? AND createdAt > ?',
            whereArgs: ['tread_depth_low', 'deleted_tread_depth_low', carId, pos, cutoff],
          );
          if (existing.isEmpty) {
            await db.insert('notifications', {
              'id': '${now.millisecondsSinceEpoch}_bg_$notifId',
              'type': 'tread_depth_low',
              'title': '🚨 ดอกยางวิกฤต!',
              'body': 'ดอกยาง $thaiPos ต่ำกว่า 1.6 มม. (${depthMm.toStringAsFixed(1)} มม.) ต้องเปลี่ยนยางทันที!',
              'read': 0,
              'carId': carId,
              'position': pos,
              'createdAt': now.toIso8601String(),
            });
            await _showNotif(
              plugin, notifId++,
              '🚨 ดอกยางวิกฤต!',
              'ดอกยาง $thaiPos ต่ำกว่า 1.6 มม. (${depthMm.toStringAsFixed(1)} มม.)',
            );
          }
        }
      }
    }

    await db.close();
  } catch (_) {
    // Silent fail — background task ไม่ควร crash
  }
}

Future<void> _showNotif(
  FlutterLocalNotificationsPlugin plugin,
  int id,
  String title,
  String body,
) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'smart_tire_bg',
      'Smart Tire Background Alerts',
      channelDescription: 'แจ้งเตือนจาก background check',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
  );
  await plugin.show(id, title, body, details);
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
