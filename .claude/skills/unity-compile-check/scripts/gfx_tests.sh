#!/usr/bin/env bash
# Führt Unity-Tests MIT GPU aus (kein -nographics) – nötig für Bildvergleichstests (GraphicsTestsURP/HDRP).
# Nutzung: gfx_tests.sh <projektpfad> [PlayMode|EditMode] [timeout-minuten]
# Exit: 0 alle grün | 1 Fehlschläge | 2 Setup-Problem | 3 Timeout
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_resolve_unity.sh"
PROJECT="$(cd "${1:?projektpfad}" && pwd)"; PLATFORM="${2:-PlayMode}"; MAXMIN="${3:-40}"
UNITY="$(resolve_unity "$PROJECT")" || exit 2
check_lock "$PROJECT" || exit 2
OUT="$PROJECT/Logs/claude"; mkdir -p "$OUT"; RES="$OUT/gfx-${PLATFORM,,}-results.xml"; rm -f "$RES"
timeout "${MAXMIN}m" "$UNITY" -batchmode -projectPath "$PROJECT" -runTests -testPlatform "$PLATFORM" \
  -testResults "$RES" -logFile "$OUT/gfx-${PLATFORM,,}.log"
code=$?
[[ $code == 124 ]] && { echo "Timeout nach $MAXMIN min"; exit 3; }
[[ -f "$RES" ]] || { echo "Keine Testergebnisse ($RES) – Compile-Fehler? Log: $OUT/gfx-${PLATFORM,,}.log"; exit 2; }
head=$(grep -o -m1 '<test-run[^>]*>' "$RES"); attr() { printf '%s' "$head" | grep -oE " $1=\"[^\"]*\"" | cut -d'"' -f2; }
echo "$PLATFORM (GPU): total=$(attr total) passed=$(attr passed) failed=$(attr failed) skipped=$(attr skipped)"
if [[ "$(attr failed)" != "0" ]]; then
  echo "---- fehlgeschlagen ----"
  grep -o 'test-case [^>]*result="Failed"' "$RES" | grep -o 'fullname="[^"]*"' | sed 's/fullname=//; s/&quot;/"/g' | head -40
  exit 1
fi
exit 0
