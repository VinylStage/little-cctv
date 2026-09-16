#!/usr/bin/env bash
# Captures the Razer Kiyo Pro (video + audio) and publishes it to MediaMTX over RTSP.
# Launched by MediaMTX via runOnInit. Device indices come from:
#   ffmpeg -f avfoundation -list_devices true -i ""
#
# Tunables (override via environment, e.g. `RES=1280x720 FPS=30 ./run.sh`):
#   VIDEO_IDX      avfoundation VIDEO device index   (Razer Kiyo Pro)
#   CAM_AUDIO_IDX  avfoundation AUDIO device index   (Razer Kiyo Pro mic)
#   MAC_AUDIO_IDX  avfoundation AUDIO device index   (MacBook Pro Microphone)
#   AUDIO_MODE     dual = L:camera / R:macbook   |   single = camera mic only
#   RES, FPS, VBITRATE

set -euo pipefail

VIDEO_IDX="${VIDEO_IDX:-0}"
CAM_AUDIO_IDX="${CAM_AUDIO_IDX:-0}"
MAC_AUDIO_IDX="${MAC_AUDIO_IDX:-1}"
AUDIO_MODE="${AUDIO_MODE:-dual}"

RES="${RES:-1920x1080}"
FPS="${FPS:-30}"
VBITRATE="${VBITRATE:-4M}"

RTSP_URL="rtsp://localhost:${RTSP_PORT:-8554}/${MTX_PATH:-cam}"

# Give MediaMTX's RTSP listener a moment on cold start.
sleep 2

V_OPTS=(-c:v libx264 -profile:v main -preset veryfast -tune zerolatency
        -pix_fmt yuv420p -g "$((FPS * 2))"
        -b:v "$VBITRATE" -maxrate "$VBITRATE" -bufsize "$VBITRATE"
        -r "$FPS")
A_OPTS=(-c:a aac -b:a 128k -ar 48000 -ac 2)
OUT_OPTS=(-f rtsp -rtsp_transport tcp "$RTSP_URL")

if [ "$AUDIO_MODE" = "single" ]; then
  exec ffmpeg -hide_banner -loglevel warning \
    -f avfoundation -framerate "$FPS" -video_size "$RES" -pixel_format nv12 \
    -i "${VIDEO_IDX}:${CAM_AUDIO_IDX}" \
    -map 0:v -map 0:a \
    "${V_OPTS[@]}" "${A_OPTS[@]}" "${OUT_OPTS[@]}"
else
  exec ffmpeg -hide_banner -loglevel warning \
    -f avfoundation -framerate "$FPS" -video_size "$RES" -pixel_format nv12 \
    -i "${VIDEO_IDX}:${CAM_AUDIO_IDX}" \
    -f avfoundation -i ":${MAC_AUDIO_IDX}" \
    -filter_complex "[0:a]pan=mono|c0=c0[cam];[1:a]pan=mono|c0=c0[mac];[cam][mac]amerge=inputs=2[a]" \
    -map 0:v -map "[a]" \
    "${V_OPTS[@]}" "${A_OPTS[@]}" "${OUT_OPTS[@]}"
fi
