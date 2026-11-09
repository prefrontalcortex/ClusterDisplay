<#
  Einstiegspunkt fuer das Testpaket: ein Skript, ein paar Fragen, fertig.

      Rechtsklick auf setup.ps1 -> "Mit PowerShell ausfuehren"   (oder in PowerShell: .\setup.ps1)

  Das Skript startet sich bei Bedarf selbst als Administrator neu und ruft danach setup-controller.ps1
  bzw. setup-node.ps1 mit den passenden Parametern auf. Alles Weitere steht in ANLEITUNG.md.

  Optional ohne Fragen:
      .\setup.ps1 -Role controller -Nic "Ethernet 2"
      .\setup.ps1 -Role node -ControllerAddress 192.168.1.102
#>
param(
    [ValidateSet('controller', 'node')][string]$Role,
    [string]$Nic,
    [string]$ControllerAddress,
    [string]$Target = 'C:\ClusterTest'
)
$ErrorActionPreference = 'Stop'

# --- Selbst als Administrator neu starten (Parameter werden mitgegeben) ---------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Starte neu mit Administratorrechten (Windows fragt gleich nach) ...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    foreach ($k in 'Role', 'Nic', 'ControllerAddress', 'Target') {
        if ($PSBoundParameters.ContainsKey($k)) { $argList += "-$k"; $argList += "`"$($PSBoundParameters[$k])`"" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

$scripts = Join-Path $PSScriptRoot 'scripts'
Set-Location $PSScriptRoot
Get-ChildItem $PSScriptRoot -Recurse -File | Unblock-File   # entfernt die "aus dem Internet"-Sperre der ZIP-Dateien

function Select-Nic([string]$Prompt) {
    $all = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' })
    if ($all.Count -eq 0) { throw 'Kein Netzwerkadapter mit IPv4-Adresse gefunden.' }
    Write-Host ''
    for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $all[$i].InterfaceAlias, $all[$i].IPAddress) }
    $c = Read-Host $Prompt
    $idx = 0
    if (-not [int]::TryParse($c, [ref]$idx) -or $idx -lt 1 -or $idx -gt $all.Count) { throw "Ungueltige Auswahl: '$c'" }
    return $all[$idx - 1].InterfaceAlias
}

Write-Host '=== Cluster-Testpaket: Einrichtung ===' -ForegroundColor Cyan
if (-not $Role) {
    Write-Host ''
    Write-Host '  [1] Steuerrechner  (Mission Control + Oberflaeche, genau EIN Rechner im Cluster)'
    Write-Host '  [2] Knoten         (jeder weitere Rechner)'
    $r = Read-Host 'Was ist dieser Rechner? (1/2)'
    switch ($r) { '1' { $Role = 'controller' } '2' { $Role = 'node' } default { throw "Ungueltige Auswahl: '$r'" } }
}

if ($Role -eq 'controller') {
    if (-not $Nic) { $Nic = Select-Nic 'Welcher Adapter ist das (verkabelte) Cluster-Netz? Nummer eingeben' }
    & (Join-Path $scripts 'setup-controller.ps1') -Nic $Nic -Target $Target
}
else {
    if (-not $ControllerAddress) { $ControllerAddress = (Read-Host 'IP-Adresse des Steuerrechners (steht am Ende seines Setups)').Trim() }
    if ($ControllerAddress -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Keine gueltige IPv4-Adresse: '$ControllerAddress'" }
    $p = @{ ControllerAddress = $ControllerAddress; Target = $Target }
    if ($Nic) { $p.Nic = $Nic }
    & (Join-Path $scripts 'setup-node.ps1') @p
}
