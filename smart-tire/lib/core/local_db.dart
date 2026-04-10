import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'smart_tire.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cars (
            id TEXT PRIMARY KEY,
            carName TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE tires (
            id TEXT PRIMARY KEY,
            carId TEXT NOT NULL,
            position TEXT NOT NULL,
            tireCode TEXT,
            sizeCode TEXT,
            lastDepthMm REAL,
            lastEstimatedRemainingKm INTEGER,
            status TEXT DEFAULT 'OK',
            updatedAt TEXT,
            FOREIGN KEY (carId) REFERENCES cars(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE notifications (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            read INTEGER DEFAULT 0,
            carId TEXT,
            position TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
        // v2: Settings
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        // v3: Tire History
        await db.execute('''
          CREATE TABLE tire_history (
            id TEXT PRIMARY KEY,
            tireId TEXT NOT NULL,
            depthMm REAL NOT NULL,
            position TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (tireId) REFERENCES tires(id) ON DELETE CASCADE
          )
        ''');
        // v4: Swap History
        await db.execute('''
          CREATE TABLE swap_history (
            id TEXT PRIMARY KEY,
            carId TEXT NOT NULL,
            tireId TEXT NOT NULL,
            fromPos TEXT NOT NULL,
            toPos TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (tireId) REFERENCES tires(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tire_history (
              id TEXT PRIMARY KEY,
              tireId TEXT NOT NULL,
              depthMm REAL NOT NULL,
              position TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              FOREIGN KEY (tireId) REFERENCES tires(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS swap_history (
              id TEXT PRIMARY KEY,
              carId TEXT NOT NULL,
              tireId TEXT NOT NULL,
              fromPos TEXT NOT NULL,
              toPos TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              FOREIGN KEY (tireId) REFERENCES tires(id) ON DELETE CASCADE
            )
          ''');
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Init เรียกใน main()
  static Future<void> init() async {
    await db;
  }

  // --- Settings / Key-Value ---
  static Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert("settings", {
      "key": key,
      "value": value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getSetting(String key) async {
    final d = await db;
    final res = await d.query(
      "settings",
      where: "key = ?",
      whereArgs: [key],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first["value"] as String?;
    }
    return null;
  }

  static Future<void> clearAllData() async {
    final d = await db;
    await d.delete("cars");
    await d.delete("tires");
    await d.delete("notifications");
    await d.delete("settings");
    await d.delete("tire_history");
    await d.delete("swap_history");
  }

  static Future<bool> hasAnyData() async {
    final d = await db;

    final carsRows = await d.query('cars');
    bool hasCustomCar = false;
    if (carsRows.length > 1) {
      hasCustomCar = true;
    } else if (carsRows.length == 1) {
      final name = carsRows.first['carName'] as String?;
      if (name != null && name != 'รถคันที่ 1') {
        hasCustomCar = true;
      }
    }

    final tires =
        Sqflite.firstIntValue(
          await d.rawQuery(
            'SELECT COUNT(*) FROM tires WHERE tireCode IS NOT NULL OR lastDepthMm IS NOT NULL',
          ),
        ) ??
        0;

    final notifs =
        Sqflite.firstIntValue(
          await d.rawQuery(
            "SELECT COUNT(*) FROM notifications WHERE type NOT LIKE 'deleted_%'",
          ),
        ) ??
        0;

    return hasCustomCar || tires > 0 || notifs > 0;
  }

  // ─── ID helper ───
  static String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

  // ═════════════════════════════════════════════
  // CARS
  // ═════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getCars() async {
    final d = await db;
    return d.query('cars', orderBy: 'createdAt ASC');
  }

  static Future<Map<String, dynamic>> createCar(String? name) async {
    final d = await db;
    final id = _genId();
    final now = DateTime.now().toIso8601String();

    String carName;
    if (name != null && name.trim().isNotEmpty) {
      carName = name.trim();
    } else {
      final countResult = await d.rawQuery('SELECT COUNT(*) FROM cars');
      final count = Sqflite.firstIntValue(countResult) ?? 0;
      carName = 'รถคันที่ ${count + 1}';
    }

    final row = {'id': id, 'carName': carName, 'createdAt': now};
    await d.insert('cars', row);
    return row;
  }

  static Future<Map<String, dynamic>> renameCar(
    String carId,
    String newName,
  ) async {
    final d = await db;
    await d.update(
      'cars',
      {'carName': newName},
      where: 'id = ?',
      whereArgs: [carId],
    );
    final rows = await d.query('cars', where: 'id = ?', whereArgs: [carId]);
    return rows.first;
  }

  static Future<void> deleteCar(String carId) async {
    final d = await db;
    await d.delete('tires', where: 'carId = ?', whereArgs: [carId]);
    await d.delete('cars', where: 'id = ?', whereArgs: [carId]);
  }

  // ═════════════════════════════════════════════
  // TIRES
  // ═════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getTires(String carId) async {
    final d = await db;
    return d.query('tires', where: 'carId = ?', whereArgs: [carId]);
  }

  static Future<Map<String, dynamic>> upsertTire({
    required String carId,
    required String position,
    String? tireCode,
    String? sizeCode,
    double? lastDepthMm,
    int? lastEstimatedRemainingKm,
    String? status,
  }) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();

    final existing = await d.query(
      'tires',
      where: 'carId = ? AND position = ?',
      whereArgs: [carId, position],
    );

    if (existing.isNotEmpty) {
      final updates = <String, dynamic>{'updatedAt': now};
      if (tireCode != null) updates['tireCode'] = tireCode;
      if (sizeCode != null) updates['sizeCode'] = sizeCode;
      if (lastDepthMm != null) updates['lastDepthMm'] = lastDepthMm;
      if (lastEstimatedRemainingKm != null) {
        updates['lastEstimatedRemainingKm'] = lastEstimatedRemainingKm;
      }
      if (status != null) updates['status'] = status;

      await d.update(
        'tires',
        updates,
        where: 'carId = ? AND position = ?',
        whereArgs: [carId, position],
      );

      final rows = await d.query(
        'tires',
        where: 'carId = ? AND position = ?',
        whereArgs: [carId, position],
      );
      return rows.first;
    } else {
      final id = _genId();
      final row = {
        'id': id,
        'carId': carId,
        'position': position,
        'tireCode': tireCode,
        'sizeCode': sizeCode,
        'lastDepthMm': lastDepthMm,
        'lastEstimatedRemainingKm': lastEstimatedRemainingKm,
        'status': status ?? 'OK',
        'updatedAt': now,
      };
      await d.insert('tires', row);
      return row;
    }
  }

  static Future<void> swapTires(String tireAId, String tireBId) async {
    final d = await db;
    final a = (await d.query('tires', where: 'id = ?', whereArgs: [tireAId])).first;
    final b = (await d.query('tires', where: 'id = ?', whereArgs: [tireBId])).first;

    final posA = a['position'].toString();
    final posB = b['position'].toString();

    await d.update('tires', {'position': posB}, where: 'id = ?', whereArgs: [tireAId]);
    await d.update('tires', {'position': posA}, where: 'id = ?', whereArgs: [tireBId]);

    // Record swap history
    final carId = a['carId'].toString();
    await addSwapHistory(carId, tireAId, posA, posB);
    await addSwapHistory(carId, tireBId, posB, posA);
  }

  static Future<void> updateTirePosition(String tireId, String newPosition) async {
    final d = await db;
    final row = (await d.query('tires', where: 'id = ?', whereArgs: [tireId])).first;
    final oldPos = row['position'].toString();

    await d.update('tires', {'position': newPosition}, where: 'id = ?', whereArgs: [tireId]);

    // Record swap history
    await addSwapHistory(row['carId'].toString(), tireId, oldPos, newPosition);
  }

  static Future<void> deleteTire(String tireId) async {
    final d = await db;
    await d.delete('tire_history', where: 'tireId = ?', whereArgs: [tireId]);
    await d.delete('swap_history', where: 'tireId = ?', whereArgs: [tireId]);
    await d.delete('tires', where: 'id = ?', whereArgs: [tireId]);
  }

  // ═════════════════════════════════════════════
  // TIRE HISTORY
  // ═════════════════════════════════════════════

  static Future<void> addTireHistory(String tireId, double depthMm, String position) async {
    final d = await db;
    final row = {
      'id': _genId(),
      'tireId': tireId,
      'depthMm': depthMm,
      'position': position,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await d.insert('tire_history', row);
  }

  static Future<List<Map<String, dynamic>>> getTireHistory(String tireId) async {
    final d = await db;
    return d.query(
      'tire_history',
      where: 'tireId = ?',
      whereArgs: [tireId],
      orderBy: 'createdAt ASC',
    );
  }

  // ═════════════════════════════════════════════
  // SWAP HISTORY
  // ═════════════════════════════════════════════

  static Future<void> addSwapHistory(String carId, String tireId, String fromPos, String toPos) async {
    final d = await db;
    final row = {
      'id': _genId(),
      'carId': carId,
      'tireId': tireId,
      'fromPos': fromPos,
      'toPos': toPos,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await d.insert('swap_history', row);
  }

  static Future<List<Map<String, dynamic>>> getSwapHistory(String tireId) async {
    final d = await db;
    return d.query(
      'swap_history',
      where: 'tireId = ?',
      whereArgs: [tireId],
      orderBy: 'createdAt ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getCombinedHistory(String tireId) async {
    final measurements = await getTireHistory(tireId);
    final swaps = await getSwapHistory(tireId);

    final combined = <Map<String, dynamic>>[];
    for (var m in measurements) {
      combined.add({...m, 'type': 'measurement'});
    }
    for (var s in swaps) {
      combined.add({...s, 'type': 'swap'});
    }

    combined.sort((a, b) {
      final dateA = DateTime.parse(a['createdAt'].toString());
      final dateB = DateTime.parse(b['createdAt'].toString());
      return dateA.compareTo(dateB);
    });

    return combined;
  }

  // ═════════════════════════════════════════════
  // NOTIFICATIONS
  // ═════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    final d = await db;
    return d.query(
      'notifications',
      where: "type NOT LIKE 'deleted_%'",
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  static Future<void> addNotification({
    required String type,
    required String title,
    required String body,
    String? carId,
    String? position,
  }) async {
    final d = await db;
    final id = _genId();
    await d.insert('notifications', {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'read': 0,
      'carId': carId,
      'position': position,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<bool> hasRecentNotification(String type, String? carId, String? position) async {
    final d = await db;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

    final rows = await d.query(
      'notifications',
      where: '(type = ? OR type = ?) AND carId = ? AND position = ? AND createdAt > ?',
      whereArgs: [type, 'deleted_$type', carId ?? '', position ?? '', cutoff],
    );
    return rows.isNotEmpty;
  }

  static Future<void> markRead(String id) async {
    final d = await db;
    await d.update('notifications', {'read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markAllRead() async {
    final d = await db;
    await d.update('notifications', {'read': 1}, where: 'read = 0');
  }

  static Future<void> deleteNotification(String id) async {
    final d = await db;
    final rows = await d.query('notifications', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final t = rows.first['type'] as String?;
      if (t != null && !t.startsWith('deleted_')) {
        await d.update('notifications', {'type': 'deleted_$t'}, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  static Future<void> deleteAllNotifications() async {
    final d = await db;
    final rows = await d.query('notifications');
    for (final r in rows) {
      final t = r['type'] as String?;
      if (t != null && !t.startsWith('deleted_')) {
        await d.update('notifications', {'type': 'deleted_$t'}, where: 'id = ?', whereArgs: [r['id']]);
      }
    }
  }

  static Future<int> getUnreadCount() async {
    final d = await db;
    final result = await d.rawQuery(
      "SELECT COUNT(*) as c FROM notifications WHERE read = 0 AND type NOT LIKE 'deleted_%'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
