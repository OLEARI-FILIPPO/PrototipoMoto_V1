# 🌐 Implementazione Propagazione Mesh - ESP32 BLE

## 📋 Riepilogo Modifiche

**Data:** 22 Gennaio 2026  
**Obiettivo:** Implementare logica mesh completa con propagazione dei peers indiretti

---

## ✨ Cosa è stato Modificato

### 🔧 **1. Parsing Manufacturer Data Migliorato**

**File:** Tutti e 3 gli sketch (A, B, C)  
**Funzione:** `onResult()` della classe `MyAdvertisedDeviceCallbacks`

**Modifiche:**
- ✅ Aggiunto parsing dettagliato dei neighbors dai manufacturer data
- ✅ Log diagnostici con emoji per identificare facilmente il parsing
- ✅ Costruzione corretta del nome completo: `"ESP32_S3_BLE_" + neighborId`
- ✅ Calcolo approssimato dell'RSSI (somma degli RSSI: A→B + B→C)
- ✅ Skip automatico se il neighbor è lo stesso dispositivo

**Log Aggiunti:**
```cpp
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_B (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from B
[MESH] ⏭️  Skipping neighbor A (it's me)
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via B | RSSI: -45 (approx) | Dist: 0.05m
```

---

### 🔧 **2. Gestione RSSI per Peers Indiretti**

**File:** Tutti e 3 gli sketch (A, B, C)  
**Funzione:** `updatePeer()`

**Modifiche:**
- ✅ Rimosso RSSI fittizio `-100` per peers indiretti
- ✅ Ora usa l'RSSI approssimato calcolato dal mesh (somma A→B + B→C)
- ✅ Aggiornamento RSSI anche per peers indiretti esistenti

**Prima:**
```cpp
peers[peerCount].rssi = -100; // Fake rssi for indirect
```

**Dopo:**
```cpp
peers[peerCount].rssi = rssi; // Use approximated RSSI from mesh calculation
```

---

### 🔧 **3. Log Dettagliati JSON Message**

**File:** Tutti e 3 gli sketch (A, B, C)  
**Funzione:** `jsonPeerMessage()`

**Modifiche:**
- ✅ Contatore separato per peers diretti e indiretti
- ✅ Log riassuntivo prima dell'invio al telefono

**Log Aggiunti:**
```cpp
[JSON] 📤 Built message: 3 total peers (2 direct, 1 indirect)
```

---

## 🎯 Logica Mesh Implementata

### **Scenario di Funzionamento:**

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   ESP32-A   │ ←─BLE─→ │   ESP32-B   │ ←─BLE─→ │   ESP32-C   │
└─────────────┘         └─────────────┘         └─────────────┘
      ↓                       ↓                       ↓
   Phone_1               Phone_2                  (none)
```

### **Dati Ricevuti da Phone_1 (connesso ad A):**

**Situazione Normale (tutti si vedono):**
```json
{
  "peers": [
    {"id": "ESP32_S3_BLE_B", "rssi": -20, "dist": 0.01},
    {"id": "ESP32_S3_BLE_C", "rssi": -30, "dist": 0.04}
  ],
  "src": "A"
}
```

**Situazione con Perdita Parziale (A non vede C):**
```json
{
  "peers": [
    {"id": "ESP32_S3_BLE_B", "rssi": -20, "dist": 0.01},
    {"id": "ESP32_S3_BLE_C", "rssi": -45, "dist": 0.05, "via": "B"}
  ],
  "src": "A"
}
```

**Campo `via`:**  
Indica che il peer è **indiretto** e viene visto tramite l'ESP32 specificato.

---

## 📊 Formato Manufacturer Data

**Struttura:**
```
[0xFF] [0xFF] [State] [ID1] [RSSI1] [ID2] [RSSI2] ...
```

**Esempio da ESP32-B:**
```
0xFF 0xFF 0x03 'A' 0xEC 'C' 0xE7
       │    │   │    │    │    │
       │    │   │    │    │    └─ RSSI di C = -25 dBm
       │    │   │    │    └────── ID = 'C'
       │    │   │    └─────────── RSSI di A = -20 dBm
       │    │   └──────────────── ID = 'A'
       │    └──────────────────── State = CONNECTED (3)
       └───────────────────────── Manufacturer ID
```

---

## 🔄 Flusso di Propagazione

1. **ESP32-B** fa scan e trova **A** (RSSI: -20) e **C** (RSSI: -25)
2. **ESP32-B** aggiunge A e C al suo array `peers[]`
3. **ESP32-B** costruisce manufacturer data: `[0xFF 0xFF 0x03 'A' 0xEC 'C' 0xE7]`
4. **ESP32-B** fa advertising con questi dati
5. **ESP32-A** fa scan e riceve l'advertising di B
6. **ESP32-A** parsa i manufacturer data e trova i neighbors di B
7. **ESP32-A** calcola:
   - Distanza A→B = 0.01m (RSSI: -20)
   - Distanza B→C = 0.02m (RSSI: -25)
   - **Distanza totale A→C = 0.03m**
   - **RSSI approssimato = -20 + (-25) = -45**
8. **ESP32-A** aggiunge C come peer **indiretto** (via: "B")
9. **ESP32-A** invia JSON al telefono con entrambi i peers (B diretto, C indiretto)

---

## 📱 Gestione nell'App Flutter

L'app **già gestisce correttamente** i peers indiretti:

**Parser in `network_view_screen.dart`:**
- ✅ Distingue DIRECT vs INDIRECT tramite campo `via`
- ✅ Log separati: `→ ` per diretti, `↪️ ` per indiretti
- ✅ UI mostra icone diverse

**Esempio Log App:**
```
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | Type: DIRECT | RSSI: -20 dBm
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_C | Type: INDIRECT (via B) | RSSI: -45 dBm
```

---

## 🧪 Test da Eseguire

### **Test 1: Mesh Completo (tutti si vedono)**
1. Avvicina tutti e 3 gli ESP32
2. Fai PAIRING su un dispositivo
3. Fai SEARCHING sull'altro
4. **Verifica:** Tutti vedono tutti come DIRECT

### **Test 2: Perdita Parziale (simulazione)**
1. Allontana ESP32-C da ESP32-A (ma mantienilo vicino a B)
2. **Verifica log di A:**
   - Dovrebbe vedere B come DIRECT
   - Dovrebbe vedere C come INDIRECT via B
3. **Verifica log di B:**
   - Dovrebbe vedere sia A che C come DIRECT

### **Test 3: Calcolo Distanze**
1. Misura manualmente le distanze reali con un metro
2. Confronta con le distanze calcolate dall'app
3. Verifica che la distanza indiretta A→C = Dist(A→B) + Dist(B→C)

---

## 🎨 Log da Monitorare nel Serial Monitor

**Durante il scan (ogni 3 secondi):**
```
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_B (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from B
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via B | RSSI: -45 (approx) | Dist: 0.05m
```

**Durante la costruzione del messaggio:**
```
[JSON] 📤 Built message: 3 total peers (2 direct, 1 indirect)
[REPORT] JSON Payload: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-20,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-45,"dist":0.05,"via":"B"}],"src":"A"}
```

---

## ⚙️ Parametri Configurabili

### **Timeout Peers Indiretti:**
```cpp
void cleanupOldPeers() {
  if (now - peers[i].lastSeenMs > 8000) { // 8 secondi
```
- Attualmente: **8 secondi** (più tollerante rispetto ai diretti)
- Può essere aumentato se i peers indiretti "flappano" troppo

### **Priorità Diretti vs Indiretti:**
```cpp
// Update indirect info only if we don't have recent direct info (older than 2s)
if (peers[i].isIndirect || (now - peers[i].lastSeenMs > 2000)) {
```
- I peers **diretti hanno sempre priorità**
- Un peer indiretto viene sovrascritto se arriva un aggiornamento diretto entro 2 secondi

### **Hop Limit:**
- Attualmente: **1 hop** (A→B→C)
- Per implementare 2+ hop, modificare il parsing per ri-propagare anche i peers indiretti ricevuti

---

## 📝 Note Importanti

1. **RSSI Approssimato:**  
   L'RSSI per peers indiretti è una **somma** degli RSSI individuali. Non è fisicamente accurato ma fornisce un'indicazione della "qualità" del path.

2. **Distanza Cumulativa:**  
   La distanza è calcolata come **somma delle distanze** lungo il path. È più accurata dell'RSSI approssimato.

3. **Manufacturer Data Limitato:**  
   BLE advertising ha un limite di ~31 byte. Con overhead di 3 byte (FF FF State), possiamo includere circa **14 neighbors** (2 byte per neighbor).

4. **Nessuna Validazione Loop:**  
   Attualmente non c'è protezione contro loop (A→B→A). Con 1 hop questo non è un problema, ma servirà per implementazioni future.

---

## ✅ Checklist Implementazione

- [x] Parsing manufacturer data con log dettagliati
- [x] Calcolo corretto distanza indiretta (A→B + B→C)
- [x] Calcolo RSSI approssimato (somma RSSI)
- [x] Aggiunta peers indiretti all'array `peers[]`
- [x] Campo `via` nel JSON per peers indiretti
- [x] Priorità ai peers diretti su quelli indiretti
- [x] Log riassuntivi in `jsonPeerMessage()`
- [x] Applicato a tutti e 3 gli sketch (A, B, C)
- [ ] Test con dispositivi reali (da fare)
- [ ] Validazione calcoli distanza (da fare)
- [ ] Test perdita connessione parziale (da fare)

---

## 🚀 Prossimi Passi

1. **Carica sketch aggiornati** su tutti e 3 gli ESP32
2. **Test base:** Verifica che tutti e 3 si vedano come DIRECT
3. **Test mesh:** Allontana C da A, verifica che A vede C via B
4. **Analizza log:** Verifica nei Serial Monitor che i log [MESH] appaiano correttamente
5. **Integrazione LoRa:** Una volta validata la mesh BLE, procedi con il collegamento al dispositivo LoRa

---

## 📞 Supporto

Se durante i test emergono problemi:
- Controlla i log del Serial Monitor (115200 baud)
- Verifica che i manufacturer data vengano popolati correttamente
- Controlla che il campo `via` appaia nel JSON quando previsto
- Usa i log `[MESH]` e `[JSON]` per il debugging

**Grandi passi avanti oggi! 🎉**
