#!/usr/bin/env bash
# Kompiliert ein Unity-Projekt im Batchmode und fasst C#-Fehler/Obsolete-Warnungen zusammen.
# Nutzung: check_compile.sh [projektpfad]
# Exit: 0 ok | 1 Compile-Fehler | 2 Setup-Problem | 3 Editor offen
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_resolve_unity.sh"

PROJECT="$(cd "${1:-${UNITY_PROJECT_PATH:-.}}" && pwd)"
UNITY="$(resolve_unity "$PROJECT")" || exit 2
check_lock "$PROJECT" || exit 3

LOG_DIR="$PROJECT/Logs/claude"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/compile.log"

echo "Unity:   $UNITY"
echo "Projekt: $PROJECT"
echo "Kompiliere (kann einige Minuten dauern) ..."
start=$(date +%s)
"$UNITY" -batchmode -nographics -quit -projectPath "$PROJECT" -logFile "$LOG"
code=$?
echo "Dauer: $(( $(date +%s) - start ))s, Unity-Exitcode: $code"

errors=$(grep -E 'error CS[0-9]{4}' "$LOG" | sed -E 's/^[[:space:]]+//' | sort -u)
nerr=$(printf '%s' "$errors" | grep -c . || true)
nobs=$(grep -E 'warning CS06(18|19)|error CS0619' "$LOG" | sort -u | grep -c . || true)
nwarn=$(grep -E 'warning CS[0-9]{4}' "$LOG" | sort -u | grep -c . || true)

echo "----"
echo "C#-Fehler (eindeutig):        $nerr"
echo "Obsolete (CS0618/CS0619):     $nobs"
echo "C#-Warnungen gesamt:          $nwarn"
if (( nerr > 0 )); then
  echo "---- erste Fehler ----"
  printf '%s\n' "$errors" | head -n 30
  (( nerr > 30 )) && echo "... ($nerr insgesamt, siehe $LOG)"
  exit 1
fi
if (( code != 0 )); then
  echo "Unity endete mit $code ohne CS-Fehler. Log prüfen: grep -nE 'error|Exception' \"$LOG\" | head"
  exit 1
fi
echo "OK – kompiliert ohne Fehler."
exit 0
