#!/usr/bin/env bash
# Führt Unity-Tests im Batchmode aus und fasst das Ergebnis zusammen.
# Nutzung: run_tests.sh [projektpfad] [EditMode|PlayMode]
# Exit: 0 alle grün | 1 Fehlschläge | 2 Setup-Problem | 3 Editor offen
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_resolve_unity.sh"

PROJECT="$(cd "${1:-${UNITY_PROJECT_PATH:-.}}" && pwd)"
PLATFORM="${2:-EditMode}"
UNITY="$(resolve_unity "$PROJECT")" || exit 2
check_lock "$PROJECT" || exit 3

OUT="$PROJECT/Logs/claude"; mkdir -p "$OUT"
RES="$OUT/${PLATFORM,,}-results.xml"; LOG="$OUT/${PLATFORM,,}-tests.log"
rm -f "$RES"

# Kein -quit: -runTests beendet Unity selbst.
"$UNITY" -batchmode -nographics -projectPath "$PROJECT" -runTests \
  -testPlatform "$PLATFORM" -testResults "$RES" -logFile "$LOG"
code=$?

if [[ ! -f "$RES" ]]; then
  echo "Keine Testergebnisse ($RES). Vermutlich Compile-Fehler – check_compile.sh ausführen. Log: $LOG"
  exit 2
fi
head=$(grep -o -m1 '<test-run[^>]*>' "$RES")
attr() { printf '%s' "$head" | grep -oE " $1=\"[^\"]*\"" | cut -d'"' -f2; }
echo "$PLATFORM: total=$(attr total) passed=$(attr passed) failed=$(attr failed) skipped=$(attr skipped)"
if [[ "$(attr failed)" != "0" ]]; then
  echo "---- fehlgeschlagen ----"
  grep -oE '<test-case [^>]*result="Failed"[^>]*>' "$RES" | grep -oE 'fullname="[^"]*"' | cut -d'"' -f2 | head -n 20
  exit 1
fi
if (( code == 139 )) && [[ "$(attr total)" != "0" ]]; then
  # Bekannt (siehe MIGRATION_PROGRESS.md): Unity stürzt in ~1 von 3 ClusterSyncTests-Läufen beim BEENDEN ab (Segfault),
  # nachdem die Ergebnisse vollständig geschrieben wurden und keine Tests fehlgeschlagen sind.
  echo "Warnung: Unity-Exitcode 139 (Segfault beim Beenden) nach vollständigen, grünen Ergebnissen – ignoriert."
  exit 0
fi
(( code == 0 )) || { echo "Unity-Exitcode $code"; exit 1; }
exit 0
