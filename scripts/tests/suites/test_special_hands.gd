extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("특수 족보 연출 판정 (special_hand_rolled)")

	_test_yacht_wins_over_four_of_a_kind(r)
	_test_large_straight(r)
	_test_full_house(r)
	_test_four_of_a_kind_only(r)
	_test_confirmed_category_falls_through(r)
	_test_no_duplicate_same_rank_in_turn(r)
	_test_upgrade_reemits_in_same_turn(r)
	_test_downgrade_does_not_reemit(r)
	_test_nothing_special_emits_nothing(r)
	_test_new_turn_resets_shown_rank(r)


# 강제로 원하는 주사위 값을 굴린 것처럼 만든다: 다섯 개를 전부 고정해 두고
# dice_results를 미리 덮어쓴 뒤 roll()을 부르면, _roll_unlocked_dice()가 고정된
# 주사위는 건드리지 않아서 값이 그대로 유지된 채로 진짜 roll() 경로(및 그 안의
# special_hand emit 로직)를 탄다.
func _force_roll(gs: GameState, dice: Array[int]) -> void:
	for i in 5:
		gs.dice_results[i] = dice[i]
		if not gs.dice_locked[i]:
			gs.toggle_lock(i)
	gs.roll()


func _test_yacht_wins_over_four_of_a_kind(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [6, 6, 6, 6, 6])  # 야추이자 포카드 -> 더 높은 우선순위인 야추만 떠야 함

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("야추=포카드 동시 성립: emit 횟수 1", events.size(), 1)
	if events.size() == 1:
		r.expect_eq("야추가 포카드보다 우선", events[0][1], GameStateScript.YACHT_CATEGORY_INDEX)
		r.expect_eq("야추 점수 50", events[0][2], 50)


func _test_large_straight(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [1, 2, 3, 4, 5])

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("라지 스트레이트: emit 횟수 1", events.size(), 1)
	if events.size() == 1:
		r.expect_eq("라지 스트레이트 카테고리", events[0][1], GameStateScript.LARGE_STRAIGHT_CATEGORY_INDEX)
		r.expect_eq("라지 스트레이트 점수 30", events[0][2], 30)


func _test_full_house(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [3, 3, 3, 5, 5])

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("풀 하우스: emit 횟수 1", events.size(), 1)
	if events.size() == 1:
		r.expect_eq("풀 하우스 카테고리", events[0][1], GameStateScript.FULL_HOUSE_CATEGORY_INDEX)
		r.expect_eq("풀 하우스 점수 25", events[0][2], 25)


func _test_four_of_a_kind_only(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [2, 2, 2, 2, 5])

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("포카드만 성립: emit 횟수 1", events.size(), 1)
	if events.size() == 1:
		r.expect_eq("포카드 카테고리", events[0][1], GameStateScript.FOUR_OF_A_KIND_CATEGORY_INDEX)
		r.expect_eq("포카드 점수(합계) 13", events[0][2], 13)


func _test_confirmed_category_falls_through(r) -> void:
	var gs := GameStateScript.new()
	gs.player_score_confirmed[0][GameStateScript.YACHT_CATEGORY_INDEX] = true  # 이미 야추를 써버린 상태
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [6, 6, 6, 6, 6])  # 야추 칸은 막혀 있으니 포카드로 폴스루되어야 함

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("야추 칸 확정 후: emit 횟수 1", events.size(), 1)
	if events.size() == 1:
		r.expect_eq("야추 칸이 막혀 있으면 포카드로 폴스루", events[0][1], GameStateScript.FOUR_OF_A_KIND_CATEGORY_INDEX)
		r.expect_eq("포카드 점수(합계) 30", events[0][2], 30)


func _test_no_duplicate_same_rank_in_turn(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [3, 3, 3, 5, 5])  # 풀 하우스, 1회차
	_force_roll(gs, [3, 3, 3, 5, 5])  # 같은 턴에 리롤해도 여전히 풀 하우스

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("같은 턴, 같은 족보 재굴림: 재emit 안 됨(총 1회)", events.size(), 1)


func _test_upgrade_reemits_in_same_turn(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [3, 3, 3, 5, 5])  # 풀 하우스
	_force_roll(gs, [6, 6, 6, 6, 6])  # 같은 턴에 더 높은 야추로 업그레이드 -> 다시 떠야 함

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("같은 턴, 상위 족보로 업그레이드: emit 2회", events.size(), 2)
	if events.size() == 2:
		r.expect_eq("두 번째 emit은 풀 하우스", events[0][1], GameStateScript.FULL_HOUSE_CATEGORY_INDEX)
		r.expect_eq("두 번째 emit은 야추", events[1][1], GameStateScript.YACHT_CATEGORY_INDEX)


func _test_downgrade_does_not_reemit(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [6, 6, 6, 6, 6])  # 야추
	_force_roll(gs, [2, 2, 2, 2, 5])  # 같은 턴에 포카드로 내려감 -> 다시 뜨면 안 됨

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("같은 턴, 하위 족보로 다운그레이드: 재emit 안 됨(총 1회)", events.size(), 1)


func _test_nothing_special_emits_nothing(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [1, 2, 2, 3, 4])  # 아무 족보도 성립하지 않음

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("아무 족보도 없으면 emit 없음", events.size(), 0)


func _test_new_turn_resets_shown_rank(r) -> void:
	var gs := GameStateScript.new()
	gs.start_turn()

	var events := []
	var handler := func(player, category, points): events.append([player, category, points])
	GameEvents.special_hand_rolled.connect(handler)

	_force_roll(gs, [6, 6, 6, 6, 6])  # 1턴에서 야추

	gs.start_turn()  # 새 턴 시작 -> 이번 턴엔 아직 아무것도 안 보여준 상태로 리셋되어야 함
	_force_roll(gs, [6, 6, 6, 6, 6])  # 2턴에서 다시 야추 -> 다시 떠야 함

	GameEvents.special_hand_rolled.disconnect(handler)

	r.expect_eq("새 턴에서는 같은 족보도 다시 emit됨(총 2회)", events.size(), 2)
