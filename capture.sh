#!/usr/bin/env bash
# Capture Kiyo Pro video + dual audio, scale to the selected resolution, hardware-encode
# (VideoToolbox) and publish to MediaMTX over RTSP.
#
# Resolution/FPS are read from settings.env (written live by the dashboard); defaults apply
# when it is absent. Video is always captured at native 1080p and scaled down, so 540/360
# (non-native modes) work too. Audio is always published as stereo (L=camera, R=MacBook mic);
# the browser dashboard selects which channel(s) to listen to — no re-encode needed here.
set -euo pipefail
cd "$(dirname "$0")"

RES_H=1080
FPS=30
AUDIO_MODE=dual
VIDEO_IDX=0
CAM_AUDIO_IDX=0
MAC_AUDIO_IDX=1
[ -f settings.env ] && . ./settings.env

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

if [ "$RES_H" = "1080" ]; then SCALE=""; else SCALE="scale=-2:${RES_H},"; fi
VF_V="[0:v]${SCALE}format=nv12[v]"

sleep 2

if [ "$AUDIO_MODE" = "single" ]; then
  INPUTS=(-f avfoundation -framerate "$FPS" -video_size 1920x1080 -pixel_format nv12 -i "${VIDEO_IDX}:${CAM_AUDIO_IDX}")
  FILTER="${VF_V};[0:a]aresample=async=1000[a]"
else
  INPUTS=(-f avfoundation -framerate "$FPS" -video_size 1920x1080 -pixel_format nv12 -i "${VIDEO_IDX}:${CAM_AUDIO_IDX}"
          -f avfoundation -i ":${MAC_AUDIO_IDX}")
  FILTER="${VF_V};[0:a]pan=mono|c0=c0[cam];[1:a]pan=mono|c0=c0[mac];[cam][mac]amerge=inputs=2,aresample=async=1000[a]"
fi

exec ffmpeg -hide_banner -loglevel warning \
  "${INPUTS[@]}" \
  -filter_complex "$FILTER" \
  -map "[v]" -map "[a]" \
  -c:v h264_videotoolbox -profile:v main -realtime true \
  -b:v "${VB}k" -maxrate "${VB}k" -bufsize "$((VB * 2))k" -g "$GOP" -r "$FPS" \
  -c:a aac -b:a 128k -ar 48000 -ac 2 \
  -f rtsp -rtsp_transport tcp "$RTSP_URL"
