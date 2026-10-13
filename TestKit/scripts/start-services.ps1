<#
  Startet die Dienste (neu), z. B. nach einem Neustart des Rechners.

      .\start-services.ps1 -Role controller      # Steuerrechner: HangarBay, LaunchPad, MissionControl, Oberflaeche
      .\start-services.ps1 -Role node            # Knoten: HangarBay, LaunchPad

  Die Dienste laufen in minimierten Fenstern; Protokolle liegen in <Target>\logs.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('controller', 'node')][string]$Role,
    [string]$Target = 'C:\ClusterTest'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$logs = Join-Path $Target 'logs'
$hb = Join-Path $Target 'HangarBay\HangarBay\bin'
$lp = Join-Path $Target 'LaunchPad\LaunchPad\bin'
Start-ClusterService 'HangarBay' $hb (Join-Path $hb 'HangarBay.exe') $logs
Start-ClusterService 'LaunchPad' $lp (Join-Path $lp 'LaunchPad.exe') $logs
if ($Role -eq 'controller') {
    $mc = Join-Path $Target 'MissionControl\MissionControl\bin'
    $ui = Join-Path $Target 'UI\UI'
    Start-ClusterService 'MissionControl' $mc (Join-Path $mc 'MissionControl.exe') $logs
    Start-ClusterService 'UI' $ui (Join-Path $ui 'MissionControl.EngineeringUI.Server.exe') $logs
}

$ports = @{ HangarBay = 8100; LaunchPad = 8200 }
if ($Role -eq 'controller') { $ports['MissionControl'] = 8000; $ports['UI'] = 9000 }
foreach ($k in $ports.Keys) {
    if (Wait-Port $ports[$k]) { Write-Host "OK    $k (Port $($ports[$k]))" }
    else { Write-Warning "$k antwortet nicht auf Port $($ports[$k]). Siehe $logs\$k.err und $logs\$k.log" }
}
