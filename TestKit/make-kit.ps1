<#
  Stellt das Testpaket "test-kit" aus dem Repo, den gebauten Diensten und den Player-Builds zusammen.

      .\make-kit.ps1 -Out H:\Projekt\_mc_test\test-kit -Zip

  Voraussetzungen (nicht Teil des Repos):
    * Dienste-Pakete: MissionControlSystem\Package.ps1 ausgefuehrt (erzeugt HangarBay.zip, LaunchPad.zip, MissionControl.zip, UI.zip)
    * Player-Builds in TestProjects\pfcClusterBasicTestURP\builds\{release,netlog,quadro-d3d11,quadro-d3d12}
      (Erzeugung: .claude\skills\unity-compile-check\scripts\build_player.sh; Details in MIGRATION_PROGRESS.md)

  Die Player-Ordner werden byte-genau kopiert (robocopy). Mission Control prueft jede Datei per MD5, deshalb darf
  nichts umkodiert werden (kein git add, keine Zeilenenden-Umwandlung).
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [switch]$Zip,
    [string[]]$Players = @('release', 'netlog', 'quadro-d3d11', 'quadro-d3d12')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$mcs = Join-Path $repo 'MissionControlSystem'
$builds = Join-Path $repo 'TestProjects\pfcClusterBasicTestURP\builds'

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item (Join-Path $Out 'packages'), (Join-Path $Out 'player'), (Join-Path $Out 'scripts') -ItemType Directory -Force | Out-Null

foreach ($z in 'HangarBay', 'LaunchPad', 'MissionControl', 'UI') {
    $src = Join-Path $mcs "$z.zip"
    if (-not (Test-Path $src)) { throw "Fehlt: $src (Package.ps1 ausfuehren)" }
    Copy-Item $src (Join-Path $Out 'packages')
}
foreach ($p in $Players) {
    $src = Join-Path $builds $p
    if (-not (Test-Path (Join-Path $src 'LaunchCatalog.json'))) { throw "Player-Build fehlt oder unvollstaendig: $src" }
    robocopy $src (Join-Path $Out "player\$p") /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy fehlgeschlagen fuer $p (Code $LASTEXITCODE)" }
}
Copy-Item (Join-Path $PSScriptRoot 'scripts\*.ps1') (Join-Path $Out 'scripts')
Copy-Item (Join-Path $PSScriptRoot 'ANLEITUNG.md'), (Join-Path $PSScriptRoot 'MESSPROTOKOLL.md') $Out

# Kontrolle: jede Datei der Player-Builds muss unveraendert angekommen sein
foreach ($p in $Players) {
    $a = Get-ChildItem (Join-Path $builds $p) -Recurse -File | Sort-Object FullName
    $b = Get-ChildItem (Join-Path $Out "player\$p") -Recurse -File | Sort-Object FullName
    if ($a.Count -ne $b.Count) { throw "Dateianzahl weicht ab fuer $p ($($a.Count) gegen $($b.Count))" }
    $bad = 0
    for ($i = 0; $i -lt $a.Count; $i++) { if ((Get-FileHash $a[$i].FullName -Algorithm MD5).Hash -ne (Get-FileHash $b[$i].FullName -Algorithm MD5).Hash) { $bad++ } }
    if ($bad) { throw "$bad Dateien weichen ab in $p" }
    Write-Host "OK  player\$p ($($a.Count) Dateien, byte-gleich)"
}
if ($Zip) {
    $zipPath = "$Out.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $Out -DestinationPath $zipPath
    Write-Host ("ZIP: {0} ({1:N0} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB))
}
Write-Host "Paket: $Out"
$global:LASTEXITCODE = 0   # robocopy meldet Code 1 bei erfolgreichem Kopieren
