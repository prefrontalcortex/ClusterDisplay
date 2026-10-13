# Cluster Display auf Unity 6.3: Testanleitung

Diese Anleitung führt durch einen Test des Cluster-Display-Systems mit **zwei verkabelten Windows-Rechnern**
(Teil A) und, darauf aufbauend, durch den Test der **Hardware-Synchronisation mit Quadro/RTX PRO Sync** (Teil B,
für den Forschungspartner). Teil B setzt voraus, dass Teil A fehlerfrei lief.

Was getestet wird: Ein Player-Build (Unity 6000.3, URP) läuft gleichzeitig auf beiden Rechnern. Ein Rechner ist der
**Emitter** (gibt Zustand und Takt vor), der andere der **Repeater** (folgt Frame für Frame). Gestartet, überwacht
und beendet wird über die Web-Oberfläche von **Mission Control** auf dem Steuerrechner.

Stand der Software: Branch `dotnet-update`, Unity 6000.3.13f1. Bekannte Einschränkungen stehen in Abschnitt 9.

> **Sicherheitshinweis: nur in einem abgeschotteten Testnetz verwenden.**
> Mission Control, HangarBay und LaunchPad haben **keine Anmeldung** und lauschen auf allen Netzwerkadaptern
> (Ports 8000, 8100, 8200, 8300, 9000, dazu UDP 25690). Wer diese Ports erreicht, kann Programme auf den
> Rechnern installieren und starten lassen. Die Setup-Skripte öffnen die Ports in der Windows-Firewall für **alle**
> Netzwerkprofile und stellen das Profil des Cluster-Adapters auf „Privat“. Deshalb:
> Rechner nur in einem eigenen Netz (eigener Switch, nicht mit Büro-, WLAN- oder Internetnetz verbunden) betreiben und
> nach dem Test die Regeln entfernen und die Dienste beenden (Abschnitt 10).

> **Hinweis zu Drittmaterial:** Die Player-Builds enthalten das Fulldome-Testmuster von Paul Bourke. Seine Lizenzangabe
> steht in `THIRD-PARTY-NOTICES.md` (liegt diesem Paket bei) und muss beiliegen, wenn das Paket oder Teile davon
> weitergegeben werden.

---

## 1. Was gebraucht wird

| | Anforderung |
|---|---|
| Rechner | 2 × Windows 11 (64 Bit), Grafikkarte mit aktuellem Treiber, Monitor am Rechner (der Player zeigt ein Fenster) |
| Netzwerk | Beide Rechner **per Kabel am selben Switch**, im **selben IP-Netz** (z. B. 192.168.10.x / 255.255.255.0). Multicast muss erlaubt sein. WLAN am besten ausschalten. |
| Software | **ASP.NET Core Runtime 8 (x64)** auf beiden Rechnern: <https://dotnet.microsoft.com/en-us/download/dotnet/8.0>, Spalte „ASP.NET Core Runtime“ (nicht nur „.NET Runtime“ oder „Desktop Runtime“) |
| Rechte | Administrator auf beiden Rechnern (für die Firewall-Regeln beim Setup) |
| Platz | ca. 1 GB je Rechner |
| Benutzer | Auf jedem Rechner ist ein Benutzer **angemeldet** (der Player öffnet sein Fenster auf diesem Desktop) |

Rollen der beiden Rechner:

| Rechner | Rolle | Dienste |
|---|---|---|
| **A** (Steuerrechner) | steuert und ist selbst Knoten (Emitter) | MissionControl, Web-Oberfläche, HangarBay, LaunchPad |
| **B** | Knoten (Repeater) | HangarBay, LaunchPad |

## 2. Inhalt des Pakets

```
test-kit\
  ANLEITUNG.md                diese Datei
  MESSPROTOKOLL.md            Vorlage zum Ausfüllen und Zurückschicken
  THIRD-PARTY-NOTICES.md      Lizenzhinweis zum enthaltenen Testmuster (muss beiliegen)
  packages\                   Dienste (HangarBay, LaunchPad, MissionControl, UI als ZIP)
  player\
    release\                  Player-Build für Teil A (Automatische Grafik-API, Fenstermodus)
    netlog\                   gleicher Build mit Netzwerk-Protokoll (nur zur Fehlersuche, schreibt viel Log)
    quadro-d3d11\             Teil B: nur DirectX 11, Exclusive Fullscreen
    quadro-d3d12\             Teil B: nur DirectX 12, Exclusive Fullscreen
  scripts\                    Setup- und Hilfsskripte
```

**Wichtig:** Die Ordner unter `player\` nicht öffnen, bearbeiten oder durch Git/Editoren laufen lassen. Mission
Control prüft jede Datei per Prüfsumme. Wurde eine Datei verändert (auch nur Zeilenenden), wird der Build abgelehnt.
Dann den Ordner frisch aus dem Paket kopieren.

## 3. Vorbereitung (auf beiden Rechnern)

1. Das Paket `test-kit` auf **beide** Rechner kopieren (z. B. nach `C:\test-kit`).
2. Falls das Paket als ZIP-Datei oder über die Cloud kam, in einer PowerShell einmalig ausführen:
   ```powershell
   Get-ChildItem C:\test-kit -Recurse | Unblock-File
   ```
3. Adapternamen und IP notieren:
   ```powershell
   Get-NetAdapter | Where-Object Status -eq Up | Select Name, LinkSpeed
   Get-NetIPAddress -AddressFamily IPv4 | Select InterfaceAlias, IPAddress
   ```
   Der Kabeladapter heißt meist „Ethernet“. `LinkSpeed` sollte 1 Gbps sein.
4. Prüfen, dass sich beide Rechner erreichen: `ping <IP des anderen>`. Wenn nicht: Windows-Firewall bzw.
   Netzwerkprofil prüfen (Abschnitt 8) und Switch/Subnetz kontrollieren.

## 4. Netzwerk-Check (Pflicht, 5 Minuten)

Das Cluster-Protokoll nutzt **UDP-Multicast** (Gruppe 224.0.1.0, Port 25690). Dieser Check zeigt, ob das Netz dafür
taugt, bevor irgendetwas anderes eingerichtet wird. Er braucht weder Unity noch die Dienste.

Alle Befehle in einer PowerShell im Ordner `C:\test-kit\scripts`. Ersetze `"Ethernet"` durch den Adapternamen.

**Richtung A → B:**

1. Auf **B** den Empfänger starten (wartet 60 s):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\network-check.ps1 -Mode receive -Nic "Ethernet" -Seconds 60
   ```
2. Danach auf **A** den Sender (30 Pakete in ca. 15 s):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\network-check.ps1 -Mode send -Nic "Ethernet" -Count 30
   ```
3. Ergebnis auf B ablesen: `ERGEBNIS: 30 Pakete von <IP von A>`.

**Richtung B → A:** dieselben Schritte mit vertauschten Rollen.

**Auswertung:** 28 bis 30 von 30 in beiden Richtungen ist gut. Kommt **nichts** an, nicht fortfahren, sondern
Abschnitt 8 („Es kommt nichts an“). Ein Verlust von mehr als ca. 10 % deutet auf ein ungeeignetes Netz hin (häufig WLAN).

## 5. Dienste einrichten

Jeweils eine **PowerShell als Administrator** (Rechtsklick auf „Windows PowerShell“ → „Als Administrator ausführen“),
Ordner `C:\test-kit\scripts`.

**Rechner A (Steuerrechner):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-controller.ps1 -Nic "Ethernet"
```

Das Skript entpackt die Dienste nach `C:\ClusterTest`, erzeugt die Konfiguration, legt Firewall-Regeln an, setzt das
Netzwerkprofil des Kabeladapters auf „Privat“, startet die vier Dienste und gibt zum Schluss die **IP von A** aus.

**Rechner B (Knoten):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-node.ps1 -ControllerAddress <IP von A>
```

Am Ende gibt das Skript zwei Adressen aus, die in Abschnitt 6 gebraucht werden
(`http://<IP von B>:8100/` und `http://<IP von B>:8200/`).

Nach einem Neustart eines Rechners die Dienste wieder starten (kein erneutes Setup nötig):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-services.ps1 -Role controller   # auf A
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-services.ps1 -Role node         # auf B
```

## 6. Einrichten in der Web-Oberfläche (auf A)

Browser auf Rechner A: **<http://localhost:9000>**.

### 6.1 Geräte anlegen (Menü „Devices“)

Pro Rechner ein **Launch Complex**. Unter „Devices“ → **Add New**:

| Feld | Rechner A | Rechner B |
|---|---|---|
| Name | `A` | `B` |
| Hangar bay endpoint | `http://127.0.0.1:8100/` | `http://<IP von B>:8100/` |
| Hangar bay identifier | per Pfeil-Knopf neben dem Feld laden | ebenso |

Im Dialog dann **Launchpads → Add New**:

| Feld | Rechner A | Rechner B |
|---|---|---|
| Name | `LaunchPad A` | `LaunchPad B` |
| Endpoint | `http://127.0.0.1:8200/` | `http://<IP von B>:8200/` |
| Launchpad identifier | per Pfeil-Knopf laden | ebenso |

Beide Dialoge mit **Add** bestätigen. Lässt sich die Kennung nicht laden, ist der Dienst nicht erreichbar
(Abschnitt 8).

### 6.2 Build registrieren (Menü „Assets“)

**Add New**, dann:

- Name: `Test Release`
- URL: Pfad des Ordners **auf Rechner A**, z. B. `C:\test-kit\player\release`

Nach **Add** prüft Mission Control alle Dateien (dauert einige Sekunden bis eine Minute). Der Eintrag erscheint mit
Größe (ca. 40 MB). Erscheint stattdessen eine Fehlermeldung mit einem Dateinamen, siehe Abschnitt 8.

### 6.3 Konfigurieren (Menü „Configuration“)

1. Oben im Dropdown den Asset `Test Release` wählen.
2. Beim Complex `A` das Zahnrad → beim LaunchPad das Zahnrad: **Node role = Emitter**, mit OK bestätigen
   (beide Dialoge). Das ist wichtig, damit klar ist, welcher Rechner Emitter ist.
3. Beim Complex `B` ebenso: **Node role = Repeater**.
4. Globale Parameter (weiter unten auf der Seite):
   - **Enable hardware synchronization: AUS** (Teil A testet nur das Netzwerk; die Hardware-Synchronisation kommt in Teil B)
   - Target frame rate: `60` (Standard 0 bedeutet unbegrenzt)
   - Handshake timeout: `10` Sekunden (Standard)
   - alle anderen Werte unverändert

### 6.4 Starten und beenden

- **Starten:** oben rechts **Launch**. Auf beiden Rechnern öffnet sich nach wenigen Sekunden das Player-Fenster.
- **Beenden:** oben rechts **Stop**. Mit mindestens zwei Knoten wird der Cluster geordnet beendet.

Hinweis: Mit nur **einem** Knoten funktioniert das geordnete Beenden nicht (kein Steuerprozess); der Player wird
nach 15 s hart beendet. Das ist erwartet.

## 7. Was geprüft und notiert wird

Trage die Ergebnisse in `MESSPROTOKOLL.md` ein.

1. **Start:** Erscheinen beide Fenster innerhalb von etwa 10 s? Meldet die Oberfläche beide LaunchPads als
   „launched“?
2. **Synchronität:** Läuft die Animation auf beiden Bildschirmen gleichzeitig? (Beide Monitore nebeneinander
   oder mit Handykamera filmen, z. B. 30 Sekunden.)
3. **Stabilität:** Läuft der Cluster **10 Minuten** ohne Abbruch? Bleibt die Bildrate konstant?
4. **Beenden:** Beenden beide Fenster nach **Stop** innerhalb von 15 s?
5. **Bildrate genau messen** (optional, mit dem Build `netlog`): In 6.2 stattdessen `C:\test-kit\player\netlog`
   registrieren und wählen. Nach einem Lauf von 2 Minuten auf einem Rechner:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\fps-from-network-log.ps1
   ```
   Das Skript nennt Bildrate und Abstand zwischen den Frames. Erwartung im Kabelnetz: Bildrate ≈ Zielwert
   (z. B. 60 fps), der Abstand schwankt nur im Bereich weniger Millisekunden. Die Protokolle des Builds
   `netlog` sind groß (mehrere MB pro Minute); nach dem Test löschen.

### Bekannter Referenzwert

Auf einem **WLAN**-Aufbau (nur zum Vergleich) lief der Cluster mit etwa **0,4 fps**, weil die Meldungen pro Frame
verzögert wurden. Im Kabelnetz sollte das nicht passieren. Kommt es doch so, ist das ein Hinweis auf das Netz
(Abschnitt 8).

## 8. Fehlersuche

Bei jedem Problem zuerst `collect-logs.ps1` auf **beiden** Rechnern ausführen und die ZIP-Dateien aus
`C:\ClusterTest\collected` mitschicken:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\collect-logs.ps1
```

Die ZIP enthält **nur** die Protokolle dieses Tests (`Player.log`, `Network*.log` des Test-Players, Dienst-Protokolle,
`config.json` der Dienste) und `system.txt` (Rechnername, Windows-Version, Grafikkarte, Netzwerkadapter und IP-Adressen,
Routen, Firewall-Regeln `ClusterTest*`). Das Skript listet die Dateien am Ende auf; die ZIP kann vor dem Versenden
mit einem ZIP-Programm angesehen werden.

| Beobachtung | Wahrscheinliche Ursache und Maßnahme |
|---|---|
| Dienst startet nicht, Meldung zu .NET oder `Microsoft.AspNetCore.App` | Nur „.NET Runtime“ installiert. **ASP.NET Core Runtime 8** installieren (siehe Abschnitt 1). Prüfen: `dotnet --list-runtimes` muss `Microsoft.AspNetCore.App 8.x` enthalten. |
| Skript bricht ab: „Bitte als Administrator starten“ | PowerShell mit „Als Administrator ausführen“ öffnen. |
| In der Oberfläche lässt sich die Kennung nicht laden | Dienst auf dem Rechner läuft nicht oder die Firewall blockt: `start-services.ps1` ausführen, dann vom anderen Rechner `Test-NetConnection <IP> -Port 8100` und `-Port 8200`. |
| Asset wird abgelehnt, Meldung nennt eine Datei („MD5“) | Datei verändert (z. B. Zeilenenden durch Git oder Editor). Ordner `player\...` frisch aus dem Paket kopieren, nicht öffnen. |
| **Es kommt nichts an** (Netzwerk-Check, Abschnitt 4) | 1) Netzwerkprofil des Adapters auf „Privat“ (`Get-NetConnectionProfile`). 2) Beide Rechner im selben Subnetz? 3) Switch: IGMP-Snooping ohne Querier oder „Multicast blocken“ abschalten bzw. Multicast-Flooding aktivieren. 4) Firewall: `Get-NetFirewallRule -DisplayName 'ClusterTest*'` zeigt die Regeln. 5) Mehrere Adapter (VPN, Hyper-V, WLAN)? Mit `-Nic` den richtigen Adapter wählen, andere Adapter zum Test deaktivieren. |
| Player beendet sich nach etwa 10 s. Log: `TimeoutException: Repeater failed to register with emitter` | Der Repeater bekommt keine Antwort vom Emitter (Multicast kommt nicht an). Netzwerk-Check in beiden Richtungen wiederholen. |
| Player-Log: `InvalidDataException: Received FrameData for frame 1 while we were expecting data for frame 0` | Pakete gingen beim Start verloren (typisch für WLAN oder überlastete Netze). Cluster erneut starten, sonst Netzwerk prüfen. |
| Cluster läuft, aber sehr langsam (unter 5 fps) | Netz verzögert die Meldungen pro Frame. Kabel und Switch prüfen, nichts anderes im Netz übertragen, Gigabit-Verbindung (`LinkSpeed`). |
| Bild auf einem Rechner erscheint nicht | Auf dem Rechner muss ein Benutzer angemeldet sein; der Bildschirm darf nicht gesperrt sein. |
| Nach einem Neustart geht nichts | `start-services.ps1` (Abschnitt 5). |

Die Player-Protokolle liegen unter `%USERPROFILE%\AppData\LocalLow\DefaultCompany\pfcClusterBasicTestURP\Player.log`,
die Dienst-Protokolle unter `C:\ClusterTest\logs`.

## 9. Bekannte Einschränkungen (Stand der Software)

- Gemessen und getestet sind: Kompilierung, Bildtests (URP, HDRP), Protokoll und Handshake auf zwei Rechnern. **Nicht
  getestet** sind Hardware-Synchronisation (Quadro/RTX PRO Sync) und Dauerläufe von Stunden.
- Das Beenden von Unity im Testlauf (Editor) stürzt in seltenen Fällen nach vollständigen Ergebnissen ab. Betrifft nicht den Player.
- Mit nur einem Knoten wird der Player nach 15 s hart beendet (siehe 6.4).
- Der Zeit-Sync läuft im Standard über den Engine-Zustand (kein fester Takt).

## 10. Aufräumen

```powershell
Get-Process HangarBay, LaunchPad, MissionControl, MissionControl.EngineeringUI.Server -ErrorAction SilentlyContinue | Stop-Process -Force
Get-NetFirewallRule -DisplayName 'ClusterTest*' | Remove-NetFirewallRule
Remove-Item C:\ClusterTest -Recurse -Force
```

---

# Teil B: Hardware-Synchronisation (Quadro Sync II / RTX PRO Sync)

Nur für Rechner mit **NVIDIA Quadro bzw. RTX PRO GPU** und **Quadro Sync II** oder **RTX PRO Sync**. Das Plugin
(`GfxPluginQuadroSync`) ist gegen die Unity-6.3-Header gebaut, wurde aber **noch nie mit Hardware ausgeführt**. Alle
Ergebnisse, auch Fehlschläge, sind wertvoll. Bitte genau protokollieren.

## B.1 Voraussetzungen

1. **Teil A** ist mit den Partner-Rechnern fehlerfrei durchgelaufen (Netzwerk-Check, Start, 10 Minuten stabil).
2. Sync-Karten sind eingebaut, per Sync-Kabel verbunden (Ethernet-Variante: **nicht über einen Switch**, sondern
   wie von NVIDIA empfohlen als Daisy-Chain; die Netzwerkverbindung des Clusters bleibt davon getrennt).
3. Aktueller NVIDIA-Treiber auf allen Knoten.
4. **Pro Knoten** in der NVIDIA-Systemsteuerung (Details und Bilder: `quadro-sync.md` in der Package-Dokumentation):
   - Windows-Anzeigeskalierung **100 %**
   - 3D-Einstellungen → Globale Voreinstellung **Workstation App – Dynamic Streaming**
   - **Vertikale Synchronisierung: Ein**
   - Auflösung und Bildwiederholrate einstellen (auf allen Knoten gleich)
   - **Anzeigen synchronisieren**: ein Knoten **Master** (Server-Bildwiederholrate = gewählte Rate), alle anderen **Slave**
5. Die Builds `quadro-d3d11` und `quadro-d3d12` laufen im **Exclusive Fullscreen** (Voraussetzung für Quadro Sync).
   Es darf nichts über dem Player liegen (Taskleiste, Fernwartung, Explorer-Fenster), das kostet einen Frame.

## B.2 Testablauf

Für **beide** Builds nacheinander, zuerst **DirectX 11**, dann **DirectX 12**:

1. Wie in Abschnitt 6.2: `player\quadro-d3d11` (später `player\quadro-d3d12`) als Asset registrieren und wählen.
2. Rollen wie in 6.3 (ein Emitter, übrige Repeater).
3. **Enable hardware synchronization: EIN** (in 6.3 war er aus).
4. Target frame rate = Bildwiederholrate der Anzeigen (z. B. `60`).
5. Cluster starten (**Launch**), mindestens 10 Minuten laufen lassen, dann **Stop**.

## B.3 Was zu prüfen und zu notieren ist

1. **Läuft der Player?** Auf allen Knoten, in beiden APIs (D3D11/D3D12). Fehlermeldungen im `Player.log`
   suchen (Stichworte `QuadroSync`, `NvAPI`, `swap group`, `barrier`).
2. **Ist die Synchronisation aktiv?** Mit Nvidias `configureDriver.exe` (Option **8**) zeigt jedes DirectX-Fenster
   links unten eine kleine Debug-Anzeige, die Quadro Sync als aktiv oder inaktiv ausweist (Bilder in `quadro-sync.md`).
3. **Tearing und Versatz:** Testmuster oder harte Kamerawechsel auf mehreren Anzeigen nebeneinander. Mit Kamera (Zeitlupe)
   filmen und festhalten: Sind die Schnitte auf allen Anzeigen im selben Bild? Kein Zerreißen?
4. **Bildratenabfälle:** Dabei geht die Synchronisation kurz verloren (Tearing). Zählen und notieren.
5. **Mit Hardware-Sync AUS wiederholen** (nur Schritt 3 ändern) und dasselbe aufnehmen, als Vergleich.

Dann `collect-logs.ps1` auf allen Knoten ausführen und alles zusammen mit `MESSPROTOKOLL.md` zurückschicken.
