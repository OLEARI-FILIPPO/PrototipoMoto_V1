# Modifiche Mesh Network - 28 Dicembre 2025

## Panoramica
Implementata rete mesh completa dove ogni ESP32 trasmette informazioni su **TUTTI** i peer che vede, non solo uno.

## Modifiche agli Sketch ESP32

### Cambiamenti Comuni (MotoA e MotoB)

#### 1. Array di Peer invece di singolo peer
**Prima:**
```cpp
static int lastPeerRssi = -127;
static unsigned long lastPeerSeenMs = 0;
static String lastPeerName = "";
```

**Dopo:**
```cpp
struct PeerInfo {
  String name;
  int rssi;
  unsigned long lastSeenMs;
};

#define MAX_PEERS 10
PeerInfo peers[MAX_PEERS];
int peerCount = 0;
```

#### 2. Funzioni Helper per gestione peer
**Nuove funzioni:**
- `updatePeer(name, rssi)` - Aggiunge o aggiorna un peer nell'array
- `cleanupOldPeers()` - Rimuove peer non visti da 5 secondi
- `jsonPeerMessage()` - Genera JSON con array di tutti i peer

**Formato JSON nuovo:**
```json
{
  "peers": [
    {"id": "ESP32_S3_BLE_A", "rssi": -65, "dist": 2.34},
    {"id": "ESP32_S3_BLE_C", "rssi": -72, "dist": 5.12}
  ],
  "src": "B"
}
```

**Formato JSON vecchio:**
```json
{"peer": "ESP32_S3_BLE_A", "dist": 2.34, "rssi": -65, "src": "B"}
```

#### 3. Callback di Scan aggiornato
**Ora salva TUTTI i peer:**
```cpp
void onResult(BLEAdvertisedDevice advertisedDevice) override {
  // ... validazione ...
  
  // In CONNECTED o SEARCHING, salva info su TUTTI i peer
  if (currentState == CONNECTED || currentState == SEARCHING) {
    updatePeer(peerName, advertisedDevice.getRSSI());
  }
}
```

#### 4. Loop() aggiornato
**Aggiunte:**
- Chiamata a `cleanupOldPeers()` ogni ciclo
- Telemetria invia `jsonPeerMessage()` senza parametri
- Scan interval aumentato a 3 secondi per migliore copertura
- Comando STATUS nel serial per debug

**Comandi Serial disponibili:**
- `PAIRING` / `STARTPAIRING`
- `SEARCHING` / `STARTSEARCHING`
- `IDLE` / `STOPMODE`
- `STATUS` - mostra stato corrente e numero di peer

## Modifiche Flutter

### network_view_screen.dart

#### Parsing JSON aggiornato
**Prima:** Parsava singolo peer con regex semplici

**Dopo:** Parsa array di peer:
```dart
void _parseAndUpdateNodes(List<int> payload) {
  // Cerca array peers: {"peers":[...]}
  final peersMatch = RegExp(r'"peers":\s*\[([^\]]*)\]').firstMatch(message);
  
  // Parse ogni oggetto peer: {"id":"...","rssi":...,"dist":...}
  final peerObjects = RegExp(r'\{[^\}]+\}').allMatches(peersArrayStr);
  
  // Aggiorna o aggiungi ogni peer alla lista _nodes
  for (final peerMatch in peerObjects) {
    // ... parsing e aggiornamento nodi ...
  }
}
```

## Comportamento della Rete Mesh

### Scenario 3 dispositivi (ESP32_A, ESP32_B, ESP32_C)

1. **ESP32_A in PAIRING** (LED rosso)
   - Advertise state=1
   - Non fa scan
   - Telemetria: `{"peers":[],"src":"A"}` (nessun peer visibile)

2. **ESP32_B in SEARCHING** (LED blu)
   - Advertise state=2
   - Fa scan e trova A (state=1)
   - Transizione automatica a CONNECTED
   - Continua scan e vede A e C
   - Telemetria: `{"peers":[{"id":"ESP32_S3_BLE_A","rssi":-65,"dist":2.3},{"id":"ESP32_S3_BLE_C","rssi":-72,"dist":5.1}],"src":"B"}`

3. **ESP32_C in SEARCHING** (LED blu)
   - Advertise state=2
   - Fa scan e trova A (state=1)
   - Transizione automatica a CONNECTED
   - Continua scan e vede A e B
   - Telemetria: `{"peers":[{"id":"ESP32_S3_BLE_A","rssi":-63,"dist":2.1},{"id":"ESP32_S3_BLE_B","rssi":-72,"dist":5.1}],"src":"C"}`

### Network View su Smartphone

Ogni smartphone connesso a un ESP32 mostra:
- **Dispositivo locale**: ESP32 connesso al telefono
- **Tutti i peer**: Tutti gli ESP32 visibili dal dispositivo locale
- **Distanze**: Calcolate da RSSI
- **Colori distanza**: Verde (<3m), Arancione (3-7m), Rosso (>7m)

## Vantaggi della Nuova Architettura

1. ✅ **Scalabilità**: Supporta fino a 10 peer simultanei (configurabile con MAX_PEERS)
2. ✅ **Vista completa**: Ogni smartphone vede TUTTA la rete mesh dal punto di vista del suo ESP32
3. ✅ **Ridondanza**: Se B vede A e C, e C vede A e B, abbiamo conferma della topologia
4. ✅ **Auto-cleanup**: Peer non visti da 5 secondi vengono rimossi automaticamente
5. ✅ **Debug migliorato**: Comando STATUS mostra stato e numero peer

## Test Consigliati

### Test Base (2 dispositivi)
1. ESP32_A → PAIRING
2. ESP32_B → SEARCHING
3. Verificare: B trova A e transita a CONNECTED
4. Network View su Phone-B mostra A

### Test Mesh (3+ dispositivi)
1. ESP32_A → PAIRING
2. ESP32_B → SEARCHING (trova A → CONNECTED)
3. ESP32_C → SEARCHING (trova A → CONNECTED)
4. Verificare:
   - B vede [A, C]
   - C vede [A, B]
   - Network View mostra tutti i nodi

### Test Timeout e Cleanup
1. Connetti 3 dispositivi
2. Spegni ESP32_A
3. Verificare: dopo 5 secondi A scompare da liste di B e C
4. Verificare: dopo 10 secondi A scompare da Network View

## File Modificati

### ESP32
- `sketch_ESP32_S3_BLE_Server/MotoA/sketch_ESP32_S3_BLE_Server/sketch_ESP32_S3_BLE_Server.ino`
- `sketch_ESP32_S3_BLE_Server/MotoB/sketch_ESP32_S3_BLE_Server_B/sketch_ESP32_S3_BLE_Server_B.ino`

**Modifiche identiche eccetto:**
- `DEVICE_ID`: "A" vs "B"
- `BLE_NAME`: "ESP32_S3_BLE_A" vs "ESP32_S3_BLE_B"

### Flutter
- `primo_progetto_flutter/lib/screens/network_view_screen.dart`

## Note Importanti

1. **Formato JSON retrocompatibile**: NO - vecchio formato `{"peer":"..."}` non più supportato
2. **Array vuoto**: `{"peers":[],"src":"A"}` è valido - significa nessun peer trovato
3. **Limite peers**: MAX_PEERS = 10, aumentabile cambiando la costante
4. **Scan interval**: 3 secondi per bilanciare copertura e responsività
5. **Cleanup**: Peer vecchi (>5s) rimossi lato ESP32, nodi vecchi (>10s) rimossi lato Flutter
6. **LED blinking**: Controllato da updateLedBlink() che richiede blinkColorA != 0

## Prossimi Passi

- [ ] Test con 3 ESP32 simultanei
- [ ] Ottimizzazione interval scan basato su densità rete
- [ ] Aggiunta stato peer nel JSON (IDLE/PAIRING/SEARCHING/CONNECTED)
- [ ] Visualizzazione grafo rete in Network View
- [ ] Filtro scan list: nascondere ESP32 già connessi (stato != IDLE/PAIRING)
