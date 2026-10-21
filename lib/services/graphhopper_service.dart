import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'flood_service.dart';

class GraphHopperService {
  static const String baseUrl = 'http://localhost:8000';

  static Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
    required List<FloodRoad> floodRoads,

    // PILIHAN KENDARAAN
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

        // kirim pilihan kendaraan ke FastAPI
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

    final coordinates =
        paths[0]['points']['coordinates'] as List;

    return coordinates.map<LatLng>((point) {
      final longitude =
          (point[0] as num).toDouble();

      final latitude =
          (point[1] as num).toDouble();

      return LatLng(
        latitude,
        longitude,
      );
    }).toList();
  }
}