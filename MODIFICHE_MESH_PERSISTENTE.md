# 🔧 MODIFICHE AL FIRMWARE ESP32 - MESH PERSISTENTE

## 📋 RIEPILOGO MODIFICHE

### **Problema Identificato:**
Gli ESP32 dopo 30 secondi dalla modalità PAIRING/SEARCHING tornavano in modalità IDLE, perdendo tutti i peer accoppiati e fermando lo scambio dati mesh.

### **Soluzione Implementata:**
Modificata la funzione `checkStateTimeout()` in tutti e 3 i firmware (MotoA, MotoB, MotoC):

```cpp
// PRIMA (comportamento problematico):
if (timeout) {
    enterState(IDLE);  // Sempre IDLE → mesh si ferma
}

// DOPO (comportamento corretto):
if (timeout) {
    if (peerCount > 0) {
        enterState(CONNECTED);  // Mantiene mesh attiva
    } else {
        enterState(IDLE);       // Solo se nessun peer trovato
    }
}
```

---

## ✅ FILE MODIFICATI

1. **MotoA**: `sketch_ESP32_S3_BLE_Server/MotoA/sketch_ESP32_S3_BLE_Server/sketch_ESP32_S3_BLE_Server.ino`
2. **MotoB**: `sketch_ESP32_S3_BLE_Server/MotoB/sketch_ESP32_S3_BLE_Server_B/sketch_ESP32_S3_BLE_Server_B.ino`
3. **MotoC**: `sketch_ESP32_S3_BLE_Server/MotoC/sketch_ESP32_S3_BLE_Server_C/sketch_ESP32_S3_BLE_Server_C.ino`

---

## 🎯 COMPORTAMENTO ATTESO

### **Ciclo di Vita Mesh Network:**

1. **IDLE** → Dispositivo acceso ma non attivo
   - LED: 🔵 Blu fisso
   - Scansione: ❌ Disabilitata
   - Peers: Vuoto

2. **PAIRING/SEARCHING** → Ricerca e accoppiamento (30s)
   - LED: 🟡 Giallo lampeggiante (PAIRING) / 🟣 Magenta lampeggiante (SEARCHING)
   - Scansione: ✅ Attiva
   - Peers: In rilevamento

3. **CONNECTED** → Mesh attiva permanente
   - LED: 🟢 Verde fisso
   - Scansione: ✅ Attiva (continua)
   - Peers: Mantiene e aggiorna continuamente
   - **Persistenza**: Rimane in questo stato finché:
     - ESP32 viene spento
     - Comando STOPMODE viene inviato manualmente
     - Tutti i peers scompaiono oltre il timeout (10s)

---

## 🧪 PROCEDURA DI TEST

### **Setup Iniziale:**
```
┌─────────┐         ┌─────────┐         ┌─────────┐
│ ESP32-A │ ◄─────► │ ESP32-B │ ◄─────► │ ESP32-C │
│  (A)    │   BLE   │  (B)    │   BLE   │  (C)    │
└────┬────┘  Mesh   └────┬────┘  Mesh   └─────────┘
     │                   │
     │ BLE               │ BLE
     ▼                   ▼
┌─────────┐         ┌─────────┐
│ Phone 1 │         │ Phone 2 │
│Wireless │         │ Cabled  │
└─────────┘         └─────────┘
```

### **Passo 1: Flash del Firmware**
```bash
# Caricare i 3 firmware aggiornati sugli ESP32
# - MotoA → ESP32-A
# - MotoB → ESP32-B
# - MotoC → ESP32-C
```

### **Passo 2: Avvio delle App Flutter**
```bash
# Terminale 1 (Wireless Device - ESP32-A)
cd primo_progetto_flutter
flutter run -d 10.29.1.105:35719

# Terminale 2 (Cabled Device - ESP32-B)
cd primo_progetto_flutter
flutter run -d R58M32PJ87V

# Terminale 3 (Logs Device 1)
adb -s 10.29.1.105:35719 logcat -v time "*:S" "flutter:I"

# Terminale 4 (Logs Device 2)
adb -s R58M32PJ87V logcat -v time "*:S" "flutter:I"
```

### **Passo 3: Attivazione Mesh**
1. **Su Phone 1 (connesso a ESP32-A)**: Premi **PAIRING**
2. **Su Phone 2 (connesso a ESP32-B)**: Premi **SEARCHING**
3. ⏱️ **Aspetta 30 secondi** (timer scade)
4. ✅ **VERIFICA**: Entrambi i log devono mostrare:
   ```
   [STATE] Timeout reached, transitioning to CONNECTED (peers found)
   [MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | RSSI: -18 dBm | Distance: 0.01m
   [MESH PARSER] 📡 Peer: ESP_INDIRECT_C | RSSI: -25 dBm | Distance: 0.02m
   ```

### **Passo 4: Test Persistenza**
1. ⏱️ **Aspetta altri 2-3 minuti** senza toccare nulla
2. ✅ **VERIFICA**: I log continuano a mostrare dati mesh ogni ~100ms
3. ❌ **NON deve apparire**: `"peers":[]` dopo il timeout iniziale

### **Passo 5: Test Disconnessione/Riconnessione**
1. 🔌 **Spegni ESP32-C**
2. ✅ **VERIFICA**: Dopo ~10s, dovrebbe scomparire dai peers di A e B
3. 🔌 **Riaccendi ESP32-C**
4. ✅ **VERIFICA**: Riappare automaticamente grazie alla persistenza del MAC

---

## 📊 LOG DA MONITORARE

### **✅ Log di Successo:**
```
[MESH PARSER] Found 2 peer(s) in message
[MESH PARSER] 📡 Peer: ESP32_S3_BLE_B | RSSI: -18 dBm | Distance: 0.01m
[MESH PARSER] 📡 Peer: ESP_INDIRECT_C | RSSI: -25 dBm | Distance: 0.02m
[MESH PARSER] ✅ Updated: 2, New: 0, Total nodes: 2
```

### **❌ Log di Problema:**
```
[MESH PARSER] ℹ️ Empty peers list received  ← Se appare dopo 30s = PROBLEMA
[STATE] Timeout reached, returning to IDLE   ← Non deve più apparire con peers
```

---

## 🎨 INDICATORI LED

| Stato | Colore | Pattern | Significato |
|-------|--------|---------|-------------|
| IDLE | 🔵 Blu | Fisso | Nessuna attività mesh |
| PAIRING | 🟡 Giallo | Lampeggiante | In attesa di connessioni (30s) |
| SEARCHING | 🟣 Magenta | Lampeggiante | Cerca dispositivi (30s) |
| CONNECTED | 🟢 Verde | Fisso | **Mesh attiva e persistente** |

---

## 🚨 TROUBLESHOOTING

### **Problema: Peers scompaiono dopo 30s**
- ✅ **Soluzione**: Verificare che il firmware sia stato caricato con le modifiche
- ✅ **Check**: Cercare nel Serial Monitor: `"transitioning to CONNECTED (peers found)"`

### **Problema: ESP32-C non viene visto**
- ✅ **Soluzione**: Verificare che ESP32-C sia stato flashato con il nuovo firmware
- ✅ **Check**: Deve essere in modalità PAIRING o SEARCHING

### **Problema: Distanze sempre 0.00m**
- ❌ **Causa**: RSSI non viene letto correttamente
- ✅ **Soluzione**: Verificare che la funzione `rssiToDistanceMeters()` riceva valori RSSI validi

---

## 📝 NOTE IMPORTANTI

1. **Persistenza Flash**: I MAC address vengono salvati in NVS (Non-Volatile Storage)
2. **Comando CLEAR**: Per resettare i peers salvati, inviare "CLEAR" via BLE
3. **Timeout Peer**: Un peer viene rimosso dalla lista dopo 10s di inattività
4. **Auto-Save**: Ogni nuovo peer scoperto viene automaticamente salvato in flash

---

## ✨ PROSSIMI PASSI

Dopo aver verificato il funzionamento:
1. ✅ Testare con distanze maggiori (0.5m, 1m, 2m)
2. ✅ Testare con ostacoli tra i dispositivi
3. ✅ Testare la riconnessione dopo spegnimento/riaccensione
4. ✅ Aggiungere log su Serial Monitor ESP32 per debug dettagliato
5. ✅ Ottimizzare i parametri di calcolo distanza (`txPower`, `n`)

---

**Data Modifica**: 2026-01-21  
**Autore**: GitHub Copilot AI Assistant  
**Test Status**: ⏳ In attesa di verifica
