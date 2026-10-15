# TestKit

Anleitung, Skripte und Messprotokoll für den Zwei-Rechner-Test und den Quadro-Sync-Test (siehe `ANLEITUNG.md`).

## Wichtig: die Player-Builds sind NICHT im Repo

Dieser Ordner enthält nur Dokumente und Skripte. Die Player-Builds (je ca. 100 MB) und die Dienste-Pakete gehören nicht
in Git: Git würde Zeilenenden verändern, und Mission Control lehnt Builds ab, deren Dateien nicht mehr zur Prüfsumme im
`LaunchCatalog.json` passen. Das fertige Paket (`test-kit.zip`, ca. 185 MB) wird aus diesem Ordner **gebaut** und von Hand
weitergegeben. Wer nur das Repo hat, baut es nach den folgenden Schritten oder bekommt die ZIP vom Entwicklerteam.

## Paket herstellen

Voraussetzung: Unity 6000.3.13f1 (Pfad in `UNITY_PATH`), .NET 8 SDK, PowerShell. Immer von einem sauberen Git-Stand
bauen (`git status` ohne Änderungen).

1. **Dienste-Pakete** (HangarBay, LaunchPad, MissionControl, UI):
   ```powershell
   cd MissionControlSystem
   .\Package.ps1        # erzeugt HangarBay.zip, LaunchPad.zip, MissionControl.zip, UI.zip (von Git ignoriert)
   ```
2. **Player-Builds** nach `TestProjects/pfcClusterBasicTestURP/builds/<Name>` (je Variante, danach die Projekteinstellungen
   zurücksetzen, weil Unity beim Bauen Dateien verändert: `git checkout -- TestProjects/pfcClusterBasicTestURP/ProjectSettings TestProjects/pfcClusterBasicTestURP/Assets/Resources`):
   ```bash
   export UNITY_PATH='<Unity-Hub-Pfad>/6000.3.13f1/Editor/Unity.exe'
   .claude/skills/unity-compile-check/scripts/build_player.sh TestProjects/pfcClusterBasicTestURP builds/release 25
   ```
   | Variante | Änderung in `ProjectSettings/ProjectSettings.asset` vor dem Bauen |
   |---|---|
   | `release` | keine |
   | `netlog` | unter `scriptingDefineSymbols:` den Eintrag `Standalone: CLUSTER_DISPLAY_NETWORK_LOG` setzen (schreibt ein großes Netzwerk-Protokoll, nur zur Fehlersuche) |
   | `quadro-d3d11` | unter `m_BuildTargetGraphicsAPIs:` einen Eintrag `- m_BuildTarget: WindowsStandaloneSupport`, `m_APIs: 02000000`, `m_Automatic: 0` einfügen; `fullscreenMode: 0` (Exclusive Fullscreen) |
   | `quadro-d3d12` | wie oben mit `m_APIs: 12000000` |

   Prüfen, dass die API greift: den Player einmal kurz mit `-screen-fullscreen 0 -screen-width 640 -screen-height 360`
   starten und in `Player.log` die Zeile `Version: Direct3D 11.0` bzw. `Direct3D 12` suchen.
3. **Paket zusammenstellen** (prüft jede Datei per Prüfsumme gegen die Builds):
   ```powershell
   .\TestKit\make-kit.ps1 -Out <Zielordner>\test-kit -Zip
   ```
   Die ZIP enthält auch `THIRD-PARTY-NOTICES.md` (Lizenzhinweis des Fulldome-Testmusters von Paul Bourke). Dieser Hinweis
   muss jeder Weitergabe beiliegen.

## Inhalt dieses Ordners

| Datei | Zweck |
|---|---|
| `ANLEITUNG.md` | Schritt-für-Schritt-Anleitung, Teil A (Netzwerk, zwei Rechner) und Teil B (Quadro/RTX PRO Sync) |
| `MESSPROTOKOLL.md` | Vorlage zum Ausfüllen und Zurückschicken |
| `make-kit.ps1` | stellt das Paket zusammen |
| `scripts/` | Setup- und Hilfsskripte (`setup-controller`, `setup-node`, `start-services`, `network-check`, `fps-from-network-log`, `collect-logs`) |
