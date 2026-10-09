#!/usr/bin/env bash
# Startet einen Emitter und einen Repeater (zwei Player-Instanzen) auf diesem Rechner über Multicast.
# Beide müssen länger laufen als Handshake-/Kommunikations-Timeout (10 s/5 s), sonst ist die Synchronisation gescheitert
# (ClusterDebug.Log ist ohne CLUSTER_DISPLAY_VERBOSE_LOGGING stumm, Überleben ist das Signal).
# Nutzung: two_node_smoke.sh <player.exe> <adaptername> [sekunden=30] [multicast=224.0.1.0:25690]
# Exit: 0 beide leben nach <sekunden> und keine Exceptions | 1 Fehler
set -uo pipefail
EXE="$(readlink -f "${1:?player.exe}")"; ADAPTER="${2:?adaptername, z.B. \"Ethernet 2\"}"; SECS="${3:-30}"; MC="${4:-224.0.1.0:25690}"
NAME="$(basename "$EXE")"; SHORT="${NAME:0:25}"
LOGDIR="${TMPDIR:-/tmp}"; E="$LOGDIR/two_node_emitter.log"; R="$LOGDIR/two_node_repeater.log"; rm -f "$E" "$R"
ARGS=(-screen-fullscreen 0 -screen-width 480 -screen-height 270 -adapterName "$ADAPTER")
"$EXE" "${ARGS[@]}" -logFile "$R" -node 1 "$MC" >/dev/null 2>&1 &
sleep 2
"$EXE" "${ARGS[@]}" -logFile "$E" -emitterNode 0 1 "$MC" >/dev/null 2>&1 &
sleep "$SECS"
ALIVE=$(tasklist 2>/dev/null | grep -ci "${SHORT%.exe}")
taskkill //F //IM "$NAME" >/dev/null 2>&1
EXC=$(cat "$E" "$R" 2>/dev/null | grep -a -ciE "exception|timeout")
echo "alive=$ALIVE/2 exceptions_or_timeouts=$EXC (logs: $E, $R)"
[[ "$ALIVE" == 2 && "$EXC" == 0 ]]
