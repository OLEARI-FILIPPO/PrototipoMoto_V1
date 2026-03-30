# Pinout Firmware Moto (ESP32-S3 + BLE + LoRa + UWB)

Questo documento rappresenta la **legenda unica e ufficiale** per il cablaggio dell'hardware (ESP32-S3 con schede LoRa e UWB) usato nel progetto `MotoA`, `MotoB` e `MotoC`. 

> **Nota:** I tre sketch condividono il medesimo pinout logico.

---

## 1. Schema di Cablaggio Hardware 

Di seguito la tabella ufficiale con tutti i collegamenti, comprensiva dei colori dei cavi utilizzati fisicamente per facilitare il montaggio e la manutenzione.

**Convenzione Colori Cavi:**
- 🟡 **Giallo**: Corrente (VCC / 3V3)
- 🟤 **Marrone**: Ground (GND)
- ⚪ **Bianco**: IRQ per UWB e Interrupt (DIO1) per LoRa
- 🔴 **Rosso**: Chip Select (CS)
- ⚫ **Nero**: Reset (RST)
- 🟠 **Arancione**: Busy (solo LoRa)
- 🔵 **Blu**: MISO (Out to ESP)
- 🟢 **Verde**: MOSI (IN From ESP)

### Tabella Assegnazione Pin (GPIO)

*(Per "GPIOXX" ci si riferisce sempre al nome logico del pin sul microcontroller e alla serigrafia corrispondente sulla board, es. "IO12" o "12", **non** alla posizione meccanica sequenziale 1..40 del connettore).*

| Funzione / Segnale | Pin dell'Hardware | GPIO ESP32-S3 | Destinazione | Colore Cavo | Condivisione |
|---|---|---|---|---|---|
| **Alimentazione** | `VCC / 3V3` | `3V3` | LoRa + UWB | 🟡 Giallo | Comune |
| **Massa** | `GND` | `GND` | LoRa + UWB | 🟤 Marrone | Comune |
| | | | | | |
| **SPI Clock** | `SCK` (Pin 14 per LoRa) | **`GPIO12`** | LoRa + UWB | *(a seconda del cablaggio)* | **Condiviso** |
| **SPI MISO** | `MISO` (Pin 16 per LoRa) | **`GPIO13`** | LoRa + UWB | 🔵 Blu | **Condiviso** |
| **SPI MOSI** | `MOSI` (Pin 15 per LoRa) | **`GPIO11`** | LoRa + UWB | 🟢 Verde | **Condiviso** |
| | | | | | |
| **LoRa CS** | `CS / NSS` (Pin 5) | **`GPIO10`** | Solo LoRa | 🔴 Rosso | Dedicato LoRa |
| **LoRa Reset** | `RST` | **`GPIO5`** | Solo LoRa | ⚫ Nero | Dedicato LoRa |
| **LoRa BUSY** | `BUSY` | **`GPIO4`** | Solo LoRa | 🟠 Arancione | Dedicato LoRa |
| **LoRa DIO1** | `DIO1` (IRQ) | **`GPIO6`** | Solo LoRa | ⚪ Bianco | Dedicato LoRa |
| | | | | | |
| **UWB UART RX** | `RXD2` | **`GPIO18`** | Solo UWB (riceve da STM32) | ⚪ Bianco | Dedicato UWB |
| **UWB UART TX** | `TXD2` | **`GPIO17`** | Solo UWB (trasmette a STM32) | 🟢 Verde | Dedicato UWB |
| **UWB Reset** | `RSTn` | **`GPIO16`** | Solo UWB (reset hardware STM32) | ⚫ Nero | Dedicato UWB |
| | | | | | |
| **LED di Stato** | NeoPixel Onboard | **`GPIO48`** | LED RGB | - | Dedicato ESP32 |

---

## 2. Dettaglio Componenti Firmware

Tutti i pin elencati sopra si riflettono direttamente nei sorgenti del firmware.

### 2.1 File `comm_mode.h`
Il file di configurazione centrale per la gestione radio riporta queste costanti:

```cpp
// PIN LoRa (Modulo Pico-Style)
#define LORA_SCK   12
#define LORA_MISO  13
#define LORA_MOSI  11
#define LORA_CS    10
#define LORA_BUSY  4
#define LORA_RST   5
#define LORA_DIO1  6

// PIN UWB – MaUWB DW3000 con STM32 AT Command (UART2)
// Il modulo STM32 gestisce la comunicazione SPI con DW3000.
// L'ESP32 invia comandi AT via UART2; non serve SPI diretto.
#define UWB_RXD    18   // GPIO18 = UART2 RX (ESP32 riceve da STM32)
#define UWB_TXD    17   // GPIO17 = UART2 TX (ESP32 trasmette a STM32)
#define UWB_RESET  16   // GPIO16 = Reset hardware modulo UWB (STM32)
```

### 2.2 Bluetooth Low Energy (BLE)
La comunicazione BLE sfrutta il modulo integrato all'interno dell'ESP32-S3 e non coinvolge i pin fisici esposti.

- **Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- **Characteristic UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a8`

---

## 3. Riepilogo Logica Architetturale

Il progetto prevede l'uso contemporaneo di tre tecnologie wireless (BLE, LoRa, UWB) gestite dal medesimo microcontroller. Per ottimizzare le risorse e ridurre l'impiego dei GPIO dell'ESP32-S3:

1. Il **bus SPI** (`SCK`, `MISO`, `MOSI`) è utilizzato **esclusivamente** dal modulo LoRa (gestito internamente da RadioLib). Il modulo UWB **non** richiede SPI dall'ESP32.
2. Il modulo UWB adottato è il **MaUWB DW3000 con STM32 AT Command** (Makerfabs), dove un microcontroller STM32 gestisce internamente la comunicazione SPI con il chip DW3000. L'ESP32 si interfaccia al modulo tramite **UART2 (AT Commands)** su `GPIO17` (TX) e `GPIO18` (RX).
3. Il reset hardware del modulo UWB avviene tramite `GPIO16`.
4. Entrambi i moduli (LoRa e UWB) dispongono di **linee Reset indipendenti**.
5. Il protocollo AT seguito è quello documentato nel manuale Makerfabs UWB AT Module AT Command Manual. I comandi principali utilizzati all'avvio sono: `AT?`, `AT+RESTORE`, `AT+SETCFG`, `AT+SETCAP`, `AT+SETRPT`, `AT+SAVE`, `AT+RESTART`. I dati di ranging vengono ricevuti automaticamente in formato: `AT+RANGE=tid:X,mask:YY,seq:Z,range:(d0,...,d7),rssi:(r0,...)`.
