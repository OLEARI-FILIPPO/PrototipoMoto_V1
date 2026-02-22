import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import '../models/region.dart';
import '../services/map_service.dart';
import '../services/notification_service.dart';

/// Schermata per selezionare e scaricare le regioni italiane
class RegionSelectionScreen extends StatefulWidget {
  const RegionSelectionScreen({super.key});

  @override
  State<RegionSelectionScreen> createState() => _RegionSelectionScreenState();
}

class _RegionSelectionScreenState extends State<RegionSelectionScreen> {
  final MapService _mapService = MapService();
  final NotificationService _notificationService = NotificationService();
  List<ItalianRegion> _regions = [];
  final Set<String> _selectedRegions = {};
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _currentDownloadingRegion;
  String? _currentRegionName;
  late File _downloadedFile;
  bool _loadingDownloaded = true;
  bool _locatingRegion = false;

  @override
  void initState() {
    super.initState();
    _regions = ItalianRegion.getAllRegions();
    _initialize();
  }

  Future<void> _initialize() async {
    await _notificationService.init();
    await _initializeMapService();
    await _preparePersistence();
    await _loadDownloadedRegions();
    await _detectAndPrioritizeCurrentRegion();
    setState(() => _loadingDownloaded = false);
  }

  Future<void> _initializeMapService() async {
    await _mapService.initialize();
    // Verifica quali regioni sono già state scaricate
    // Per ora impostiamo tutto come non scaricato
    setState(() {});
  }

  Future<void> _preparePersistence() async {
    final dir = await getApplicationSupportDirectory();
    _downloadedFile = File('${dir.path}/downloaded_regions.json');
    if (!(await _downloadedFile.exists())) {
      await _downloadedFile.create(recursive: true);
      await _downloadedFile.writeAsString(jsonEncode(<String>[]));
    }
  }

  Future<void> _loadDownloadedRegions() async {
    try {
      final raw = await _downloadedFile.readAsString();
      final List<dynamic> decoded = jsonDecode(raw);
      final downloaded = decoded.cast<String>().toSet();

      setState(() {
        for (final region in _regions) {
          region.isDownloaded = downloaded.contains(region.name);
        }
      });
    } catch (_) {
      // fallback: empty list
      await _downloadedFile.writeAsString(jsonEncode(<String>[]));
    }
  }

  Future<void> _saveDownloadedRegions() async {
    final names = _regions.where((r) => r.isDownloaded).map((r) => r.name).toList();
    await _downloadedFile.writeAsString(jsonEncode(names));
  }

  Future<void> _detectAndPrioritizeCurrentRegion() async {
    setState(() => _locatingRegion = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locatingRegion = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locatingRegion = false);
        return;
      }

      Position? pos;
      // Primo tentativo: massima precisione con timeout (usa GPS + reti)
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        pos = null;
      }

      // Secondo tentativo: alta precisione ma meno aggressiva
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 6),
            ),
          );
        } catch (_) {
          pos = null;
        }
      }

      // Fallback finale: ultima posizione nota
      pos ??= await Geolocator.getLastKnownPosition();
      if (pos == null) return;

      final currentLatLng = LatLng(pos.latitude, pos.longitude);

      // Padding per includere piccoli errori GPS e mare vicino costa
      const paddingDeg = 0.25; // ~28km

      ItalianRegion? match;
      for (final r in _regions) {
        final padded = LatLngBounds(
          LatLng(r.bounds.south - paddingDeg, r.bounds.west - paddingDeg),
          LatLng(r.bounds.north + paddingDeg, r.bounds.east + paddingDeg),
        );
        if (padded.contains(currentLatLng)) {
          match = r;
          break;
        }
      }

      // Fallback: regione più vicina al centro se non rientra in nessun bound
      match ??= _regions.reduce((a, b) {
        final distA = const Distance().as(LengthUnit.Kilometer, currentLatLng, a.getCenter());
        final distB = const Distance().as(LengthUnit.Kilometer, currentLatLng, b.getCenter());
        return distA <= distB ? a : b;
      });

      setState(() {
        _currentRegionName = match!.name;
        _prioritizeCurrentRegion();
      });
    } catch (_) {
      // ignore errors, keep ordering
    } finally {
      if (mounted) setState(() => _locatingRegion = false);
    }
  }

  void _prioritizeCurrentRegion() {
    if (_currentRegionName == null) return;
    _regions.sort((a, b) {
      if (a.name == _currentRegionName) return -1;
      if (b.name == _currentRegionName) return 1;
      return a.name.compareTo(b.name);
    });
  }

  Future<void> _downloadSelectedRegions() async {
    if (_selectedRegions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona almeno una regione da scaricare'),
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    // Notifica iniziale
    await _notificationService.showDownloadProgress(
      title: 'Download mappe offline',
      body: 'Avvio download regioni selezionate...',
      progress: 0,
    );

    try {
      int totalRegions = _selectedRegions.length;
      int currentIndex = 0;

      for (String regionName in _selectedRegions) {
        final region = _regions.firstWhere((r) => r.name == regionName);

        setState(() {
          _currentDownloadingRegion = regionName;
        });

        await _mapService.downloadRegion(
          regionName: regionName,
          bounds: region.bounds,
          minZoom: 6,
          maxZoom: 14, // Limito a 14 per non scaricare troppi dati
          onProgress: (progress) {
            setState(() {
              // Calcola il progresso totale considerando tutte le regioni
              double regionProgress = progress / 100;
              _downloadProgress =
                  ((currentIndex + regionProgress) / totalRegions) * 100;
            });
            _notificationService.showDownloadProgress(
              title: 'Download mappe offline',
              body: 'Scaricamento $regionName (${_downloadProgress.toStringAsFixed(0)}%)',
              progress: _downloadProgress.round().clamp(0, 100),
            );
          },
        );

        currentIndex++;

        // Marca la regione come scaricata
        setState(() {
          region.isDownloaded = true;
        });
        await _saveDownloadedRegions();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download completato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _notificationService.cancelDownloadNotification();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante il download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      await _notificationService.cancelDownloadNotification();
    } finally {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
        _currentDownloadingRegion = null;
      });
    }
  }

  Future<void> _deleteRegion(ItalianRegion region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina mappe offline'),
        content: const Text(
          'Questa azione rimuove le tile salvate (tutte le regioni). Vuoi procedere?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _mapService.deleteAllTiles();
    setState(() {
      for (final r in _regions) {
        r.isDownloaded = false;
      }
      _selectedRegions.clear();
    });
    await _saveDownloadedRegions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mappe offline rimosse')), // all regions cleared
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleziona Regioni'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
          if (_loadingDownloaded || _locatingRegion)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Regione rilevata',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentRegionName ?? 'Non rilevata',
                        style: TextStyle(
                          color: _currentRegionName != null ? Colors.blueGrey.shade800 : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _locatingRegion ? null : _detectAndPrioritizeCurrentRegion,
                  icon: Icon(_locatingRegion ? Icons.hourglass_empty : Icons.my_location),
                  label: Text(_locatingRegion ? 'Ricerca...' : 'Ottieni posizione'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                ),
              ],
            ),
          ),
          // Barra informativa
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Seleziona le regioni da scaricare per l\'uso offline',
                    style: TextStyle(color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),

          // Barra di progresso durante il download
          if (_isDownloading)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Scaricando: $_currentDownloadingRegion',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _downloadProgress / 100),
                  const SizedBox(height: 4),
                  Text(
                    '${_downloadProgress.toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Lista delle regioni
          Expanded(
            child: ListView.builder(
              itemCount: _regions.length,
              itemBuilder: (context, index) {
                final region = _regions[index];
                final isSelected = _selectedRegions.contains(region.name);
                final isCurrent = region.name == _currentRegionName;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: Row(
                            children: [
                              Text(
                                region.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (isCurrent)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Qui',
                                    style: TextStyle(color: Colors.blue.shade800, fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            region.isDownloaded ? 'Scaricata in locale' : 'Non scaricata',
                            style: TextStyle(
                              color: region.isDownloaded ? Colors.green : Colors.grey,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (_isDownloading || region.isDownloaded)
                              ? null
                              : (bool? value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedRegions.add(region.name);
                                    } else {
                                      _selectedRegions.remove(region.name);
                                    }
                                  });
                                },
                          secondary: Icon(
                            region.isDownloaded
                                ? Icons.download_done
                                : Icons.download,
                            color: region.isDownloaded ? Colors.green : Colors.grey,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  region.isDownloaded
                                      ? 'Occupazione locale pronta. Puoi eliminarla.'
                                      : 'Seleziona e scarica per uso offline.',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (region.isDownloaded)
                                OutlinedButton.icon(
                                  onPressed: _isDownloading ? null : () => _deleteRegion(region),
                                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                                  label: const Text('Elimina', style: TextStyle(color: Colors.red)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: _isDownloading ? null : _downloadSelectedRegions,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Scarica'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Pulsanti di azione
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedRegions.length} regione/i selezionate',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadSelectedRegions,
                  icon: const Icon(Icons.download),
                  label: const Text('Scarica'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
