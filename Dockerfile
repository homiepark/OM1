# -----------------------
# 1) Builder stage: CycloneDDS build
# -----------------------
FROM debian:bookworm-slim AS dds-builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential curl pkg-config libssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth=1 --branch releases/0.10.x https://github.com/eclipse-cyclonedds/cyclonedds

WORKDIR /build/cyclonedds/build
RUN cmake .. -DCMAKE_INSTALL_PREFIX=/opt/cyclonedds -DBUILD_EXAMPLES=OFF \
 && cmake --build . --target install

# -----------------------
# 2) App stage
# -----------------------
FROM python:3.10-slim AS app

ARG DEBIAN_FRONTEND=noninteractive

# 기본 라벨/환경
LABEL org.opencontainers.image.source="https://github.com/OpenMind/OM1"
ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_SYSTEM_PYTHON=1

# 필수 패키지 (추천: no-install-recommends)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg \
    portaudio19-dev libasound2-dev libv4l-dev \
    libasound2 libasound2-data libasound2-plugins \
    libpulse0 alsa-utils alsa-topology-conf alsa-ucm-conf pulseaudio-utils \
    iputils-ping ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# uv 바이너리 복사
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# CycloneDDS 결과물만 복사 (빌드 도구는 포함 안 됨)
COPY --from=dds-builder /opt/cyclonedds /opt/cyclonedds
ENV CYCLONEDDS_HOME=/opt/cyclonedds \
    CMAKE_PREFIX_PATH=/opt/cyclonedds

# ALSA 기본 설정 (Pulse를 기본으로)
RUN mkdir -p /etc/alsa && ln -snf /usr/share/alsa/alsa.conf.d /etc/alsa/conf.d && \
    printf '%s\n' \
      'pcm.!default { type pulse }' \
      'ctl.!default { type pulse }' \
    > /etc/asound.conf

# 비루트 유저 생성 (오디오/비디오 그룹 추가)
RUN groupadd -r app && useradd -m -r -g app -G audio,video app
USER app
WORKDIR /app/OM1

# 의존성 캐시 최적화:
# 1) 프로젝트 메타 먼저 복사 -> uv sync 캐시
#    (pyproject.toml / uv.lock 등 이름은 실제 리포와 맞춰주세요)
COPY --chown=app:app pyproject.toml ./
# 필요하다면 uv.lock 파일도 함께:
# COPY --chown=app:app uv.lock ./

# 가상환경 생성 + 의존성 설치
# - pyproject 기반이면 uv sync 사용을 권장
RUN uv venv /app/OM1/.venv && \
    . /app/OM1/.venv/bin/activate && \
    uv sync --extra dds

# 2) 나머지 소스 복사 (변경 잦은 코드)
COPY --chown=app:app . .

# 서브모듈 동기화 (필요 시)
RUN git submodule update --init --recursive

# 엔트리포인트 스크립트: 간단/안전 (네트워크 핑 제거)
# OM_API_KEY 필수 체크만 수행 (선택)
RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'set -euo pipefail' \
': "${OM_API_KEY:?OM_API_KEY is not set}"' \
'echo "Starting OM1 agent: $*"' \
'exec /app/OM1/.venv/bin/uv run src/run.py "$@"' \
> /app/entrypoint.sh && chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["spot"]

