import 'package:flutter/material.dart';

import 'capture_page.dart';
import 'home_page.dart';

class CaptureInstructionPage extends StatelessWidget {
  final String pos;
  final String carId;
  final ScanMode mode;
  final double? prevDepth;
  final String? prevUpdateDate;

  const CaptureInstructionPage({
    super.key,
    required this.pos,
    required this.carId,
    required this.mode,
    this.prevDepth,
    this.prevUpdateDate,
  });

  @override
  Widget build(BuildContext context) {
    final isSidewall = mode == ScanMode.sidewall;

    final title = isSidewall ? "คำแนะนำการถ่ายแก้มยาง" : "คำแนะนำการถ่ายดอกยาง";
    final instruction = isSidewall
        ? "ให้ทำการถ่ายยางทั้งเส้นโดยต้องถ่ายให้เห็นตัวอักษรทั้งหมดของยางอย่างชัดเจน"
        : "ถ่ายภาพร่องยางรถยนต์ให้เห็นทั้งพื้นร่องและขอบบนของร่องยางอย่างชัดเจน";

    // Using assets provided by user or placeholders
    final imageAsset = isSidewall
        ? 'assets/20260314_153627.jpg'
        : 'assets/image.png';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "คำแนะนำ:",
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                instruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: isSidewall ? (4080 / 3060) : (4080 / 3060),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        imageAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported,
                                  size: 64,
                                  color: Colors.white24,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  "ไม่พบรูปตัวอย่าง",
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CapturePage(
                        scanMode: isSidewall ? "sidewall" : "tread",
                        position: pos,
                        carId: carId,
                        prevDepth: prevDepth,
                        prevUpdateDate: prevUpdateDate,
                      ),
                    ),
                  );
                  if (context.mounted && result != null) {
                    Navigator.pop(context, result);
                  }
                },
                child: const Text(
                  "เริ่มต้นถ่าย",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
