#!/usr/bin/env bash
# Listet Obsolete-Warnungen aus dem letzten Compile-Log, gruppiert nach Datei.
# Nutzung: list_obsolete.sh [projektpfad]   (vorher check_compile.sh ausführen)
set -uo pipefail
PROJECT="$(cd "${1:-${UNITY_PROJECT_PATH:-.}}" && pwd)"
LOG="$PROJECT/Logs/claude/compile.log"
[[ -f "$LOG" ]] || { echo "Kein Log. Erst check_compile.sh ausführen." >&2; exit 2; }
grep -E '(warning|error) CS06(18|19)' "$LOG" | sed -E 's/^[[:space:]]+//' | sort -u \
  | awk -F'\\(' '{f=$1; cnt[f]++; lines[f]=lines[f] "\n    " $0} END {for (f in cnt) printf "%3d  %s%s\n", cnt[f], f, lines[f]}' \
  | sort -rn
