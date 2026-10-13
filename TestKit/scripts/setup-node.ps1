<#
  Richtet einen weiteren CLUSTER-KNOTEN ein (HangarBay + LaunchPad).

  Aufruf (PowerShell ALS ADMINISTRATOR):
      .\setup-node.ps1 -ControllerAddress 192.168.10.5
      .\setup-node.ps1 -ControllerAddress 192.168.10.5 -Nic "Ethernet"

  -ControllerAddress  IP-Adresse des Steuerrechners (dort lief setup-controller.ps1)
  -Nic                Adaptername fuer den Cluster-Verkehr. Ohne Angabe wird der Adapter gewaehlt, der im selben
                      /24-Netz wie der Steuerrechner liegt.
  -Target / -PlayerName  wie bei setup-controller.ps1
#>
param(
    [Parameter(Mandatory = $true)][string]$ControllerAddress,
    [string]$Nic,
    [string]$Target = 'C:\ClusterTest',
    [string]$PlayerName = 'pfcClusterBasicTestURP'
)
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-Admin
Assert-AspNet8
$n = Resolve-ClusterNic -Nic $Nic -PeerAddress $ControllerAddress
Set-NicPrivate $n.Name
Write-Host "Cluster-Adapter: $($n.Name), IP $($n.Ip)"

Write-Host "Teste Verbindung zum Steuerrechner ($ControllerAddress`:8000) ..."
if (-not (Test-NetConnection $ControllerAddress -Port 8000 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    Write-Warning "MissionControl auf $ControllerAddress`:8000 nicht erreichbar. Laeuft setup-controller.ps1? Firewall? Setup wird trotzdem fortgesetzt."
}

New-Item $Target -ItemType Directory -Force | Out-Null
foreach ($p in 'HangarBay', 'LaunchPad') { Expand-Package $p $Target }
$cache = Join-Path $Target 'data\HangarBayCache'
New-Item $cache -ItemType Directory -Force | Out-Null

Write-JsonNoBom (Join-Path $Target 'HangarBay\HangarBay\config.json') ([ordered]@{
    identifier = [guid]::NewGuid().ToString(); controlEndPoints = @('http://0.0.0.0:8100')
    storageFolders = @(@{ path = $cache; maximumSize = 21474836480 }) })
Write-JsonNoBom (Join-Path $Target 'LaunchPad\LaunchPad\config.json') ([ordered]@{
    identifier = [guid]::NewGuid().ToString(); controlEndPoints = @('http://0.0.0.0:8200')
    clusterNetworkNic = $n.Name; hangarBayEndPoint = 'http://127.0.0.1:8100' })

$lpDir = Join-Path $Target 'LaunchPad\LaunchPad'
Add-FirewallRule 'ClusterTest Ports TCP' @{ Protocol = 'TCP'; LocalPort = '8100,8200,8300' }
Add-FirewallRule 'ClusterTest Multicast' @{ Protocol = 'UDP'; LocalPort = '25690' }
Add-FirewallRule 'ClusterTest Player'    @{ Program = (Join-Path $lpDir "toLaunch\$PlayerName.exe") }

& (Join-Path $PSScriptRoot 'start-services.ps1') -Role node -Target $Target

Write-Host ''
Write-Host '=== FERTIG: Knoten ===' -ForegroundColor Green
Write-Host "Adresse dieses Rechners im Cluster-Netz: $($n.Ip)"
Write-Host 'In der Web-Oberflaeche des Steuerrechners (Geraete -> Neu) eintragen:'
Write-Host "  Hangar-Bay-Endpunkt:  http://$($n.Ip):8100/"
Write-Host "  Launchpad-Endpunkt:   http://$($n.Ip):8200/"
