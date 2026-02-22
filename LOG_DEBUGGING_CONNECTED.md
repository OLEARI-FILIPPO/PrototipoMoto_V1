# 📋 Log di Debugging - Transizione CONNECTED e Invio Dati

## 🎯 Obiettivo

Capire se il problema "dati che si fermano dopo PAIRING/SEARCHING" è causato da:
1. ❓ ESP32 che NON entrano in stato CONNECTED
2. ❓ ESP32 in CONNECTED ma che smettono di inviare dati
3. ❓ Altro comportamento inaspettato

## 🔍 Log Implementati (Tutti e 3 gli ESP32)

### 1. Log Entrata in CONNECTED
**Quando**: L'ESP32 entra in stato CONNECTED (sia da timeout che da transizione immediata)

**Esempio**:
```
[STATE] 🔗 Entering CONNECTED STATE
[STATE] 📊 Current peers: 2
[STATE]   - A: RSSI=-65, Dist=0.58m, DIRECT
[STATE]   - C: RSSI=-78, Dist=1.82m, INDIRECT
[STATE] ✅ CONNECTED state active - will continue scanning and sending data
```

**Cosa verifica**: 
- ✅ Conferma che entra effettivamente in CONNECTED
- ✅ Mostra quanti peer ha trovato
- ✅ Dettagli su ciascun peer (RSSI, distanza, tipo)

---

### 2. Log Timeout PAIRING/SEARCHING
**Quando**: Scade il timeout di 30 secondi in PAIRING o SEARCHING

**Esempio con peers trovati**:
```
[STATE] ⏰ TIMEOUT REACHED! State: PAIRING, Duration: 30004 ms, PeerCount: 1
[STATE] ✅ Transitioning to CONNECTED (found 1 peers)
  - Peer 0: B (RSSI: -67, Dist: 0.65m, DIRECT)
```

**Esempio senza peers**:
```
[STATE] ⏰ TIMEOUT REACHED! State: SEARCHING, Duration: 30001 ms, PeerCount: 0
[STATE] ⚠️ Returning to IDLE (no peers found)
```

**Cosa verifica**:
- ✅ Quando scade esattamente il timeout
- ✅ Quanti peer sono stati trovati
- ✅ Quale decisione prende (CONNECTED o IDLE)

---

### 3. Log Invio Dati (Ogni 5 secondi)
**Quando**: Mentre invia dati al telefono (ogni 5 secondi, non ogni 100ms per non intasare)

**Esempio**:
```
[REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
```

**Esempio in PAIRING**:
```
[REPORT] 📡 State: PAIRING | PeerCount: 0 | Sending: {"peers":[],"src":"A"}
```

**Cosa verifica**:
- ✅ In quale stato è l'ESP32 mentre invia dati
- ✅ Quanti peer ha in quel momento
- ✅ Cosa invia esattamente al telefono
- ✅ **CRITICO**: Conferma che continua a inviare anche dopo PAIRING/SEARCHING

---

### 4. Log Transizione Immediata (NUOVO)
**Quando**: Rileva il primo peer durante PAIRING/SEARCHING

**Esempio**:
```
[PEERS] Added new DIRECT peer: B (via ), Dist: 0.58m (total: 1)
[STATE] ⚡ First peer detected! Transitioning to CONNECTED immediately
[STATE] 🔗 Entering CONNECTED STATE
[STATE] 📊 Current peers: 1
[STATE]   - B: RSSI=-67, Dist=0.58m, DIRECT
[STATE] ✅ CONNECTED state active - will continue scanning and sending data
```

**Cosa verifica**:
- ✅ La transizione immediata funziona (non aspetta 30s)
- ✅ Avviene solo quando peerCount passa da 0 a 1
- ✅ Entra correttamente in CONNECTED

---

## 📊 Scenario di Test - Cosa Aspettarsi

### Test 1: Dispositivo A (PAIRING) + Dispositivo B (SEARCHING)

**Timeline Attesa con Firmware NUOVO (transizione immediata)**:

```
T=0s
[A] [STATE] Entering PAIRING
[B] [STATE] Entering SEARCHING

T=2-5s (quando si rilevano)
[A] [PEERS] Added new DIRECT peer: B (via ), Dist: 0.58m (total: 1)
[A] [STATE] ⚡ First peer detected! Transitioning to CONNECTED immediately
[A] [STATE] 🔗 Entering CONNECTED STATE
[A] [STATE] ✅ CONNECTED state active - will continue scanning and sending data

[B] [PEERS] Added new DIRECT peer: A (via ), Dist: 0.58m (total: 1)
[B] [STATE] ⚡ First peer detected! Transitioning to CONNECTED immediately
[B] [STATE] 🔗 Entering CONNECTED STATE
[B] [STATE] ✅ CONNECTED state active - will continue scanning and sending data

T=5s, 10s, 15s, 20s... (ogni 5 secondi)
[A] [REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
[B] [REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"A","rssi":-65,"dist":0.58}],"src":"B"}
```

---

**Timeline con Firmware VECCHIO (solo timeout)**:

```
T=0s
[A] [STATE] Entering PAIRING
[B] [STATE] Entering SEARCHING

T=0-5s (mentre rilevano peer)
[A] [PEERS] Added new DIRECT peer: B (via ), Dist: 0.58m (total: 1)
[B] [PEERS] Added new DIRECT peer: A (via ), Dist: 0.58m (total: 1)
(MA NON ENTRANO IN CONNECTED!)

T=5s, 10s, 15s... (inviano ma con peers vuoti o instabili)
[A] [REPORT] 📡 State: PAIRING | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
[B] [REPORT] 📡 State: SEARCHING | PeerCount: 1 | Sending: {"peers":[{"id":"A","rssi":-65,"dist":0.58}],"src":"B"}

T=30s (timeout)
[A] [STATE] ⏰ TIMEOUT REACHED! State: PAIRING, Duration: 30004 ms, PeerCount: 1
[A] [STATE] ✅ Transitioning to CONNECTED (found 1 peers)
[B] [STATE] ⏰ TIMEOUT REACHED! State: SEARCHING, Duration: 30001 ms, PeerCount: 1
[B] [STATE] ✅ Transitioning to CONNECTED (found 1 peers)

T=35s, 40s... (ora in CONNECTED)
[A] [REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
```

---

## 🐛 Problemi Potenziali da Identificare

### Problema 1: Non Entra Mai in CONNECTED
**Sintomo**: Non vedi mai i log `[STATE] 🔗 Entering CONNECTED STATE`

**Log da cercare**:
```
[STATE] ⏰ TIMEOUT REACHED! State: PAIRING, Duration: 30004 ms, PeerCount: 0
[STATE] ⚠️ Returning to IDLE (no peers found)
```

**Causa**: I peer vengono rimossi troppo presto (cleanupOldPeers) prima del timeout

---

### Problema 2: Entra in CONNECTED ma Peer Svaniscono
**Sintomo**: Vedi log CONNECTED ma poi PeerCount torna a 0

**Log da cercare**:
```
[STATE] 🔗 Entering CONNECTED STATE
[STATE] 📊 Current peers: 1
...
T+35s
[REPORT] 📡 State: CONNECTED | PeerCount: 0 | Sending: {"peers":[],"src":"A"}
```

**Causa**: cleanupOldPeers troppo aggressivo o scan non aggiorna lastSeenMs

---

### Problema 3: Smette di Inviare Dati
**Sintomo**: Log REPORT si fermano dopo un po'

**Log da cercare**:
- Ultimi log REPORT
- Verifica se phoneConnected diventa false

**Causa**: Disconnessione BLE non gestita o crash

---

### Problema 4: Dati Inviate ma Non Cambiano
**Sintomo**: Log REPORT continua ma payload sempre uguale

**Log da cercare**:
```
[REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
[REPORT] 📡 State: CONNECTED | PeerCount: 1 | Sending: {"peers":[{"id":"B","rssi":-67,"dist":0.65}],"src":"A"}
(RSSI e dist identici)
```

**Causa**: Scan non aggiorna peers o peers congelati

---

## 🧪 Come Testare

### Setup:
1. Ricarica firmware su ESP32-A e ESP32-B
2. Apri monitor seriale su ENTRAMBI gli ESP32
3. Connetti telefono 1 a ESP32-A
4. Connetti telefono 2 a ESP32-B

### Test Sequence:
1. Premi PAIRING su telefono 1 (ESP32-A)
2. Premi SEARCHING su telefono 2 (ESP32-B)
3. **Osserva i log seriali** per 60 secondi
4. Copia e incolla i log per analisi

### Cosa Verificare:
- [ ] Vedi `[STATE] ⚡ First peer detected!` entro 5 secondi?
- [ ] Vedi `[STATE] 🔗 Entering CONNECTED STATE`?
- [ ] `[REPORT]` continua ogni 5 secondi?
- [ ] PeerCount rimane > 0 in CONNECTED?
- [ ] RSSI e dist cambiano nel tempo?

---

## 📝 Note

- **Frequenza log REPORT**: Ogni 5 secondi invece di ogni 100ms per non intasare il serial monitor
- **Emoji**: Usati per facilitare la ricerca visiva nei log
- **Timestamp**: Usa `millis()` per calcolare durate precise
- **Static variable**: `lastStateLog` è statica per mantenere lo stato tra chiamate

## 🎯 Risultato Atteso

Con questi log, domani potrai:
1. ✅ Confermare se la transizione immediata funziona
2. ✅ Capire se il problema è nel timeout o nell'invio dati
3. ✅ Identificare esattamente quando e perché i dati si fermano
4. ✅ Decidere se serve ulteriore debug o se il firmware è pronto
