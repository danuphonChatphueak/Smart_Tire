import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../core/local_db.dart';
import '../core/local_notification_service.dart';
import '../core/tire_calculator.dart';
import '../widgets/vehicle_center_layout.dart';
import 'capture_instruction_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'tire_history_page.dart';

enum ScanMode { tread, sidewall }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String currentCarId = "";
  String carName = "กำลังโหลด...";
  int unreadCount = 0;

  List<Map<String, dynamic>> cars = [];

  // tires map: FL/FR/RL/RR/SPARE
  final Map<String, dynamic> tires = {
    "FL": _newTire(),
    "FR": _newTire(),
    "RL": _newTire(),
    "RR": _newTire(),
    "SPARE": _newTire(),
  };

  bool swapMode = false;
  String? first;
  String? second;

  bool _showWarningBanner = false;
  Timer? _bannerTimer;

  bool get hasCar => currentCarId.isNotEmpty;

  // -----------------------------
  // Tire helpers
  // -----------------------------
  static Map<String, dynamic> _newTire() => {
    "dotCode": null,
    "sizeCode": null,
    "dotConf": null,
    "depthMm": null,
    "depthConf": null,
    "lifeKm": null,
    "lifePercent": 0.0,
    "lifeColor": Colors.grey.toARGB32(),
    "updatedAt": null,
    "_id": null,
  };

  double _calcLifeKmFromMm(double mm) {
    // Usable tread starts from 1.6mm up to ~8.0mm
    // Formula: (current_depth - 1.6) * 7500 km/mm
    final truncatedMm = (mm * 10).truncateToDouble() / 10;
    final km = (truncatedMm - 1.6) * 7500.0;
    if (km < 0) return 0;
    if (km > 60000) return 60000;
    return km;
  }

  /// คำนวณระยะทางปลอดภัย: 1 mm = 7,500 km
  String _safeDistanceLabel(double? depth) {
    if (depth == null) return "-";
    final truncatedMm = (depth * 10).truncateToDouble() / 10;
    final km = truncatedMm * 7500.0;
    final formatted = km
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return "$formatted กิโลเมตร";
  }

  int _lifeColorFromPercent(double p) {
    if (p >= 75) return Colors.green.toARGB32();
    if (p >= 50) return Colors.yellow.toARGB32();
    if (p >= 25) return Colors.orange.toARGB32();
    return Colors.red.toARGB32();
  }

  String _dotAgeLabel(String? dot) {
    final manufacturedDate = _getProductionDateFromDot(dot);
    if (manufacturedDate == null) return "-";

    final expiryDate = _getExpiryDate(manufacturedDate);
    final now = DateTime.now();

    if (now.isAfter(expiryDate)) {
      return "ยางหมดอายุแล้ว";
    }

    final daysLeft = expiryDate.difference(now).inDays;
    final thaiMonths = [
      "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน",
      "พฤษภาคม", "มิถุนายน", "กรกฎาคม", "สิงหาคม",
      "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
    ];
    final expiryMonthName = thaiMonths[expiryDate.month - 1];
    final expiryDateStr = "วันที่ ${expiryDate.day} $expiryMonthName ${expiryDate.year + 543}";

    // คำนวณ ปี เดือน วัน ที่เหลือ
    int years = expiryDate.year - now.year;
    int months = expiryDate.month - now.month;
    int days = expiryDate.day - now.day;
    if (days < 0) {
      months -= 1;
      final lastDay = DateTime(expiryDate.year, expiryDate.month, 0).day;
      days += lastDay;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    // แจ้งเตือนล่วงหน้าถ้าเหลือ <= 7 วัน
    if (daysLeft <= 7) {
      return "⚠️ ใกล้หมดอายุ! เหลือ $daysLeft วัน\n(หมดอายุ: $expiryDateStr)";
    }

    String remaining = "";
    if (years > 0) remaining += "$years ปี ";
    if (months > 0) remaining += "$months เดือน ";
    remaining += "$days วัน";

    return "เหลือ $remaining\n(หมดอายุ: $expiryDateStr)";
  }

  DateTime _getExpiryDate(DateTime manufacturedDate) {
    int expiryYear = manufacturedDate.year + 5;
    int expiryMonth = manufacturedDate.month;
    int expiryDay = manufacturedDate.day;
    if (expiryMonth == 2 && expiryDay == 29) {
      bool isLeap = (expiryYear % 4 == 0) && (expiryYear % 100 != 0 || expiryYear % 400 == 0);
      if (!isLeap) expiryDay = 28;
    }
    return DateTime(expiryYear, expiryMonth, expiryDay);
  }

  bool _isExpired(String? dot) {
    final manufacturedDate = _getProductionDateFromDot(dot);
    if (manufacturedDate == null) return false;
    return DateTime.now().isAfter(_getExpiryDate(manufacturedDate));
  }

  bool _isExpiringSoon(String? dot) {
    final manufacturedDate = _getProductionDateFromDot(dot);
    if (manufacturedDate == null) return false;
    final expiry = _getExpiryDate(manufacturedDate);
    final daysLeft = expiry.difference(DateTime.now()).inDays;
    return daysLeft > 0 && daysLeft <= 7;
  }

  DateTime? _getProductionDateFromDot(String? dot) {
    if (dot == null) return null;
    final s = dot.replaceAll(RegExp(r"\s+"), "");
    if (s.length < 4) return null;
    final last4 = s.substring(s.length - 4);
    final ww = int.tryParse(last4.substring(0, 2));
    final yy = int.tryParse(last4.substring(2, 4));
    if (ww == null || yy == null || ww < 1 || ww > 53) return null;

    final year = 2000 + yy;
    // ISO 8601: สัปดาห์แรกคือสัปดาห์ที่มีพฤหัสบดีแรก (วันที่ 4 ม.ค. อยู่สัปดาห์ 1 เสมอ)
    final jan4 = DateTime(year, 1, 4);
    // หาวันจันทร์ของสัปดาห์ที่ 1
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    // หาวันแรกของสัปดาห์ ww (วันจันทร์)
    return week1Monday.add(Duration(days: (ww - 1) * 7));
  }

  bool _isTreadOld(Map<String, dynamic> t) {
    final updatedAt = t["updatedAt"];
    if (updatedAt == null) return false;
    try {
      final dt = DateTime.parse(updatedAt.toString());
      return DateTime.now().difference(dt).inDays > 90;
    } catch (_) {
      return false;
    }
  }

  bool _hasAnyIssue() {
    for (var pos in tires.keys) {
      final t = tires[pos];
      if (t == null) continue;
      if (_isExpired(t["dotCode"]?.toString())) return true;
      if (_isTreadOld(t)) return true;
    }
    return false;
  }

  // -----------------------------
  // CARS — Local DB
  // -----------------------------
  @override
  void initState() {
    super.initState();
    _bootstrapCars();
    _loadUnreadCount();
    _checkPrivacyPolicy();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await LocalDb.getUnreadCount();
      if (!mounted) return;
      setState(() {
        unreadCount = count;
      });
    } catch (_) {}
  }

  Future<void> _checkPrivacyPolicy() async {
    final accepted = await LocalDb.getSetting("app_privacy_accepted");
    if (accepted != "true") {
      // Small delay to ensure the UI is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showPrivacyPolicyPopup();
      });
    }
  }

  void _showPrivacyPolicyPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          "ข้อมูลแอพและความเป็นส่วนตัว (Privacy Policy)",
          style: TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const SingleChildScrollView(
          child: Text(
            "• แอปพลิเคชันรองรับเฉพาะรถยนต์ส่วนบุคคล 4 ล้อ เช่นรถเก๋งหรือรถกระบะ\n"
            "• แอปพลิเคชันเพื่อให้ผู้ใช้ได้ทราบถึงข้อมูลยางรถยนต์ของตนเองในปัจจุบัน\n"
            "• ข้อมูลทั้งหมด (รถ, ยาง, ประวัติ) ถูกจัดเก็บในเครื่องของคุณเท่านั้น (Local Storage)\n"
            "• รูปถ่ายจะถูกส่งไปประมวลผลที่ AI Server และถูกลบทิ้งทันทีหลังวิเคราะห์เสร็จสิ้น\n"
            "• ไม่มีการเก็บข้อมูลส่วนตัวของผู้ใช้บน Cloud",
            style: TextStyle(color: Colors.white, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              await LocalDb.setSetting("app_privacy_accepted", "true");
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              "ยอมรับและใช้งาน",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bootstrapCars() async {
    try {
      final list = await LocalDb.getCars();

      if (list.isEmpty) {
        final created = await LocalDb.createCar(null);
        setState(() {
          cars = [created];
          currentCarId = (created["id"] ?? "").toString();
          carName = (created["carName"] ?? "รถคันที่ 1").toString();
        });
        _loadTiresForCar(currentCarId);
      } else {
        final firstCar = list.first;
        setState(() {
          cars = list;
          currentCarId = (firstCar["id"] ?? "").toString();
          carName = (firstCar["carName"] ?? "รถคันที่ 1").toString();
        });
        _loadTiresForCar(currentCarId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => carName = "โหลดรถไม่สำเร็จ");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("โหลดรถไม่สำเร็จ: $e")));
    }
  }

  Future<void> _addCar() async {
    try {
      final created = await LocalDb.createCar(null);

      setState(() {
        cars = [...cars, created];
        currentCarId = (created["id"] ?? "").toString();
        carName = (created["carName"] ?? "รถคันใหม่").toString();
      });

      // Load tires for the new car (which will be empty and clear the previous state)
      _loadTiresForCar(currentCarId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("เพิ่มรถแล้ว: $carName")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("เพิ่มรถไม่สำเร็จ: $e")));
    }
  }

  Future<void> _pickCar() async {
    if (cars.isEmpty) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: ListView.separated(
          itemCount: cars.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = cars[i];
            final id = (c["id"] ?? "").toString();
            final name = (c["carName"] ?? "รถคันที่ ${i + 1}").toString();
            final isCurrent = id == currentCarId;

            return ListTile(
              title: Text(name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(id, style: const TextStyle(color: Colors.white54)),
              trailing: isCurrent
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(context, c),
              onLongPress: () async {
                await _confirmDeleteCarById(id, name, closeSheet: true);
              },
            );
          },
        ),
      ),
    );

    if (selected == null) return;
    setState(() {
      currentCarId = (selected["id"] ?? "").toString();
      carName = (selected["carName"] ?? "รถ").toString();
      _loadTiresForCar(currentCarId);
    });
  }

  Future<void> _renameCurrentCar() async {
    if (!hasCar) return;

    final newName = await _renameDialog(context, carName);
    if (newName == null || newName.trim().isEmpty) return;

    try {
      final updated = await LocalDb.renameCar(currentCarId, newName.trim());

      setState(() {
        carName = (updated["carName"] ?? newName.trim()).toString();
        cars = cars.map((c) {
          final id = (c["id"] ?? "").toString();
          if (id == currentCarId) return {...c, "carName": carName};
          return c;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("เปลี่ยนชื่อไม่สำเร็จ: $e")));
    }
  }

  // -----------------------------
  // Load Tires — Local DB
  // -----------------------------
  Future<void> _loadTiresForCar(String carId) async {
    if (carId.isEmpty) return;
    try {
      setState(() {
        tires["FL"] = _newTire();
        tires["FR"] = _newTire();
        tires["RL"] = _newTire();
        tires["RR"] = _newTire();
        tires["SPARE"] = _newTire();
      });

      final list = await LocalDb.getTires(carId);
      for (final item in list) {
        final pos = item["position"] ?? "";
        if (!tires.containsKey(pos)) continue;

        final t = tires[pos]!;
        t["_id"] = item["id"];
        t["dotCode"] = item["tireCode"];
        t["sizeCode"] = item["sizeCode"];

        final mm = (item["lastDepthMm"] as num?)?.toDouble();
        if (mm != null) {
          t["depthMm"] = mm;
          t["lifeKm"] = _calcLifeKmFromMm(mm);
        }

        final dot = t["dotCode"]?.toString();
        if (mm != null || (dot != null && dot.isNotEmpty)) {
          final p = TireCalculator.calculateHealthPercentage(dotCode: dot, treadDepth: mm);
          t["lifePercent"] = p;
          t["lifeColor"] = _lifeColorFromPercent(p);
        }
        t["updatedAt"] = item["updatedAt"];
        tires[pos] = t;
      }

      setState(() {});
      _triggerWarningBanner();
    } catch (e) {
      // print("Load tires failed: $e");
    }
  }

  void _triggerWarningBanner() {
    if (_hasAnyIssue()) {
      setState(() => _showWarningBanner = true);
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showWarningBanner = false);
      });
      _checkImmediateNotifications();
    } else {
      setState(() => _showWarningBanner = false);
      _bannerTimer?.cancel();
    }
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

  Future<void> _checkImmediateNotifications() async {
    if (!hasCar) return;
    int notifId = DateTime.now().millisecondsSinceEpoch % 100000;

    for (final pos in tires.keys) {
      final t = tires[pos];
      if (t == null) continue;

      final thaiPos = _getThaiPos(pos);
      final dot = (t["dotCode"] ?? "").toString().trim();

      // Expired 5 years
      if (_isExpired(dot)) {
        final already = await LocalDb.hasRecentNotification(
          "tire_age_expired",
          currentCarId,
          pos,
        );
        if (!already) {
          await LocalDb.addNotification(
            type: "tire_age_expired",
            title: "ยางหมดอายุ!",
            body: "ยาง $thaiPos อายุเกิน 5 ปี ได้เวลาเปลี่ยนยางแล้ว",
            carId: currentCarId,
            position: pos,
          );
          await LocalNotificationService.show(
            id: notifId++,
            title: "ยางหมดอายุ!",
            body: "ยาง $thaiPos อายุเกิน 5 ปี ได้เวลาเปลี่ยนยางแล้ว",
          );
          _loadUnreadCount();
        }
      }

      // Tread old
      if (_isTreadOld(t)) {
        final already = await LocalDb.hasRecentNotification(
          "tread_depth_reminder",
          currentCarId,
          pos,
        );
        if (!already) {
          await LocalDb.addNotification(
            type: "tread_depth_reminder",
            title: "อัพเดตดอกยาง",
            body:
                "ดอกยาง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน อัพเดตดอกยางเพื่อความปลอดภัย",
            carId: currentCarId,
            position: pos,
          );
          await LocalNotificationService.show(
            id: notifId++,
            title: "อัพเดตดอกยาง",
            body:
                "ดอกยาง $thaiPos ไม่ได้อัพเดตเกิน 3 เดือน อัพเดตดอกยางเพื่อความปลอดภัย",
          );
          _loadUnreadCount();
        }
      }

      // ยางใกล้หมดอายุ ≤ 7 วัน
      if (_isExpiringSoon(dot) && !_isExpired(dot)) {
        final already = await LocalDb.hasRecentNotification(
          "tire_expiring_soon",
          currentCarId,
          pos,
        );
        if (!already) {
          await LocalDb.addNotification(
            type: "tire_expiring_soon",
            title: "⚠️ ยางใกล้หมดอายุ!",
            body: "ยาง $thaiPos ใกล้หมดอายุ 5 ปีแล้ว! ควรเตรียมเปลี่ยนยาง",
            carId: currentCarId,
            position: pos,
          );
          await LocalNotificationService.show(
            id: notifId++,
            title: "⚠️ ยางใกล้หมดอายุ!",
            body: "ยาง $thaiPos ใกล้หมดอายุ 5 ปีแล้ว! ควรเตรียมเปลี่ยนยาง",
          );
          _loadUnreadCount();
        }
      }

      // ดอกยางต่ำกว่า 1.6 mm
      final depthMm = (t["depthMm"] as num?)?.toDouble();
      if (depthMm != null && depthMm < 1.6) {
        final already = await LocalDb.hasRecentNotification(
          "tread_depth_low",
          currentCarId,
          pos,
        );
        if (!already) {
          await LocalDb.addNotification(
            type: "tread_depth_low",
            title: "🚨 ดอกยางวิกฤต!",
            body: "ดอกยาง $thaiPos ต่ำกว่า 1.6 มม. (${depthMm.toStringAsFixed(1)} มม.) ต้องเปลี่ยนยางทันที!",
            carId: currentCarId,
            position: pos,
          );
          await LocalNotificationService.show(
            id: notifId++,
            title: "🚨 ดอกยางวิกฤต!",
            body: "ดอกยาง $thaiPos ต่ำกว่า 1.6 มม. (${depthMm.toStringAsFixed(1)} มม.) ต้องเปลี่ยนยางทันที!",
          );
          _loadUnreadCount();
        }
      }
    }
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        title: GestureDetector(
          onTap: hasCar ? _renameCurrentCar : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                carName,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (hasCar)
                const Icon(Icons.edit, size: 18, color: Colors.black54),
            ],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            tooltip: "การตั้งค่า",
            icon: const Icon(Icons.settings, color: Colors.black87),
            onPressed: () async {
              final cleared = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              if (cleared == true) {
                _bootstrapCars();
              }
            },
          ),
          // 🔔 Notification bell with badge
          Stack(
            children: [
              IconButton(
                tooltip: "การแจ้งเตือน",
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: Colors.black87,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsPage(),
                    ),
                  );
                  _loadUnreadCount();
                },
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      unreadCount > 99 ? "99+" : "$unreadCount",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: "เลือกคันรถ",
            icon: const Icon(Icons.directions_car, color: Colors.black87),
            onPressed: _pickCar,
          ),
          IconButton(
            tooltip: "เพิ่มรถ",
            icon: const Icon(Icons.add_circle_outline, color: Colors.black87),
            onPressed: _addCar,
          ),
        ],
      ),
      body: Stack(
        children: [
          VehicleCenterLayout(
            tires: tires,
            swapMode: swapMode,
            selectedFirst: first,
            selectedSecond: second,
            onTapTire: (pos) async {
              if (!hasCar) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("ยังไม่มีรถ โปรดกด + เพื่อเพิ่มรถก่อน"),
                  ),
                );
                return;
              }

              if (swapMode) {
                setState(() {
                  if (first == null) {
                    first = pos;
                  } else if (first != pos && second == null) {
                    second = pos;
                    _processSwap(first!, second!);
                  }
                });
                return;
              }

              await _openTireActionSheet(pos);
            },
          ),
          if (_showWarningBanner)
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "พบปัญหาเกี่ยวกับยาง! กรุณาตรวจสอบสถานะยางแต่ละตำแหน่ง",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              backgroundColor: swapMode ? Colors.red : const Color(0xFFFFD700),
              foregroundColor: swapMode ? Colors.white : Colors.black,
              icon: Icon(swapMode ? Icons.close : Icons.swap_horiz),
              label: Text(swapMode ? 'ยกเลิก' : 'สลับยาง'),
              onPressed: () {
                setState(() {
                  swapMode = !swapMode;
                  if (!swapMode) {
                    first = null;
                    second = null;
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processSwap(String pos1, String pos2) async {
    final t1 = tires[pos1];
    final t2 = tires[pos2];

    final id1 = t1?["_id"]?.toString();
    final id2 = t2?["_id"]?.toString();

    try {
      if (id1 != null && id2 != null) {
        // ทั้ง 2 ตำแหน่งมีข้อมูลใน DB → สลับ position
        await LocalDb.swapTires(id1, id2);
      } else if (id1 != null && id2 == null) {
        // มีข้อมูลแค่ตำแหน่ง 1 → ย้ายไปตำแหน่ง 2
        await LocalDb.updateTirePosition(id1, pos2);
      } else if (id1 == null && id2 != null) {
        // มีข้อมูลแค่ตำแหน่ง 2 → ย้ายไปตำแหน่ง 1
        await LocalDb.updateTirePosition(id2, pos1);
      }
      // ถ้าทั้งคู่ไม่มีข้อมูล ไม่ต้องทำอะไรใน DB

      setState(() {
        final temp = tires[pos1];
        tires[pos1] = tires[pos2];
        tires[pos2] = temp;

        swapMode = false;
        first = null;
        second = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("สลับยางเรียบร้อย")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("สลับยางล้มเหลว: $e")));
      setState(() {
        swapMode = false;
        first = null;
        second = null;
      });
    }
  }

  // -----------------------------
  // Action Sheet
  // -----------------------------
  Future<void> _openTireActionSheet(String pos) async {
    final t = tires[pos] ?? _newTire();
    final dot = (t["dotCode"] as String?)?.trim();
    final size = (t["sizeCode"] as String?)?.trim();
    final depth = (t["depthMm"] as num?)?.toDouble();
    final hasSidewall = (dot != null && dot.isNotEmpty) && (size != null && size.isNotEmpty);
    final hasTread = depth != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.45, 0.92],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // ── Handle bar ──
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // ── Title ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      "ยาง${_getThaiPos(pos)}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  // ── Action buttons ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if (!hasSidewall) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              label: const Text(
                                "เพิ่มข้อมูลแก้มยาง",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () async {
                                Navigator.pop(sheetCtx);
                                await _runScanFlow(pos, ScanMode.sidewall);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            label: Text(
                              hasTread ? "อัพเดตความลึกดอกยาง" : "เพิ่มความลึกดอกยาง",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              await _runScanFlow(pos, ScanMode.tread);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Mini Chart (History) Placeholder removed here ──


                  // ── Collapsible Tire Info ──
                  StatefulBuilder(
                    builder: (ctx, setInnerState) {
                      final bool isExpanded = t['_infoExpanded'] ?? true;
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                setInnerState(() {
                                  t['_infoExpanded'] = !isExpanded;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "ข้อมูลยาง",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Icon(
                                      isExpanded ? Icons.expand_less : Icons.expand_more,
                                      color: const Color(0xFFFFD700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (isExpanded) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    _infoLine(
                                      "สัปดาห์-ปีที่ผลิต",
                                      _formatDotCode(dot),
                                    ),
                                    _buildSizeCodeDetails(t["sizeCode"]?.toString()),
                                    _infoLine(
                                      "อายุยางที่เหลือ",
                                      _dotAgeLabel(dot),
                                      color: _isExpired(dot)
                                          ? Colors.redAccent
                                          : _isExpiringSoon(dot)
                                              ? Colors.orangeAccent
                                              : null,
                                    ),
                                    _infoLine(
                                      "ความลึกดอกยาง",
                                      depth == null
                                          ? "-"
                                          : "${depth.toStringAsFixed(1)} มิลลิเมตร",
                                      color: (depth != null && depth < 1.6)
                                          ? Colors.redAccent
                                          : (_isTreadOld(t) ? Colors.orangeAccent : null),
                                    ),
                                    _infoLine(
                                      "ระยะทางที่สามารถวิ่งได้อย่างปลอดภัย",
                                      _safeDistanceLabel(depth),
                                      color: (depth != null && depth < 1.6)
                                          ? Colors.redAccent
                                          : null,
                                    ),
                                    _infoLine(
                                      "สภาพยางที่ใช้ได้",
                                      "${(t["lifePercent"] as num?)?.toStringAsFixed(0) ?? "0"}% ",
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  // ── Mini Chart (History) ──
                  if (t["_id"] != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: LocalDb.getTireHistory(t["_id"].toString()),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final history = snapshot.data!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                "แนวโน้มความลึกดอกยาง (mm)",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              height: 180,
                              padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
                              child: _buildMiniChart(history),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),

                  // ── Warnings ──
                  if (_isExpired(dot))
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.redAccent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "⚠️ ยางหมดอายุ (เกิน 5 ปี) ควรเปลี่ยนยางใหม่",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isExpiringSoon(dot) && !_isExpired(dot))
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.orangeAccent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "⚠️ ยางใกล้หมดอายุ 5 ปีแล้ว! ควรเตรียมเปลี่ยนยาง",
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!_isExpired(dot) && _isTreadOld(t))
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.orangeAccent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.history,
                            color: Colors.orangeAccent,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "⚠️ ข้อมูลดอกยางไม่อัพเดต (เกิน 3 เดือน) กรุณาถ่ายดอกยางใหม่",
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 10),

                  if (t["_id"] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SafeArea(
                        bottom: false,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFFD700),
                            side: const BorderSide(color: Color(0xFFFFD700)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text(
                            "ดูประวัติฉบับเต็ม",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TireHistoryPage(
                                  tireId: t["_id"].toString(),
                                  positionName: _getThaiPos(pos),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text("ลบข้อมูลยางตำแหน่งนี้"),
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        await _confirmDeleteTire(pos);
                      },
                    ),
                  ),

                  // ── Swipe up hint ──
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center),
                  ),

                  const Divider(color: Colors.white12, height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoLine(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              v,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDotCode(String? dot) {
    final date = _getProductionDateFromDot(dot);
    if (date == null) return dot ?? "-";

    final thaiMonths = [
      "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน",
      "พฤษภาคม", "มิถุนายน", "กรกฎาคม", "สิงหาคม",
      "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
    ];
    final monthName = thaiMonths[date.month - 1];
    final last4 = dot!.replaceAll(RegExp(r"\s+"), "").substring(dot.length - 4);

    return "วันที่ ${date.day} $monthName ปี พ.ศ. ${date.year + 543} (Dot Code: $last4)";
  }

  Widget _buildSizeCodeDetails(String? sizeCode) {
    if (sizeCode == null || sizeCode.trim().isEmpty) {
      return _infoLine("Size Code", "-");
    }
    
    final s = sizeCode.trim().toUpperCase();
    final RegExp sizeExp = RegExp(
        r'(\d{2,3})\s*/\s*(\d{2,3})\s*([A-Z])\s*(\d{2})(?:\s+(\d{2,3})\s*([A-Z]))?');
    final match = sizeExp.firstMatch(s);
    
    if (match == null) {
      return _infoLine("Size", sizeCode.trim());
    }

    final width = match.group(1);
    final series = match.group(2);
    final construct = match.group(3);
    final diameter = match.group(4);
    final loadIndex = match.group(5);
    final speed = match.group(6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ข้อมูลขนาดยางหรือไซส์ยาง",
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sizeCode.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                if (width != null) _subInfoLine("• $width", "มม. (ความกว้างหน้ายาง )"),
                if (series != null) _subInfoLine("• $series", "% ของ $width มม.(ซีรีส์ยาง หรือความสูงแก้มยาง)"),
                if (construct != null) _subInfoLine("• $construct", "${construct == 'R' ? 'ยางเรเดียล' : 'ไบแอส'} (โครงสร้างยาง)"),
                if (diameter != null) _subInfoLine("• $diameter", "นิ้ว (เส้นผ่านศูนย์กลางล้อ)"),
                if (loadIndex != null) _subInfoLine("• $loadIndex", "ดัชนีการรับน้ำหนัก (Load Index)"),
                if (speed != null) _subInfoLine("• $speed", "ดัชนีระบุความเร็ว (Speed Symbol)"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subInfoLine(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 35,
            child: Text(
              key,
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // Scan Flow
  // -----------------------------
  Future<void> _runScanFlow(String pos, ScanMode mode) async {
    await _openCaptureAndApplyResult(pos, mode);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openCaptureAndApplyResult(String pos, ScanMode mode) async {
    final t = (tires[pos] as Map<String, dynamic>?) ?? _newTire();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureInstructionPage(
          pos: pos,
          carId: currentCarId,
          mode: mode,
          prevDepth: (t["depthMm"] as num?)?.toDouble(),
          prevUpdateDate: t["updatedAt"] as String?,
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (mode == ScanMode.sidewall) {
      final dot = (result["dotCode"] ?? result["tireCode"] ?? "")
          .toString()
          .trim();
      final size = (result["sizeCode"] ?? "").toString().trim();

      t["dotCode"] = dot.isNotEmpty ? dot : t["dotCode"];
      t["sizeCode"] = size.isNotEmpty ? size : t["sizeCode"];
      t["dotConf"] = (result["dotConf"] ?? result["tireCodeConf"] as num?)
          ?.toDouble();

      final p = TireCalculator.calculateHealthPercentage(dotCode: t["dotCode"]?.toString(), treadDepth: t["depthMm"]);
      t["lifePercent"] = p;
      t["lifeColor"] = _lifeColorFromPercent(p);

      // save to local DB — ส่ง null ถ้า field ว่างเพื่อไม่ทับค่าเดิม
      await LocalDb.upsertTire(
        carId: currentCarId,
        position: pos,
        tireCode: dot.isNotEmpty ? dot : null,
        sizeCode: size.isNotEmpty ? size : null,
      );
    } else {
      final rawMm = (result["depthMm"] ?? result["depth"] as num?)?.toDouble();
      // ตัดทศนิยมตำแหน่งที่ 2 ทิ้ง (truncate) เช่น 2.37 → 2.3
      final mm = rawMm != null ? (rawMm * 10).truncateToDouble() / 10 : null;
      if (mm != null) {
        t["depthMm"] = mm;
        t["depthConf"] = (result["depthConf"] as num?)?.toDouble();

        final km = _calcLifeKmFromMm(mm);
        
        final dot = t["dotCode"]?.toString();
        final p = TireCalculator.calculateHealthPercentage(dotCode: dot, treadDepth: mm);
        
        t["lifeKm"] = km;
        t["lifePercent"] = p;
        t["lifeColor"] = _lifeColorFromPercent(p);

        // save to local DB
        final savedRow = await LocalDb.upsertTire(
          carId: currentCarId,
          position: pos,
          lastDepthMm: mm,
          lastEstimatedRemainingKm: km.toInt(),
          status: p < 25 ? "REPLACE" : (p < 50 ? "WARN" : "OK"),
        );
        final tireIdStr = savedRow['id']?.toString() ?? t['_id']?.toString();
        if (tireIdStr != null) {
          await LocalDb.addTireHistory(tireIdStr, mm, pos);
        }
      }
    }

    t["updatedAt"] = DateTime.now().toIso8601String();
    tires[pos] = t;

    // Reload to get the tire ID from DB
    await _loadTiresForCar(currentCarId);
  }

  // -----------------------------
  // Delete tire
  // -----------------------------
  Future<void> _confirmDeleteTire(String pos) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          "ลบข้อมูลยาง?",
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          "ต้องการลบข้อมูลยางตำแหน่ง ${_getThaiPos(pos)} ใช่ไหม?",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบ", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final t = tires[pos];
    final tireId = t?["_id"];
    if (tireId != null) {
      try {
        await LocalDb.deleteTire(tireId.toString());
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("ลบไม่สำเร็จ: $e")));
        return;
      }
    }

    setState(() {
      tires[pos] = _newTire();
    });
  }

  // -----------------------------
  // Delete Car
  // -----------------------------
  Future<void> _confirmDeleteCarById(
    String id,
    String name, {
    required bool closeSheet,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          "ลบรถคันนี้?",
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          "ยืนยันลบรถ '$name'? ข้อมูลยางทั้งหมดจะหายไป",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบ", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await LocalDb.deleteCar(id);

      setState(() {
        cars.removeWhere((c) {
          final cid = (c["id"] ?? "").toString();
          return cid == id;
        });

        if (id == currentCarId) {
          if (cars.isNotEmpty) {
            final first = cars.first;
            currentCarId = (first["id"] ?? "").toString();
            carName = (first["carName"] ?? "รถ").toString();
            _loadTiresForCar(currentCarId);
          } else {
            currentCarId = "";
            carName = "ไม่มีรถ";
            tires["FL"] = _newTire();
            tires["FR"] = _newTire();
            tires["RL"] = _newTire();
            tires["RR"] = _newTire();
            tires["SPARE"] = _newTire();
          }
        }
      });

      if (closeSheet) {
        if (!mounted) return;
        Navigator.pop(context);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("ลบรถเรียบร้อย")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบรถไม่สำเร็จ: $e")));
    }
  }

  // -----------------------------
  // Rename dialog
  // -----------------------------
  Future<String?> _renameDialog(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'แก้ไขชื่อรถ',
          style: TextStyle(color: Color(0xFFFFD700)),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ชื่อรถ',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFD700)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text(
              'บันทึก',
              style: TextStyle(color: Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChart(List<Map<String, dynamic>> history) {
    List<FlSpot> spots = [];
    double minDepth = double.infinity;
    double maxDepth = 0.0;

    for (int i = 0; i < history.length; i++) {
      final depth = (history[i]['depthMm'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), depth));
      if (depth < minDepth) minDepth = depth;
      if (depth > maxDepth) maxDepth = depth;
    }

    if (minDepth > maxDepth) {
      minDepth = 0;
      maxDepth = 8;
    } else {
      minDepth = (minDepth - 1).clamp(0, double.infinity).toDouble();
      maxDepth = maxDepth + 1;
    }

    return LineChart(
      LineChartData(
        minY: minDepth,
        maxY: maxDepth,
        minX: 0,
        maxX: (history.length - 1).toDouble() < 1 ? 1 : (history.length - 1).toDouble(),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (value != idx.toDouble()) return const SizedBox.shrink();
                if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "${idx + 1}",
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Colors.white12),
            left: BorderSide(color: Colors.white12),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFFFFD700),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x33FFD700),
            ),
          ),
        ],
      ),
    );
  }
}
