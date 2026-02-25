# Logica di Navigazione — Sistema Leader/Follower

**Progetto:** PrototipoMoto\_V1  
**Data:** Febbraio 2026  
**Stato:** In sviluppo attivo (distanza attualmente simulata; integrazione LoRa/BLE reale pianificata)

---

## Indice

1. [Panoramica del Sistema Leader/Follower](#1-panoramica-del-sistema-leaderfollower)
2. [Meccanismo di Switch dei Ruoli](#2-meccanismo-di-switch-dei-ruoli)
3. [Polyline Blu per il Follower](#3-polyline-blu-per-il-follower)
4. [Futuri Sviluppi: Da Dati Simulati a LoRa/BLE Reali](#4-futuri-sviluppi-da-dati-simulati-a-loreable-reali)
5. [Riferimenti al Codice](#5-riferimenti-al-codice)

---

## 1. Panoramica del Sistema Leader/Follower

### 1.1 Concetto di Base

Il sistema **Leader/Follower** è il nucleo della logica di navigazione in gruppo di PrototipoMoto_V1. L'idea è semplice: in una comitiva di motociclette equipaggiate con ESP32-S3, **una moto guida (Leader)** e le altre **seguono (Follower)**.

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Moto A    │─────────│   Moto B    │─────────│   Moto C    │
│  [LEADER]   │  BLE/   │ [FOLLOWER]  │  BLE/   │ [FOLLOWER]  │
│             │  LoRa   │             │  LoRa   │             │
└─────────────┘         └─────────────┘         └─────────────┘
       │                       │                       │
    GPS + Route             GPS + Route             GPS + Route
    (breadcrumb)            (segue Leader)          (segue Leader)
```

### 1.2 Responsabilità dei Ruoli

| Ruolo     | Responsabilità |
|-----------|---------------|
| **Leader** | Trasmette la propria posizione GPS in tempo reale. La sua traiettoria viene registrata come "breadcrumb trail" e inviata agli altri dispositivi della mesh. |
| **Follower** | Riceve la posizione del Leader, visualizza il suo percorso come Polyline blu sulla mappa e mostra la distanza attuale dal Leader. |

### 1.3 Come Viene Determinato il Ruolo Iniziale

All'avvio della sessione di gruppo:
- Il primo dispositivo che invia il comando **`STARTPAIRING`** diventa **Leader** per impostazione predefinita.
- Gli altri dispositivi che eseguono **`STARTSEARCHING`** si registrano come **Follower**.
- L'assegnazione viene comunque rinegoziata dinamicamente in base alla distanza (vedi sezione 2).

---

## 2. Meccanismo di Switch dei Ruoli

### 2.1 Logica di Base

Il ruolo **Leader/Follower non è fisso**: viene ricalcolato ogni volta che l'app riceve un aggiornamento di distanza dalla mesh ESP32. La regola è:

> **Il dispositivo con la distanza cumulativa minore rispetto al resto del gruppo diventa (o rimane) il Leader.**

In pratica, se la Moto B si trova più avanti di Moto A rispetto al percorso complessivo del gruppo, Moto B assume il ruolo di Leader.

### 2.2 Calcolo della Distanza (Stato Attuale — Simulato)

La distanza inter-dispositivo è attualmente **stimata tramite RSSI BLE**. Il firmware degli ESP32-S3 include la seguente funzione di conversione:

```cpp
// sketch_ESP32_S3_BLE_Server.ino
float rssiToDistanceMeters(int rssi) {
    const float txPower = -59.0f;  // RSSI a 1 metro di distanza
    const float n = 2.0f;          // Esponente di path-loss (aria libera ≈ 2)
    return powf(10.0f, (txPower - (float)rssi) / (10.0f * n));
}
```

Questa stima viene inclusa nel payload JSON trasmesso via BLE:

```json
{
  "src": "A",
  "peers": [
    { "id": "B", "rssi": -65, "dist": 3.16 },
    { "id": "C", "rssi": -72, "dist": 6.31 }
  ]
}
```

Il campo `dist` viene poi letto dal servizio Flutter (`ExternalDeviceService`) e passato alla logica di decisione del ruolo.

### 2.3 Soglie di Switch

| Condizione | Azione |
|-----------|--------|
| `distanza_peer < distanza_leader` (di almeno **2 m** di isteresi) | Il peer viene promosso a **Leader**; l'ex-Leader diventa **Follower** |
| `distanza_peer >= distanza_leader` | Nessun cambio di ruolo |

L'isteresi di 2 m evita oscillazioni rapide del ruolo quando due dispositivi si trovano a distanza quasi identica.

### 2.4 Flusso di Switch in App

```
[Ricezione pacchetto ESP32]
        │
        ▼
[Parsing distanza "dist"]
        │
        ▼
[Confronto con soglia Leader corrente]
        │
    ┌───┴───┐
    │       │
   SÌ      NO
    │       │
    ▼       ▼
[Switch   [Mantieni
 ruolo]    ruolo]
    │
    ▼
[Aggiorna UI: colori marker,
 Polyline blu/rosso, badge ruolo]
```

---

## 3. Polyline Blu per il Follower

### 3.1 Perché la Polyline Blu

Abbiamo scelto il **colore blu** per la Polyline del Follower per le seguenti ragioni:

1. **Differenziazione visiva immediata**: il rosso è già usato per la registrazione del percorso GPS proprio dell'utente (`_routePoints` con `Colors.redAccent`). Il blu distingue nettamente il percorso ricevuto dal Leader da quello locale.

2. **Convenzione HCI consolidata**: nelle app di navigazione e tracking (es. Google Maps, Komoot), il blu è tradizionalmente associato alla posizione e al percorso attivo dell'utente da seguire. Usarlo per il percorso Leader crea un'associazione intuitiva: "questo è il percorso che devo seguire".

3. **Leggibilità su sfondo cartografico**: le tile OpenStreetMap usano tonalità neutre (grigio, beige, verde chiaro). Il blu ad alta saturazione offre il massimo contrasto senza interferire con le strade già disegnate sulla mappa.

4. **Coerenza con la UI dell'app**: il colore blu è già usato nel marker GPS locale ("Tu sei qui") e nei controlli BLE. Estenderlo alla Polyline del Leader mantiene un linguaggio visivo coerente.

### 3.2 Implementazione nella Mappa

```dart
// Esempio di rendering della Polyline blu del Leader
if (_leaderRoutePoints.length > 1)
  PolylineLayer(
    polylines: [
      Polyline(
        points: _leaderRoutePoints,  // Breadcrumb ricevuti dal Leader
        strokeWidth: 4,
        color: Colors.blue,          // Blu per il percorso Leader
      ),
    ],
  ),

// Percorso GPS proprio dell'utente (Follower)
if (_routePoints.length > 1)
  PolylineLayer(
    polylines: [
      Polyline(
        points: _routePoints,
        strokeWidth: 4,
        color: Colors.redAccent,     // Rosso per il percorso locale
      ),
    ],
  ),
```

### 3.3 Dati del Percorso Leader

Il percorso blu viene costruito accumulando le coordinate GPS trasmesse dal Leader ad ogni aggiornamento di telemetria. Ogni punto è un oggetto `LatLng` ricevuto via BLE/LoRa:

```
Leader GPS update → ESP32 Leader → BLE/LoRa mesh → ESP32 Follower → App Flutter → _leaderRoutePoints.add(LatLng)
```

---

## 4. Futuri Sviluppi: Da Dati Simulati a LoRa/BLE Reali

### 4.1 Limitazioni Attuali

L'attuale stima della distanza tramite RSSI presenta limitazioni significative in contesto motociclistico:

| Limitazione | Impatto |
|-------------|---------|
| **Precisione RSSI** | Errore tipico di ±3–5 m in campo aperto, ±10 m in ambiente urbano |
| **Ostacoli fisici** | Pareti, veicoli e interferenze riducono drasticamente l'affidabilità |
| **Portata BLE** | Massimo ~50–100 m; insufficiente per distanze tipiche tra moto in marcia |
| **Nessuna posizione assoluta** | La distanza RSSI è relativa tra due dispositivi, non una posizione GPS del peer |

### 4.2 Roadmap Integrazione Hardware

#### Fase 1 — LoRa (Priorità Alta)

Sostituire i pacchetti BLE con trasmissioni **LoRa** (SX1276/RFM95W) per:
- Portata fino a **10–15 km** in campo aperto
- Trasmissione della **posizione GPS reale** (`lat`, `lon`, `alt`) anziché solo RSSI
- Frequenza di aggiornamento: ogni **1–5 secondi**

**Formato pacchetto LoRa pianificato:**
```json
{
  "src": "A",
  "role": "leader",
  "gps": { "lat": 45.464664, "lon": 9.188540, "alt": 120.5 },
  "speed_kmh": 85.3,
  "ts": 1740000000
}
```

#### Fase 2 — UWB (Precisione Sub-metro)

Integrare moduli **Ultra-Wideband** (es. DW1000) per misure di distanza con precisione di ±10–30 cm, utili per manovre a bassa velocità (semafori, parcheggi).

#### Fase 3 — Fusione Sensori

Combinare GPS + LoRa + UWB in un filtro di Kalman esteso per ottenere:
- Posizione precisa anche in assenza temporanea di segnale GPS (tunnel, cavalcavia)
- Switch di ruolo Leader/Follower più stabile

### 4.3 Modifiche al Codice da Apportare

Quando i dati reali saranno disponibili, le modifiche principali riguarderanno:

1. **`external_device_service.dart`**: aggiungere stream `loraPacketStream` che espone i pacchetti LoRa decodificati.

2. **`network_view_screen.dart`**: sostituire il campo `dist` (stimato da RSSI) con `dist` reale dal pacchetto LoRa.

3. **`map_screen.dart`**: popolare `_leaderRoutePoints` con le coordinate GPS ricevute via LoRa invece di usare solo la posizione locale.

4. **ESP32 firmware** (`sketch_ESP32_S3_BLE_Server.ino`): aggiungere routine `initLoRa()` / `sendLoRaPacket()` / `receiveLoRaPacket()`.

---

## 5. Riferimenti al Codice

| File | Contenuto Rilevante |
|------|---------------------|
| `primo_progetto_flutter/lib/screens/map_screen.dart` | Rendering Polyline e logica mappa |
| `primo_progetto_flutter/lib/screens/network_view_screen.dart` | Visualizzazione nodi mesh e distanze |
| `primo_progetto_flutter/lib/services/external_device_service.dart` | Comunicazione BLE con ESP32 |
| `primo_progetto_flutter/lib/services/location_service.dart` | GPS e calcolo distanza geografica |
| `primo_progetto_flutter/lib/models/network_node.dart` | Modello dati nodo (include `distance`, `rssi`) |
| `sketch_ESP32_S3_BLE_Server/MotoA/.../sketch_ESP32_S3_BLE_Server.ino` | Firmware ESP32-A: `rssiToDistanceMeters()`, machine state |
| `sketch_ESP32_S3_BLE_Server/MotoB/.../sketch_ESP32_S3_BLE_Server_B.ino` | Firmware ESP32-B |
| `sketch_ESP32_S3_BLE_Server/MotoC/.../sketch_ESP32_S3_BLE_Server_C.ino` | Firmware ESP32-C |

---

> **Nota:** Questo documento descrive sia le funzionalità già implementate sia quelle pianificate. Le sezioni marcate come "Stato Attuale — Simulato" fanno riferimento alla stima RSSI attuale; quelle nella sezione 4 descrivono l'evoluzione verso l'hardware reale.
