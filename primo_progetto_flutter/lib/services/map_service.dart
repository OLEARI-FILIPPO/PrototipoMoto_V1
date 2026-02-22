import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map/flutter_map.dart';

/// Servizio per gestire il download e la gestione delle mappe offline
class MapService {
  // Singleton pattern
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  static const String storeName = 'mapStore';
  late final FMTCStore store;
  bool _storeInitialized = false;

  /// Inizializza il servizio delle mappe
  Future<void> initialize() async {
    // Il backend è già stato inizializzato in main.dart
    // Inizializza solo lo store se non è già stato fatto
    if (!_storeInitialized) {
      store = FMTCStore(storeName);
      await store.manage.create();
      _storeInitialized = true;
    }
  }

  /// Scarica le tile di una regione specifica
  ///
  /// [regionName] - Nome della regione da scaricare
  /// [bounds] - Limiti geografici della regione
  /// [minZoom] - Livello di zoom minimo (default: 6)
  /// [maxZoom] - Livello di zoom massimo (default: 16)
  /// [onProgress] - Callback per tracciare il progresso del download
  Future<void> downloadRegion({
    required String regionName,
    required LatLngBounds bounds,
    int minZoom = 6,
    int maxZoom = 16,
    Function(double progress)? onProgress,
  }) async {
    await initialize();

    final rectangleRegion = RectangleRegion(bounds);
    final region = rectangleRegion.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.primo_progetto_flutter',
      ),
    );

    final download = store.download.startForeground(
      region: region,
      skipExistingTiles: true,
    );

    await for (final progress in download.downloadProgress) {
      if (onProgress != null) {
        final percentComplete = progress.percentageProgress;
        onProgress(percentComplete);
      }
    }
  }

  /// Ottiene le statistiche di una regione scaricata
  Future<Map<String, dynamic>> getRegionStats() async {
    await initialize();

    final stats = await store.stats.length;
    final size = await store.stats.size;

    return {
      'tiles': stats,
      'size': (size / (1024 * 1024)).toStringAsFixed(2), // MB
    };
  }

  /// Verifica se una regione è stata scaricata
  Future<bool> isRegionDownloaded() async {
    await initialize();
    final stats = await store.stats.length;
    return stats > 0;
  }

  /// Elimina tutte le tile scaricate
  Future<void> deleteAllTiles() async {
    await initialize();
    await store.manage.reset();
  }

  /// Elimina le tile vecchie (più di X giorni)
  Future<void> deleteOldTiles(int days) async {
    await initialize();
    // La nuova API non supporta direttamente la cancellazione per data
    // Si può implementare una logica personalizzata se necessario
  }

  /// Ottiene il TileLayer per flutter_map
  ///
  /// Usa sempre la cache (cacheFirst) e scrive/aggiorna le tile quando online.
  TileLayer getTileLayer() {
    final options = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.primo_progetto_flutter',
      tileProvider: _storeInitialized
          ? FMTCTileProvider.allStores(
              allStoresStrategy: BrowseStoreStrategy.readUpdateCreate,
              loadingStrategy: BrowseLoadingStrategy.cacheFirst,
            )
          : NetworkTileProvider(),
    );
    return options;
  }
}
