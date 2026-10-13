<#
  Sammelt die Protokolle des Cluster-Tests und Netzwerkangaben dieses Rechners in EINER ZIP-Datei
  (zum Zurueckschicken an das Entwicklerteam). Die ZIP liegt in <Target>\collected.

      .\collect-logs.ps1
      .\collect-logs.ps1 -Target C:\ClusterTest -Product pfcClusterBasicTestURP

  Enthalten ist NUR: Player.log, Player-prev.log und Network*.log des Produkts -Product (Network gekuerzt),
  die Dienst-Protokolle und config.json der Dienste, sowie system.txt (Rechnername, Windows-Version, Grafikkarte,
  Netzwerkadapter, IPv4-Adressen, Routen, Firewall-Regeln 'ClusterTest*', dotnet-Laufzeiten).
  Protokolle anderer Unity-Programme, Passwoerter und Dateiinhalte werden NICHT gesammelt.
  Am Ende listet das Skript alle Dateien der ZIP auf; die ZIP vor dem Versenden bei Bedarf ansehen.
#>
param(
    [string]$Target = 'C:\ClusterTest',
    [string]$Product = 'pfcClusterBasicTestURP'
)
$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP "cluster-logs-$env:COMPUTERNAME-$stamp"
New-Item $work -ItemType Directory -Force | Out-Null

# Player-Protokolle (Unity schreibt nach LocalLow\<Firma>\<Produkt>), nur das Produkt dieses Tests
$low = Join-Path $env:USERPROFILE 'AppData\LocalLow'
Get-ChildItem $low -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName $Product } |
    Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem $_ -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'Player.log', 'Player-prev.log' -or $_.Name -like 'Network*.log' } } |
    ForEach-Object {
        $name = ($_.FullName.Substring($low.Length + 1) -replace '[\\/]', '__')
        if ($_.Name -like 'Network*') {
            # Netzwerk-Protokolle werden sehr gross: Anfang (Handshake) und Ende behalten
            $lines = Get-Content $_.FullName -TotalCount 30000
            $tail = Get-Content $_.FullName -Tail 3000
            Set-Content (Join-Path $work $name) ($lines + '... (gekuerzt) ...' + $tail)
        } else { Copy-Item $_.FullName (Join-Path $work $name) }
    }

# Dienste
foreach ($f in Get-ChildItem (Join-Path $Target 'logs') -ErrorAction SilentlyContinue) { Copy-Item $f.FullName (Join-Path $work ("service__" + $f.Name)) }
foreach ($c in 'HangarBay\HangarBay\config.json', 'LaunchPad\LaunchPad\config.json', 'MissionControl\MissionControl\config.json') {
    $p = Join-Path $Target $c; if (Test-Path $p) { Copy-Item $p (Join-Path $work ("config__" + ($c -replace '[\\/]', '__'))) }
}

# Netzwerk und System
$sys = Join-Path $work 'system.txt'
& {
    "Rechner: $env:COMPUTERNAME   Zeit: $(Get-Date)"
    (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version | Out-String)
    "--- Grafikkarten"; (Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion | Out-String)
    "--- Adapter"; (Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed | Out-String)
    "--- IPv4"; (Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress, PrefixLength | Out-String)
    "--- Schnittstellenmetriken"; (Get-NetIPInterface -AddressFamily IPv4 | Select-Object InterfaceAlias, InterfaceMetric, NlMtu | Out-String)
    "--- Multicast-Routen"; (Get-NetRoute -DestinationPrefix '224.0.0.0/4' | Select-Object InterfaceAlias, RouteMetric, InterfaceMetric | Out-String)
    "--- Netzwerkprofile"; (Get-NetConnectionProfile | Select-Object InterfaceAlias, NetworkCategory | Out-String)
    "--- Multicast-Mitgliedschaften"; (netsh interface ipv4 show joins | Out-String)
    "--- Firewall-Regeln ClusterTest"; (Get-NetFirewallRule -DisplayName 'ClusterTest*' -ErrorAction SilentlyContinue | Select-Object DisplayName, Enabled, Action | Out-String)
    "--- dotnet"; (& dotnet --list-runtimes 2>&1 | Out-String)
} *> $sys

$outDir = Join-Path $Target 'collected'; New-Item $outDir -ItemType Directory -Force | Out-Null
$zip = Join-Path $outDir "cluster-logs-$env:COMPUTERNAME-$stamp.zip"
Get-ChildItem $work | ForEach-Object { '  enthalten: {0} ({1:N0} KB)' -f $_.Name, ($_.Length / 1KB) } | Write-Host
Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
Remove-Item $work -Recurse -Force
Write-Host "Fertig: $zip" -ForegroundColor Green
