# little-cctv

Razer Kiyo Pro를 임시 CCTV로 쓰는 최소 구성. macOS 로컬에서 캡처·녹화하고, 외부에서 브라우저로 라이브 시청.

- 캡처/인코딩: `ffmpeg` (avfoundation)
- 미디어 서버: `MediaMTX` — LL-HLS 라이브 재생 + 로컬 녹화
- 움직임 감지: `ffmpeg` scene 필터 → 스냅샷 + 이벤트 로그
- 인증 없음 (외부 노출은 공유기에서 IP 제한 전제)

## 요구 사항

- macOS (Apple Silicon), Homebrew
- `brew install ffmpeg mediamtx`

## 실행

**반드시 Terminal.app에서 실행** — macOS가 카메라/마이크 권한(TCC)을 실행한 앱에 부여하기 때문. 첫 실행 시 권한 팝업이 뜨면 허용.

```
./run.sh
```

- 중지: `Ctrl+C`
- MediaMTX가 `capture.sh`(캡처)와 `motion.sh`(움직임 감지)를 자동으로 띄움.

## 접속

- 기본적으로 **유선 LAN 인터페이스(en10)** 에 바인딩됨. IP는 실행 시 자동 조회 (`IFACE`로 변경 가능, IP 하드코딩 없음).
- LAN: `http://<en10-IP>:7357/cam`  (예: `http://192.168.0.2:7357/cam`)
- 원격: `http://<공인-IP>:7357/cam`

브라우저 내장 플레이어가 뜸. HTTP라서 "주의 요함(비보안)" 표시는 정상 — 인증/TLS 없는 설계.

### 외부 접속 포트포워딩 (공유기에서 직접)

```
외부(WAN) 7357  →  유선 LAN(en10) IP : 7357   (TCP)
```

- **이 한 포트(TCP 7357)면 충분.** WebRTC를 쓰지 않으므로 별도 미디어 포트 불필요.
- 라우터에서 접속 허용 IP 제한 권장 (인증 없음).

## 오디오

- 기본 `AUDIO_MODE=dual`: **왼쪽=카메라 마이크, 오른쪽=맥북 마이크** (2채널).
- 듀얼이 안 되면 `AUDIO_MODE=single`로 카메라 마이크만.
- 코덱은 AAC (HLS/브라우저 호환). 48kHz, 2ch.

## 녹화

- 위치: `./recordings/cam/` — fMP4, 1시간 세그먼트, **24시간 후 자동 삭제**.
- 상시 녹화 (움직임과 무관).
- 지난 영상 조회 API: `http://localhost:9996/list?path=cam`, 다운로드: `.../get?path=cam&start=...&duration=...&format=mp4`.

## 움직임 감지

- 스냅샷: `./snapshots/motion_YYYYMMDD_HHMMSS.jpg`
- 이벤트 로그: `./motion.log` (scene score + pts_time)
- 카메라를 재오픈하지 않고 MediaMTX RTSP 재스트림을 구독함.
- 오탐이 많으면 `MOTION_THRESH` 상향(기본 0.05), 놓치면 하향.

## 설정 변경 (환경변수)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `RES` | `1920x1080` | 해상도 (원본 Kiyo Pro 최대 1080p60) |
| `FPS` | `30` | 프레임레이트 |
| `VBITRATE` | `4M` | 영상 비트레이트 |
| `AUDIO_MODE` | `dual` | `dual` \| `single` |
| `VIDEO_IDX` / `CAM_AUDIO_IDX` / `MAC_AUDIO_IDX` | `0` / `0` / `1` | avfoundation 장치 인덱스 |
| `MOTION_THRESH` | `0.05` | 움직임 감지 민감도 (높을수록 둔감) |
| `IFACE` | `en10` | HLS를 바인딩할 인터페이스(유선 LAN). IP는 실행 시 자동 조회 |
| `HLS_PORT` | `7357` | 라이브 HLS 포트 |

장치 인덱스 확인: `ffmpeg -f avfoundation -list_devices true -i ""`

예: `RES=1280x720 AUDIO_MODE=single ./run.sh`

## 내부 포트

| 포트 | 용도 | 노출 |
|---|---|---|
| 7357 | LL-HLS 라이브 (브라우저) | 외부 포워딩 대상 |
| 8554 | RTSP (내부 캡처·모션용) | 로컬 전용 |
| 9996 | 녹화 재생 API | 로컬 전용 |
| 9997 | MediaMTX API | 로컬 전용 |

## 주의

- 인증/TLS 없음. 외부 노출 시 공유기 IP 화이트리스트 필수.
- 임시(하루) 용도 기준. 상시 운영이면 TLS·인증·디스크 정책 별도 검토.
