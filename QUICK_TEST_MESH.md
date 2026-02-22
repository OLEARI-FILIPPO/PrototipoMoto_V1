# 🧪 Quick Test Guide - Mesh Propagation

## 📋 Preparazione

1. **Carica sketch aggiornati** su tutti e 3 gli ESP32:
   - Upload `MotoA/sketch_ESP32_S3_BLE_Server.ino` su ESP32-A
   - Upload `MotoB/sketch_ESP32_S3_BLE_Server_B.ino` su ESP32-B
   - Upload `MotoC/sketch_ESP32_S3_BLE_Server_C.ino` su ESP32-C

2. **Apri Serial Monitor** su tutti e 3 (baud: 115200)

3. **Resetta** tutti e 3 gli ESP32

4. **Verifica inizializzazione:**
   ```
   ═══════════════════════════════════════
   [INIT] 🚀 ESP32-S3 BLE Mesh Server Starting...
   [INIT] 📱 Device Name: ESP32_S3_BLE_A
   ...
   [INIT] 🎉 ESP32_S3_BLE_A is READY!
   ```

---

## ✅ Test 1: Base Connectivity (tutti si vedono)

### Setup:
- Posiziona tutti e 3 gli ESP32 **vicini** (~10cm)

### Procedura:
1. Lancia app su entrambi i telefoni
2. Premi **PAIRING** su un dispositivo
3. Premi **SEARCHING** sull'altro

### Verifica nei LOG del Serial Monitor:

**ESP32-A:**
```
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_B (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from B
[MESH] ⏭️  Skipping neighbor A (it's me)
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via B
```

**ESP32-B:**
```
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_A (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from A
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via A
```

### Verifica nei LOG dell'App:

**Phone_1:**
```
[MESH PARSER] 📥 RAW MESSAGE: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-20,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-25,"dist":0.02}],"src":"A"}
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | Type: DIRECT
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_C | Type: DIRECT
```

**Phone_2:**
```
[MESH PARSER] 📥 RAW MESSAGE: {"peers":[{"id":"ESP32_S3_BLE_A","rssi":-18,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-23,"dist":0.02}],"src":"B"}
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_A | Type: DIRECT
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_C | Type: DIRECT
```

### ✅ Successo se:
- Tutti e 3 gli ESP32 si vedono
- Tutti i peers sono DIRECT (nessun campo `via`)
- Le distanze sono ragionevoli (~0.01-0.02m)

---

## 🔄 Test 2: Mesh Propagation (perdita parziale)

### Setup:
```
ESP32-A ←─(10cm)─→ ESP32-B ←─(10cm)─→ ESP32-C
                                        ↑
                               Allontanalo da A!
```

### Procedura:
1. Mantieni A e B vicini (~10cm)
2. Mantieni B e C vicini (~10cm)
3. **Allontana C da A** (~2-3 metri, oppure schermalo con oggetti metallici)

### Verifica nei LOG del Serial Monitor:

**ESP32-A (dovrebbe vedere C via B):**
```
[SCAN] >>> Found device: ESP32_S3_BLE_B, RSSI: -20
[MESH] 🔍 Parsing manufacturer data from ESP32_S3_BLE_B (len: 7)
[MESH] 📡 Found 2 neighbor(s) in advertising from B
[MESH] ↪️  Added INDIRECT peer: ESP32_S3_BLE_C via B | RSSI: -45 (approx) | Dist: 0.05m

[JSON] 📤 Built message: 2 total peers (1 direct, 1 indirect)
[REPORT] JSON Payload: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-20,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-45,"dist":0.05,"via":"B"}],"src":"A"}
```

**ESP32-B (dovrebbe vedere tutti DIRECT):**
```
[JSON] 📤 Built message: 2 total peers (2 direct, 0 indirect)
[REPORT] JSON Payload: {"peers":[{"id":"ESP32_S3_BLE_A","rssi":-18,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-25,"dist":0.02}],"src":"B"}
```

### Verifica nei LOG dell'App:

**Phone_1 (connesso ad A):**
```
[MESH PARSER] 📥 RAW MESSAGE: {"peers":[{"id":"ESP32_S3_BLE_B","rssi":-20,"dist":0.01},{"id":"ESP32_S3_BLE_C","rssi":-45,"dist":0.05,"via":"B"}],"src":"A"}
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | Type: DIRECT | RSSI: -20 dBm | Distance: 0.01m
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_C | Type: INDIRECT (via B) | RSSI: -45 dBm | Distance: 0.05m | ↪️  INDIRECT
```

### ✅ Successo se:
- A vede B come **DIRECT**
- A vede C come **INDIRECT via B**
- La distanza A→C è circa = Dist(A→B) + Dist(B→C)
- Il campo `via` è presente nel JSON per C
- L'app mostra `↪️ ` per il peer indiretto

---

## 🐛 Troubleshooting

### ❌ Non vedo log [MESH]:
- Verifica che gli sketch siano stati caricati correttamente
- Controlla che il baud rate sia 115200
- Premi il bottone RESET sugli ESP32

### ❌ Nessun peer indiretto:
- Verifica che l'ESP32 intermedio (B) stia effettivamente vedendo entrambi (A e C)
- Controlla che i manufacturer data vengano popolati: cerca `[ADV] Setting manufacturer data`
- Verifica che il peer da "nascondere" (C) sia effettivamente fuori portata da A

### ❌ Campo `via` non appare nel JSON:
- Controlla che il peer sia effettivamente indiretto (log `[MESH] ↪️  Added INDIRECT peer`)
- Verifica che `isIndirect` sia `true` nell'array `peers[]`
- Controlla la lunghezza dei manufacturer data (deve essere > 3 byte)

### ❌ Distanze sbagliate:
- Verifica la formula RSSI→Distance: `float rssiToDistanceMeters(int rssi)`
- Controlla che la somma delle distanze sia corretta
- Ricorda che RSSI è molto variabile, fluttuazioni sono normali

---

## 📸 Screenshot da Catturare

1. **Serial Monitor ESP32-A** con log [MESH] ↪️  
2. **Serial Monitor ESP32-B** con log [JSON] mostrando manufacturer data
3. **App Phone_1** mostrando peer INDIRECT con campo `via`
4. **Network View UI** con icona `↪️ ` per peer indiretto

---

## 📝 Dati da Annotare

| Parametro | Valore Atteso | Valore Misurato | Note |
|-----------|---------------|-----------------|------|
| Distanza A→B | ~0.01m | _____ m | Diretta |
| Distanza B→C | ~0.02m | _____ m | Diretta |
| Distanza A→C (mesh) | ~0.03m | _____ m | Indiretta |
| Distanza A→C (reale) | ? | _____ m | Misura col metro |
| RSSI A→B | ~-20 dBm | _____ dBm | |
| RSSI B→C | ~-25 dBm | _____ dBm | |
| RSSI A→C (approx) | ~-45 dBm | _____ dBm | Somma |

---

## ⏱️ Timeline Test

1. **0:00** - Upload sketch, apri Serial Monitor
2. **0:30** - Reset ESP32, verifica init
3. **1:00** - Lancia app, fai PAIRING+SEARCHING
4. **2:00** - Verifica Test 1 (tutti vicini)
5. **3:00** - Allontana ESP32-C da A
6. **4:00** - Verifica Test 2 (mesh propagation)
7. **5:00** - Cattura screenshot e annota risultati

**Durata totale:** ~5-10 minuti

---

## 🎯 Criteri di Successo

✅ **Test PASSED se:**
- [ ] Tutti e 3 gli ESP32 si inizializzano correttamente
- [ ] Test 1: Tutti si vedono come DIRECT quando vicini
- [ ] Test 2: ESP32-A vede C come INDIRECT via B quando C è lontano
- [ ] Campo `via` appare correttamente nel JSON
- [ ] App mostra icona `↪️ ` per peers indiretti
- [ ] Distanza calcolata è ragionevole (somma delle distanze)

❌ **Test FAILED se:**
- [ ] ESP32 non si vedono anche quando vicini
- [ ] Nessun peer indiretto viene mai creato
- [ ] App crasha o non mostra i peers
- [ ] Distanze completamente sbagliate (>1m di errore)

---

## 🚀 Dopo il Test

Se tutto funziona:
✅ Procedi con **integrazione LoRa**!

Se ci sono problemi:
🐛 Analizza i log e riporta:
- Screenshot Serial Monitor
- Screenshot App
- Descrizione setup fisico (distanze, orientamento)
