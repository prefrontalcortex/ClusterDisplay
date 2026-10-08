---
name: unity-compile-check
description: Kompiliert das Unity-Projekt headless im Batchmode und führt EditMode-/PlayMode-Tests aus, mit kompakter Auswertung von C#-Fehlern (CS-Codes), Obsolete-Warnungen und Testergebnissen. Immer verwenden nach jeder Code-Änderung an C#-Skripten, .asmdef-Dateien oder Package-Manifesten, vor jedem Commit, und wann immer gefragt wird, ob etwas kompiliert, ob Tests grün sind oder welche Obsolete-Warnungen es noch gibt – auch wenn "Unity" oder "Batchmode" nicht ausdrücklich erwähnt wird.
---

# Unity Compile Check

Unity-Builds sind langsam (oft 1–5 Minuten). Darum: gezielt aufrufen, Ausgabe der Skripte lesen statt das komplette Log, und das Ergebnis festhalten.

## Kompilieren

```bash
.claude/skills/unity-compile-check/scripts/check_compile.sh [projektpfad]
```

Exit-Codes: `0` sauber · `1` Compile-Fehler · `2` Unity nicht gefunden / Setup-Problem · `3` Projekt im Editor geöffnet (Lockfile).

Das Skript gibt eindeutige `error CS....`-Zeilen und die Anzahl der Obsolete-Warnungen (CS0618/CS0619) aus. Das volle Log liegt unter `<projekt>/Logs/claude/compile.log` – nur hineinschauen, wenn die Zusammenfassung nicht reicht (z. B. Fehler ohne CS-Code wie Package-Resolve-Probleme: dort nach `error` und `Exception` suchen).

## Obsolete-Liste nach Datei

```bash
.claude/skills/unity-compile-check/scripts/list_obsolete.sh [projektpfad]
```

Wertet das letzte Compile-Log aus; nützlich, um die nächste Datei für `unity-api-migration` auszuwählen.

## Tests

```bash
.claude/skills/unity-compile-check/scripts/run_tests.sh [projektpfad] EditMode
.claude/skills/unity-compile-check/scripts/run_tests.sh [projektpfad] PlayMode
```

`-runTests` beendet Unity selbst; nicht zusätzlich `-quit` übergeben, sonst laufen die Tests je nach Version nicht.

## Vorgehen nach einer Änderung

1. Compile-Check. Bei Fehlern: zuerst den ersten Fehler beheben – Folgefehler verschwinden oft mit.
2. Anzahl Obsolete-Warnungen mit dem vorherigen Stand vergleichen; sie darf nicht steigen.
3. EditMode-Tests, wenn Logik geändert wurde.
4. Ergebnis (Fehler 0, Warnungen vorher → nachher, Tests x/y) in `MIGRATION_PROGRESS.md` beim Task eintragen.

## Typische Stolpersteine

- **Exit 3 / "another Unity instance"**: Der Editor hat das Projekt offen. Den Nutzer bitten, ihn zu schließen; das Lockfile nicht selbst löschen, solange Unity läuft.
- **Repo ist ein Package, kein Projekt**: Es gibt kein `ProjectSettings/` im Root. Das Host-/Testprojekt aus `CLAUDE.md` als Pfad übergeben.
- **API Updater**: Beim ersten Öffnen in neuer Unity-Version schreibt Unity Code automatisch um. Vorher committen, danach den Diff des Updaters prüfen und separat committen.
- **Erster Lauf dauert lange** (Library-Import). Nicht als Hänger interpretieren.
