import 'package:flutter_test/flutter_test.dart';
import 'package:smarttire/core/tire_calculator.dart';

void main() {
  group('Depth Truncation Logic', () {
    double truncateDepth(double raw) =>
        (raw * 10).truncateToDouble() / 10;

    test('4.73 และ 4.75 ต้องถูกแปลงเป็น 4.7 และถือว่าเท่ากัน (ไม่ผิดปกติ)', () {
      final oldMm = 4.73;
      final newMm = 4.75;

      final truncatedOld = truncateDepth(oldMm);
      final truncatedNew = truncateDepth(newMm);

      expect(truncatedOld, equals(4.7));
      expect(truncatedNew, equals(4.7));
      expect(truncatedNew > truncatedOld, isFalse); // ถือว่าไม่เพิ่มขึ้น (ถูกต้อง)
    });

    test('2.37 ต้องเปลี่ยนเป็น 2.3 (ตัดทศนิยมตำแหน่งที่ 2 ทิ้งเลย)', () {
      expect(truncateDepth(2.37), equals(2.3));
    });

    test('5.88 ต้องเปลี่ยนเป็น 5.8 (ตัดทศนิยมตำแหน่งที่ 2 ทิ้งเลย)', () {
      expect(truncateDepth(5.88), equals(5.8));
    });

    test('1.59 ต้องเปลี่ยนเป็น 1.5 (ต่ำกว่า 1.6)', () {
      expect(truncateDepth(1.59), equals(1.5));
    });

    test('8.09 ต้องเปลี่ยนเป็น 8.0 (ตัดทศนิยมตำแหน่งที่ 2 ทิ้งเลย)', () {
      expect(truncateDepth(8.09), equals(8.0));
    });
  });

  group('TireCalculator Health Percentage', () {
    test('ไม่มีข้อมูลเลย -> 0%', () {
      expect(TireCalculator.calculateHealthPercentage(), equals(0.0));
    });

    test('ดอกยางสูงสุด 8.0 mm และไม่มี DOT -> 70% (เฉพาะส่วนดอกยาง)', () {
      final health = TireCalculator.calculateHealthPercentage(treadDepth: 8.0);
      expect(health, closeTo(70.0, 0.01));
    });

    test('ดอกยางต่ำสุด 1.6 mm และไม่มี DOT -> 0%', () {
      final health = TireCalculator.calculateHealthPercentage(treadDepth: 1.6);
      expect(health, closeTo(0.0, 0.01));
    });
  });
}
