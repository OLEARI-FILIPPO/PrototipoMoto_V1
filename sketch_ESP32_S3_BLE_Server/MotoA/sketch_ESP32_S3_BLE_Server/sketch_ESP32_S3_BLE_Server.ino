#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
#include <SPI.h>

// Imposta a 1 quando la libreria arduino-DW1000 è installata:
// https://github.com/thotro/arduino-dw1000
#define USE_UWB 0
#ifdef USE_UWB
#include <DW1000Ranging.h>
#endif

#include <math.h>
#include <cstdlib>

#include "comm_mode.h"  // CommModeManager: UWB <=> LoRa switching

// ---- CommMode singleton ----
CommModeManager commManager;

// =============================================================================
// GESTIONE UWB (DW1000/DW3000)
// =============================================================================
float currentUwbDist = -1.0f;
unsigned long lastUwbReadingTime = 0;
bool uwbInitialized = false;

#ifdef USE_UWB
void cbUwbNewRange() {
  currentUwbDist    = DW1000Ranging.getDistantDevice()->getRange();
  lastUwbReadingTime = millis();
  Serial.printf("[UWB-SUCCESS] Ranging valido! Distanza: %.2f m | Peer MAC: %04X | RX Power: %.1f dBm\n",
                currentUwbDist,
                DW1000Ranging.getDistantDevice()->getShortAddress(),
                DW1000Ranging.getDistantDevice()->getRXPower());
}

void cbUwbNewDevice(DW1000Device* device) {
  Serial.printf("[UWB-INFO] Nuovo dispositivo UWB connesso! MAC: %04X\n", device->getShortAddress());
}

void cbUwbInactiveDevice(DW1000Device* device) {
  Serial.printf("[UWB-WARN] Dispositivo UWB disconnesso: %04X\n", device->getShortAddress());
  currentUwbDist = -1.0f;
}
#endif // USE_UWB

void initUWB() {
  Serial.println("\n[UWB] Avvio inizializzazione modulo...");

  // Disabilita LoRa dal bus SPI condiviso durante init UWB
  pinMode(LORA_CS, OUTPUT);
  digitalWrite(LORA_CS, HIGH);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI);

  // Probe SPI: leggi DEV_ID del DW1000 prima di usare la libreria
  {
    pinMode(UWB_CS, OUTPUT);
    digitalWrite(UWB_CS, HIGH);
    delay(5);
    SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
    digitalWrite(UWB_CS, LOW);
    SPI.transfer(0x00);
    uint8_t b0 = SPI.transfer(0x00);
    uint8_t b1 = SPI.transfer(0x00);
    uint8_t b2 = SPI.transfer(0x00);
    uint8_t b3 = SPI.transfer(0x00);
    digitalWrite(UWB_CS, HIGH);
    SPI.endTransaction();
    uint32_t devId = ((uint32_t)b3 << 24) | ((uint32_t)b2 << 16) |
                     ((uint32_t)b1 << 8)  |  (uint32_t)b0;
    Serial.printf("[UWB]  DEV_ID raw = 0x%08X\n", devId);
    bool present = ((devId >> 16) == 0xDECA) && (devId != 0xFFFFFFFF) && (devId != 0x00000000);
    if (present) {
      Serial.println("[UWB]  Modulo UWB rilevato via SPI! (DEV_ID valido)");
    } else {
      Serial.println("[UWB]  Modulo UWB NON risponde su SPI. Init saltato. Fallback: LoRa.");
      return;
    }
  }

#ifdef USE_UWB
  DW1000Ranging.initCommunication(UWB_RST, UWB_CS, UWB_IRQ);

  // MAC univoco per device per evitare collisioni
  String macStr = "DE:AD:BE:EF:00:0";
  macStr += String(DEVICE_ID);

  DW1000Ranging.attachNewRange(cbUwbNewRange);
  DW1000Ranging.attachNewDevice(cbUwbNewDevice);
  DW1000Ranging.attachInactiveDevice(cbUwbInactiveDevice);

  Serial.println("[UWB] Configurazione SPI e pin completata.");
  Serial.printf("[UWB] Indirizzo MAC assegnato: %s\n", macStr.c_str());

  // MotoA = Anchor (punto fisso di riferimento), B e C = Tag (nodi mobili)
  if (String(DEVICE_ID) == "A") {
    DW1000Ranging.startAsAnchor((char *)macStr.c_str(), DW1000.MODE_LONGDATA_RANGE_ACCURACY);
    Serial.println("[UWB] Modulo configurato come ANCHOR (nodo fisso di riferimento).");
    Serial.println("[UWB] In attesa dei TAG (MotoB, MotoC)...");
  } else {
    DW1000Ranging.startAsTag((char *)macStr.c_str(), DW1000.MODE_LONGDATA_RANGE_ACCURACY);
    Serial.println("[UWB] Modulo configurato come TAG (nodo in movimento).");
    Serial.println("[UWB] In ricerca dell Anchor (MotoA)...");
  }

  uwbInitialized = true;
#else
  Serial.println("[UWB] Modulo UWB disabilitato a compile-time (USE_UWB=0).");
#endif // USE_UWB
}

float readUwbDistanceMeters() {
  if (!uwbInitialized) return -1.0f;
#ifdef USE_UWB
  DW1000Ranging.loop();
#endif
  if (millis() - lastUwbReadingTime > 3000 && currentUwbDist >= 0.0f) {
    Serial.println("[UWB-ERROR] Nessun dato recente dal modulo UWB (Timeout 3s). Verificare connessione.");
    currentUwbDist = -1.0f;
  }
  return currentUwbDist;
}

// =============================================================================
// BLE UUIDs
// =============================================================================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// =============================================================================
// CONFIG -- solo queste 2 righe cambiano tra A / B / C
// =============================================================================
static const char* DEVICE_ID = "A";
static const char* BLE_NAME  = "ESP32_S3_BLE_A";

// =============================================================================
// NeoPixel (GPIO 48 su ESP32-S3 DevKit)
// =============================================================================
const int ledPin    = 48;
const int numPixels = 1;
Adafruit_NeoPixel pixel(numPixels, ledPin, NEO_GRB + NEO_KHZ800);

// =============================================================================
// 1. TIPI (definiti prima delle funzioni che li usano)
// =============================================================================
enum DeviceState {
  IDLE,       // In attesa
  PAIRING,    // Accetta connessioni da altri dispositivi (timeout 30s)
  SEARCHING,  // Cerca dispositivi in PAIRING (timeout 30s)
  CONNECTED   // Connesso alla rete mesh
};

struct PeerInfo {
  String id;            // Identificatore breve "A", "B" ...
  String fullName;      // Nome BLE completo
  String address;       // Indirizzo MAC (per persistenza)
  int    rssi;          // Qualita del segnale (peer diretto)
  float  dist;          // Distanza calcolata (m)
  bool   isIndirect;    // true se il dato proviene da un altro peer
  String viaId;         // ID del peer che ha segnalato questo (se indiretto)
  unsigned long lastSeenMs;
};

// =============================================================================
// 2. VARIABILI GLOBALI
// =============================================================================
BLEServer*         pServer         = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool               phoneConnected  = false;
Preferences        preferences;

DeviceState   currentState    = IDLE;
unsigned long stateStartMs    = 0;
const unsigned long STATE_TIMEOUT_MS = 30000;

unsigned long lastBlinkMs     = 0;
const unsigned long BLINK_INTERVAL_MS = 500;
bool          ledState        = false;
uint32_t      blinkColorA     = 0;
uint32_t      blinkColorB     = 0;

static BLEScan* pScan       = nullptr;
static bool     scanEnabled = false;
unsigned long   lastReportMs = 0;

#define MAX_PEERS 12
PeerInfo peers[MAX_PEERS];
int      peerCount = 0;

// =============================================================================
// 3. PROTOTIPI
// =============================================================================
void   setLedOff();
void   setLedBlinkPattern(uint32_t colorA, uint32_t colorB = 0);
void   setLedSolid(uint32_t color);
void   updateLedBlink();
void   updateAdvertising();
void   enterState(DeviceState newState);
float  rssiToDistanceMeters(int rssi);
bool   isPeerPaired(String address);
void   savePeerToFlash(String address);

// =============================================================================
// 4. IMPLEMENTAZIONE
// =============================================================================

float rssiToDistanceMeters(int rssi) {
  const float txPower = -59.0f;  // RSSI a 1 m
  const float n       =   2.0f;  // esponente path-loss
  return powf(10.0f, (txPower - (float)rssi) / (10.0f * n));
}

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

void setLedBlinkPattern(uint32_t colorA, uint32_t colorB) {
  blinkColorA = colorA;
  blinkColorB = colorB;
  lastBlinkMs = millis();
  ledState    = false;
}

void updateLedBlink() {
  unsigned long now = millis();
  if (now - lastBlinkMs >= BLINK_INTERVAL_MS) {
    lastBlinkMs = now;
    ledState    = !ledState;
    pixel.setPixelColor(0, ledState ? blinkColorA : (blinkColorB != 0 ? blinkColorB : (uint32_t)0));
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
      setLedBlinkPattern(pixel.Color(255, 0, 0));  // Rosso lampeggiante
      scanEnabled = true;
      break;
    case SEARCHING:
      Serial.println("[STATE] Entering SEARCHING (30s)");
      setLedBlinkPattern(pixel.Color(0, 0, 255));  // Blu lampeggiante
      scanEnabled = true;
      break;
    case CONNECTED:
      Serial.println("[STATE] Entering CONNECTED STATE");
      Serial.printf("[STATE] Current peers: %d\n", peerCount);
      for (int i = 0; i < peerCount; i++) {
        Serial.printf("[STATE]   - %s: RSSI=%d, Dist=%.2fm, %s\n",
          peers[i].id.c_str(), peers[i].rssi, peers[i].dist,
          peers[i].isIndirect ? "INDIRECT" : "DIRECT");
      }
      setLedBlinkPattern(pixel.Color(0, 0, 255), pixel.Color(0, 255, 0));  // Blu-Verde
      scanEnabled = true;
      Serial.println("[STATE] CONNECTED: continuera scansione e invio dati");
      break;
  }

  updateAdvertising();
  Serial.printf("[STATE] Entered state: %d, scanEnabled: %d\n", currentState, scanEnabled);
}

void updateAdvertising() {
  if (pServer == nullptr) {
    Serial.println("[ADV] ERROR: pServer is NULL!");
    return;
  }

  BLEAdvertising* pAdvertising = pServer->getAdvertising();
  pAdvertising->stop();
  Serial.println("[ADV] Stopped previous advertising");

  pAdvertising->addServiceUUID(SERVICE_UUID);
  Serial.printf("[ADV] Added Service UUID: %s\n", SERVICE_UUID);

  // Manufacturer data: [0xFF 0xFF State ID1 RSSI1 ID2 RSSI2 ...]
  String mfgData = "";
  mfgData += (char)0xFF;
  mfgData += (char)0xFF;
  mfgData += (char)currentState;

  int added = 0;
  for (int i = 0; i < peerCount && added < 4; i++) {
    if (!peers[i].isIndirect && peers[i].id.length() > 0) {
      mfgData += peers[i].id.charAt(0);
      mfgData += (char)(peers[i].rssi);
      added++;
    }
  }

  Serial.printf("[ADV] Manufacturer data len %d, %d neighbors encoded\n", mfgData.length(), added);

  BLEAdvertisementData advData;
  advData.setFlags(0x06);
  advData.setCompleteServices(BLEUUID(SERVICE_UUID));
  advData.setManufacturerData(mfgData);
  pAdvertising->setAdvertisementData(advData);

  BLEAdvertisementData scanResponseData;
  scanResponseData.setName(BLE_NAME);
  pAdvertising->setScanResponseData(scanResponseData);

  pAdvertising->start();
  Serial.printf("[ADV] Advertising STARTED with state: %d (phoneConnected=%d)\n",
                currentState, phoneConnected);
}

void checkStateTimeout() {
  unsigned long now = millis();
  if ((currentState == PAIRING || currentState == SEARCHING) &&
      (now - stateStartMs >= STATE_TIMEOUT_MS)) {

    Serial.printf("[STATE] TIMEOUT! State: %s, Duration: %lu ms, PeerCount: %d\n",
      currentState == PAIRING ? "PAIRING" : "SEARCHING",
      now - stateStartMs, peerCount);

    if (peerCount > 0) {
      Serial.printf("[STATE] Transitioning to CONNECTED (found %d peers)\n", peerCount);
      for (int i = 0; i < peerCount; i++) {
        Serial.printf("  - Peer %d: %s (RSSI: %d, Dist: %.2fm, %s)\n",
          i, peers[i].id.c_str(), peers[i].rssi, peers[i].dist,
          peers[i].isIndirect ? "INDIRECT" : "DIRECT");
      }
      enterState(CONNECTED);
    } else {
      Serial.println("[STATE] Returning to IDLE (no peers found)");
      enterState(IDLE);
    }
  }
}

String extractIdFromName(String name) {
  int idx = name.lastIndexOf('_');
  if (idx > 0 && idx < name.length() - 1) {
    return name.substring(idx + 1);
  }
  return name;
}

void updatePeer(const String& fullName, int rssi, String address = "", bool indirect = false, String viaId = "", float indirectDist = 0.0) {
  unsigned long now = millis();
  String pid = extractIdFromName(fullName);

  if (pid == String(DEVICE_ID)) return;  // ignora se stessi

  for (int i = 0; i < peerCount; i++) {
    if (peers[i].id == pid) {
      if (!indirect) {
        peers[i].rssi       = rssi;
        peers[i].dist       = rssiToDistanceMeters(rssi);
        peers[i].isIndirect = false;
        peers[i].lastSeenMs = now;
        if (address != "") peers[i].address = address;
      } else {
        if (peers[i].isIndirect || (now - peers[i].lastSeenMs > 2000)) {
          peers[i].isIndirect = true;
          peers[i].viaId      = viaId;
          peers[i].dist       = indirectDist;
          peers[i].rssi       = rssi;
          peers[i].lastSeenMs = now;
        }
      }
      return;
    }
  }

  if (peerCount < MAX_PEERS) {
    peers[peerCount].id         = pid;
    peers[peerCount].fullName   = fullName;
    peers[peerCount].address    = address;
    peers[peerCount].isIndirect = indirect;
    peers[peerCount].viaId      = viaId;
    peers[peerCount].lastSeenMs = now;

    if (indirect) {
      peers[peerCount].dist = indirectDist;
      peers[peerCount].rssi = rssi;
    } else {
      peers[peerCount].rssi = rssi;
      peers[peerCount].dist = rssiToDistanceMeters(rssi);
      if ((currentState == PAIRING || currentState == SEARCHING) && address != "") {
        savePeerToFlash(address);
      }
    }

    peerCount++;
    Serial.printf("[PEERS] Added new %s peer: %s (via %s), Dist: %.2fm (total: %d)\n",
      indirect ? "INDIRECT" : "DIRECT", pid.c_str(), viaId.c_str(),
      peers[peerCount - 1].dist, peerCount);
  }
}

void cleanupOldPeers() {
  unsigned long now = millis();
  for (int i = 0; i < peerCount; i++) {
    if (now - peers[i].lastSeenMs > 8000) {
      peers[i] = peers[peerCount - 1];
      peerCount--;
      i--;
    }
  }
}

String jsonPeerMessage() {
  String json = "{\"peers\":[";
  int directCount   = 0;
  int indirectCount = 0;

  for (int i = 0; i < peerCount; i++) {
    if (i > 0) json += ",";
    json += "{\"id\":\"" + peers[i].fullName + "\"";
    json += ",\"rssi\":" + String(peers[i].rssi);
    if (peers[i].isIndirect) {
      json += ",\"via\":\"" + peers[i].viaId + "\"";
      indirectCount++;
    } else {
      directCount++;
    }
    json += ",\"dist\":" + String(peers[i].dist, 2) + "}";
  }

  json += "],\"src\":\"" + String(DEVICE_ID) + "\"";
  json += ",\"comm\":\"" + String(commManager.modeStr()) + "\"";
  json += "}";

  Serial.printf("[JSON] Built message: %d total peers (%d direct, %d indirect) | CommMode: %s\n",
                peerCount, directCount, indirectCount, commManager.modeStr());
  return json;
}

// =============================================================================
// BLE CALLBACKS
// =============================================================================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    phoneConnected = true;
    Serial.println("[PHONE] Phone connected");
    updateAdvertising();
  }
  void onDisconnect(BLEServer* server) override {
    phoneConnected = false;
    Serial.println("[PHONE] Phone disconnected");
    updateAdvertising();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* chr) override {
    String arduinoString = chr->getValue();
    std::string value(arduinoString.c_str());
    if (value.empty()) return;

    Serial.printf("[CMD-RECEIVED] '%s' (length=%d)\n", value.c_str(), value.length());

    if (value == "STARTPAIRING")  { enterState(PAIRING);                      Serial.println("[CMD] PAIRING mode");  return; }
    if (value == "STARTSEARCHING"){ enterState(SEARCHING);                     Serial.println("[CMD] SEARCHING mode"); return; }
    if (value == "STOPMODE")      { enterState(IDLE);                          Serial.println("[CMD] IDLE");           return; }
    if (value == "COMM_UWB")      { commManager.setOverride(OVERRIDE_UWB);                                             return; }
    if (value == "COMM_LORA")     { commManager.setOverride(OVERRIDE_LORA);                                            return; }
    if (value == "COMM_AUTO")     { commManager.setOverride(OVERRIDE_AUTO);                                            return; }

    if (value == "0") {
      pixel.clear();
      pixel.show();
      Serial.println("LED SPENTO");
      return;
    }
    if (value.rfind("PEERLED:", 0) == 0) {
      Serial.printf("[CMD] %s\n", value.c_str());
      return;
    }
    if (value.rfind("PEERSETCOLOR:", 0) == 0) {
      Serial.printf("[CMD] %s\n", value.c_str());
      return;
    }
    if (value[0] == '#' && value.length() == 7) {
      uint32_t color = (uint32_t)strtol(value.substr(1).c_str(), NULL, 16);
      uint8_t r = (color >> 16) & 0xFF;
      uint8_t g = (color >> 8)  & 0xFF;
      uint8_t b =  color        & 0xFF;
      pixel.setPixelColor(0, pixel.Color(r, g, b));
      pixel.show();
      Serial.printf("COLORE IMPOSTATO: #%s (R:%d, G:%d, B:%d)\n", value.substr(1).c_str(), r, g, b);
      return;
    }
    pixel.setPixelColor(0, pixel.Color(255, 255, 255));
    pixel.show();
    Serial.println("LED ACCESO (Bianco)");
  }
};

class PeerScanCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) override {
    if (!advertisedDevice.haveServiceUUID()) {
      Serial.println("[SCAN] Rejected: no service UUID - " + advertisedDevice.getName());
      return;
    }
    if (!advertisedDevice.isAdvertisingService(BLEUUID(SERVICE_UUID))) {
      Serial.println("[SCAN] Rejected: wrong service UUID - " + advertisedDevice.getName());
      return;
    }

    const String peerName = advertisedDevice.getName();
    if (peerName.length() == 0) {
      Serial.println("[SCAN] Rejected: empty name");
      return;
    }

    Serial.printf("[SCAN] Found: %s, RSSI: %d, My state: %d\n",
                  peerName.c_str(), advertisedDevice.getRSSI(), currentState);

    if (peerName.indexOf("ESP") < 0) {
      Serial.printf("[SCAN] Rejected (no 'ESP' in name): %s\n", peerName.c_str());
      return;
    }
    if (peerName == String(BLE_NAME)) {
      Serial.printf("[SCAN] Rejected (ourselves): %s\n", peerName.c_str());
      return;
    }

    String peerAddress = advertisedDevice.getAddress().toString().c_str();
    bool accept = (currentState == PAIRING || currentState == SEARCHING) || isPeerPaired(peerAddress);

    if (!accept) {
      Serial.printf("[SCAN] Rejected (not paired, not in discovery): %s\n", peerName.c_str());
      return;
    }

    if (currentState == SEARCHING || currentState == PAIRING || currentState == CONNECTED) {
      String mfgData = advertisedDevice.getManufacturerData();
      if (mfgData.length() >= 3) {
        String peerId   = extractIdFromName(peerName);
        float  peerDist = rssiToDistanceMeters(advertisedDevice.getRSSI());

        Serial.printf("[MESH] Parsing mfgData from %s (len: %d)\n", peerName.c_str(), mfgData.length());

        if (mfgData.length() > 3) {
          int neighborCount = (mfgData.length() - 3) / 2;
          Serial.printf("[MESH] %d neighbor(s) in advertising from %s\n", neighborCount, peerId.c_str());

          for (int i = 3; i < mfgData.length() - 1; i += 2) {
            char   neighborChar = mfgData[i];
            int8_t neighborRssi = (int8_t)mfgData[i + 1];
            String neighborId   = String(neighborChar);

            if (neighborId == String(DEVICE_ID)) {
              Serial.printf("[MESH] Skipping neighbor %s (it's me)\n", neighborId.c_str());
              continue;
            }

            float  distToNeighbor   = rssiToDistanceMeters(neighborRssi);
            float  totalDist        = peerDist + distToNeighbor;
            String neighborFullName = "ESP32_S3_BLE_" + neighborId;
            int    approxRssi       = advertisedDevice.getRSSI() + neighborRssi;

            updatePeer(neighborFullName, approxRssi, "", true, peerId, totalDist);
            Serial.printf("[MESH] Added INDIRECT peer: %s via %s | RSSI: %d | Dist: %.2fm\n",
              neighborFullName.c_str(), peerId.c_str(), approxRssi, totalDist);
          }
        } else {
          Serial.printf("[MESH] No neighbors in advertising from %s\n", peerId.c_str());
        }
      }
    }

    updatePeer(peerName, advertisedDevice.getRSSI(), peerAddress);
  }
};

// =============================================================================
// SETUP
// =============================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n\n");
  Serial.println("=======================================");
  Serial.println("[INIT] ESP32-S3 BLE Mesh Server Starting...");
  Serial.printf("[INIT] Device Name: %s\n", BLE_NAME);
  Serial.printf("[INIT] Service UUID: %s\n", SERVICE_UUID);
  Serial.printf("[INIT] Characteristic UUID: %s\n", CHARACTERISTIC_UUID);
  Serial.println("=======================================");

  pixel.begin();
  pixel.setBrightness(50);
  pixel.clear();
  pixel.show();
  Serial.println("[INIT] NeoPixel initialized");

  initUWB();

  commManager.begin();
  Serial.println("[INIT] CommMode Manager initialized");

  BLEDevice::init(BLE_NAME);
  Serial.println("[INIT] BLE Device initialized");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  Serial.println("[INIT] GATT Server created");

  BLEService* service = pServer->createService(SERVICE_UUID);
  pCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ   |
    BLECharacteristic::PROPERTY_WRITE  |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->setValue("READY");
  service->start();
  Serial.println("[INIT] BLE Service started");

  pServer->getAdvertising()->addServiceUUID(SERVICE_UUID);
  pServer->getAdvertising()->start();
  Serial.println("[INIT] Advertising started - Phone can now connect");

  pScan = BLEDevice::getScan();
  pScan->setAdvertisedDeviceCallbacks(new PeerScanCallbacks());
  pScan->setActiveScan(true);
  pScan->setInterval(50);
  pScan->setWindow(30);
  Serial.println("[INIT] BLE Scanner configured");

  Serial.println("=======================================");
  Serial.printf("[INIT] %s is READY!\n", BLE_NAME);
  Serial.println("[INIT] Waiting for phone connection...");
  Serial.println("[INIT] Current State: IDLE");
  Serial.println("[INIT] Send 'PAIRING' or 'SEARCHING' to start discovering");
  Serial.println("=======================================\n");
}

// =============================================================================
// LOOP
// =============================================================================
void loop() {
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();

    if      (cmd == "PAIRING"   || cmd == "STARTPAIRING")  { enterState(PAIRING);   Serial.println("[SERIAL CMD] PAIRING mode"); }
    else if (cmd == "SEARCHING" || cmd == "STARTSEARCHING") { enterState(SEARCHING); Serial.println("[SERIAL CMD] SEARCHING mode"); }
    else if (cmd == "IDLE"      || cmd == "STOPMODE")       { enterState(IDLE);      Serial.println("[SERIAL CMD] IDLE"); }
    else if (cmd == "CLEAR") {
      preferences.begin("peers", false);
      preferences.clear();
      preferences.end();
      Serial.println("[SERIAL CMD] Cleared paired devices from flash");
    }
    else if (cmd == "STATUS") {
      const char* stateStr[] = {"IDLE", "PAIRING", "SEARCHING", "CONNECTED"};
      Serial.printf("[STATUS] State: %s\n", stateStr[currentState]);
    }
    else {
      Serial.println("[SERIAL CMD] Unknown. Available: PAIRING, SEARCHING, IDLE, CLEAR, STATUS");
    }
  }

  if (blinkColorA != 0) updateLedBlink();

  checkStateTimeout();
  cleanupOldPeers();

  if (scanEnabled && (currentState == PAIRING || currentState == SEARCHING || currentState == CONNECTED)) {
    pScan->start(3.0, false);
    pScan->clearResults();
  }

  if (phoneConnected && (millis() - lastReportMs) > 100) {
    lastReportMs = millis();
    String payload = jsonPeerMessage();
    pCharacteristic->setValue(payload.c_str());
    pCharacteristic->notify();

    static unsigned long lastStateLog = 0;
    if (millis() - lastStateLog > 3000) {
      const char* stateStr[] = {"IDLE", "PAIRING", "SEARCHING", "CONNECTED"};
      Serial.println("=======================================");
      Serial.printf("[REPORT] %s Status Report\n", BLE_NAME);
      Serial.printf("[REPORT] State: %s | Scan: %s | Phone: %s\n",
        stateStr[currentState],
        scanEnabled    ? "ON"         : "OFF",
        phoneConnected ? "CONNECTED"  : "DISCONNECTED");
      Serial.printf("[REPORT] Total Peers: %d\n", peerCount);
      if (peerCount > 0) {
        Serial.println("[REPORT] Peer List:");
        for (int i = 0; i < peerCount; i++) {
          Serial.printf("[REPORT]   %d) %s | RSSI: %d | Dist: %.2fm | Via: %s\n",
            i + 1,
            peers[i].fullName.c_str(),
            peers[i].rssi,
            peers[i].dist,
            peers[i].viaId.length() > 0 ? peers[i].viaId.c_str() : "Direct");
        }
      } else {
        Serial.println("[REPORT] No peers detected!");
        if (currentState == IDLE) {
          Serial.println("[REPORT] TIP: Send PAIRING or SEARCHING to discover devices");
        } else {
          Serial.println("[REPORT] TIP: Ensure other ESP32 are powered on and in PAIRING/SEARCHING mode");
        }
      }
      Serial.println("=======================================");
      lastStateLog = millis();
    }
  }

  // CommMode: aggiorna UWB e seleziona modalita ottimale
  {
    float uwbDist = readUwbDistanceMeters();
    if (uwbDist >= 0.0f) commManager.onUwbReading(uwbDist);

    float bestDist = (uwbDist >= 0.0f) ? uwbDist : 9999.0f;
    for (int i = 0; i < peerCount; i++) {
      if (!peers[i].isIndirect && peers[i].dist < bestDist) bestDist = peers[i].dist;
    }
    CommMode prevMode = commManager.mode();
    commManager.update(bestDist);
    if (commManager.mode() != prevMode) {
      Serial.printf("[COMM] Modalita cambiata: %s\n", commManager.modeStr());
    }
  }

  // Log peer count changes
  {
    static int _lastPeerCount = -1;
    if (peerCount != _lastPeerCount) {
      Serial.printf("[PEERS] Peer count: %d -> %d\n", _lastPeerCount, peerCount);
      for (int i = 0; i < peerCount; i++) {
        Serial.printf("  %s %s | %.1fm | RSSI %d\n",
          peers[i].isIndirect ? "<" : ">",
          peers[i].id.c_str(), peers[i].dist, peers[i].rssi);
      }
      _lastPeerCount = peerCount;
    }
  }

  delay(10);
}
