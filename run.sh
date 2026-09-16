#!/usr/bin/env bash
# Starts the little-cctv stack: MediaMTX + (auto-spawned) capture + motion detection.
# Run this from Terminal.app so macOS attaches the Camera/Microphone permission to it.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p recordings snapshots

MEDIAMTX_BIN="${MEDIAMTX_BIN:-/opt/homebrew/bin/mediamtx}"

# Bind the public HLS endpoint to a specific interface (default: wired LAN en10).
# No IP is hardcoded — it is resolved from the interface at launch, so a DHCP change
# is picked up on the next start. Override the interface/port with IFACE=... HLS_PORT=...
IFACE="${IFACE:-en10}"
HLS_PORT="${HLS_PORT:-7357}"
LAN_IP="$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)"

if [ -n "$LAN_IP" ]; then
  export MTX_HLSADDRESS="${LAN_IP}:${HLS_PORT}"
  VIEW_HOST="$LAN_IP"
else
  echo "warning: interface '$IFACE' has no IPv4 — HLS will listen on all interfaces." >&2
  export MTX_HLSADDRESS=":${HLS_PORT}"
  VIEW_HOST="<this-mac-ip>"
fi

echo "little-cctv starting..."
echo "  interface : $IFACE${LAN_IP:+ ($LAN_IP)}"
echo "  live view : http://${VIEW_HOST}:${HLS_PORT}/cam"
echo "  recordings: ./recordings/   snapshots: ./snapshots/   events: ./motion.log"
echo "  stop      : Ctrl+C"
echo

exec "$MEDIAMTX_BIN" ./mediamtx.yml
