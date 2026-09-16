#!/usr/bin/env bash
# Motion detection. Reads the RTSP restream from MediaMTX (NOT the camera directly,
# because a USB webcam can only be opened by one process on macOS) and writes a
# timestamped JPEG + a log line whenever the frame changes beyond MOTION_THRESH.
# Launched by MediaMTX via runOnReady once the camera stream is live.
#
# Tunables (environment):
#   MOTION_THRESH  scene-change score 0..1 (higher = less sensitive). Default 0.05
#   SNAP_DIR       snapshot output dir
#   MOTION_LOG     event log path

set -euo pipefail

RTSP_URL="rtsp://localhost:${RTSP_PORT:-8554}/${MTX_PATH:-cam}"
SNAP_DIR="${SNAP_DIR:-./snapshots}"
MOTION_LOG="${MOTION_LOG:-./motion.log}"
MOTION_THRESH="${MOTION_THRESH:-0.05}"

mkdir -p "$SNAP_DIR"

# Let the stream settle before subscribing.
sleep 3

exec ffmpeg -hide_banner -loglevel warning \
  -rtsp_transport tcp -i "$RTSP_URL" \
  -an \
  -vf "fps=5,scale=640:-1,select='gt(scene,${MOTION_THRESH})',metadata=print:file=${MOTION_LOG}" \
  -fps_mode vfr -f image2 -strftime 1 "${SNAP_DIR}/motion_%Y%m%d_%H%M%S.jpg"
