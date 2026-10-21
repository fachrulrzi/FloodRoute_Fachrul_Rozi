import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SearchResult {
  final String name;
  final String displayName;
  final LatLng location;

  SearchResult({
    required this.name,
    required this.displayName,
    required this.location,
  });
}

class SearchService {
  static Future<List<SearchResult>> searchLocation(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': query,
        'format': 'jsonv2',
        'limit': '5',
        'countrycodes': 'id',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'FloodRoute/1.0',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal mencari lokasi');
    }

    final List data = jsonDecode(response.body);

    return data.map((item) {
      return SearchResult(
        name: item['name'] ?? item['display_name'],
        displayName: item['display_name'],
        location: LatLng(
          double.parse(item['lat']),
          double.parse(item['lon']),
        ),
      );
    }).toList();
  }
}