#!/bin/bash
# 2-7 후속(헬스체크 후보 C) - 컨테이너의 유일한 시작 프로세스(PID 1). Godot은
# HTTP에 응답 못 하므로 nginx가 공개 포트를 받아서 평범한 요청엔 직접 답하고
# WebSocket 업그레이드만 내부 Godot 서버로 넘긴다(자세한 배경은
# docs/deployment_checklist.md "단계 5 첫 배포 결과"/"후보 C 설계안" 참고).
# 이 스크립트가 두 프로세스의 포트 배정/기동 순서/동반 종료를 전부 책임진다.
set -u

INTERNAL_PORT=8910
# Render는 항상 PORT를 주입하지만, 로컬에서 -e PORT 없이 띄우는 경우를
# 대비해 기본값을 둔다 - 내부 Godot 포트(8910)와 절대 겹치면 안 된다
# (겹치면 nginx와 Godot이 같은 포트를 다투게 됨 - 로컬 검증 설계 중 실제로
# 이 실수를 한 번 했다).
PORT="${PORT:-10000}"

if [ "$PORT" = "$INTERNAL_PORT" ]; then
    echo "[entrypoint] 설정 오류: 공개 포트(PORT=$PORT)와 내부 Godot 포트($INTERNAL_PORT)가 같습니다 - 둘을 반드시 다르게 하세요."
    exit 1
fi

export PORT
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# 헬스체크 후보 C 후속(실제 배포에서 발견) - Godot이 0.0.0.0에 바인딩된
# 채로 두면 Render의 포트 스캐너가 이 내부 전용 포트까지 찾아내 평범한
# HTTP로 계속 찔러본다("Detected a new open port TCP:8910" +
# "Not enough response headers" 에러가 1초마다 반복돼 [서버][연결계측]
# 로그가 묻히고, Render가 이 포트를 트래픽 라우팅 대상으로 착각할
# 위험까지 있었다). 127.0.0.1로 바인딩해서 같은 컨테이너 안의 nginx만
# 접속 가능하게 하고 외부(Render 스캐너 포함)에서는 아예 안 보이게 한다 -
# 외부에 노출되는 것은 nginx뿐이어야 한다.
#
# 후속 - 127.0.0.1 바인딩으로도 스캐너 소음 자체는 안 없어졌다(스캐너가
# 컨테이너 내부에서 동작하므로 - docs/deployment_checklist.md "정정"
# 참고). docker-log-filter.sh로 Godot의 출력만 걸러서 이 특정 에러
# 블록만 지운다(nginx 로그는 안 건드림) - FIFO를 거치는 이유는 파이프로
# 바로 연결하면($!` 가 필터의 PID가 되어) Godot 자신의 PID를 못 얻어서
# 아래 준비 대기/동반 종료 로직이 깨지기 때문이다. FIFO를 쓰면 Godot을
# 평소처럼 백그라운드로 띄우고 그 PID를 그대로 얻으면서, 출력만 별도로
# 필터를 거쳐 나가게 분리할 수 있다.
echo "[entrypoint] Godot 시작 (내부 포트 $INTERNAL_PORT, 127.0.0.1 전용 - 공개 포트 $PORT는 nginx가 받음)"
GODOT_LOG_FIFO=$(mktemp -u)
mkfifo "$GODOT_LOG_FIFO"
/app/docker-log-filter.sh < "$GODOT_LOG_FIFO" &
FILTER_PID=$!

godot --headless --path /app res://server_main.tscn -- "$INTERNAL_PORT" "127.0.0.1" > "$GODOT_LOG_FIFO" 2>&1 &
GODOT_PID=$!

# nginx가 Godot보다 먼저 요청을 받으면(특히 무료 플랜이 유휴 정지에서
# 깨어날 때 실제로 이 구간이 생긴다) 그 사이 들어온 WebSocket 요청은
# 502가 된다 - Godot이 내부 포트를 실제로 열 때까지 기다렸다가 nginx를
# 띄운다. 무한정 기다리면 안 되므로 상한(30초)을 둔다.
echo "[entrypoint] Godot이 내부 포트를 열 때까지 대기 중..."
READY=0
for i in $(seq 1 30); do
    if ! kill -0 "$GODOT_PID" 2>/dev/null; then
        echo "[entrypoint] Godot이 준비되기 전에 죽었습니다 - 중단합니다."
        exit 1
    fi
    if (echo > "/dev/tcp/127.0.0.1/${INTERNAL_PORT}") 2>/dev/null; then
        READY=1
        break
    fi
    sleep 1
done
if [ "$READY" -ne 1 ]; then
    echo "[entrypoint] 30초 안에 Godot이 내부 포트를 열지 않았습니다 - 중단합니다."
    kill -TERM "$GODOT_PID" 2>/dev/null
    exit 1
fi
echo "[entrypoint] Godot 준비 완료 - nginx 시작"

nginx -g "daemon off;" &
NGINX_PID=$!

# 셋 중 하나라도 먼저 끝나면 나머지도 반드시 같이 내린다(★ 사용자 지적,
# 이 설계의 핵심) - "프록시만 살아있고 게임 서버는 죽어있는" 상태가
# 구조적으로 성립하면 안 된다. 로그 필터(FILTER_PID)도 포함한다 - 필터가
# 죽으면 Godot이 FIFO에 쓰다가 버퍼가 차서 결국 멈추므로, 필터도 다른
# 둘과 똑같이 "죽으면 전체가 죽어야 하는" 구성요소다. SIGTERM/SIGINT
# (Render가 재배포/종료 시 보냄)도 셋 다에 전달한다 - 안 그러면 "PID 1
# 문제"로 자식들이 정리 안 된 채 SIGKILL당할 수 있다.
trap 'echo "[entrypoint] 신호 수신 - 전부 종료"; kill -TERM $GODOT_PID $NGINX_PID $FILTER_PID 2>/dev/null; wait; rm -f "$GODOT_LOG_FIFO"; exit 0' TERM INT

wait -n
EXIT_CODE=$?
if ! kill -0 "$GODOT_PID" 2>/dev/null; then
    echo "[entrypoint] Godot이 먼저 종료됨(코드 $EXIT_CODE) - 나머지도 같이 내립니다"
elif ! kill -0 "$NGINX_PID" 2>/dev/null; then
    echo "[entrypoint] nginx가 먼저 종료됨(코드 $EXIT_CODE) - 나머지도 같이 내립니다"
else
    echo "[entrypoint] 로그 필터가 먼저 종료됨(코드 $EXIT_CODE) - 나머지도 같이 내립니다"
fi
kill -TERM $GODOT_PID $NGINX_PID $FILTER_PID 2>/dev/null
wait
rm -f "$GODOT_LOG_FIFO"
exit $EXIT_CODE
