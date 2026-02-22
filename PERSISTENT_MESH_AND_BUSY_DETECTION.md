# 🔗 Mesh Persistente e Rilevamento Dispositivi Occupati

## 📋 Panoramica delle Modifiche

Implementate due funzionalità critiche per migliorare l'esperienza utente nella gestione della rete mesh:

### 1. **Mesh Persistente dopo Pairing** 
I nodi della mesh rimangono visibili indefinitamente dopo il pairing/searching, anche dopo il timeout di 30 secondi.

### 2. **Rilevamento Dispositivi ESP32 Occupati**
Indica visivamente quali ESP32 sono già connessi ad altri dispositivi e impedisce tentativi di connessione falliti.

---

## 🎯 Problema Risolto 1: Scomparsa Nodi dopo 10 Secondi

### ❌ Comportamento Precedente
```dart
// network_view_screen.dart (VECCHIO)
_nodes.removeWhere(
  (n) => DateTime.now().difference(n.lastSeen).inSeconds > 10,
);
```

**Problema**: Dopo il pairing, i nodi mesh venivano automaticamente rimossi se non ricevevano aggiornamenti per 10 secondi. Questo era un comportamento errato perché:

1. Il firmware ESP32 invia dati SOLO durante PAIRING/SEARCHING
2. Dopo il timeout (30s), l'ESP32 va in stato CONNECTED e smette di trasmettere
3. La lista peers diventa `{"peers":[],"src":"X"}` ma la mesh è ancora attiva
4. L'app cancellava erroneamente i nodi visualizzati

### ✅ Comportamento Nuovo
```dart
// network_view_screen.dart (NUOVO)
// ✨ NON RIMUOVERE I NODI! 
// Dopo il pairing, i nodi rimangono visibili fino a disconnessione esplicita
// Questo permette di visualizzare la mesh persistente anche dopo il timeout di 30s
debugPrint('[MESH] 💾 Persistent mesh: keeping all ${_nodes.length} discovered node(s)');
```

**Soluzione**: I nodi rimangono visibili e vengono rimossi SOLO quando:
- L'utente preme **STOP MODE** (pulizia manuale)
- Si disconnette dall'ESP32 Bridge
- L'app viene chiusa

---

## 🛡️ Problema Risolto 2: ESP32 Già Connessi

### ❌ Comportamento Precedente
- Nessuna indicazione se un ESP32 era già connesso ad un altro telefono
- L'utente tentava la connessione e riceveva errore 133 (ANDROID_SPECIFIC_ERROR)
- Esperienza utente frustrante con messaggi di errore criptici

### ✅ Comportamento Nuovo

#### **A) Rilevamento Automatico**
```dart
// ScanDeviceScreen (NUOVO)
final Set<String> _busyDevices = {}; // Tracking dispositivi occupati

// Se connessione fallisce con errore 133 o timeout
if (e.toString().contains('133') || 
    e.toString().toLowerCase().contains('timeout')) {
  setState(() {
    _busyDevices.add(macAddress);
  });
}
```

#### **B) Indicatore Visivo**
```dart
if (isBusy) 
  Container(
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(0.2),
      border: Border.all(color: Colors.red, width: 1),
    ),
    child: const Text('CONNECTED'), // Badge rosso
  )
```

#### **C) Prevenzione Tap**
```dart
ListTile(
  enabled: !isBusy,  // Disabilita l'elemento
  onTap: isBusy 
    ? () {
        ScaffoldMessenger.showSnackBar(
          SnackBar(content: Text("Questo ESP32 è già connesso")),
        );
      }
    : () async { /* normale connessione */ },
)
```

---

## 📱 Esperienza Utente Migliorata

### Scenario 1: Pairing Completato
```
1. Utente preme "START PAIRING" su telefono A (ESP32-B)
2. Utente preme "START SEARCHING" su telefono B (ESP32-C)
3. Entrambi vedono i nodi mesh: ESP32-A, ESP32-B, ESP32-C
4. Dopo 30 secondi, timer scade
   ✅ NUOVO: Nodi rimangono visibili nella Network View
   ❌ VECCHIO: Nodi sparivano dopo 10s di silenzio
5. Mesh continua a funzionare in background (stato CONNECTED)
6. Utente può visualizzare la topologia della rete
```

### Scenario 2: Tentativo Connessione ESP32 Occupato
```
1. Telefono A connesso a ESP32-B
2. Telefono B apre la scansione e vede ESP32-B
3. Telefono B tenta connessione → ERRORE 133
   ✅ NUOVO: ESP32-B marcato come "CONNECTED", badge rosso, tap disabilitato
   ❌ VECCHIO: Errore generico, utente riprova inutilmente
4. Telefono B vede chiaramente che deve scegliere ESP32-C
```

---

## 🔧 Dettagli Tecnici

### Modello Dati Aggiornato

#### `network_node.dart`
```dart
class NetworkNode {
  final bool isBusy; // ✨ NUOVO campo
  
  NetworkNode({
    // ... altri campi
    this.isBusy = false,
  });
  
  NetworkNode copyWith({
    bool? isBusy,  // ✨ NUOVO parametro
    // ...
  })
}
```

### Logica di Pulizia Selettiva

#### `network_view_screen.dart`
```dart
Future<void> _setMode(DeviceNodeState mode) async {
  if (mode == DeviceNodeState.idle) {
    // Pulizia MANUALE quando utente preme STOP
    setState(() {
      _nodes.clear();
      debugPrint('[MESH] 🗑️ Cleared all nodes on STOP MODE');
    });
  }
  
  // Timer scaduto (dopo 30s)
  _modeTimer = Timer(const Duration(seconds: 30), () {
    setState(() {
      _localDeviceState = DeviceNodeState.idle;
      // ✅ NON pulire i nodi qui! Lasciamo la mesh visibile
      debugPrint('[MESH] ⏱️ Timer expired, keeping nodes visible');
    });
  });
}
```

### Stati di un Dispositivo nella Scan Screen

| Stato | Badge | Colore | Tap Enabled | Comportamento |
|-------|-------|--------|-------------|---------------|
| **Disponibile** | Nessuno | Normale | ✅ Sì | Connessione normale |
| **Segnale Debole** | WEAK | 🟠 Arancione | ✅ Sì | Connessione possibile ma avviso |
| **Già Connesso** | CONNECTED | 🔴 Rosso | ❌ No | Snackbar esplicativa |

---

## 🧪 Test di Validazione

### Test 1: Persistenza Mesh
```
1. Avvia PAIRING su dispositivo A
2. Avvia SEARCHING su dispositivo B
3. Verifica comparsa nodi (ESP32-A, B, C)
4. Attendi 35+ secondi
5. ✅ SUCCESSO: Nodi ancora visibili in Network View
6. ✅ SUCCESSO: Log mostra "Persistent mesh: keeping all X node(s)"
7. Premi STOP MODE
8. ✅ SUCCESSO: Nodi vengono puliti, log mostra "Cleared all nodes"
```

### Test 2: Rilevamento Dispositivi Occupati
```
1. Telefono A connesso a ESP32-B
2. Telefono B apre scansione
3. Vede ESP32-B, ESP32-C in lista
4. Tenta connessione a ESP32-B
5. ✅ SUCCESSO: Errore 133 rilevato
6. ✅ SUCCESSO: Badge "CONNECTED" rosso appare su ESP32-B
7. ✅ SUCCESSO: Tap su ESP32-B disabilitato
8. ✅ SUCCESSO: Snackbar spiega che è occupato
9. Connessione a ESP32-C funziona normalmente
```

### Test 3: Refresh Manuale
```
1. Lista mostra ESP32-B come "CONNECTED"
2. Disconnetti telefono A da ESP32-B
3. Premi icona refresh (🔄) su telefono B
4. ✅ SUCCESSO: _busyDevices.clear() eseguito
5. ✅ SUCCESSO: ESP32-B riappare disponibile
6. Connessione ora possibile
```

---

## 📊 Log di Debug

### Log Mesh Persistente
```
[MESH PARSER] ✅ Updated: 0, New: 2, Total nodes: 2
[MESH] 💾 Persistent mesh: keeping all 2 discovered node(s)
[MESH] ⏱️ Timer expired, keeping nodes visible
[MESH] 🗑️ Cleared all nodes on STOP MODE  # Solo quando utente preme STOP
```

### Log Dispositivo Occupato
```
[BLE] Connecting to ESP32_S3_BLE_B (DC:B4:D9:04:70:C5)...
[BLE] Connection failed: FlutterBluePlusException | connect | android-code: 133
[SCAN] 🔒 Marked DC:B4:D9:04:70:C5 as BUSY (connection error 133)
```

---

## 🎨 UI/UX Finale

### Network View Screen
```
┌──────────────────────────────────────┐
│  🔵 ESP32_S3_BLE_B                  │
│  DC:B4:D9:04:70:C5                  │
├──────────────────────────────────────┤
│  📡 Network View                     │
│  ┌────────────────────────────────┐ │
│  │ 🟢 ESP32_S3_BLE_A              │ │  ← Nodo persistente
│  │ RSSI: -18 dBm    0.1m          │ │
│  ├────────────────────────────────┤ │
│  │ 🟢 ESP32_S3_BLE_C              │ │  ← Nodo persistente
│  │ RSSI: -25 dBm    0.3m          │ │
│  └────────────────────────────────┘ │
│                                      │
│  [PAIRING] [SEARCHING] [STOP]       │  ← STOP pulisce i nodi
└──────────────────────────────────────┘
```

### Scan Device Screen
```
┌──────────────────────────────────────┐
│  Scansione ESP32              🔄      │  ← Refresh pulisce _busyDevices
├──────────────────────────────────────┤
│  ESP32_S3_BLE_A                      │  ← Disponibile
│  DC:B4:D9:04:70:A1    -45 dBm        │
├──────────────────────────────────────┤
│  ESP32_S3_BLE_B 🔴CONNECTED          │  ← Occupato (tap disabled)
│  DC:B4:D9:04:70:C5    -38 dBm        │
├──────────────────────────────────────┤
│  ESP32_S3_BLE_C 🟠WEAK               │  ← Segnale debole
│  DC:B4:D9:04:70:D9    -82 dBm        │
└──────────────────────────────────────┘
```

---

## ✅ Checklist Implementazione

- [x] Rimosso timeout 10s di cleanup automatico nodi
- [x] Aggiunto log "Persistent mesh: keeping all nodes"
- [x] Pulizia manuale solo su STOP MODE
- [x] Timer 30s NON pulisce più i nodi
- [x] Aggiunto campo `isBusy` al modello NetworkNode
- [x] Implementato Set `_busyDevices` per tracking
- [x] Rilevamento errore 133 e timeout
- [x] Badge "CONNECTED" rosso per ESP32 occupati
- [x] Disabilitazione tap su dispositivi occupati
- [x] Snackbar informativa su tentativo connessione occupato
- [x] Bottone refresh per pulire cache dispositivi occupati
- [x] Badge "WEAK" per segnale < -80 dBm
- [x] Formattazione codice Dart
- [x] Documentazione completa

---

## 🚀 Benefici

1. **UX Migliorata**: Utente vede sempre la topologia mesh completa
2. **Feedback Chiaro**: Indicatori visivi per ESP32 occupati
3. **Prevenzione Errori**: Impossibile tentare connessione a dispositivo occupato
4. **Debug Facilitato**: Log dettagliati per troubleshooting
5. **Comportamento Intuitivo**: Mesh persiste come ci si aspetterebbe
6. **Recovery Facile**: Bottone refresh per resettare stato occupato

---

## 📝 Note Implementative

### Perché Non Timeout Automatico?
Il comportamento mesh permanente è corretto perché:
- Il firmware ESP32 mantiene la mesh in stato CONNECTED
- I MAC address sono salvati in NVS (memoria non volatile)
- La mesh è "sempre attiva" finché i dispositivi sono accesi
- Solo lo STOP MODE o lo spegnimento terminano la mesh

### Perché Tracking Client-Side dei Dispositivi Occupati?
- BLE non espone API per verificare connessioni attive di altri client
- L'errore 133 è l'unico indicatore affidabile
- Il tracking viene pulito manualmente per permettere riconnessione

### Alternativa Futura: Notifica dal Firmware
Il firmware potrebbe esporre un campo "connected_clients" nel JSON telemetry:
```json
{
  "peers": [...],
  "src": "B",
  "connected_clients": 1  // ← Nuovo campo
}
```
Questo permetterebbe rilevamento server-side senza tentativi falliti.

---

**Autore**: GitHub Copilot  
**Data**: 21 Gennaio 2026  
**Versione**: 1.0
