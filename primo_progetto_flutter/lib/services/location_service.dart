import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Servizio per gestire la geolocalizzazione dell'utente
class LocationService {
  /// Stream per tracciare la posizione in tempo reale
  Stream<LatLng>? _positionStream;

  /// Verifica se i servizi di localizzazione sono abilitati
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Richiede i permessi per la localizzazione
  Future<bool> requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Ottiene la posizione corrente dell'utente
  Future<LatLng?> getCurrentLocation() async {
    try {
      // Verifica se i servizi di localizzazione sono abilitati
      bool serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Richiede i permessi
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        return null;
      }

      // Ottiene la posizione corrente
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Errore nel recupero della posizione: $e');
      return null;
    }
  }

  /// Avvia il tracciamento continuo della posizione
  Stream<LatLng> getLocationStream() {
    _positionStream ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Aggiorna ogni 10 metri
      ),
    ).map((position) => LatLng(position.latitude, position.longitude));

    return _positionStream!;
  }

  /// Calcola la distanza tra due punti in metri
  double calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Apre le impostazioni di localizzazione del dispositivo
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}
