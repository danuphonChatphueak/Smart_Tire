import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../core/local_db.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isLockEnabled = false;
  bool _isLoading = true;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final val = await LocalDb.getSetting("app_lock_enabled");
    final hasData = await LocalDb.hasAnyData();
    if (mounted) {
      setState(() {
        _isLockEnabled = val == "true";
        _hasData = hasData;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ลบข้อมูลทั้งหมด?"),
        content: const Text(
          "ข้อมูลรถ, ยาง, และการแจ้งเตือนทั้งหมดจะถูกลบถาวร\nคุณแน่ใจหรือไม่?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ลบทั้งหมด"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalDb.clearAllData();
      if (mounted) {
        setState(() {
          _hasData = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("ลบข้อมูลเรียบร้อยแล้ว")));
        // Refresh app state if needed, or just pop
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("การตั้งค่า")),
      body: ListView(
        children: [
          _buildSectionHeader("จัดการข้อมูล"),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: _hasData ? Colors.red : Colors.grey,
            ),
            title: Text(
              "ลบข้อมูลทั้งหมด",
              style: TextStyle(color: _hasData ? Colors.red : Colors.grey),
            ),
            onTap: _hasData ? _clearData : null,
            enabled: _hasData,
          ),
          const Divider(),
          _buildSectionHeader("ข้อมูลแอปพลิเคชัน"),
          _buildPrivacyTile(),
          _buildFormulaTile(),
          _buildPermissionTile(),
        ],
      ),
    );
  }

  Widget _buildPrivacyTile() {
    return ExpansionTile(
      leading: const Icon(
        Icons.privacy_tip_outlined,
        color: Colors.amberAccent,
      ),
      shape: const Border(), // Remove default borders
      title: const Text("ข้อมูลแอพและความเป็นส่วนตัว"),
      subtitle: const Text(
        "รายละเอียดนโยบายความเป็นส่วนตัวและเงื่อนไขแอปพลิเคชัน",
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoItem(
          "เงื่อนไขการใช้งานและนโยบายความเป็นส่วนตัว",
          "• แอปพลิเคชันรองรับเฉพาะรถยนต์ส่วนบุคคล 4 ล้อ เช่นรถเก๋งหรือรถกระบะ\n"
              "• แอปพลิเคชันเพื่อให้ผู้ใช้ได้ทราบถึงข้อมูลยางรถยนต์ของตนเองในปัจจุบัน\n"
              "• ข้อมูลทั้งหมด (รถ, ยาง, ประวัติ) ถูกจัดเก็บในเครื่องของคุณเท่านั้น (Local Storage)\n"
              "• รูปถ่ายจะถูกส่งไปประมวลผลที่ AI Server และถูกลบทิ้งทันทีหลังวิเคราะห์เสร็จสิ้น\n"
              "• ไม่มีการเก็บข้อมูลส่วนตัวของผู้ใช้บน Cloud",
        ),
      ],
    );
  }

  Widget _buildFormulaTile() {
    return ExpansionTile(
      leading: const Icon(Icons.calculate_outlined, color: Colors.blueAccent),
      shape: const Border(), // Remove default borders
      title: const Text("สูตรการคำนวณสุขภาพยาง"),
      subtitle: const Text(
        "รายละเอียดการคำนวณจากอายุและความลึกดอกยาง",
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoItem(
          "สูตรการคำนวณแบบถ่วงน้ำหนัก (Weighted Average):",
          "คะแนนรวมจะถูกคำนวณจากสองส่วนประกอบหลัก:\n"
              "1. ข้อมูลความลึกดอกยาง (70%): ((ความลึกที่ได้ - 1.6) / (8.0 - 1.6)) * 100\n"
              " (1.6 = ค่าความลึกต่ำสุด)\n"
              " (8.0 = ค่าความลึกสูงสุด)\n"
              "2. ข้อมูลแก้มยาง(30%): 100 - (อายุการใช้งานสะสม / 5 * 100)\n\n"
              "สูตร: (ข้อมูลความลึกดอกยาง * 0.70) + (ข้อมูลแก้มยาง * 0.30)",
        ),
      ],
    );
  }

  Widget _buildPermissionTile() {
    return ExpansionTile(
      leading: const Icon(Icons.security_outlined, color: Colors.greenAccent),
      shape: const Border(), // Remove default borders
      title: const Text("การขอสิทธิ์เข้าถึงข้อมูล"),
      subtitle: const Text(
        "เหตุผลที่แอปจำเป็นต้องขอสิทธิ์ต่างๆ",
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoItem(
          "กล้อง (Camera):",
          "เพื่อใช้สแกนรหัส DOT และวัดความลึกดอกยางผ่านระบบ Smart Vision",
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          "การแจ้งเตือน (Notification):",
          "เพื่อแจ้งเตือนเมื่อยางใกล้หมดอายุ หรือถึงกำหนดตรวจเช็คสภาพ",
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          "คลังภาพ (Storage/Gallery):",
          "เพื่อให้คุณสามารถเลือกรูปภาพยางจากเครื่องมาวิเคราะห์ย้อนหลังได้",
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          "ระบบยืนยันตัวตน (Biometrics):",
          "เพื่อใช้ในการปลดล็อคแอปและปกป้องข้อมูลส่วนตัวของคุณ",
        ),
      ],
    );
  }

  Widget _buildInfoItem(String title, String detail) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
