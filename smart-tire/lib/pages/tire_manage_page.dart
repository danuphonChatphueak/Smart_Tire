import 'package:flutter/material.dart';

import 'capture_page.dart';

class TireManagePage extends StatefulWidget {
  final String carId;
  final String carName;
  const TireManagePage({super.key, required this.carId, required this.carName});

  @override
  State<TireManagePage> createState() => _TireManagePageState();
}

class _TireManagePageState extends State<TireManagePage> {
  static const yellow = Color(0xFFF3C300);
  static const panel = Color(0xFF222222);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: yellow,
      body: SafeArea(
        child: Column(
          children: [
            _TopArea(
              carName: widget.carName,
              onBag: () {},
              onBell: () {},
              onAdd: () {},
              onSettings: () {},
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(34),
                    topRight: Radius.circular(34),
                  ),
                ),
                child: Center(
                  child: _CarPanel(onTapPos: (pos) => _chooseScanMode(pos)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseScanMode(String pos) async {
    final mode = await showModalBottomSheet<_ScanMode>(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ScanModeSheet(position: pos),
    );

    if (mode == null) return;

    _openCapture(pos, mode);
  }

  void _openCapture(String pos, _ScanMode mode) {
    // ✅ ส่ง scanMode ไป CapturePage
    // ต้องไปเพิ่ม parameter ใน CapturePage ให้รับ scanMode ด้วย
    final scanModeStr = mode == _ScanMode.tread ? "tread" : "sidewall";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CapturePage(
          carId: widget.carId,
          position: pos,
          scanMode: scanModeStr, // ✅ เพิ่ม
        ),
      ),
    );
  }
}

enum _ScanMode { tread, sidewall }

// ==================== SCAN MODE SHEET ====================

class _ScanModeSheet extends StatelessWidget {
  final String position;
  const _ScanModeSheet({required this.position});

  String _getThaiPos(String pos) {
    switch (pos) {
      case 'FL': return 'หน้าซ้าย';
      case 'FR': return 'หน้าขวา';
      case 'RL': return 'หลังซ้าย';
      case 'RR': return 'หลังขวา';
      case 'SPARE': return 'อะไหล่';
      default: return pos;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "เลือกโหมดสแกน (${_getThaiPos(position)})",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),

            _ModeCard(
              title: "สแกนดอกยาง (Tread)",
              subtitle: "ใช้โมเดล depth_tire_model เพื่อวัดความลึก (mm)",
              icon: Icons.stacked_line_chart,
              onTap: () => Navigator.pop(context, _ScanMode.tread),
            ),
            const SizedBox(height: 10),
            _ModeCard(
              title: "สแกนแก้มยาง (Sidewall)",
              subtitle: "ใช้โมเดล detect + recognition เพื่ออ่านรหัสยาง",
              icon: Icons.qr_code_2,
              onTap: () => Navigator.pop(context, _ScanMode.sidewall),
            ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ยกเลิก",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  static const accent = Color(0xFFF3C300);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

// ==================== TOP AREA ====================

class _TopArea extends StatelessWidget {
  final String carName;
  final VoidCallback onBag;
  final VoidCallback onBell;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  const _TopArea({
    required this.carName,
    required this.onBag,
    required this.onBell,
    required this.onAdd,
    required this.onSettings,
  });

  static const yellowCard = Color(0xFFF6CC1B);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Yellow card
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: yellowCard,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _BoldLine("Brand : Honda"),
                  _BoldLine("Model : Civic"),
                  _BoldLine("Year : 2023"),
                  _BoldLine("Sub-Model : 1.5 Turbo RS"),
                  _BoldLine("Total : 69,001km"),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Right icon stack
          Column(
            children: [
              _RightIcon(icon: Icons.shopping_bag_outlined, onTap: onBag),
              const SizedBox(height: 10),
              _RightIcon(icon: Icons.notifications_none_rounded, onTap: onBell),
              const SizedBox(height: 10),
              _RightIcon(icon: Icons.add_circle_outline, onTap: onAdd),
              const SizedBox(height: 10),
              _RightIcon(icon: Icons.settings_outlined, onTap: onSettings),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoldLine extends StatelessWidget {
  final String text;
  const _BoldLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RightIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RightIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87),
      ),
    );
  }
}

// ==================== CAR PANEL ====================

class _CarPanel extends StatelessWidget {
  final void Function(String pos) onTapPos;
  const _CarPanel({required this.onTapPos});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        final boxW = w.clamp(280.0, 380.0);
        final boxH = h.clamp(420.0, 650.0);

        return SizedBox(
          width: boxW,
          height: boxH,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const _Silhouette(),

              Positioned(
                top: boxH * 0.16,
                child: const Text(
                  "Front side",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                left: boxW * 0.18,
                top: boxH * 0.38,
                child: const Text(
                  "Left side",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                right: boxW * 0.18,
                top: boxH * 0.38,
                child: const Text(
                  "Right side",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                bottom: boxH * 0.18,
                child: const Text(
                  "Back side",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              Positioned(
                left: boxW * 0.12,
                top: boxH * 0.22,
                child: _TireButton(
                  shape: _TireShape.vertical,
                  onTap: () => onTapPos("FL"),
                ),
              ),
              Positioned(
                right: boxW * 0.12,
                top: boxH * 0.22,
                child: _TireButton(
                  shape: _TireShape.vertical,
                  onTap: () => onTapPos("FR"),
                ),
              ),
              Positioned(
                left: boxW * 0.12,
                top: boxH * 0.53,
                child: _TireButton(
                  shape: _TireShape.vertical,
                  onTap: () => onTapPos("RL"),
                ),
              ),
              Positioned(
                right: boxW * 0.12,
                top: boxH * 0.53,
                child: _TireButton(
                  shape: _TireShape.vertical,
                  onTap: () => onTapPos("RR"),
                ),
              ),

              Positioned(
                bottom: boxH * 0.08,
                child: _TireButton(
                  shape: _TireShape.horizontal,
                  onTap: () => onTapPos("BACK"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TireShape { vertical, horizontal }

class _TireButton extends StatelessWidget {
  final _TireShape shape;
  final VoidCallback onTap;
  const _TireButton({required this.shape, required this.onTap});

  static const addColor = Color(0xFFF3C300);

  @override
  Widget build(BuildContext context) {
    final isVertical = shape == _TireShape.vertical;
    final width = isVertical ? 78.0 : 120.0;
    final height = isVertical ? 98.0 : 64.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Center(child: Icon(Icons.add, size: 34, color: addColor)),
      ),
    );
  }
}

// ==================== SILHOUETTE ====================

class _Silhouette extends StatelessWidget {
  const _Silhouette();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 132,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(36),
            ),
          ),
          Container(
            width: 50,
            height: 210,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(36),
            ),
          ),
          Container(
            width: 132,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(36),
            ),
          ),
        ],
      ),
    );
  }
}
