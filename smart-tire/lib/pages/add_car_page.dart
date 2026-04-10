import 'package:flutter/material.dart';

import '../core/local_db.dart';

class AddCarPage extends StatefulWidget {
  final int nextIndex;
  const AddCarPage({super.key, required this.nextIndex});

  @override
  State<AddCarPage> createState() => _AddCarPageState();
}

class _AddCarPageState extends State<AddCarPage> {
  late final TextEditingController nameCtrl;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: "รถคันที่ ${widget.nextIndex}");
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => busy = true);

    await LocalDb.createCar(nameCtrl.text.trim());

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("เพิ่มรถ")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: "ชื่อรถ",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: busy ? null : _save,
              child: busy
                  ? const CircularProgressIndicator()
                  : const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );
  }
}
