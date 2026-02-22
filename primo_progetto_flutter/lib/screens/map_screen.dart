import 'dart:async';import 'dart:async';import 'dart:async';import 'dart:async';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';import 'package:flutter/foundation.dart';import 'dart:io' show Platform;import 'dart:io' show Platform;

import 'package:latlong2/latlong.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_map/flutter_map.dart';import 'package:flutter/foundation.dart';import 'package:flutter/material.dart';

import '../services/location_service.dart';

import '../services/map_service.dart';import 'package:latlong2/latlong.dart';

import '../services/external_device_service.dart';

import 'network_view_screen.dart';import 'package:flutter_blue_plus/flutter_blue_plus.dart';import 'package:flutter/material.dart';import 'package:flutter_map/flutter_map.dart';



/// Schermata principale con la mappa offline e la posizione GPSimport 'package:permission_handler/permission_handler.dart';

class MapScreen extends StatefulWidget {

  const MapScreen({super.key});import 'package:flutter_map/flutter_map.dart';import 'package:latlong2/latlong.dart';



  @overrideimport '../services/location_service.dart';

  State<MapScreen> createState() => _MapScreenState();

}import '../services/map_service.dart';import 'package:latlong2/latlong.dart';import '../services/location_service.dart';



class _MapScreenState extends State<MapScreen> {import '../services/external_device_service.dart';

  final LocationService _locationService = LocationService();

  final MapService _mapService = MapService();import 'network_view_screen.dart';import 'package:flutter_blue_plus/flutter_blue_plus.dart';import '../services/map_service.dart';

  final MapController _mapController = MapController();

  final ExternalDeviceService _externalDeviceService = ExternalDeviceService();



  LatLng? _currentPosition;/// Schermata principale con la mappa offline e la posizione GPSimport 'package:permission_handler/permission_handler.dart';import '../services/external_device_service.dart';

  bool _isTrackingLocation = false;

  bool _mapInitialized = false;class MapScreen extends StatefulWidget {

  String _statusMessage = 'Caricamento...';

    const MapScreen({super.key});import 'network_view_screen.dart';

  // Percorso registrato

  final List<LatLng> _routePoints = [];

  bool _isRecordingRoute = false;

    @overrideimport '../services/location_service.dart';import 'package:flutter/foundation.dart';

  // Subscription separata per route recording (evita duplicati su toggle tracking)

  StreamSubscription<LatLng>? _routeSub;  State<MapScreen> createState() => _MapScreenState();



  @override}import '../services/map_service.dart';import 'package:flutter_blue_plus/flutter_blue_plus.dart';

  void initState() {

    super.initState();

    _initializeServices();

  }class _MapScreenState extends State<MapScreen> {import '../services/external_device_service.dart';import 'package:permission_handler/permission_handler.dart';

  

  @override  final LocationService _locationService = LocationService();

  void dispose() {

    _routeSub?.cancel();  final MapService _mapService = MapService();import 'network_view_screen.dart';import 'package:flutter_colorpicker/flutter_colorpicker.dart';

    super.dispose();

  }  final MapController _mapController = MapController();



  Future<void> _initializeServices() async {  final ExternalDeviceService _externalDeviceService = ExternalDeviceService();

    try {

      // Inizializza il servizio mappe

      await _mapService.initialize();

  LatLng? _currentPosition;/// Schermata principale con la mappa offline e la posizione GPS/// Schermata principale con la mappa offline e la posizione GPS

      setState(() {

        _mapInitialized = true;  bool _isTrackingLocation = false;

        _statusMessage = 'Premi il pulsante per ottenere la tua posizione';

      });  bool _mapInitialized = false;class MapScreen extends StatefulWidget {class MapScreen extends StatefulWidget {

    } catch (e) {

      setState(() {  String _statusMessage = 'Caricamento...';

        _statusMessage = 'Errore nell\'inizializzazione: $e';

      });    const MapScreen({super.key});  const MapScreen({super.key});

    }

  }  // Percorso registrato



  Future<void> _getCurrentLocation() async {  final List<LatLng> _routePoints = [];

    setState(() {

      _statusMessage = 'Ottenendo posizione GPS...';  bool _isRecordingRoute = false;

    });

    @override  @override

    final position = await _locationService.getCurrentLocation();

  // Subscription separata per route recording (evita duplicati su toggle tracking)

    if (position != null) {

      setState(() {  StreamSubscription<LatLng>? _routeSub;  State<MapScreen> createState() => _MapScreenState();  State<MapScreen> createState() => _MapScreenState();

        _currentPosition = position;

        _statusMessage = 'Posizione trovata!';

      });

  @override}}

      // Centra la mappa sulla posizione corrente

      _mapController.move(position, 13.0);  void initState() {

    } else {

      setState(() {    super.initState();

        _statusMessage =

            'Impossibile ottenere la posizione. Verifica i permessi.';    _initializeServices();

      });

  }class _MapScreenState extends State<MapScreen> {class _DeviceManagerSheet extends StatefulWidget {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(  

          const SnackBar(

            content: Text(  @override  final LocationService _locationService = LocationService();  const _DeviceManagerSheet({

              'Impossibile ottenere la posizione GPS. Verifica i permessi nelle impostazioni.',

            ),  void dispose() {

            backgroundColor: Colors.orange,

            duration: Duration(seconds: 5),    _routeSub?.cancel();  final MapService _mapService = MapService();    required this.service,

          ),

        );    super.dispose();

      }

    }  }  final MapController _mapController = MapController();    required this.initialConnections,

  }



  void _startLocationTracking() {

    _locationService.getLocationStream().listen((position) {  Future<void> _initializeServices() async {  final ExternalDeviceService _externalDeviceService = ExternalDeviceService();    required this.initialBridgingEnabled,

      if (_isTrackingLocation && mounted) {

        setState(() {    try {

          _currentPosition = position;

          _statusMessage = 'Tracciamento attivo';      // Inizializza il servizio mappe  });

        });

      await _mapService.initialize();

        // Opzionale: aggiorna la vista della mappa per seguire l'utente

        _mapController.move(position, _mapController.camera.zoom);  LatLng? _currentPosition;

      }

    });      setState(() {

  }

        _mapInitialized = true;  bool _isTrackingLocation = false;  final ExternalDeviceService service;

  void _toggleLocationTracking() {

    setState(() {        _statusMessage = 'Premi il pulsante per ottenere la tua posizione';

      _isTrackingLocation = !_isTrackingLocation;

    });      });  bool _mapInitialized = false;  final Map<DeviceSlot, DeviceConnectionInfo> initialConnections;



    if (_isTrackingLocation) {    } catch (e) {

      _startLocationTracking();

    }      setState(() {  String _statusMessage = 'Caricamento...';  final bool initialBridgingEnabled;

  }

        _statusMessage = 'Errore nell\'inizializzazione: $e';

  void _toggleRouteRecording() {

    setState(() => _isRecordingRoute = !_isRecordingRoute);      });  

    if (_isRecordingRoute) {

      _routeSub = _locationService.getLocationStream().listen((p) {    }

        if (!_isRecordingRoute) return;

        setState(() {  }  // Percorso registrato  @override

          _routePoints.add(p);

        });

      });

    } else {  Future<void> _getCurrentLocation() async {  final List<LatLng> _routePoints = [];  State<_DeviceManagerSheet> createState() => _DeviceManagerSheetState();

      _routeSub?.cancel();

      _routeSub = null;    setState(() {

    }

  }      _statusMessage = 'Ottenendo posizione GPS...';  bool _isRecordingRoute = false;}



  Future<void> _openNetworkView() async {    });

    // Verifica permessi prima

    if (!await _ensureBluetoothPrerequisites()) {  

      return;

    }    final position = await _locationService.getCurrentLocation();

    

    if (!mounted) return;  // Subscription separata per route recording (evita duplicati su toggle tracking)class _DeviceManagerSheetState extends State<_DeviceManagerSheet> {

    

    await Navigator.push(    if (position != null) {

      context,

      MaterialPageRoute(      setState(() {  StreamSubscription<LatLng>? _routeSub;  List<ScanResult> _scanResults = const [];

        builder: (context) => const NetworkViewScreen(),

      ),        _currentPosition = position;

    );

  }        _statusMessage = 'Posizione trovata!';  late Map<DeviceSlot, DeviceConnectionInfo> _connections;



  Future<bool> _ensureBluetoothPrerequisites() async {      });

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {

      return true;  @override  late bool _bridgingEnabled;

    }

      // Centra la mappa sulla posizione corrente

    final permissions = <Permission>[];

    if (Platform.isAndroid) {      _mapController.move(position, 13.0);  void initState() {  DeviceSlot? _connectingSlot;

      permissions.addAll([

        Permission.bluetoothScan,    } else {

        Permission.bluetoothConnect,

        Permission.bluetooth,      setState(() {    super.initState();  bool _isScanning = true;

        Permission.locationWhenInUse,

      ]);        _statusMessage =

    } else if (Platform.isIOS) {

      permissions.addAll([            'Impossibile ottenere la posizione. Verifica i permessi.';    _initializeServices();  final Map<DeviceSlot, bool> _ledOn = {

        Permission.bluetooth,

        Permission.locationWhenInUse,      });

      ]);

    }  }    DeviceSlot.deviceA: false,



    if (permissions.isNotEmpty) {      if (mounted) {

      final results = await permissions.request();

      final granted = results.values.every((status) => status.isGranted || status.isLimited);        ScaffoldMessenger.of(context).showSnackBar(      DeviceSlot.deviceB: false,

      if (!granted) {

        if (mounted) {          const SnackBar(

          ScaffoldMessenger.of(context).showSnackBar(

            const SnackBar(content: Text('Permessi Bluetooth/posizione richiesti')),            content: Text(  @override  };

          );

        }              'Impossibile ottenere la posizione GPS. Verifica i permessi nelle impostazioni.',

        return false;

      }            ),  void dispose() {  final Map<DeviceSlot, bool> _sendingLed = {

    }

            backgroundColor: Colors.orange,

    final bluetoothOn = await FlutterBluePlus.isOn;

    if (!bluetoothOn) {            duration: Duration(seconds: 5),    _routeSub?.cancel();    DeviceSlot.deviceA: false,

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(          ),

          const SnackBar(content: Text('Attiva il Bluetooth sul dispositivo')),

        );        );    super.dispose();    DeviceSlot.deviceB: false,

      }

      return false;      }

    }

    return true;    }  }  };

  }

  }

  @override

  Widget build(BuildContext context) {  final Map<DeviceSlot, bool> _sendingColor = {

    return Scaffold(

      appBar: AppBar(  void _startLocationTracking() {

        title: const Text('Mappa Offline'),

        backgroundColor: Theme.of(context).colorScheme.inversePrimary,    _locationService.getLocationStream().listen((position) {  Future<void> _initializeServices() async {    DeviceSlot.deviceA: false,

        actions: [

          IconButton(      if (_isTrackingLocation && mounted) {

            icon: Icon(_isRecordingRoute ? Icons.route : Icons.alt_route),

            tooltip: _isRecordingRoute ? 'Stop percorso' : 'Registra percorso',        setState(() {    try {    DeviceSlot.deviceB: false,

            onPressed: _toggleRouteRecording,

          ),          _currentPosition = position;

          IconButton(

            icon: const Icon(Icons.hub),          _statusMessage = 'Tracciamento attivo';      // Inizializza il servizio mappe  };

            tooltip: 'Rete Dispositivi (Mesh)',

            onPressed: _openNetworkView,        });

          ),

          IconButton(      await _mapService.initialize();  final Map<DeviceSlot, bool> _sendingPeerColor = {

            icon: const Icon(Icons.info_outline),

            tooltip: 'Informazioni',        // Opzionale: aggiorna la vista della mappa per seguire l'utente

            onPressed: () {

              showDialog(        _mapController.move(position, _mapController.camera.zoom);    DeviceSlot.deviceA: false,

                context: context,

                builder: (context) => AlertDialog(      }

                  title: const Text('Informazioni Mappa'),

                  content: const Text(    });      setState(() {    DeviceSlot.deviceB: false,

                    'Questa mappa usa le tile scaricate offline.\n\n'

                    'Premi il pulsante GPS per ottenere la tua posizione.\n\n'  }

                    'Il punto blu mostra dove ti trovi.',

                  ),        _mapInitialized = true;  };

                  actions: [

                    TextButton(  void _toggleLocationTracking() {

                      onPressed: () => Navigator.pop(context),

                      child: const Text('OK'),    setState(() {        _statusMessage = 'Premi il pulsante per ottenere la tua posizione';  final Map<DeviceSlot, bool> _scanningPeer = {

                    ),

                  ],      _isTrackingLocation = !_isTrackingLocation;

                ),

              );    });      });    DeviceSlot.deviceA: false,

            },

          ),

        ],

      ),    if (_isTrackingLocation) {    } catch (e) {    DeviceSlot.deviceB: false,

      body: Stack(

        children: [      _startLocationTracking();

          // Mappa

          if (_mapInitialized)    }      setState(() {  };

            FlutterMap(

              mapController: _mapController,  }

              options: MapOptions(

                initialCenter: const LatLng(        _statusMessage = 'Errore nell\'inizializzazione: $e';  final Map<DeviceSlot, bool> _peerScanActive = {

                  41.9028,

                  12.4964,  void _toggleRouteRecording() {

                ), // Roma - centro Italia

                initialZoom: 6.0,    setState(() => _isRecordingRoute = !_isRecordingRoute);      });    DeviceSlot.deviceA: false,

                minZoom: 3.0,

                maxZoom: 18.0,    if (_isRecordingRoute) {

              ),

              children: [      _routeSub = _locationService.getLocationStream().listen((p) {    }    DeviceSlot.deviceB: false,

                // Layer delle tile della mappa

                _mapService.getTileLayer(),        if (!_isRecordingRoute) return;

                // Polyline del percorso registrato

                if (_routePoints.length > 1)        setState(() {  }  };

                  PolylineLayer(

                    polylines: [          _routePoints.add(p);

                      Polyline(

                        points: _routePoints,        });  final Map<DeviceSlot, bool> _autoScanEnabled = {

                        strokeWidth: 4,

                        color: Colors.redAccent,      });

                      ),

                    ],    } else {  Future<void> _getCurrentLocation() async {    DeviceSlot.deviceA: true, // Default is enabled

                  ),

      _routeSub?.cancel();

                // Marker per la posizione corrente

                if (_currentPosition != null)      _routeSub = null;    setState(() {    DeviceSlot.deviceB: true,

                  MarkerLayer(

                    markers: [    }

                      Marker(

                        point: _currentPosition!,  }      _statusMessage = 'Ottenendo posizione GPS...';  };

                        width: 80,

                        height: 80,

                        alignment: Alignment.center,

                        child: Column(  Future<void> _openNetworkView() async {    });  final Map<DeviceSlot, Color> _selectedColor = {

                          mainAxisSize: MainAxisSize.min,

                          children: [    // Verifica permessi prima

                            Container(

                              padding: const EdgeInsets.all(8),    if (!await _ensureBluetoothPrerequisites()) {    DeviceSlot.deviceA: Colors.blueAccent,

                              decoration: BoxDecoration(

                                color: Colors.blue,      return;

                                shape: BoxShape.circle,

                                border: Border.all(    }    final position = await _locationService.getCurrentLocation();    DeviceSlot.deviceB: Colors.pinkAccent,

                                  color: Colors.white,

                                  width: 3,    

                                ),

                                boxShadow: [    if (!mounted) return;  };

                                  BoxShadow(

                                    color: Colors.blue.withOpacity(0.5),    

                                    blurRadius: 10,

                                    spreadRadius: 5,    await Navigator.push(    if (position != null) {  final Map<DeviceSlot, List<RemotePeer>> _peers = {

                                  ),

                                ],      context,

                              ),

                              child: const Icon(      MaterialPageRoute(      setState(() {    DeviceSlot.deviceA: const [],

                                Icons.person,

                                color: Colors.white,        builder: (context) => const NetworkViewScreen(),

                                size: 24,

                              ),      ),        _currentPosition = position;    DeviceSlot.deviceB: const [],

                            ),

                            const SizedBox(height: 4),    );

                            Container(

                              padding: const EdgeInsets.symmetric(  }        _statusMessage = 'Posizione trovata!';  };

                                horizontal: 8,

                                vertical: 4,

                              ),

                              decoration: BoxDecoration(  Future<bool> _ensureBluetoothPrerequisites() async {      });  final Map<DeviceSlot, DeviceTelemetryMessage?> _lastTelemetry = {

                                color: Colors.white,

                                borderRadius: BorderRadius.circular(12),    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {

                                border: Border.all(color: Colors.blue),

                              ),      return true;    DeviceSlot.deviceA: null,

                              child: const Text(

                                'Tu sei qui',    }

                                style: TextStyle(

                                  fontSize: 10,      // Centra la mappa sulla posizione corrente    DeviceSlot.deviceB: null,

                                  fontWeight: FontWeight.bold,

                                  color: Colors.blue,    final permissions = <Permission>[];

                                ),

                              ),    if (Platform.isAndroid) {      _mapController.move(position, 13.0);  };

                            ),

                          ],      permissions.addAll([

                        ),

                      ),        Permission.bluetoothScan,    } else {

                    ],

                  ),        Permission.bluetoothConnect,

              ],

            )        Permission.bluetooth,      setState(() {  StreamSubscription<List<ScanResult>>? _scanSub;

          else

            const Center(child: CircularProgressIndicator()),        Permission.locationWhenInUse,



          // Pannello di debug con coordinate GPS in alto a sinistra      ]);        _statusMessage =  StreamSubscription<Map<DeviceSlot, DeviceConnectionInfo>>? _connectionSub;

          if (_currentPosition != null)

            Positioned(    } else if (Platform.isIOS) {

              top: 16,

              left: 16,      permissions.addAll([            'Impossibile ottenere la posizione. Verifica i permessi.';  StreamSubscription<bool>? _bridgingSub;

              child: Container(

                padding: const EdgeInsets.all(12),        Permission.bluetooth,

                decoration: BoxDecoration(

                  color: Colors.black.withOpacity(0.85),        Permission.locationWhenInUse,      });  StreamSubscription<DeviceTelemetryMessage>? _telemetrySub;

                  borderRadius: BorderRadius.circular(8),

                  border: Border.all(      ]);

                    color: Colors.green.withOpacity(0.5),

                    width: 2,    }  StreamSubscription<Map<DeviceSlot, List<RemotePeer>>>? _peersSub;

                  ),

                  boxShadow: [

                    BoxShadow(

                      color: Colors.black.withOpacity(0.3),    if (permissions.isNotEmpty) {      if (mounted) {

                      blurRadius: 8,

                      offset: const Offset(0, 2),      final results = await permissions.request();

                    ),

                  ],      final granted = results.values.every((status) => status.isGranted || status.isLimited);        ScaffoldMessenger.of(context).showSnackBar(  @override

                ),

                child: Column(      if (!granted) {

                  crossAxisAlignment: CrossAxisAlignment.start,

                  mainAxisSize: MainAxisSize.min,        if (mounted) {          const SnackBar(  void initState() {

                  children: [

                    Row(          ScaffoldMessenger.of(context).showSnackBar(

                      mainAxisSize: MainAxisSize.min,

                      children: [            const SnackBar(content: Text('Permessi Bluetooth/posizione richiesti')),            content: Text(    super.initState();

                        Icon(

                          _isTrackingLocation          );

                              ? Icons.gps_fixed

                              : Icons.gps_not_fixed,        }              'Impossibile ottenere la posizione GPS. Verifica i permessi nelle impostazioni.',    _connections = Map<DeviceSlot, DeviceConnectionInfo>.from(widget.initialConnections);

                          color: _isTrackingLocation

                              ? Colors.green        return false;

                              : Colors.orange,

                          size: 16,      }            ),    _bridgingEnabled = widget.initialBridgingEnabled;

                        ),

                        const SizedBox(width: 8),    }

                        const Text(

                          'DEBUG GPS',            backgroundColor: Colors.orange,    _isScanning = FlutterBluePlus.isScanningNow;

                          style: TextStyle(

                            color: Colors.green,    // Check if bluetooth is on

                            fontSize: 12,

                            fontWeight: FontWeight.bold,    final bluetoothOn = await FlutterBluePlus.isOn;            duration: Duration(seconds: 5),    _scanSub = widget.service.scanResultsStream.listen((results) {

                          ),

                        ),    if (!bluetoothOn) {

                      ],

                    ),      if (mounted) {          ),      if (!mounted) return;

                    const SizedBox(height: 8),

                    const Divider(        ScaffoldMessenger.of(context).showSnackBar(

                      color: Colors.green,

                      thickness: 1,          const SnackBar(content: Text('Attiva il Bluetooth sul dispositivo')),        );      setState(() {

                      height: 1,

                    ),        );

                    const SizedBox(height: 8),

                    Row(      }      }        _scanResults = results;

                      mainAxisSize: MainAxisSize.min,

                      children: [      return false;

                        const Icon(

                          Icons.location_on,    }    }        _isScanning = FlutterBluePlus.isScanningNow;

                          color: Colors.blue,

                          size: 14,    return true;

                        ),

                        const SizedBox(width: 6),  }  }      });

                        const Text(

                          'LAT:',

                          style: TextStyle(

                            color: Colors.white70,  @override    });

                            fontSize: 11,

                            fontWeight: FontWeight.bold,  Widget build(BuildContext context) {

                          ),

                        ),    return Scaffold(  void _startLocationTracking() {    _connectionSub = widget.service.connectionStream.listen((snapshot) {

                        const SizedBox(width: 4),

                        Text(      appBar: AppBar(

                          _currentPosition!.latitude.toStringAsFixed(6),

                          style: const TextStyle(        title: const Text('Mappa Offline'),    _locationService.getLocationStream().listen((position) {      if (!mounted) return;

                            color: Colors.white,

                            fontSize: 13,        backgroundColor: Theme.of(context).colorScheme.inversePrimary,

                            fontFamily: 'monospace',

                          ),        actions: [      if (_isTrackingLocation && mounted) {      setState(() {

                        ),

                      ],          IconButton(

                    ),

                    const SizedBox(height: 4),            icon: Icon(_isRecordingRoute ? Icons.route : Icons.alt_route),        setState(() {        _connections = snapshot;

                    Row(

                      mainAxisSize: MainAxisSize.min,            tooltip: _isRecordingRoute ? 'Stop percorso' : 'Registra percorso',

                      children: [

                        const Icon(            onPressed: _toggleRouteRecording,          _currentPosition = position;      });

                          Icons.location_on,

                          color: Colors.orange,          ),

                          size: 14,

                        ),          IconButton(          _statusMessage = 'Tracciamento attivo';    });

                        const SizedBox(width: 6),

                        const Text(            icon: const Icon(Icons.hub),

                          'LON:',

                          style: TextStyle(            tooltip: 'Rete Dispositivi (Mesh)',        });    _bridgingSub = widget.service.bridgingStream.listen((enabled) {

                            color: Colors.white70,

                            fontSize: 11,            onPressed: _openNetworkView,

                            fontWeight: FontWeight.bold,

                          ),          ),      if (!mounted) return;

                        ),

                        const SizedBox(width: 4),          IconButton(

                        Text(

                          _currentPosition!.longitude.toStringAsFixed(6),            icon: const Icon(Icons.info_outline),        // Opzionale: aggiorna la vista della mappa per seguire l'utente      setState(() => _bridgingEnabled = enabled);

                          style: const TextStyle(

                            color: Colors.white,            tooltip: 'Informazioni',

                            fontSize: 13,

                            fontFamily: 'monospace',            onPressed: () {        _mapController.move(position, _mapController.camera.zoom);    });

                          ),

                        ),              showDialog(

                      ],

                    ),                context: context,      }    _telemetrySub = widget.service.telemetryStream.listen((message) {

                  ],

                ),                builder: (context) => AlertDialog(

              ),

            ),                  title: const Text('Informazioni Mappa'),    });      if (!mounted) return;

        ],

      ),                  content: const Text(

      floatingActionButton: Column(

        mainAxisAlignment: MainAxisAlignment.end,                    'Questa mappa usa le tile scaricate offline.\n\n'  }      setState(() {

        children: [

          // Pulsante per ottenere posizione corrente                    'Premi il pulsante GPS per ottenere la tua posizione.\n\n'

          FloatingActionButton(

            heroTag: 'location',                    'Il punto blu mostra dove ti trovi.',        _lastTelemetry[message.slot] = message;

            onPressed: _getCurrentLocation,

            tooltip: 'Ottieni posizione',                  ),

            child: const Icon(Icons.my_location),

          ),                  actions: [  void _toggleLocationTracking() {      });

          const SizedBox(height: 16),

                    TextButton(

          // Pulsante per attivare/disattivare tracciamento

          FloatingActionButton(                      onPressed: () => Navigator.pop(context),    setState(() {    });

            heroTag: 'tracking',

            onPressed: _toggleLocationTracking,                      child: const Text('OK'),

            tooltip: _isTrackingLocation

                ? 'Disattiva tracciamento'                    ),      _isTrackingLocation = !_isTrackingLocation;    _peersSub = widget.service.peersStream.listen((snapshot) {

                : 'Attiva tracciamento',

            backgroundColor: _isTrackingLocation ? Colors.green : null,                  ],

            child: Icon(

              _isTrackingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,                ),    });      if (!mounted) return;

            ),

          ),              );

          const SizedBox(height: 16),

            },      setState(() {

          // Pulsante zoom +

          FloatingActionButton(          ),

            heroTag: 'zoom_in',

            mini: true,        ],    if (_isTrackingLocation) {        _peers[DeviceSlot.deviceA] = snapshot[DeviceSlot.deviceA] ?? const [];

            onPressed: () {

              final currentZoom = _mapController.camera.zoom;      ),

              _mapController.move(

                _mapController.camera.center,      body: Stack(      _startLocationTracking();        _peers[DeviceSlot.deviceB] = snapshot[DeviceSlot.deviceB] ?? const [];

                currentZoom + 1,

              );        children: [

            },

            tooltip: 'Zoom in',          // Mappa    }      });

            child: const Icon(Icons.add),

          ),          if (_mapInitialized)

          const SizedBox(height: 8),

            FlutterMap(  }    });

          // Pulsante zoom -

          FloatingActionButton(              mapController: _mapController,

            heroTag: 'zoom_out',

            mini: true,              options: MapOptions(  }

            onPressed: () {

              final currentZoom = _mapController.camera.zoom;                initialCenter: const LatLng(

              _mapController.move(

                _mapController.camera.center,                  41.9028,  void _toggleRouteRecording() {

                currentZoom - 1,

              );                  12.4964,

            },

            tooltip: 'Zoom out',                ), // Roma - centro Italia    setState(() => _isRecordingRoute = !_isRecordingRoute);  @override

            child: const Icon(Icons.remove),

          ),                initialZoom: 6.0,

        ],

      ),                minZoom: 3.0,    if (_isRecordingRoute) {  void dispose() {

    );

  }                maxZoom: 18.0,

}

              ),      _routeSub = _locationService.getLocationStream().listen((p) {    _scanSub?.cancel();

              children: [

                // Layer delle tile della mappa        if (!_isRecordingRoute) return;    _connectionSub?.cancel();

                _mapService.getTileLayer(),

                // Polyline del percorso registrato        setState(() {    _bridgingSub?.cancel();

                if (_routePoints.length > 1)

                  PolylineLayer(          _routePoints.add(p);    _telemetrySub?.cancel();

                    polylines: [

                      Polyline(        });    _peersSub?.cancel();

                        points: _routePoints,

                        strokeWidth: 4,      });    super.dispose();

                        color: Colors.redAccent,

                      ),    } else {  }

                    ],

                  ),      _routeSub?.cancel();



                // Marker per la posizione corrente      _routeSub = null;  bool _isCompatibleDevice(ScanResult result) {

                if (_currentPosition != null)

                  MarkerLayer(    }    final adv = result.advertisementData;

                    markers: [

                      Marker(  }    final name = _formatScanResultName(result).toLowerCase();

                        point: _currentPosition!,

                        width: 80,    final hasService = adv.serviceUuids.contains(widget.service.serviceUuid) ||

                        height: 80,

                        alignment: Alignment.center,  Future<void> _openNetworkView() async {        adv.serviceUuids.contains(widget.service.espLedServiceUuid);

                        child: Column(

                          mainAxisSize: MainAxisSize.min,    // Verifica permessi prima    final likelyName = name.contains('esp32') || name.contains('uwb') || name.contains('moto');

                          children: [

                            Container(    if (!await _ensureBluetoothPrerequisites()) {    return hasService || likelyName;

                              padding: const EdgeInsets.all(8),

                              decoration: BoxDecoration(      return;  }

                                color: Colors.blue,

                                shape: BoxShape.circle,    }

                                border: Border.all(

                                  color: Colors.white,      @override

                                  width: 3,

                                ),    if (!mounted) return;  Widget build(BuildContext context) {

                                boxShadow: [

                                  BoxShadow(        final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

                                    color: Colors.blue.withOpacity(0.5),

                                    blurRadius: 10,    await Navigator.push(

                                    spreadRadius: 5,

                                  ),      context,    return SafeArea(

                                ],

                              ),      MaterialPageRoute(      child: Padding(

                              child: const Icon(

                                Icons.person,        builder: (context) => const NetworkViewScreen(),        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding > 0 ? bottomPadding + 16 : 24),

                                color: Colors.white,

                                size: 24,      ),        child: Column(

                              ),

                            ),    );          crossAxisAlignment: CrossAxisAlignment.start,

                            const SizedBox(height: 4),

                            Container(  }          children: [

                              padding: const EdgeInsets.symmetric(

                                horizontal: 8,            Row(

                                vertical: 4,

                              ),  Future<bool> _ensureBluetoothPrerequisites() async {              children: [

                              decoration: BoxDecoration(

                                color: Colors.white,    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {                const Icon(Icons.settings_input_antenna),

                                borderRadius: BorderRadius.circular(12),

                                border: Border.all(color: Colors.blue),      return true;                const SizedBox(width: 8),

                              ),

                              child: const Text(    }                const Expanded(

                                'Tu sei qui',

                                style: TextStyle(                  child: Text(

                                  fontSize: 10,

                                  fontWeight: FontWeight.bold,    final permissions = <Permission>[];                    'Gestione dispositivi UWB',

                                  color: Colors.blue,

                                ),    if (Platform.isAndroid) {                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),

                              ),

                            ),      permissions.addAll([                  ),

                          ],

                        ),        Permission.bluetoothScan,                ),

                      ),

                    ],        Permission.bluetoothConnect,                IconButton(

                  ),

              ],        Permission.bluetooth,                  onPressed: () => Navigator.of(context).pop(),

            )

          else        Permission.locationWhenInUse,                  icon: const Icon(Icons.close),

            const Center(child: CircularProgressIndicator()),

      ]);                ),

          // Pannello di debug con coordinate GPS in alto a sinistra

          if (_currentPosition != null)    } else if (Platform.isIOS) {              ],

            Positioned(

              top: 16,      permissions.addAll([            ),

              left: 16,

              child: Container(        Permission.bluetooth,            const SizedBox(height: 16),

                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(        Permission.locationWhenInUse,            _buildConnectedCard(DeviceSlot.deviceA),

                  color: Colors.black.withOpacity(0.85),

                  borderRadius: BorderRadius.circular(8),      ]);            const SizedBox(height: 12),

                  border: Border.all(

                    color: Colors.green.withOpacity(0.5),    }            // Bottone per cercare dispositivi - solo se connesso

                    width: 2,

                  ),            if (_connections[DeviceSlot.deviceA]?.device != null &&

                  boxShadow: [

                    BoxShadow(    if (permissions.isNotEmpty) {                _connections[DeviceSlot.deviceA]!.telemetryReady)

                      color: Colors.black.withOpacity(0.3),

                      blurRadius: 8,      final results = await permissions.request();              _buildSearchDevicesButton(),

                      offset: const Offset(0, 2),

                    ),      final granted = results.values.every((status) => status.isGranted || status.isLimited);            const SizedBox(height: 12),

                  ],

                ),      if (!granted) {            // Sezione dispositivi rilevati (peers) - solo se connesso

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,        if (mounted) {            if (_connections[DeviceSlot.deviceA]?.device != null &&

                  mainAxisSize: MainAxisSize.min,

                  children: [          ScaffoldMessenger.of(context).showSnackBar(                _connections[DeviceSlot.deviceA]!.telemetryReady)

                    Row(

                      mainAxisSize: MainAxisSize.min,            const SnackBar(content: Text('Permessi Bluetooth/posizione richiesti')),              _buildDetectedDevicesSection(),

                      children: [

                        Icon(          );            // Sezione dispositivi disponibili - solo se NON connesso

                          _isTrackingLocation

                              ? Icons.gps_fixed        }            if (_connections[DeviceSlot.deviceA]?.device == null) ...[

                              : Icons.gps_not_fixed,

                          color: _isTrackingLocation        return false;              const SizedBox(height: 20),

                              ? Colors.green

                              : Colors.orange,      }              Row(

                          size: 16,

                        ),    }                children: [

                        const SizedBox(width: 8),

                        const Text(                  const Expanded(

                          'DEBUG GPS',

                          style: TextStyle(    // Check if bluetooth is on                    child: Text(

                            color: Colors.green,

                            fontSize: 12,    final bluetoothOn = await FlutterBluePlus.isOn;                      'Dispositivi disponibili',

                            fontWeight: FontWeight.bold,

                          ),    if (!bluetoothOn) {                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

                        ),

                      ],      if (mounted) {                    ),

                    ),

                    const SizedBox(height: 8),        ScaffoldMessenger.of(context).showSnackBar(                  ),

                    const Divider(

                      color: Colors.green,          const SnackBar(content: Text('Attiva il Bluetooth sul dispositivo')),                  if (_isScanning)

                      thickness: 1,

                      height: 1,        );                    const Padding(

                    ),

                    const SizedBox(height: 8),      }                      padding: EdgeInsets.only(right: 8.0),

                    Row(

                      mainAxisSize: MainAxisSize.min,      return false;                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),

                      children: [

                        const Icon(    }                    ),

                          Icons.location_on,

                          color: Colors.blue,    return true;                  IconButton(

                          size: 14,

                        ),  }                    tooltip: 'Aggiorna scansione',

                        const SizedBox(width: 6),

                        const Text(                    onPressed: _refreshScan,

                          'LAT:',

                          style: TextStyle(  @override                    icon: const Icon(Icons.refresh),

                            color: Colors.white70,

                            fontSize: 11,  Widget build(BuildContext context) {                  ),

                            fontWeight: FontWeight.bold,

                          ),    return Scaffold(                ],

                        ),

                        const SizedBox(width: 4),      appBar: AppBar(              ),

                        Text(

                          _currentPosition!.latitude.toStringAsFixed(6),        title: const Text('Mappa Offline'),              const SizedBox(height: 8),

                          style: const TextStyle(

                            color: Colors.white,        backgroundColor: Theme.of(context).colorScheme.inversePrimary,              Expanded(

                            fontSize: 13,

                            fontFamily: 'monospace',        actions: [                child: _scanResults.isEmpty

                          ),

                        ),          IconButton(                    ? Center(

                      ],

                    ),            icon: Icon(_isRecordingRoute ? Icons.route : Icons.alt_route),                        child: Text(

                    const SizedBox(height: 4),

                    Row(            tooltip: _isRecordingRoute ? 'Stop percorso' : 'Registra percorso',                          _isScanning

                      mainAxisSize: MainAxisSize.min,

                      children: [            onPressed: _toggleRouteRecording,                              ? 'Scansione in corso...'

                        const Icon(

                          Icons.location_on,          ),                              : 'Nessun dispositivo trovato. Riavvia la scansione.',

                          color: Colors.orange,

                          size: 14,          IconButton(                          textAlign: TextAlign.center,

                        ),

                        const SizedBox(width: 6),            icon: const Icon(Icons.hub),                        ),

                        const Text(

                          'LON:',            tooltip: 'Rete Dispositivi (Mesh)',                      )

                          style: TextStyle(

                            color: Colors.white70,            onPressed: _openNetworkView,                    : ListView.builder(

                            fontSize: 11,

                            fontWeight: FontWeight.bold,          ),                        itemCount: _scanResults.length,

                          ),

                        ),          IconButton(                        itemBuilder: (context, index) {

                        const SizedBox(width: 4),

                        Text(            icon: const Icon(Icons.info_outline),                          return _buildScanResultCard(_scanResults[index]);

                          _currentPosition!.longitude.toStringAsFixed(6),

                          style: const TextStyle(            tooltip: 'Informazioni',                        },

                            color: Colors.white,

                            fontSize: 13,            onPressed: () {                      ),

                            fontFamily: 'monospace',

                          ),              showDialog(              ),

                        ),

                      ],                context: context,              const SizedBox(height: 12),

                    ),

                  ],                builder: (context) => AlertDialog(            ],

                ),

              ),                  title: const Text('Informazioni Mappa'),            // Bridge telemetria - rimuoviamo per ora

            ),

        ],                  content: const Text(          ],

      ),

      floatingActionButton: Column(                    'Questa mappa usa le tile scaricate offline.\n\n'        ),

        mainAxisAlignment: MainAxisAlignment.end,

        children: [                    'Premi il pulsante GPS per ottenere la tua posizione.\n\n'      ),

          // Pulsante per ottenere posizione corrente

          FloatingActionButton(                    'Il punto blu mostra dove ti trovi.',    );

            heroTag: 'location',

            onPressed: _getCurrentLocation,                  ),  }

            tooltip: 'Ottieni posizione',

            child: const Icon(Icons.my_location),                  actions: [

          ),

          const SizedBox(height: 16),                    TextButton(  Widget _buildSearchDevicesButton() {



          // Pulsante per attivare/disattivare tracciamento                      onPressed: () => Navigator.pop(context),    final slot = DeviceSlot.deviceA;

          FloatingActionButton(

            heroTag: 'tracking',                      child: const Text('OK'),    final scanning = _scanningPeer[slot] == true;

            onPressed: _toggleLocationTracking,

            tooltip: _isTrackingLocation                    ),    

                ? 'Disattiva tracciamento'

                : 'Attiva tracciamento',                  ],    return Card(

            backgroundColor: _isTrackingLocation ? Colors.green : null,

            child: Icon(                ),      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

              _isTrackingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,

            ),              );      child: Padding(

          ),

          const SizedBox(height: 16),            },        padding: const EdgeInsets.all(12.0),



          // Pulsante zoom +          ),        child: Column(

          FloatingActionButton(

            heroTag: 'zoom_in',        ],          crossAxisAlignment: CrossAxisAlignment.stretch,

            mini: true,

            onPressed: () {      ),          children: [

              final currentZoom = _mapController.camera.zoom;

              _mapController.move(      body: Stack(            Row(

                _mapController.camera.center,

                currentZoom + 1,        children: [              children: [

              );

            },          // Mappa                const Icon(Icons.network_check, size: 20),

            tooltip: 'Zoom in',

            child: const Icon(Icons.add),          if (_mapInitialized)                const SizedBox(width: 8),

          ),

          const SizedBox(height: 8),            FlutterMap(                const Expanded(



          // Pulsante zoom -              mapController: _mapController,                  child: Text(

          FloatingActionButton(

            heroTag: 'zoom_out',              options: MapOptions(                    'Modalità Connessione Mesh',

            mini: true,

            onPressed: () {                initialCenter: const LatLng(                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),

              final currentZoom = _mapController.camera.zoom;

              _mapController.move(                  41.9028,                  ),

                _mapController.camera.center,

                currentZoom - 1,                  12.4964,                ),

              );

            },                ), // Roma - centro Italia              ],

            tooltip: 'Zoom out',

            child: const Icon(Icons.remove),                initialZoom: 6.0,            ),

          ),

        ],                minZoom: 3.0,            const SizedBox(height: 12),

      ),

    );                maxZoom: 18.0,            Row(

  }

}              ),              children: [


              children: [                Expanded(

                // Layer delle tile della mappa                  child: ElevatedButton.icon(

                _mapService.getTileLayer(),                    onPressed: scanning ? null : () => _startPairingMode(slot),

                // Polyline del percorso registrato                    icon: scanning

                if (_routePoints.length > 1)                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))

                  PolylineLayer(                        : const Icon(Icons.hub, size: 18),

                    polylines: [                    label: const Text('Pairing', style: TextStyle(fontSize: 13)),

                      Polyline(                    style: ElevatedButton.styleFrom(

                        points: _routePoints,                      padding: const EdgeInsets.symmetric(vertical: 10),

                        strokeWidth: 4,                      backgroundColor: Colors.red.shade700,

                        color: Colors.redAccent,                      foregroundColor: Colors.white,

                      ),                    ),

                    ],                  ),

                  ),                ),

                const SizedBox(width: 8),

                // Marker per la posizione corrente                Expanded(

                if (_currentPosition != null)                  child: ElevatedButton.icon(

                  MarkerLayer(                    onPressed: scanning ? null : () => _startSearchingMode(slot),

                    markers: [                    icon: scanning

                      Marker(                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))

                        point: _currentPosition!,                        : const Icon(Icons.search, size: 18),

                        width: 80,                    label: const Text('Searching', style: TextStyle(fontSize: 13)),

                        height: 80,                    style: ElevatedButton.styleFrom(

                        alignment: Alignment.center,                      padding: const EdgeInsets.symmetric(vertical: 10),

                        child: Column(                      backgroundColor: Colors.blue.shade700,

                          mainAxisSize: MainAxisSize.min,                      foregroundColor: Colors.white,

                          children: [                    ),

                            Container(                  ),

                              padding: const EdgeInsets.all(8),                ),

                              decoration: BoxDecoration(              ],

                                color: Colors.blue,            ),

                                shape: BoxShape.circle,            const SizedBox(height: 8),

                                border: Border.all(            const Text(

                                  color: Colors.white,              '• Pairing: Accetta connessioni (LED rosso lampeggiante)\n'

                                  width: 3,              '• Searching: Cerca dispositivi in Pairing (LED blu lampeggiante)\n'

                                ),              '• Timeout: 60 secondi',

                                boxShadow: [              style: TextStyle(fontSize: 10, color: Colors.black54, fontStyle: FontStyle.italic),

                                  BoxShadow(            ),

                                    color: Colors.blue.withOpacity(0.5),          ],

                                    blurRadius: 10,        ),

                                    spreadRadius: 5,      ),

                                  ),    );

                                ],  }

                              ),

                              child: const Icon(  Widget _buildConnectedCard(DeviceSlot slot) {

                                Icons.person,    final info = _connections[slot] ?? const DeviceConnectionInfo.empty();

                                color: Colors.white,    final device = info.device;

                                size: 24,    final connected = device != null;

                              ),    final telemetryReady = info.telemetryReady;

                            ),    final sendingLed = _sendingLed[slot] ?? false;

                            const SizedBox(height: 4),    final ledOn = _ledOn[slot] ?? false;

                            Container(    final sendingColor = _sendingColor[slot] ?? false;

                              padding: const EdgeInsets.symmetric(    final selectedColor = _selectedColor[slot] ?? Colors.orangeAccent;

                                horizontal: 8,

                                vertical: 4,    return Card(

                              ),      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

                              decoration: BoxDecoration(      child: Column(

                                color: Colors.white,        children: [

                                borderRadius: BorderRadius.circular(12),          Padding(

                                border: Border.all(color: Colors.blue),            padding: const EdgeInsets.all(16),

                              ),            child: Row(

                              child: const Text(              children: [

                                'Tu sei qui',                Icon(

                                style: TextStyle(                  connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,

                                  fontSize: 10,                  color: connected ? Colors.green : Colors.redAccent,

                                  fontWeight: FontWeight.bold,                ),

                                  color: Colors.blue,                const SizedBox(width: 12),

                                ),                Expanded(

                              ),                  child: Column(

                            ),                    crossAxisAlignment: CrossAxisAlignment.start,

                          ],                    children: [

                        ),                      const Text(

                      ),                        'La tua moto',

                    ],                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

                  ),                      ),

              ],                      const SizedBox(height: 4),

            )                      Text(

          else                        connected ? _formatConnectedName(device) : 'Nessun dispositivo collegato',

            const Center(child: CircularProgressIndicator()),                        style: const TextStyle(fontSize: 14),

                      ),

          // Pannello di debug con coordinate GPS in alto a sinistra                      if (connected)

          if (_currentPosition != null)                        Text(

            Positioned(                          telemetryReady ? 'Connesso' : 'Connessione in corso...',

              top: 16,                          style: TextStyle(color: telemetryReady ? Colors.teal : Colors.orange, fontSize: 12),

              left: 16,                        ),

              child: Container(                    ],

                padding: const EdgeInsets.all(12),                  ),

                decoration: BoxDecoration(                ),

                  color: Colors.black.withOpacity(0.85),                const SizedBox(width: 12),

                  borderRadius: BorderRadius.circular(8),                if (connected)

                  border: Border.all(                  OutlinedButton.icon(

                    color: Colors.green.withOpacity(0.5),                    onPressed: () => _disconnect(slot),

                    width: 2,                    icon: const Icon(Icons.link_off),

                  ),                    label: const Text('Disconnetti'),

                  boxShadow: [                  )

                    BoxShadow(                else

                      color: Colors.black.withOpacity(0.3),                  const SizedBox.shrink(),

                      blurRadius: 8,              ],

                      offset: const Offset(0, 2),            ),

                    ),          ),

                  ],          if (connected && telemetryReady)

                ),            Padding(

                child: Column(              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

                  crossAxisAlignment: CrossAxisAlignment.start,              child: Column(

                  mainAxisSize: MainAxisSize.min,                crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [                children: [

                    Row(                  Row(

                      mainAxisSize: MainAxisSize.min,                    children: [

                      children: [                      Expanded(

                        Icon(                        child: ElevatedButton.icon(

                          _isTrackingLocation                          onPressed: sendingLed

                              ? Icons.gps_fixed                              ? null

                              : Icons.gps_not_fixed,                              : () async {

                          color: _isTrackingLocation                                  setState(() => _sendingLed[slot] = true);

                              ? Colors.green                                  try {

                              : Colors.orange,                                    await widget.service.sendLedCommand(slot, on: !ledOn);

                          size: 16,                                    setState(() => _ledOn[slot] = !ledOn);

                        ),                                    if (mounted) {

                        const SizedBox(width: 8),                                      ScaffoldMessenger.of(context).showSnackBar(

                        const Text(                                        SnackBar(content: Text('LED ${!ledOn ? 'acceso' : 'spento'}')),

                          'DEBUG GPS',                                      );

                          style: TextStyle(                                    }

                            color: Colors.green,                                  } catch (e) {

                            fontSize: 12,                                    if (mounted) {

                            fontWeight: FontWeight.bold,                                      ScaffoldMessenger.of(context).showSnackBar(

                          ),                                        SnackBar(content: Text('Errore LED: $e')),

                        ),                                      );

                      ],                                    }

                    ),                                  } finally {

                    const SizedBox(height: 8),                                    if (mounted) setState(() => _sendingLed[slot] = false);

                    const Divider(                                  }

                      color: Colors.green,                                },

                      thickness: 1,                          icon: sendingLed

                      height: 1,                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))

                    ),                              : Icon(ledOn ? Icons.lightbulb : Icons.lightbulb_outline),

                    const SizedBox(height: 8),                          label: Text(ledOn ? 'Spegni LED' : 'Accendi LED'),

                    Row(                        ),

                      mainAxisSize: MainAxisSize.min,                      ),

                      children: [                      const SizedBox(width: 8),

                        const Icon(                      Expanded(

                          Icons.location_on,                        child: ElevatedButton.icon(

                          color: Colors.blue,                          onPressed: sendingColor ? null : () => _pickAndSendColor(slot, selectedColor),

                          size: 14,                          icon: sendingColor

                        ),                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))

                        const SizedBox(width: 6),                              : const Icon(Icons.palette_outlined),

                        const Text(                          label: const Text('Colore LED'),

                          'LAT:',                        ),

                          style: TextStyle(                      ),

                            color: Colors.white70,                    ],

                            fontSize: 11,                  ),

                            fontWeight: FontWeight.bold,                  const SizedBox(height: 8),

                          ),                  Row(

                        ),                    mainAxisAlignment: MainAxisAlignment.end,

                        const SizedBox(width: 4),                    children: [

                        Text(                      const Text('Colore attuale:', style: TextStyle(fontSize: 12)),

                          _currentPosition!.latitude.toStringAsFixed(6),                      const SizedBox(width: 8),

                          style: const TextStyle(                      Container(

                            color: Colors.white,                        width: 24,

                            fontSize: 13,                        height: 24,

                            fontFamily: 'monospace',                        decoration: BoxDecoration(

                          ),                          color: selectedColor,

                        ),                          borderRadius: BorderRadius.circular(4),

                      ],                          border: Border.all(color: Colors.black12),

                    ),                        ),

                    const SizedBox(height: 4),                      ),

                    Row(                    ],

                      mainAxisSize: MainAxisSize.min,                  ),

                      children: [                ],

                        const Icon(              ),

                          Icons.location_on,            ),

                          color: Colors.orange,        ],

                          size: 14,      ),

                        ),    );

                        const SizedBox(width: 6),  }

                        const Text(

                          'LON:',  Widget _buildDetectedDevicesSection() {

                          style: TextStyle(    // Filtra i peer con id "unknown"

                            color: Colors.white70,    final allPeers = _peers[DeviceSlot.deviceA] ?? [];

                            fontSize: 11,    final peers = allPeers.where((peer) => peer.id.toLowerCase() != 'unknown').toList();

                            fontWeight: FontWeight.bold,    

                          ),    if (peers.isEmpty) {

                        ),      return Card(

                        const SizedBox(width: 4),        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

                        Text(        child: Padding(

                          _currentPosition!.longitude.toStringAsFixed(6),          padding: const EdgeInsets.all(16.0),

                          style: const TextStyle(          child: Column(

                            color: Colors.white,            children: [

                            fontSize: 13,              Row(

                            fontFamily: 'monospace',                children: const [

                          ),                  Icon(Icons.radar, color: Colors.grey),

                        ),                  SizedBox(width: 8),

                      ],                  Text(

                    ),                    'Dispositivi Rilevati',

                  ],                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

                ),                  ),

              ),                ],

            ),              ),

        ],              const SizedBox(height: 8),

      ),              const Text(

      floatingActionButton: Column(                'Nessun dispositivo rilevato. Premi "Cerca Peer" per iniziare la scansione.',

        mainAxisAlignment: MainAxisAlignment.end,                style: TextStyle(color: Colors.grey),

        children: [                textAlign: TextAlign.center,

          // Pulsante per ottenere posizione corrente              ),

          FloatingActionButton(            ],

            heroTag: 'location',          ),

            onPressed: _getCurrentLocation,        ),

            tooltip: 'Ottieni posizione',      );

            child: const Icon(Icons.my_location),    }

          ),

          const SizedBox(height: 16),    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

          // Pulsante per attivare/disattivare tracciamento      children: [

          FloatingActionButton(        Row(

            heroTag: 'tracking',          children: const [

            onPressed: _toggleLocationTracking,            Icon(Icons.radar),

            tooltip: _isTrackingLocation            SizedBox(width: 8),

                ? 'Disattiva tracciamento'            Text(

                : 'Attiva tracciamento',              'Dispositivi Rilevati',

            backgroundColor: _isTrackingLocation ? Colors.green : null,              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

            child: Icon(            ),

              _isTrackingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,          ],

            ),        ),

          ),        const SizedBox(height: 8),

          const SizedBox(height: 16),        ...peers.map((peer) => _buildPeerCard(peer)),

      ],

          // Pulsante zoom +    );

          FloatingActionButton(  }

            heroTag: 'zoom_in',

            mini: true,  Widget _buildPeerCard(RemotePeer peer) {

            onPressed: () {    final slot = DeviceSlot.deviceA; // I comandi vanno sempre tramite MotoA

              final currentZoom = _mapController.camera.zoom;    final sendingColor = _sendingPeerColor[slot] ?? false;

              _mapController.move(    

                _mapController.camera.center,    return Card(

                currentZoom + 1,      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

              );      child: Padding(

            },        padding: const EdgeInsets.all(16.0),

            tooltip: 'Zoom in',        child: Column(

            child: const Icon(Icons.add),          crossAxisAlignment: CrossAxisAlignment.start,

          ),          children: [

          const SizedBox(height: 8),            Row(

              children: [

          // Pulsante zoom -                Icon(Icons.devices, color: Colors.blue),

          FloatingActionButton(                const SizedBox(width: 8),

            heroTag: 'zoom_out',                Expanded(

            mini: true,                  child: Text(

            onPressed: () {                    peer.id,

              final currentZoom = _mapController.camera.zoom;                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

              _mapController.move(                  ),

                _mapController.camera.center,                ),

                currentZoom - 1,                Text(

              );                  '${peer.distanceMeters.toStringAsFixed(2)} m',

            },                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),

            tooltip: 'Zoom out',                ),

            child: const Icon(Icons.remove),              ],

          ),            ),

        ],            const SizedBox(height: 12),

      ),            Wrap(

    );              spacing: 8,

  }              runSpacing: 8,

}              children: [

                ElevatedButton.icon(
                  onPressed: () => _togglePeerLed(peer.id, true),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Accendi LED'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _togglePeerLed(peer.id, false),
                  icon: const Icon(Icons.lightbulb),
                  label: const Text('Spegni LED'),
                ),
                ElevatedButton.icon(
                  onPressed: sendingColor ? null : () => _pickPeerColorDirect(peer.id),
                  icon: sendingColor
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.palette_outlined),
                  label: const Text('Cambia Colore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanResultCard(ScanResult result) {
    final adv = result.advertisementData;
    final name = _formatScanResultName(result);
    final hasService = adv.serviceUuids.contains(widget.service.serviceUuid) ||
        adv.serviceUuids.contains(widget.service.espLedServiceUuid);
    final lowerName = name.toLowerCase();
    final likelyEsp = lowerName.contains('esp32') || lowerName.contains('uwb');
    final isCompatible = hasService || likelyEsp;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        result.device.remoteId.str,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text('RSSI ${result.rssi} dBm'),
              ],
            ),
            const SizedBox(height: 12),
            if (!isCompatible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Dispositivo non riconosciuto (prova comunque a collegare se è l\'ESP32)',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                ),
              ),
            // Mostra solo il bottone per collegare alla tua moto (DeviceA)
            ElevatedButton.icon(
              onPressed: (!isCompatible || _connectingSlot == DeviceSlot.deviceA || _isConnectedToSlot(DeviceSlot.deviceA, result))
                  ? null
                  : () => _connect(DeviceSlot.deviceA, result),
              icon: _connectingSlot == DeviceSlot.deviceA
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.motorcycle),
              label: const Text('Collega la tua moto'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshScan() async {
    setState(() => _isScanning = true);
    try {
      await widget.service.startScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore scansione: $e')),
      );
    }
  }

  bool _isConnectedToSlot(DeviceSlot slot, ScanResult result) {
    final info = _connections[slot];
    final device = info?.device;
    if (device == null) return false;
    return device.remoteId == result.device.remoteId;
  }

  Future<void> _connect(DeviceSlot slot, ScanResult result) async {
    setState(() => _connectingSlot = slot);
    try {
      await widget.service.connectTo(result, slot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${slot.label} connesso a ${_formatScanResultName(result)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore connessione: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _connectingSlot = null);
      }
    }
  }

  Future<void> _disconnect(DeviceSlot slot) async {
    try {
      await widget.service.disconnect(slot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${slot.label} disconnesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore disconnessione: $e')),
      );
    }
  }

  Future<void> _pickAndSendColor(DeviceSlot slot, Color initialColor) async {
    var tempColor = initialColor;
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Colore LED - ${slot.label}'),
          content: BlockPicker(
            pickerColor: tempColor,
            onColorChanged: (c) => tempColor = c,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempColor),
              child: const Text('Invia'),
            ),
          ],
        );
      },
    );

    if (chosen != null) {
      await _sendColor(slot, chosen);
    }
  }

  Future<void> _sendColor(DeviceSlot slot, Color color) async {
    setState(() {
      _sendingColor[slot] = true;
      _selectedColor[slot] = color;
    });
    try {
      await widget.service.sendColorCommand(slot, color: color);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${slot.label}: colore inviato (${color.red}, ${color.green}, ${color.blue})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore invio colore ${slot.label}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingColor[slot] = false);
    }
  }

  Future<void> _sendPeerColor(DeviceSlot slot, String peerId, Color color) async {
    setState(() => _sendingPeerColor[slot] = true);
    try {
      await widget.service.sendPeerColorCommand(slot, peerId: peerId, color: color);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${slot.label} → $peerId: colore inviato')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore colore peer: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingPeerColor[slot] = false);
    }
  }

  Future<void> _togglePeerScan(DeviceSlot slot) async {
    final active = _peerScanActive[slot] ?? false;
    setState(() => _scanningPeer[slot] = true);
    try {
      if (active) {
        await widget.service.stopPeerScan(slot);
        if (mounted) setState(() => _peerScanActive[slot] = false);
      } else {
        await widget.service.startPeerScan(slot);
        if (mounted) setState(() => _peerScanActive[slot] = true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${slot.label}: scan peer ${active ? "fermato" : "avviato"}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore scan peer ${slot.label}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningPeer[slot] = false);
    }
  }

  Future<void> _toggleAutoScan(DeviceSlot slot, bool enabled) async {
    try {
      if (enabled) {
        await widget.service.enableAutoScan(slot);
      } else {
        await widget.service.disableAutoScan(slot);
      }
      if (mounted) {
        setState(() => _autoScanEnabled[slot] = enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${slot.label}: auto-scan ${enabled ? "abilitato" : "disabilitato"}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore auto-scan ${slot.label}: $e')),
        );
      }
    }
  }

  Future<void> _startPairingMode(DeviceSlot slot) async {
    setState(() => _scanningPeer[slot] = true);
    try {
      await widget.service.startPairingMode(slot);
      if (mounted) {
        setState(() => _peerScanActive[slot] = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modalità PAIRING attivata (60s) - LED rosso lampeggiante'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore avvio PAIRING: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningPeer[slot] = false);
    }
  }

  Future<void> _startSearchingMode(DeviceSlot slot) async {
    setState(() => _scanningPeer[slot] = true);
    try {
      await widget.service.startSearchingMode(slot);
      if (mounted) {
        setState(() => _peerScanActive[slot] = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modalità SEARCHING attivata (60s) - LED blu lampeggiante'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore avvio SEARCHING: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningPeer[slot] = false);
    }
  }

  Future<void> _togglePeerLed(String peerId, bool on) async {
    final slot = DeviceSlot.deviceA;
    try {
      await widget.service.sendPeerLedCommand(slot, peerId: peerId, on: on);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$peerId: LED ${on ? "acceso" : "spento"}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore LED $peerId: $e')),
        );
      }
    }
  }

  Future<void> _pickPeerColorDirect(String peerId) async {
    final slot = DeviceSlot.deviceA;
    Color tempColor = _selectedColor[slot] ?? Colors.orangeAccent;
    
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Colore LED - $peerId'),
          content: BlockPicker(
            pickerColor: tempColor,
            onColorChanged: (c) => tempColor = c,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempColor),
              child: const Text('Invia'),
            ),
          ],
        );
      },
    );

    if (chosen != null) {
      await _sendPeerColor(slot, peerId, chosen);
    }
  }

  Future<void> _pickPeerAndColor(DeviceSlot slot, List<RemotePeer> peers) async {
    if (peers.isEmpty) return;

    String selectedPeer = peers.first.id;
    Color tempColor = _selectedColor[slot] ?? Colors.orangeAccent;

    final result = await showDialog<(String, Color)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Colore peer - ${slot.label}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: selectedPeer,
                    isExpanded: true,
                    items: peers
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text('${p.id} · ${p.distanceMeters.toStringAsFixed(2)} m'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setStateDialog(() => selectedPeer = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  BlockPicker(
                    pickerColor: tempColor,
                    onColorChanged: (c) => setStateDialog(() => tempColor = c),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop((selectedPeer, tempColor)),
                  child: const Text('Invia'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final (peerId, color) = result;
      await _sendPeerColor(slot, peerId, color);
    }
  }

  String _formatConnectedName(BluetoothDevice device) {
    final platformName = device.platformName.trim();
    if (platformName.isNotEmpty) {
      return platformName;
    }
    final advName = device.advName.trim();
    if (advName.isNotEmpty) {
      return advName;
    }
    return device.remoteId.str;
  }

  String _formatScanResultName(ScanResult result) {
    final platformName = result.device.platformName.trim();
    if (platformName.isNotEmpty) {
      return platformName;
    }
    final advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) {
      return advName;
    }
    return result.device.remoteId.str;
  }

  String _formatPayloadPreview(List<int> payload) {
    if (payload.isEmpty) return 'payload vuoto';
    final previewLength = payload.length > 8 ? 8 : payload.length;
    final buffer = StringBuffer();
    for (var i = 0; i < previewLength; i++) {
      buffer.write(payload[i].toRadixString(16).padLeft(2, '0'));
      if (i != previewLength - 1) buffer.write(' ');
    }
    if (payload.length > previewLength) {
      buffer.write(' …');
    }
    return buffer.toString();
  }

  String _formatManagerTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }
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
  // Distanze UWB per i due dispositivi
  double? _uwbDistanceA;
  double? _uwbDistanceB;
  DeviceConnectionInfo? _deviceInfoA;
  DeviceConnectionInfo? _deviceInfoB;
  bool _bridgingEnabled = false;
  bool _showDevicePanel = false;
  final Map<DeviceSlot, List<DeviceTelemetryMessage>> _telemetryHistory = {
    DeviceSlot.deviceA: <DeviceTelemetryMessage>[],
    DeviceSlot.deviceB: <DeviceTelemetryMessage>[],
  };
  // Subscription separata per route recording (evita duplicati su toggle tracking)
  StreamSubscription<LatLng>? _routeSub;
  StreamSubscription<DeviceDistanceUpdate>? _distanceUpdatesSub;
  StreamSubscription<Map<DeviceSlot, DeviceConnectionInfo>>? _connectionUpdatesSub;
  StreamSubscription<bool>? _bridgingStatusSub;
  StreamSubscription<DeviceTelemetryMessage>? _telemetrySub;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _distanceUpdatesSub = _externalDeviceService.distanceUpdates.listen((update) {
      setState(() {
        if (update.slot == DeviceSlot.deviceA) {
          _uwbDistanceA = update.distance;
        } else {
          _uwbDistanceB = update.distance;
        }
      });
    });
    _connectionUpdatesSub = _externalDeviceService.connectionStream.listen((snapshot) {
      setState(() {
        _deviceInfoA = snapshot[DeviceSlot.deviceA];
        _deviceInfoB = snapshot[DeviceSlot.deviceB];
      });
    });
    _bridgingStatusSub = _externalDeviceService.bridgingStream.listen((enabled) {
      setState(() => _bridgingEnabled = enabled);
    });
    _telemetrySub = _externalDeviceService.telemetryStream.listen((message) {
      setState(() {
        final history = _telemetryHistory[message.slot]!;
        history.insert(0, message);
        if (history.length > 20) {
          history.removeRange(20, history.length);
        }
      });
    });
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

  Future<void> _openExternalDeviceManager() async {
    if (!await _ensureBluetoothPrerequisites()) {
      return;
    }

    try {
      await _externalDeviceService.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore scansione: $e')),
        );
      }
      return;
    }

    if (!mounted) {
      await _externalDeviceService.stopScan();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _DeviceManagerSheet(
          service: _externalDeviceService,
          initialConnections: {
            DeviceSlot.deviceA: _deviceInfoA ?? const DeviceConnectionInfo.empty(),
            DeviceSlot.deviceB: _deviceInfoB ?? const DeviceConnectionInfo.empty(),
          },
          initialBridgingEnabled: _bridgingEnabled,
        ),
      ),
    );

    await _externalDeviceService.stopScan();
  }

  Future<void> _openNetworkView() async {
    if (!mounted) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NetworkViewScreen(
          service: _externalDeviceService,
        ),
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
            tooltip: 'Network View',
            onPressed: _openNetworkView,
          ),
          IconButton(
            icon: const Icon(Icons.usb),
            tooltip: 'Collega dispositivo UWB',
            onPressed: _openExternalDeviceManager,
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

          // Barra di stato in alto
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                children: [
                  Icon(
                    _isTrackingLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: _isTrackingLocation ? Colors.green : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_uwbDistanceA != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Moto A: ${_uwbDistanceA!.toStringAsFixed(2)} m',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      if (_uwbDistanceB != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Moto B: ${_uwbDistanceB!.toStringAsFixed(2)} m',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _bridgingEnabled
                              ? Colors.teal.withOpacity(0.7)
                              : Colors.grey.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _bridgingEnabled ? Icons.sync : Icons.sync_disabled,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _bridgingEnabled ? 'Bridge attivo' : 'Bridge off',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_showDevicePanel)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _buildDeviceStatusPanel(),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'device_dashboard',
            mini: true,
            backgroundColor: _showDevicePanel ? Colors.deepPurple : null,
            tooltip: _showDevicePanel
                ? 'Nascondi gestione dispositivi'
                : 'Collega dispositivo UWB',
            onPressed: () {
              setState(() => _showDevicePanel = !_showDevicePanel);
            },
            child: Icon(
              _showDevicePanel ? Icons.close : Icons.settings_input_antenna,
            ),
          ),
          const SizedBox(height: 12),
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

  Widget _buildDeviceStatusPanel() {
    final infoA = _deviceInfoA ?? const DeviceConnectionInfo.empty();
    final infoB = _deviceInfoB ?? const DeviceConnectionInfo.empty();

    return Card(
      color: Colors.black.withOpacity(0.7),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth, color: Colors.lightBlueAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dispositivi UWB',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi pannello',
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => setState(() => _showDevicePanel = false),
                ),
                TextButton.icon(
                  onPressed: _openExternalDeviceManager,
                  icon: const Icon(Icons.settings_input_antenna),
                  label: const Text('Gestisci'),
                  style: TextButton.styleFrom(foregroundColor: Colors.lightBlueAccent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDeviceStatusRow(DeviceSlot.deviceA, infoA, _uwbDistanceA),
            const SizedBox(height: 8),
            _buildDeviceStatusRow(DeviceSlot.deviceB, infoB, _uwbDistanceB),
            const Divider(color: Colors.white24, height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bridge telemetria',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _externalDeviceService.canBridge
                            ? 'Quando attivo inoltra i dati tra Moto A e Moto B.'
                            : 'Collega entrambe le moto con telemetria per abilitare il bridge.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _bridgingEnabled,
                  onChanged: _externalDeviceService.canBridge
                      ? (value) {
                          try {
                            _externalDeviceService.setBridgingEnabled(value);
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      : null,
                  activeThumbColor: Colors.tealAccent,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Telemetria recente',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Svuota log telemetria',
                  onPressed: _telemetryHistory.values.every((entries) => entries.isEmpty)
                      ? null
                      : _clearTelemetryHistory,
                  icon: const Icon(Icons.delete_sweep, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...DeviceSlot.values.map(
              (slot) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildTelemetryCard(slot),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(DeviceSlot slot) {
    final entries = _telemetryHistory[slot]!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                slot == DeviceSlot.deviceA ? Icons.bike_scooter : Icons.directions_bike,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                slot.label,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                entries.isEmpty ? '—' : '${entries.length} pacchetti',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Text(
              'Nessun payload ricevuto ancora.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries
                  .take(5)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TelemetryPayloadTile(
                        timestamp: _formatTimestamp(entry.timestamp),
                        hexPayload: _formatPayloadHex(entry.payload),
                        asciiPayload: _formatPayloadAscii(entry.payload),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  void _clearTelemetryHistory() {
    setState(() {
      for (final entries in _telemetryHistory.values) {
        entries.clear();
      }
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  String _formatPayloadHex(List<int> payload) {
    if (payload.isEmpty) {
      return '(vuoto)';
    }
    return payload.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _formatPayloadAscii(List<int> payload) {
    if (payload.isEmpty) {
      return '∅';
    }
    final buffer = StringBuffer();
    for (final byte in payload) {
      if (byte >= 32 && byte <= 126) {
        buffer.writeCharCode(byte);
      } else {
        buffer.write('.');
      }
    }
    final ascii = buffer.toString();
    return ascii.trim().isEmpty ? '∅' : ascii;
  }

  Widget _buildDeviceStatusRow(
    DeviceSlot slot,
    DeviceConnectionInfo info,
    double? distance,
  ) {
    final connected = info.device != null;
    final telemetry = info.telemetryReady;
    final color = connected ? Colors.greenAccent : Colors.redAccent;
    final icon = connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                connected ? _formatDeviceName(info.device) : 'Non connesso',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                connected
                    ? (telemetry ? 'Telemetria attiva' : 'Solo distanza')
                    : 'In attesa di connessione',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        if (distance != null)
          Text(
            '${distance.toStringAsFixed(2)} m',
            style: const TextStyle(color: Colors.white70),
          ),
      ],
    );
  }

  String _formatDeviceName(BluetoothDevice? device) {
    if (device == null) return '—';
    final name = device.platformName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return device.remoteId.str;
  }

  @override
  void dispose() {
    _isTrackingLocation = false;
    _routeSub?.cancel();
    _distanceUpdatesSub?.cancel();
    _connectionUpdatesSub?.cancel();
    _bridgingStatusSub?.cancel();
    _telemetrySub?.cancel();
    unawaited(_externalDeviceService.stopScan());
    unawaited(_externalDeviceService.disconnectAll());
    super.dispose();
  }
}

class _TelemetryPayloadTile extends StatelessWidget {
  const _TelemetryPayloadTile({
    required this.timestamp,
    required this.hexPayload,
    required this.asciiPayload,
  });

  final String timestamp;
  final String hexPayload;
  final String asciiPayload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                timestamp,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'HEX',
            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2),
          ),
          const SizedBox(height: 2),
          SelectableText(
            hexPayload,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'ASCII',
            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2),
          ),
          const SizedBox(height: 2),
          Text(
            asciiPayload,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
