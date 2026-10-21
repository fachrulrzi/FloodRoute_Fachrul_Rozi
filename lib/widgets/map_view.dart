import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/flood_service.dart';

class MapView extends StatefulWidget {
  final LatLng currentLocation;
  final LatLng? origin;
  final LatLng? destination;
  final List<LatLng> routePoints;
  final List<FloodRoad> floodRoads;

  const MapView({
    super.key,
    required this.currentLocation,
    this.origin,
    this.destination,
    this.routePoints = const [],
    this.floodRoads = const [],
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController mapController = MapController();

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Pindahkan kamera ke tujuan jika tujuan berubah.
    if (widget.destination != oldWidget.destination &&
        widget.destination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        mapController.move(
          widget.destination!,
          15,
        );
      });
    }

    // Tampilkan seluruh rute jika titik rute berubah.
    if (widget.routePoints != oldWidget.routePoints &&
        widget.routePoints.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final bounds = LatLngBounds.fromPoints(widget.routePoints);

        mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(60),
          ),
        );
      });
    }

    // Log saat data sensor berubah.
    if (widget.floodRoads != oldWidget.floodRoads) {
      debugPrint(
        '🗺️ MAPVIEW: Data sensor diperbarui '
        '(${widget.floodRoads.length} sensor)',
      );

      for (final road in widget.floodRoads) {
        debugPrint(
          '🗺️ SENSOR ${road.sensorId} | '
          'Air: ${road.waterLevel} cm | '
          'Status: ${road.status} | '
          'Lokasi: ${road.location}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Memeriksa nilai yang diterima peta.
    debugPrint(
      '🗺️ MAPVIEW BUILD: '
      '${widget.floodRoads.map(
        (road) =>
            '${road.sensorId}: ${road.waterLevel} cm '
            '(${road.status})',
      ).join(' | ')}',
    );

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: widget.currentLocation,
        initialZoom: 14,
      ),
      children: [
        // =========================
        // OPENSTREETMAP
        // =========================
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.floodroute',
        ),

        // =========================
        // RUTE
        // =========================
        if (widget.routePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.routePoints,
                strokeWidth: 6,
                color: Colors.blue,
              ),
            ],
          ),

        // =========================
        // MARKER
        // =========================
        MarkerLayer(
          markers: [
            // Lokasi GPS sekarang.
            Marker(
              point: widget.currentLocation,
              width: 45,
              height: 45,
              child: const Icon(
                Icons.my_location,
                color: Colors.blue,
                size: 32,
              ),
            ),

            // Titik asal.
            if (widget.origin != null &&
                widget.origin != widget.currentLocation)
              Marker(
                point: widget.origin!,
                width: 45,
                height: 45,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 40,
                ),
              ),

            // Titik tujuan.
            if (widget.destination != null)
              Marker(
                point: widget.destination!,
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 50,
                ),
              ),

            // Marker sensor banjir dari Firebase.
            ...widget.floodRoads.map((road) {
              final status = road.status.toLowerCase().trim();

              final Color markerColor;
              final IconData markerIcon;

              if (status == 'banjir' ||
                  status == 'flooded') {
                markerColor = Colors.red;
                markerIcon = Icons.warning;
              } else if (status == 'warning' ||
                  status == 'waspada') {
                markerColor = Colors.amber;
                markerIcon = Icons.warning_amber;
              } else {
                markerColor = Colors.green;
                markerIcon = Icons.warning;
              }

              return Marker(
                point: road.location,
                width: 100,
                height: 75,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      markerIcon,
                      color: markerColor,
                      size: 35,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: markerColor,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '${road.waterLevel} cm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: markerColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),

        // =========================
        // ATRIBUSI OPENSTREETMAP
        // =========================
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
            ),
          ],
        ),
      ],
    );
  }
}