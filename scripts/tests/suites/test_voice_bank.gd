extends RefCounted

# VoiceBank는 autoload라서 실제 오디오 재생/AudioStreamPlayer 배선은 이 스위트가
# 아니라 windowed 실행으로 눈/귀로 확인한다(Main.gd가 그런 것과 같은 관례).
# 여기서는 실제 파일 로딩 없이 검증 가능한 순수 판정 로직만 다룬다: 이벤트 키
# 매핑, 점수 분류 기준, 파일 선택(직전 재선택 금지), 우선순위 표 순서.


func run(r) -> void:
	r.begin_suite("VoiceBank 판정 로직")

	_test_event_key_for_category(r)
	_test_classify_score_event(r)
	_test_pick_voice_file(r)
	_test_priority_ordering(r)


func _test_event_key_for_category(r) -> void:
	r.expect_eq("야추 카테고리 -> yacht.yacht", VoiceBank.event_key_for_category(GameState.YACHT_CATEGORY_INDEX), GameEvents.Yacht.YACHT)
	r.expect_eq("라지 스트레이트 카테고리 -> yacht.large_straight", VoiceBank.event_key_for_category(GameState.LARGE_STRAIGHT_CATEGORY_INDEX), GameEvents.Yacht.LARGE_STRAIGHT)
	r.expect_eq("풀 하우스 카테고리 -> yacht.full_house", VoiceBank.event_key_for_category(GameState.FULL_HOUSE_CATEGORY_INDEX), GameEvents.Yacht.FULL_HOUSE)
	r.expect_eq("포카드 카테고리 -> yacht.four_of_a_kind", VoiceBank.event_key_for_category(GameState.FOUR_OF_A_KIND_CATEGORY_INDEX), GameEvents.Yacht.FOUR_OF_A_KIND)
	r.expect_eq("특수 족보가 아닌 카테고리(Aces)는 빈 문자열", VoiceBank.event_key_for_category(0), "")


func _test_classify_score_event(r) -> void:
	r.expect_eq("25점(경계): 큰 점수", VoiceBank.classify_score_event(25), GameEvents.Yacht.BIG_SCORE)
	r.expect_eq("50점: 큰 점수", VoiceBank.classify_score_event(50), GameEvents.Yacht.BIG_SCORE)
	r.expect_eq("24점: 큰 점수도 작은 점수도 아님", VoiceBank.classify_score_event(24), "")
	r.expect_eq("6점: 큰 점수도 작은 점수도 아님", VoiceBank.classify_score_event(6), "")
	r.expect_eq("5점(경계): 작은 점수", VoiceBank.classify_score_event(5), GameEvents.Yacht.SMALL_SCORE)
	r.expect_eq("1점: 작은 점수", VoiceBank.classify_score_event(1), GameEvents.Yacht.SMALL_SCORE)
	r.expect_eq("0점: zero_scored 전담이라 여기선 빈 문자열", VoiceBank.classify_score_event(0), "")


func _test_pick_voice_file(r) -> void:
	r.expect_eq("후보 없음 -> 빈 문자열", VoiceBank.pick_voice_file([], ""), "")
	r.expect_eq("후보 1개면 항상 그것", VoiceBank.pick_voice_file(["only.wav"], ""), "only.wav")
	r.expect_eq("후보 1개면 직전 값과 같아도 그대로", VoiceBank.pick_voice_file(["only.wav"], "only.wav"), "only.wav")

	# 후보 2개 이상이면 직전에 고른 파일이 연속으로 다시 나오지 않아야 한다.
	# 무작위라 여러 번 반복해서 매번 확인한다.
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

	# 후보가 전부 직전 값과 같은 극단적인 경우(사실상 같은 파일이 중복 등록됨)엔
	# 걸러내면 후보가 텅 비므로, 원래 목록으로 되돌아가 뭐라도 골라야 한다(무한루프/빈 문자열 금지).
	var picked_from_degenerate := VoiceBank.pick_voice_file(["x.wav", "x.wav"], "x.wav")
	r.expect_eq("모든 후보가 직전 값과 같으면 그래도 뭔가 고름", picked_from_degenerate, "x.wav")


func _test_priority_ordering(r) -> void:
	var p := VoiceBank._event_priority
	r.expect_true("승리 보이스가 주사위 굴림 보이스보다 우선순위 높음", p[GameEvents.Common.WIN] > p[GameEvents.Yacht.ROLL])
	r.expect_true("패배 보이스가 주사위 고정 보이스보다 우선순위 높음", p[GameEvents.Common.LOSE] > p[GameEvents.Yacht.HOLD])
	r.expect_true("야추가 포카드보다 우선순위 높음", p[GameEvents.Yacht.YACHT] > p[GameEvents.Yacht.FOUR_OF_A_KIND])
	r.expect_true("보너스가 작은 점수보다 우선순위 높음", p[GameEvents.Yacht.BONUS] > p[GameEvents.Yacht.SMALL_SCORE])
	r.expect_true("작은 점수가 턴 시작보다 우선순위 높음", p[GameEvents.Yacht.SMALL_SCORE] > p[GameEvents.Common.TURN_START])
	r.expect_true("턴 시작이 리롤보다 우선순위 높음", p[GameEvents.Common.TURN_START] > p[GameEvents.Yacht.REROLL])
