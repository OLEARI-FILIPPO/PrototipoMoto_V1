import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/external_device_service.dart';
import 'network_view_screen.dart';

/// Schermata principale con la mappa offline e la posizione GPS
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final LocationService _locationService = LocationService();
  final MapService _mapService = MapService();
  final MapController _mapController = MapController();
  final ExternalDeviceService _externalDeviceService = ExternalDeviceService();

  LatLng? _currentPosition;
  bool _isTrackingLocation = false;
  bool _mapInitialized = false;
  String _statusMessage = 'Caricamento...';
  
  // Percorso registrato
  final List<LatLng> _routePoints = [];
  bool _isRecordingRoute = false;
  
  // Subscription separata per route recording (evita duplicati su toggle tracking)
  StreamSubscription<LatLng>? _routeSub;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }
  
  @override
  void dispose() {
    _routeSub?.cancel();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      // Inizializza il servizio mappe
      await _mapService.initialize();

      setState(() {
        _mapInitialized = true;
        _statusMessage = 'Premi il pulsante per ottenere la tua posizione';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Errore nell\'inizializzazione: $e';
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _statusMessage = 'Ottenendo posizione GPS...';
    });

    final position = await _locationService.getCurrentLocation();

    if (position != null) {
      setState(() {
        _currentPosition = position;
        _statusMessage = 'Posizione trovata!';
      });

      // Centra la mappa sulla posizione corrente
      _mapController.move(position, 13.0);
    } else {
      setState(() {
        _statusMessage =
            'Impossibile ottenere la posizione. Verifica i permessi.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile ottenere la posizione GPS. Verifica i permessi nelle impostazioni.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _startLocationTracking() {
    _locationService.getLocationStream().listen((position) {
      if (_isTrackingLocation && mounted) {
        setState(() {
          _currentPosition = position;
          _statusMessage = 'Tracciamento attivo';
        });

        // Opzionale: aggiorna la vista della mappa per seguire l'utente
        _mapController.move(position, _mapController.camera.zoom);
      }
    });
  }

  void _toggleLocationTracking() {
    setState(() {
      _isTrackingLocation = !_isTrackingLocation;
    });

    if (_isTrackingLocation) {
      _startLocationTracking();
    }
  }

  void _toggleRouteRecording() {
    setState(() => _isRecordingRoute = !_isRecordingRoute);
    if (_isRecordingRoute) {
      _routeSub = _locationService.getLocationStream().listen((p) {
        if (!_isRecordingRoute) return;
        setState(() {
          _routePoints.add(p);
        });
      });
    } else {
      _routeSub?.cancel();
      _routeSub = null;
    }
  }

  Future<void> _openNetworkView() async {
    // Verifica permessi prima
    if (!await _ensureBluetoothPrerequisites()) {
      return;
    }
    
    if (!mounted) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NetworkViewScreen(),
      ),
    );
  }

  Future<bool> _ensureBluetoothPrerequisites() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return true;
    }

    final permissions = <Permission>[];
    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    } else if (Platform.isIOS) {
      permissions.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    if (permissions.isNotEmpty) {
      final results = await permissions.request();
      final granted = results.values.every((status) => status.isGranted || status.isLimited);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permessi Bluetooth/posizione richiesti')),
          );
        }
        return false;
      }
    }

    final bluetoothOn = await FlutterBluePlus.isOn;
    if (!bluetoothOn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attiva il Bluetooth sul dispositivo')),
        );
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappa Offline'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isRecordingRoute ? Icons.route : Icons.alt_route),
            tooltip: _isRecordingRoute ? 'Stop percorso' : 'Registra percorso',
            onPressed: _toggleRouteRecording,
          ),
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: 'Rete Dispositivi (Mesh)',
            onPressed: _openNetworkView,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Informazioni',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Informazioni Mappa'),
                  content: const Text(
                    'Questa mappa usa le tile scaricate offline.\n\n'
                    'Premi il pulsante GPS per ottenere la tua posizione.\n\n'
                    'Il punto blu mostra dove ti trovi.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mappa
          if (_mapInitialized)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(
                  41.9028,
                  12.4964,
                ), // Roma - centro Italia
                initialZoom: 6.0,
                minZoom: 3.0,
                maxZoom: 18.0,
              ),
              children: [
                // Layer delle tile della mappa
                _mapService.getTileLayer(),
                // Polyline del percorso registrato
                if (_routePoints.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4,
                        color: Colors.redAccent,
                      ),
                    ],
                  ),

                // Marker per la posizione corrente
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
                        width: 80,
                        height: 80,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue),
                              ),
                              child: const Text(
                                'Tu sei qui',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Pannello di debug con coordinate GPS in alto a sinistra
          if (_currentPosition != null)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isTrackingLocation
                              ? Icons.gps_fixed
                              : Icons.gps_not_fixed,
                          color: _isTrackingLocation
                              ? Colors.green
                              : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'DEBUG GPS',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(
                      color: Colors.green,
                      thickness: 1,
                      height: 1,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LAT:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _currentPosition!.latitude.toStringAsFixed(6),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.orange,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LON:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _currentPosition!.longitude.toStringAsFixed(6),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Pulsante per ottenere posizione corrente
          FloatingActionButton(
            heroTag: 'location',
            onPressed: _getCurrentLocation,
            tooltip: 'Ottieni posizione',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 16),

          // Pulsante per attivare/disattivare tracciamento
          FloatingActionButton(
            heroTag: 'tracking',
            onPressed: _toggleLocationTracking,
            tooltip: _isTrackingLocation
                ? 'Disattiva tracciamento'
                : 'Attiva tracciamento',
            backgroundColor: _isTrackingLocation ? Colors.green : null,
            child: Icon(
              _isTrackingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
            ),
          ),
          const SizedBox(height: 16),

          // Pulsante zoom +
          FloatingActionButton(
            heroTag: 'zoom_in',
            mini: true,
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom + 1,
              );
            },
            tooltip: 'Zoom in',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),

          // Pulsante zoom -
          FloatingActionButton(
            heroTag: 'zoom_out',
            mini: true,
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom - 1,
              );
            },
            tooltip: 'Zoom out',
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}
