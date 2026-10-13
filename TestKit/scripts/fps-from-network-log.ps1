<#
  Berechnet aus einem Netzwerk-Protokoll (Player-Build "netlog") die Bildrate des Clusters.
  Das Protokoll liegt in %USERPROFILE%\AppData\LocalLow\<Firma>\<Produkt>\Network.NodeId-N.log.

      .\fps-from-network-log.ps1                       # neuestes Network*.log dieses Rechners
      .\fps-from-network-log.ps1 -Path D:\logs\Network.NodeId-1.log

  Ausgewertet werden die Zeilen "FrameData" (auf Repeatern "Recv", auf dem Emitter "Send").
  Pro Frame-Nummer zaehlt das erste Auftreten (Wiederholungen werden ignoriert).
#>
param([string]$Path)
$ErrorActionPreference = 'Stop'
if (-not $Path) {
    $Path = (Get-ChildItem (Join-Path $env:USERPROFILE 'AppData\LocalLow') -Recurse -Filter 'Network*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\Unity\*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $Path -or -not (Test-Path $Path)) { throw 'Kein Network*.log gefunden. Wurde der Player-Build "netlog" benutzt?' }
Write-Host "Auswertung: $Path"

$inv = [Globalization.CultureInfo]::InvariantCulture
$rx = [regex]'^(?<t>[0-9]+[,.][0-9]+),\s+(?<dir>Recv|Send) FrameData\s+: FrameIndex = (?<f>[0-9]+)'
$recv = @{}; $send = @{}
foreach ($line in [IO.File]::ReadLines($Path)) {
    $m = $rx.Match($line); if (-not $m.Success) { continue }
    $f = [long]$m.Groups['f'].Value; $t = [double]::Parse($m.Groups['t'].Value.Replace(',', '.'), $inv)
    $tbl = if ($m.Groups['dir'].Value -eq 'Recv') { $recv } else { $send }
    if (-not $tbl.ContainsKey($f)) { $tbl[$f] = $t }
}
$tbl = if ($recv.Count -gt 0) { $recv } else { $send }
$kind = if ($recv.Count -gt 0) { 'empfangene (Repeater)' } else { 'gesendete (Emitter)' }
if ($tbl.Count -lt 3) { throw "Zu wenige FrameData-Zeilen ($($tbl.Count)) gefunden." }

$frames = $tbl.Keys | Sort-Object
$times = $frames | ForEach-Object { $tbl[$_] }
$dt = for ($i = 1; $i -lt $times.Count; $i++) { ($times[$i] - $times[$i - 1]) * 1000.0 }
$span = $times[-1] - $times[0]
$sorted = $dt | Sort-Object
$p99 = $sorted[[Math]::Min($sorted.Count - 1, [int][Math]::Floor($sorted.Count * 0.99))]
Write-Host ("{0} Frames ({1}), von Frame {2} bis {3}, Dauer {4:N1} s" -f $times.Count, $kind, $frames[0], $frames[-1], $span)
Write-Host ("Mittlere Bildrate:        {0:N1} fps" -f (($times.Count - 1) / $span))
Write-Host ("Frame-Abstand:            mittel {0:N1} ms, Median {1:N1} ms, 99 % unter {2:N1} ms, max {3:N1} ms" -f ($dt | Measure-Object -Average).Average, $sorted[[int]($sorted.Count / 2)], $p99, $sorted[-1])
$missing = ($frames[-1] - $frames[0] + 1) - $frames.Count
if ($missing -gt 0) { Write-Host "Hinweis: $missing Frame-Nummern fehlen im Protokoll (Verlust oder Wiederholung)." }
