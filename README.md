# PrototipoMoto_V1

Sistema di navigazione in gruppo per motociclette con comunicazione mesh tramite ESP32-S3 e app Flutter.

## Struttura del Progetto

```
PrototipoMoto_V1/
├── primo_progetto_flutter/        # App Flutter (Android/iOS)
│   ├── lib/
│   │   ├── screens/               # Schermate: mappa, rete mesh
│   │   ├── services/              # BLE, GPS, mappe offline
│   │   └── models/                # Modelli dati (nodi, regioni)
│   └── README.md                  # Guida utente e setup Flutter
├── sketch_ESP32_S3_BLE_Server/    # Firmware Arduino per ESP32-S3
│   ├── MotoA/                     # Firmware Moto A
│   ├── MotoB/                     # Firmware Moto B
│   └── MotoC/                     # Firmware Moto C
└── docs/
    └── NAVIGATION_LOGIC.md        # Logica Leader/Follower e navigazione in gruppo
```

## Documentazione

| Documento | Descrizione |
|-----------|-------------|
| [`docs/NAVIGATION_LOGIC.md`](docs/NAVIGATION_LOGIC.md) | Logica Leader/Follower, switch di ruolo basato su distanza, Polyline blu, roadmap LoRa |
| [`primo_progetto_flutter/README.md`](primo_progetto_flutter/README.md) | Guida utente dell'app Flutter, setup e compilazione |
| [`primo_progetto_flutter/GUIDA_UTENTE.md`](primo_progetto_flutter/GUIDA_UTENTE.md) | Manuale utente dettagliato |
| [`TECHNICAL_DOCUMENTATION.md`](TECHNICAL_DOCUMENTATION.md) | Documentazione tecnica del sistema mesh BLE |
| [`sketch_ESP32_S3_BLE_Server/README_MOTO_FIRMWARE.md`](sketch_ESP32_S3_BLE_Server/README_MOTO_FIRMWARE.md) | Guida al firmware ESP32 |

## Funzionalità Principali

- 🏍️ **Sistema Leader/Follower** — Una moto guida, le altre seguono tracciando il percorso blu del Leader sulla mappa
- 📡 **Mesh BLE** — Rete mesh tra ESP32-S3 per comunicazione inter-moto (portata ~100 m BLE, future espansioni LoRa fino a 15 km)
- 🗺️ **Mappe offline** — Tile OpenStreetMap scaricabili per le 20 regioni italiane
- 📍 **GPS in tempo reale** — Tracciamento continuo con aggiornamento ogni 10 metri
- 🔵 **Polyline blu** — Percorso del Leader visualizzato in blu sulla mappa per i Follower
- 🔌 **Distanza inter-moto** — Attualmente stimata via RSSI BLE; futura integrazione con LoRa/UWB per precisione sub-metro

## Avvio Rapido

### App Flutter

```bash
cd primo_progetto_flutter
flutter pub get
flutter run
```

### Firmware ESP32

1. Apri Arduino IDE
2. Carica `sketch_ESP32_S3_BLE_Server/MotoA/.../sketch_ESP32_S3_BLE_Server.ino` su ESP32-A
3. Ripeti per MotoB e MotoC con i rispettivi sketch
4. Connetti l'app Flutter all'ESP32 via BLE

## Stato del Progetto

| Componente | Stato |
|-----------|-------|
| App Flutter — Mappa offline | ✅ Funzionante |
| App Flutter — Mesh BLE visualizzazione | ✅ Funzionante |
| App Flutter — Leader/Follower UI | 🚧 In sviluppo |
| Firmware ESP32 — Mesh BLE | ✅ Funzionante |
| Firmware ESP32 — Distanza RSSI (simulata) | ✅ Funzionante |
| Integrazione LoRa (distanza reale) | 📋 Pianificato |
| Integrazione UWB (precisione sub-metro) | 📋 Pianificato |

Per i dettagli sulla logica di navigazione in gruppo, consulta **[`docs/NAVIGATION_LOGIC.md`](docs/NAVIGATION_LOGIC.md)**.
