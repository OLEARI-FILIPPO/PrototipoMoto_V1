# Mappa Offline Italia - App Flutter

Un'applicazione Flutter per visualizzare mappe offline delle regioni italiane con tracciamento GPS in tempo reale.

## Funzionalità

✨ **Caratteristiche principali:**

- 📥 **Download mappe offline**: Scarica le mappe di una o più regioni italiane per l'uso offline
- 📍 **Tracciamento GPS**: Visualizza la tua posizione in tempo reale sulla mappa
- 🗺️ **20 Regioni italiane**: Tutte le regioni d'Italia disponibili per il download
- 🔄 **Tracciamento continuo**: Opzione per seguire automaticamente i tuoi spostamenti
- 📱 **Funziona offline**: Una volta scaricate le mappe, funziona senza connessione internet
- 🎯 **Accuratezza elevata**: Utilizza il GPS del dispositivo per la massima precisione

## Come Usare l'App

### 1. Schermata Iniziale
All'avvio dell'app vedrai due opzioni principali:
- **Scarica Regioni**: Per scaricare le mappe offline
- **Visualizza Mappa**: Per aprire la mappa e vedere la tua posizione

### 2. Scaricare le Regioni

1. Premi il pulsante **"Scarica Regioni"**
2. Seleziona una o più regioni dalla lista (es. Lombardia, Lazio, Sicilia)
3. Premi il pulsante **"Scarica"** in basso
4. Attendi il completamento del download
   - Vedrai una barra di progresso che indica lo stato
   - Il download può richiedere alcuni minuti a seconda del numero di regioni

**⚠️ Nota importante:**
- Il download richiede una connessione internet attiva
- Le mappe possono occupare diversi MB di spazio
- Si consiglia di usare una connessione WiFi

### 3. Visualizzare la Mappa e la Posizione GPS

1. Premi il pulsante **"Visualizza Mappa"**
2. Premi il pulsante GPS blu (icona `my_location`) per ottenere la tua posizione
3. Concedi i permessi di localizzazione quando richiesto
4. La mappa si centrerà sulla tua posizione con un marker blu "Tu sei qui"

**Controlli disponibili:**
- 📍 **Pulsante GPS** (in basso a destra): Ottieni la posizione corrente
- 🔄 **Pulsante tracciamento**: Attiva/disattiva il tracciamento continuo (diventa verde quando attivo)
- ➕ **Zoom +**: Aumenta lo zoom della mappa
- ➖ **Zoom -**: Diminuisce lo zoom della mappa

### 4. Modalità Tracciamento

Quando attivi il tracciamento continuo:
- Il pulsante diventa **verde**
- La mappa segue automaticamente i tuoi spostamenti
- La posizione viene aggiornata ogni 10 metri
- Lo stato in alto mostra "Tracciamento attivo"

## Requisiti Tecnici

### Permessi necessari

**Android:**
- Accesso alla posizione (fine e approssimativa)
- Accesso a internet (per scaricare le mappe)

**iOS:**
- Accesso alla posizione quando l'app è in uso
- Accesso a internet (per scaricare le mappe)

### Requisiti di sistema
- Flutter SDK 3.9.2 o superiore
- Android 5.0 (API 21) o superiore
- iOS 12.0 o superiore

## Regioni Disponibili

Tutte le 20 regioni italiane:

**Nord:**
- Valle d'Aosta
- Piemonte
- Liguria
- Lombardia
- Trentino-Alto Adige
- Veneto
- Friuli-Venezia Giulia
- Emilia-Romagna

**Centro:**
- Toscana
- Umbria
- Marche
- Lazio

**Sud e Isole:**
- Abruzzo
- Molise
- Campania
- Puglia
- Basilicata
- Calabria
- Sicilia
- Sardegna

## Architettura del Progetto

```
lib/
├── main.dart                          # Entry point dell'app
├── models/
│   └── region.dart                    # Modello dati delle regioni italiane
├── services/
│   ├── location_service.dart          # Gestione GPS e geolocalizzazione
│   └── map_service.dart               # Download e gestione mappe offline
└── screens/
    ├── map_screen.dart                # Schermata mappa con GPS
    └── region_selection_screen.dart   # Schermata selezione/download regioni
```

## Tecnologie Utilizzate

- **flutter_map** (v8.2.2): Rendering delle mappe OpenStreetMap
- **flutter_map_tile_caching** (v10.1.1): Cache e download mappe offline
- **geolocator** (v13.0.4): Servizi di geolocalizzazione GPS
- **latlong2** (v0.9.1): Gestione coordinate geografiche
- **permission_handler** (v11.4.0): Gestione permessi del dispositivo
- **path_provider** (v2.1.5): Accesso al file system locale

## Risoluzione Problemi

### La posizione GPS non funziona
1. Verifica che i servizi di localizzazione siano attivi sul dispositivo
2. Controlla di aver concesso i permessi all'app
3. Prova a uscire all'aperto per una migliore ricezione GPS
4. Su Android, vai in Impostazioni > App > Mappa Offline Italia > Permessi

### Il download delle mappe fallisce
1. Verifica la connessione internet
2. Assicurati di avere spazio sufficiente sul dispositivo
3. Prova a scaricare una regione alla volta
4. Riavvia l'app e riprova

### La mappa appare vuota
1. Assicurati di aver scaricato almeno una regione
2. Verifica di essere nell'area della regione scaricata
3. Prova a scaricare nuovamente la regione

## Compilazione e Installazione

### Installare le dipendenze
```bash
cd primo_progetto_flutter
flutter pub get
```

### Eseguire l'app
```bash
flutter run
```

### Compilare per Android
```bash
flutter build apk --release
```

### Compilare per iOS
```bash
flutter build ios --release
```

## Note di Sviluppo

- Le mappe utilizzano tile di OpenStreetMap
- Livelli di zoom scaricati: 6-14 (bilanciamento tra qualità e spazio)
- Aggiornamento posizione GPS: ogni 10 metri
- Le coordinate delle regioni sono approssimative ai confini amministrativi

## Licenza

Questo progetto utilizza mappe da OpenStreetMap, che sono disponibili sotto la licenza Open Database License (ODbL).

## Crediti

- Mappe: © OpenStreetMap contributors
- Sviluppato con Flutter e Dart
