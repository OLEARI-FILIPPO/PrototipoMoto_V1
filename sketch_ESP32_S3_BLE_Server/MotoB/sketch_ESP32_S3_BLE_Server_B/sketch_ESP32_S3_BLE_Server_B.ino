#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
// Nota: la comunicazione UWB avviene tramite AT commands via UART2
// (modulo MaUWB DW3000 con STM32 – non richiede libreria DW1000/DW3000)
// Riferimento: https://github.com/Makerfabs/MaUWB_ESP32S3-with-STM32-AT-Command

#include <math.h>
#include <cstdlib>

#include "comm_mode.h"  // CommModeManager: UWB <=> LoRa switching

// ---- CommMode singleton ----
CommModeManager commManager;

// =============================================================================
// GESTIONE UWB (MaUWB DW3000 – comunicazione via AT command su UART2)
// MotoA = Anchor 0 (nodo fisso di riferimento)
// MotoB = Tag 0, MotoC = Tag 1 (nodi in movimento)
// =============================================================================
float currentUwbDist = -1.0f;
unsigned long lastUwbReadingTime = 0;
bool uwbInitialized = false;
String uwbLineBuffer = "";  // buffer riga AT in arrivo dal modulo

void initUWB() {
  Serial.println("\n[UWB] Avvio inizializzazione modulo (AT command mode)...");

  // Reset hardware del modulo STM32/UWB
  pinMode(UWB_RESET, OUTPUT);
  digitalWrite(UWB_RESET, LOW);
  delay(50);
  digitalWrite(UWB_RESET, HIGH);
  delay(500);  // attendi riavvio STM32

  // Inizializza UART2 per comunicazione AT con STM32
  uwbSerial.begin(115200, SERIAL_8N1, UWB_RXD, UWB_TXD);
  uwbLineBuffer.reserve(128);
  delay(100);

  // Test comunicazione
  String resp = uwbSendAT("AT?", 2000);
  if (resp.indexOf("OK") < 0) {
    Serial.println("[UWB]  Modulo non risponde ai comandi AT. Fallback: LoRa.");
    return;
  }

  // Configura ruolo e ID: MotoA = Anchor 0, MotoB = Tag 0, MotoC = Tag 1
  int uwbIndex = 0;
  int uwbRole  = 1;  // 1 = Anchor, 0 = Tag
  if (String(DEVICE_ID) == "B") { uwbIndex = 0; uwbRole = 0; }
  else if (String(DEVICE_ID) == "C") { uwbIndex = 1; uwbRole = 0; }

  uwbSendAT("AT+RESTORE", 5000);
  String cfgCmd = "AT+SETCFG=" + String(uwbIndex) + "," + String(uwbRole) + ",0,1";
  uwbSendAT(cfgCmd, 2000);
  uwbSendAT("AT+SETCAP=10,15", 2000);
  uwbSendAT("AT+SETRPT=1", 2000);
  uwbSendAT("AT+SAVE", 2000);
  uwbSendAT("AT+RESTART", 3000);

  uwbInitialized = true;
  Serial.printf("[UWB] Configurazione completata: %s (Index=%d, Ruolo=%s)\n",
    DEVICE_ID, uwbIndex, uwbRole == 1 ? "ANCHOR" : "TAG");
}

float readUwbDistanceMeters() {
  if (!uwbInitialized) return -1.0f;

  // Leggi dati in arrivo dal modulo UWB (non bloccante)
  while (uwbSerial.available()) {
    char c = uwbSerial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      float dist = uwbParseRangeDistance(uwbLineBuffer);
      uwbLineBuffer = "";
      if (dist >= 0.0f) {
        currentUwbDist    = dist;
        lastUwbReadingTime = millis();
        Serial.printf("[UWB-SUCCESS] Distanza: %.2f m\n", currentUwbDist);
      }
    } else {
      uwbLineBuffer += c;
    }
  }

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
static const char* DEVICE_ID = "B";
static const char* BLE_NAME  = "ESP32_S3_BLE_B";

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
