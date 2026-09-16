# little-cctv

Razer Kiyo Pro를 임시 CCTV로 쓰는 최소 구성. macOS 로컬에서 캡처·(온디맨드) 녹화하고,
외부에서 브라우저 **대시보드**로 라이브 시청 + 화질/프레임/오디오/녹화를 제어.

- 캡처/인코딩: `ffmpeg` (avfoundation) — **하드웨어 인코딩(VideoToolbox)**, 스케일링, 듀얼 마이크
- 미디어 서버: `MediaMTX` — LL-HLS (내부 전용) + RTSP 재스트림
- 제어 서버: `control.py` (Python 표준 라이브러리, 의존성 0) — 대시보드 + 컨트롤 API + HLS 프록시
- 움직임 감지: `ffmpeg` scene 필터 → 스냅샷 + 이벤트 로그
- 인증 없음 (외부 노출은 공유기에서 IP 제한 전제)

## 요구 사항

- macOS (Apple Silicon), Homebrew
- `brew install ffmpeg mediamtx`  (Python3는 시스템/pyenv 기본)

## 실행

**반드시 Terminal.app에서 실행** — macOS가 카메라/마이크 권한(TCC)을 실행한 앱에 부여함. 첫 실행 시 권한 팝업 → 허용.

```
./run.sh
```

- `run.sh`가 MediaMTX + `control.py`를 함께 띄우고, MediaMTX가 `capture.sh`(캡처)·`motion.sh`(감지)를 자동 실행.
- 중지: `Ctrl+C` (모든 하위 프로세스 정리)

## 접속 (대시보드)

- 기본적으로 **유선 LAN 인터페이스(en10)** 에 바인딩. IP는 실행 시 자동 조회(하드코딩 없음, `IFACE`로 변경).
- LAN: `http://<en10-IP>:7357/`  (예: `http://192.168.0.2:7357/`)
- 원격: `http://<공인-IP>:7357/`

HTTP라서 "주의 요함(비보안)" 표시는 정상 — 인증/TLS 없는 설계.

### 외부 접속 포트포워딩 (공유기에서 직접)

```
외부(WAN) 7357  →  유선 LAN(en10) IP : 7357   (TCP)
```

- **이 한 포트(TCP 7357)면 충분.** WebRTC 미사용이라 별도 미디어 포트 불필요.
- 라우터에서 접속 허용 IP 제한 권장 (인증 없음).

## 대시보드 기능

- **해상도**: 1080 / 720 / 540 / 360 (1080p 캡처 후 스케일)
- **프레임**: 60 / 30
  - 해상도·프레임 변경 시 캡처가 재시작되어 약 3초 재연결.
- **오디오 채널** (브라우저에서 즉시 전환, 재인코딩 없음):
  - 왼쪽 채널 마이크: 카메라 / 맥북 (택1)
  - 오른쪽 채널 마이크: 카메라 / 맥북 (택1)
  - 양쪽을 같은 마이크로 두면 그 마이크 단일(모노) 자동 처리
  - 첫 오디오 클릭 시 소리가 켜짐(브라우저 자동재생 정책)
- **녹화** (온디맨드): 녹화 / 일시정지 / 종료
  - 모니터링 스트림을 `-c copy`로 저장 → **화질은 모니터링을 그대로 따라감**(재인코딩 없음)
  - 저장 위치: `./recordings/rec_<timestamp>.mp4` (fragmented MP4, 중단돼도 재생 가능)

## 움직임 감지

- 스냅샷: `./snapshots/motion_YYYYMMDD_HHMMSS.jpg`, 이벤트 로그: `./motion.log`
- 카메라를 재오픈하지 않고 MediaMTX RTSP 재스트림을 구독.
- 민감도: `MOTION_THRESH`(기본 0.05, 높을수록 둔감).

## 설정 (환경변수)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `IFACE` | `en10` | 대시보드를 바인딩할 인터페이스(유선 LAN). IP는 실행 시 자동 조회 |
| `PORT` | `7357` | 대시보드/HLS 공개 포트 |
| `BIND_ADDR` | (en10 IP) | 바인드 주소 직접 지정(예: `127.0.0.1`, `0.0.0.0`) |
| `AUDIO_MODE` | `dual` | `dual`(카메라+맥북 스테레오) \| `single`(카메라만) |
| `MOTION_THRESH` | `0.05` | 움직임 감지 민감도 |
| `VIDEO_IDX`/`CAM_AUDIO_IDX`/`MAC_AUDIO_IDX` | `0`/`0`/`1` | avfoundation 장치 인덱스 |

- 해상도/프레임 현재값은 대시보드가 `settings.env`에 기록(런타임 상태, git 무시).
- 장치 인덱스 확인: `ffmpeg -f avfoundation -list_devices true -i ""`

## 내부 포트

| 포트 | 용도 | 노출 |
|---|---|---|
| 7357 | 대시보드 + HLS 프록시 + 컨트롤 API (control.py) | 외부 포워딩 대상 |
| 8888 | MediaMTX LL-HLS | 127.0.0.1 전용 |
| 8554 | MediaMTX RTSP (캡처·감지·녹화용) | 127.0.0.1 전용 |
| 9997 | MediaMTX API | 127.0.0.1 전용 |

## 주의

- 인증/TLS 없음. 외부 노출 시 공유기 IP 화이트리스트 필수.
- 해상도/프레임 변경은 캡처를 재시작하므로, **녹화 중이면 해당 녹화가 종료됨**.
- HDR/노출은 macOS에서 Razer 소프트로 조절 불가(Synapse는 윈도우 전용).
- 임시(하루) 용도 기준. 상시 운영이면 TLS·인증·디스크 정책 별도 검토.
