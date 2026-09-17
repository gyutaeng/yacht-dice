#!/bin/bash
# 2-7 후속(Render 포트 스캐너 소음, 사용자 요청, 2026-09-17) - 왜 이 필터가
# 존재하는가: Render의 포트 스캐너가 컨테이너 "내부"(같은 네트워크
# 네임스페이스)에서 동작한다는 게 실측으로 확인됐다(docs/deployment_checklist.md
# "정정 - 127.0.0.1 바인딩은 원인 진단이 틀렸다" 참고) - 그래서 Godot을
# 127.0.0.1 전용으로 바꿔도(외부 노출은 막았지만) 이 내부 스캐너는 여전히
# Godot의 내부 전용 포트에 평범한 HTTP 프로브를 계속 보낸다. Godot의
# WebSocket 서버는 이걸 WebSocket 핸드셰이크로 파싱하려다 실패해서
# "ERROR: Not enough response headers, got: 3, expected >= 4." 4줄짜리
# 에러 블록을 초당 1회 찍는다 - 서비스 동작 자체엔 무해하지만(헬스 응답/
# 외부 접속/nginx 경유 전부 정상으로 이미 확인됨) Render Logs를 이 소음이
# 도배해서 정작 필요한 로그([서버][연결계측], 친구 테스트 관찰 등)를
# 읽을 수 없게 만든다.
#
# 이 스크립트는 Godot의 표준출력/표준에러만 걸러서(nginx 로그는 안
# 건드림) 이 특정 블록만 지운다 - 다른 어떤 ERROR도 건드리지 않는다.
# 조용히 지우면 "계기가 거짓말하는" 것이므로(이 프로젝트가 이미 여러 번
# 겪은 함정), 몇 건을 지웠는지 5분마다 반드시 알린다 - 0건이어도 찍는다
# (억제 건수가 갑자기 0이 되거나 급증하는 것 자체가 신호이기 때문).
#
# DISABLE_PORT_SCANNER_FILTER=1로 필터를 완전히 끌 수 있다 - 이 에러
# 자체를 다시 조사해야 할 때, 원본 로그를 그대로 봐야 한다.

if [ "${DISABLE_PORT_SCANNER_FILTER:-}" = "1" ]; then
    echo "[필터] DISABLE_PORT_SCANNER_FILTER=1 - 필터가 꺼져 있습니다. Godot 로그가 원본 그대로 나갑니다."
    exec cat
fi

COUNTER_FILE=$(mktemp)
echo 0 > "$COUNTER_FILE"

# 5분마다 억제 건수를 알린다(요구사항 3/4) - 라인이 전혀 안 들어와도
# (스캐너가 조용해져도) 이 타이머는 독립적으로 계속 돈다.
(
    while true; do
        sleep 300
        COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
        echo 0 > "$COUNTER_FILE"
        echo "[필터] 포트 스캐너 프로브 에러 ${COUNT}건 억제됨 (최근 5분)"
    done
) &
REPORTER_PID=$!
trap 'kill "$REPORTER_PID" 2>/dev/null; rm -f "$COUNTER_FILE"' EXIT

# in_block=1이면 "Not enough response headers" 블록의 딸린 줄(스택
# 트레이스)을 억제하는 중이라는 뜻 - 그 블록에 안 속하는 첫 줄을 만나는
# 순간 즉시 정상 출력으로 복귀한다(요구사항 1 - 대상을 좁게).
in_block=0
while IFS= read -r line; do
    if [[ "$line" == "ERROR: Not enough response headers"* ]]; then
        in_block=1
        count=$(cat "$COUNTER_FILE")
        echo $((count + 1)) > "$COUNTER_FILE"
        continue
    fi
    if [ "$in_block" -eq 1 ]; then
        if [[ "$line" == "   at: "* ]] || [[ "$line" == "   GDScript backtrace"* ]] || [[ "$line" =~ ^[[:space:]]+\[[0-9]+\] ]]; then
            continue
        fi
        in_block=0
        # 이 줄은 블록에 안 속한다 - 억제하지 않고 아래로 그대로 흘려보낸다.
    fi
    echo "$line"
done
