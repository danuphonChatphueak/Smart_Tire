import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/local_db.dart';

class TireHistoryPage extends StatefulWidget {
  final String tireId;
  final String positionName;

  const TireHistoryPage({
    super.key,
    required this.tireId,
    required this.positionName,
  });

  @override
  State<TireHistoryPage> createState() => _TireHistoryPageState();
}

class _TireHistoryPageState extends State<TireHistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await LocalDb.getCombinedHistory(widget.tireId);
    if (!mounted) return;
    setState(() {
      _history = list;
      _isLoading = false;
    });
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return isoString;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text(
          "ประวัติยาง${widget.positionName}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _history.isEmpty
              ? const Center(
                  child: Text(
                    "ยังไม่มีประวัติยางเส้นนี้",
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    // ── History List ──
                    Expanded(
                      child: ListView.separated(
                        itemCount: _history.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, index) {
                          final reversedIndex = _history.length - 1 - index;
                          final item = _history[reversedIndex];
                          final type = item['type'] as String? ?? 'measurement';
                          final dateStr = _formatDate(item['createdAt'] as String);

                          if (type == 'measurement') {
                            final depthMm = (item['depthMm'] as num?)?.toDouble() ?? 0.0;
                            final posCode = item['position'] as String? ?? '-';
                            final displayPos = _getThaiPos(posCode);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: const CircleAvatar(
                                backgroundColor: Colors.black26,
                                child: Icon(Icons.straighten, color: Color(0xFFFFD700), size: 18),
                              ),
                              title: Text(
                                "ความลึก: ${depthMm.toStringAsFixed(1)} มิลลิเมตร",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    "วัดเมื่อ: $dateStr",
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "ที่ตำแหน่ง: ยาง$displayPos",
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            // Swap Event
                            final fromPos = _getThaiPos(item['fromPos']?.toString() ?? '-');
                            final toPos = _getThaiPos(item['toPos']?.toString() ?? '-');

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: const CircleAvatar(
                                backgroundColor: Colors.black26,
                                child: Icon(Icons.swap_horiz, color: Colors.blueAccent, size: 20),
                              ),
                              title: const Text(
                                "สลับตำแหน่งยาง",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    "สลับเมื่อ: $dateStr",
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "ย้ายจาก: ยาง$fromPos ➔ ยาง$toPos",
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
