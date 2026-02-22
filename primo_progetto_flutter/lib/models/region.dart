import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// Modello per rappresentare una regione italiana con i suoi confini geografici
class ItalianRegion {
  final String name;
  final LatLngBounds bounds;
  bool isDownloaded;

  ItalianRegion({
    required this.name,
    required this.bounds,
    this.isDownloaded = false,
  });

  /// Lista di tutte le regioni italiane con le loro coordinate approssimative
  static List<ItalianRegion> getAllRegions() {
    return [
      ItalianRegion(
        name: 'Piemonte',
        bounds: LatLngBounds(
          const LatLng(43.7, 6.6), // Sud-Ovest
          const LatLng(46.5, 9.2), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Valle d\'Aosta',
        bounds: LatLngBounds(
          const LatLng(45.4, 6.7), // Sud-Ovest
          const LatLng(46.0, 7.9), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Lombardia',
        bounds: LatLngBounds(
          const LatLng(44.6, 8.5), // Sud-Ovest
          const LatLng(46.6, 11.5), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Trentino-Alto Adige',
        bounds: LatLngBounds(
          const LatLng(45.7, 10.4), // Sud-Ovest
          const LatLng(47.1, 12.5), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Veneto',
        bounds: LatLngBounds(
          const LatLng(44.8, 10.6), // Sud-Ovest
          const LatLng(46.7, 13.0), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Friuli-Venezia Giulia',
        bounds: LatLngBounds(
          const LatLng(45.5, 12.3), // Sud-Ovest
          const LatLng(46.7, 13.9), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Liguria',
        bounds: LatLngBounds(
          const LatLng(43.8, 7.5), // Sud-Ovest
          const LatLng(44.7, 10.1), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Emilia-Romagna',
        bounds: LatLngBounds(
          const LatLng(43.7, 9.2), // Sud-Ovest
          const LatLng(45.2, 13.0), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Toscana',
        bounds: LatLngBounds(
          const LatLng(42.2, 9.8), // Sud-Ovest
          const LatLng(44.5, 12.4), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Umbria',
        bounds: LatLngBounds(
          const LatLng(42.4, 11.9), // Sud-Ovest
          const LatLng(43.6, 13.3), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Marche',
        bounds: LatLngBounds(
          const LatLng(42.7, 12.4), // Sud-Ovest
          const LatLng(44.0, 13.9), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Lazio',
        bounds: LatLngBounds(
          const LatLng(40.8, 11.4), // Sud-Ovest
          const LatLng(42.9, 14.0), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Abruzzo',
        bounds: LatLngBounds(
          const LatLng(41.7, 13.0), // Sud-Ovest
          const LatLng(42.9, 14.8), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Molise',
        bounds: LatLngBounds(
          const LatLng(41.4, 14.0), // Sud-Ovest
          const LatLng(42.0, 15.2), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Campania',
        bounds: LatLngBounds(
          const LatLng(39.9, 13.7), // Sud-Ovest
          const LatLng(41.5, 15.8), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Puglia',
        bounds: LatLngBounds(
          const LatLng(39.8, 14.9), // Sud-Ovest
          const LatLng(42.2, 18.5), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Basilicata',
        bounds: LatLngBounds(
          const LatLng(39.9, 15.4), // Sud-Ovest
          const LatLng(41.1, 16.9), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Calabria',
        bounds: LatLngBounds(
          const LatLng(37.9, 15.6), // Sud-Ovest
          const LatLng(40.2, 17.2), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Sicilia',
        bounds: LatLngBounds(
          const LatLng(36.6, 12.4), // Sud-Ovest
          const LatLng(38.8, 15.7), // Nord-Est
        ),
      ),
      ItalianRegion(
        name: 'Sardegna',
        bounds: LatLngBounds(
          const LatLng(38.9, 8.1), // Sud-Ovest
          const LatLng(41.3, 9.8), // Nord-Est
        ),
      ),
    ];
  }

  /// Ottiene il centro della regione
  LatLng getCenter() {
    return LatLng(
      (bounds.south + bounds.north) / 2,
      (bounds.west + bounds.east) / 2,
    );
  }

  /// Stima il numero di tile che verranno scaricate
  /// Questo è un calcolo approssimativo
  int estimateTileCount(int minZoom, int maxZoom) {
    int totalTiles = 0;
    for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
      // Calcolo approssimativo basato sull'area
      final latDiff = (bounds.north - bounds.south).abs();
      final lngDiff = (bounds.east - bounds.west).abs();
      final tilesAtZoom = (latDiff * lngDiff * (1 << (zoom * 2))).round();
      totalTiles += tilesAtZoom;
    }
    return totalTiles;
  }
}
