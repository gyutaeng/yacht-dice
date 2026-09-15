extends RefCounted

# VoiceBank는 autoload라서 실제 오디오 재생/AudioStreamPlayer 배선은 이 스위트가
# 아니라 windowed 실행으로 눈/귀로 확인한다(Main.gd가 그런 것과 같은 관례).
# 여기서는 실제 파일 로딩 없이 검증 가능한 순수 판정 로직만 다룬다: 이벤트 키
# 매핑, 파일 선택(직전 재선택 금지), 승/패 플레이어 선택, 우선순위 표 순서,
# 그리고 VOICE_EVENTS 테이블이 Common/Yacht 값과 정확히 맞는지.


func run(r) -> void:
	r.begin_suite("VoiceBank 판정 로직")

	_test_voice_events_table(r)
	_test_event_key_for_category(r)
	_test_pick_voice_file(r)
	_test_pick_win_lose_players(r)
	_test_priority_ordering(r)
	_test_greeting_sequence_completes_synchronously_when_no_voices(r)
	_test_skip_greeting_when_not_active_is_noop(r)


func _test_voice_events_table(r) -> void:
	r.expect_eq("VOICE_EVENTS는 정확히 10개", GameEvents.VOICE_EVENTS.size(), 10)

	var seen_keys := {}
	var all_have_label_and_description := true
	for entry in GameEvents.VOICE_EVENTS:
		seen_keys[entry.key] = true
		if entry.label == "" or entry.description == "":
			all_have_label_and_description = false
	r.expect_true("모든 항목에 한국어 라벨/설명이 비어있지 않게 채워져 있음", all_have_label_and_description)

	var expected_keys := [
		GameEvents.Common.GAME_START, GameEvents.Common.TURN_START,
		GameEvents.Common.WIN, GameEvents.Common.LOSE,
		GameEvents.Yacht.YACHT, GameEvents.Yacht.LARGE_STRAIGHT,
		GameEvents.Yacht.FULL_HOUSE, GameEvents.Yacht.FOUR_OF_A_KIND,
		GameEvents.Yacht.BONUS, GameEvents.Yacht.ZERO,
	]
	var all_present := true
	for key in expected_keys:
		if not seen_keys.has(key):
			all_present = false
	r.expect_true("Common/Yacht의 10개 키가 전부 VOICE_EVENTS에 있음", all_present)
	r.expect_eq("VOICE_EVENTS에 예상 밖의 키가 없음", seen_keys.size(), expected_keys.size())

	# yacht.roll/reroll/hold/big_score/small_score는 보이스 테이블에서 빠져야 한다
	# (시그널 자체는 GameEvents에 남아 있지만 이 테이블엔 없어야 함).
	r.expect_true("Yacht 딕셔너리에 ROLL 키가 없음", not GameEvents.Yacht.has("ROLL"))
	r.expect_true("Yacht 딕셔너리에 REROLL 키가 없음", not GameEvents.Yacht.has("REROLL"))
	r.expect_true("Yacht 딕셔너리에 HOLD 키가 없음", not GameEvents.Yacht.has("HOLD"))
	r.expect_true("Yacht 딕셔너리에 BIG_SCORE 키가 없음", not GameEvents.Yacht.has("BIG_SCORE"))
	r.expect_true("Yacht 딕셔너리에 SMALL_SCORE 키가 없음", not GameEvents.Yacht.has("SMALL_SCORE"))


func _test_event_key_for_category(r) -> void:
	r.expect_eq("야추 카테고리 -> yacht.yacht", VoiceBank.event_key_for_category(GameState.YACHT_CATEGORY_INDEX), GameEvents.Yacht.YACHT)
	r.expect_eq("라지 스트레이트 카테고리 -> yacht.large_straight", VoiceBank.event_key_for_category(GameState.LARGE_STRAIGHT_CATEGORY_INDEX), GameEvents.Yacht.LARGE_STRAIGHT)
	r.expect_eq("풀 하우스 카테고리 -> yacht.full_house", VoiceBank.event_key_for_category(GameState.FULL_HOUSE_CATEGORY_INDEX), GameEvents.Yacht.FULL_HOUSE)
	r.expect_eq("포카드 카테고리 -> yacht.four_of_a_kind", VoiceBank.event_key_for_category(GameState.FOUR_OF_A_KIND_CATEGORY_INDEX), GameEvents.Yacht.FOUR_OF_A_KIND)
	r.expect_eq("특수 족보가 아닌 카테고리(Aces)는 빈 문자열", VoiceBank.event_key_for_category(0), "")


func _test_pick_voice_file(r) -> void:
	r.expect_eq("후보 없음 -> 빈 문자열", VoiceBank.pick_voice_file([], ""), "")
	r.expect_eq("후보 1개면 항상 그것", VoiceBank.pick_voice_file(["only.wav"], ""), "only.wav")
	r.expect_eq("후보 1개면 직전 값과 같아도 그대로", VoiceBank.pick_voice_file(["only.wav"], "only.wav"), "only.wav")

	var candidates := ["a.wav", "b.wav", "c.wav"]
	var last := "a.wav"
	var never_repeated := true
	for i in 200:
		var picked := VoiceBank.pick_voice_file(candidates, last)
		if picked == last:
			never_repeated = false
			break
		last = picked
	r.expect_true("후보 여러 개: 직전 파일이 연속으로 다시 뽑히지 않음(200회 반복)", never_repeated)

	var picked_from_degenerate := VoiceBank.pick_voice_file(["x.wav", "x.wav"], "x.wav")
	r.expect_eq("모든 후보가 직전 값과 같으면 그래도 뭔가 고름", picked_from_degenerate, "x.wav")


func _test_pick_win_lose_players(r) -> void:
	# 단독 1등, 단독 꼴등.
	var result := VoiceBank.pick_win_lose_players([0], [50, 30, 10])
	r.expect_eq("단독 1등: winner=0", result.winner, 0)
	r.expect_eq("단독 1등: 최하위(10점)인 2번이 loser", result.loser, 2)

	# 전원 동점(winners 크기 == 인원수) -> loser 없음.
	var tied_result := VoiceBank.pick_win_lose_players([0, 1, 2], [30, 30, 30])
	r.expect_eq("전원 동점: loser 없음(-1)", tied_result.loser, -1)
	r.expect_true("전원 동점이어도 winner는 셋 중 하나", [0, 1, 2].has(tied_result.winner))

	# 공동 1등(둘), 단독 꼴등 -> winner는 둘 중 하나, loser는 항상 꼴등 한 명.
	var winner_seen := {}
	for i in 100:
		var r2 := VoiceBank.pick_win_lose_players([0, 1], [50, 50, 10])
		winner_seen[r2.winner] = true
		r.expect_eq("공동 1등 상황에서도 loser는 항상 꼴등(2번)", r2.loser, 2)
	r.expect_true("공동 1등 100회 반복: 0번이 winner로 뽑힌 적 있음", winner_seen.has(0))
	r.expect_true("공동 1등 100회 반복: 1번이 winner로 뽑힌 적 있음", winner_seen.has(1))

	# 공동 꼴등(둘) -> loser는 그 둘 중 하나, winner는 항상 1등.
	var loser_seen := {}
	for i in 100:
		var r3 := VoiceBank.pick_win_lose_players([0], [50, 10, 10])
		r.expect_eq("공동 꼴등 상황에서도 winner는 항상 1등(0번)", r3.winner, 0)
		loser_seen[r3.loser] = true
	r.expect_true("공동 꼴등 100회 반복: 1번이 loser로 뽑힌 적 있음", loser_seen.has(1))
	r.expect_true("공동 꼴등 100회 반복: 2번이 loser로 뽑힌 적 있음", loser_seen.has(2))


func _test_priority_ordering(r) -> void:
	var p := VoiceBank._event_priority
	r.expect_true("승리/패배가 야추보다 우선순위 높음", p[GameEvents.Common.WIN] > p[GameEvents.Yacht.YACHT])
	r.expect_eq("승리와 패배는 같은 우선순위", p[GameEvents.Common.WIN], p[GameEvents.Common.LOSE])
	r.expect_true("야추가 나머지 특수 족보보다 우선순위 높음", p[GameEvents.Yacht.YACHT] > p[GameEvents.Yacht.FOUR_OF_A_KIND])
	r.expect_true("보너스가 야추 포기보다 우선순위 높음", p[GameEvents.Yacht.BONUS] > p[GameEvents.Yacht.ZERO])
	r.expect_true("야추 포기가 게임 시작 인사보다 우선순위 높음", p[GameEvents.Yacht.ZERO] > p[GameEvents.Common.GAME_START])
	r.expect_true("게임 시작 인사가 내 차례보다 우선순위 높음", p[GameEvents.Common.GAME_START] > p[GameEvents.Common.TURN_START])


## 1-4C: 전원이 game_start 보이스를 안 가진 경우(내장 기본 캐릭터만 있는
## 웹 첫 실행 등) play_greeting_sequence()가 await 지점을 한 번도 안 거치고
## 그 자리에서 끝까지 돌아야 한다 - Main.gd가 이 함수를 부르기 직전에 입력
## 차단을 켜놔도 화면에 아예 안 보이는 이유가 이 동기 완결성이다.
func _test_greeting_sequence_completes_synchronously_when_no_voices(r) -> void:
	var fallback := CharacterLibrary.get_builtin_fallback()
	r.expect_true("내장 기본 캐릭터는 voice_map이 비어있음(이 테스트의 전제)", fallback.voice_map.is_empty())

	var profiles: Array[CharacterProfile] = [fallback, fallback]
	VoiceBank.configure(profiles)

	# bool 지역변수를 람다에서 그냥 대입하면 GDScript 람다는 캡처를 값으로
	# 뜨기 때문에(참조가 아님) 바깥에서 안 보인다 - 배열/딕셔너리처럼 참조
	# 타입을 캡처해서 그 내용을 바꿔야 바깥에서도 보인다.
	var step_fired := [false]
	var finished_fired := [false]
	VoiceBank.greeting_step_started.connect(func(_p): step_fired[0] = true, CONNECT_ONE_SHOT)
	VoiceBank.greeting_sequence_finished.connect(func(): finished_fired[0] = true, CONNECT_ONE_SHOT)

	VoiceBank.play_greeting_sequence()  # await가 있어도 아무도 안 걸리면 여기서 이미 다 끝나야 한다.

	r.expect_true("아무도 매핑이 없으면 greeting_step_started가 한 번도 안 뜸", not step_fired[0])
	r.expect_true("호출이 끝나는 시점에 이미 greeting_sequence_finished가 발생함(동기 완결)", finished_fired[0])

	VoiceBank.configure([])  # 이 테스트가 만든 슬롯을 정리해서 다음 스위트에 영향 안 주게.


func _test_skip_greeting_when_not_active_is_noop(r) -> void:
	VoiceBank.configure([])
	var finished_fired := [false]
	VoiceBank.greeting_sequence_finished.connect(func(): finished_fired[0] = true, CONNECT_ONE_SHOT)

	VoiceBank.request_skip_greeting()  # 진행 중인 시퀀스가 없을 때 - 아무 일도 없어야 한다.

	r.expect_true("연출 중이 아닐 때 건너뛰기를 불러도 greeting_sequence_finished가 안 뜸", not finished_fired[0])
