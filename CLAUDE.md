# Unity Cluster Display – Modernisierung

Legacy-Code von Unity Cluster Display / Cluster Rendering wird auf eine aktuelle Unity-LTS gebracht.
Ziel: kompiliert ohne Fehler und ohne Obsolete-Warnungen, stabiler Frame-Lock über mehrere Nodes.

## Projektfakten
- Unity-Zielversion: 6000.3.26f1 LTS; danach Folgemeilenstein 6.7 LTS (derzeit nicht installiert). Quelle je Projekt: `ProjectSettings/ProjectVersion.txt`
- Das Repo besteht aus Packages unter `source/` (`com.unity.cluster-display`, `.graphics`, `.rpc`), kein Unity-Projekt im Root. Kompilier-Projekte: `TestProjects/pfcClusterBasicTestURP` (URP) und `TestProjects/GraphicsDemoProject` (HDRP)
- Netzwerk-Stack: eigenes UDP über `System.Net.Sockets` (`Runtime/Networking/UDPAgent.cs`, `Runtime/Node/{Emitter,Repeater}Node.cs`) – kein UNet, kein Unity Transport. Das Protokoll muss nur mit Unity 6.3 LTS laufen, nicht rückwärtskompatibel sein; Änderungen am Wire-Format weiter nur mit Protokollversion
- Render Pipelines im Scope: URP und HDRP (kein Built-in)
- Plattform der Nodes: Windows x64, Scripting-Backend Mono, D3D11/D3D12; Multicast im Netz erlaubt
- Backlog und Entscheidungen: `MIGRATION_PROGRESS.md` (Repo-Root)

## Befehle
- Kompilieren: `.claude/skills/unity-compile-check/scripts/check_compile.sh [projektpfad]`
- EditMode-Tests: `.claude/skills/unity-compile-check/scripts/run_tests.sh [projektpfad] EditMode`
- Unity-Pfad: über `UNITY_PATH` setzen, sonst wird er aus der ProjectVersion abgeleitet.
- Batchmode läuft nicht, solange der Editor das Projekt geöffnet hat (`Temp/UnityLockfile`).

## Harte Regeln
1. Eine Aufgabe aus `MIGRATION_PROGRESS.md` pro Session/Commit. Danach Compile-Check + Tests, Ergebnis im Backlog eintragen.
2. Obsolete-APIs ersetzen, nicht mit `#pragma warning disable` verstecken.
3. Kein `async/await`, keine Coroutines und keine Task-Continuations im Frame-Sync-Pfad – dort ist die Ausführungsreihenfolge pro Frame die eigentliche Anforderung. async ist ok für I/O, Laden, Tooling.
4. Wire-Format nur zusammen mit Protokollversion ändern.
5. Keine Unity-API-Aufrufe aus Hintergrund-Threads.
6. Kein `BinaryFormatter`, keine neuen Drittanbieter-Pakete (UniTask etc.) ohne Rückfrage.

## Skills
- `migration-backlog` – Analyse und Pflege von `MIGRATION_PROGRESS.md`
- `unity-api-migration` – Obsolete-/Deprecated-APIs ersetzen
- `cluster-sync-network` – Transport, Wire-Format, Frame-Lock
- `unity-compile-check` – Kompilierung und Tests headless prüfen
