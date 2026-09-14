extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("초기 상태(굴리기 전) 회귀 테스트")

	# GameState.new() 직후, start_turn()을 아직 한 번도 안 부른 "날것" 상태.
	var gs := GameStateScript.new()

	r.expect_true("생성 직후: has_rolled == false", not gs.has_rolled)

	for i in GameStateScript.CATEGORY_NAMES.size():
		var score: int = gs.preview_score(i)
		r.expect_eq(
			"start_turn() 전: %s 미리보기는 0점이어야 함" % GameStateScript.CATEGORY_NAMES[i],
			score,
			0
		)

	gs.confirm_category(0)
	r.expect_eq("start_turn() 전: confirm_category는 거부되어야 함(Aces 미확정 유지)", gs.player_score_confirmed[0][0], false)

	# 실제 게임이 쓰는 초기화 순서: new() 직후 바로 start_turn().
	# start_turn()은 더 이상 자동으로 굴리지 않는다 — 플레이어가 직접
	# [주사위 굴리기]를 눌러야 첫 결과가 나온다.
	var gs2 := GameStateScript.new()
	gs2.start_turn()

	r.expect_true("start_turn() 후: has_rolled == false(자동으로 안 굴림)", not gs2.has_rolled)
	r.expect_eq("start_turn() 후: 남은 굴리기는 MAX_ROLLS_PER_TURN", gs2.rolls_left, GameStateScript.MAX_ROLLS_PER_TURN)

	for i in GameStateScript.CATEGORY_NAMES.size():
		r.expect_eq(
			"start_turn() 후, 굴리기 전: %s 미리보기는 여전히 0점" % GameStateScript.CATEGORY_NAMES[i],
			gs2.preview_score(i),
			0
		)

	gs2.confirm_category(0)
	r.expect_eq("start_turn() 후, 굴리기 전: confirm_category는 거부됨", gs2.player_score_confirmed[0][0], false)

	# 플레이어가 직접 [주사위 굴리기]를 눌러야 실제 값이 나온다.
	gs2.roll()

	r.expect_true("roll() 후: has_rolled == true", gs2.has_rolled)
	r.expect_eq("roll() 후: 남은 굴리기가 1 줄어듦", gs2.rolls_left, GameStateScript.MAX_ROLLS_PER_TURN - 1)

	var all_in_range := true
	for value in gs2.dice_results:
		if value < 1 or value > 6:
			all_in_range = false

	r.expect_eq("roll() 후: 주사위가 5개", gs2.dice_results.size(), 5)
	r.expect_true("roll() 후: 주사위 5개가 전부 1~6 범위", all_in_range)

	gs2.confirm_category(0)
	r.expect_true("roll() 후: confirm_category가 정상적으로 확정됨", gs2.player_score_confirmed[0][0])
