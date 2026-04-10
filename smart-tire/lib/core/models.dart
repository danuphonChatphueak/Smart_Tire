class Car {
  final String id;
  final String carName;

  Car({required this.id, required this.carName});

  factory Car.fromJson(Map<String, dynamic> j) =>
      Car(id: j["_id"] ?? j["id"], carName: j["carName"] ?? "รถของฉัน");

  Map<String, dynamic> toMap() => {"id": id, "carName": carName};
}

class Tire {
  final String id;
  final String position;
  final String tireCode;
  final String? sizeCode;
  final double? lastDepthMm;
  final int? remainingKm;
  final String status;
  final String? updatedAt;

  Tire({
    required this.id,
    required this.position,
    required this.tireCode,
    this.sizeCode,
    required this.lastDepthMm,
    required this.remainingKm,
    required this.status,
    this.updatedAt,
  });

  factory Tire.fromJson(Map<String, dynamic> j) => Tire(
    id: j["_id"] ?? j["id"] ?? "",
    position: j["position"] ?? "",
    tireCode: j["tireCode"] ?? "",
    sizeCode: j["sizeCode"],
    lastDepthMm: (j["lastDepthMm"] is num)
        ? (j["lastDepthMm"] as num).toDouble()
        : null,
    remainingKm: (j["lastEstimatedRemainingKm"] is num)
        ? (j["lastEstimatedRemainingKm"] as num).toInt()
        : null,
    status: j["status"] ?? "OK",
    updatedAt: j["updatedAt"]?.toString(),
  );

  Map<String, dynamic> toMap() => {
    "id": id,
    "position": position,
    "tireCode": tireCode,
    "sizeCode": sizeCode,
    "lastDepthMm": lastDepthMm,
    "lastEstimatedRemainingKm": remainingKm,
    "status": status,
    "updatedAt": updatedAt,
  };
}
