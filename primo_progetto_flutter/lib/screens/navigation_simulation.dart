import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Waypoint simulati per il percorso (area del Nord Italia)
const List<LatLng> _simulatedWaypoints = [
  LatLng(45.4654, 9.1859),  // Milano
  LatLng(45.4720, 9.2010),
  LatLng(45.4790, 9.2140),
  LatLng(45.4860, 9.2270),
  LatLng(45.4930, 9.2400),
  LatLng(45.5000, 9.2530),
  LatLng(45.5070, 9.2660),
  LatLng(45.5140, 9.2790),
  LatLng(45.5210, 9.2920),
  LatLng(45.5280, 9.3050),
  LatLng(45.5350, 9.3180),
  LatLng(45.5420, 9.3310),
  LatLng(45.5490, 9.3440),
  LatLng(45.5560, 9.3570),
  LatLng(45.5630, 9.3700),
  LatLng(45.5700, 9.3830),
  LatLng(45.5770, 9.3960),
  LatLng(45.5840, 9.4090),
  LatLng(45.5910, 9.4220),
  LatLng(45.5980, 9.4350),
];

/// Distanza iniziale simulata (in metri) tra Leader e Follower
const double _initialDistance = 50.0;

/// Soglia sotto la quale avviene l'inversione dei ruoli
const double _swapThreshold = 0.0;

/// Schermata di simulazione navigazione con due moto su mappa offline
class NavigationSimulationScreen extends StatefulWidget {
  const NavigationSimulationScreen({super.key});

  @override
  State<NavigationSimulationScreen> createState() =>
      _NavigationSimulationScreenState();
}

class _NavigationSimulationScreenState
    extends State<NavigationSimulationScreen> {
  final MapController _mapController = MapController();

  /// Indice del waypoint corrente lungo il percorso simulato
  int _waypointIndex = 0;

  /// Percorso tracciato dal Leader corrente (linea blu)
  final List<LatLng> _leaderPath = [];

  /// Variabile di distanza fittizia (decrementa nel tempo)
  double _distance = _initialDistance;

  /// true = Moto 1 è Leader; false = Moto 2 è Leader
  bool _moto1IsLeader = true;

  /// Numero di inversioni avvenute
  int _swapCount = 0;

  Timer? _simulationTimer;
  Timer? _distanceTimer;

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _distanceTimer?.cancel();
    super.dispose();
  }

  void _startSimulation() {
    // Aggiungi il punto di partenza
    _leaderPath.add(_simulatedWaypoints[0]);

    // Timer che avanza la posizione del Leader ogni 1.5 secondi
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() {
        _waypointIndex =
            (_waypointIndex + 1) % _simulatedWaypoints.length;
        final newPoint = _simulatedWaypoints[_waypointIndex];
        _leaderPath.add(newPoint);

        // Centra la mappa sull'ultima posizione del leader
        _mapController.move(newPoint, _mapController.camera.zoom);
      });
    });

    // Timer che decrementa la distanza ogni 2 secondi
    _distanceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _distance -= 8.0;

        // Inversione ruoli quando la distanza scende sotto la soglia
        if (_distance <= _swapThreshold) {
          _performRoleSwap();
        }
      });
    });
  }

  /// Inverte i ruoli Leader/Follower e resetta la distanza e il percorso
  void _performRoleSwap() {
    _moto1IsLeader = !_moto1IsLeader;
    _swapCount++;
    _distance = _initialDistance;
    _leaderPath.clear();
    // Il nuovo Leader riparte dall'ultima posizione simulata
    if (_simulatedWaypoints.isNotEmpty) {
      _leaderPath.add(_simulatedWaypoints[_waypointIndex]);
    }
  }

  String get _leaderLabel => _moto1IsLeader ? 'Moto 1' : 'Moto 2';
  String get _followerLabel => _moto1IsLeader ? 'Moto 2' : 'Moto 1';

  @override
  Widget build(BuildContext context) {
    final currentLeaderPos = _simulatedWaypoints[_waypointIndex];
    // Posizione simulata del Follower: waypoint precedente (con wrapping circolare)
    final followerIndex =
        (_waypointIndex - 2 + _simulatedWaypoints.length) %
        _simulatedWaypoints.length;
    final followerPos = _simulatedWaypoints[followerIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulazione Navigazione'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // Mappa con OpenStreetMap (online) come fallback per la simulazione
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _simulatedWaypoints[0],
              initialZoom: 12.0,
              minZoom: 3.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.primo_progetto_flutter',
              ),

              // Polyline blu del percorso Leader
              if (_leaderPath.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _leaderPath,
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),

              // Marker del Leader (bandierina verde)
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLeaderPos,
                    width: 80,
                    height: 80,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.sports_motorsports,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Leader',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Marker del Follower (arancione)
                  Marker(
                    point: followerPos,
                    width: 80,
                    height: 80,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.sports_motorsports,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Follower',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Pannello di stato in alto a sinistra
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.6),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statusRow(
                    Icons.emoji_flags,
                    Colors.green,
                    'Leader',
                    _leaderLabel,
                  ),
                  const SizedBox(height: 6),
                  _statusRow(
                    Icons.directions_bike,
                    Colors.orange,
                    'Follower',
                    _followerLabel,
                  ),
                  const SizedBox(height: 6),
                  _statusRow(
                    Icons.social_distance,
                    _distance > 20
                        ? Colors.greenAccent
                        : _distance > 0
                            ? Colors.yellowAccent
                            : Colors.redAccent,
                    'Distanza',
                    '${_distance.toStringAsFixed(1)} m',
                  ),
                  const SizedBox(height: 6),
                  _statusRow(
                    Icons.swap_horiz,
                    Colors.cyanAccent,
                    'Inversioni',
                    '$_swapCount',
                  ),
                ],
              ),
            ),
          ),

          // Banner inversione ruoli
          if (_distance <= _swapThreshold)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'INVERSIONE RUOLI! $_leaderLabel ora è Leader.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusRow(
    IconData icon,
    Color iconColor,
    String label,
    String value,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
