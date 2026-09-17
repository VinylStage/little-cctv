#!/usr/bin/env bash
# Capture Kiyo Pro video + ONE selected microphone, scale to the selected resolution,
# hardware-encode (VideoToolbox) and publish to MediaMTX over RTSP.
#
# One avfoundation input carries video (Kiyo Pro) + the chosen audio device
# (-i "VIDEO:AUDIO"), so there is a single capture clock — no amerge of two live
# devices. The chosen mic is encoded to stereo (both channels), selectable live from
# the dashboard. Settings come from settings.env; defaults apply when it is absent.
set -euo pipefail
cd "$(dirname "$0")"

RES_H=1080
FPS=30
AUDIO_DEV=cam          # cam | mac
VIDEO_IDX=0
CAM_AUDIO_IDX=0
MAC_AUDIO_IDX=1
[ -f settings.env ] && . ./settings.env

case "$AUDIO_DEV" in
  mac) AIDX="$MAC_AUDIO_IDX" ;;
  *)   AIDX="$CAM_AUDIO_IDX" ;;
esac

RTSP_URL="rtsp://localhost:${RTSP_PORT:-8554}/${MTX_PATH:-cam}"

case "$RES_H" in
  1080) VB=6000 ;;
  720)  VB=3000 ;;
  540)  VB=1800 ;;
  360)  VB=1000 ;;
  *)    RES_H=1080; VB=6000 ;;
esac
[ "$FPS" = "60" ] || FPS=30
[ "$FPS" = "60" ] && VB=$(( VB * 16 / 10 ))
GOP=$FPS

if [ "$RES_H" = "1080" ]; then VF="format=nv12"; else VF="scale=-2:${RES_H},format=nv12"; fi

sleep 2

exec ffmpeg -hide_banner -loglevel warning \
  -thread_queue_size 1024 \
  -f avfoundation -framerate "$FPS" -video_size 1920x1080 -pixel_format nv12 \
  -i "${VIDEO_IDX}:${AIDX}" \
  -vf "$VF" \
  -map 0:v:0 -map 0:a:0 \
  -c:v h264_videotoolbox -profile:v main -realtime true -bf 0 \
  -b:v "${VB}k" -maxrate "${VB}k" -bufsize "$((VB * 2))k" -g "$GOP" -r "$FPS" \
  -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f rtsp -rtsp_transport tcp "$RTSP_URL"
