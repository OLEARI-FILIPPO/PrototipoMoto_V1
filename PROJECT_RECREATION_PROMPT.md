# PROJECT RECREATION PROMPT
## Prompt Completo per Ricreare l'Applicazione Mesh Network BLE

**Versione:** 1.0  
**Data:** 22 Gennaio 2026  
**Scopo:** Backup testuale completo per ricreare il progetto da zero

---

## 📋 PROMPT DA DARE ALL'AI ASSISTANT

Copia e incolla questo prompt ad un AI Assistant (GitHub Copilot, ChatGPT, Claude, ecc.) per ricreare il progetto:

---

### PROMPT INIZIALE

```
Crea un sistema completo di mesh networking BLE con le seguenti specifiche:

OBIETTIVO:
Sviluppare un'applicazione Flutter Android che comunica con dispositivi ESP32-S3 tramite BLE, 
creando una rete mesh dove i nodi possono propagare informazioni sui peer anche attraverso 
nodi intermediari (propagazione multi-hop con 1 hop).

COMPONENTI DA CREARE:

1. APP FLUTTER (Android):
   - Linguaggio: Dart/Flutter
   - Target: Android API 33+
   - Package: flutter_blue_plus, permission_handler, geolocator, objectbox

2. FIRMWARE ESP32 (3 varianti):
   - Hardware: ESP32-S3 DevKit
   - IDE: Arduino IDE 2.x
   - Librerie: BLEDevice, BLEServer, ArduinoJson
   - 3 ESP32 con ID: A, B, C

ARCHITETTURA:

┌─────────────┐ BLE  ┌─────────────┐ BLE-Mesh ┌─────────────┐ BLE  ┌─────────────┐
│ Smartphone A│◄────►│  ESP32-A    │◄────────►│  ESP32-B    │◄────►│ Smartphone B│
└─────────────┘      └─────────────┘          └─────────────┘      └─────────────┘
                                               BLE-Mesh
                                                   │
                                                   ▼
                                           ┌─────────────┐
                                           │  ESP32-C    │
                                           └─────────────┘

FUNZIONALITÀ CHIAVE:

1. STATI DEL SISTEMA:
   - IDLE: Inattivo, LED spento
   - PAIRING: Connessione BLE in corso, LED rosso lampeggiante (500ms)
   - SEARCHING: Scansione mesh attiva, LED blu lampeggiante (500ms)
   - CONNECTED: Mesh attiva, LED blu-verde alternato (500ms)

2. COMUNICAZIONE BLE:
   - Service UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b
   - Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8
   - Formato messaggi: JSON
   - Esempio messaggio ESP32→Phone:
     {
       "peers": [
         {"id":"ESP32_S3_BLE_B","rssi":-25,"dist":0.02},
         {"id":"ESP32_S3_BLE_C","rssi":-48,"dist":0.15,"via":"B"}
       ],
       "src":"A"
     }

3. PROPAGAZIONE MESH:
   - Ogni ESP32 include nell'advertising BLE (Manufacturer Data) i peer che vede
   - Formato Manufacturer Data: [0xFF 0xFF State ID1 RSSI1 ID2 RSSI2 ...]
   - Altri ESP32 parsano questo dato e aggiungono peer INDIRETTI
   - Campo "via" identifica il nodo intermediario

4. PARAMETRI TECNICI:
   - SCAN_INTERVAL: 3000ms
   - SCAN_WINDOW: 1000ms
   - REPORT_INTERVAL: 3000ms (invio JSON)
   - PEER_TIMEOUT: 8000ms
   - DIRECT_PRIORITY_WINDOW: 2000ms (priorità peer diretti)
   - MAX_PEERS: 20
   - MAX_ADVERTISED_PEERS: 14 (limite payload BLE)
   - LED_BLINK_INTERVAL: 500ms

5. CONVERSIONE RSSI → DISTANZA:
   Formula: dist = 10 ^ ((RSSI_1m - RSSI) / (10 * n))
   Dove:
   - RSSI_1m = -59 dBm (calibrato a 1 metro)
   - n = 2.0 (path loss exponent per free space)

6. CALCOLI MESH:
   - RSSI approssimato per peer indiretti: RSSI_totale = RSSI(A→B) + RSSI(B→C)
   - Distanza cumulativa: Dist_totale = Dist(A→B) + Dist(B→C)

DETTAGLI IMPLEMENTAZIONE:

ESP32 FIRMWARE:
- File: sketch_ESP32_S3_BLE_Server.ino
- 3 varianti identiche tranne per:
  * String myDeviceId = "A"; (o "B" o "C")
  * String deviceName = "ESP32_S3_BLE_A"; (o B o C)

Funzioni principali ESP32:
1. setup():
   - Inizializza Serial (115200 baud)
   - Configura LED (GPIO 48, PWM)
   - Inizializza BLE server con UUID custom
   - Crea characteristic con NOTIFY + WRITE
   - Avvia advertising con manufacturer data

2. loop():
   - Gestisce stati (IDLE→PAIRING→SEARCHING→CONNECTED)
   - Aggiorna LED in base allo stato
   - In SEARCHING/CONNECTED:
     * Esegue scan BLE ogni SCAN_INTERVAL
     * Aggiorna manufacturer data con peer list
     * Invia JSON con peer list ogni REPORT_INTERVAL

3. onResult() (callback scan BLE):
   - Filtra solo dispositivi "ESP32_S3_BLE_*"
   - Aggiunge peer DIRETTO dalla connessione diretta
   - Parsa manufacturer data del peer
   - Aggiunge peer INDIRETTI trovati nel manufacturer data
   - Log dettagliati con emoji: 🔍 📡 ↪️ ➕

4. updatePeer():
   - Gestisce priorità: diretti > indiretti
   - DIRECT_PRIORITY_WINDOW: mantiene peer diretto per 2s
   - Upgrade automatico: indiretto→diretto quando possibile
   - Memorizza campo "via" per peer indiretti

5. jsonPeerMessage():
   - Crea JSON con array "peers"
   - Filtra peer scaduti (timeout)
   - Aggiunge campo "via" solo per indiretti
   - Log conteggio diretti/indiretti

6. updateAdvertisingData():
   - Crea manufacturer data: [0xFF 0xFF State ID1 RSSI1 ID2 RSSI2 ...]
   - Limita a MAX_ADVERTISED_PEERS (14)
   - Aggiorna advertising BLE

APP FLUTTER:
- File principale: lib/screens/network_view_screen.dart
- Service BLE: lib/services/ble_service.dart
- Modello dati: lib/models/device_node.dart

Classi principali Flutter:
1. DeviceNode (model):
   class DeviceNode {
     final String id;
     final String name;
     final int rssi;
     final double distance;
     final DeviceNodeState state;
     final DateTime lastUpdate;
     final String? via;  // Campo opzionale per peer indiretti
   }

2. NetworkViewScreen (UI):
   - Gestisce connessione BLE all'ESP32
   - Mostra lista nodi mesh
   - Pulsanti: PAIRING, SEARCHING, STOP
   - Debug banner con stato connessione
   - Lista nodi con icone: → (diretti) e ↪️ (indiretti)

3. _parseMeshMessage():
   - Parsa JSON ricevuto da ESP32
   - Estrae array "peers" e campo "src"
   - Per ogni peer:
     * Controlla presenza campo "via"
     * Se via == null → peer DIRETTO
     * Se via != null → peer INDIRETTO via nodo X
   - Aggiorna lista _nodes
   - Chiama setState() per refresh UI
   - Log dettagliati con emoji: 📥 📍 📡 ↪️ → 🔄 ➕

4. Timer di transizione:
   Timer(const Duration(seconds: 30), () {
     setState(() {
       _localDeviceState = DeviceNodeState.connected;
       debugPrint('[MESH] ⏱️ Timer expired - transitioning to CONNECTED');
     });
     // NON chiamare stopMode() - ESP32 deve rimanere attivo!
   });

5. BleService:
   - Scan dispositivi BLE
   - Connessione a ESP32 specifico
   - Subscribe a characteristic per ricevere JSON
   - Write su characteristic per inviare comandi stato

PROBLEMI RISOLTI (da evitare):

1. BUG TIMER:
   ERRATO: Timer che chiama stopMode() dopo 30s → interrompe mesh
   CORRETTO: Timer che cambia solo stato UI, ESP32 rimane attivo

2. BUG PROPAGAZIONE:
   ERRATO: Manufacturer data non parsato, peer indiretti mai creati
   CORRETTO: Parsing completo manufacturer data in onResult()

3. BUG RSSI INDIRETTI:
   ERRATO: peers[i].rssi = -100; (valore fittizio)
   CORRETTO: peers[i].rssi = approximatedRssi; (somma path)

4. BUG NOMI:
   ERRATO: String neighborFullName = "PEER_" + neighborId;
   CORRETTO: String neighborFullName = "ESP32_S3_BLE_" + neighborId;

STRUTTURA FILE:

PrimoProgetto/
├── primo_progetto_flutter/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   │   └── device_node.dart
│   │   ├── screens/
│   │   │   └── network_view_screen.dart
│   │   └── services/
│   │       └── ble_service.dart
│   ├── pubspec.yaml
│   └── android/
│       └── app/
│           └── src/
│               └── main/
│                   └── AndroidManifest.xml
│
└── sketch_ESP32_S3_BLE_Server/
    ├── MotoA/
    │   └── sketch_ESP32_S3_BLE_Server/
    │       └── sketch_ESP32_S3_BLE_Server.ino
    ├── MotoB/
    │   └── sketch_ESP32_S3_BLE_Server_B/
    │       └── sketch_ESP32_S3_BLE_Server_B.ino
    └── MotoC/
        └── sketch_ESP32_S3_BLE_Server_C/
            └── sketch_ESP32_S3_BLE_Server_C.ino

DIPENDENZE:

pubspec.yaml:
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.32.11
  permission_handler: ^11.3.1
  geolocator: ^11.0.0
  objectbox: ^2.5.1

AndroidManifest.xml permessi:
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

Librerie Arduino (installare via Library Manager):
- ArduinoJson by Benoit Blanchon (v6.x)
- ESP32 BLE Arduino (built-in con ESP32 board package)

LOGGING:

ESP32 Serial (115200 baud):
[INIT] 🚀 ESP32-S3 BLE Mesh Server Starting...
[INIT] 📝 Device ID: A
[STATE] Transitioning to: SEARCHING
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_B (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from B
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via B | RSSI: -48 | Dist: 0.15m
[JSON] 📤 Built message: 2 total peers (1 direct, 1 indirect)

Flutter logs (debugPrint):
[MESH PARSER] 📥 RAW MESSAGE: {"peers":[...],"src":"A"}
[MESH PARSER] 📍 Source ESP32: A
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | Type: DIRECT | RSSI: -20 dBm
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_C | Type: INDIRECT (via B) | RSSI: -48 dBm | ↪️
[MESH PARSER] 📊 Current network topology:
[MESH PARSER]    →  ESP32_S3_BLE_B (RSSI: -20, Dist: 0.01m)
[MESH PARSER]    ↪️  ESP32_S3_BLE_C (via B) (RSSI: -48, Dist: 0.15m)

TEST SCENARIO:

Test 1 - Base Connectivity:
- Posiziona ESP32-A, B, C vicini (~10cm)
- Tutti dovrebbero vedersi come peer DIRETTI
- Nessun campo "via" nei JSON

Test 2 - Mesh Propagation:
- ESP32-A e B vicini (~10cm)
- ESP32-B e C vicini (~10cm)
- ESP32-C lontano da A (2-3 metri)
- ESP32-A dovrebbe vedere C come INDIRETTO via B
- JSON contiene: {"id":"ESP32_S3_BLE_C","rssi":-48,"dist":0.15,"via":"B"}

IMPLEMENTA:
1. Crea tutti i file con codice completo
2. Usa exact UUID e parametri specificati
3. Implementa logging dettagliato con emoji
4. Gestisci correttamente peer diretti/indiretti con priorità
5. Parser JSON robusto con gestione errori
6. UI con icone distinte per diretti/indiretti
7. Evita i 4 bug documentati sopra

STILE CODICE:
- Commenti dettagliati per sezioni critiche
- Emoji nei log per visibilità rapida
- Separatori ═══ per delimitare log messaggi
- Nomi variabili descriptive (peerCount, directRssi, etc.)
- Costanti in maiuscolo (#define per Arduino, const per Dart)
```

---

## 📋 PROMPT AVANZATO (Con Specifiche Dettagliate)

Se hai bisogno di maggiori dettagli, usa questo prompt esteso:

```
Espandi il progetto precedente con i seguenti dettagli implementativi:

ESP32 - STRUCT PEER:
struct Peer {
  char name[32];           // Nome completo: "ESP32_S3_BLE_A"
  int rssi;                // RSSI in dBm
  float distance;          // Distanza in metri
  unsigned long lastSeen;  // Timestamp millis()
  bool isIndirect;         // true se peer indiretto
  char viaNode[8];         // ID nodo intermediario (es: "B")
};

ESP32 - FUNZIONE updatePeer() COMPLETA:
void updatePeer(String peerName, int rssi, String viaNode, 
                bool isIndirect, String peerId, float distance) {
  
  // Cerca peer esistente
  int existingIndex = -1;
  for (int i = 0; i < peerCount; i++) {
    if (strcmp(peers[i].name, peerName.c_str()) == 0) {
      existingIndex = i;
      break;
    }
  }
  
  if (existingIndex >= 0) {
    // PEER ESISTENTE
    Peer* peer = &peers[existingIndex];
    unsigned long now = millis();
    
    // Priorità diretti: mantieni diretto se visto recentemente
    if (!peer->isIndirect && isIndirect) {
      if (now - peer->lastSeen < DIRECT_PRIORITY_WINDOW) {
        Serial.printf("[MESH] ⚠️  Keeping DIRECT peer %s\n", peerName.c_str());
        return;
      }
    }
    
    // Upgrade automatico: indiretto → diretto
    if (peer->isIndirect && !isIndirect) {
      Serial.printf("[MESH] ⬆️  Upgrading %s to DIRECT\n", peerName.c_str());
    }
    
    // Aggiorna dati
    peer->rssi = rssi;
    peer->distance = distance;
    peer->lastSeen = now;
    peer->isIndirect = isIndirect;
    
    if (isIndirect) {
      strncpy(peer->viaNode, viaNode.c_str(), sizeof(peer->viaNode) - 1);
    } else {
      peer->viaNode[0] = '\0';
    }
    
  } else {
    // NUOVO PEER
    if (peerCount < MAX_PEERS) {
      Peer* newPeer = &peers[peerCount];
      strncpy(newPeer->name, peerName.c_str(), sizeof(newPeer->name) - 1);
      newPeer->rssi = rssi;
      newPeer->distance = distance;
      newPeer->lastSeen = millis();
      newPeer->isIndirect = isIndirect;
      
      if (isIndirect) {
        strncpy(newPeer->viaNode, viaNode.c_str(), sizeof(newPeer->viaNode) - 1);
      } else {
        newPeer->viaNode[0] = '\0';
      }
      
      peerCount++;
      Serial.printf("[MESH] ➕ Added %s peer: %s\n", 
                   isIndirect ? "INDIRECT" : "DIRECT", peerName.c_str());
    }
  }
}

ESP32 - PARSING MANUFACTURER DATA (onResult callback):
void onResult(BLEAdvertisedDevice advertisedDevice) {
  String deviceName = String(advertisedDevice.getName().c_str());
  
  if (!deviceName.startsWith("ESP32_S3_BLE_")) return;
  
  int lastUnderscorePos = deviceName.lastIndexOf('_');
  String peerId = deviceName.substring(lastUnderscorePos + 1);
  
  // Peer DIRETTO
  int directRssi = advertisedDevice.getRSSI();
  float directDist = rssiToDistance(directRssi);
  updatePeer(deviceName, directRssi, "", false, peerId, directDist);
  
  // PARSING MANUFACTURER DATA per peer INDIRETTI
  if (advertisedDevice.haveManufacturerData()) {
    std::string mfgData = advertisedDevice.getManufacturerData();
    
    Serial.printf("[MESH] 🔍 Parsing manufacturer data from %s (len: %d)\n", 
                  deviceName.c_str(), mfgData.length());
    
    // Verifica header [0xFF 0xFF]
    if (mfgData.length() >= 3 && 
        (uint8_t)mfgData[0] == 0xFF && 
        (uint8_t)mfgData[1] == 0xFF) {
      
      // mfgData[2] = stato (non usato)
      // mfgData[3+] = pairs di (ID, RSSI)
      
      int neighborCount = (mfgData.length() - 3) / 2;
      
      Serial.printf("[MESH] 📡 Found %d neighbor(s) from %s\n", 
                    neighborCount, deviceName.c_str());
      
      for (int i = 0; i < neighborCount; i++) {
        int offset = 3 + (i * 2);
        char neighborIdChar = mfgData[offset];
        int8_t neighborRssi = (int8_t)mfgData[offset + 1];
        
        String neighborId = String(neighborIdChar);
        
        // Skip se è questo ESP32
        if (neighborId == myDeviceId) {
          Serial.printf("[MESH] ⏭️  Skipping %s (it's me)\n", neighborId.c_str());
          continue;
        }
        
        // Calcola RSSI approssimato (somma path)
        int approximatedRssi = directRssi + neighborRssi;
        
        // Calcola distanza cumulativa
        float neighborDist = rssiToDistance(neighborRssi);
        float totalDist = directDist + neighborDist;
        
        // Costruisci nome completo
        String neighborFullName = "ESP32_S3_BLE_" + neighborId;
        
        // Aggiungi peer INDIRETTO
        updatePeer(neighborFullName, approximatedRssi, peerId, true, 
                   neighborId, totalDist);
        
        Serial.printf("[MESH] ↪️  Added INDIRECT: %s via %s | RSSI: %d | Dist: %.2fm\n",
                     neighborFullName.c_str(), peerId.c_str(), 
                     approximatedRssi, totalDist);
      }
    }
  }
}

ESP32 - GESTIONE STATI (loop):
void loop() {
  unsigned long currentMillis = millis();
  
  updateLED();  // Aggiorna LED in base a currentState
  
  switch (currentState) {
    case STATE_IDLE:
      // Attesa comando PAIRING
      break;
      
    case STATE_PAIRING:
      // Attesa connessione BLE (gestito da callback)
      break;
      
    case STATE_SEARCHING:
    case STATE_CONNECTED:
      // SCAN BLE
      if (currentMillis - lastScanTime >= SCAN_INTERVAL) {
        if (!pBLEScan->isScanning()) {
          pBLEScan->start(SCAN_WINDOW / 1000, false);  // Scan non bloccante
        }
        lastScanTime = currentMillis;
      }
      
      // AGGIORNA ADVERTISING DATA
      if (currentMillis - lastAdvertisingUpdate >= REPORT_INTERVAL) {
        updateAdvertisingData();
        lastAdvertisingUpdate = currentMillis;
      }
      
      // INVIA JSON via BLE characteristic
      if (deviceConnected && currentMillis - lastReportTime >= REPORT_INTERVAL) {
        String message = jsonPeerMessage();
        pCharacteristic->setValue(message.c_str());
        pCharacteristic->notify();
        lastReportTime = currentMillis;
      }
      break;
  }
}

FLUTTER - DeviceNode MODEL:
class DeviceNode {
  final String id;
  final String name;
  final int rssi;
  final double distance;
  final DeviceNodeState state;
  final DateTime lastUpdate;
  final String? via;  // null = direct, non-null = indirect
  
  DeviceNode({
    required this.id,
    required this.name,
    required this.rssi,
    required this.distance,
    required this.state,
    required this.lastUpdate,
    this.via,
  });
  
  bool get isDirect => via == null;
  bool get isIndirect => via != null;
  
  String get typeIcon => isDirect ? '→' : '↪️';
  
  String get displayName {
    if (isIndirect) {
      return '$name (via $via)';
    }
    return name;
  }
}

FLUTTER - _parseMeshMessage() COMPLETA:
void _parseMeshMessage(String message) {
  debugPrint('═══════════════════════════════════════');
  debugPrint('[MESH PARSER] 📥 RAW MESSAGE: $message');
  
  try {
    final data = jsonDecode(message);
    final String source = data['src'] ?? 'UNKNOWN';
    final List<dynamic> peersData = data['peers'] ?? [];
    
    debugPrint('[MESH PARSER] 📍 Source ESP32: $source');
    debugPrint('[MESH PARSER] ✅ Found ${peersData.length} peer(s)');
    
    int updatedCount = 0;
    int newCount = 0;
    
    for (var peerData in peersData) {
      final String id = peerData['id'];
      final int rssi = peerData['rssi'];
      final double distance = (peerData['dist'] as num).toDouble();
      final String? via = peerData['via'];
      
      final bool isDirect = via == null;
      final String peerType = isDirect ? 'DIRECT' : 'INDIRECT (via $via)';
      final String icon = isDirect ? '→' : '↪️';
      
      final existingIndex = _nodes.indexWhere((n) => n.id == id);
      
      if (existingIndex >= 0) {
        final oldNode = _nodes[existingIndex];
        
        debugPrint('[MESH PARSER] 📡 Peer: $id | Type: $peerType | '
                  'RSSI: $rssi dBm | Distance: ${distance}m | 🔄 UPDATING');
        
        debugPrint('[MESH PARSER] 🔄 $id: RSSI ${oldNode.rssi} → $rssi, '
                  'Dist ${oldNode.distance.toStringAsFixed(2)} → ${distance.toStringAsFixed(2)}m');
        
        _nodes[existingIndex] = DeviceNode(
          id: id,
          name: id,
          rssi: rssi,
          distance: distance,
          state: DeviceNodeState.connected,
          lastUpdate: DateTime.now(),
          via: via,
        );
        
        updatedCount++;
      } else {
        debugPrint('[MESH PARSER] 📡 Peer: $id | Type: $peerType | '
                  'RSSI: $rssi dBm | Distance: ${distance}m | ➕ NEW');
        
        _nodes.add(DeviceNode(
          id: id,
          name: id,
          rssi: rssi,
          distance: distance,
          state: DeviceNodeState.connected,
          lastUpdate: DateTime.now(),
          via: via,
        ));
        
        newCount++;
      }
    }
    
    debugPrint('[MESH PARSER] ✅ SUMMARY: Updated: $updatedCount | New: $newCount | Total: ${_nodes.length}');
    
    debugPrint('[MESH PARSER] 📊 Current topology:');
    for (var node in _nodes) {
      if (node.isIndirect) {
        debugPrint('[MESH PARSER]    ↪️  ${node.id} (via ${node.via}) '
                  '(RSSI: ${node.rssi}, Dist: ${node.distance.toStringAsFixed(2)}m)');
      } else {
        debugPrint('[MESH PARSER]    →  ${node.id} '
                  '(RSSI: ${node.rssi}, Dist: ${node.distance.toStringAsFixed(2)}m)');
      }
    }
    
    setState(() {});
    
    debugPrint('[MESH PARSER] 💾 Persistent mesh: keeping all ${_nodes.length} node(s)');
    
  } catch (e) {
    debugPrint('[MESH PARSER] ❌ ERROR: $e');
  }
  
  debugPrint('═══════════════════════════════════════');
}

FLUTTER - UI LISTA NODI:
ListView.builder(
  itemCount: _nodes.length,
  itemBuilder: (context, index) {
    final node = _nodes[index];
    return Card(
      child: ListTile(
        leading: Icon(
          node.isDirect ? Icons.bluetooth_connected : Icons.route,
          color: node.isDirect ? Colors.blue : Colors.orange,
        ),
        title: Text(
          node.displayName,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RSSI: ${node.rssi} dBm'),
            Text('Distance: ${node.distance.toStringAsFixed(2)}m'),
            Text('Type: ${node.isDirect ? 'Direct →' : 'Indirect ↪️'}'),
          ],
        ),
        trailing: Text(
          node.typeIcon,
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  },
)

IMPLEMENTA con questi dettagli esatti per garantire compatibilità completa.
```

---

## 🔧 VARIANTI E ESTENSIONI

### Prompt per Aggiungere LoRa:

```
Estendi il progetto mesh BLE aggiungendo comunicazione LoRa per collegare cluster BLE remoti:

OBIETTIVO:
- ESP32-B diventa gateway BLE↔LoRa
- Colleziona topologia mesh locale (BLE)
- Trasmette via LoRa a gateway remoto
- Propaga peer remoti come indiretti con via: "LORA_X"

HARDWARE:
- Modulo LoRa: SX1276/78 o RFM95W
- Connessione SPI a ESP32
- Pin: MISO, MOSI, SCK, CS, RST, DIO0

CONFIGURAZIONE LORA:
- Frequenza: 868MHz (Europa) o 915MHz (USA)
- Bandwidth: 125kHz
- Spreading Factor: 7 (bilanciamento range/speed)
- TX Power: 20dBm (100mW)

FORMATO PACCHETTO LORA:
{
  "cluster": "1",
  "gateway": "B",
  "mesh": {
    "peers": [...],
    "src": "B"
  }
}

IMPLEMENTA:
1. Nuovo firmware: sketch_ESP32_S3_BLE_LoRa_Gateway.ino
2. Funzioni: initLoRa(), sendMeshToLoRa(), receiveLoRaPackets()
3. Bridging bidirezionale BLE↔LoRa
4. App Flutter: visualizzazione multi-cluster
5. UI: icona 📡 per peer remoti via LoRa

LIBRERIA ARDUINO:
#include <LoRa.h>  // by Sandeep Mistry
```

### Prompt per Ottimizzare Power Management:

```
Aggiungi power management al progetto mesh BLE per deployments battery-powered:

OBIETTIVO:
- Ridurre consumo energetico ESP32
- Mantenere funzionalità mesh
- Configurabile: duty cycle, deep sleep

IMPLEMENTA:
1. Deep sleep tra scan cycles
2. Wake-on-BLE advertising (se supportato)
3. Parametri configurabili:
   - DEEP_SLEEP_DURATION: 5000ms (5s sleep)
   - ACTIVE_DURATION: 1000ms (1s active)
   - Duty cycle risultante: 16.7%

4. Modifica loop():
   - Esegui scan BLE
   - Aggiorna advertising
   - Invia JSON
   - Entra in deep sleep
   - Wake up dopo DEEP_SLEEP_DURATION

5. Persistenza stato:
   - Salva peerCount in RTC memory
   - Ripristina dopo wake up

CODICE ESEMPIO:
void enterDeepSleep() {
  Serial.println("[POWER] Entering deep sleep...");
  esp_sleep_enable_timer_wakeup(DEEP_SLEEP_DURATION * 1000);
  esp_deep_sleep_start();
}
```

### Prompt per Aggiungere Sicurezza:

```
Aggiungi sicurezza e crittografia al mesh network BLE:

OBIETTIVO:
- Crittografare messaggi JSON
- Autenticare peer
- Prevenire spoofing

IMPLEMENTA:
1. AES-128 per messaggi JSON:
   - Chiave condivisa: 128-bit
   - IV random per ogni messaggio
   - Formato: [IV(16 bytes)][Encrypted JSON][HMAC(32 bytes)]

2. HMAC-SHA256 per autenticazione:
   - Verifica integrità messaggio
   - Secret key condivisa

3. Whitelist peer autorizzati:
   - Array di device_id autorizzati
   - Ignora peer non autorizzati

LIBRERIE:
#include <mbedtls/aes.h>
#include <mbedtls/md.h>

FLUTTER:
import 'package:encrypt/encrypt.dart';

CODICE ESEMPIO ESP32:
#define AES_KEY "YOUR_128BIT_KEY_"
#define HMAC_KEY "YOUR_SECRET_KEY"

String encryptMessage(String plaintext) {
  // Generate random IV
  // Encrypt with AES-128-CBC
  // Calculate HMAC
  // Return: Base64(IV + Encrypted + HMAC)
}

bool verifyMessage(String encrypted) {
  // Decode Base64
  // Extract IV, Encrypted, HMAC
  // Verify HMAC
  // Decrypt
  // Return decrypted JSON
}
```

---

## 📝 CHECKLIST IMPLEMENTAZIONE

Quando ricrei il progetto, verifica questi punti:

### ESP32 Firmware:
- [ ] 3 file .ino identici tranne myDeviceId ("A", "B", "C")
- [ ] UUID corretti (Service e Characteristic)
- [ ] LED configurato su GPIO 48 con PWM
- [ ] Serial.begin(115200) in setup()
- [ ] Manufacturer data con header [0xFF 0xFF]
- [ ] Parsing manufacturer data in onResult()
- [ ] updatePeer() con logica priorità diretti
- [ ] rssiToDistance() con RSSI_AT_1M=-59, n=2.0
- [ ] jsonPeerMessage() con campo "via" condizionale
- [ ] Tutti i parametri timing corretti (SCAN_INTERVAL=3000, etc.)
- [ ] Log con emoji per visibilità

### Flutter App:
- [ ] pubspec.yaml con flutter_blue_plus ^1.32.11
- [ ] AndroidManifest.xml con tutti permessi BLE
- [ ] DeviceNode model con campo via opzionale
- [ ] _parseMeshMessage() che estrae campo "via"
- [ ] UI con icone distinte (→ vs ↪️)
- [ ] Timer che NON chiama stopMode()
- [ ] Log dettagliati con emoji
- [ ] Gestione errori nel parsing JSON

### Test:
- [ ] Test 1 completato: tutti vicini, tutti diretti
- [ ] Test 2 ready: C lontano da A, indiretto via B
- [ ] Log ESP32 mostrano "↪️ Added INDIRECT peer"
- [ ] JSON contiene campo "via": "B"
- [ ] App mostra icona ↪️ per peer indiretti

---

## 💾 BACKUP PARAMETRI CRITICI

Se perdi il codice, ricorda questi valori esatti:

```cpp
// ESP32 PARAMETRI CRITICI
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SCAN_INTERVAL 3000
#define SCAN_WINDOW 1000
#define REPORT_INTERVAL 3000
#define PEER_TIMEOUT 8000
#define DIRECT_PRIORITY_WINDOW 2000
#define MAX_PEERS 20
#define MAX_ADVERTISED_PEERS 14
#define LED_PIN 48
#define LED_BLINK_INTERVAL 500
#define RSSI_AT_1M -59
#define PATH_LOSS_EXPONENT 2.0

// MANUFACTURER DATA FORMAT
// [0xFF][0xFF][State][ID1][RSSI1][ID2][RSSI2]...

// JSON FORMAT
// {"peers":[{"id":"ESP32_S3_BLE_X","rssi":INT,"dist":FLOAT,"via":"X"}],"src":"X"}
```

---

## 🚀 UTILIZZO DEL PROMPT

1. **Copia il "PROMPT INIZIALE"** (sezione principale)
2. **Incolla in un AI Assistant** (GitHub Copilot Chat, ChatGPT, Claude)
3. **Specifica il linguaggio target** se necessario
4. **Aggiungi "PROMPT AVANZATO"** se serve maggior dettaglio
5. **Usa VARIANTI** per estensioni (LoRa, Power, Security)

### Esempio Comando:

```
@workspace /new Crea un nuovo progetto Flutter + ESP32 mesh network BLE seguendo queste specifiche:

[INCOLLA PROMPT INIZIALE QUI]

Crea i file con codice completo e funzionante.
```

---

## 📚 RIFERIMENTI RAPIDI

### UUID Generator (se servono nuovi UUID):
```
Online: https://www.uuidgenerator.net/version4
Formato: 4fafc201-1fb5-459e-8fcc-c5c9c331914b (lowercase con trattini)
```

### Calcolo RSSI→Distanza Online:
```
Formula: dist = 10 ^ ((RSSI_1m - RSSI) / (10 * n))
Tool: https://www.rfwireless-world.com/calculators/RSSI-to-Distance-Calculator.html
```

### BLE Advertising Payload Calculator:
```
Header: 2 bytes (0xFF 0xFF)
State: 1 byte
Per peer: 2 bytes (ID + RSSI)
Max peers: (31 - 3) / 2 = 14 peer
```

---

**NOTA IMPORTANTE:**
Questo prompt è stato testato e produce codice funzionante. 
Salva questo file in un luogo sicuro come backup testuale del progetto.

**Versione Documento:** 1.0  
**Data Creazione:** 22 Gennaio 2026  
**Ultima Modifica:** 22 Gennaio 2026  

---

*Fine del Prompt di Ricreazione Progetto*
