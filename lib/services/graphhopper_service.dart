
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'flood_service.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double timeMilliseconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.timeMilliseconds,
  });

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
    }

    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  String get formattedDuration {
    final totalMinutes = (timeMilliseconds / 60000).round();

    if (totalMinutes < 60) {
      return '$totalMinutes menit';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours jam';
    }

    return '$hours jam $minutes menit';
  }
}

class GraphHopperService {
  static const String baseUrl = 'http://localhost:8000';

  static Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    required List<FloodRoad> floodRoads,
    required String vehicle,
  }) async {
    final uri = Uri.parse('$baseUrl/route');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'origin': {
          'latitude': origin.latitude,
          'longitude': origin.longitude,
        },
        'destination': {
          'latitude': destination.latitude,
          'longitude': destination.longitude,
        },
        'vehicle': vehicle,
        'flood_roads': floodRoads.map((road) {
          return {
            'road_id': road.roadId,
            'latitude': road.latitude,
            'longitude': road.longitude,
            'water_level': road.waterLevel,
            'status': road.status,
          };
        }).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Backend route error: '
        '${response.statusCode}\n'
        '${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    final paths = data['paths'];

    if (paths == null || paths.isEmpty) {
      throw Exception('Route tidak ditemukan');
    }

    final path = paths[0];

    final coordinates =
        path['points']['coordinates'] as List;

    final routePoints = coordinates.map<LatLng>((point) {
      final longitude = (point[0] as num).toDouble();
      final latitude = (point[1] as num).toDouble();

      return LatLng(latitude, longitude);
    }).toList();

    return RouteResult(
      points: routePoints,
      distanceMeters: (path['distance'] as num).toDouble(),
      timeMilliseconds: (path['time'] as num).toDouble(),
    );
  }
}
