# Moto BLE firmware (A/B/C/…)

Documentazione collegata:

- `PINOUT_MOTO_FIRMWARE.md` — riepilogo dei pin usati dal firmware e loro funzione

Questi sketch sono pensati per essere **tutti identici** per MotoA, MotoB, MotoC…
L'unica cosa che cambia è:

- `DEVICE_ID` (A, B, C, …)
- `BLE_NAME` (es. `ESP32_S3_BLE_A`)

Ogni Moto:

- espone lo stesso servizio/characteristic BLE usato dall'app Flutter
- accetta comandi LED via write (`0`, `#RRGGBB`, ecc.)
- fa scanning BLE per trovare un altro Moto e stima una distanza *approssimativa* da RSSI
- quando un telefono è connesso, invia notifiche JSON con la distanza verso il peer (es. `{"peer":"MotoB","dist":1.23,"rssi":-67,"src":"A"}`)

## Come creare MotoC (o D, …)

1) Duplica uno degli sketch (A o B) in un nuovo file `.ino`.

2) Cambia solo queste 2 righe nella sezione `// --- CONFIG ---`:

- `static const char* DEVICE_ID = "C";`
- `static const char* BLE_NAME = "ESP32_S3_BLE_C";`

3) (Opzionale) aggiorna la logica di riconoscimento peer se vuoi che un Moto trovi *tutti* gli altri (non solo “quello opposto”).

## Note

- La conversione RSSI→metri è una stima molto grossolana (dipende da antenna, ambiente, orientamento).
- Il pin NeoPixel potrebbe cambiare in base alla tua scheda: qui è impostato a `GPIO48`.

## Peer discovery (importante)

La discovery dei peer **non** usa logiche tipo "se il nome finisce con `_A`".
Per rispettare questo vincolo, il firmware considera peer qualunque dispositivo che:

- pubblicizza `SERVICE_UUID`
- ha un nome non vuoto che contiene la stringa `ESP` (filtro generico)
- e non è uguale al proprio `BLE_NAME`

