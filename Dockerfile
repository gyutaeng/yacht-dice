# 2-7(Render 상시 배포) - `docs/deployment_checklist.md` "2-7 사전 조사"의
# 방식 (A)를 따른다: 프로젝트 소스 + Godot 엔진 바이너리를 이미지에 같이
# 넣고, 컨테이너 시작 시 `godot --headless --path /app res://server_main.tscn`
# 으로 실행한다 - 이건 로컬에서 이미 수없이 검증된 실행 방식(`run_server.bat`
# 과 완전히 같은 커맨드라인)을 그대로 재사용하는 것이라 export 과정에서
# 생길 수 있는 새로운 변수를 늘리지 않는다.
FROM debian:bookworm-slim

# Godot는 --headless로 돌아도 시작 시 그래픽/오디오 관련 공유 라이브러리를
# 찾으려 한다(실제로 못 쓰더라도 라이브러리 자체가 없으면 시작이 실패할 수
# 있음) - 그래서 X11/GL/오디오 관련 최소 런타임 라이브러리를 같이 깐다.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        unzip \
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

# 문서화 목적일 뿐 실제 리슨 포트는 PORT 환경변수(Render가 주입)가
# 결정한다(server_main.gd::_resolve_port() 참고) - EXPOSE 자체가 포트를
# 바꾸지는 않는다.
EXPOSE 8910

# 서버는 절대 스스로 안 끝난다(Ctrl+C로만 종료 - CLAUDE.md 2-3 참고) -
# 그래서 헬스체크/타임아웃으로 종료를 유도하는 방식은 안 쓴다.
CMD ["godot", "--headless", "--path", "/app", "res://server_main.tscn"]
