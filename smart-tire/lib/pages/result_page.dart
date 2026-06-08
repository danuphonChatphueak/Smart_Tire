import 'dart:convert';

import 'package:flutter/material.dart';

class ResultPage extends StatefulWidget {
  final String scanMode; // "sidewall" | "tread"
  final String position;
  final Map<String, dynamic> result;
  final double? prevDepth;
  final String? prevUpdateDate;

  const ResultPage({
    super.key,
    required this.scanMode,
    required this.position,
    required this.result,
    this.prevDepth,
    this.prevUpdateDate,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late final TextEditingController _dotCtrl;
  late final TextEditingController _sizeCtrl;

  String? _sizeErrorText;

  bool _showRetakeWarning = false;
  bool _hasValidationError = false;
  bool _isBlocking = false;
  bool _isDepthIncrease = false;
  String _validationMsg = "";

  void _validateSizeOnFly(String text) {
    if (text.trim().isEmpty) {
      if (_sizeErrorText != null) setState(() => _sizeErrorText = null);
      return;
    }
    bool sizeValid = false;
    final RegExp regex = RegExp(r'(\d{3})\s*/\s*(\d{2})');
    final match = regex.firstMatch(text);
    if (match != null) {
      final w = int.tryParse(match.group(1)!) ?? 0;
      final p = int.tryParse(match.group(2)!) ?? 0;
      if (w >= 155 && w <= 285 && p >= 30 && p <= 80) {
        sizeValid = true;
      }
    }
    
    if (mounted) {
      setState(() {
        if (!sizeValid) {
          _sizeErrorText = "ข้อมูลขนาดยางผิดปกติ ไม่ใช่ของรถเก๋ง/กระบะ";
        } else {
          _sizeErrorText = null;
        }
      });
    }
  }

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
  void initState() {
    super.initState();
    final dot = _readDotText(widget.result);
    final size = _readSizeText(widget.result);

    _dotCtrl = TextEditingController(text: dot);
    _sizeCtrl = TextEditingController(text: size);

    if (widget.scanMode == "sidewall" && size.isNotEmpty) {
      _validateSizeOnFly(size);
    }
    _sizeCtrl.addListener(() {
      _validateSizeOnFly(_sizeCtrl.text);
    });

    // ถ้าเป็นการสแกนโหมดแก้มยาง
    if (widget.scanMode == "sidewall") {
      if (dot.isEmpty && size.isEmpty) {
        _showRetakeWarning = true;
        // Schedule dialog
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showRetakeDialog();
        });
      } else if (size.isNotEmpty) {
        bool sizeValid = false;
        final RegExp regex = RegExp(r'(\d{3})\s*/\s*(\d{2})');
        final match = regex.firstMatch(size);
        if (match != null) {
          final w = int.tryParse(match.group(1)!) ?? 0;
          final p = int.tryParse(match.group(2)!) ?? 0;
          if (w >= 155 && w <= 285 && p >= 30 && p <= 80) {
            sizeValid = true;
          }
        }
        
        if (!sizeValid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showInvalidSizeDialog();
          });
        }
      }
    }

    // Tread mode check
    if (widget.scanMode == "tread") {
      final d = _readDepthMm(widget.result);

      if (d != null && d > 0) {
        final prevMm = widget.prevDepth;
        final prevUpdateStr = widget.prevUpdateDate;

        if (prevMm != null && prevUpdateStr != null) {
          final now = DateTime.now();
          final prevDate = DateTime.parse(prevUpdateStr);
          final isSameDay = now.year == prevDate.year &&
              now.month == prevDate.month &&
              now.day == prevDate.day;
          final diffHours = now.difference(prevDate).inHours.abs();

          // ตรวจสอบตามลำดับความสำคัญ (เรียงจากหนักไปเบา)
          // Rule 3: ค่าเพิ่มขึ้น — บล็อก (ตรงนี้ต้องเช็คก่อน ก่อนที่ rule อื่นจะ fire ทับ)
          if (d > prevMm + 0.01) {
            _hasValidationError = true;
            _isBlocking = true;
            _isDepthIncrease = true;
            _validationMsg = "ความลึกดอกยางเพิ่มขึ้นจากเดิม (เดิม ${prevMm.toStringAsFixed(2)} มิลลิเมตร ➔ ใหม่ ${d.toStringAsFixed(2)} มิลลิเมตร)";
          }
          // Rule 2: สึกหรอเร็วมากผิดปกติภายใน 24 ชม. — เตือน (ไม่บล็อก)
          else if (diffHours <= 24 && (prevMm - d) > 0.5) {
            _hasValidationError = true;
            _isBlocking = false;
            _validationMsg = "อัตราการสึกหรอสูงผิดปกติ (เดิม ${prevMm.toStringAsFixed(2)} มิลลิเมตร ➔ ใหม่ ${d.toStringAsFixed(2)} มิลลิเมตร)";
          }
          // Rule 1: วัดในวันเดียวกันแต่ค่าต่างกัน (เฉพาะกรณีค่าลด) — เตือน (ไม่บล็อก)
          else if (isSameDay && d < prevMm - 0.01) {
            _hasValidationError = true;
            _isBlocking = false;
            _validationMsg = "ข้อมูลขัดแย้งในวันเดียวกัน (เดิม ${prevMm.toStringAsFixed(2)} มิลลิเมตร ➔ ใหม่ ${d.toStringAsFixed(2)} มิลลิเมตร)";
          }

          if (_hasValidationError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showValidationWarningDialog(prevMm, d);
            });
          }
        }
      }

      // ถ้าวัดค่าไม่ได้ (d == 0 หรือ null) แสดงเตือนแยกต่างหาก ไม่ซ้ำกับ 3 กรณีข้างต้น
      final d2 = _readDepthMm(widget.result);
      if (d2 != null && d2 == 0 && !_hasValidationError) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showLowDepthWarning(d2),
        );
      } else if (d2 != null && d2 > 0 && d2 < 1.6 && !_hasValidationError) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showLowDepthWarning(d2),
        );
      }
    }
  }

  void _showLowDepthWarning(double depth) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("ไม่สามารถวัดค่าความลึกได้"),
        content: const Text(
          "โดยอาจมีสาเหตุจากแสงไม่พอหรือการวางกล้องที่ไม่เหมาะสม \nกรุณาลองถ่ายใหม่อีกครั้ง",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Back to capture
            },
            child: const Text("ถ่ายใหม่",style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showValidationWarningDialog(double oldMm, double newMm) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text("คำเตือน", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("ความลึกเดิม: ${oldMm.toStringAsFixed(2)} มิลลิเมตร",
                style: const TextStyle(color: Colors.white70)),
            Text("ผลการวัดใหม่: ${newMm.toStringAsFixed(2)} มิลลิเมตร",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text("แนะนำให้ลองถ่ายใหม่อีกครั้ง",
                style: TextStyle(color: Colors.white)),
            if (_isDepthIncrease) ...[
              const SizedBox(height: 12),
              const Text(
                "*ถ้ามีการเปลี่ยนยางใหม่ให้ลบข้อมูลยางก่อนค่อยถ่าย",
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isBlocking) ...[
            // กรณีเตือน (ไม่บล็อก): ถ่ายใหม่ = เหลือง, ตกลง = ข้อความ
            TextButton(
              onPressed: () => Navigator.pop(context), // Just close dialog
              child: const Text("ตกลง", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Back to capture
              },
              child: const Text("ถ่ายใหม่", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ] else ...[
            // กรณีบล็อก (ค่าเพิ่มขึ้น): ถ่ายใหม่ = เหลือง เท่านั้น
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Back to capture
              },
              child: const Text("ถ่ายใหม่", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  void _showRetakeDialog({bool allowManual = true}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("ตรวจสอบไม่พบข้อมูล"),
        content: const Text(
          "ระบบไม่สามารถอ่านรหัสยางหรือขนาดได้ชัดเจน\nกรุณาขยับเข้าไปใกล้ หรือปรับแสง แล้วถ่ายใหม่",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close result page -> back to capture
            },
            child: const Text("ถ่ายใหม่"),
          ),
          if (allowManual)
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                ); // close dialog, stay on page to manual edit
              },
              child: const Text("กรอกเอง"),
            ),
        ],
      ),
    );
  }

  void _showInvalidSizeDialog({bool fromSubmit = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("ขนาดข้อมูลยางผิดปกติ"),
        content: Text(
          "ข้อมูลขนาดยางไม่อยู่ในเกณฑ์มาตรฐาน\n"
          "(เลข 3 ตัวแรกต้องอยู่ระหว่าง 155-285 และเลขหลังเครื่องหมาย '/' ต้องอยู่ระหว่าง 30-80)\n\n"
          "❗ นี้ไม่ใช่ข้อมูลขนาดยางของรถเก๋งหรือรถกระบะ\n\n"
          "${fromSubmit ? 'กรุณาแก้ไขข้อมูลให้ถูกต้อง หรือถ่ายภาพใหม่' : 'กรุณาถ่ายใหม่ให้ชัดเจนขึ้น หรือกรอกข้อมูลนี้ด้วยตนเอง'}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // back to capture
            },
            child: const Text("ถ่ายใหม่"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // continue to manual edit
            },
            child: Text(fromSubmit ? "แก้ไขข้อมูล" : "กรอกเอง"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  String _readDotText(Map<String, dynamic> r) {
    if (r.containsKey("results")) {
      final res = r["results"];
      if (res is Map && res["tire_code"] is Map) {
        return (res["tire_code"]["text"] ?? "").toString();
      }
    }
    // Fallback for old API structure
    if (r["tireCode"] is Map) return r["tireCode"]["text"]?.toString() ?? "";
    if (r["tireCodeResult"] is Map) {
      return r["tireCodeResult"]["text"]?.toString() ?? "";
    }
    return "";
  }

  String _readSizeText(Map<String, dynamic> r) {
    if (r.containsKey("results")) {
      final res = r["results"];
      if (res is Map && res["size_code"] is Map) {
        return (res["size_code"]["text"] ?? "").toString();
      }
    }
    // Fallback or other structure
    return "";
  }

  double? _readDepthMm(Map<String, dynamic> r) {
    if (r["depthMm"] is Map) {
      return (r["depthMm"]["value"] as num?)?.toDouble();
    }
    return (r["depthResult"]?["depthMm"] as num?)?.toDouble();
  }

  /// อ่าน base64 รูป crop จาก result
  String? _readImage(Map<String, dynamic> r, String key) {
    if (r.containsKey("results")) {
      final res = r["results"];
      if (res is Map && res[key] is Map) {
        final img = res[key]["image"];
        if (img is String && img.isNotEmpty) return img;
      }
    }
    return null;
  }

  Widget _cropImageWidget(String? b64, String label) {
    if (b64 == null || b64.isEmpty) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(b64);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSidewall = widget.scanMode == "sidewall";
    final depthMm = _readDepthMm(widget.result);

    return Scaffold(
      appBar: AppBar(title: Text("ผลลัพธ์ • ${_getThaiPos(widget.position)}")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: isSidewall ? _sidewallView() : _treadView(depthMm),
        ),
      ),
      bottomNavigationBar: (_hasValidationError && _isBlocking)
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("ยืนยัน"),
                onPressed: () {
            if (isSidewall) {
              final sizeText = _sizeCtrl.text.trim();
              if (sizeText.isNotEmpty) {
                bool sizeValid = false;
                final RegExp regex = RegExp(r'(\d{3})\s*/\s*(\d{2})');
                final match = regex.firstMatch(sizeText);
                if (match != null) {
                  final w = int.tryParse(match.group(1)!) ?? 0;
                  final p = int.tryParse(match.group(2)!) ?? 0;
                  if (w >= 155 && w <= 285 && p >= 30 && p <= 80) {
                    sizeValid = true;
                  }
                }
                
                if (!sizeValid) {
                  _showInvalidSizeDialog(fromSubmit: true);
                  return; // Stop and wait for user to fix
                }
              }

              Navigator.pop<Map<String, dynamic>>(context, {
                "dotCode": _dotCtrl.text.trim(),
                "sizeCode": sizeText,
              });
            } else {
              Navigator.pop<Map<String, dynamic>>(context, {
                "depthMm": depthMm ?? 0.0,
              });
            }
          },
        ),
      ),
    );
  }

  Widget _sidewallView() {
    final dotImage = _readImage(widget.result, "tire_code");
    final sizeImage = _readImage(widget.result, "size_code");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "แก้มยาง (Sidewall)",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),

        // DOT CODE
        const Text("รหัสยาง (Dotcode / Tire Code)"),
        const SizedBox(height: 8),
        TextField(
          controller: _dotCtrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "เช่น DOT ... 3523",
          ),
        ),
        const SizedBox(height: 10),
        _cropImageWidget(dotImage, "ภาพบริเวณ DOT Code ที่ตรวจพบ"),

        // SIZE CODE
        const Text("ขนาด (Size Code)"),
        const SizedBox(height: 8),
        TextField(
          controller: _sizeCtrl,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: "เช่น 195/65 R15",
            errorText: _sizeErrorText,
          ),
        ),
        const SizedBox(height: 10),
        _cropImageWidget(sizeImage, "ภาพบริเวณ Size Code ที่ตรวจพบ"),

        if (_showRetakeWarning)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: const [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "ตรวจไม่พบข้อมูล หรือความมั่นใจต่ำ (กรุณากรอกเองหรือถ่ายใหม่)",
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _treadView(double? depthMm) {
    // คำนวณระยะทางปลอดภัย: 1 mm = 7,500 km
    String safeDistLabel = "-";
    final hasValue = depthMm != null && depthMm > 0;

    if (hasValue) {
      final km = depthMm * 7500.0;
      final formatted = km
          .toStringAsFixed(0)
          .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
      safeDistLabel = "$formatted กิโลเมตร";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "ดอกยาง (Depth)",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color.fromARGB(31, 255, 255, 255),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                depthMm == null
                    ? "-"
                    : (depthMm == 0 ? "วัดค่าไม่ได้" : "${depthMm.toStringAsFixed(2)} มิลลิเมตร"),
                style: TextStyle(
                  fontSize: depthMm == 0 ? 24 : 28,
                  fontWeight: FontWeight.w900,
                  color: depthMm == 0 ? Colors.redAccent : const Color.fromARGB(255, 255, 255, 255),
                ),
              ),
              if (hasValue) ...[
                const SizedBox(height: 8),
                Text(
                  "ระยะทางปลอดภัย: $safeDistLabel",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: depthMm < 1.6 ? Colors.redAccent : Colors.green,
                  ),
                ),
              ],
              if (depthMm == 0) ...[
                const SizedBox(height: 8),
                const Text(
                  "กรุณาเลื่อนกล้องให้เห็นร่องดอกยางชัดเจนแจ้วถ่ายใหม่อีกครั้ง",
                  style: TextStyle(fontSize: 13, color: Color.fromARGB(137, 215, 215, 215)),
                ),
              ],
              if (_hasValidationError) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _validationMsg,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "แนะนำให้ลองถ่ายใหม่อีกครั้ง เพื่อความแม่นยำสูงสุด",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      if (_isDepthIncrease) ...[
                        const SizedBox(height: 6),
                        const Text(
                          "*ถ้ามีการเปลี่ยนยางใหม่ให้ลบข้อมูลยางก่อนค่อยถ่าย",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_isBlocking)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text("ถ่ายใหม่"),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
