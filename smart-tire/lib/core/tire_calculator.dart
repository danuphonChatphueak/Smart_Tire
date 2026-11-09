class TireCalculator {
  /// Calculate tire health percentage based on:
  /// - 70% Tread depth (x): (depth - 1.6) / (8.0 - 1.6) * 100
  /// - 30% Sidewall/Age (y): 100 - (((ageMonths/12 + ageYears) / 5) * 100)
  /// Total = (x * 0.70) + (y * 0.30)
  static double calculateHealthPercentage({String? dotCode, double? treadDepth}) {
    if ((dotCode == null || dotCode.isEmpty) && treadDepth == null) return 0.0;

    double? yPercentage; // Age-based health percentage
    double? xPercentage; // Depth-based health percentage

    // Case 1: Age percentage from DOT Code
    if (dotCode != null && dotCode.length >= 4) {
      final last4 = dotCode.substring(dotCode.length - 4);
      final weekStr = last4.substring(0, 2);
      final yearStr = last4.substring(2, 4);
      
      final week = int.tryParse(weekStr) ?? 1;
      final yy = int.tryParse(yearStr);
      
      if (yy != null) {
        final year = 2000 + yy;
        int maxLifeYears = 5;

        // Approximate month from week (1-52)
        int month = (week / 4.34).ceil();
        if (month <= 0) month = 1;
        if (month > 12) month = 12;

        final now = DateTime.now();
        
        int ageYears = now.year - year;
        int ageMonths = now.month - month;
        if (ageMonths < 0) {
          ageYears--;
          ageMonths += 12;
        }

        if (ageYears < 0) {
          // Future date (e.g. invalid DOT or timezone edge case)
          yPercentage = 100.0;
        } else {
          // Formula: 100 - (((ageMonths/12) + ageYears) / 5) * 100
          double usagePercent = (((ageMonths / 12.0) + ageYears) / maxLifeYears) * 100;
          yPercentage = 100.0 - usagePercent;
          
          if (yPercentage < 0) yPercentage = 0.0;
          if (yPercentage > 100) yPercentage = 100.0;
        }
      }
    }

    // Case 2: Depth percentage from Tread Depth
    if (treadDepth != null) {
      final truncatedMm = (treadDepth * 10).truncateToDouble() / 10;
      // Formula: (depth - 1.6) / (8.0 - 1.6) * 100
      xPercentage = ((truncatedMm - 1.6) / (8.0 - 1.6)) * 100.0;
      if (xPercentage < 0) xPercentage = 0.0;
      if (xPercentage > 100) xPercentage = 100.0;
    }

    // Case 3: Strict weighting (70% Tread, 30% Sidewall)
    final x = xPercentage ?? 0.0;
    final y = yPercentage ?? 0.0;
    return (x * 0.70) + (y * 0.30);
  }
}
