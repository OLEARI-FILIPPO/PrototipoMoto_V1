# Script PowerShell per Wireless Debugging
# Salvare come: connect_wireless.ps1

param(
    [switch]$Quick,
    [string]$Ip = "10.29.1.105"
)

# Aggiungi ADB al PATH
$env:Path += ";C:\Users\fillo\AppData\Local\Android\sdk\platform-tools"

Write-Host "=== Flutter Wireless Debugging ===" -ForegroundColor Green
Write-Host ""

if ($Quick) {
    # Modalità veloce: usa MDNS per trovare automaticamente il dispositivo
    Write-Host "Ricerca dispositivo wireless già accoppiato..." -ForegroundColor Cyan
    
    $devices = adb devices | Select-String "10.29.1" | ForEach-Object { $_.ToString().Split()[0] }
    
    if ($devices.Count -eq 0) {
        Write-Host "❌ Nessun dispositivo wireless trovato. Provo a riconnettermi..." -ForegroundColor Red
        Write-Host ""
        Write-Host "Sul telefono, vai in 'Debug wireless' e leggi la porta sotto 'Indirizzo IP e porta'" -ForegroundColor Yellow
        $wirelessPort = Read-Host "Inserisci la PORTA wireless (es: 34413)"
        
        adb connect "${Ip}:${wirelessPort}"
        
        Write-Host ""
        Write-Host "Dispositivi connessi:" -ForegroundColor Green
        flutter devices
        
        Write-Host ""
        Write-Host "✅ FATTO! Ora puoi usare:" -ForegroundColor Green
        Write-Host "   flutter run -d ${Ip}:${wirelessPort}" -ForegroundColor White
    } else {
        Write-Host "✅ Dispositivo wireless già connesso!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Dispositivi disponibili:" -ForegroundColor Cyan
        flutter devices
        
        $wirelessDevice = $devices[0]
        Write-Host ""
        Write-Host "Per lanciare l'app:" -ForegroundColor Green
        Write-Host "   flutter run -d $wirelessDevice" -ForegroundColor White
    }
} else {
    Write-Host "ISTRUZIONI SUL TELEFONO:" -ForegroundColor Yellow
    Write-Host "1. Vai in Impostazioni > Opzioni sviluppatore"
    Write-Host "2. Attiva 'Debug wireless'"
    Write-Host "3. Tocca 'Accoppia dispositivo con codice di accoppiamento'"
    Write-Host "4. Annota IP, Porta e Codice"
    Write-Host ""

    # Input utente
    $pairIp = Read-Host "Inserisci IP del telefono (lascia vuoto per 10.29.1.105)"
    if ([string]::IsNullOrWhiteSpace($pairIp)) { $pairIp = "10.29.1.105" }
    
    $pairPort = Read-Host "Inserisci PORTA di accoppiamento (es: 41907)"
    $pairCode = Read-Host "Inserisci CODICE di accoppiamento (es: 193841)"

    Write-Host ""
    Write-Host "Accoppiamento in corso..." -ForegroundColor Cyan

    # Accoppiamento
    adb pair "${pairIp}:${pairPort}" $pairCode

    Write-Host ""
    Write-Host "Ora inserisci la porta WIRELESS (diversa dalla porta di accoppiamento)" -ForegroundColor Yellow
    Write-Host "Sul telefono, torna indietro e vedrai 'Indirizzo IP e porta' sotto 'Debug wireless'"
    $wirelessPort = Read-Host "Inserisci PORTA wireless (es: 34413)"

    Write-Host ""
    Write-Host "Connessione wireless in corso..." -ForegroundColor Cyan

    # Connessione
    adb connect "${pairIp}:${wirelessPort}"

    Write-Host ""
    Write-Host "Dispositivi connessi:" -ForegroundColor Green
    adb devices

    Write-Host ""
    Write-Host "Dispositivi Flutter:" -ForegroundColor Green
    flutter devices

    Write-Host ""
    Write-Host "✅ FATTO! Ora puoi usare:" -ForegroundColor Green
    Write-Host "   flutter run -d ${pairIp}:${wirelessPort}" -ForegroundColor White
    Write-Host ""
    Write-Host "Per riconnetterti velocemente la prossima volta:" -ForegroundColor Cyan
    Write-Host "   .\connect_wireless.ps1 -Quick" -ForegroundColor White
    Write-Host ""
    Write-Host "Per disconnettere:" -ForegroundColor Yellow
    Write-Host "   adb disconnect ${pairIp}:${wirelessPort}" -ForegroundColor White
}
