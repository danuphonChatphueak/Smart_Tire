import 'package:flutter/material.dart';

import '../core/local_db.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => loading = true);
    try {
      final list = await LocalDb.getNotifications();
      if (!mounted) return;
      setState(() {
        notifications = List<Map<String, dynamic>>.from(list);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("โหลดแจ้งเตือนไม่สำเร็จ: $e")));
    }
  }

  Future<void> _markRead(String id, int index) async {
    try {
      await LocalDb.markRead(id);
      if (!mounted) return;
      setState(() {
        notifications[index] = {...notifications[index], "read": 1};
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await LocalDb.markAllRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < notifications.length; i++) {
          notifications[i] = {...notifications[i], "read": 1};
        }
      });
    } catch (_) {}
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await LocalDb.deleteNotification(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("ลบการแจ้งเตือนแล้ว")));
    } catch (_) {}
  }

  Future<void> _deleteAllNotifications() async {
    try {
      await LocalDb.deleteAllNotifications();
      if (!mounted) return;
      setState(() {
        notifications.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ลบการแจ้งเตือนทั้งหมดแล้ว")),
      );
    } catch (_) {}
  }

  Future<void> _confirmDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text("ลบทั้งหมด?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "คุณต้องการลบการแจ้งเตือนทั้งหมดใช่หรือไม่?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "ยกเลิก",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบเลย", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _deleteAllNotifications();
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case "tire_age_expired":
        return Icons.warning_amber_rounded;
      case "tread_depth_reminder":
        return Icons.history;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String? type) {
    switch (type) {
      case "tire_age_expired":
        return Colors.redAccent;
      case "tread_depth_reminder":
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
  }

  String _labelForType(String? type) {
    switch (type) {
      case "tire_age_expired":
        return "ยางหมดอายุ";
      case "tread_depth_reminder":
        return "อัพเดตดอกยาง";
      default:
        return "แจ้งเตือน";
    }
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return "";
    try {
      final dt = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return "เมื่อสักครู่";
      if (diff.inMinutes < 60) return "${diff.inMinutes} นาทีที่แล้ว";
      if (diff.inHours < 24) return "${diff.inHours} ชั่วโมงที่แล้ว";
      if (diff.inDays < 30) return "${diff.inDays} วันที่แล้ว";
      return "${(diff.inDays / 30).floor()} เดือนที่แล้ว";
    } catch (_) {
      return "";
    }
  }

  bool _isRead(Map<String, dynamic> n) {
    final r = n["read"];
    return r == true || r == 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          "การแจ้งเตือน",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (notifications.any((n) => !_isRead(n)))
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                "อ่านทั้งหมด",
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 13),
              ),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              onPressed: _confirmDeleteAll,
              icon: const Icon(Icons.delete_sweep, color: Colors.white54),
            ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            )
          : notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_off,
                    size: 64,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "ยังไม่มีการแจ้งเตือน",
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              color: const Color(0xFFFFD700),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: notifications.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: Color(0xFF333333)),
                itemBuilder: (context, index) {
                  final n = notifications[index];
                  final isRead = _isRead(n);
                  final type = n["type"]?.toString();
                  final color = _colorForType(type);
                  final idStr = (n["id"] ?? "").toString();

                  return Dismissible(
                    key: Key(idStr.isEmpty ? index.toString() : idStr),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.redAccent,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) {
                      final removedId = idStr;
                      setState(() {
                        notifications.removeAt(index);
                      });
                      _deleteNotification(removedId);
                    },
                    child: InkWell(
                      onTap: () {
                        if (!isRead) {
                          _markRead((n["id"] ?? "").toString(), index);
                        }
                      },
                      child: Container(
                        color: isRead
                            ? Colors.transparent
                            : const Color(0xFF2A2A2A).withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _iconForType(type),
                                color: color,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          _labelForType(type),
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (!isRead)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFFD700),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (n["title"] ?? "").toString(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: isRead
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    (n["body"] ?? "").toString(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _timeAgo(n["createdAt"]?.toString()),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white38,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                final removedId = idStr;
                                setState(() {
                                  notifications.removeAt(index);
                                });
                                _deleteNotification(removedId);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
