#!/usr/bin/env bash
# Starts little-cctv: MediaMTX (internal) + control.py (dashboard + control API + HLS proxy).
# Run from Terminal.app so macOS attaches the Camera/Microphone permission to it.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p recordings snapshots static

MEDIAMTX_BIN="${MEDIAMTX_BIN:-$(command -v mediamtx || echo /opt/homebrew/bin/mediamtx)}"
PORT="${PORT:-7357}"

# Bind address for the dashboard / public port:
#   - default 0.0.0.0  -> reachable from any device on your LAN (the usual CCTV case)
#   - BIND_ADDR=<ip>   -> bind one address (e.g. 127.0.0.1 for local-only)
#   - IFACE=<name>     -> bind a specific interface's IPv4 (e.g. IFACE=en0)
if [ -n "${BIND_ADDR:-}" ]; then
  :
elif [ -n "${IFACE:-}" ]; then
  BIND_ADDR="$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)"
  [ -n "$BIND_ADDR" ] || { echo "error: IFACE=$IFACE has no IPv4 address" >&2; exit 1; }
else
  BIND_ADDR="0.0.0.0"
fi

# This machine's primary LAN IP — for the printed URL only (binding may be 0.0.0.0).
PRIMARY_IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
LAN_IP="$(ipconfig getifaddr "${PRIMARY_IFACE:-en0}" 2>/dev/null || true)"
VIEW_HOST="${LAN_IP:-<this-mac-ip>}"

MTX_PID=""
cleanup() {
  [ -n "$MTX_PID" ] && kill "$MTX_PID" 2>/dev/null || true
  pkill -9 -f 'rtsp://localhost:8554/cam' 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "little-cctv starting..."
echo "  dashboard : http://${VIEW_HOST}:${PORT}/   (binding ${BIND_ADDR})"
echo "  recordings: ./recordings/   snapshots: ./snapshots/"
echo "  note      : no authentication — use on a trusted LAN. Set BIND_ADDR to restrict."
echo "  stop      : Ctrl+C"
echo

"$MEDIAMTX_BIN" ./mediamtx.yml &
MTX_PID=$!
sleep 1

BIND_ADDR="$BIND_ADDR" PORT="$PORT" UPSTREAM="127.0.0.1:8888" \
  python3 ./control.py
