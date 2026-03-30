import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/network_node.dart';
import '../services/external_device_service.dart';
import 'dart:async';

class NetworkViewScreen extends StatefulWidget {
  const NetworkViewScreen({super.key});

  @override
  State<NetworkViewScreen> createState() => _NetworkViewScreenState();
}

class _NetworkViewScreenState extends State<NetworkViewScreen> {
  final ExternalDeviceService _service = ExternalDeviceService();
  final List<NetworkNode> _nodes = [];

  StreamSubscription? _telemetrySubscription;
  StreamSubscription? _connectionSubscription;

  DeviceNodeState _localDeviceState = DeviceNodeState.idle;
  DeviceConnectionInfo _connection = const DeviceConnectionInfo.empty();
  Timer? _modeTimer;
  String _activeCommMode = "Sconosciuto";
  String _commOverride = 'AUTO'; // 'AUTO' | 'UWB' | 'LoRa'

  @override
  void initState() {
    super.initState();
    _connection = _service.currentConnection;
    _startListening();
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _connectionSubscription?.cancel();
    _modeTimer?.cancel();
    super.dispose();
  }

  void _startListening() {
    _connectionSubscription = _service.connectionStream.listen((connection) {
      if (!mounted) return;
      setState(() {
        _connection = connection;
      });
    });

    _telemetrySubscription = _service.telemetryStream.listen((message) {
      if (!mounted) return;
      _parseAndUpdateNodes(message.payload);
    });
  }

  void _parseAndUpdateNodes(List<int> payload) {
    final message = String.fromCharCodes(payload);

    try {
      // --- Comm mode (solo quando cambia) ---
      final commMatch = RegExp(r'"comm":"([^"]+)"').firstMatch(message);
      final comm = commMatch?.group(1) ?? 'UNKNOWN';
      if (comm != 'UNKNOWN' && _activeCommMode != comm) {
        setState(() { _activeCommMode = comm; });
        debugPrint('[COMM] Modalità → $comm');
      }

      // --- Peers ---
      final peersMatch = RegExp(r'"peers":\s*\[([^\]]*)\]').firstMatch(message);
      if (peersMatch == null) return;

      final peersArrayStr = peersMatch.group(1)!;
      if (peersArrayStr.trim().isEmpty) {
        // Nessun peer: teniamo i nodi esistenti visibili, nessun log
        return;
      }

      final peerObjects = RegExp(r'\{[^\}]+\}').allMatches(peersArrayStr);
      final int prevCount = _nodes.length;

      setState(() {
        for (final peerMatch in peerObjects) {
          final peerStr = peerMatch.group(0)!;
          final idMatch = RegExp(r'"id":"([^"]+)"').firstMatch(peerStr);
          if (idMatch == null) continue;

          final peerId = idMatch.group(1)!;
          if (peerId.toLowerCase() == 'unknown') continue;

          final rssiMatch = RegExp(r'"rssi":(-?\d+)').firstMatch(peerStr);
          final distMatch = RegExp(r'"dist":([0-9.]+)').firstMatch(peerStr);
          final rssi = rssiMatch != null ? int.parse(rssiMatch.group(1)!) : 0;
          final dist = distMatch != null ? double.parse(distMatch.group(1)!) : null;

          final newNode = NetworkNode(
            id: peerId,
            name: peerId,
            state: DeviceNodeState.unknown,
            distance: dist,
            rssi: rssi,
            lastSeen: DateTime.now(),
            isLocalDevice: false,
          );

          final existingIndex = _nodes.indexWhere((n) => n.id == peerId);
          if (existingIndex >= 0) {
            _nodes[existingIndex] = newNode;
          } else {
            _nodes.add(newNode);
            debugPrint('[PEERS] ➕ Nuovo nodo: $peerId | RSSI $rssi | ${dist?.toStringAsFixed(1) ?? "--"}m');
          }
        }

        // Log solo quando il numero di nodi cambia
        if (_nodes.length != prevCount) {
          debugPrint('[PEERS] Totale nodi: $prevCount → ${_nodes.length}');
        }
      });
    } catch (e) {
      debugPrint('[PARSER] ❌ Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connection.device != null;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Network View',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.red),
              onPressed: () => _service.disconnect(),
              tooltip: 'Disconnetti',
            ),
        ],
      ),
      body: isConnected ? _buildNetworkView() : _buildDisconnectedView(),
    );
  }

  Widget _buildDisconnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 80, color: Colors.blue[400]),
          const SizedBox(height: 24),
          const Text(
            'Non connesso al Bridge ESP32',
            style: TextStyle(fontSize: 20, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanDeviceScreen()),
              );
            },
            icon: const Icon(Icons.search),
            label: const Text('Cerca Dispositivi'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkView() {
    return Column(
      children: [
        _buildLocalHeader(),
        _buildDebugBanner(), // ✨ NUOVO: Banner di debug
        Expanded(
          child: _nodes.isEmpty
              ? const Center(
                  child: Text(
                    "Nessun nodo rilevato",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _nodes.length,
                  itemBuilder: (context, index) =>
                      _buildNodeCard(_nodes[index]),
                ),
        ),
        _buildControls(),
        _buildCommControls(),
      ],
    );
  }

  Widget _buildLocalHeader() {
    final device = _connection.device;
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_connected, color: Colors.green),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device?.platformName ?? "Unknown",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    device?.remoteId.str ?? "",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _activeCommMode.startsWith("UWB")
                  ? Colors.blueAccent
                  : _activeCommMode.startsWith("LoRa")
                      ? Colors.orangeAccent
                      : Colors.grey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  _activeCommMode.contains("[F]")
                      ? Icons.lock
                      : _activeCommMode.startsWith("UWB")
                          ? Icons.wifi_tethering
                          : _activeCommMode.startsWith("LoRa")
                              ? Icons.cell_tower
                              : Icons.help_outline,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _activeCommMode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✨ NUOVO: Banner di debug per vedere lo stato in tempo reale
  Widget _buildDebugBanner() {
    final totalNodes = _nodes.length;
    final directNodes = _nodes.where((n) => !n.id.toLowerCase().contains('indirect')).length;
    final indirectNodes = totalNodes - directNodes;
    
    Color bannerColor = Colors.grey[800]!;
    String statusEmoji = "⏸️";
    String statusText = "Idle";
    
    if (_localDeviceState == DeviceNodeState.pairing) {
      bannerColor = Colors.red[900]!;
      statusEmoji = "🔴";
      statusText = "PAIRING Mode";
    } else if (_localDeviceState == DeviceNodeState.searching) {
      bannerColor = Colors.blue[900]!;
      statusEmoji = "🔵";
      statusText = "SEARCHING Mode";
    } else if (totalNodes > 0) {
      bannerColor = Colors.green[900]!;
      statusEmoji = "✅";
      statusText = "Connected";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: bannerColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                statusEmoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$totalNodes node${totalNodes != 1 ? 's' : ''}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (totalNodes > 0) ...[
            const SizedBox(height: 8),
            Text(
              "→ Direct: $directNodes | ↪️ Indirect: $indirectNodes",
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "💡 Check logs for detailed mesh topology",
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              "No ESP32 devices detected. Press PAIRING or SEARCHING to discover.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeCard(NetworkNode node) {
    final isIndirect = node.id.toLowerCase().contains('indirect');
    final icon = isIndirect ? Icons.repeat : Icons.circle;
    final subtitle = isIndirect 
        ? "RSSI: ${node.rssi} dBm (via another ESP32)" 
        : "RSSI: ${node.rssi} dBm (direct connection)";
    
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: _getDistanceColor(node.distance ?? 0),
          size: isIndirect ? 24 : 16,
        ),
        title: Row(
          children: [
            if (isIndirect)
              const Text(
                "↪️ ",
                style: TextStyle(color: Colors.orange, fontSize: 16),
              ),
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isIndirect ? Colors.orange[300] : Colors.grey,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          node.distance != null
              ? "${node.distance!.toStringAsFixed(1)}m"
              : "--",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getDistanceColor(double dist) {
    if (dist < 2.0) return Colors.green;
    if (dist < 5.0) return Colors.orange;
    return Colors.red;
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF222222),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModeButton(
            "PAIRING",
            DeviceNodeState.pairing,
            Colors.redAccent,
          ),
          _buildModeButton(
            "SEARCHING",
            DeviceNodeState.searching,
            Colors.blueAccent,
          ),
          _buildModeButton("STOP", DeviceNodeState.idle, Colors.grey),
        ],
      ),
    );
  }

  Widget _buildCommControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          const Text(
            "Comm:",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 8),
          _buildCommButton("UWB", Colors.blueAccent),
          const SizedBox(width: 6),
          _buildCommButton("LoRa", Colors.orangeAccent),
          const SizedBox(width: 6),
          _buildCommButton("AUTO", Colors.green),
        ],
      ),
    );
  }

  Widget _buildCommButton(String mode, Color color) {
    final isActive = _commOverride == mode;
    return ElevatedButton(
      onPressed: () async {
        await _service.setCommMode(mode);
        setState(() => _commOverride = mode);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : color.withOpacity(0.3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(mode, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildModeButton(String label, DeviceNodeState mode, Color color) {
    final isActive = _localDeviceState == mode;
    return ElevatedButton(
      onPressed: () => _setMode(mode),
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : color.withOpacity(0.3),
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  Future<void> _setMode(DeviceNodeState mode) async {
    _modeTimer?.cancel();

    try {
      if (mode == DeviceNodeState.pairing) {
        await _service.startPairingMode();
      } else if (mode == DeviceNodeState.searching) {
        await _service.startSearchingMode();
      } else {
        await _service.stopMode();
        setState(() {
          _nodes.clear();
          _commOverride = 'AUTO';
        });
      }

      setState(() => _localDeviceState = mode);

      if (mode != DeviceNodeState.idle) {
        // Auto-transition to CONNECTED after 30s if nodes found
        _modeTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() {
              _localDeviceState = DeviceNodeState.connected;
            });
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

class ScanDeviceScreen extends StatefulWidget {
  const ScanDeviceScreen({super.key});

  @override
  State<ScanDeviceScreen> createState() => _ScanDeviceScreenState();
}

class _ScanDeviceScreenState extends State<ScanDeviceScreen> {
  final ExternalDeviceService _service = ExternalDeviceService();
  List<ScanResult> _results = [];
  StreamSubscription? _scanSub;
  final Set<String> _busyDevices =
      {}; // MAC addresses di dispositivi occupati/problematici

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    _results = [];
    _scanSub = _service.scanResultsStream.listen((results) {
      if (mounted) {
        setState(() {
          _results = results
              .where((r) => r.device.platformName.toUpperCase().contains('ESP'))
              .toList();
        });
      }
    });
    _service.startScan();
  }

  @override
  void dispose() {
    _service.stopScan();
    _scanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scansione ESP32"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _busyDevices.clear();
              _startScan();
            },
            tooltip: 'Aggiorna scansione',
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final r = _results[index];
          final macAddress = r.device.remoteId.str;
          final isBusy = _busyDevices.contains(macAddress);
          final isWeak = r.rssi < -80;

          return ListTile(
            enabled: !isBusy,
            title: Row(
              children: [
                Text(
                  r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : "Unknown Device",
                  style: TextStyle(color: isBusy ? Colors.grey : null),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red, width: 1),
                    ),
                    child: const Text(
                      'CONNECTED',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isWeak)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange, width: 1),
                    ),
                    child: const Text(
                      'WEAK',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              macAddress,
              style: TextStyle(color: isBusy ? Colors.grey : null),
            ),
            trailing: Text(
              "${r.rssi} dBm",
              style: TextStyle(color: isBusy ? Colors.grey : null),
            ),
            onTap: isBusy
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Questo ESP32 è già connesso a un altro dispositivo",
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                : () async {
                    try {
                      await _service.connectTo(r);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      // Se errore 133 o timeout, probabilmente è occupato
                      if (e.toString().contains('133') ||
                          e.toString().toLowerCase().contains('timeout')) {
                        setState(() {
                          _busyDevices.add(macAddress);
                        });
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Connessione fallita: $e"),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
          );
        },
      ),
    );
  }
}
