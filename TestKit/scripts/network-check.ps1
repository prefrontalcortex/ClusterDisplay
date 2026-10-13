<#
  Prueft, ob UDP-Multicast zwischen zwei Rechnern ankommt (unabhaengig von Unity).
  Der Test benutzt dieselbe Gruppe, denselben Port und denselben Socket-Aufbau wie der Cluster-Player
  (224.0.1.0:25690, gebunden an die Adapter-IP, Beitritt auf dem Adapter, TTL 1).

  Ablauf: auf Rechner A zuerst EMPFAENGER starten, danach auf Rechner B den SENDER. Danach Rollen tauschen.
      A:  .\network-check.ps1 -Mode receive -Nic "Ethernet" -Seconds 60
      B:  .\network-check.ps1 -Mode send    -Nic "Ethernet" -Count 30

  Auswertung: kommen alle (oder fast alle) Pakete an, ist das Netz fuer den Cluster geeignet. Kommt nichts an,
  siehe ANLEITUNG.md Abschnitt 8 (Switch, Firewall, mehrere Adapter, WLAN).
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('send', 'receive')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Nic,
    [int]$Seconds = 60,
    [int]$Count = 30,
    [string]$Group = '224.0.1.0',
    [int]$Port = 25690
)
$ErrorActionPreference = 'Stop'
$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $Nic -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
if (-not $ip) { throw "Adapter '$Nic' nicht gefunden oder ohne IPv4-Adresse (Get-NetAdapter zeigt die Namen)." }
$addr = [Net.IPAddress]::Parse($ip); $grp = [Net.IPAddress]::Parse($Group)

$u = New-Object System.Net.Sockets.UdpClient
$u.Client.SetSocketOption('IP', 'MulticastInterface', $addr.GetAddressBytes())
$u.Client.SetSocketOption('IP', 'MulticastTimeToLive', 1)
$u.Client.SetSocketOption('Socket', 'ReuseAddress', $true)
$u.Client.Bind([Net.IPEndPoint]::new($addr, $Port))
$u.JoinMulticastGroup($grp, $addr)
$u.MulticastLoopback = $true

if ($Mode -eq 'send') {
    $ep = [Net.IPEndPoint]::new($grp, $Port)
    Write-Host "Sende $Count Pakete von $ip an ${Group}:$Port ..."
    1..$Count | ForEach-Object {
        $b = [Text.Encoding]::ASCII.GetBytes("netcheck $env:COMPUTERNAME $_")
        [void]$u.Send($b, $b.Length, $ep); Start-Sleep -Milliseconds 500
    }
    Write-Host 'Fertig. Auf dem Empfaenger steht, wie viele angekommen sind.'
    return
}

$u.Client.ReceiveTimeout = 1000
Write-Host "Empfange auf ${ip}:$Port (Gruppe $Group), $Seconds s. Jetzt den Sender auf dem anderen Rechner starten ..."
$end = (Get-Date).AddSeconds($Seconds); $perSender = @{}
while ((Get-Date) -lt $end) {
    try {
        $ep = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $b = $u.Receive([ref]$ep)
        $txt = [Text.Encoding]::ASCII.GetString($b)
        if ($txt -like 'netcheck *' -and $ep.Address.ToString() -ne $ip) {
            $perSender[$ep.Address.ToString()] = 1 + [int]$perSender[$ep.Address.ToString()]
        }
    } catch [System.Net.Sockets.SocketException] { }
}
if ($perSender.Count -eq 0) { Write-Host 'ERGEBNIS: keine Pakete von einem anderen Rechner empfangen.' -ForegroundColor Red }
else { $perSender.GetEnumerator() | ForEach-Object { Write-Host ("ERGEBNIS: {0} Pakete von {1} (gesendet wurden normalerweise 30)" -f $_.Value, $_.Key) -ForegroundColor Green } }
