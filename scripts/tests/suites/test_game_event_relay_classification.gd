extends RefCounted

# GameEvents(autoload/game_events.gd)에 정의된 시그널이 전부
# scripts/net/game_event_relay.gd의 RELAYED_EVENTS/EXCLUDED_EVENTS 둘 중
# 하나로 분류돼 있는지 검사한다(2-4C 재발 방지). die_held_changed가 이
# 분류에서 빠져서 온라인 홀드 효과음이 안 나는 버그가 실제로 났었다 -
# "나중에 사람이 기억해서 확인"에 기대지 않고, 새 시그널을 추가하고
# 분류를 빠뜨리면 이 테스트가 바로 실패하게 한다.
#
# GameEvents.get_signal_list()로 실제 시그널 이름을 읽어온다(리플렉션) -
# 그래서 이 테스트는 game_event_relay.gd를 고치는 게 아니라 GameEvents
# 쪽에 새 시그널이 추가될 때마다 저절로 다시 검증된다.

func run(r) -> void:
	r.begin_suite("GameEventRelay 분류 완전성")

	_test_every_signal_is_classified(r)
	_test_every_classified_name_is_a_real_signal(r)
	_test_relayed_and_excluded_do_not_overlap(r)
	_test_score_previewed_is_the_only_exclusion(r)


## get_signal_list()는 Node/Object가 물려주는 시그널(tree_entered 등)까지
## 전부 섞여 나온다 - get_script_signal_list()를 써야 game_events.gd
## 자신이 선언한 12개만 나온다(직접 실행해서 확인함).
func _actual_signal_names() -> Array[String]:
	var names: Array[String] = []
	for signal_info in GameEvents.get_script().get_script_signal_list():
		names.append(signal_info["name"])
	return names


func _test_every_signal_is_classified(r) -> void:
	var classified: Array = GameEventRelay.RELAYED_EVENTS + GameEventRelay.EXCLUDED_EVENTS
	for name in _actual_signal_names():
		r.expect_true(
			"GameEvents.%s가 RELAYED_EVENTS나 EXCLUDED_EVENTS 중 하나로 분류돼 있음" % name,
			classified.has(name)
		)


## 오타/삭제된 시그널 방지 - 목록에 있는 이름인데 실제로는 없는 시그널이면
## 그 항목이 조용히 죽은 채로 남는다(연결도 안 되고 테스트도 못 잡음).
func _test_every_classified_name_is_a_real_signal(r) -> void:
	var actual := _actual_signal_names()
	var classified: Array = GameEventRelay.RELAYED_EVENTS + GameEventRelay.EXCLUDED_EVENTS
	for name in classified:
		r.expect_true("분류 목록의 '%s'는 실제 GameEvents 시그널임" % name, actual.has(name))


func _test_relayed_and_excluded_do_not_overlap(r) -> void:
	var overlap := []
	for name in GameEventRelay.RELAYED_EVENTS:
		if GameEventRelay.EXCLUDED_EVENTS.has(name):
			overlap.append(name)
	r.expect_eq("RELAYED_EVENTS와 EXCLUDED_EVENTS는 겹치지 않음", overlap, [])


## 2-4C에서 확정한 규칙: "게임에서 일어난 사건은 전부 전달한다. 예외는
## score_previewed 하나이며, 이유는 빈도와 클라이언트 재계산 가능성이다."
func _test_score_previewed_is_the_only_exclusion(r) -> void:
	r.expect_eq("EXCLUDED_EVENTS는 score_previewed 하나뿐", GameEventRelay.EXCLUDED_EVENTS, ["score_previewed"])
