#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
#include <SPI.h>

// Imposta a 1 quando la libreria DW3000 è installata:
// https://github.com/Makerfabs/Makerfabs-ESP32-UWB
// Installazione Arduino IDE: Sketch → Include Library → Add .ZIP Library
#define USE_UWB 1
#ifdef USE_UWB
#include <dw3000.h>
#endif

#include <math.h>
#include <cstdlib>

#include "comm_mode.h"  // CommModeManager: UWB <=> LoRa switching

// ---- CommMode singleton ----
CommModeManager commManager;

// =============================================================================
// GESTIONE UWB DW3000  (DS-TWR / SS-TWR  –  SPI condiviso con LoRa)
// =============================================================================
float currentUwbDist = -1.0f;
unsigned long lastUwbReadingTime = 0;
bool uwbInitialized = false;

// ---- Timing DS-TWR (microsecondi; convertiti in tick DW3000 dove necessario) ----
#define UWB_TX_ANT_DLY                  16385U  // Ritardo antenna TX (calibrare su banco)
#define UWB_RX_ANT_DLY                  16385U  // Ritardo antenna RX
#define UWB_POLL_RX_TO_RESP_TX_DLY_UUS   2000U  // Delay fisso risposta Anchor dopo Poll RX
#define UWB_POLL_TX_TO_RESP_RX_DLY_UUS    500U  // Finestra RX Tag dopo Poll TX
#define UWB_RESP_RX_TO_FINAL_TX_DLY_UUS   300U  // Delay TX Final dopo Reply RX (Tag)
#define UWB_RESP_RX_TIMEOUT_UUS            600U  // Timeout RX Reply (Tag)
#define UWB_FINAL_RX_TIMEOUT_UUS          2500U  // Timeout RX Final (Anchor)
#define UWB_PRE_TIMEOUT                      5U  // Timeout rilevamento preambolo (PAC)
#define UWB_UUS_TO_TICKS               63898ULL  // tick DW3000 per µs  (499.2 × 128 tick/µs)
#define UWB_SPEED_OF_LIGHT          299702547.0  // m/s
#define UWB_DWT_TS_UNIT   (1.0 / (499.2e6 * 128.0))  // secondi per tick DW3000

// ---- Indici byte nei frame DS-TWR ----
#define UWB_MSG_SN_IDX          2   // Sequence number nel frame
#define UWB_MSG_COMMON_LEN     10   // Header comune per confronto tipo frame
#define UWB_RESP_POLL_RX_IDX   10   // poll_rx_ts (4 B) nel Reply Anchor
#define UWB_RESP_RESP_TX_IDX   14   // resp_tx_ts (4 B) nel Reply Anchor
#define UWB_FINAL_POLL_TX_IDX  10   // poll_tx_ts (4 B) nel Final Tag
#define UWB_FINAL_RESP_RX_IDX  14   // resp_rx_ts (4 B) nel Final Tag
#define UWB_FINAL_FINAL_TX_IDX 18   // final_tx_ts (4 B) nel Final Tag
#define UWB_TS_LEN              4   // Byte per campo timestamp nei messaggi

#ifdef USE_UWB
// ---- Configurazione canale DW3000 ----
static dwt_config_t uwb_config = {
  5,                       // Canale 5 (6.5 GHz)
  DWT_PLEN_128,            // Preambolo 128 simboli
  DWT_PAC8,                // PAC size 8
  9,                       // Codice TX preambolo (canale 5)
  9,                       // Codice RX preambolo
  1,                       // SFD non standard Decawave
  DWT_BR_6M8,              // Data rate 6.8 Mbps
  DWT_PHRMODE_STD,         // PHY header standard
  DWT_PHRRATE_STD,         // Rate PHY header standard
  (128 + 1 + 8 - 8),       // Timeout SFD
  DWT_STS_MODE_OFF,        // STS disabilitato
  DWT_STS_LEN_64,          // Lunghezza STS (ignorata con STS_OFF)
  DWT_PDOA_M0              // PDOA mode 0
};

// ---- Frame DS-TWR (IEEE 802.15.4 semplificati) ----
// Poll : Tag → Anchor  (12 byte payload; DW3000 aggiunge 2 byte FCS automaticamente)
static uint8_t uwb_tx_poll[]  = {0x41,0x88,0,0xCA,0xDE,'W','A','V','E',0xE0,0,0};
// Reply: Anchor → Tag  (byte 10-13: poll_rx_ts; 14-17: resp_tx_ts)
static uint8_t uwb_tx_reply[] = {0x41,0x88,0,0xCA,0xDE,'V','E','W','A',0xE1,0,0,0,0,0,0,0,0,0};
// Final: Tag → Anchor  (byte 10-13: poll_tx_ts; 14-17: resp_rx_ts; 18-21: final_tx_ts)
static uint8_t uwb_tx_final[] = {0x41,0x88,0,0xCA,0xDE,'W','A','V','E',0xE2,0,0,0,0,0,0,0,0,0,0,0,0,0};
static uint8_t uwb_rx_buf[sizeof(uwb_tx_final)];
static uint8_t uwb_frame_seq = 0;

// ---- Helper: legge timestamp TX o RX a 40 bit come uint64_t ----
static uint64_t uwb_get_tx_ts() {
  uint8_t ts[5];
  dwt_readtxtimestamp(ts);
  uint64_t t = 0;
  for (int i = 4; i >= 0; i--) { t <<= 8; t |= ts[i]; }
  return t;
}
static uint64_t uwb_get_rx_ts() {
  uint8_t ts[5];
  dwt_readrxtimestamp(ts);
  uint64_t t = 0;
  for (int i = 4; i >= 0; i--) { t <<= 8; t |= ts[i]; }
  return t;
}

// ---- Helper: serializza/deserializza 32 bit (little-endian) nei messaggi ----
static void uwb_put32(uint8_t *buf, uint32_t val) {
  for (int i = 0; i < UWB_TS_LEN; i++) { buf[i] = (uint8_t)val; val >>= 8; }
}
static uint32_t uwb_get32(const uint8_t *buf) {
  uint32_t v = 0;
  for (int i = UWB_TS_LEN - 1; i >= 0; i--) { v <<= 8; v |= buf[i]; }
  return v;
}
#endif // USE_UWB

void initUWB() {
  Serial.println("\n[UWB] Avvio inizializzazione DW3000...");

  // Mantieni LoRa disabilitato sul bus SPI condiviso durante l'init UWB
  pinMode(LORA_CS, OUTPUT);
  digitalWrite(LORA_CS, HIGH);

  // Configura il bus SPI con i pin fisici condivisi LoRa + UWB
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI);

#ifdef USE_UWB
  // Inizializza pin RST, IRQ e CS per il DW3000 tramite la libreria
  spiBegin(UWB_IRQ, UWB_RST);
  spiSelect(UWB_CS);
  // Riconfigura il bus SPI con i nostri pin (spiSelect() usa internamente i pin
  // default della board Makerfabs; questa chiamata ripristina il mapping corretto)
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI);

  delay(2);  // Breve pausa per stabilizzazione oscillatore

  // Attendi stato IDLE RC prima di procedere
  uint32_t t0 = millis();
  while (!dwt_checkidlerc()) {
    if (millis() - t0 > 500) {
      Serial.println("[UWB] ERRORE: DW3000 non raggiunge IDLE. Verificare alimentazione e cablaggio SPI.");
      return;
    }
    delay(5);
  }

  if (dwt_initialise(DWT_DW_INIT) == DWT_ERROR) {
    Serial.println("[UWB] ERRORE: inizializzazione DW3000 fallita. Controllare SCK/MISO/MOSI/CS.");
    return;
  }

  if (dwt_configure(&uwb_config)) {
    Serial.println("[UWB] ERRORE: configurazione canale DW3000 fallita.");
    return;
  }

  dwt_setrxantennadelay(UWB_RX_ANT_DLY);
  dwt_settxantennadelay(UWB_TX_ANT_DLY);

  Serial.printf("[UWB] DW3000 DEV_ID = 0x%08X\n", (unsigned int)dwt_readdevid());
  Serial.printf("[UWB] Pin: CS=%d  RST=%d  IRQ=%d  SCK=%d  MISO=%d  MOSI=%d\n",
                UWB_CS, UWB_RST, UWB_IRQ, LORA_SCK, LORA_MISO, LORA_MOSI);
  Serial.printf("[UWB] Ruolo: %s\n",
                String(DEVICE_ID) == "A"
                  ? "ANCHOR (Responder DS-TWR)"
                  : "TAG (Initiator SS/DS-TWR)");
  Serial.println("[UWB] DW3000 inizializzato con successo.");
  uwbInitialized = true;

#else
  // USE_UWB=0: probe SPI per verificare la presenza fisica del modulo
  {
    pinMode(UWB_CS, OUTPUT);
    digitalWrite(UWB_CS, HIGH);
    delay(5);
    SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
    digitalWrite(UWB_CS, LOW);
    SPI.transfer(0x00);               // comando: leggi registro 0 (DEV_ID)
    uint8_t b0 = SPI.transfer(0x00);
    uint8_t b1 = SPI.transfer(0x00);
    uint8_t b2 = SPI.transfer(0x00);
    uint8_t b3 = SPI.transfer(0x00);
    digitalWrite(UWB_CS, HIGH);
    SPI.endTransaction();
    uint32_t devId = ((uint32_t)b3 << 24) | ((uint32_t)b2 << 16) |
                     ((uint32_t)b1 << 8)  |  (uint32_t)b0;
    Serial.printf("[UWB] DEV_ID raw = 0x%08X\n", devId);
    bool present = ((devId >> 16) == 0xDECA) && (devId != 0xFFFFFFFF) && (devId != 0x00000000);
    Serial.println(present
      ? "[UWB] Modulo DW3000 rilevato su SPI (DEV_ID valido). Installare libreria e ricompilare con USE_UWB=1."
      : "[UWB] Modulo DW3000 NON risponde su SPI. Verificare cablaggio.");
  }
  Serial.println("[UWB] UWB disabilitato a compile-time (USE_UWB=0).");
#endif // USE_UWB
}

float readUwbDistanceMeters() {
  if (!uwbInitialized) return -1.0f;

#ifdef USE_UWB
  uint32_t status;
  const bool isAnchor = (String(DEVICE_ID) == "A");

  if (isAnchor) {
    // =========================================================================
    // ANCHOR (Responder):
    //   1) Attende Poll dal Tag
    //   2) Invia Reply con timestamps embedded (T2, T3)
    //   3) Attende Final dal Tag
    //   4) Calcola distanza DS-TWR dai 6 timestamp totali
    // =========================================================================
    dwt_setrxtimeout(0);
    dwt_setpreambledetecttimeout(0);
    dwt_rxenable(DWT_START_RX_IMMEDIATE);

    uint32_t tstart = millis();
    while (!((status = dwt_read32bitreg(SYS_STATUS_ID)) &
             (SYS_STATUS_RXFCG_BIT_MASK | SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR))) {
      if (millis() - tstart > 200) {
        dwt_forcetrxoff();
        return currentUwbDist;   // Nessun Poll ricevuto entro 200 ms
      }
    }
    if (!(status & SYS_STATUS_RXFCG_BIT_MASK)) {
      dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR);
      return currentUwbDist;
    }

    // Leggi il frame ricevuto
    uint32_t flen = dwt_read32bitreg(RX_FINFO_ID) & RXFLEN_MASK;
    if (flen <= sizeof(uwb_rx_buf)) dwt_readrxdata(uwb_rx_buf, flen, 0);
    dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_RXFCG_BIT_MASK);

    // Verifica tipo frame: deve essere un Poll
    uwb_rx_buf[UWB_MSG_SN_IDX] = 0;
    if (memcmp(uwb_rx_buf, uwb_tx_poll, UWB_MSG_COMMON_LEN) != 0) return currentUwbDist;

    // T2 = timestamp ricezione Poll (40 bit)
    uint64_t poll_rx_ts = uwb_get_rx_ts();

    // Calcola T3 = tempo schedulato TX Reply (arrotondato a multiplo di 2 per PLL)
    uint32_t resp_tx_time = (uint32_t)((poll_rx_ts +
      (uint64_t)UWB_POLL_RX_TO_RESP_TX_DLY_UUS * UWB_UUS_TO_TICKS) >> 8);
    resp_tx_time &= 0xFFFFFFFEUL;
    // Timestamp atteso della trasmissione Reply (include ritardo antenna TX)
    uint32_t resp_tx_ts_32 = (uint32_t)(((uint64_t)resp_tx_time << 8) + UWB_TX_ANT_DLY);

    // Componi Reply con T2 e T3 embedded
    uwb_tx_reply[UWB_MSG_SN_IDX] = uwb_frame_seq;
    uwb_put32(uwb_tx_reply + UWB_RESP_POLL_RX_IDX, (uint32_t)(poll_rx_ts & 0xFFFFFFFF));
    uwb_put32(uwb_tx_reply + UWB_RESP_RESP_TX_IDX, resp_tx_ts_32);

    // Programma TX differito e abilita RX automatico per il Final successivo
    dwt_setdelayedtrxtime(resp_tx_time);
    dwt_setrxaftertxdelay(UWB_RESP_RX_TO_FINAL_TX_DLY_UUS);
    dwt_setrxtimeout(UWB_FINAL_RX_TIMEOUT_UUS);
    dwt_setpreambledetecttimeout(UWB_PRE_TIMEOUT);
    dwt_writetxdata(sizeof(uwb_tx_reply), uwb_tx_reply, 0);
    dwt_writetxfctrl(sizeof(uwb_tx_reply) + 2, 0, 1);  // +2 FCS; ranging=1
    if (dwt_starttx(DWT_START_TX_DELAYED | DWT_RESPONSE_EXPECTED) != DWT_SUCCESS) {
      Serial.println("[UWB] ANCHOR: TX Reply in ritardo. Aumentare UWB_POLL_RX_TO_RESP_TX_DLY_UUS.");
      return currentUwbDist;
    }

    // Attendi Final dal Tag
    tstart = millis();
    while (!((status = dwt_read32bitreg(SYS_STATUS_ID)) &
             (SYS_STATUS_RXFCG_BIT_MASK | SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR))) {
      if (millis() - tstart > 400) {
        dwt_forcetrxoff();
        return currentUwbDist;
      }
    }
    if (!(status & SYS_STATUS_RXFCG_BIT_MASK)) {
      dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR);
      return currentUwbDist;
    }

    flen = dwt_read32bitreg(RX_FINFO_ID) & RXFLEN_MASK;
    if (flen <= sizeof(uwb_rx_buf)) dwt_readrxdata(uwb_rx_buf, flen, 0);
    dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_RXFCG_BIT_MASK);

    uwb_rx_buf[UWB_MSG_SN_IDX] = 0;
    if (memcmp(uwb_rx_buf, uwb_tx_final, UWB_MSG_COMMON_LEN) != 0) return currentUwbDist;

    // T6 = timestamp ricezione Final
    uint64_t final_rx_ts = uwb_get_rx_ts();

    // Leggi T1, T4, T5 dal messaggio Final
    uint32_t poll_tx_ts_32  = uwb_get32(uwb_rx_buf + UWB_FINAL_POLL_TX_IDX);
    uint32_t resp_rx_ts_32  = uwb_get32(uwb_rx_buf + UWB_FINAL_RESP_RX_IDX);
    uint32_t final_tx_ts_32 = uwb_get32(uwb_rx_buf + UWB_FINAL_FINAL_TX_IDX);

    // Calcolo distanza DS-TWR (tutti e sei i timestamp, aritmetica a 32 bit con wrap)
    // Ra = T4 - T1  (Round-trip 1 lato Tag)
    // Da = T3 - T2  (Turnaround Anchor)
    // Rb = T6 - T3  (Round-trip 2 lato Anchor)
    // Db = T5 - T4  (Turnaround Tag)
    // ToF = (Ra·Rb − Da·Db) / (Ra + Rb + Da + Db)
    double Ra = (double)((resp_rx_ts_32                              - poll_tx_ts_32 ) & 0xFFFFFFFFUL);
    double Da = (double)((resp_tx_ts_32 - (uint32_t)(poll_rx_ts & 0xFFFFFFFF)       ) & 0xFFFFFFFFUL);
    double Rb = (double)(((uint32_t)(final_rx_ts & 0xFFFFFFFF)      - resp_tx_ts_32 ) & 0xFFFFFFFFUL);
    double Db = (double)((final_tx_ts_32                             - resp_rx_ts_32 ) & 0xFFFFFFFFUL);

    double tof  = (Ra * Rb - Da * Db) / (Ra + Rb + Da + Db);
    float  dist = (float)(tof * UWB_DWT_TS_UNIT * UWB_SPEED_OF_LIGHT);
    if (dist > 0.0f && dist < 300.0f) {
      currentUwbDist     = dist;
      lastUwbReadingTime = millis();
      Serial.printf("[UWB] ANCHOR distanza = %.2f m (DS-TWR)\n", dist);
    }
    uwb_frame_seq++;

  } else {
    // =========================================================================
    // TAG (Initiator):
    //   1) Invia Poll
    //   2) Riceve Reply con T2 e T3 embedded (da Anchor)
    //   3) Invia Final con T1, T4, T5 (per DS-TWR lato Anchor)
    //   4) Calcola distanza SS-TWR localmente dai timestamp embedded nel Reply
    // =========================================================================
    uwb_tx_poll[UWB_MSG_SN_IDX] = uwb_frame_seq;
    dwt_writetxdata(sizeof(uwb_tx_poll), uwb_tx_poll, 0);
    dwt_writetxfctrl(sizeof(uwb_tx_poll) + 2, 0, 1);   // +2 FCS; ranging=1
    dwt_setrxaftertxdelay(UWB_POLL_TX_TO_RESP_RX_DLY_UUS);
    dwt_setrxtimeout(UWB_RESP_RX_TIMEOUT_UUS);
    dwt_setpreambledetecttimeout(UWB_PRE_TIMEOUT);
    dwt_starttx(DWT_START_TX_IMMEDIATE | DWT_RESPONSE_EXPECTED);

    // Attendi Reply dall'Anchor
    uint32_t tstart = millis();
    while (!((status = dwt_read32bitreg(SYS_STATUS_ID)) &
             (SYS_STATUS_RXFCG_BIT_MASK | SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR))) {
      if (millis() - tstart > 150) {
        dwt_forcetrxoff();
        return currentUwbDist;
      }
    }
    if (!(status & SYS_STATUS_RXFCG_BIT_MASK)) {
      dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_ALL_RX_TO | SYS_STATUS_ALL_RX_ERR);
      return currentUwbDist;   // Timeout o errore RX: Anchor non trovato
    }

    // T1 = timestamp trasmissione Poll (lettura dopo TX, quando RX è arrivato)
    uint64_t poll_tx_ts = uwb_get_tx_ts();
    // T4 = timestamp ricezione Reply
    uint64_t resp_rx_ts = uwb_get_rx_ts();

    // Leggi frame Reply
    uint32_t flen = dwt_read32bitreg(RX_FINFO_ID) & RXFLEN_MASK;
    if (flen <= sizeof(uwb_rx_buf)) dwt_readrxdata(uwb_rx_buf, flen, 0);
    dwt_write32bitreg(SYS_STATUS_ID, SYS_STATUS_RXFCG_BIT_MASK);

    uwb_rx_buf[UWB_MSG_SN_IDX] = 0;
    if (memcmp(uwb_rx_buf, uwb_tx_reply, UWB_MSG_COMMON_LEN) != 0) return currentUwbDist;

    // Estrai T2 e T3 embedded nel Reply (inviati dall'Anchor)
    uint32_t poll_rx_ts_32 = uwb_get32(uwb_rx_buf + UWB_RESP_POLL_RX_IDX);
    uint32_t resp_tx_ts_32 = uwb_get32(uwb_rx_buf + UWB_RESP_RESP_TX_IDX);

    // Calcola T5 = tempo schedulato TX Final
    uint32_t final_tx_time = (uint32_t)((resp_rx_ts +
      (uint64_t)UWB_RESP_RX_TO_FINAL_TX_DLY_UUS * UWB_UUS_TO_TICKS) >> 8);
    final_tx_time &= 0xFFFFFFFEUL;
    uint32_t final_tx_ts_32 = (uint32_t)(((uint64_t)final_tx_time << 8) + UWB_TX_ANT_DLY);

    // Componi Final con T1, T4, T5
    uwb_tx_final[UWB_MSG_SN_IDX] = uwb_frame_seq;
    uwb_put32(uwb_tx_final + UWB_FINAL_POLL_TX_IDX,  (uint32_t)(poll_tx_ts & 0xFFFFFFFF));
    uwb_put32(uwb_tx_final + UWB_FINAL_RESP_RX_IDX,  (uint32_t)(resp_rx_ts & 0xFFFFFFFF));
    uwb_put32(uwb_tx_final + UWB_FINAL_FINAL_TX_IDX, final_tx_ts_32);

    dwt_setdelayedtrxtime(final_tx_time);
    dwt_writetxdata(sizeof(uwb_tx_final), uwb_tx_final, 0);
    dwt_writetxfctrl(sizeof(uwb_tx_final) + 2, 0, 1);
    dwt_starttx(DWT_START_TX_DELAYED);

    // Calcolo distanza SS-TWR lato Tag (usando T2 e T3 dell'Anchor dal Reply)
    // Ra = T4 - T1  (Round-trip Poll→Reply al Tag)
    // Da = T3 - T2  (Turnaround Anchor: tempo tra ricezione Poll e TX Reply)
    // ToF = (Ra - Da) / 2
    double Ra = (double)(((uint32_t)(resp_rx_ts & 0xFFFFFFFF) -
                           (uint32_t)(poll_tx_ts & 0xFFFFFFFF)) & 0xFFFFFFFFUL);
    double Da = (double)((resp_tx_ts_32 - poll_rx_ts_32) & 0xFFFFFFFFUL);
    double tof  = (Ra - Da) / 2.0;
    float  dist = (float)(tof * UWB_DWT_TS_UNIT * UWB_SPEED_OF_LIGHT);
    if (dist > 0.0f && dist < 300.0f) {
      currentUwbDist     = dist;
      lastUwbReadingTime = millis();
      Serial.printf("[UWB] TAG distanza = %.2f m (SS-TWR)\n", dist);
    }
    uwb_frame_seq++;
  }
#endif // USE_UWB

  // Invalida la distanza se nessun dato recente dal DW3000
  if (millis() - lastUwbReadingTime > 3000 && currentUwbDist >= 0.0f) {
    Serial.println("[UWB] Timeout: nessun dato recente dal DW3000.");
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
static const char* DEVICE_ID = "C";
static const char* BLE_NAME  = "ESP32_S3_BLE_C";

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
