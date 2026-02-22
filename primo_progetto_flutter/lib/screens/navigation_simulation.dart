import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Role enum
// ---------------------------------------------------------------------------
enum MotoRole { leader, follower }

// ---------------------------------------------------------------------------
// RouteNotifier – efficient mutable list backed by ChangeNotifier.
//
// Using a plain ValueNotifier<List<LatLng>> would require creating a full copy
// of the list on every GPS tick to trigger the equality check, which is O(n)
// per tick and produces garbage proportional to the route length.
//
// RouteNotifier keeps the list mutable and calls notifyListeners() explicitly,
// so the PolylineLayer is rebuilt only when new points actually arrive –
// without any allocation overhead.
// ---------------------------------------------------------------------------
class _RouteNotifier extends ChangeNotifier {
  final List<LatLng> points = [];

  void add(LatLng point) {
    points.add(point);
    notifyListeners();
  }

  void clear() {
    points.clear();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// NavigationSimulationScreen
// ---------------------------------------------------------------------------
class NavigationSimulationScreen extends StatefulWidget {
  const NavigationSimulationScreen({super.key});

  @override
  State<NavigationSimulationScreen> createState() =>
      _NavigationSimulationScreenState();
}

class _NavigationSimulationScreenState
    extends State<NavigationSimulationScreen> {
  // --- Hysteresis thresholds for role switching ---
  //
  // Two separate thresholds prevent the classic "chattering" problem where the
  // distance value oscillates around a single boundary and causes continuous
  // role flips:
  //
  //   - _enterFollowerThreshold  : if current role == leader   and
  //                                 distance drops BELOW this → become follower
  //   - _enterLeaderThreshold    : if current role == follower and
  //                                 distance rises ABOVE this  → become leader
  //
  // Because _enterLeaderThreshold > _enterFollowerThreshold there is a "dead
  // zone" in between where no switch occurs, eliminating oscillation.
  static const double _enterFollowerThreshold = 0.0;
  static const double _enterLeaderThreshold = 5.0;

  // Minimum time between two consecutive role switches (extra guard against
  // rapid GPS noise driving distance through the thresholds quickly).
  static const Duration _roleSwitchCooldown = Duration(seconds: 3);

  // --- Simulation parameters ---
  // Base GPS position (Milano).
  static const LatLng _basePosition = LatLng(45.4654, 9.1859);

  // GPS simulation step (degrees per tick).
  static const double _latStep = 0.0001;
  static const double _lngStep = 0.00015;

  // Distance simulation: sawtooth pattern over 20 ticks (40 s), ranging
  // roughly from +10 m down to –14 m, giving one full leader/follower cycle
  // every ~40 seconds – visible enough to exercise the logic in a demo.
  // Formula: 10 - (tick % 20) * 1.2 + 2 * sin(tick * 0.5)
  double _distanceAtTick(int tick) =>
      10.0 - (tick % 20) * 1.2 + 2.0 * sin(tick * 0.5);

  // --- Mutable state ---
  MotoRole _role = MotoRole.leader;
  double _simulatedDistance = 10.0;
  DateTime? _lastRoleSwitch;
  int _tick = 0;

  // Route notifier keeps points efficiently without per-tick list copies.
  final _RouteNotifier _route = _RouteNotifier();

  // Map controller.
  final MapController _mapController = MapController();

  // Simulation timer.
  Timer? _simulationTimer;

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _route.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Simulation helpers
  // -------------------------------------------------------------------------

  void _startSimulation() {
    _simulationTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _onGpsTick(),
    );
  }

  void _onGpsTick() {
    _tick++;

    // 1. Simulate a GPS coordinate (gentle sine-wave path).
    final newPoint = LatLng(
      _basePosition.latitude + _tick * _latStep + 0.0002 * sin(_tick * 0.3),
      _basePosition.longitude + _tick * _lngStep + 0.0002 * cos(_tick * 0.2),
    );

    // 2. Simulate distance value.
    final newDistance = _distanceAtTick(_tick);

    // 3. Compute the new role without touching the widget tree.
    final (newRole, newLastSwitch) = _computeNewRole(newDistance);
    final roleChanged = newRole != _role;

    // 4. Mutate route notifier before setState so the PolylineLayer sees the
    //    correct state on the very same frame.
    if (roleChanged) {
      _route.clear();
    } else if (_role == MotoRole.leader) {
      _route.add(newPoint);
    }

    // 5. Single setState call, guarded by mounted check.
    if (mounted) {
      setState(() {
        _simulatedDistance = newDistance;
        _role = newRole;
        _lastRoleSwitch = newLastSwitch;
      });
    }
  }

  /// Pure computation: given the new [distance], returns the role and
  /// last-switch timestamp that should apply after this tick.
  ///
  /// Does NOT touch the widget tree or call setState.
  (MotoRole, DateTime?) _computeNewRole(double distance) {
    final now = DateTime.now();
    final cooldownOk = _lastRoleSwitch == null ||
        now.difference(_lastRoleSwitch!) >= _roleSwitchCooldown;

    if (cooldownOk) {
      if (_role == MotoRole.leader && distance < _enterFollowerThreshold) {
        return (MotoRole.follower, now);
      }
      if (_role == MotoRole.follower && distance > _enterLeaderThreshold) {
        return (MotoRole.leader, now);
      }
    }

    return (_role, _lastRoleSwitch);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isLeader = _role == MotoRole.leader;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulazione Navigazione'),
        backgroundColor: isLeader ? Colors.blue : Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _basePosition,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.example.primo_progetto_flutter',
              ),
              // -------------------------------------------------------
              // Efficient polyline: only this sub-tree rebuilds when a
              // new GPS point arrives.  The outer FlutterMap widget (and
              // TileLayer) are NOT touched, preventing unnecessary tile
              // re-fetches and avoiding the memory-leak pattern of
              // rebuilding the whole map tree on every GPS tick.
              // -------------------------------------------------------
              ListenableBuilder(
                listenable: _route,
                builder: (_, __) {
                  if (_route.points.length < 2) {
                    return const SizedBox.shrink();
                  }
                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route.points,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          // Status overlay (distance, role, last switch time).
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _StatusCard(
              isLeader: isLeader,
              distance: _simulatedDistance,
              pointCount: _route.points.length,
              lastSwitch: _lastRoleSwitch,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _StatusCard – purely presentational, extracted to keep build() clean.
// ---------------------------------------------------------------------------
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isLeader,
    required this.distance,
    required this.pointCount,
    required this.lastSwitch,
  });

  final bool isLeader;
  final double distance;
  final int pointCount;
  final DateTime? lastSwitch;

  @override
  Widget build(BuildContext context) {
    final roleColor = isLeader ? Colors.blue : Colors.orange;
    final roleLabel = isLeader ? 'LEADER' : 'FOLLOWER';
    final roleIcon =
        isLeader ? Icons.star_rounded : Icons.follow_the_signs_rounded;

    return Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(roleIcon, color: roleColor),
                const SizedBox(width: 8),
                Text(
                  'Ruolo: $roleLabel',
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Distanza simulata: ${distance.toStringAsFixed(2)} m',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Punti percorso: $pointCount',
              style: const TextStyle(color: Colors.grey),
            ),
            if (lastSwitch != null) ...[
              const SizedBox(height: 4),
              Text(
                'Ultimo cambio ruolo: ${lastSwitch!.toIso8601String().substring(11, 19)}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
