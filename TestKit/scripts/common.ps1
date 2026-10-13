# Gemeinsame Funktionen fuer die Setup-Skripte des Cluster-Display-Testkits.
# Wird von setup-controller.ps1, setup-node.ps1 und start-services.ps1 eingebunden (dot-sourcing).
# Hinweis: bewusst nur ASCII (Windows PowerShell 5.1 liest UTF-8 ohne BOM sonst falsch).

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Bitte PowerShell als Administrator starten (Rechtsklick -> Als Administrator ausfuehren). Noetig fuer die Firewall-Regeln.' }
}

function Assert-AspNet8 {
    $runtimes = $null
    try { $runtimes = & dotnet --list-runtimes 2>$null } catch { }
    if (-not ($runtimes | Select-String 'Microsoft\.AspNetCore\.App 8\.')) {
        throw ('ASP.NET Core Runtime 8 (x64) fehlt. Bitte installieren: https://dotnet.microsoft.com/en-us/download/dotnet/8.0 ' +
               '(Spalte "ASP.NET Core Runtime", NICHT nur ".NET Runtime" oder "Desktop Runtime"). Danach dieses Skript erneut starten.')
    }
}

# Liefert (Name, IPv4) des Netzwerkadapters. Ohne -Nic wird der Adapter gewaehlt, dessen IP im selben /24-Netz liegt
# wie -PeerAddress; sonst wird abgebrochen (damit nicht still der falsche Adapter benutzt wird).
function Resolve-ClusterNic([string]$Nic, [string]$PeerAddress) {
    $all = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' }
    if ($Nic) {
        $hit = $all | Where-Object { $_.InterfaceAlias -eq $Nic } | Select-Object -First 1
        if (-not $hit) {
            Write-Host 'Vorhandene Adapter mit IPv4-Adresse:'; $all | Format-Table InterfaceAlias, IPAddress | Out-String | Write-Host
            throw "Netzwerkadapter '$Nic' nicht gefunden oder ohne IPv4-Adresse."
        }
        return @{ Name = $hit.InterfaceAlias; Ip = $hit.IPAddress }
    }
    if ($PeerAddress) {
        $prefix = ($PeerAddress -split '\.')[0..2] -join '.'
        $hit = $all | Where-Object { $_.IPAddress -like "$prefix.*" } | Select-Object -First 1
        if ($hit) { return @{ Name = $hit.InterfaceAlias; Ip = $hit.IPAddress } }
    }
    Write-Host 'Vorhandene Adapter mit IPv4-Adresse:'; $all | Format-Table InterfaceAlias, IPAddress | Out-String | Write-Host
    throw 'Adapter konnte nicht automatisch bestimmt werden. Bitte -Nic "<Adaptername>" angeben (Name wie in Get-NetAdapter).'
}

function Write-JsonNoBom([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 6 -Compress
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Expand-Package([string]$Name, [string]$Target) {
    $zip = Join-Path (Join-Path $PSScriptRoot '..\packages') "$Name.zip"
    if (-not (Test-Path $zip)) { throw "Paket nicht gefunden: $zip" }
    $dst = Join-Path $Target $Name
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path $dst) {
        # config.json und Daten bleiben bei einem erneuten Setup nicht erhalten (frische Installation)
        Remove-Item $dst -Recurse -Force
    }
    Expand-Archive $zip -DestinationPath $dst -Force
}

function Add-FirewallRule([string]$Name, [hashtable]$Params) {
    Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Profile Any @Params | Out-Null
}

# Netzwerkprofil "Oeffentlich" blockiert eingehende Verbindungen strenger; fuer den Test auf "Privat" stellen
function Set-NicPrivate([string]$NicName) {
    $p = Get-NetConnectionProfile -InterfaceAlias $NicName -ErrorAction SilentlyContinue
    if ($p -and $p.NetworkCategory -ne 'Private') {
        Write-Host "Netzwerkprofil von '$NicName' war '$($p.NetworkCategory)', wird auf 'Privat' gesetzt."
        Set-NetConnectionProfile -InterfaceAlias $NicName -NetworkCategory Private
    }
}

function Start-ClusterService([string]$Name, [string]$WorkDir, [string]$Exe, [string]$LogDir) {
    if (-not (Test-Path $Exe)) { throw "Programm nicht gefunden: $Exe" }
    New-Item $LogDir -ItemType Directory -Force | Out-Null
    Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Exe)) -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process $Exe -WorkingDirectory $WorkDir -WindowStyle Minimized `
        -RedirectStandardOutput (Join-Path $LogDir "$Name.log") -RedirectStandardError (Join-Path $LogDir "$Name.err")
}

function Wait-Port([int]$Port, [int]$TimeoutSec = 40) {
    $end = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $end) {
        if (Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) { return $true }
        Start-Sleep 2
    }
    return $false
}
