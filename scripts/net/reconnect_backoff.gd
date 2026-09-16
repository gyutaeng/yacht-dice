class_name ReconnectBackoff
extends RefCounted

# 2-6(연결 끊김/재접속, docs/multiplayer.md §6) - 지수 백오프로 재시도
# 간격을 계산하는 순수 로직. 첫 접속(배포 환경이 무료 플랜이라 유휴 시
# 서버가 잠들고 깨어나는 데 최대 1분 걸림)과 게임 도중 재접속 양쪽에서
# 이 클래스 하나만 재사용한다(온라인 화면이 두 흐름에 각자 다른 재시도
# 로직을 새로 만들지 않도록).

const BASE_DELAY_SEC := 1.0
const MAX_DELAY_SEC := 16.0

var attempt := 0


## 다음에 기다릴 시간(초)을 돌려주고 시도 횟수를 하나 올린다 - 1, 2, 4, 8,
## 16, 16, ...으로 늘다가 MAX_DELAY_SEC에서 멈춘다.
func next_delay_sec() -> float:
	var delay: float = min(BASE_DELAY_SEC * pow(2.0, attempt), MAX_DELAY_SEC)
	attempt += 1
	return delay


func has_attempts_left() -> bool:
	return attempt < NetProtocol.MAX_RECONNECT_ATTEMPTS


func reset() -> void:
	attempt = 0
