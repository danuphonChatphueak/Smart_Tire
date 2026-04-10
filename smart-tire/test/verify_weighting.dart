import 'package:smarttire/core/tire_calculator.dart';

void main() {
  print("Testing TireCalculator with strict 70/30 weighting...");

  // Mocking DateTime.now() is hard in simple script, but we can check the weights.
  
  // Case 1: Only Tread (8.0mm = 100%)
  double treadOnly = TireCalculator.calculateHealthPercentage(treadDepth: 8.0);
  print("Tread Only (100% of 70%): Expected 70.0, Got $treadOnly");

  // Case 2: Only DOT (New tire = 100%)
  // Need a recent DOT. Let's assume current year 2026.
  // DOT 1426 (Week 14, 2026)
  double dotOnly = TireCalculator.calculateHealthPercentage(dotCode: "1426");
  print("DOT Only (100% of 30%): Expected 30.0, Got $dotOnly");

  // Case 3: Both (100% Tread, 100% DOT)
  double both = TireCalculator.calculateHealthPercentage(dotCode: "1426", treadDepth: 8.0);
  print("Both (100% each): Expected 100.0, Got $both");

  // Case 4: 50% Tread (4.8mm), No DOT
  // ((4.8 - 1.6) / 6.4) * 100 = 50%
  // 50% * 0.7 = 35%
  double halfTread = TireCalculator.calculateHealthPercentage(treadDepth: 4.8);
  print("Half Tread Only: Expected 35.0, Got $halfTread");
}
