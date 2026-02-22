#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>

#include <math.h>
#include <cstdlib>

// BLE service used by the phone app
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// --- CONFIG ---
// The A/B/C/etc sketches are IDENTICAL: only DEVICE_ID + BLE_NAME change.
static const char* DEVICE_ID = "A";
static const char* BLE_NAME = "ESP32_S3_BLE_A";

// NeoPixel (onboard LED often on GPIO48 for ESP32-S3 DevKit)
const int ledPin = 48;
const int numPixels = 1;
Adafruit_NeoPixel pixel(numPixels, ledPin, NEO_GRB + NEO_KHZ800);

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool phoneConnected = false;
Preferences preferences;

// ===== DEVICE STATE MACHINE =====
enum DeviceState {
  IDLE,       // Not doing anything
  PAIRING,    // Accepting connections from other devices (30s timeout)
  SEARCHING,  // Looking for device in PAIRING mode (30s timeout)
  CONNECTED   // Connected to peer network
};

DeviceState currentState = IDLE;
unsigned long stateStartMs = 0;
const unsigned long STATE_TIMEOUT_MS = 30000; // 30 seconds

// LED blink patterns
unsigned long lastBlinkMs = 0;
const unsigned long BLINK_INTERVAL_MS = 500; // 0.5 second blink
bool ledState = false;
uint32_t blinkColorA = 0; // First color for alternating
uint32_t blinkColorB = 0; // Second color for alternating

// Peer scanning
static BLEScan* pScan = nullptr;
static bool scanEnabled = false;  // Manual scan control
unsigned long lastReportMs = 0;

// Struttura per memorizzare info su ogni peer
struct PeerInfo {
  String id;       // Short Identifier "A", "B"... derived from name or advertised
  String fullName; // full BLE Name
  String address;  // MAC Address (saved for persistence)
  int rssi;        // Link strength (for direct peers)
  float dist;      // Calculated distance
  bool isIndirect; // True if this info came from another peer
  String viaId;    // The ID of the peer who told us about this (if indirect)
  unsigned long lastSeenMs;
};

#define MAX_PEERS 12
PeerInfo peers[MAX_PEERS];
int peerCount = 0;

// Approx RSSI->distance (very rough)
float rssiToDistanceMeters(int rssi) {
  // Calibrated-ish parameters. Tune for your environment.
  const float txPower = -59.0f;  // RSSI at 1m
  const float n = 2.0f;          // path-loss exponent
  return powf(10.0f, (txPower - (float)rssi) / (10.0f * n));
}

// ===== PERSISTENCE FUNCTIONS =====
bool isPeerPaired(String address) {
  String key = address; 
  key.replace(":", "");
  preferences.begin("peers", true);
  bool exists = preferences.isKey(key.c_str());
  preferences.end();
  return exists;
}

void savePeerToFlash(String address) {
  if (isPeerPaired(address)) return;
  
  String key = address; 
  key.replace(":", "");
  
  preferences.begin("peers", false);
  preferences.putBool(key.c_str(), true);
  preferences.end();
  Serial.printf("[FLASH] Saved new peer: %s\n", address.c_str());
}

// ===== LED CONTROL FUNCTIONS =====
void setLedBlinkPattern(uint32_t colorA, uint32_t colorB = 0) {
  blinkColorA = colorA;
  blinkColorB = colorB;
  lastBlinkMs = millis();
  ledState = false;
}

void updateLedBlink() {
  unsigned long now = millis();
  if (now - lastBlinkMs >= BLINK_INTERVAL_MS) {
    lastBlinkMs = now;
    ledState = !ledState;
    
    if (ledState) {
      pixel.setPixelColor(0, blinkColorA);
    } else {
      // If colorB is set, alternate between A and B, otherwise turn off
      if (blinkColorB != 0) {
        pixel.setPixelColor(0, blinkColorB);
      } else {
        pixel.clear();
      }
    }
    pixel.show();
  }
}

void setLedSolid(uint32_t color) {
  pixel.setPixelColor(0, color);
  pixel.show();
  blinkColorA = 0;
  blinkColorB = 0;
}

void setLedOff() {
  pixel.clear();
  pixel.show();
  blinkColorA = 0;
  blinkColorB = 0;
}

// ===== STATE MACHINE FUNCTIONS =====
// Update BLE advertising with current state (align with MotoA)
void updateAdvertising() {
  if (pServer == nullptr) {
    Serial.println("[ADV] ERROR: pServer is NULL!");
    return;
  }

  BLEAdvertising* pAdvertising = pServer->getAdvertising();
  pAdvertising->stop();
  Serial.println("[ADV] Stopped previous advertising");

  // Usa API di alto livello invece di creare manualmente BLEAdvertisementData
  pAdvertising->addServiceUUID(SERVICE_UUID);
  Serial.printf("[ADV] Added Service UUID: %s\n", SERVICE_UUID);

  // Manufacturer data: Company ID (0xFFFF) + state byte
  // New Format: [0xFF, 0xFF, State, Flags, Neighbor1_ID, Neighbor1_RSSI, Neighbor2_ID, Neighbor2_RSSI...]
  String mfgData = "";
  mfgData += (char)0xFF;
  mfgData += (char)0xFF;
  mfgData += (char)currentState; 
  
  // Encode Neighbors
  // Include up to 4 closest DIRECT neighbors
  int added = 0;
  for(int i=0; i<peerCount && added<4; i++) {
    if (!peers[i].isIndirect) {
      // Encode ID (1 char) and RSSI (offset by +128 to fit in unsigned char if needed, stick to raw byte)
      // ID: "A" -> 0x41
      if(peers[i].id.length() > 0) {
        mfgData += peers[i].id.charAt(0); 
        mfgData += (char)(peers[i].rssi); // Signed RSSI cast to char (usually -100 to -30)
        added++;
      }
    }
  }

  Serial.printf("[ADV] Setting manufacturer data len %d with %d neighbors\n", mfgData.length(), added);

  // Imposta manufacturer data usando l'API di advertising
  BLEAdvertisementData advData;
  advData.setFlags(0x06);
  advData.setCompleteServices(BLEUUID(SERVICE_UUID));
  advData.setManufacturerData(mfgData);
  
  pAdvertising->setAdvertisementData(advData);
  
  // IMPORTANTE: Imposta anche i Scan Response Data con il nome
  BLEAdvertisementData scanResponseData;
  scanResponseData.setName(BLE_NAME);
  pAdvertising->setScanResponseData(scanResponseData);
  
  pAdvertising->start();
  Serial.printf("[ADV] ✓✓✓ Advertising STARTED with SERVICE_UUID and state: %d (phoneConnected=%d)\n", 
                currentState, phoneConnected);
}

void enterState(DeviceState newState) {
  currentState = newState;
  stateStartMs = millis();
  
  switch (newState) {
    case IDLE:
      Serial.println("[STATE] Entering IDLE");
      setLedOff();
      scanEnabled = false;
      break;
      
    case PAIRING:
      Serial.println("[STATE] Entering PAIRING (30s)");
      // Red blinking - accepting connections
      setLedBlinkPattern(pixel.Color(255, 0, 0)); // Red
      scanEnabled = true; // ENABLED SCANNING IN PAIRING TOO
      break;
      
    case SEARCHING:
      Serial.println("[STATE] Entering SEARCHING (30s)");
      // Blue blinking - looking for pairing device
      setLedBlinkPattern(pixel.Color(0, 0, 255)); // Blue
      scanEnabled = true; // Start scanning
      break;
      
    case CONNECTED:
      Serial.println("[STATE] 🔗 Entering CONNECTED STATE");
      Serial.printf("[STATE] 📊 Current peers: %d\n", peerCount);
      for (int i = 0; i < peerCount; i++) {
        Serial.printf("[STATE]   - %s: RSSI=%d, Dist=%.2fm, %s\n", 
          peers[i].id.c_str(), peers[i].rssi, peers[i].dist,
          peers[i].isIndirect ? "INDIRECT" : "DIRECT");
      }
      // Keep red for principal, or blue-green alternating for secondary
      // (We'll determine this based on role later)
      setLedBlinkPattern(pixel.Color(0, 0, 255), pixel.Color(0, 255, 0)); // Blue-Green
      scanEnabled = true; // Continua a fare scan per mantenere aggiornato RSSI del peer
      Serial.println("[STATE] ✅ CONNECTED state active - will continue scanning and sending data");
      break;
  }
  
  // Update advertising with new state
  updateAdvertising();
  Serial.printf("[STATE] Entered state: %d, scanEnabled: %d\n", currentState, scanEnabled);
}

void checkStateTimeout() {
  unsigned long now = millis();
  
  // Check timeout for PAIRING and SEARCHING states
  if ((currentState == PAIRING || currentState == SEARCHING) && 
      (now - stateStartMs >= STATE_TIMEOUT_MS)) {
    
    Serial.printf("[STATE] ⏰ TIMEOUT REACHED! State: %s, Duration: %lu ms, PeerCount: %d\n", 
      currentState == PAIRING ? "PAIRING" : "SEARCHING", 
      now - stateStartMs, 
      peerCount);
    
    // If we have paired peers, transition to CONNECTED to keep mesh active
    if (peerCount > 0) {
      Serial.printf("[STATE] ✅ Transitioning to CONNECTED (found %d peers)\n", peerCount);
      for (int i = 0; i < peerCount; i++) {
        Serial.printf("  - Peer %d: %s (RSSI: %d, Dist: %.2fm, %s)\n", 
          i, peers[i].id.c_str(), peers[i].rssi, peers[i].dist, 
          peers[i].isIndirect ? "INDIRECT" : "DIRECT");
      }
      enterState(CONNECTED);
    } else {
      Serial.println("[STATE] ⚠️ Returning to IDLE (no peers found)");
      enterState(IDLE);
    }
  }
}

// Parse simple ID from standard name format "ESP32_S3_BLE_X" -> "X"
String extractIdFromName(String name) {
  int idx = name.lastIndexOf('_');
  if (idx > 0 && idx < name.length()-1) {
    return name.substring(idx+1);
  }
  return name; // Fallback
}

// Funzione helper per aggiungere o aggiornare un peer
void updatePeer(const String& fullName, int rssi, String address = "", bool indirect = false, String viaId = "", float indirectDist = 0.0) {
  unsigned long now = millis();
  String pid = extractIdFromName(fullName);
  
  // Ignore self
  if (pid == String(DEVICE_ID)) return;
  
  // Cerca se il peer esiste già
  for (int i = 0; i < peerCount; i++) {
    if (peers[i].id == pid) {
      // Prioritize Direct updates over Indirect ones
      if (!indirect) {
         peers[i].rssi = rssi;
         peers[i].dist = rssiToDistanceMeters(rssi);
         peers[i].isIndirect = false; // Promoted to direct
         peers[i].lastSeenMs = now;
         if (address != "") peers[i].address = address;
      } else {
         // Update indirect info only if we don't have recent direct info (older than 2s)
         if (peers[i].isIndirect || (now - peers[i].lastSeenMs > 2000)) {
            peers[i].isIndirect = true;
            peers[i].viaId = viaId;
            peers[i].dist = indirectDist;
            peers[i].rssi = rssi; // Use approximated RSSI
            peers[i].lastSeenMs = now;
         }
      }
      return;
    }
  }
  
  // Aggiungi nuovo peer se c'è spazio
  if (peerCount < MAX_PEERS) {
    peers[peerCount].id = pid;
    peers[peerCount].fullName = fullName;
    peers[peerCount].address = address;
    peers[peerCount].isIndirect = indirect;
    peers[peerCount].viaId = viaId;
    peers[peerCount].lastSeenMs = now;
    
    if (indirect) {
      peers[peerCount].dist = indirectDist;
      peers[peerCount].rssi = rssi; // Use approximated RSSI from mesh calculation
    } else {
      peers[peerCount].rssi = rssi;
      peers[peerCount].dist = rssiToDistanceMeters(rssi);
      
      // Save to flash if direct discovery in Pairing/Searching
      if (currentState == PAIRING || currentState == SEARCHING) {
        if (address != "") savePeerToFlash(address);
      }
    }
    
    peerCount++;
    Serial.printf("[PEERS] Added new %s peer: %s (via %s), Dist: %.2fm (total: %d)\n", 
       indirect ? "INDIRECT" : "DIRECT", pid.c_str(), viaId.c_str(), peers[peerCount-1].dist, peerCount);
  }
}

// Rimuovi peer vecchi (non visti da 8 secondi - un po' più tollerante per Mesh)
void cleanupOldPeers() {
  unsigned long now = millis();
  for (int i = 0; i < peerCount; i++) {
    if (now - peers[i].lastSeenMs > 8000) {
      // Sposta l'ultimo peer in questa posizione
      peers[i] = peers[peerCount - 1];
      peerCount--;
      i--; // Ricontrolla questa posizione
    }
  }
}

String jsonPeerMessage() {
  String json = "{\"peers\":[";
  
  int directCount = 0;
  int indirectCount = 0;
  
  for (int i = 0; i < peerCount; i++) {
    if (i > 0) json += ",";
    json += "{\"id\":\"" + peers[i].fullName + "\""; // Send full name to phone for consistency
    json += ",\"rssi\":" + String(peers[i].rssi);
    
    // Add mesh info
    if (peers[i].isIndirect) {
       json += ",\"via\":\"" + peers[i].viaId + "\"";
       indirectCount++;
    } else {
       directCount++;
    }
    
    json += ",\"dist\":" + String(peers[i].dist, 2) + "}";
  }
  
  json += "],\"src\":\"" + String(DEVICE_ID) + "\"}";
  
  Serial.printf("[JSON] 📤 Built message: %d total peers (%d direct, %d indirect)\n", 
                peerCount, directCount, indirectCount);
  
  return json;
}

String jsonPeerMessage_OLD(const String& peerId, float distMeters, int rssi) {
  String s = "{";
  s += "\"peer\":\"" + peerId + "\",";
  s += "\"dist\":" + String(distMeters, 2) + ",";
  s += "\"rssi\":" + String(rssi) + ",";
  s += "\"src\":\"" + String(DEVICE_ID) + "\"";
  s += "}";
  return s;
}

// ---- BLE callbacks ----
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    phoneConnected = true;
    Serial.println("[PHONE] Phone connected");
    // Restart advertising so other ESP32 devices can still find us
    updateAdvertising();
  }

  void onDisconnect(BLEServer* server) override {
    phoneConnected = false;
    Serial.println("[PHONE] Phone disconnected");
    // Use our custom advertising instead of default
    updateAdvertising();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* chr) override {
    String arduinoString = chr->getValue();
    std::string value(arduinoString.c_str());
    if (value.empty()) return;
    
    // DEBUG: Log what we received
    Serial.printf("[CMD-RECEIVED] '%s' (length=%d)\n", value.c_str(), value.length());

    // Commands supported:
    // 0 -> off LED
    // #RRGGBB -> set local LED color (solid)
    // STARTPAIRING -> enter PAIRING mode (accept connections, 30s timeout)
    // STARTSEARCHING -> enter SEARCHING mode (look for pairing device, 30s timeout)
    // STOPMODE -> return to IDLE
    // PEERSETCOLOR:<peerId>:#RRGGBB -> forward in the future (placeholder)
    
    if (value == "STARTPAIRING") {
      enterState(PAIRING);
      Serial.println("[CMD] PAIRING mode activated");
      return;
    }
    
    if (value == "STARTSEARCHING") {
      enterState(SEARCHING);
      Serial.println("[CMD] SEARCHING mode activated");
      return;
    }
    
    if (value == "STOPMODE") {
      enterState(IDLE);
      Serial.println("[CMD] Returned to IDLE");
      return;
    }
    
    if (value == "0") {
      pixel.clear();
      pixel.show();
      Serial.println("LED SPENTO (0)");
      return;
    }

    if (value.rfind("PEERLED:", 0) == 0) {
      Serial.printf("[CMD] %s\n", value.c_str());
      // TODO: forward LED command to peer via your own protocol.
      return;
    }

    if (value.rfind("PEERSETCOLOR:", 0) == 0) {
      Serial.printf("[CMD] %s\n", value.c_str());
      // TODO: forward color command to peer via your own protocol.
      // For now only log it so the phone side can be tested.
      return;
    }

    if (value[0] == '#' && value.length() == 7) {
      uint32_t color = (uint32_t)strtol(value.substr(1).c_str(), NULL, 16);
      uint8_t r = (color >> 16) & 0xFF;
      uint8_t g = (color >> 8) & 0xFF;
      uint8_t b = color & 0xFF;
      pixel.setPixelColor(0, pixel.Color(r, g, b));
      pixel.show();
      Serial.printf("COLORE IMPOSTATO: #%s (R:%d, G:%d, B:%d)\n", value.substr(1).c_str(), r, g, b);
      return;
    }

    // default on:
    pixel.setPixelColor(0, pixel.Color(255, 255, 255));
    pixel.show();
    Serial.println("LED ACCESO (Bianco)");
  }
};

class PeerScanCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) override {
    // Look for our own service and *any* other peer device.
    // IMPORTANT: do NOT rely on suffixes like _A/_B, because there may be many devices.
    if (!advertisedDevice.haveServiceUUID()) {
      Serial.println("[SCAN] Device rejected: no service UUID" + advertisedDevice.getName());
      return;
    }
    if (!advertisedDevice.isAdvertisingService(BLEUUID(SERVICE_UUID))) {
      Serial.println("[SCAN] Device rejected: wrong service UUID"  + advertisedDevice.getName());
      return;
    }

    // ESP32 core 3.x returns Arduino String here.
    const String peerName = advertisedDevice.getName();
    if (peerName.length() == 0) {
      Serial.println("[SCAN] Device rejected: empty name");
      return;
    }

    // Debug: log what we found
    Serial.printf("[SCAN] >>> Found device: %s, RSSI: %d, My state: %d\n", 
                  peerName.c_str(), advertisedDevice.getRSSI(), currentState);

    // Optional generic filter: name contains "ESP".
    // (Allowed by requirement; we avoid encoding any A/B/C logic in the name.)
    if (peerName.indexOf("ESP") < 0) {
      Serial.printf("[SCAN] Rejected (no 'ESP' in name): %s\n", peerName.c_str());
      return;
    }

    // Ignore ourselves.
    if (peerName == String(BLE_NAME)) {
      Serial.printf("[SCAN] Rejected (ourselves): %s\n", peerName.c_str());
      return;
    }

    // Get MAC address early for persistence checks
    String peerAddress = advertisedDevice.getAddress().toString().c_str();
    
    // DECISION LOGIC: Accept or Reject based on state and pairing status
    bool accept = false;
    
    // 1. If Pairing/Searching -> Accept ALL ESPs (to find new peers)
    if (currentState == PAIRING || currentState == SEARCHING) {
      accept = true;
    }
    // 2. If Connected/Idle -> Only Accept PAIRED devices (persistence check)
    else if (isPeerPaired(peerAddress)) {
      accept = true;
    }

    if (!accept) {
      Serial.printf("[SCAN] Rejected (not paired and not in discovery mode): %s\n", peerName.c_str());
      return;
    }

    // CRITICAL: Only accept devices in PAIRING mode when we are SEARCHING or PAIRING
    // Check manufacturer data for state information
    if (currentState == SEARCHING || currentState == PAIRING || currentState == CONNECTED) {
      String mfgData = advertisedDevice.getManufacturerData();
      
      if (mfgData.length() >= 3) {
        uint8_t peerState = (uint8_t)mfgData[2];
        
        // Handling State Transitions (Legacy Logic)
        if (currentState == SEARCHING && (peerState == PAIRING || peerState == CONNECTED)) {
           // Original logic: transition if found suitable peer
           // enterState(CONNECTED); // Temporarily disabled auto-transition to focus on scanning
        }
        
        // MESH LOGIC: Parse Neighbors from Manufacturer Data
        // Format: [FF FF State ID1 RSSI1 ID2 RSSI2 ...]
        // Start at index 3
        String peerId = extractIdFromName(peerName);
        float peerDist = rssiToDistanceMeters(advertisedDevice.getRSSI());
        
        Serial.printf("[MESH] 🔍 Parsing manufacturer data from %s (len: %d)\n", 
                      peerName.c_str(), mfgData.length());
        
        if (mfgData.length() > 3) {
          int neighborCount = (mfgData.length() - 3) / 2;
          Serial.printf("[MESH] 📡 Found %d neighbor(s) in advertising from %s\n", 
                        neighborCount, peerId.c_str());
        
          for (int i = 3; i < mfgData.length() - 1; i += 2) {
             char neighborChar = mfgData[i];
             int8_t neighborRssi = (int8_t)mfgData[i+1];
             
             String neighborId = String(neighborChar);
             
             // If neighbor is me, ignore
             if (neighborId == String(DEVICE_ID)) {
               Serial.printf("[MESH] ⏭️  Skipping neighbor %s (it's me)\n", neighborId.c_str());
               continue;
             }
             
             // Calculate Indirect Distance: My->Peer->Neighbor
             float distToNeighbor = rssiToDistanceMeters(neighborRssi);
             float totalDist = peerDist + distToNeighbor;
             
             // Build full name using standard format
             String neighborFullName = "ESP32_S3_BLE_" + neighborId;
             
             // Add as indirect peer (address="", indirect=true, viaId=peerId, totalDist)
             // RSSI is approximated as sum of RSSIs (not accurate but indicative)
             int approxRssi = advertisedDevice.getRSSI() + neighborRssi;
             
             updatePeer(neighborFullName, approxRssi, "", true, peerId, totalDist);
             
             Serial.printf("[MESH] ↪️  Added INDIRECT peer: %s via %s | RSSI: %d (approx) | Dist: %.2fm (A→%s: %.2fm + %s→%s: %.2fm)\n", 
                neighborFullName.c_str(), peerId.c_str(), approxRssi,
                totalDist, peerId.c_str(), peerDist, peerId.c_str(), neighborId.c_str(), distToNeighbor);
          }
        } else {
          Serial.printf("[MESH] ℹ️  No neighbors in advertising from %s (mfgData too short)\n", peerId.c_str());
        }
        
      }
    }
    
    // Update the peer with address
    updatePeer(peerName, advertisedDevice.getRSSI(), peerAddress);
  }
};

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

  // --- GATT server for phone ---
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  Serial.println("[INIT] ✅ GATT Server created");

  BLEService* service = pServer->createService(SERVICE_UUID);
  pCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  // NimBLE auto-adds the 2902 descriptor; manual addition is deprecated in ESP32 core 3.x
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->setValue("READY");
  service->start();
  Serial.println("[INIT] ✅ BLE Service started");
  
  pServer->getAdvertising()->addServiceUUID(SERVICE_UUID);
  pServer->getAdvertising()->start();
  Serial.println("[INIT] ✅ Advertising started - Phone can now connect");

  // --- Scanner for peer ---
  pScan = BLEDevice::getScan();
  pScan->setAdvertisedDeviceCallbacks(new PeerScanCallbacks());
  pScan->setActiveScan(true);
  pScan->setInterval(50);  // More frequent scan
  pScan->setWindow(30);    // Shorter window
  Serial.println("[INIT] ✅ BLE Scanner configured");

  Serial.println("═══════════════════════════════════════");
  Serial.printf("[INIT] 🎉 %s is READY!\n", BLE_NAME);
  Serial.println("[INIT] 📱 Waiting for phone connection...");
  Serial.println("[INIT] 🔍 Current State: IDLE");
  Serial.println("[INIT] 💡 Send 'PAIRING' or 'SEARCHING' via Serial or App to start discovering");
  Serial.println("═══════════════════════════════════════\n");
}

void loop() {
  // Check for Serial commands (for testing from Arduino IDE)
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    
    if (cmd == "PAIRING" || cmd == "STARTPAIRING") {
      enterState(PAIRING);
      Serial.println("[SERIAL CMD] PAIRING mode activated");
    } else if (cmd == "SEARCHING" || cmd == "STARTSEARCHING") {
      enterState(SEARCHING);
      Serial.println("[SERIAL CMD] SEARCHING mode activated");
    } else if (cmd == "IDLE" || cmd == "STOPMODE") {
      enterState(IDLE);
      Serial.println("[SERIAL CMD] Returned to IDLE");
    } else if (cmd == "CLEAR") {
      preferences.begin("peers", false);
      preferences.clear();
      preferences.end();
      Serial.println("[SERIAL CMD] Cleared paired devices from flash");
    } else if (cmd == "STATUS") {
      Serial.print("[STATUS] Current state: ");
      switch (currentState) {
        case IDLE: Serial.println("IDLE"); break;
        case PAIRING: Serial.println("PAIRING"); break;
        case SEARCHING: Serial.println("SEARCHING"); break;
        case CONNECTED: Serial.println("CONNECTED"); break;
      }
    } else {
      Serial.println("[SERIAL CMD] Unknown command. Available: PAIRING, SEARCHING, IDLE, CLEAR, STATUS");
    }
  }
  
  // Update LED blinking pattern
  if (blinkColorA != 0) {
    updateLedBlink();
  }
  
  // Check state timeout (PAIRING/SEARCHING -> IDLE after 60s)
  checkStateTimeout();
  
  // Pulisci peer vecchi
  cleanupOldPeers();
  
  // Scan for peers when in PAIRING, SEARCHING or CONNECTED mode
  if (scanEnabled && (currentState == PAIRING || currentState == SEARCHING || currentState == CONNECTED)) {
    pScan->start(3.0 /* seconds - increased for better peer detection */, false);
    pScan->clearResults();
  }

  // Report to phone at ~10Hz when connected (always report, regardless of state)
  // Each device always communicates with its own phone
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
            peers[i].fullName.c_str(),
            peers[i].rssi,
            peers[i].dist,
            peers[i].viaId.length() > 0 ? peers[i].viaId.c_str() : "Direct");
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

  delay(10);  // Reduced to 10ms for more responsive LED and state management
}