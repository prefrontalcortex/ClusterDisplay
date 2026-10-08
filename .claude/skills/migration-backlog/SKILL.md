---
name: migration-backlog
description: Analysiert das Unity-Cluster-Display-Repository (Packages, .asmdef, Abhängigkeiten, Netzwerk-/Input-/Render-Subsysteme) und erstellt oder pflegt MIGRATION_PROGRESS.md als priorisiertes Backlog atomarer Migrationsaufgaben. Verwenden zu Beginn der Modernisierung, beim Start eines neuen Meilensteins, wenn gefragt wird "was als Nächstes?", "wo stehen wir?", nach Abschluss eines Tasks zum Abhaken, oder wenn ein Task zu groß geworden ist und aufgeteilt werden muss.
---

# Migration Backlog

`MIGRATION_PROGRESS.md` im Repo-Root ist das gemeinsame Gedächtnis zwischen Sessions. Claude Code beginnt jede Session ohne Erinnerung – was nicht dort steht, ist verloren.

## Erstanalyse (nur lesen, keinen Code ändern)

1. **Inventar**: `Packages/manifest.json`, `package.json` (falls Package), alle `*.asmdef` (Referenzen, `defineConstraints`, `versionDefines`), `ProjectSettings/ProjectVersion.txt`, Player Settings → Active Input Handling, verwendete Render Pipeline.
2. **Abhängigkeitsgraph der Assemblies** aus den `.asmdef`-Referenzen ableiten und als kurze Liste/Mermaid in den Backlog schreiben. Zyklen markieren.
3. **Subsysteme lokalisieren** per Suche, nicht per Annahme:
   - Netzwerk: `using System.Net`, `UnityEngine.Networking`, `Socket`, `UdpClient`, `NetworkTransport`, `Unity.Networking.Transport`
   - Sync/Timing: `PlayerLoop`, `Time.`, `Random.state`, Wait/Barrier-Logik
   - Input: `Input.`, `UnityEngine.InputSystem`
   - Render: `OnPreRender`, `OnRenderImage`, `projectionMatrix`, `RenderPipelineManager`, `Display.`
4. **Ist-Zustand messen**: `unity-compile-check` ausführen (sofern Ziel-Unity installiert). Fehler- und Obsolete-Zahl als Baseline eintragen. Wenn kein Unity verfügbar ist, das vermerken statt Zahlen zu schätzen.
5. **Offene Fragen** an den Nutzer sammeln (Zielversion, Pipelines, Multicast erlaubt?, Rückwärtskompatibilität des Protokolls nötig?) und unter "Entscheidungen" eintragen.

## Backlog erstellen

Vorlage: `assets/MIGRATION_PROGRESS.template.md`.

Regeln für Tasks:
- **Atomar**: in einer Session machbar, ein Commit, kompiliert danach. Faustregel: wenige Dateien, ein Subsystem.
- **Reihenfolge nach Abhängigkeit, nicht nach Bequemlichkeit**: erst was das Kompilieren blockiert (entfernte APIs, fehlende Packages), dann Obsolete-Warnungen, dann Verhaltensänderungen (Transport, Input-Replikation).
- **Jeder Task hat ein prüfbares Abnahmekriterium** (z. B. "0 Fehler, Obsolete ≤ 12, Roundtrip-Tests grün") und nennt den passenden Skill.
- Hardware-only-Prüfungen als `[manuell]` kennzeichnen.

## Pflege

- Nach jedem Task: Status, Datum, Messwerte, Commit-Hash, Auffälligkeiten.
- Wird ein Task zu groß: abbrechen, Teil-Tasks anlegen, ursprünglichen Task als "aufgeteilt" markieren.
- Entscheidungen mit Begründung im Abschnitt "Entscheidungen" festhalten – das verhindert, dass spätere Sessions sie neu aufrollen.
