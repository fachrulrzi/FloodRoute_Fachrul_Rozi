import 'package:flutter/material.dart';

import '../services/flood_service.dart';

class FloodInfoPanel extends StatelessWidget {
  final List<FloodRoad> floodRoads;

  const FloodInfoPanel({
    super.key,
    required this.floodRoads,
  });

  @override
  Widget build(BuildContext context) {
    // =========================
    // FILTER STATUS
    // =========================
    final floodedRoads = floodRoads.where((road) {
      final status = road.status.toLowerCase();

      return status == 'banjir' || status == 'flooded';
    }).toList();

    final warningRoads = floodRoads.where((road) {
      final status = road.status.toLowerCase();

      return status == 'waspada' || status == 'warning';
    }).toList();

    final normalRoads = floodRoads.where((road) {
      final status = road.status.toLowerCase();

      return status == 'normal';
    }).toList();

    final hasWarning = warningRoads.isNotEmpty;
    final hasFlood = floodedRoads.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ==========================================
          // HEADER
          // ==========================================
          Row(
            children: [
              Icon(
                hasFlood
                    ? Icons.warning_rounded
                    : hasWarning
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                color: hasFlood
                    ? Colors.red
                    : hasWarning
                        ? Colors.orange
                        : Colors.green,
                size: 24,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kondisi Banjir',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      hasFlood
                          ? '${floodedRoads.length} titik banjir terdeteksi'
                          : hasWarning
                              ? '${warningRoads.length} titik dalam kondisi waspada'
                              : 'Tidak ada titik banjir',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ==========================================
          // NORMAL
          // ==========================================
          if (!hasWarning && !hasFlood)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.water_drop_outlined,
                    color: Colors.green,
                  ),

                  SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Semua titik sensor dalam kondisi normal.',
                      style: TextStyle(
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ==========================================
          // WASPADA
          // ==========================================
          if (warningRoads.isNotEmpty) ...[
            _buildSectionTitle(
              icon: Icons.warning_amber_rounded,
              title: 'WASPADA',
              color: Colors.orange,
            ),

            const SizedBox(height: 8),

            ...warningRoads.map(
              (road) => _buildWarningItem(road),
            ),

            const SizedBox(height: 6),
          ],

          // ==========================================
          // BANJIR
          // ==========================================
          if (floodedRoads.isNotEmpty) ...[
            _buildSectionTitle(
              icon: Icons.block,
              title: 'BANJIR - TIDAK DAPAT DILALUI',
              color: Colors.red,
            ),

            const SizedBox(height: 8),

            ...floodedRoads.map(
              (road) => _buildFloodItem(road),
            ),

            const SizedBox(height: 6),
          ],

          // ==========================================
          // REALTIME STATUS
          // ==========================================
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),

              const SizedBox(width: 6),

              Text(
                'Data realtime',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================================================
  // SECTION TITLE
  // ==================================================

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 18,
        ),

        const SizedBox(width: 6),

        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ==================================================
  // ITEM WASPADA
  // ==================================================

  Widget _buildWarningItem(FloodRoad road) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withOpacity(0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ICON
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.water_drop,
              color: Colors.orange,
              size: 21,
            ),
          ),

          const SizedBox(width: 10),

          // INFO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  road.roadId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Row(
                  children: [
                    const Icon(
                      Icons.water,
                      size: 15,
                      color: Colors.blue,
                    ),

                    const SizedBox(width: 4),

                    Text(
                      '${road.waterLevel.toStringAsFixed(0)} cm',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'WASPADA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  'Kendaraan masih dapat melintas dengan hati-hati.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // ITEM BANJIR
  // ==================================================

  Widget _buildFloodItem(FloodRoad road) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.withOpacity(0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ICON
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.block,
              color: Colors.red,
              size: 21,
            ),
          ),

          const SizedBox(width: 10),

          // INFO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  road.roadId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Row(
                  children: [
                    const Icon(
                      Icons.water,
                      size: 15,
                      color: Colors.blue,
                    ),

                    const SizedBox(width: 4),

                    Text(
                      '${road.waterLevel.toStringAsFixed(0)} cm',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'BANJIR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  'Kendaraan tidak dapat melintas. Gunakan rute alternatif.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}