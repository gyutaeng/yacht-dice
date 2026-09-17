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

echo "[entrypoint] Godot 시작 (내부 포트 $INTERNAL_PORT, 공개 포트 $PORT는 nginx가 받음)"
godot --headless --path /app res://server_main.tscn -- "$INTERNAL_PORT" &
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

# 둘 중 하나가 먼저 끝나면 나머지도 반드시 같이 내린다(★ 사용자 지적,
# 이 설계의 핵심) - "프록시만 살아있고 게임 서버는 죽어있는" 상태가
# 구조적으로 성립하면 안 된다. SIGTERM/SIGINT(Render가 재배포/종료 시
# 보냄)도 양쪽에 전달한다 - 안 그러면 "PID 1 문제"로 자식들이 정리
# 안 된 채 SIGKILL당할 수 있다.
trap 'echo "[entrypoint] 신호 수신 - 두 프로세스 모두 종료"; kill -TERM $GODOT_PID $NGINX_PID 2>/dev/null; wait; exit 0' TERM INT

wait -n
EXIT_CODE=$?
if kill -0 "$GODOT_PID" 2>/dev/null; then
    echo "[entrypoint] nginx가 먼저 종료됨(코드 $EXIT_CODE) - Godot도 같이 내립니다"
else
    echo "[entrypoint] Godot이 먼저 종료됨(코드 $EXIT_CODE) - nginx도 같이 내립니다"
fi
kill -TERM $GODOT_PID $NGINX_PID 2>/dev/null
wait
exit $EXIT_CODE
