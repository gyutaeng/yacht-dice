extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("초기 상태(굴리기 전) 회귀 테스트")

	# GameState.new() 직후, start_turn()을 아직 한 번도 안 부른 "날것" 상태.
	# 예전 버그: 화면 Label은 하드코딩된 값을 보여주는데 dice_results 기본값은
	# [1,1,1,1,1]이라 Yacht가 시작하자마자 50점으로 잡혔다. 지금은 has_rolled
	# 플래그가 false인 동안 preview_score()/confirm_category()를 막아서,
	# dice_results 기본값이 무엇이든 "굴리기 전"에는 점수가 절대 안 잡힌다.
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

	# 실제 게임(Main.gd)이 쓰는 진짜 초기화 순서: new() 직후 바로 start_turn().
	var gs2 := GameStateScript.new()
	gs2.start_turn()

	r.expect_true("start_turn() 후: has_rolled == true", gs2.has_rolled)

	var all_in_range := true
	for value in gs2.dice_results:
		if value < 1 or value > 6:
			all_in_range = false

	r.expect_eq("start_turn() 후: 주사위가 5개", gs2.dice_results.size(), 5)
	r.expect_true("start_turn() 후: 주사위 5개가 전부 1~6 범위", all_in_range)

	gs2.confirm_category(0)
	r.expect_true("start_turn() 후: confirm_category가 정상적으로 확정됨", gs2.player_score_confirmed[0][0])
