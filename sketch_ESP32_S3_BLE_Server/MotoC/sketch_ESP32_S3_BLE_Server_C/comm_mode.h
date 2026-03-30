// =============================================================================
// comm_mode.h  –  Gestione modalità di comunicazione: UWB ↔ LoRa
// =============================================================================
//
// Logica di switching:
//
//   • COMM_UWB   → dati UWB disponibili E distanza < UWB_MAX_RANGE_M
//   • COMM_LORA  → UWB assente OPPURE distanza > LORA_THRESHOLD_M
//
// Hysteresis: si passa a LoRa a >200 m, si torna a UWB a <180 m
//             (evita oscillazioni sulla soglia)
//
// =============================================================================
#pragma once

#include <Arduino.h>
#include <RadioLib.h>   // https://github.com/jgromes/RadioLib  (v6+)

// ---------------------------------------------------------------------------
// PIN LoRa – adatta ai tuoi moduli (es. TTGO LoRa32 / Heltec WiFi LoRa 32)
// Cambia i valori se usi un pinout diverso.
// ---------------------------------------------------------------------------
#define LORA_SCK   12
#define LORA_MISO  13
#define LORA_MOSI  11
#define LORA_CS    10
#define LORA_BUSY  4
#define LORA_RST   5
#define LORA_DIO1  6

// ---------------------------------------------------------------------------
// PIN UWB – Cablaggio DWM3000 / DW1000 condivide SPI con LoRa
// ---------------------------------------------------------------------------
#define UWB_CS     7
#define UWB_RST    18
#define UWB_IRQ    17

// ---------------------------------------------------------------------------
// Soglie
// ---------------------------------------------------------------------------
static constexpr float    LORA_THRESHOLD_M  = 200.0f;  // passa a LoRa sopra questa distanza
static constexpr float    UWB_RETURN_M      = 180.0f;  // torna a UWB sotto questa (hysteresis)
static constexpr float    UWB_MIN_QUALITY   = 0.5f;    // qualità minima UWB (0..1); sotto → forza LoRa
static constexpr uint32_t UWB_TIMEOUT_MS    = 3000;    // ms senza dati UWB → considera assente
static constexpr uint32_t UWB_GRACE_MS      = 8000;    // ms di grace period al boot: non switcha a LoRa finché UWB non ha avuto tempo di inizializzarsi

// ---------------------------------------------------------------------------
// Enum modalità comunicazione
// ---------------------------------------------------------------------------
enum CommMode {
  COMM_UWB,
  COMM_LORA,
};

// ---------------------------------------------------------------------------
// Override manuale (da UI telefono): AUTO lascia decidere la logica automatica
// ---------------------------------------------------------------------------
enum CommOverride {
  OVERRIDE_AUTO,   // nessun override → logica automatica
  OVERRIDE_UWB,    // forza UWB
  OVERRIDE_LORA,   // forza LoRa
};

// ---------------------------------------------------------------------------
// Dati distanza da UWB (compilati dal modulo DW1000/DW3000 quando disponibile)
// ---------------------------------------------------------------------------
struct UwbReading {
  float    distM   = 0.0f;   // distanza misurata (m)
  float    quality = 0.0f;   // 0..1  (1 = ottima)
  uint32_t tsMs    = 0;      // millis() dell'ultima lettura
  bool     valid   = false;  // true se il modulo ha risposto
};

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------
class CommModeManager {
public:
  // ---- Costruttore --------------------------------------------------------
  CommModeManager()
    : _radio(new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY)),
      _mode(COMM_UWB),        // parte in UWB: al pairing i dispositivi sono vicini
      _loraReady(false),
      _override(OVERRIDE_AUTO)
  {}

  // ---- Inizializzazione ---------------------------------------------------
  void begin() {
    Serial.println(F("[COMM] Initializing LoRa SX1276..."));
    int state = _radio.begin(
      868.0,   // MHz  (EU 868 / cambia a 915.0 per US)
      125.0,   // kHz  bandwidth
      9,       // spreading factor
      7,       // coding rate 4/7
      0x12,    // sync word (privato, evita interferenze con reti pubbliche)
      17,      // dBm TX power
      8        // preamble length
    );

    if (state == RADIOLIB_ERR_NONE) {
      _loraReady = true;
      Serial.println(F("[COMM] ✅ LoRa SX1276 inizializzato"));
    } else {
      Serial.printf("[COMM] ⚠️  LoRa init fallito (code %d). Solo UWB disponibile.\n", state);
    }
  }

  // ---- Aggiorna lettura UWB -----------------------------------------------
  // Chiama questo quando il modulo UWB ti fornisce un nuovo dato.
  // quality: 0..1  (puoi usare il "fp_power / rx_level" del DW3000)
  void onUwbReading(float distM, float quality = 1.0f) {
    _uwb.distM   = distM;
    _uwb.quality = quality;
    _uwb.tsMs    = millis();
    _uwb.valid   = true;
  }

  // ---- Invalida UWB (es. modulo disconnesso) ------------------------------
  void invalidateUwb() {
    _uwb.valid = false;
    _uwb.tsMs  = 0;
  }

  // ---- Override manuale (da UI telefono) ----------------------------------
  // Chiama setOverride(OVERRIDE_UWB/LORA/AUTO) quando arriva il comando BLE.
  void setOverride(CommOverride ov) {
    if (_override == ov) return;
    _override = ov;
    const char* labels[] = {"AUTO", "UWB", "LoRa"};
    Serial.printf("[COMM] 📱 Override impostato da telefono: %s\n", labels[(int)ov]);
  }
  CommOverride getOverride() const { return _override; }

  // ---- Tick: deve essere chiamato nel loop() ------------------------------
  // Ritorna la modalità attiva dopo aver eventualmente eseguito lo switch.
  CommMode update(float bestDistM) {
    const uint32_t now         = millis();

    // --- Override manuale da UI telefono: bypassa tutta la logica automatica ---
    if (_override == OVERRIDE_UWB) {
      if (_mode != COMM_UWB) _switchMode(COMM_UWB, bestDistM);
      return _mode;
    }
    if (_override == OVERRIDE_LORA) {
      if (_mode != COMM_LORA) _switchMode(COMM_LORA, bestDistM);
      return _mode;
    }

    // --- Logica automatica ---
    const bool inGracePeriod   = (now < UWB_GRACE_MS);  // primi 8s: non forziamo LoRa se UWB non ha ancora dati
    const bool uwbFresh        = _uwb.valid && (now - _uwb.tsMs < UWB_TIMEOUT_MS);
    const bool uwbGoodQual     = _uwb.quality >= UWB_MIN_QUALITY;
    const bool withinRange     = bestDistM < LORA_THRESHOLD_M;
    const bool belowHyst       = bestDistM < UWB_RETURN_M;

    CommMode desired;

    if (inGracePeriod) {
      // Boot recente: mantieni UWB in attesa che il modulo si stabilizzi
      desired = COMM_UWB;
    } else if (!uwbFresh || !uwbGoodQual) {
      // UWB assente o di bassa qualità → LoRa
      desired = COMM_LORA;
    } else if (!withinRange) {
      // Superati i 200 m → LoRa
      desired = COMM_LORA;
    } else if (_mode == COMM_LORA && belowHyst) {
      // Eravamo in LoRa, ora siamo tornati sotto 180 m con UWB buono → UWB
      desired = COMM_UWB;
    } else if (_mode == COMM_UWB) {
      // Siamo in UWB e le condizioni sono ok
      desired = COMM_UWB;
    } else {
      // Mantieni stato corrente (zona di hysteresis 180..200 m)
      desired = _mode;
    }

    if (desired != _mode) {
      _switchMode(desired, bestDistM);
    }

    return _mode;
  }

  // ---- Getters ------------------------------------------------------------
  CommMode    mode()        const { return _mode; }
  bool        loraReady()   const { return _loraReady; }
  UwbReading  uwbReading()  const { return _uwb; }

  // ---- Trasmetti un payload via LoRa --------------------------------------
  // Ritorna true se la trasmissione ha avuto successo.
  // Nota: RadioLib transmit() richiede String non-const; usiamo una copia locale.
  bool loraSend(const String& payload) {
    if (!_loraReady) return false;
    String buf = payload;           // copia mutabile richiesta da RadioLib
    int state = _radio.transmit(buf);
    if (state == RADIOLIB_ERR_NONE) {
      Serial.printf("[LORA] 📤 TX OK (%d byte)\n", payload.length());
      return true;
    }
    Serial.printf("[LORA] ❌ TX error %d\n", state);
    return false;
  }

  // ---- Ricevi un payload via LoRa (non-bloccante) -------------------------
  // Ritorna true se c'è un messaggio, e lo scrive in `out`.
  bool loraReceive(String& out) {
    if (!_loraReady) return false;
    int state = _radio.receive(out);
    if (state == RADIOLIB_ERR_NONE) {
      Serial.printf("[LORA] 📥 RX: %s (RSSI %.0f dBm)\n",
                    out.c_str(), _radio.getRSSI());
      return true;
    }
    // ERR_RX_TIMEOUT è normale, tutto il resto è un errore
    if (state != RADIOLIB_ERR_RX_TIMEOUT) {
      Serial.printf("[LORA] ⚠️ RX error %d\n", state);
    }
    return false;
  }

  // ---- Stato human-readable -----------------------------------------------
  const char* modeStr() const {
    if (_override == OVERRIDE_UWB)   return "UWB[F]";
    if (_override == OVERRIDE_LORA)  return "LoRa[F]";
    return _mode == COMM_UWB ? "UWB" : "LoRa";
  }

  // ---- Costruisce il JSON di diagnostica da includere nel payload ----------
  String diagJson() const {
    String j = "{\"comm\":\"";
    j += modeStr();
    j += "\",\"uwb_valid\":";
    j += _uwb.valid ? "true" : "false";
    j += ",\"uwb_dist\":";
    j += String(_uwb.distM, 2);
    j += ",\"uwb_q\":";
    j += String(_uwb.quality, 2);
    j += ",\"lora_ok\":";
    j += _loraReady ? "true" : "false";
    j += "}";
    return j;
  }

private:
  SX1276       _radio;
  CommMode     _mode;
  bool         _loraReady;
  UwbReading   _uwb;
  CommOverride _override;

  void _switchMode(CommMode newMode, float distM) {
    const char* from = modeStr();
    _mode = newMode;
    const char* to   = modeStr();

    Serial.println(F("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"));
    Serial.printf("[COMM] 🔀 SWITCH: %s → %s  (dist %.1f m)\n", from, to, distM);

    if (newMode == COMM_LORA) {
      if (!_uwb.valid) {
        Serial.println(F("[COMM]   Motivo: UWB assente / timeout"));
      } else if (_uwb.quality < UWB_MIN_QUALITY) {
        Serial.printf("[COMM]   Motivo: qualità UWB bassa (%.2f < %.2f)\n",
                      _uwb.quality, UWB_MIN_QUALITY);
      } else {
        Serial.printf("[COMM]   Motivo: distanza %.1f m > soglia %.1f m\n",
                      distM, LORA_THRESHOLD_M);
      }
    } else {
      Serial.printf("[COMM]   Condizioni UWB ripristinate (dist %.1f m < %.1f m, q %.2f)\n",
                    distM, UWB_RETURN_M, _uwb.quality);
    }

    Serial.println(F("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"));
  }
};
