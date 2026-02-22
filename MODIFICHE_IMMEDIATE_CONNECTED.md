# Modifiche Critiche: Transizione Immediata a CONNECTED

## Problema Identificato

**Problema 1**: Gli ESP32 transitavano a stato CONNECTED solo dopo 30 secondi di timeout, anche se avevano già rilevato un peer.

**Problema 2**: Due telefoni potevano connettersi allo stesso ESP32 contemporaneamente.

**Problema 3**: ESP32 continuava a fare advertising anche quando già connesso a un telefono.

## Soluzione Implementata

### 1. Transizione IMMEDIATA a CONNECTED (Tutti e 3 gli ESP32)

**File modificati**:
- `MotoA/sketch_ESP32_S3_BLE_Server/sketch_ESP32_S3_BLE_Server.ino`
- `MotoB/sketch_ESP32_S3_BLE_Server_B/sketch_ESP32_S3_BLE_Server_B.ino`
- `MotoC/sketch_ESP32_S3_BLE_Server_C/sketch_ESP32_S3_BLE_Server_C.ino`

**Modifica nella funzione `updatePeer()`** (dopo `peerCount++`):

```cpp
// CRITICAL: Transition to CONNECTED immediately when first peer detected
if (peerCount == 1 && (currentState == PAIRING || currentState == SEARCHING)) {
  Serial.println("[STATE] ⚡ First peer detected! Transitioning to CONNECTED immediately");
  enterState(CONNECTED);
}
```

**Comportamento**: 
- Quando un ESP32 è in stato PAIRING o SEARCHING
- E rileva il PRIMO peer (peerCount passa da 0 a 1)
- Transita IMMEDIATAMENTE a stato CONNECTED
- Non aspetta più 30 secondi di timeout!

### 2. Blocco Connessioni Multiple (Tutti e 3 gli ESP32)

**Modifica in `MyServerCallbacks::onConnect()`**:

```cpp
void onConnect(BLEServer* server) override {
  // CRITICAL: Reject second phone connection - only one phone allowed
  if (phoneConnected) {
    Serial.println("[PHONE] ⛔ Rejecting second phone connection - already connected!");
    server->disconnect(server->getConnId());
    return;
  }
  
  phoneConnected = true;
  Serial.println("[PHONE] Phone connected");
  // Keep advertising for mesh visibility - app will filter occupied devices
  updateAdvertising();
}
```

**Comportamento**:
- Se un telefono è già connesso (`phoneConnected == true`)
- La nuova connessione viene RIFIUTATA immediatamente
- L'advertising BLE **continua** (necessario per mesh ESP32)
- Solo UN telefono per ESP32!
- **Nota**: App Flutter filtrerà dispositivi occupati nello scan

### 3. Resume Advertising alla Disconnessione

**Modifica in `MyServerCallbacks::onDisconnect()`**:

```cpp
void onDisconnect(BLEServer* server) override {
  phoneConnected = false;
  Serial.println("[PHONE] Phone disconnected");
  // Resume phone advertising
  updateAdvertising();
}
```

**Comportamento**:
- Quando il telefono si disconnette
- L'advertising BLE riprende automaticamente
- L'ESP32 torna disponibile per nuove connessioni

## Risultato Atteso

### Prima delle modifiche:
1. ❌ ESP32-A e ESP32-B in PAIRING/SEARCHING per 30 secondi
2. ❌ Si rilevano reciprocamente ma restano in attesa
3. ❌ Dopo 30 secondi: transizione a CONNECTED
4. ❌ Nel frattempo i peer potrebbero essere già spariti (timeout)
5. ❌ Dati mesh quasi sempre vuoti: `{"peers":[],"src":"X"}`
6. ❌ Due telefoni connessi allo stesso ESP32-A

### Dopo le modifiche:
1. ✅ ESP32-A entra in PAIRING
2. ✅ ESP32-B entra in SEARCHING
3. ✅ ESP32-B rileva ESP32-A → **TRANSIZIONE IMMEDIATA A CONNECTED!**
4. ✅ ESP32-A rileva ESP32-B → **TRANSIZIONE IMMEDIATA A CONNECTED!**
5. ✅ Mesh si stabilisce in ~2-3 secondi invece di 30!
6. ✅ Dati mesh sempre popolati: `{"peers":[{"id":"A","rssi":-65,"dist":0.5}],"src":"B"}`
7. ✅ Aggiornamenti continui di RSSI e distanza in tempo reale
8. ✅ Solo UN telefono per ESP32 (secondo telefono rifiutato)
9. 📱 ESP32 occupato rimane visibile in scan (filtro lato app da implementare)

## Log Attesi

Quando funziona correttamente, nei log seriali vedrai:

```
[SCAN] ESP32-B found with RSSI -67
[PEERS] Added new DIRECT peer: B (via ), Dist: 0.58m (total: 1)
[STATE] ⚡ First peer detected! Transitioning to CONNECTED immediately
[STATE] → CONNECTED
[MESH] {"peers":[{"id":"B","rssi":-67,"dist":0.58}],"src":"A"}
```

E nell'app Flutter:
```
[MESH PARSER] 📡 Peer: B | RSSI: -67 dBm | Distance: 0.58m | NEW
[MESH PARSER] 🎨 Calling setState() to refresh UI
```

## Azioni Necessarie

### 1. Ricaricare il Firmware
**IMPORTANTE**: Devi ricaricare il firmware su TUTTI E TRE gli ESP32:
- ESP32-A (MotoA)
- ESP32-B (MotoB) 
- ESP32-C (MotoC)

### 2. Test Sequence
1. Ricarica firmware su ESP32-A e ESP32-B
2. Disconnetti entrambi i telefoni
3. Riavvia entrambe le app Flutter
4. Telefono 1 → connettiti a ESP32-A
5. Telefono 2 → connettiti a ESP32-B (NON più allo stesso ESP32-A!)
6. Premi PAIRING su dispositivo 1 (ESP32-A)
7. Premi SEARCHING su dispositivo 2 (ESP32-B)
8. **Attendi 2-3 secondi** → Dovresti vedere la transizione IMMEDIATA a CONNECTED!
9. Verifica che i dati mesh si aggiornino continuamente nell'interfaccia

### 3. Cosa Verificare
- ✅ Transizione immediata a CONNECTED (2-3 secondi invece di 30)
- ✅ Dati mesh popolati: nodi visibili con RSSI e distanza
- ✅ Aggiornamenti continui nell'UI (RSSI che cambia)
- ✅ Solo un telefono connesso per ESP32
- ✅ ESP32 occupato non appare nello scan dell'altro telefono

## Note Tecniche

### Perché peerCount == 1?
La condizione `peerCount == 1` assicura che la transizione avvenga solo quando il PRIMO peer viene rilevato. Se aggiungiamo peer indiretti successivamente (mesh a 3+ nodi), non vogliamo ri-triggerare la transizione.

### Perché continuare l'advertising?
- Gli ESP32 usano lo **stesso advertising** per comunicare tra loro (mesh) e con i telefoni
- Fermando l'advertising, gli ESP32 diventerebbero **invisibili anche agli altri ESP32**
- Questo romperebbe completamente la mesh!
- **Soluzione**: L'app Flutter filtrerà i dispositivi occupati nello scan (TODO futuro)
- **Roadmap**: Passaggio a LoRa renderà questa distinzione irrilevante

### Impatto sul Mesh Multi-Hop
Queste modifiche NON impattano il mesh multi-hop (3+ nodi). I nodi indiretti vengono ancora aggiunti correttamente via `updatePeer()` con `indirect=true`, ma non triggherano una nuova transizione di stato perché `peerCount` sarà già > 1.
