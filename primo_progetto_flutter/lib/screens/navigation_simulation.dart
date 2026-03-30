import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Waypoint reali Passo dello Stelvio (SS38 - tornanti lato Bormio)
// ---------------------------------------------------------------------------
const List<LatLng> _stelvioRoute = [
  LatLng(46.5283, 10.4536), // Partenza bassa
  LatLng(46.5291, 10.4549),
  LatLng(46.5301, 10.4556),
  LatLng(46.5308, 10.4548),
  LatLng(46.5311, 10.4537),
  LatLng(46.5306, 10.4526),
  LatLng(46.5295, 10.4521),
  LatLng(46.5289, 10.4531),
  LatLng(46.5286, 10.4545),
  LatLng(46.5292, 10.4557),
  LatLng(46.5302, 10.4563),
  LatLng(46.5314, 10.4559),
  LatLng(46.5322, 10.4548),
  LatLng(46.5325, 10.4534),
  LatLng(46.5318, 10.4522),
  LatLng(46.5306, 10.4517),
  LatLng(46.5297, 10.4524),
  LatLng(46.5293, 10.4538),
  LatLng(46.5299, 10.4552),
  LatLng(46.5310, 10.4561), // Arrivo tornante alto
];

// ---------------------------------------------------------------------------
// Modello moto
// ---------------------------------------------------------------------------
class _Moto {
  final int id;
  final String name;
  final Color color;
  double speedKmh;
  double dist; // distanza percorsa in metri (vera)
  bool reverse = false;
  bool isLeader = false;

  // --- Visibilità mesh ---
  /// true se NESSUNO riesce a ricevere dati da questa moto
  /// (tutti i link TX di questa moto sono blocked/lost verso tutti)
  bool isBlind = false;

  /// Posizione "congelata" sull'ultima posizione nota prima del blackout
  LatLng? lastKnownPos;

  /// Tick in cui è iniziato il blackout (per stimare il salto)
  int? blindSinceTick;

  _Moto({
    required this.id,
    required this.name,
    required this.color,
    this.speedKmh = 0,
    this.dist = 0,
  });
}

// ---------------------------------------------------------------------------
// Log
// ---------------------------------------------------------------------------
class _SimLog {
  final String msg;
  final DateTime time;
  _SimLog(this.msg) : time = DateTime.now();

  String get label =>
      '[${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}] $msg';
}

// ---------------------------------------------------------------------------
// Dati che una moto "riceve" da un'altra nel mesh
// ---------------------------------------------------------------------------
enum _LinkStatus {
  direct,    // pacchetto ricevuto direttamente
  relayed,   // ricevuto via moto-ponte (rumore aggiunto)
  lost,      // pacchetto droppato, nessun relay disponibile
  blocked,   // interferenza manuale attivata dall'utente
}

class _MeshPacket {
  final double distM;       // distanza reale del mittente (m)
  final double speedKmh;    // velocità reale del mittente
  final _LinkStatus status; // come è arrivato (o non arrivato)
  final double noiseM;      // errore di distanza introdotto dal relay (m)
  final String? relayName;  // nome della moto ponte (se relayed)

  const _MeshPacket({
    required this.distM,
    required this.speedKmh,
    required this.status,
    this.noiseM = 0.0,
    this.relayName,
  });

  /// Valore di distanza che il ricevitore "vede" (con rumore se relayed)
  double get perceivedDistM => distM + noiseM;

  bool get isBlocked => status == _LinkStatus.blocked;
  bool get isLost    => status == _LinkStatus.lost;
  bool get isRelayed => status == _LinkStatus.relayed;
  bool get isDirect  => status == _LinkStatus.direct;
}

// ---------------------------------------------------------------------------
// Screen principale
// ---------------------------------------------------------------------------
class NavigationSimulationScreen extends StatefulWidget {
  const NavigationSimulationScreen({super.key});

  @override
  State<NavigationSimulationScreen> createState() =>
      _NavSimState();
}

class _NavSimState extends State<NavigationSimulationScreen> {
  static const int _dtMs = 1000 ~/ 60; // 60 fps

  final MapController _map = MapController();
  final Distance _geo = const Distance();

  late final List<double> _cumDist;
  late final double _totalDist;

  late final List<_Moto> _motos;
  final List<_SimLog> _logs = [];
  Map<int, LatLng> _pos = {};

  // Posizioni visibili in mappa: congelate durante blackout
  Map<int, LatLng> _visiblePos = {};

  // Mesh: _blocked[tx] = {rx, rx} → interferenza manuale
  final Map<int, Set<int>> _blocked = {};

  // Ultima lettura mesh: _mesh[receiverId][senderId] = packet
  Map<int, Map<int, _MeshPacket>> _mesh = {};

  // Tab panel inferiore: 0 = log, 1 = mesh
  int _bottomTab = 0;

  // POV selezionato: null = vista globale, altrimenti id della moto
  int? _selectedPov;

  // Contatore tick (1 tick = ~16 ms a 60 fps)
  int _tickCount = 0;

  // Ogni quanti tick simulare un packet-loss periodico (30 s)
  static const int _lossIntervalTicks = 30 * 60; // 30 s × 60 fps

  // Random per rumore di misura
  final math.Random _rng = math.Random();

  // Flag: la moto "ponte" (id=2) è disabilitata manualmente dall'utente?
  // (separato da _blocked per chiarezza semantica)
  // → usa _blocked come unica sorgente di verità

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _buildCumDist();
    _motos = [
      _Moto(id: 1, name: 'Moto A', color: Colors.blue,   speedKmh: 30, dist: 200),
      _Moto(id: 2, name: 'Moto B', color: Colors.orange, speedKmh: 20, dist: 100),
      _Moto(id: 3, name: 'Moto C', color: Colors.green,  speedKmh: 15, dist: 0),
    ];
    _recalcLeader(log: false);
    for (var m in _motos) {
      _pos[m.id] = _interpolate(m.dist);
      _visiblePos[m.id] = _interpolate(m.dist);
      _blocked[m.id] = {}; // nessuna interferenza iniziale
    }
    _buildMesh();
    _log('Simulazione avviata al Passo dello Stelvio');
    debugPrint('[SIM] Simulazione avviata – Passo dello Stelvio');
    _timer = Timer.periodic(Duration(milliseconds: _dtMs), (_) => _tick());
  }

  void _buildCumDist() {
    final List<double> c = [0];
    double d = 0;
    for (int i = 0; i < _stelvioRoute.length - 1; i++) {
      d += _geo.as(LengthUnit.Meter, _stelvioRoute[i], _stelvioRoute[i + 1]);
      c.add(d);
    }
    _cumDist = c;
    _totalDist = d;
  }

  void _tick() {
    _tickCount++;
    final double dtSec = _dtMs / 1000.0;
    final List<int> oldRank = _ranked();

    for (final m in _motos) {
      if (m.speedKmh <= 0) continue;
      final double step = (m.speedKmh / 3.6) * dtSec;
      if (!m.reverse) {
        m.dist += step;
        if (m.dist >= _totalDist) {
          m.dist = _totalDist;
          m.reverse = true;
          _log('${m.name} → capolinea, torna indietro');
          debugPrint('[SIM] ${m.name} → capolinea');
        }
      } else {
        m.dist -= step;
        if (m.dist <= 0) {
          m.dist = 0;
          m.reverse = false;
          _log('${m.name} → partenza, riparte in avanti');
          debugPrint('[SIM] ${m.name} → riparte in avanti');
        }
      }
    }

    final List<int> newRank = _ranked();
    for (int i = 0; i < newRank.length - 1; i++) {
      final int id = newRank[i];
      final int oldIdx = oldRank.indexOf(id);
      if (oldIdx > i) {
        final String a = _motos.firstWhere((m) => m.id == id).name;
        final String b = _motos.firstWhere((m) => m.id == newRank[i + 1]).name;
        _log('🏁 $a ha superato $b!');
      }
    }

    _recalcLeader(log: true);
    _buildMesh();
    _updateBlindness();

    // Aggiorna posizione reale e visibile
    final Map<int, LatLng> newPos = {};
    final Map<int, LatLng> newVisible = {};
    for (final m in _motos) {
      final LatLng real = _interpolate(m.dist);
      newPos[m.id] = real;
      if (m.isBlind) {
        // Congela la posizione visibile sull'ultima nota
        newVisible[m.id] = m.lastKnownPos ?? real;
      } else {
        newVisible[m.id] = real;
        m.lastKnownPos = real;
      }
    }

    setState(() {
      _pos = newPos;
      _visiblePos = newVisible;
    });
  }

  List<int> _ranked() {
    final List<_Moto> s = List.from(_motos)
      ..sort((a, b) => b.dist.compareTo(a.dist));
    return s.map((m) => m.id).toList();
  }

  void _recalcLeader({required bool log}) {
    // Il leader è chi è più avanti IN AVANTI (non in retromarcia).
    // Se tutti stanno tornando indietro, mantieni il leader corrente.
    final goingForward = _motos.where((m) => !m.reverse).toList()
      ..sort((a, b) => b.dist.compareTo(a.dist));

    final _Moto? candidate = goingForward.isNotEmpty ? goingForward.first : null;

    // Se nessuno va avanti, non cambiare leader
    if (candidate == null) return;

    // Cambia leader solo se il candidato ha superato l'attuale leader
    final current = _motos.firstWhere((m) => m.isLeader, orElse: () => _motos.first);
    if (candidate.id == current.id) return;

    // Il candidato deve essere effettivamente davanti al leader corrente
    if (candidate.dist <= current.dist) return;

    final bool changed = true;
    for (final m in _motos) {
      m.isLeader = false;
    }
    candidate.isLeader = true;
    if (changed && log) {
      _log('⭐ ${candidate.name} è il nuovo LEADER');
      debugPrint('[SIM] ⭐ ${candidate.name} è il nuovo LEADER (dist: ${candidate.dist.toStringAsFixed(0)} m)');
    }
  }

  // ---------------------------------------------------------------------------
  // Mesh helpers
  // ---------------------------------------------------------------------------

  /// Determina se il link diretto TX→RX è soggetto a packet-loss periodico.
  /// Si applica solo al link leader↔ultimo (i due estremi della catena).
  bool _isPeriodicLossTick(int txId, int rxId) {
    // Identifica leader e ultimo in base alla posizione attuale
    final sorted = List<_Moto>.from(_motos)
      ..sort((a, b) => b.dist.compareTo(a.dist));
    final leaderId = sorted.first.id;
    final lastId   = sorted.last.id;

    // Solo il link diretto tra i due estremi è soggetto al drop periodico
    final isExtremePair =
        (txId == leaderId && rxId == lastId) ||
        (txId == lastId   && rxId == leaderId);

    if (!isExtremePair) return false;

    // Drop ogni _lossIntervalTicks per 3 tick (≈ 50 ms) → simula un singolo
    // pacchetto perso
    final phase = _tickCount % _lossIntervalTicks;
    return phase < 3;
  }

  /// Ricalcola la tabella mesh con logica completa:
  ///   1. Link manualmente bloccato    → _LinkStatus.blocked
  ///   2. Packet-loss periodico diretto AND relay disponibile
  ///                                   → _LinkStatus.relayed  (con rumore)
  ///   3. Packet-loss periodico diretto AND relay NON disponibile
  ///                                   → _LinkStatus.lost
  ///   4. Nessun problema              → _LinkStatus.direct
  void _buildMesh() {
    final sorted = List<_Moto>.from(_motos)
      ..sort((a, b) => b.dist.compareTo(a.dist));
    // La moto "ponte" è quella in posizione mediana (indice 1 su 3)
    final _Moto? bridge = sorted.length >= 3 ? sorted[1] : null;

    final Map<int, Map<int, _MeshPacket>> table = {};

    for (final rx in _motos) {
      final Map<int, _MeshPacket> row = {};

      for (final tx in _motos) {
        if (tx.id == rx.id) continue;

        // 1. Interferenza manuale
        if (_blocked[tx.id]?.contains(rx.id) ?? false) {
          row[tx.id] = _MeshPacket(
            distM: tx.dist,
            speedKmh: tx.speedKmh,
            status: _LinkStatus.blocked,
          );
          continue;
        }

        // 2. Packet-loss periodico sul link diretto?
        if (_isPeriodicLossTick(tx.id, rx.id)) {
          // Prova relay attraverso la moto ponte
          if (bridge != null &&
              bridge.id != tx.id &&
              bridge.id != rx.id) {
            // Link tx→bridge e bridge→rx devono essere entrambi liberi
            final txBridgeOk  = !(_blocked[tx.id]?.contains(bridge.id)     ?? false);
            final bridgeRxOk  = !(_blocked[bridge.id]?.contains(rx.id)     ?? false);

            if (txBridgeOk && bridgeRxOk) {
              // Relay riuscito: aggiungi rumore gaussiano ≈ ±5 m
              final noise = (_rng.nextDouble() - 0.5) * 10.0;
              row[tx.id] = _MeshPacket(
                distM: tx.dist,
                speedKmh: tx.speedKmh,
                status: _LinkStatus.relayed,
                noiseM: noise,
                relayName: bridge.name,
              );
              _logOnce(
                '🔁 RELAY ${tx.name}→${rx.name} via ${bridge.name} '
                '(errore dist: ${noise.toStringAsFixed(1)} m)',
                tag: 'relay_${tx.id}_${rx.id}_${_tickCount ~/ _lossIntervalTicks}',
              );
            } else {
              // Relay non disponibile → pacchetto perso
              row[tx.id] = _MeshPacket(
                distM: tx.dist,
                speedKmh: tx.speedKmh,
                status: _LinkStatus.lost,
              );
              _logOnce(
                '❌ LOST ${tx.name}→${rx.name}: relay ${bridge.name} anch\'esso bloccato!',
                tag: 'lost_${tx.id}_${rx.id}_${_tickCount ~/ _lossIntervalTicks}',
              );
            }
          } else {
            // Nessun bridge disponibile
            row[tx.id] = _MeshPacket(
              distM: tx.dist,
              speedKmh: tx.speedKmh,
              status: _LinkStatus.lost,
            );
          }
          continue;
        }

        // 3. Link diretto OK
        row[tx.id] = _MeshPacket(
          distM: tx.dist,
          speedKmh: tx.speedKmh,
          status: _LinkStatus.direct,
        );
      }

      table[rx.id] = row;
    }

    _mesh = table;
  }

  // Logga un messaggio solo una volta per tag (evita spam a 60fps)
  final Set<String> _loggedTags = {};
  void _logOnce(String msg, {required String tag}) {
    if (_loggedTags.contains(tag)) return;
    _loggedTags.add(tag);
    _log(msg);
    debugPrint('[MESH] $msg');
  }

  // ---------------------------------------------------------------------------
  // Visibilità moto: blackout e riapparizione
  // ---------------------------------------------------------------------------

  /// Una moto è "cieca" (invisible agli altri) se TUTTE le altre moto
  /// non riescono a riceverla (tutti i link TX→* di quella moto sono
  /// blocked o lost).
  void _updateBlindness() {
    for (final tx in _motos) {
      // Conta quante moto ricevono dati da tx
      int rxCount = 0;
      int blindCount = 0;
      for (final rx in _motos) {
        if (rx.id == tx.id) continue;
        rxCount++;
        final packet = _mesh[rx.id]?[tx.id];
        if (packet == null ||
            packet.status == _LinkStatus.blocked ||
            packet.status == _LinkStatus.lost) {
          blindCount++;
        }
      }

      final wasBlind = tx.isBlind;
      tx.isBlind = rxCount > 0 && blindCount == rxCount;

      if (tx.isBlind && !wasBlind) {
        // Inizia blackout
        tx.blindSinceTick = _tickCount;
        _logOnce(
          '❓ ${tx.name} scomparsa dalla rete! (pos. congelata)',
          tag: 'blind_start_${tx.id}_$_tickCount',
        );
      } else if (!tx.isBlind && wasBlind) {
        // Fine blackout → stima posizione avanzata
        final blindTicks = _tickCount - (tx.blindSinceTick ?? _tickCount);
        final double elapsed = blindTicks * _dtMs / 1000.0; // secondi
        final double estimated = tx.dist; // dist è già aggiornata internamente
        final String dir = tx.reverse ? '←' : '→';
        _logOnce(
          '📍 ${tx.name} riappare: era a ${estimated.toStringAsFixed(0)} m '
          '(assente ${elapsed.toStringAsFixed(1)} s, dir $dir)',
          tag: 'blind_end_${tx.id}_$_tickCount',
        );
        debugPrint('[MESH] 📍 ${tx.name} riappare dopo ${elapsed.toStringAsFixed(1)} s '
            '– posizione stimata: ${estimated.toStringAsFixed(0)} m');
        tx.blindSinceTick = null;
      }
    }
  }

  /// Inverte lo stato del link TX → RX (interferenza on/off).
  void _toggleLink(int txId, int rxId) {
    setState(() {
      final set = _blocked[txId] ??= {};
      if (set.contains(rxId)) {
        set.remove(rxId);
        final txName = _motos.firstWhere((m) => m.id == txId).name;
        final rxName = _motos.firstWhere((m) => m.id == rxId).name;
        _log('📶 Link $txName → $rxName ripristinato');
        debugPrint('[MESH] 📶 Link $txName → $rxName ripristinato');
      } else {
        set.add(rxId);
        final txName = _motos.firstWhere((m) => m.id == txId).name;
        final rxName = _motos.firstWhere((m) => m.id == rxId).name;
        _log('⚡ Interferenza $txName → $rxName attivata');
        debugPrint('[MESH] ⚡ Interferenza $txName → $rxName attivata');
        // Pulisci i tag di "relay/lost" per questo link così si riloggano
        _loggedTags.removeWhere((t) =>
            t.startsWith('relay_${txId}_$rxId') ||
            t.startsWith('lost_${txId}_$rxId'));
      }
      _buildMesh();
    });
  }

  void _log(String msg) {
    _logs.insert(0, _SimLog(msg));
    if (_logs.length > 60) _logs.removeLast();
  }

  LatLng _interpolate(double dist) {
    if (dist <= 0) return _stelvioRoute.first;
    if (dist >= _totalDist) return _stelvioRoute.last;
    for (int i = 0; i < _cumDist.length - 1; i++) {
      if (dist >= _cumDist[i] && dist <= _cumDist[i + 1]) {
        final double len = _cumDist[i + 1] - _cumDist[i];
        final double f = (dist - _cumDist[i]) / len;
        final LatLng a = _stelvioRoute[i];
        final LatLng b = _stelvioRoute[i + 1];
        return LatLng(
          a.latitude  + (b.latitude  - a.latitude)  * f,
          a.longitude + (b.longitude - a.longitude) * f,
        );
      }
    }
    return _stelvioRoute.last;
  }

  // Scia ambrata: dal veicolo più indietro al leader
  List<LatLng> _trail() {
    if (_motos.isEmpty) return [];
    final double minD = _motos.map((m) => m.dist).reduce(math.min);
    final double maxD = _motos.map((m) => m.dist).reduce(math.max);
    if ((maxD - minD) < 1) return [];
    final List<LatLng> pts = [_interpolate(minD)];
    for (int i = 0; i < _stelvioRoute.length; i++) {
      if (_cumDist[i] > minD && _cumDist[i] < maxD) pts.add(_stelvioRoute[i]);
    }
    pts.add(_interpolate(maxD));
    return pts;
  }

  // ---------------------------------------------------------------------------
  // POV helpers
  // ---------------------------------------------------------------------------

  /// Restituisce la posizione che il veicolo [povId] "vede" per [targetId].
  /// - Se stesso → posizione reale (sempre nota)
  /// - Link RX ok (direct/relayed) → posizione basata sul dato ricevuto
  /// - Link RX lost/blocked → null (moto sconosciuta per questo POV)
  LatLng? _povPositionOf(int povId, int targetId) {
    if (povId == targetId) return _pos[targetId];

    final packet = _mesh[povId]?[targetId];
    if (packet == null) return null;

    switch (packet.status) {
      case _LinkStatus.direct:
        return _interpolate(packet.distM);
      case _LinkStatus.relayed:
        // Posizione con rumore già contenuto in perceivedDistM
        return _interpolate(packet.perceivedDistM.clamp(0, _totalDist));
      case _LinkStatus.lost:
      case _LinkStatus.blocked:
        return null; // il POV non sa dove si trova
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _Moto leader =
        _motos.firstWhere((m) => m.isLeader, orElse: () => _motos.first);

    final pov = _selectedPov != null
        ? _motos.firstWhere((m) => m.id == _selectedPov)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: pov == null
            ? const Text('Stelvio – Simulazione Moto')
            : Row(children: [
                Icon(Icons.visibility, color: pov.color, size: 16),
                const SizedBox(width: 6),
                Text('Vista da: ${pov.name}',
                    style: TextStyle(color: pov.color, fontSize: 15)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _selectedPov = null),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('GLOBALE',
                        style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ),
              ]),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── MAPPA ──────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: LatLng(46.5301, 10.4540),
                    initialZoom: 16.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.primo_progetto_flutter',
                    ),
                    PolylineLayer(polylines: [
                      Polyline(
                        points: _stelvioRoute,
                        strokeWidth: 5,
                        color: Colors.white24,
                      ),
                      if (_trail().length >= 2)
                        Polyline(
                          points: _trail(),
                          strokeWidth: 5,
                          color: Colors.amber.withOpacity(0.85),
                        ),
                    ]),
                    MarkerLayer(
                      markers: _motos.map((m) {
                        LatLng? p;
                        bool isUnknown = false;

                        if (pov == null) {
                          // Vista globale: usa posizione visibile reale
                          p = _visiblePos[m.id] ?? _pos[m.id];
                          isUnknown = m.isBlind;
                        } else {
                          // Vista soggettiva del POV
                          p = _povPositionOf(pov.id, m.id);
                          if (p == null) {
                            // Il POV non conosce questa moto:
                            // mostra ultima posizione nota congelata
                            p = _visiblePos[m.id] ?? _pos[m.id];
                            isUnknown = true;
                          }
                        }

                        if (p == null) {
                          return const Marker(
                              point: LatLng(0, 0),
                              child: SizedBox.shrink());
                        }

                        // Usa un _MotoView per l'icona (con isBlind sovrascrivibile)
                        final displayMoto =
                            _MotoView.from(m, overrideBlind: isUnknown);

                        return Marker(
                          point: p,
                          width: m.isLeader ? 44 : 32,
                          height: m.isLeader ? 44 : 32,
                          child: _MotoIcon(moto: displayMoto),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                // FAB centra sul leader (o sul POV)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    onPressed: () {
                      final focusId = pov?.id ?? leader.id;
                      final p = _visiblePos[focusId] ?? _pos[focusId];
                      if (p != null) _map.move(p, _map.camera.zoom);
                    },
                    child: Icon(Icons.my_location,
                        color: pov?.color ?? Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // ── SELECTOR + SLIDER VELOCITÀ ────────────────────────────
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Row(
              children: _motos.map((m) {
                final isSelected = _selectedPov == m.id;
                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsante selezione POV
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectedPov = isSelected ? null : m.id;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? m.color.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  isSelected ? m.color : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                m.isLeader
                                    ? Icons.star_rounded
                                    : (m.isBlind
                                        ? Icons.question_mark_rounded
                                        : Icons.two_wheeler),
                                color: m.isBlind ? Colors.grey : m.color,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  m.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: m.isBlind
                                        ? Colors.grey
                                        : m.color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.visibility,
                                    color: m.color, size: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Text(
                        '${m.speedKmh.round()} km/h',
                        style: TextStyle(
                            color: m.color.withValues(alpha: 0.7),
                            fontSize: 9),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: m.color,
                          thumbColor: m.color,
                          inactiveTrackColor:
                              m.color.withOpacity(0.2),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10),
                        ),
                        child: Slider(
                          value: m.speedKmh,
                          min: 0,
                          max: 50,
                          onChanged: (v) =>
                              setState(() => m.speedKmh = v),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // ── PANNELLO INFERIORE (LOG / MESH) ────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: Column(
                children: [
                  // Tab bar
                  Row(
                    children: [
                      _TabBtn(
                        label: 'LOG EVENTI',
                        active: _bottomTab == 0,
                        onTap: () => setState(() => _bottomTab = 0),
                      ),
                      _TabBtn(
                        label: 'MESH NETWORK',
                        active: _bottomTab == 1,
                        onTap: () => setState(() => _bottomTab = 1),
                      ),
                    ],
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: _bottomTab == 0
                        ? _buildLogPanel()
                        : _buildMeshPanel(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Log panel ────────────────────────────────────────────────────────────
  Widget _buildLogPanel() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _logs.length,
      itemBuilder: (_, i) => Text(
        _logs[i].label,
        style: const TextStyle(
            color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
      ),
    );
  }

  // ── Mesh panel ───────────────────────────────────────────────────────────
  Widget _buildMeshPanel() {
    // Colonne = mittenti (TX), righe = destinatari (RX)
    final ids = _motos.map((m) => m.id).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legenda
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Tocca una cella per simulare interferenza su quel link TX→RX',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          // Intestazione colonne (TX)
          Table(
            border: TableBorder.all(color: Colors.white12),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FlexColumnWidth(1.4), // etichetta RX
              for (int i = 0; i < ids.length; i++) i + 1: const FlexColumnWidth(1.6),
            },
            children: [
              // Header row
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('RX \\ TX',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                  ...ids.map((txId) {
                    final tx = _motos.firstWhere((m) => m.id == txId);
                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.two_wheeler, color: tx.color, size: 12),
                          const SizedBox(width: 2),
                          Text(tx.name,
                              style: TextStyle(
                                  color: tx.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
              // Data rows
              ...ids.map((rxId) {
                final rx = _motos.firstWhere((m) => m.id == rxId);
                return TableRow(
                  children: [
                    // RX label
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Icon(Icons.two_wheeler, color: rx.color, size: 12),
                          const SizedBox(width: 2),
                          Text(rx.name,
                              style: TextStyle(
                                  color: rx.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    // One cell per TX
                    ...ids.map((txId) {
                      if (txId == rxId) {
                        // Diagonale principale
                        return Container(
                          color: Colors.white.withValues(alpha: 0.04),
                          padding: const EdgeInsets.all(6),
                          child: const Center(
                            child: Text('—',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                          ),
                        );
                      }
                      final packet = _mesh[rxId]?[txId];
                      final status = packet?.status ?? _LinkStatus.direct;

                      // Colore di sfondo per status
                      Color bgColor;
                      switch (status) {
                        case _LinkStatus.blocked:
                          bgColor = Colors.red.withValues(alpha: 0.22);
                        case _LinkStatus.lost:
                          bgColor = Colors.orange.withValues(alpha: 0.22);
                        case _LinkStatus.relayed:
                          bgColor = Colors.yellow.withValues(alpha: 0.12);
                        case _LinkStatus.direct:
                          bgColor = Colors.green.withValues(alpha: 0.08);
                      }

                      Widget cellContent;
                      switch (status) {
                        case _LinkStatus.blocked:
                          cellContent = Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.signal_wifi_off,
                                  color: Colors.red, size: 14),
                              SizedBox(height: 2),
                              Text('BLOCCATO',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold)),
                            ],
                          );
                        case _LinkStatus.lost:
                          cellContent = Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 14),
                              SizedBox(height: 2),
                              Text('PERSO',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold)),
                            ],
                          );
                        case _LinkStatus.relayed:
                          cellContent = Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.repeat,
                                      color: Colors.yellow, size: 10),
                                  const SizedBox(width: 2),
                                  Text(packet!.relayName ?? '?',
                                      style: const TextStyle(
                                          color: Colors.yellow,
                                          fontSize: 8)),
                                ],
                              ),
                              Text(
                                '${packet.perceivedDistM.toStringAsFixed(0)} m',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.yellow, fontSize: 10),
                              ),
                              Text(
                                '±${packet.noiseM.abs().toStringAsFixed(1)}m',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.yellow, fontSize: 8),
                              ),
                              Text(
                                '${packet.speedKmh.toStringAsFixed(0)} km/h',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 9),
                              ),
                            ],
                          );
                        case _LinkStatus.direct:
                          cellContent = Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                packet != null
                                    ? '${packet.distM.toStringAsFixed(0)} m'
                                    : '—',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10),
                              ),
                              Text(
                                packet != null
                                    ? '${packet.speedKmh.toStringAsFixed(0)} km/h'
                                    : '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 9),
                              ),
                            ],
                          );
                      }

                      return GestureDetector(
                        onTap: () => _toggleLink(txId, rxId),
                        child: Container(
                          color: bgColor,
                          padding: const EdgeInsets.symmetric(
                              vertical: 5, horizontal: 3),
                          child: cellContent,
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          // Riepilogo link bloccati
          ..._blocked.entries.expand((e) {
            final txName = _motos.firstWhere((m) => m.id == e.key).name;
            return e.value.map((rxId) {
              final rxName = _motos.firstWhere((m) => m.id == rxId).name;
              return Chip(
                backgroundColor: Colors.red.withValues(alpha: 0.2),
                side: const BorderSide(color: Colors.red, width: 0.5),
                label: Text('⚡ $txName → $rxName',
                    style:
                        const TextStyle(color: Colors.red, fontSize: 10)),
                deleteIcon:
                    const Icon(Icons.close, size: 14, color: Colors.red),
                onDeleted: () => _toggleLink(e.key, rxId),
              );
            });
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MotoView – snapshot immutabile per la UI (evita mutation durante build)
// ---------------------------------------------------------------------------
class _MotoView {
  final String name;
  final Color color;
  final bool isLeader;
  final bool isBlind;

  const _MotoView({
    required this.name,
    required this.color,
    required this.isLeader,
    required this.isBlind,
  });

  factory _MotoView.from(_Moto m, {bool? overrideBlind}) => _MotoView(
        name: m.name,
        color: m.color,
        isLeader: m.isLeader,
        isBlind: overrideBlind ?? m.isBlind,
      );
}

// ---------------------------------------------------------------------------
// _TabBtn – bottone tab per il pannello inferiore
// ---------------------------------------------------------------------------
class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? Colors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.amber : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icona moto colorata
// ---------------------------------------------------------------------------
class _MotoIcon extends StatelessWidget {
  const _MotoIcon({required this.moto});
  final _MotoView moto;

  @override
  Widget build(BuildContext context) {
    // Blackout / sconosciuta: cerchio grigio con ?
    if (moto.isBlind) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[850],
          border: Border.all(color: Colors.grey[500]!, width: 1.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.question_mark_rounded,
                color: Colors.grey[400], size: moto.isLeader ? 20 : 14),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: moto.color),
              ),
            ),
          ],
        ),
      );
    }

    // Normale
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: moto.color,
        border:
            Border.all(color: Colors.white, width: moto.isLeader ? 2.5 : 1.5),
        boxShadow: moto.isLeader
            ? [
                BoxShadow(
                    color: moto.color.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 2)
              ]
            : null,
      ),
      child: Icon(
        moto.isLeader ? Icons.star_rounded : Icons.two_wheeler,
        color: Colors.white,
        size: moto.isLeader ? 22 : 15,
      ),
    );
  }
}
