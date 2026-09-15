class_name GameEventRelay
extends RefCounted

# GameEvents(autoload/game_events.gd)의 시그널마다 "서버가 이벤트 메시지로
# 보내는가"를 분류해두는 단 하나의 목록(docs/multiplayer.md §2.2, 2-4C).
#
# 규칙: 게임에서 일어난 사건은 전부 전달한다. 예외는 EXCLUDED_EVENTS에 있는
# score_previewed 하나뿐이며, 이유는 빈도(한 번 굴릴 때마다 미확정 항목
# 수만큼 방출됨)와 클라이언트가 read-only GameState에서 preview_score()로
# 똑같이 다시 계산할 수 있다는 점이다(원칙 7).
#
# "지금 아무도 안 듣는다"는 여기서 제외 사유가 될 수 없다 - 오늘은 참인
# 사실이지 규칙이 아니다. die_held_changed가 정확히 이 이유로 빠져서
# 온라인에서 홀드 효과음이 안 나는 버그가 났다(2-4C). 나중에 새 연출이
# 이미 [전달됨]인 이벤트를 구독하기 시작해도 서버가 이미 보내고 있으므로
# 조용히 깨지는 일이 없다.
#
# test_game_event_relay_classification.gd가
# GameEvents.get_script().get_script_signal_list()(상속 시그널 제외, 이
# 스크립트가 직접 선언한 것만)와 이 두 목록을 대조한다 - 새 시그널을
# 추가하고 여기 안 넣으면 테스트가 바로 실패한다("나중에 사람이 기억해서
# 확인"에 기대지 않기 위함).

const RELAYED_EVENTS: Array[String] = [
	"dice_rolled",
	"die_held_changed",
	"special_hand_rolled",
	"score_committed",
	"yacht_scored",
	"zero_scored",
	"bonus_achieved",
	"turn_ended",
	"turn_started",
	"game_ended",
	"game_started",
]

# score_previewed만 예외다(위 규칙 설명 참고).
const EXCLUDED_EVENTS: Array[String] = [
	"score_previewed",
]
