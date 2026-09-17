# little-cctv

Turn a USB webcam on a Mac into a simple CCTV you can watch from a browser — live view,
audio, on-demand recording, and motion snapshots — controlled from a small dashboard.
Built and tested with a **Razer Kiyo Pro**, but works with any UVC webcam.

- **Capture / encode:** `ffmpeg` (avfoundation) with hardware H.264 (VideoToolbox)
- **Media server:** `MediaMTX` — fMP4 HLS (internal) + RTSP restream
- **Control server:** `control.py` — Python standard library only, no dependencies
- **Motion detection:** `ffmpeg` scene filter → snapshots + event log
- **No authentication by design** (intended for a trusted LAN; see the warning below)

## Requirements

- macOS (Apple Silicon recommended)
- [Homebrew](https://brew.sh)
- `brew install ffmpeg mediamtx` (Python 3 ships with macOS / your toolchain)

## Quick start

Run it from **Terminal.app** so macOS attaches the Camera/Microphone permission to it.
On first launch, allow the Camera and Microphone prompts.

```
./run.sh
```

It prints the dashboard URL, e.g. `http://192.168.1.20:7357/`. Open that in a browser
on the same network. Press `Ctrl+C` to stop (it cleans up all child processes).

If your webcam is not device index 0, list your devices and set the indices (see Config):

```
ffmpeg -f avfoundation -list_devices true -i ""
```

## Dashboard

- **Resolution:** 1080 / 720 / 540 / 360
- **Framerate:** 60 / 30 (changing resolution/fps restarts capture, ~3 s reconnect)
- **Microphone:** pick one source (camera or the Mac mic); it is output to both channels.
  Changing the mic restarts capture. Click a control once to enable sound (browser autoplay policy).
- **Recording:** start / pause / stop — saved to `./recordings/` with `-c copy`
  (no re-encode; recording quality follows the live monitoring quality)
- A "camera offline" overlay appears only if the picture actually freezes (e.g. another app
  grabbed the USB camera); it clears automatically when the stream resumes.

Latency is roughly 2–4 s (standard fMP4 HLS), which is fine for monitoring.

## Motion detection

- Snapshots: `./snapshots/motion_YYYYMMDD_HHMMSS.jpg`, event log: `./motion.log`
- Reads the MediaMTX RTSP restream (never re-opens the USB camera).
- Sensitivity: `MOTION_THRESH` (default `0.05`; higher = less sensitive).

## Remote access

The dashboard, the HLS stream, and the control API are all served on **one TCP port**
(default `7357`). To watch from outside your LAN, forward that single port on your router:

```
WAN <port>  ->  <this-mac-LAN-IP>:7357   (TCP)
```

Then open `http://<your-public-IP>:<port>/`.

> ⚠️ **Security — read this before forwarding a port.**
> little-cctv has **no authentication and no TLS by design.** Anyone who can reach the port
> gets your live camera, audio, and the control API (including recording). Only expose it on a
> **trusted LAN**, and if you port-forward, **restrict access to specific source IPs on your router.**
> By default the server binds `0.0.0.0` (all interfaces). Set `BIND_ADDR` to restrict it
> (e.g. `BIND_ADDR=127.0.0.1` for local-only, or `IFACE=en0` to bind one interface).

## Configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `7357` | Dashboard / public port |
| `BIND_ADDR` | `0.0.0.0` | Bind address; set to `127.0.0.1` for local-only |
| `IFACE` | — | Bind a specific interface's IPv4 instead (e.g. `en0`) |
| `MEDIAMTX_BIN` | auto / `/opt/homebrew/bin/mediamtx` | Path to the MediaMTX binary |
| `AUDIO_DEV` | `cam` | Mic source: `cam` (camera) or `mac` (Mac mic) |
| `VIDEO_IDX` / `CAM_AUDIO_IDX` / `MAC_AUDIO_IDX` | `0` / `0` / `1` | avfoundation device indices |
| `MOTION_THRESH` | `0.05` | Motion sensitivity (higher = less sensitive) |

Resolution/framerate/mic are also set live from the dashboard and stored in `settings.env`
(git-ignored runtime state).

## How it works

```
USB webcam
  └─ ffmpeg (VideoToolbox H.264 + AAC)  →  RTSP → MediaMTX ─┬─ fMP4 HLS  (127.0.0.1:8888)
                                                            └─ RTSP restream (motion, recorder)
control.py (:7357) serves the dashboard, proxies /cam/* → MediaMTX HLS, and handles the control API.
```

| Port | Role | Exposure |
|---|---|---|
| 7357 | dashboard + HLS proxy + control API | forwarded / LAN |
| 8888 | MediaMTX HLS | 127.0.0.1 only |
| 8554 | MediaMTX RTSP (capture / motion / recorder) | 127.0.0.1 only |
| 9997 | MediaMTX API | 127.0.0.1 only |

## Tuning a Razer Kiyo Pro on macOS (optional)

Razer Synapse does not support the Kiyo Pro on macOS. Use [`kiyoctl`](https://github.com/asm0dey/kiyoctl)
to adjust exposure, white balance, focus, HDR, and field-of-view (`brew install asm0dey/tap/kiyoctl`).
For a fixed room monitor, disable continuous autofocus and set a fixed focus so it does not hunt.

## Notes

- Recordings and snapshots are not pruned automatically — clean `./recordings/` and
  `./snapshots/` yourself, or add a cron/launchd job.
- Changing resolution/framerate/mic restarts the capture, which ends any in-progress recording.

## License

MIT — see [LICENSE](LICENSE). Bundles [hls.js](https://github.com/video-dev/hls.js) (Apache-2.0)
in `static/`.
