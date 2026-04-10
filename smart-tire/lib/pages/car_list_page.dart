import 'package:flutter/material.dart';
import '../core/local_db.dart';
import '../core/models.dart';
import 'add_car_page.dart';
import 'tire_manage_page.dart';

class CarListPage extends StatefulWidget {
  const CarListPage({super.key});

  @override
  State<CarListPage> createState() => _CarListPageState();
}

class _CarListPageState extends State<CarListPage> {
  List<Car> cars = [];
  bool loading = true;

  Future<void> _load() async {
    setState(() => loading = true);
    final res = await LocalDb.getCars();
    cars = res.map((e) => Car.fromJson(e)).toList();
    setState(() => loading = false);
  }

  Future<void> _renameCar(Car car) async {
    final ctrl = TextEditingController(text: car.carName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("แก้ไขชื่อรถ"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: "ชื่อรถ",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ยกเลิก"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    await LocalDb.renameCar(car.id, newName);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("รถของฉัน")),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddCarPage(nextIndex: cars.length + 1),
            ),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : cars.isEmpty
          ? const Center(child: Text("ยังไม่มีรถ กด + เพื่อเพิ่ม"))
          : ListView.builder(
              itemCount: cars.length,
              itemBuilder: (_, i) {
                final c = cars[i];
                return ListTile(
                  title: Text(c.carName),
                  subtitle: const Text("แตะเพื่อจัดการยาง"),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _renameCar(c),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TireManagePage(carId: c.id, carName: c.carName),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
