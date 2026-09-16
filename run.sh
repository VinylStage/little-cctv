#!/usr/bin/env bash
# Starts little-cctv: MediaMTX (internal) + control.py (dashboard + control API + HLS proxy).
# Run from Terminal.app so macOS attaches the Camera/Microphone permission to it.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p recordings snapshots static

MEDIAMTX_BIN="${MEDIAMTX_BIN:-/opt/homebrew/bin/mediamtx}"
IFACE="${IFACE:-en10}"
PORT="${PORT:-7357}"
LAN_IP="$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)"
# Public bind address: the wired-LAN IP (resolved live, never hardcoded). Override with BIND_ADDR.
BIND_ADDR="${BIND_ADDR:-${LAN_IP:-0.0.0.0}}"

MTX_PID=""
cleanup() {
  [ -n "$MTX_PID" ] && kill "$MTX_PID" 2>/dev/null || true
  pkill -9 -f 'rtsp://localhost:8554/cam' 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "little-cctv starting..."
echo "  interface : $IFACE${LAN_IP:+ ($LAN_IP)}"
echo "  dashboard : http://${BIND_ADDR}:${PORT}/"
echo "  recordings: ./recordings/   snapshots: ./snapshots/"
echo "  stop      : Ctrl+C"
echo

"$MEDIAMTX_BIN" ./mediamtx.yml &
MTX_PID=$!
sleep 1

BIND_ADDR="$BIND_ADDR" PORT="$PORT" UPSTREAM="127.0.0.1:8888" MTX_API="127.0.0.1:9997" \
  python3 ./control.py
