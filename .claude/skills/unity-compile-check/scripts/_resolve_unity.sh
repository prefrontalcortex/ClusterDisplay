#!/usr/bin/env bash
# Gemeinsame Hilfsfunktion: Unity-Editor-Pfad ermitteln.
# Reihenfolge: $UNITY_PATH -> Unity Hub Standardpfade anhand ProjectVersion.txt
resolve_unity() {
  local project="$1"
  if [[ -n "${UNITY_PATH:-}" ]]; then
    [[ -x "$UNITY_PATH" || -f "$UNITY_PATH" ]] && { echo "$UNITY_PATH"; return 0; }
    echo "UNITY_PATH gesetzt, aber nicht gefunden: $UNITY_PATH" >&2; return 1
  fi
  local pv="$project/ProjectSettings/ProjectVersion.txt"
  if [[ ! -f "$pv" ]]; then
    echo "Kein $pv – ist '$project' ein Unity-Projekt (und kein Package)?" >&2; return 1
  fi
  local ver
  ver=$(grep -m1 'm_EditorVersion:' "$pv" | awk '{print $2}' | tr -d '\r')
  local c
  for c in \
    "/Applications/Unity/Hub/Editor/$ver/Unity.app/Contents/MacOS/Unity" \
    "$HOME/Unity/Hub/Editor/$ver/Editor/Unity" \
    "/c/Program Files/Unity/Hub/Editor/$ver/Editor/Unity.exe" \
    "/mnt/c/Program Files/Unity/Hub/Editor/$ver/Editor/Unity.exe" \
    "C:/Program Files/Unity/Hub/Editor/$ver/Editor/Unity.exe"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  echo "Unity $ver nicht gefunden. UNITY_PATH setzen." >&2; return 1
}

check_lock() {
  local project="$1"
  if [[ -f "$project/Temp/UnityLockfile" ]]; then
    # Auf Windows ist die Datei gesperrt, solange der Editor läuft; überall sonst Hinweis genügen lassen.
    if ! ( : >> "$project/Temp/UnityLockfile" ) 2>/dev/null || pgrep -f "projectPath.*$(basename "$project")" >/dev/null 2>&1; then
      echo "Projekt scheint im Unity Editor geöffnet zu sein (Temp/UnityLockfile). Editor schließen." >&2
      return 1
    fi
  fi
  return 0
}
