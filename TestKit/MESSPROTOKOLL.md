# Messprotokoll: Cluster Display auf Unity 6.3

Bitte ausfüllen (im Editor oder ausgedruckt) und zusammen mit den ZIP-Dateien von `collect-logs.ps1` aller Rechner
zurückschicken. **Auch Fehlschläge eintragen**, sie sind wichtig.

| | |
|---|---|
| Datum | |
| Tester | |
| Teil | ☐ A (Netzwerk, ohne Hardware-Sync)   ☐ B (Quadro/RTX PRO Sync) |

## 1. Rechner

| | Rechner A (Emitter) | Rechner B (Repeater) | weitere |
|---|---|---|---|
| Name | | | |
| IP im Cluster-Netz | | | |
| Windows-Version | | | |
| Grafikkarte, Treiberversion | | | |
| Monitor, Auflösung, Hz | | | |
| Adapter, Link-Geschwindigkeit | | | |
| Sync-Karte (Teil B) | – | | |

Netzwerk: Switch (Hersteller/Modell): ______________   Weitere Geräte im Netz: ☐ nein  ☐ ja: ____________

## 2. Netzwerk-Check (Abschnitt 4)

| Richtung | angekommen von 30 | Bemerkung |
|---|---|---|
| A → B | | |
| B → A | | |

## 3. Cluster-Lauf (Teil A: Hardware-Sync AUS)

Build: ☐ release  ☐ netlog       Target frame rate: ______

| Prüfpunkt | Ergebnis | Bemerkung |
|---|---|---|
| Beide Fenster erscheinen innerhalb von ca. 10 s | ☐ ja  ☐ nein | |
| Beide LaunchPads „launched“ in der Oberfläche | ☐ ja  ☐ nein | |
| Animation auf beiden Bildschirmen synchron | ☐ ja  ☐ nein  ☐ unklar | |
| 10 Minuten ohne Abbruch | ☐ ja  ☐ nein | Abbruch nach: ______ |
| Beenden mit „Stop“ innerhalb von 15 s | ☐ ja  ☐ nein | |
| Mittlere Bildrate (`fps-from-network-log.ps1`, nur Build `netlog`) | ______ fps | |
| Frame-Abstand: Median / 99 % / max | ____ / ____ / ____ ms | |

Fehlermeldungen (Player.log oder Oberfläche), wörtlich:

```
```

## 4. Teil B: Hardware-Synchronisation

Pro Durchlauf eine Zeile (D3D11 und D3D12, jeweils mit Hardware-Sync **EIN** und zum Vergleich **AUS**):

| Build | HW-Sync | Player läuft auf allen Knoten | Sync aktiv laut `configureDriver` Option 8 | Tearing sichtbar | Versatz bei Kamerawechsel (Anzeigen im selben Bild?) | Bildratenabfälle in 10 min | Bemerkung |
|---|---|---|---|---|---|---|---|
| quadro-d3d11 | EIN | ☐ ja ☐ nein | ☐ ja ☐ nein ☐ ? | ☐ nein ☐ ja | ☐ ja ☐ nein | | |
| quadro-d3d11 | AUS | ☐ ja ☐ nein | – | ☐ nein ☐ ja | ☐ ja ☐ nein | | |
| quadro-d3d12 | EIN | ☐ ja ☐ nein | ☐ ja ☐ nein ☐ ? | ☐ nein ☐ ja | ☐ ja ☐ nein | | |
| quadro-d3d12 | AUS | ☐ ja ☐ nein | – | ☐ nein ☐ ja | ☐ ja ☐ nein | | |

NVIDIA-Einstellungen wie in `ANLEITUNG.md` B.1 gesetzt: ☐ ja  ☐ abweichend: ______________________________

Fehlermeldungen zum Quadro-Plugin (Stichworte `QuadroSync`, `NvAPI`, `swap`, `barrier` im Player.log), wörtlich:

```
```

Videos/Fotos beigelegt: ☐ ja (Dateinamen: ______________________)

## 5. Sonstige Beobachtungen

