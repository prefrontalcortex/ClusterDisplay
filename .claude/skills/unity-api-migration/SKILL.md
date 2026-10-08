---
name: unity-api-migration
description: Ersetzt veraltete, obsolete oder entfernte Unity-APIs in C#-Code durch ihre aktuellen Entsprechungen (FindObjectsOfType, UnityEngine.Input, Camera.onPreRender, OnRenderImage, Experimental.LowLevel.PlayerLoop, UNet, WWW u. a.) und migriert Built-in-Render-Hooks nach URP/HDRP. Verwenden bei jeder Aufgabe, die Obsolete-Warnungen (CS0618/CS0619), Compile-Fehler nach einem Unity-Versionswechsel, das Input System, Render-Pipeline-Hooks oder "Code modernisieren/aufräumen" betrifft – auch wenn nur eine einzelne Datei genannt wird.
---

# Unity API Migration

Ziel ist verhaltensgleicher Code auf aktuellen APIs – kein Redesign. Wer gleichzeitig migriert und umbaut, kann Regressionen nicht mehr einer Ursache zuordnen.

## Ablauf pro Task

1. **Ausgangslage messen**: `check_compile.sh`, dann `list_obsolete.sh`. Anzahl Fehler/Warnungen notieren.
2. **Scope festlegen**: genau ein Modul oder eine Datei aus `MIGRATION_PROGRESS.md`. Andere Treffer nur notieren, nicht anfassen.
3. **Ersatz nachschlagen**: `references/api-replacements.md`. Die Compiler-Meldung ist die Wahrheitsquelle – die `[Obsolete]`-Message nennt meist den Ersatz direkt. Wenn Tabelle und Meldung sich widersprechen, gilt die Meldung.
4. **Ersetzen** mit gleicher Semantik. Achtung bei stillen Unterschieden (z. B. Sortierung bei `FindObjectsByType`, Ereigniszeitpunkt bei SRP-Callbacks) – im Commit-Text erwähnen.
5. **Prüfen**: Compile-Check. Obsolete-Zähler muss sinken, Fehler bleiben 0. Bei Logikänderung EditMode-Tests.
6. **Dokumentieren**: Task im Backlog abhaken mit vorher/nachher-Zahlen und Hinweisen auf Verhaltensänderungen.

## Was nicht zu tun ist – und warum

- **Kein `#pragma warning disable`** für Obsolete: Obsolete-Warnungen werden in späteren Versionen zu Fehlern (CS0619).
- **Coroutines nicht pauschal zu async/await umbauen.** Coroutines laufen an definierten Stellen im Frame; `await` setzt je nach Kontext später oder auf anderem Thread fort. Im Cluster-Kontext ist die Reihenfolge im Frame Teil der Korrektheit. Umbau nur für I/O, Laden, Editor-Tooling – und nie im Sync-/Kamera-/Input-Replikationspfad (siehe `cluster-sync-network`).
- **Keine neuen Packages** (UniTask, Newtonsoft etc.) ohne Rückfrage – jedes Package ist eine weitere Versionsabhängigkeit für die Nodes.
- **`#if UNITY_20XX_OR_NEWER`-Weichen nur**, wenn laut `CLAUDE.md` mehrere Unity-Versionen unterstützt werden. Sonst alten Zweig löschen.

## Input System (Sonderfall Cluster)

Im Cluster liest nur der Emitter echtes Input; Repeater bekommen dasselbe Input pro Frame übers Netz. Beim Wechsel auf `UnityEngine.InputSystem` deshalb nicht einfach `Input.GetKey` durch `Keyboard.current` ersetzen, sondern:
- an einer Stelle pro Frame einen Input-Snapshot (blittable struct) auf dem Emitter erzeugen,
- ihn über den Sync-Pfad verteilen,
- Spielcode liest nur aus dem Snapshot – auf allen Nodes gleich.
Wenn das bestehende Projekt das anders löst, zuerst die bestehende Replikation verstehen und im Backlog als eigenen Task führen.

## Render-Hooks

Built-in-Callbacks (`OnPreRender`, `OnPostRender`, `OnRenderImage`, `Camera.onPreCull`) feuern unter URP/HDRP nicht. Ersatz und Fallstricke stehen in der Referenz. Projektionsmatrix-Änderungen (Off-Axis/Tile-Projektion pro Node) möglichst direkt über `Camera.projectionMatrix` vor dem Rendern setzen statt in Pipeline-Callbacks.
