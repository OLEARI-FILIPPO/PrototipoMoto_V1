/// Rappresenta un nodo nella rete mesh (dispositivo ESP32)
class NetworkNode {
  final String id;
  final String name;
  final DeviceNodeState state;
  final double? distance; // metri
  final int rssi;
  final DateTime lastSeen;
  final bool isLocalDevice; // true se è il dispositivo connesso al telefono
  final bool isBusy; // true se già connesso ad un altro dispositivo

  NetworkNode({
    required this.id,
    required this.name,
    required this.state,
    this.distance,
    required this.rssi,
    required this.lastSeen,
    this.isLocalDevice = false,
    this.isBusy = false,
  });

  /// Colore basato sulla distanza
  /// Verde < 2m, Giallo 2-5m, Rosso > 5m
  NetworkNodeColor get distanceColor {
    if (distance == null || distance! < 0) return NetworkNodeColor.unknown;
    if (distance! < 2.0) return NetworkNodeColor.near;
    if (distance! < 5.0) return NetworkNodeColor.medium;
    return NetworkNodeColor.far;
  }

  /// È considerato online se visto negli ultimi 5 secondi
  bool get isOnline {
    return DateTime.now().difference(lastSeen).inSeconds < 5;
  }

  NetworkNode copyWith({
    String? id,
    String? name,
    DeviceNodeState? state,
    double? distance,
    int? rssi,
    DateTime? lastSeen,
    bool? isLocalDevice,
    bool? isBusy,
  }) {
    return NetworkNode(
      id: id ?? this.id,
      name: name ?? this.name,
      state: state ?? this.state,
      distance: distance ?? this.distance,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      isLocalDevice: isLocalDevice ?? this.isLocalDevice,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

/// Stato del dispositivo nella rete mesh
enum DeviceNodeState { idle, pairing, searching, connected, unknown }

/// Colore per visualizzazione distanza
enum NetworkNodeColor {
  near, // Verde < 2m
  medium, // Giallo 2-5m
  far, // Rosso > 5m
  unknown, // Grigio (distanza sconosciuta)
}

extension DeviceNodeStateExtension on DeviceNodeState {
  String get label {
    switch (this) {
      case DeviceNodeState.idle:
        return 'IDLE';
      case DeviceNodeState.pairing:
        return 'PAIRING';
      case DeviceNodeState.searching:
        return 'SEARCHING';
      case DeviceNodeState.connected:
        return 'CONNECTED';
      case DeviceNodeState.unknown:
        return 'UNKNOWN';
    }
  }

  /// Colore per l'indicatore di stato
  int get color {
    switch (this) {
      case DeviceNodeState.idle:
        return 0xFF9E9E9E; // Grigio
      case DeviceNodeState.pairing:
        return 0xFFFF0000; // Rosso
      case DeviceNodeState.searching:
        return 0xFF2196F3; // Blu
      case DeviceNodeState.connected:
        return 0xFF4CAF50; // Verde
      case DeviceNodeState.unknown:
        return 0xFF757575; // Grigio scuro
    }
  }
}
