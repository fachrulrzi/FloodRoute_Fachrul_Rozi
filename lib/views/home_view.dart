import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import '../services/search_service.dart';
import '../services/graphhopper_service.dart';
import '../services/flood_service.dart';
import '../widgets/map_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  // =========================================================
  // LOCATION
  // =========================================================

  LatLng? currentLocation;

  StreamSubscription<Position>? positionSubscription;

  bool loadingLocation = true;


  // =========================================================
  // ORIGIN & DESTINATION
  // =========================================================

  LatLng? origin;

  LatLng? destination;

  final TextEditingController originController =
      TextEditingController();

  final TextEditingController destinationController =
      TextEditingController();


  // =========================================================
  // SEARCH
  // =========================================================

  List<SearchResult> searchResults = [];

  bool searching = false;

  String activeSearch = '';

  Timer? searchDebounce;


  // =========================================================
  // ROUTE
  // =========================================================

  List<LatLng> routePoints = [];

  bool loadingRoute = false;


  // =========================================================
  // VEHICLE
  // =========================================================

  String selectedVehicle = 'motor';


  // =========================================================
  // FLOOD
  // =========================================================

  List<FloodRoad> floodRoads = [];

  StreamSubscription<List<FloodRoad>>? floodSubscription;

  bool showFloodPanel = true;


  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _getLocation();

    _startFloodRealtime();
  }


  // =========================================================
  // GET CURRENT LOCATION
  // =========================================================

  Future<void> _getLocation() async {
    if (mounted) {
      setState(() {
        loadingLocation = true;
      });
    }

    try {
      final position =
          await LocationService.getCurrentLocation();

      if (!mounted) return;

      if (position == null) {
        setState(() {
          loadingLocation = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lokasi tidak dapat diperoleh',
            ),
          ),
        );

        return;
      }

      final location = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        currentLocation = location;

        origin = location;

        originController.text =
            '${location.latitude.toStringAsFixed(6)}, '
            '${location.longitude.toStringAsFixed(6)}';

        loadingLocation = false;
      });

      _startLocationTracking();

    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mendapatkan lokasi: $e',
          ),
        ),
      );
    }
  }


  // =========================================================
  // LIVE GPS
  // =========================================================

  void _startLocationTracking() {
    positionSubscription?.cancel();

    positionSubscription =
        LocationService.getLocationStream().listen(
      (Position position) {
        if (!mounted) return;

        final location = LatLng(
          position.latitude,
          position.longitude,
        );

        setState(() {
          currentLocation = location;
        });
      },
      onError: (error) {
        debugPrint(
          'GPS STREAM ERROR: $error',
        );
      },
    );
  }


  // =========================================================
  // SEARCH LOCATION
  // =========================================================

  void _onSearchChanged(
    String query,
    String searchType,
  ) {
    setState(() {
      activeSearch = searchType;
    });

    searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        searching = false;
      });

      return;
    }

    searchDebounce = Timer(
      const Duration(milliseconds: 600),
      () {
        _searchLocation(query);
      },
    );
  }


  Future<void> _searchLocation(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      searching = true;
    });

    try {
      final results =
          await SearchService.searchLocation(query);

      if (!mounted) return;

      setState(() {
        searchResults = results;

        searching = false;
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        searching = false;

        searchResults = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mencari lokasi: $e',
          ),
        ),
      );
    }
  }


  // =========================================================
  // SELECT SEARCH RESULT
  // =========================================================

  void _selectSearchResult(
    SearchResult result,
  ) {
    setState(() {
      if (activeSearch == 'origin') {
        origin = result.location;

        originController.text =
            result.displayName;

      } else if (activeSearch == 'destination') {
        destination = result.location;

        destinationController.text =
            result.displayName;
      }

      searchResults = [];

      activeSearch = '';

      routePoints = [];
    });

    FocusScope.of(context).unfocus();
  }


  // =========================================================
  // CLEAR SEARCH
  // =========================================================

  void _clearSearch(
    TextEditingController controller,
    String searchType,
  ) {
    controller.clear();

    setState(() {
      searchResults = [];

      activeSearch = searchType;
    });

    if (searchType == 'origin') {
      origin = null;

      routePoints = [];
    }

    if (searchType == 'destination') {
      destination = null;

      routePoints = [];
    }
  }


  // =========================================================
  // FIREBASE FLOOD REALTIME
  // =========================================================

  void _startFloodRealtime() {
    floodSubscription?.cancel();

    debugPrint('🏠 HOME: MEMULAI FLOOD REALTIME');

    floodSubscription = FloodService.watchFloodData().listen(
      (roads) {
        debugPrint(
          '🏠 HOME: UPDATE FLOOD DITERIMA '
          '(${roads.length} sensor)',
        );

        for (final road in roads) {
          debugPrint(
            '🏠 HOME SENSOR: '
            '${road.sensorId} | '
            '${road.locationName} | '
            '${road.waterLevel.toStringAsFixed(2)} cm | '
            '${road.status} | '
            '${road.latitude}, ${road.longitude} | '
            'timestamp: ${road.timestamp}',
          );
        }

        if (!mounted) return;

        setState(() {
          floodRoads = List<FloodRoad>.from(roads);
        });

        // Pastikan state Home sudah menerima data terbaru.
        debugPrint(
          '🏠 UI STATE DIPERBARUI: '
          '${floodRoads.map((road) =>
            '${road.sensorId}: '
            '${road.waterLevel.toStringAsFixed(2)} cm '
            '(${road.status})'
          ).join(' | ')}',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('❌ HOME: FIREBASE REALTIME ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
      onDone: () {
        debugPrint('⚠️ HOME: FIREBASE REALTIME STREAM SELESAI');
      },
    );
  }

  // =========================================================
  // CHECK FLOOD STATUS
  // =========================================================

  bool _hasFlood() {
    return floodRoads.any(
      (road) {
        final status =
            road.status.toLowerCase();

        return status == 'banjir' ||
            status == 'flooded';
      },
    );
  }


  // =========================================================
  // CHECK WARNING STATUS
  // =========================================================

  bool _hasWarning() {
    return floodRoads.any(
      (road) {
        final status =
            road.status.toLowerCase();

        return status == 'waspada' ||
            status == 'warning';
      },
    );
  }


  // =========================================================
  // FLOOD BUTTON
  // =========================================================

  Widget _buildFloodButton() {
    final hasFlood = _hasFlood();

    final hasWarning = _hasWarning();

    Color indicatorColor =
        Colors.green;

    if (hasFlood) {
      indicatorColor = Colors.red;
    } else if (hasWarning) {
      indicatorColor = Colors.orange;
    }

    return Material(
      color: Colors.white,
      elevation: 5,
      borderRadius:
          BorderRadius.circular(14),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(14),
        onTap: () {
          setState(() {
            showFloodPanel =
                !showFloodPanel;
          });
        },
        child: SizedBox(
          width: 50,
          height: 50,
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.water_drop,
                  color: Colors.blue,
                  size: 25,
                ),
              ),

              if (hasFlood || hasWarning)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(
                      color:
                          indicatorColor,
                      shape:
                          BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  // =========================================================
  // SHOW FLOOD HISTORY
  // =========================================================

  Future<void> _showFloodHistory(
    FloodRoad road,
  ) async {
    final sensorId =
        road.sensorId.isNotEmpty
            ? road.sensorId
            : road.roadId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FloodHistorySheet(
          road: road,
          sensorId: sensorId,
        );
      },
    );
  }


  // =========================================================
  // FLOOD PANEL
  // =========================================================

  Widget _buildFloodPanel() {

    // ---------------------------------------------------------
    // BANJIR
    // ---------------------------------------------------------

    final floodedRoads =
        floodRoads.where(
      (road) {
        final status =
            road.status.toLowerCase();

        return status == 'banjir' ||
            status == 'flooded';
      },
    ).toList();


    // ---------------------------------------------------------
    // WASPADA
    // ---------------------------------------------------------

    final warningRoads =
        floodRoads.where(
      (road) {
        final status =
            road.status.toLowerCase();

        return status == 'waspada' ||
            status == 'warning';
      },
    ).toList();


    // ---------------------------------------------------------
    // NORMAL
    // ---------------------------------------------------------

    final normalRoads =
        floodRoads.where(
      (road) {
        final status =
            road.status.toLowerCase();

        return status == 'normal';
      },
    ).toList();


    final bool hasFlood =
        floodedRoads.isNotEmpty;

    final bool hasWarning =
        warningRoads.isNotEmpty;

    final bool hasAnyData =
        floodRoads.isNotEmpty;


    return Container(
      width: double.infinity,

      margin: const EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: 4,
      ),

      padding:
          const EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10,
      ),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 2),
            color: Colors.black26,
          ),
        ],
      ),

      child: Column(
        mainAxisSize:
            MainAxisSize.min,

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // ===================================================
          // HEADER
          // ===================================================

          Row(
            children: [

              Icon(
                hasFlood
                    ? Icons.warning_rounded
                    : hasWarning
                        ? Icons.warning_amber_rounded
                        : Icons.water_drop,

                color: hasFlood
                    ? Colors.red
                    : hasWarning
                        ? Colors.orange
                        : Colors.blue,

                size: 20,
              ),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  'Informasi Banjir',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              IconButton(
                visualDensity:
                    VisualDensity.compact,

                padding:
                    EdgeInsets.zero,

                constraints:
                    const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),

                onPressed: () {
                  setState(() {
                    showFloodPanel =
                        false;
                  });
                },

                icon: const Icon(
                  Icons.close,
                  size: 22,
                ),
              ),
            ],
          ),

          const Divider(height: 1),

          const SizedBox(height: 8),


          // ===================================================
          // TIDAK ADA DATA
          // ===================================================

          if (!hasAnyData)
            Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.all(10),

              decoration: BoxDecoration(
                color:
                    Colors.green.shade50,

                borderRadius:
                    BorderRadius.circular(10),
              ),

              child: Row(
                children: [

                  Icon(
                    Icons.check_circle,
                    color:
                        Colors.green.shade700,
                    size: 20,
                  ),

                  const SizedBox(width: 8),

                  const Expanded(
                    child: Text(
                      'Tidak ada sensor yang '
                      'terdeteksi banjir.',
                      style: TextStyle(
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),


          // ===================================================
          // WASPADA
          // ===================================================

          if (warningRoads.isNotEmpty) ...[
            _buildFloodSectionTitle(
              icon:
                  Icons.warning_amber_rounded,
              title: 'WASPADA',
              color: Colors.orange,
            ),

            const SizedBox(height: 6),

            ...warningRoads.map(
              (road) =>
                  _buildWarningPanelItem(
                road,
              ),
            ),

            const SizedBox(height: 4),
          ],


          // ===================================================
          // BANJIR
          // ===================================================

          if (floodedRoads.isNotEmpty) ...[
            _buildFloodSectionTitle(
              icon: Icons.block,
              title:
                  'BANJIR - TIDAK DAPAT DILALUI',
              color: Colors.red,
            ),

            const SizedBox(height: 6),

            ...floodedRoads.map(
              (road) =>
                  _buildFloodPanelItem(
                road,
              ),
            ),

            const SizedBox(height: 4),
          ],


          // ===================================================
          // NORMAL
          // ===================================================

          if (!hasWarning && !hasFlood)
            Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.all(10),

              decoration: BoxDecoration(
                color:
                    Colors.green.shade50,

                borderRadius:
                    BorderRadius.circular(10),
              ),

              child: Row(
                children: [

                  Icon(
                    Icons.check_circle,
                    color:
                        Colors.green.shade700,
                    size: 20,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      normalRoads.isNotEmpty
                          ? 'Semua titik sensor '
                              'dalam kondisi normal.'
                          : 'Tidak ada sensor '
                              'dalam kondisi waspada '
                              'atau banjir.',

                      style:
                          const TextStyle(
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),


          const SizedBox(height: 6),


          // ===================================================
          // REALTIME
          // ===================================================

          Row(
            children: [

              Icon(
                Icons.sync,
                size: 14,
                color:
                    Colors.green.shade700,
              ),

              const SizedBox(width: 5),

              Text(
                'Data realtime',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      Colors.green.shade700,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // =========================================================
  // SECTION TITLE
  // =========================================================

  Widget _buildFloodSectionTitle({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [

        Icon(
          icon,
          color: color,
          size: 17,
        ),

        const SizedBox(width: 6),

        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight:
                FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }


  // =========================================================
  // WASPADA ITEM
  // =========================================================

  Widget _buildWarningPanelItem(
    FloodRoad road,
  ) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius:
            BorderRadius.circular(10),

        onTap: () {
          _showFloodHistory(road);
        },

        child: Container(
          width: double.infinity,

          padding:
              const EdgeInsets.all(10),

          decoration: BoxDecoration(
            color: Colors.orange.shade50,

            borderRadius:
                BorderRadius.circular(10),

            border: Border.all(
              color:
                  Colors.orange.shade200,
            ),
          ),

          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              // ICON
              Container(
                width: 34,
                height: 34,

                decoration:
                    BoxDecoration(
                  color:
                      Colors.orange.shade100,
                  shape:
                      BoxShape.circle,
                ),

                child: Icon(
                  Icons.warning_amber_rounded,
                  color:
                      Colors.orange.shade800,
                  size: 20,
                ),
              ),

              const SizedBox(width: 9),


              // INFO
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      road.locationName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,

                      style:
                          const TextStyle(
                        fontSize: 13,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Sensor: ${road.sensorId}',
                      style:
                          const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Ketinggian air: '
                      'Ketinggian air: ${road.waterLevel} cm',

                      style:
                          const TextStyle(
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [

                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),

                          decoration:
                              BoxDecoration(
                            color:
                                Colors.orange,

                            borderRadius:
                                BorderRadius.circular(
                              20,
                            ),
                          ),

                          child: const Text(
                            'WASPADA',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(width: 7),

                        Expanded(
                          child: Text(
                            'Klik untuk melihat histori',

                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.orange.shade900,
                            ),
                          ),
                        ),

                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color:
                              Colors.orange.shade700,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // =========================================================
  // BANJIR ITEM
  // =========================================================

  Widget _buildFloodPanelItem(
    FloodRoad road,
  ) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius:
            BorderRadius.circular(10),

        onTap: () {
          _showFloodHistory(road);
        },

        child: Container(
          width: double.infinity,

          padding:
              const EdgeInsets.all(10),

          decoration: BoxDecoration(
            color: Colors.red.shade50,

            borderRadius:
                BorderRadius.circular(10),

            border: Border.all(
              color:
                  Colors.red.shade200,
            ),
          ),

          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              // ICON
              Container(
                width: 34,
                height: 34,

                decoration:
                    BoxDecoration(
                  color:
                      Colors.red.shade100,
                  shape:
                      BoxShape.circle,
                ),

                child: Icon(
                  Icons.block,
                  color:
                      Colors.red.shade700,
                  size: 20,
                ),
              ),

              const SizedBox(width: 9),


              // INFO
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      road.locationName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,

                      style:
                          const TextStyle(
                        fontSize: 13,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Sensor: ${road.sensorId}',
                      style:
                          const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'Ketinggian air: '
                      '${road.waterLevel.toStringAsFixed(1)} cm',

                      style:
                          const TextStyle(
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [

                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),

                          decoration:
                              BoxDecoration(
                            color: Colors.red,

                            borderRadius:
                                BorderRadius.circular(
                              20,
                            ),
                          ),

                          child: const Text(
                            'BANJIR',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(width: 7),

                        Expanded(
                          child: Text(
                            'Klik untuk melihat histori',

                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.red.shade700,
                              fontWeight:
                                  FontWeight.w500,
                            ),
                          ),
                        ),

                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color:
                              Colors.red.shade700,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // =========================================================
  // FIND ROUTE
  // =========================================================

  
  Future<void> _findRoute() async {
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi awal belum tersedia'),
        ),
      );
      return;
    }

    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tujuan terlebih dahulu'),
        ),
      );
      return;
    }

    setState(() {
      loadingRoute = true;
      routePoints = [];
    });

    try {
      final points = await GraphHopperService.getRoute(
        origin: origin!,
        destination: destination!,
        floodRoads: floodRoads,
        vehicle: selectedVehicle,
      );

      if (!mounted) return;

      setState(() {
        routePoints = points;
        loadingRoute = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedVehicle == 'motor'
                ? 'Rute motor berhasil ditemukan'
                : 'Rute mobil berhasil ditemukan',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingRoute = false;
        routePoints = [];
      });

      if (_isNoSafeRouteError(e)) {
        await _showNoSafeRouteNotification();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mendapatkan rute:\n$e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  bool _isNoSafeRouteError(Object error) {
    final message = error.toString().toLowerCase();

    return message.contains('no_verified_safe_route') ||
        message.contains('graphhopper_flood_routing_failed') ||
        message.contains('connection between locations not found') ||
        message.contains('tidak ada rute aman') ||
        message.contains('rute masih melewati poligon banjir') ||
        message.contains('no safe route') ||
        message.contains('no route found');
  }

  Future<void> _showNoSafeRouteNotification() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.red,
            size: 48,
          ),
          title: const Text(
            'Tidak Ada Rute Alternatif',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'Tidak ditemukan jalur alternatif yang dapat '
            'dinyatakan aman menuju tujuan ini. Jalur yang '
            'tersedia mungkin terendam banjir atau tidak '
            'dapat diakses. Hindari memaksakan perjalanan '
            'melalui area tersebut.',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Mengerti'),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // START NAVIGATION
  // =========================================================

  void _startNavigation() {

    if (routePoints.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Navigasi dimulai',
        ),
      ),
    );
  }


  // =========================================================
  // SWAP
  // =========================================================

  void _swapLocations() {

    final oldOrigin = origin;

    final oldDestination = destination;

    final oldOriginText =
        originController.text;

    final oldDestinationText =
        destinationController.text;


    setState(() {

      origin = oldDestination;

      destination = oldOrigin;

      originController.text =
          oldDestinationText;

      destinationController.text =
          oldOriginText;

      routePoints = [];
    });
  }


  // =========================================================
  // VEHICLE SELECTOR
  // =========================================================

  Widget _buildVehicleSelector() {

    return Container(
      margin: const EdgeInsets.only(
        top: 12,
        bottom: 4,
      ),

      padding:
          const EdgeInsets.all(6),

      decoration: BoxDecoration(
        color: Colors.grey.shade100,

        borderRadius:
            BorderRadius.circular(12),
      ),

      child: Row(
        children: [

          Expanded(
            child:
                _buildVehicleButton(
              value: 'car',
              icon:
                  Icons.directions_car,
              label: 'Mobil',
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child:
                _buildVehicleButton(
              value: 'motor',
              icon:
                  Icons.two_wheeler,
              label: 'Motor',
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildVehicleButton({
    required String value,
    required IconData icon,
    required String label,
  }) {

    final bool selected =
        selectedVehicle == value;


    return GestureDetector(
      onTap: () {

        setState(() {

          selectedVehicle = value;

          routePoints = [];
        });
      },

      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 12,
        ),

        decoration: BoxDecoration(
          color: selected
              ? Colors.blue
              : Colors.transparent,

          borderRadius:
              BorderRadius.circular(10),
        ),

        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            Icon(
              icon,

              color: selected
                  ? Colors.white
                  : Colors.black87,
            ),

            const SizedBox(width: 8),

            Text(
              label,

              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.black87,

                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }


  // =========================================================
  // SEARCH FIELD
  // =========================================================

  Widget _buildSearchField({
    required String hint,
    required TextEditingController controller,
    required String searchType,
    required IconData icon,
  }) {

    return TextField(
      controller: controller,

      onTap: () {
        setState(() {
          activeSearch = searchType;
        });
      },

      onChanged: (value) {
        _onSearchChanged(
          value,
          searchType,
        );
      },

      decoration: InputDecoration(
        hintText: hint,

        prefixIcon: Icon(
          icon,
          size: 22,
          color:
              Colors.blueGrey.shade700,
        ),

        suffixIcon:
            controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: Colors
                          .blueGrey
                          .shade700,
                    ),

                    onPressed: () {
                      _clearSearch(
                        controller,
                        searchType,
                      );
                    },
                  )
                : null,

        border: InputBorder.none,

        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 14,
        ),
      ),
    );
  }


  // =========================================================
  // SEARCH RESULTS
  // =========================================================

  Widget _buildSearchResults() {

    if (searching) {
      return Container(
        margin:
            const EdgeInsets.only(
          top: 5,
        ),

        padding:
            const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius:
              BorderRadius.circular(12),
        ),

        child: const Row(
          children: [

            SizedBox(
              width: 20,
              height: 20,

              child:
                  CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),

            SizedBox(width: 12),

            Text(
              'Mencari lokasi...',
            ),
          ],
        ),
      );
    }


    if (searchResults.isEmpty) {
      return const SizedBox.shrink();
    }


    return Container(
      margin:
          const EdgeInsets.only(
        top: 5,
      ),

      constraints:
          const BoxConstraints(
        maxHeight: 300,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(12),
      ),

      child: ListView.builder(
        shrinkWrap: true,

        itemCount:
            searchResults.length,

        itemBuilder:
            (context, index) {

          final result =
              searchResults[index];


          return ListTile(
            leading: Icon(
              Icons.location_on,
              color:
                  Colors.blueGrey.shade700,
            ),

            title: Text(
              result.name,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
            ),

            subtitle: Text(
              result.displayName,
              maxLines: 2,
              overflow:
                  TextOverflow.ellipsis,
            ),

            onTap: () {
              _selectSearchResult(
                result,
              );
            },
          );
        },
      ),
    );
  }


  // =========================================================
  // BOTTOM PANEL
  // =========================================================

  Widget _buildBottomPanel() {

    final bool hasDestination =
        destination != null;

    final bool routeReady =
        routePoints.length > 1;


    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        12,
      ),

      decoration:
          const BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.vertical(
          top:
              Radius.circular(24),
        ),

        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, -2),
            color: Colors.black26,
          ),
        ],
      ),

      child: Column(
        mainAxisSize:
            MainAxisSize.min,

        children: [

          // ===================================================
          // HEADER
          // ===================================================

          Row(
            children: [

              const Icon(
                Icons.route,
                size: 27,
                color: Colors.blue,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    const Text(
                      'FloodRoute',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    Text(
                      !hasDestination
                          ? 'Pilih tujuan untuk mulai'
                          : loadingRoute
                              ? 'Mencari rute...'
                              : routeReady
                                  ? 'Rute tersedia'
                                  : 'Siap mencari rute',

                      style:
                          const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),


          // ===================================================
          // VEHICLE
          // ===================================================

          if (hasDestination &&
              !routeReady &&
              !loadingRoute)
            _buildVehicleSelector(),


          // ===================================================
          // ROUTE INFO
          // ===================================================

          if (routeReady)
            Container(
              margin:
                  const EdgeInsets.only(
                top: 12,
                bottom: 4,
              ),

              padding:
                  const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color:
                    Colors.blue.shade50,

                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),

              child: Row(
                children: [

                  Icon(
                    selectedVehicle ==
                            'motor'
                        ? Icons.two_wheeler
                        : Icons.directions_car,

                    color: Colors.blue,
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      selectedVehicle ==
                              'motor'
                          ? 'Rute untuk motor'
                          : 'Rute untuk mobil',

                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        routePoints = [];
                      });
                    },

                    child:
                        const Text(
                      'Ubah',
                    ),
                  ),
                ],
              ),
            ),


          const SizedBox(height: 10),


          // ===================================================
          // MAIN BUTTON
          // ===================================================

          SizedBox(
            width: double.infinity,
            height: 52,

            child:
                ElevatedButton(
              onPressed:
                  loadingRoute
                      ? null
                      : routeReady
                          ? _startNavigation
                          : hasDestination
                              ? _findRoute
                              : null,

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.blue,

                foregroundColor:
                    Colors.white,

                disabledBackgroundColor:
                    Colors.grey.shade400,

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
              ),

              child: loadingRoute
                  ? const SizedBox(
                      width: 24,
                      height: 24,

                      child:
                          CircularProgressIndicator(
                        color:
                            Colors.white,
                        strokeWidth: 3,
                      ),
                    )

                  : Text(
                      routeReady
                          ? 'MULAI NAVIGASI'
                          : 'CARI RUTE',

                      style:
                          const TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }


  // =========================================================
  // BOTTOM AREA
  // =========================================================

  Widget _buildBottomArea() {

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,

      child: SafeArea(
        top: false,

        child: Column(
          mainAxisSize:
              MainAxisSize.min,

          children: [

            if (showFloodPanel)
              _buildFloodPanel(),

            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }


  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {

    if (loadingLocation ||
        currentLocation == null) {

      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }


    return Scaffold(
      body: Stack(
        children: [

          // =================================================
          // MAP
          // =================================================

          Positioned.fill(
            child: MapView(
              currentLocation:
                  currentLocation!,

              origin: origin,

              destination:
                  destination,

              routePoints:
                  routePoints,

              floodRoads:
                  floodRoads,
            ),
          ),


          // =================================================
          // TOP SEARCH PANEL
          // =================================================

          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.all(12),

              child: Column(
                children: [

                  Material(
                    elevation: 5,

                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),

                    child: Container(
                      decoration:
                          BoxDecoration(
                        color: Colors.white,

                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                      ),

                      child: Column(
                        children: [

                          // ---------------------------------
                          // ORIGIN
                          // ---------------------------------

                          _buildSearchField(
                            hint:
                                'Lokasi awal',

                            controller:
                                originController,

                            searchType:
                                'origin',

                            icon: Icons
                                .radio_button_checked,
                          ),

                          const Divider(
                            height: 1,
                            indent: 50,
                            endIndent: 50,
                          ),


                          // ---------------------------------
                          // DESTINATION
                          // ---------------------------------

                          _buildSearchField(
                            hint:
                                'Cari tujuan',

                            controller:
                                destinationController,

                            searchType:
                                'destination',

                            icon: Icons
                                .location_on,
                          ),


                          // ---------------------------------
                          // SWAP
                          // ---------------------------------

                          Align(
                            alignment:
                                Alignment.centerRight,

                            child:
                                IconButton(
                              icon: Icon(
                                Icons.swap_vert,
                                color: Colors
                                    .blueGrey
                                    .shade700,
                              ),

                              onPressed:
                                  _swapLocations,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),


                  // -------------------------------------------
                  // SEARCH RESULTS
                  // -------------------------------------------

                  _buildSearchResults(),
                ],
              ),
            ),
          ),


          // =================================================
          // FLOOD BUTTON
          // =================================================

          if (!showFloodPanel)
            Positioned(
              right: 12,
              top: 150,

              child: SafeArea(
                child:
                    _buildFloodButton(),
              ),
            ),


          // =================================================
          // BOTTOM AREA
          // =================================================

          _buildBottomArea(),
        ],
      ),
    );
  }


  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {

    searchDebounce?.cancel();

    positionSubscription?.cancel();

    floodSubscription?.cancel();

    originController.dispose();

    destinationController.dispose();

    super.dispose();
  }
}


// ################################################################
// #
// #                     FLOOD HISTORY SHEET
// #
// ################################################################

class _FloodHistorySheet extends StatefulWidget {

  final FloodRoad road;

  final String sensorId;

  const _FloodHistorySheet({
    required this.road,
    required this.sensorId,
  });

  @override
  State<_FloodHistorySheet> createState() =>
      _FloodHistorySheetState();
}


class _FloodHistorySheetState
    extends State<_FloodHistorySheet> {

  // =========================================================
  // STATE
  // =========================================================

  late Future<List<FloodHistory>>
      _historyFuture;


  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _historyFuture =
        FloodService.getFloodHistory(
      widget.sensorId,
    );
  }


  // =========================================================
  // FORMAT TIME
  // =========================================================

  String _formatTimestamp(
    int? timestamp,
  ) {

    if (timestamp == null) {
      return '-';
    }

    final date =
        DateTime.fromMillisecondsSinceEpoch(
      timestamp,
    ).toLocal();

    final day =
        date.day.toString().padLeft(
          2,
          '0',
        );

    final month =
        date.month.toString().padLeft(
          2,
          '0',
        );

    final year =
        date.year.toString();

    final hour =
        date.hour.toString().padLeft(
          2,
          '0',
        );

    final minute =
        date.minute.toString().padLeft(
          2,
          '0',
        );

    final second =
        date.second.toString().padLeft(
          2,
          '0',
        );

    return '$day/$month/$year '
        '$hour:$minute:$second';
  }


  // =========================================================
  // STATUS COLOR
  // =========================================================

  Color _statusColor(
    String status,
  ) {

    switch (
        status.toLowerCase()) {

      case 'banjir':
      case 'flooded':
        return Colors.red;

      case 'waspada':
      case 'warning':
        return Colors.orange;

      default:
        return Colors.green;
    }
  }


  // =========================================================
  // STATUS ICON
  // =========================================================

  IconData _statusIcon(
    String status,
  ) {

    switch (
        status.toLowerCase()) {

      case 'banjir':
      case 'flooded':
        return Icons.block;

      case 'waspada':
      case 'warning':
        return Icons.warning_amber_rounded;

      default:
        return Icons.check_circle;
    }
  }


  // =========================================================
  // BUILD HISTORY ITEM
  // =========================================================

  Widget _buildHistoryItem(
    FloodHistory history,
  ) {

    final color =
        _statusColor(
      history.status,
    );

    final icon =
        _statusIcon(
      history.status,
    );


    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),

      padding:
          const EdgeInsets.all(11),

      decoration: BoxDecoration(
        color:
            color.withOpacity(0.06),

        borderRadius:
            BorderRadius.circular(12),

        border: Border.all(
          color:
              color.withOpacity(0.20),
        ),
      ),

      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // =================================================
          // ICON
          // =================================================

          Container(
            width: 36,
            height: 36,

            decoration:
                BoxDecoration(
              color:
                  color.withOpacity(0.12),

              shape:
                  BoxShape.circle,
            ),

            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),

          const SizedBox(width: 10),


          // =================================================
          // DATA
          // =================================================

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Row(
                  children: [

                    Expanded(
                      child: Text(
                        _formatTimestamp(
                          history.timestamp,
                        ),

                        style:
                            const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),

                      decoration:
                          BoxDecoration(
                        color: color,

                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),

                      child: Text(
                        history.status
                            .toUpperCase(),

                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 9,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  '${history.waterLevel} cm',

                  style:
                      const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Row(
                  children: [

                    Expanded(
                      child: Text(
                        'Sensor 1: '
                        '${history.sensor1.toStringAsFixed(1)} cm',

                        style:
                            const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                    Expanded(
                      child: Text(
                        'Sensor 2: '
                        '${history.sensor2.toStringAsFixed(1)} cm',

                        style:
                            const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),

                if (history.anomaly)
                  Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 5,
                    ),

                    child: Row(
                      children: [

                        Icon(
                          Icons.warning,
                          size: 13,
                          color: Colors.deepOrange,
                        ),

                        const SizedBox(
                          width: 4,
                        ),

                        Text(
                          'Anomaly terdeteksi',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                Colors.deepOrange.shade700,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {

    return Container(
      height:
          MediaQuery.of(context).size.height *
              0.72,

      decoration:
          const BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),

      child: Column(
        children: [

          // =================================================
          // HANDLE
          // =================================================

          const SizedBox(height: 8),

          Container(
            width: 40,
            height: 4,

            decoration: BoxDecoration(
              color: Colors.grey.shade300,

              borderRadius:
                  BorderRadius.circular(10),
            ),
          ),

          const SizedBox(height: 12),


          // =================================================
          // HEADER
          // =================================================

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),

            child: Row(
              children: [

                Container(
                  width: 42,
                  height: 42,

                  decoration:
                      BoxDecoration(
                    color:
                        Colors.blue.shade50,

                    shape:
                        BoxShape.circle,
                  ),

                  child: const Icon(
                    Icons.history,
                    color: Colors.blue,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      const Text(
                        'Histori Banjir',

                        style:
                            TextStyle(
                          fontSize: 17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        widget.sensorId,

                        style:
                            const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),

                      Text(
                        widget.road.locationName,

                        maxLines: 1,

                        overflow:
                            TextOverflow.ellipsis,

                        style:
                            const TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },

                  icon:
                      const Icon(
                    Icons.close,
                  ),
                ),
              ],
            ),
          ),


          const Divider(height: 20),


          // =================================================
          // CURRENT STATUS
          // =================================================

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),

            child: Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.all(12),

              decoration:
                  BoxDecoration(
                color:
                    _statusColor(
                  widget.road.status,
                ).withOpacity(0.08),

                borderRadius:
                    BorderRadius.circular(12),
              ),

              child: Row(
                children: [

                  Icon(
                    _statusIcon(
                      widget.road.status,
                    ),

                    color:
                        _statusColor(
                      widget.road.status,
                    ),

                    size: 20,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      'Kondisi sekarang: '
                      '${widget.road.waterLevel.toStringAsFixed(1)} cm',

                      style:
                          const TextStyle(
                        fontSize: 12,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),


          const SizedBox(height: 10),


          // =================================================
          // HISTORY
          // =================================================

          Expanded(
            child:
                FutureBuilder<
                    List<FloodHistory>>(
              future: _historyFuture,

              builder:
                  (context, snapshot) {

                // -------------------------------------------
                // LOADING
                // -------------------------------------------

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {

                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }


                // -------------------------------------------
                // ERROR
                // -------------------------------------------

                if (snapshot.hasError) {

                  return Center(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        20,
                      ),

                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,

                        children: [

                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 40,
                          ),

                          const SizedBox(
                            height: 10,
                          ),

                          const Text(
                            'Gagal mengambil histori.',
                            textAlign:
                                TextAlign.center,
                          ),

                          const SizedBox(
                            height: 10,
                          ),

                          ElevatedButton(
                            onPressed: () {

                              setState(() {
                                _historyFuture =
                                    FloodService
                                        .getFloodHistory(
                                  widget.sensorId,
                                );
                              });
                            },

                            child:
                                const Text(
                              'Coba lagi',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }


                final histories =
                    snapshot.data ?? [];


                // -------------------------------------------
                // KOSONG
                // -------------------------------------------

                if (histories.isEmpty) {

                  return const Center(
                    child: Padding(
                      padding:
                          EdgeInsets.all(20),

                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,

                        children: [

                          Icon(
                            Icons.history,
                            size: 45,
                            color: Colors.grey,
                          ),

                          SizedBox(height: 10),

                          Text(
                            'Belum ada histori '
                            'untuk sensor ini.',
                            textAlign:
                                TextAlign.center,

                            style: TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }


                // -------------------------------------------
                // LIST HISTORI
                // -------------------------------------------

                return ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    20,
                  ),

                  itemCount:
                      histories.length,

                  itemBuilder:
                      (context, index) {

                    return _buildHistoryItem(
                      histories[index],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}