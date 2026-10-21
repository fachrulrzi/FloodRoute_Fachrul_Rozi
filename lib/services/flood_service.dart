
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

// ============================================================
// MODEL FLOOD ROAD
// ============================================================

class FloodRoad {
  final String roadId;
  final String sensorId;
  final String locationName;

  final double latitude;
  final double longitude;

  final double waterLevel;
  final String status;

  final double sensor1;
  final double sensor2;

  final double difference;
  final double differencePercent;

  final bool anomaly;
  final int? timestamp;

  FloodRoad({
    required this.roadId,
    required this.sensorId,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.waterLevel,
    required this.status,
    required this.sensor1,
    required this.sensor2,
    required this.difference,
    required this.differencePercent,
    required this.anomaly,
    required this.timestamp,
  });

  LatLng get location => LatLng(latitude, longitude);

  factory FloodRoad.fromFirebase(
    String roadId,
    Map<dynamic, dynamic> json,
  ) {
    return FloodRoad(
      roadId: roadId,
      sensorId: json['sensor_id']?.toString() ?? roadId,
      locationName:
          json['location_name']?.toString() ?? roadId,
      latitude: (json['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0.0,
      waterLevel:
          (json['level_cm'] as num?)?.toDouble() ?? 0.0,
      status: json['status']?.toString() ?? 'normal',
      sensor1: (json['sensor1_cm'] as num?)?.toDouble() ?? 0.0,
      sensor2: (json['sensor2_cm'] as num?)?.toDouble() ?? 0.0,
      difference:
          (json['difference_cm'] as num?)?.toDouble() ?? 0.0,
      differencePercent:
          (json['difference_percent'] as num?)?.toDouble() ??
              0.0,
      anomaly: json['anomaly'] == true,
      timestamp: (json['timestamp'] as num?)?.toInt(),
    );
  }
}

// ============================================================
// MODEL HISTORI BANJIR
// ============================================================

class FloodHistory {
  final int? timestamp;
  final double waterLevel;
  final String status;

  final double sensor1;
  final double sensor2;

  final double difference;
  final double differencePercent;

  final bool anomaly;

  FloodHistory({
    required this.timestamp,
    required this.waterLevel,
    required this.status,
    required this.sensor1,
    required this.sensor2,
    required this.difference,
    required this.differencePercent,
    required this.anomaly,
  });

  factory FloodHistory.fromFirebase(
    Map<dynamic, dynamic> json,
  ) {
    return FloodHistory(
      timestamp: (json['timestamp'] as num?)?.toInt(),
      waterLevel:
          (json['level_cm'] as num?)?.toDouble() ?? 0.0,
      status: json['status']?.toString() ?? 'normal',
      sensor1: (json['sensor1_cm'] as num?)?.toDouble() ?? 0.0,
      sensor2: (json['sensor2_cm'] as num?)?.toDouble() ?? 0.0,
      difference:
          (json['difference_cm'] as num?)?.toDouble() ?? 0.0,
      differencePercent:
          (json['difference_percent'] as num?)?.toDouble() ??
              0.0,
      anomaly: json['anomaly'] == true,
    );
  }
}

// ============================================================
// FLOOD SERVICE
// ============================================================

class FloodService {
  static final DatabaseReference _sensorsRef =
      FirebaseDatabase.instance.ref('sensors');

  // ==========================================================
  // REALTIME FLOOD DATA
  // ==========================================================

  static Stream<List<FloodRoad>> watchFloodData() {
    debugPrint('🔥 MEMULAI FIREBASE REALTIME LISTENER');
    debugPrint('🔥 PATH FIREBASE: ${_sensorsRef.path}');

    return _sensorsRef.onValue.map((DatabaseEvent event) {
      debugPrint(
        '🔥 EVENT FIREBASE MASUK | '
        'type: ${event.type} | '
        'key: ${event.snapshot.key}',
      );

      final data = event.snapshot.value;

      if (data == null) {
        debugPrint('⚠️ DATA SENSOR KOSONG');
        return <FloodRoad>[];
      }

      if (data is! Map) {
        debugPrint(
          '❌ FORMAT DATA FIREBASE TIDAK VALID: '
          '${data.runtimeType}',
        );
        return <FloodRoad>[];
      }

      final sensors = Map<dynamic, dynamic>.from(data);

      debugPrint('📡 JUMLAH SENSOR: ${sensors.length}');

      final roads = <FloodRoad>[];

      for (final entry in sensors.entries) {
        final roadId = entry.key.toString();

        if (entry.value is! Map) {
          debugPrint('⚠️ DATA SENSOR $roadId TIDAK VALID');
          continue;
        }

        try {
          final sensorData =
              Map<dynamic, dynamic>.from(entry.value as Map);

          final road = FloodRoad.fromFirebase(
            roadId,
            sensorData,
          );

          roads.add(road);

          debugPrint(
            '📡 SENSOR UPDATE | '
            '${road.sensorId} | '
            '${road.locationName} | '
            '${road.waterLevel} cm | '
            '${road.status} | '
            '${road.latitude}, ${road.longitude} | '
            'timestamp: ${road.timestamp}',
          );
        } catch (e, stackTrace) {
          debugPrint(
            '❌ GAGAL MEMBACA SENSOR $roadId: $e',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      debugPrint(
        '✅ DATA FLOOD BERHASIL DIPROSES: '
        '${roads.length} sensor',
      );

      return roads;
    });
  }

  // ==========================================================
  // AMBIL HISTORI SENSOR
  // ==========================================================

  static Future<List<FloodHistory>> getFloodHistory(
    String sensorId,
  ) async {
    debugPrint('📚 MENGAMBIL HISTORI SENSOR: $sensorId');

    try {
      final historyRef =
          FirebaseDatabase.instance.ref('history/$sensorId');

      final snapshot = await historyRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        debugPrint('⚠️ HISTORI $sensorId KOSONG');
        return <FloodHistory>[];
      }

      if (snapshot.value is! Map) {
        debugPrint('❌ FORMAT HISTORI TIDAK VALID');
        return <FloodHistory>[];
      }

      final data =
          Map<dynamic, dynamic>.from(snapshot.value as Map);

      final histories = <FloodHistory>[];

      for (final value in data.values) {
        if (value is! Map) {
          continue;
        }

        try {
          histories.add(
            FloodHistory.fromFirebase(
              Map<dynamic, dynamic>.from(value),
            ),
          );
        } catch (e, stackTrace) {
          debugPrint('❌ GAGAL MEMBACA HISTORI: $e');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      histories.sort((a, b) {
        return (b.timestamp ?? 0).compareTo(a.timestamp ?? 0);
      });

      debugPrint(
        '✅ HISTORI $sensorId: ${histories.length} data',
      );

      return histories;
    } catch (e, stackTrace) {
      debugPrint(
        '❌ ERROR MENGAMBIL HISTORI $sensorId: $e',
      );
      debugPrintStack(stackTrace: stackTrace);

      return <FloodHistory>[];
    }
  }
}
