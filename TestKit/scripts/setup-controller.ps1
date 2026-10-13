<#
  Richtet den STEUERRECHNER ein (MissionControl + Web-Oberflaeche + HangarBay + LaunchPad).
  Dieser Rechner ist auch selbst ein Cluster-Knoten.

  Aufruf (PowerShell ALS ADMINISTRATOR):
      .\setup-controller.ps1 -Nic "Ethernet"

  -Nic          Name des (verkabelten) Netzwerkadapters fuer den Cluster-Verkehr (Get-NetAdapter zeigt ihn)
  -Target       Zielordner (Standard C:\ClusterTest)
  -PlayerName   Name der Player-EXE ohne .exe (Standard pfcClusterBasicTestURP), fuer die Firewall-Regel
#>
param(
    [Parameter(Mandatory = $true)][string]$Nic,
    [string]$Target = 'C:\ClusterTest',
    [string]$PlayerName = 'pfcClusterBasicTestURP'
)
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-Admin
Assert-AspNet8
$n = Resolve-ClusterNic -Nic $Nic -PeerAddress $null
Set-NicPrivate $n.Name
Write-Host "Cluster-Adapter: $($n.Name), IP $($n.Ip)"

New-Item $Target -ItemType Directory -Force | Out-Null
foreach ($p in 'HangarBay', 'LaunchPad', 'MissionControl', 'UI') { Expand-Package $p $Target }
$data = Join-Path $Target 'data'
New-Item (Join-Path $data 'HangarBayCache'), (Join-Path $data 'McStorage') -ItemType Directory -Force | Out-Null

# --- Konfiguration (wird hier selbst erzeugt, kein erster Start noetig) -------------------------------------------
Write-JsonNoBom (Join-Path $Target 'HangarBay\HangarBay\config.json') ([ordered]@{
    identifier = [guid]::NewGuid().ToString(); controlEndPoints = @('http://0.0.0.0:8100')
    storageFolders = @(@{ path = (Join-Path $data 'HangarBayCache'); maximumSize = 21474836480 }) })
Write-JsonNoBom (Join-Path $Target 'LaunchPad\LaunchPad\config.json') ([ordered]@{
    identifier = [guid]::NewGuid().ToString(); controlEndPoints = @('http://0.0.0.0:8200')
    clusterNetworkNic = $n.Name; hangarBayEndPoint = 'http://127.0.0.1:8100' })
Write-JsonNoBom (Join-Path $Target 'MissionControl\MissionControl\config.json') ([ordered]@{
    controlEndPoints = @('http://0.0.0.0:8000'); launchPadsEntry = "http://$($n.Ip):8000/"; localEntry = 'http://127.0.0.1:8000/'
    storageFolders = @(@{ path = (Join-Path $data 'McStorage'); maximumSize = 21474836480 })
    healthMonitoringIntervalSec = 5; launchPadFeedbackTimeoutSec = 30 })

# --- Firewall ------------------------------------------------------------------------------------------------------
$lpDir = Join-Path $Target 'LaunchPad\LaunchPad'
Add-FirewallRule 'ClusterTest Ports TCP' @{ Protocol = 'TCP'; LocalPort = '8000,8100,8200,8300,9000' }
Add-FirewallRule 'ClusterTest Multicast' @{ Protocol = 'UDP'; LocalPort = '25690' }
Add-FirewallRule 'ClusterTest Player'    @{ Program = (Join-Path $lpDir "toLaunch\$PlayerName.exe") }

# --- Starten -------------------------------------------------------------------------------------------------------
& (Join-Path $PSScriptRoot 'start-services.ps1') -Role controller -Target $Target

Write-Host ''
Write-Host '=== FERTIG: Steuerrechner ===' -ForegroundColor Green
Write-Host "Adresse dieses Rechners im Cluster-Netz: $($n.Ip)"
Write-Host "Web-Oberflaeche:  http://localhost:9000"
Write-Host "Auf dem zweiten Rechner: .\setup-node.ps1 -ControllerAddress $($n.Ip)"
Write-Host 'Weiter mit ANLEITUNG.md, Abschnitt 5.'
