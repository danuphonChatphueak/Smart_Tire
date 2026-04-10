import 'package:flutter/material.dart';

class VehicleCenterLayout extends StatelessWidget {
  final Map<String, dynamic> tires; // key: FL, FR, RL, RR, SPARE
  final void Function(String position) onTapTire;
  final bool swapMode;
  final String? selectedFirst;
  final String? selectedSecond;

  const VehicleCenterLayout({
    super.key,
    required this.tires,
    required this.onTapTire,
    this.swapMode = false,
    this.selectedFirst,
    this.selectedSecond,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF252525),
      child: Center(
        child: SizedBox(
          width: 350,
          height: 650,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ======= silhouette กลาง =======
              Container(
                width: 40,
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Positioned(
                top: 130,
                child: Container(
                  width: 240,
                  height: 35,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                bottom: 180,
                child: Container(
                  width: 240,
                  height: 35,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Container(
                width: 70,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(35),
                ),
              ),

              // ======= FL =======
              Positioned(
                top: 60,
                left: 20,
                child: Column(
                  children: [
                    _tireButton("FL", tires["FL"]),
                    const SizedBox(height: 8),
                    const Text(
                      'หน้าซ้าย',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _buildMissingDataWarning(tires["FL"]),
                  ],
                ),
              ),

              // ======= FR =======
              Positioned(
                top: 60,
                right: 20,
                child: Column(
                  children: [
                    _tireButton("FR", tires["FR"]),
                    const SizedBox(height: 8),
                    const Text(
                      'หน้าขวา',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _buildMissingDataWarning(tires["FR"]),
                  ],
                ),
              ),

              // ======= RL =======
              Positioned(
                bottom: 100,
                left: 20,
                child: Column(
                  children: [
                    _tireButton("RL", tires["RL"]),
                    const SizedBox(height: 8),
                    const Text(
                      'หลังซ้าย',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _buildMissingDataWarning(tires["RL"]),
                  ],
                ),
              ),

              // ======= RR =======
              Positioned(
                bottom: 100,
                right: 20,
                child: Column(
                  children: [
                    _tireButton("RR", tires["RR"]),
                    const SizedBox(height: 8),
                    const Text(
                      'หลังขวา',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _buildMissingDataWarning(tires["RR"]),
                  ],
                ),
              ),

              // ======= SPARE =======
              Positioned(
                bottom: 10,
                child: Column(
                  children: [
                    _tireButton("SPARE", tires["SPARE"], isHorizontal: true),
                    const SizedBox(height: 8),
                    const Text(
                      'อะไหล่',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _buildMissingDataWarning(tires["SPARE"]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- ปุ่มยาง ----------
  Widget _tireButton(
    String position,
    dynamic tireData, {
    bool isHorizontal = false,
  }) {
    final bool isFirst = selectedFirst == position;
    final bool isSecond = selectedSecond == position;

    // รองรับทั้ง TireData class หรือ Map
    int? healthPercentage;
    double? treadDepth;

    // ✅ ของใหม่จาก HomePage
    int? lifeColorInt; // Colors.xxx.value
    double? lifePercent; // 0..100
    double? depthMm; // mm
    String? dotCode; // สำหรับเช็คว่ามีข้อมูล DOT หรือไม่

    if (tireData != null) {
      if (tireData is Map) {
        // เดิม
        healthPercentage = (tireData["healthPercentage"] as num?)?.toInt();
        treadDepth = (tireData["treadDepth"] as num?)?.toDouble();

        // ✅ ใหม่
        lifeColorInt = (tireData["lifeColor"] as int?);
        lifePercent = (tireData["lifePercent"] as num?)?.toDouble();
        depthMm = (tireData["depthMm"] as num?)?.toDouble();
        dotCode = tireData["dotCode"]?.toString();
      } else {
        // object fields (กันไว้)
        try {
          healthPercentage = (tireData.healthPercentage as int?);
          treadDepth = (tireData.treadDepth as double?);
        } catch (_) {}
        try {
          lifeColorInt = (tireData.lifeColor as int?);
          lifePercent = (tireData.lifePercent as double?);
          depthMm = (tireData.depthMm as double?);
          try {
            dotCode = (tireData as dynamic).dotCode?.toString();
          } catch (_) {}
        } catch (_) {}
      }
    }

    // ถ้าเป็น Map จาก _newTire() จะไม่เป็น null อยู่แล้ว
    final hasData = tireData != null;
    
    // ตรวจสอบความครบถ้วนของข้อมูล
    final bool hasDot = dotCode != null && dotCode.trim().isNotEmpty;
    final bool hasTread = depthMm != null || treadDepth != null;
    final bool isComplete = hasDot && hasTread;

    // ✅ สีหลักของยาง:
    // 1) ถ้า swapMode เลือกอยู่ -> overlay ส้ม
    // 2) ถ้ามี lifeColor และข้อมูลครบ -> ใช้สีที่คำนวณมา
    // 3) ถ้ามี healthPercentage และข้อมูลครบ -> ใช้สีเดิม
    // 4) default ถ้าข้อมูลไม่ครบเป็นขาว หรือ สีของ icon สีเทาเมื่อคลิกได้
    final Color baseColor = (hasData && isComplete && lifeColorInt != null)
        ? Color(lifeColorInt)
        : (hasData && isComplete && healthPercentage != null)
        ? _getHealthColor(healthPercentage)
        : const Color.fromARGB(255, 87, 87, 87);

    final Color fillColor = isFirst
        ? const Color.fromRGBO(255, 165, 0, 0.22)
        : (isSecond ? const Color.fromRGBO(255, 165, 0, 0.12) : baseColor);

    final Color borderColor = isFirst
        ? Colors.orangeAccent
        : (isSecond
              ? Colors.orange.shade200
              : (isComplete ? const Color(0xFFFFD700) : Colors.black));

    return GestureDetector(
      onTap: () => onTapTire(position),
      child: Container(
        width: isHorizontal ? 120 : 80,
        height: isHorizontal ? 80 : 120,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: borderColor,
            width: isFirst ? 4 : (isSecond ? 3 : 2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: _buildCenterLabel(
            hasData: hasData,
            isComplete: isComplete,
            lifePercent: lifePercent,
            depthMm: depthMm,
            healthPercentage: healthPercentage,
            treadDepth: treadDepth,
          ),
        ),
      ),
    );
  }

  Widget _buildCenterLabel({
    required bool hasData,
    required bool isComplete,
    required double? lifePercent,
    required double? depthMm,
    required int? healthPercentage,
    required double? treadDepth,
  }) {
    // ✅ แสดงเป็น % ตามที่ผู้ใช้ขอ: แสดงเฉพาะตอนที่มีข้อมูลครบทั้ง ดอกยางและแก้มยาง
    if (isComplete && (lifePercent != null || healthPercentage != null)) {
      final double p = lifePercent ?? (healthPercentage?.toDouble() ?? 0.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${p.toInt()}%',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 22, // ปรับให้ใหญ่ขึ้นนิดหน่อยเพราะเป็นตัวเลขหลัก
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return const Icon(Icons.add, color: Color.fromRGBO(0, 0, 0, 0.973), size: 40);
  }

  Color _getHealthColor(int percentage) {
    if (percentage >= 70) return Colors.green.shade700;
    if (percentage >= 40) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Widget _buildMissingDataWarning(dynamic tireData) {
    if (tireData == null) return const SizedBox.shrink();

    String? dotCode;
    double? depthMm;

    if (tireData is Map) {
      dotCode = tireData["dotCode"]?.toString();
      depthMm = (tireData["depthMm"] as num?)?.toDouble();
    } else {
      try {
        dotCode = tireData.dotCode?.toString();
        depthMm = tireData.depthMm as double?;
      } catch (_) {}
    }

    final bool hasDot = dotCode != null && dotCode.trim().isNotEmpty;
    final bool hasTread = depthMm != null;

    // "ถ้ายางเส้นไหนขาดข้อมูลอย่างใด้อย่างนึกให้ข้อความใต้ยางนั้นว่าขาดอะไร แต่ถ้าข้อมูลไม่มีเลยหรือข้อมูลครบไม่ต้องแสดง"
    if (hasDot && !hasTread) {
      return const Text(
        'ขาดข้อมูลดอกยาง',
        style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
      );
    } else if (!hasDot && hasTread) {
      return const Text(
        'ขาดข้อมูลแก้มยาง',
        style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
      );
    }

    return const SizedBox.shrink();
  }
}
