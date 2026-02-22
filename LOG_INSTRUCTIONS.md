# 📝 Istruzioni per Aggiungere Log Diagnostici

## ✅ Modifiche già applicate:

### Flutter App (network_view_screen.dart):
- ✅ Log dettagliati con source ESP32
- ✅ Distinzione tra peer diretti e indiretti
- ✅ Banner di debug nella Network View
- ✅ Icone diverse per peer diretti (→) e indiretti (↪️)
- ✅ Contatori di nodi nel banner
- ✅ Topologia della rete nei log

### ESP32-A (sketch_ESP32_S3_BLE_Server.ino):
- ✅ Log di inizializzazione dettagliati
- ✅ Report ogni 3 secondi con stato completo
- ✅ Lista dei peer con dettagli (RSSI, distanza, via)
- ✅ Suggerimenti diagnostici quando non ci sono peer

## 🔧 Da applicare a ESP32-B e ESP32-C:

### 1. Nella funzione `setup()` (circa riga 558):

Sostituire:
```cpp
void setup() {
  Serial.begin(115200);

  pixel.begin();
  pixel.setBrightness(50);
  pixel.clear();
  pixel.show();

  BLEDevice::init(BLE_NAME);
```

Con:
```cpp
void setup() {
  Serial.begin(115200);
  delay(1000); // Piccola pausa per stabilizzare la seriale
  
  Serial.println("\n\n");
  Serial.println("═══════════════════════════════════════");
  Serial.println("[INIT] 🚀 ESP32-S3 BLE Mesh Server Starting...");
  Serial.printf("[INIT] 📱 Device Name: %s\n", BLE_NAME);
  Serial.printf("[INIT] 🆔 Service UUID: %s\n", SERVICE_UUID);
  Serial.printf("[INIT] 📡 Characteristic UUID: %s\n", CHARACTERISTIC_UUID);
  Serial.println("═══════════════════════════════════════");

  pixel.begin();
  pixel.setBrightness(50);
  pixel.clear();
  pixel.show();
  Serial.println("[INIT] ✅ NeoPixel initialized");

  BLEDevice::init(BLE_NAME);
  Serial.println("[INIT] ✅ BLE Device initialized");
```

### 2. Nella funzione `setup()` - Dopo la creazione del server (circa riga 575):

Sostituire:
```cpp
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* service = pServer->createService(SERVICE_UUID);
  ...
  pServer->getAdvertising()->start();

  pScan = BLEDevice::getScan();
  ...
  
  Serial.printf("[%s] Ready. Phone connects to this device; this device scans for peer.\n", BLE_NAME);
}
```

Con:
```cpp
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  Serial.println("[INIT] ✅ GATT Server created");

  BLEService* service = pServer->createService(SERVICE_UUID);
  ... (lasciare il resto uguale)
  service->start();
  Serial.println("[INIT] ✅ BLE Service started");
  
  pServer->getAdvertising()->addServiceUUID(SERVICE_UUID);
  pServer->getAdvertising()->start();
  Serial.println("[INIT] ✅ Advertising started - Phone can now connect");

  pScan = BLEDevice::getScan();
  pScan->setAdvertisedDeviceCallbacks(new PeerScanCallbacks());
  pScan->setActiveScan(true);
  pScan->setInterval(50);
  pScan->setWindow(30);
  Serial.println("[INIT] ✅ BLE Scanner configured");

  Serial.println("═══════════════════════════════════════");
  Serial.printf("[INIT] 🎉 %s is READY!\n", BLE_NAME);
  Serial.println("[INIT] 📱 Waiting for phone connection...");
  Serial.println("[INIT] 🔍 Current State: IDLE");
  Serial.println("[INIT] 💡 Send 'PAIRING' or 'SEARCHING' via Serial or App to start discovering");
  Serial.println("═══════════════════════════════════════\n");
}
```

### 3. Nella funzione `loop()` - Sezione Report (circa riga 650):

Sostituire:
```cpp
  if (phoneConnected && (millis() - lastReportMs) > 100) {
    lastReportMs = millis();
    String payload = jsonPeerMessage();
    pCharacteristic->setValue(payload.c_str());
    pCharacteristic->notify();
    
    static unsigned long lastStateLog = 0;
    if (millis() - lastStateLog > 5000) {
      Serial.printf("[REPORT] 📡 State: %s | PeerCount: %d | Sending: %s\n", ...);
      lastStateLog = millis();
    }
  }
```

Con:
```cpp
  if (phoneConnected && (millis() - lastReportMs) > 100) {
    lastReportMs = millis();
    String payload = jsonPeerMessage();
    pCharacteristic->setValue(payload.c_str());
    pCharacteristic->notify();
    
    // Log dettagliato ogni 3 secondi per diagnostica
    static unsigned long lastStateLog = 0;
    if (millis() - lastStateLog > 3000) {
      Serial.println("═══════════════════════════════════════");
      Serial.printf("[REPORT] 📡 ESP32-%s Status Report\n", String(BLE_NAME).substring(String(BLE_NAME).length()-1).c_str());
      Serial.printf("[REPORT] State: %s | Scan: %s | Phone: %s\n", 
        currentState == IDLE ? "IDLE" : 
        currentState == PAIRING ? "PAIRING" : 
        currentState == SEARCHING ? "SEARCHING" : 
        currentState == CONNECTED ? "CONNECTED" : "UNKNOWN",
        scanEnabled ? "ON" : "OFF",
        phoneConnected ? "CONNECTED" : "DISCONNECTED");
      Serial.printf("[REPORT] Total Peers: %d (Direct: %d, Indirect: %d)\n", 
        peerCount, 
        peerCount,
        0);
      
      if (peerCount > 0) {
        Serial.println("[REPORT] Peer List:");
        for (int i = 0; i < peerCount; i++) {
          Serial.printf("[REPORT]   %d) %s | RSSI: %d | Dist: %.2fm | Via: %s\n",
            i+1,
            peerNames[i].c_str(),
            peerRssi[i],
            peerDistance[i],
            peerVia[i].c_str());
        }
      } else {
        Serial.println("[REPORT] ⚠️ No peers detected!");
        if (currentState == IDLE) {
          Serial.println("[REPORT] 💡 TIP: Press PAIRING or SEARCHING to discover ESP32 devices");
        } else {
          Serial.println("[REPORT] 💡 TIP: Ensure other ESP32 are powered on and in PAIRING/SEARCHING mode");
        }
      }
      
      Serial.printf("[REPORT] JSON Payload: %s\n", payload.c_str());
      Serial.println("═══════════════════════════════════════");
      lastStateLog = millis();
    }
  }
```

## 🎯 Cosa vedrai dopo queste modifiche:

### Nel Serial Monitor (all'avvio):
```
═══════════════════════════════════════
[INIT] 🚀 ESP32-S3 BLE Mesh Server Starting...
[INIT] 📱 Device Name: ESP32_S3_BLE_A
[INIT] 🆔 Service UUID: 4fafc201-1fb5-459e-8fcc-c5c9c331914b
[INIT] 📡 Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8
═══════════════════════════════════════
[INIT] ✅ NeoPixel initialized
[INIT] ✅ BLE Device initialized
[INIT] ✅ GATT Server created
[INIT] ✅ BLE Service started
[INIT] ✅ Advertising started - Phone can now connect
[INIT] ✅ BLE Scanner configured
═══════════════════════════════════════
[INIT] 🎉 ESP32_S3_BLE_A is READY!
[INIT] 📱 Waiting for phone connection...
[INIT] 🔍 Current State: IDLE
[INIT] 💡 Send 'PAIRING' or 'SEARCHING' via Serial or App to start discovering
═══════════════════════════════════════
```

### Nel Serial Monitor (durante il funzionamento - ogni 3 secondi):
```
═══════════════════════════════════════
[REPORT] 📡 ESP32-C Status Report
[REPORT] State: CONNECTED | Scan: ON | Phone: CONNECTED
[REPORT] Total Peers: 2 (Direct: 2, Indirect: 0)
[REPORT] Peer List:
[REPORT]   1) ESP32_S3_BLE_B | RSSI: -23 | Dist: 0.02m | Via: Direct
[REPORT]   2) ESP32_S3_BLE_A | RSSI: -28 | Dist: 0.03m | Via: Direct
[REPORT] JSON Payload: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-23,"dist":0.02},{"id":"ESP32_S3_BLE_A","rssi":-28,"dist":0.03}],"src":"C"}
═══════════════════════════════════════
```

### Nell'App Flutter (log console):
```
═══════════════════════════════════════
[MESH PARSER] 📥 RAW MESSAGE: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-23,"dist":0.02}],"src":"C"}
[MESH PARSER] 📍 Source ESP32: C
[MESH PARSER] ✅ Found 1 peer(s) in message from C
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | Type: DIRECT | RSSI: -23 dBm | Distance: 0.02m | 🔄 UPDATING
[MESH PARSER] ✅ SUMMARY: Updated: 1 | New: 0 | Skipped: 0 | Total nodes: 3
[MESH PARSER] 📊 Current network topology:
[MESH PARSER]    → ESP32_S3_BLE_A (RSSI: -28, Dist: 0.03m)
[MESH PARSER]    → ESP32_S3_BLE_B (RSSI: -23, Dist: 0.02m)
[MESH PARSER]    → ESP32_S3_BLE_C (RSSI: -25, Dist: 0.02m)
[MESH PARSER] 🎨 Calling setState() to refresh UI with 3 node(s)
[MESH PARSER] 💾 Persistent mesh: keeping all 3 discovered node(s)
═══════════════════════════════════════
```

### Nella Network View (UI):
```
┌─────────────────────────────────────┐
│ 🟢 ESP32_S3_BLE_C                   │
│ 10:11:12:13:14:15                   │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ ✅ Connected              [3 nodes] │
│ → Direct: 2 | ↪️ Indirect: 1        │
│ 💡 Check logs for detailed mesh     │
│    topology                          │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ → ESP32_S3_BLE_A                    │
│ RSSI: -28 dBm (direct)  [0.03m]     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ → ESP32_S3_BLE_B                    │
│ RSSI: -23 dBm (direct)  [0.02m]     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ ↪️ Indirect_A                        │
│ RSSI: -99 dBm (via another ESP32)   │
│                          [0.05m]    │
└─────────────────────────────────────┘
```

## 📌 Note importanti:

1. **Serial Monitor**: Assicurati che il baud rate sia impostato a **115200**
2. **Timestamp**: I log appariranno ogni 3 secondi per non intasare la seriale
3. **Filtri**: Puoi cercare `[REPORT]`, `[INIT]`, `[MESH PARSER]` per filtrare i log
4. **Debugging**: Se non vedi nessun peer, controlla i suggerimenti nei log (`💡 TIP`)

## 🚀 Prossimi passi:

1. Ricarica il firmware su ESP32-B e ESP32-C con queste modifiche
2. Apri 3 Serial Monitor (uno per A, B, C)
3. Riavvia le app Flutter
4. Premi PAIRING su un dispositivo e SEARCHING sull'altro
5. Osserva i log sia seriali che nell'app
