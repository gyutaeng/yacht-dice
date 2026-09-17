# 2-7(Render 상시 배포) - `docs/deployment_checklist.md` "2-7 사전 조사"의
# 방식 (A)를 따른다: 프로젝트 소스 + Godot 엔진 바이너리를 이미지에 같이
# 넣는다. 실행은 `docker-entrypoint.sh`(CMD, 맨 아래)가 맡는다 - Godot
# 헤드리스 서버를 내부 고정 포트(8910)에 띄우고, nginx가 Render의 공개
# 포트(PORT)를 받아 평범한 HTTP 요청엔 직접 답하고 WebSocket 업그레이드만
# Godot으로 넘긴다(헬스체크 후보 A가 "No open HTTP ports detected"로 실측
# 실패해서 후보 C로 전환 - `docs/deployment_checklist.md` "단계 5 첫 배포
# 결과"/"후보 C 설계안" 참고).
FROM debian:bookworm-slim

# Godot는 --headless로 돌아도 시작 시 그래픽/오디오 관련 공유 라이브러리를
# 찾으려 한다(실제로 못 쓰더라도 라이브러리 자체가 없으면 시작이 실패할 수
# 있음) - 그래서 X11/GL/오디오 관련 최소 런타임 라이브러리를 같이 깐다.
# nginx/gettext-base(envsubst)/bash는 헬스체크 후보 C(프록시) 구성에
# 필요하다 - docs/deployment_checklist.md "후보 C 설계안" 참고.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        unzip \
        git \
        bash \
        nginx \
        gettext-base \
        libx11-6 \
        libxcursor1 \
        libxinerama1 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libgl1 \
        libglu1-mesa \
        libasound2 \
        libpulse0 \
        fontconfig \
    && rm -rf /var/lib/apt/lists/*

# 프로젝트가 실제로 쓰는 버전과 반드시 같아야 한다(CLAUDE.md 전체가
# Godot 4.7.2 기준으로 검증됨 - 다른 버전은 임포트 결과가 달라질 수 있음).
ARG GODOT_VERSION=4.7.2-stable
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && rm /tmp/godot.zip \
    && mv "/opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot

WORKDIR /app
COPY . .

# 2-7 후속(사용자 요청) - 서버는 export 파이프라인을 안 거치므로
# addons/build_stamp(클라이언트 export 전용)가 여기까지는 안 닿는다.
# 같은 목적(로그 한 줄만으로 어느 커밋이 배포됐는지 특정)을 이미지 빌드
# 시점에 여기서 직접 채운다 - git이 실패해도(예: .git이 빠진 빌드
# 컨텍스트) 빌드 자체는 계속돼야 하므로 실패를 절대 밖으로 전파하지
# 않는다(`|| echo unknown`, `2>/dev/null`).
RUN COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"; \
    if [ "$COMMIT_HASH" != "unknown" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then \
        COMMIT_HASH="${COMMIT_HASH}-dirty"; \
    fi; \
    sed -i "s/^const BUILD_COMMIT := \".*\"\$/const BUILD_COMMIT := \"${COMMIT_HASH}\"/" build_info.gd; \
    echo "커밋 스탬프: ${COMMIT_HASH}"

# 로컬 개발 환경에는 .import 파일이 가리키는 실제 임포트 결과물
# (`.godot/imported/`)이 에디터를 오래 써온 캐시로 이미 쌓여 있어서 이
# 문제가 로컬에서는 안 보였다 - 이 이미지는 매번 깨끗한 체크아웃이라
# `.godot/`가 아예 없고, 순수 `--headless`(에디터 아님) 실행은 임포트를
# 새로 만들지 않는다(1-8 사전 작업 때 이미 겪은 패턴,
# `godot --headless --editor --quit-after N`으로 강제 임포트).
# 여기서 한 번 에디터를 헤드리스로 띄워 임포트 + 전역 class_name 스크립트
# 캐시를 이미지 레이어에 미리 구워 넣는다 - 실제 서버 실행(CMD)은
# 순수 --headless라 이 단계가 없으면 매번 위와 같은 파싱 에러로 죽는다.
RUN godot --headless --editor --quit-after 60 --path /app 2>&1 | tail -n 40; \
    test -d /app/.godot/imported

# 헬스체크 후보 C - nginx.conf.template을 nginx의 표준 설정 경로에 둔다
# (실제 nginx.conf는 컨테이너 시작 시 docker-entrypoint.sh가 PORT를
# envsubst로 채워 넣어 생성한다 - nginx는 설정 파일에서 환경변수를 직접
# 못 읽는다). 기본 nginx.conf/사이트 설정은 안 씀 - 이 템플릿 하나로 충분.
COPY nginx.conf.template /etc/nginx/nginx.conf.template
RUN chmod +x /app/docker-entrypoint.sh

# 문서화 목적일 뿐 실제 공개 포트는 PORT 환경변수(Render가 주입, nginx가
# 받음)가 결정한다 - EXPOSE 자체가 포트를 바꾸지는 않는다. Godot은 더 이상
# 공개 포트를 직접 듣지 않고 내부 고정 포트(8910, docker-entrypoint.sh
# 참고)만 쓴다.
EXPOSE 8910

# 서버는 절대 스스로 안 끝난다(Ctrl+C로만 종료 - CLAUDE.md 2-3 참고) -
# 그래서 헬스체크/타임아웃으로 종료를 유도하는 방식은 안 쓴다. 대신
# Godot/nginx 중 하나가 죽으면 docker-entrypoint.sh가 나머지도 같이
# 내리고 컨테이너 전체를 비정상 종료시킨다("프록시만 살아있고 게임
# 서버는 죽어있는" 상태가 성립하지 않게 함 - 헬스체크 후보 C 설계).
CMD ["/app/docker-entrypoint.sh"]
