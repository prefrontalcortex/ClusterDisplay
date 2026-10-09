#!/usr/bin/env bash
# Baut einen Windows64-Player und beendet Unity selbst, sobald "Build Finished" im Log steht
# (Unity 6.3 blieb nach einem erfolgreichen Build schon stundenlang in einer Fehlerschleife hängen).
# Nutzung: build_player.sh <projektpfad> <ausgabeordner-relativ-zum-projekt> [timeout-minuten]
# Exit: 0 Build erfolgreich | 1 Build fehlgeschlagen | 2 Setup-Problem | 3 Timeout
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_resolve_unity.sh"
PROJECT="$(cd "${1:?projektpfad}" && pwd)"; OUT="${2:?ausgabeordner}"; MAXMIN="${3:-40}"
UNITY="$(resolve_unity "$PROJECT")" || exit 2
check_lock "$PROJECT" || exit 2
NAME="$(basename "$PROJECT")"
mkdir -p "$PROJECT/Logs/claude"; LOG="$PROJECT/Logs/claude/build.log"; rm -f "$LOG"
rm -rf "$PROJECT/$OUT"; mkdir -p "$PROJECT/$OUT"
"$UNITY" -batchmode -nographics -projectPath "$PROJECT" -buildWindows64Player "$PROJECT/$OUT/$NAME.exe" -logFile "$LOG" &
UPID=$!
for _ in $(seq 1 $((MAXMIN * 6))); do
  sleep 10
  if LC_ALL=C grep -a -q "Build Finished, Result" "$LOG" 2>/dev/null; then
    RESULT="$(LC_ALL=C grep -a -m1 "Build Finished, Result" "$LOG")"; echo "$RESULT"
    sleep 8; kill "$UPID" 2>/dev/null; taskkill //F //PID "$UPID" >/dev/null 2>&1 || true
    [[ "$RESULT" == *Success* ]] && exit 0 || exit 1
  fi
  kill -0 "$UPID" 2>/dev/null || { echo "Unity beendet ohne 'Build Finished' (siehe $LOG)"; exit 1; }
done
echo "Timeout nach $MAXMIN min"; kill "$UPID" 2>/dev/null; taskkill //F //PID "$UPID" >/dev/null 2>&1 || true; exit 3
