extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("상단 보너스(63점 경계)")

	# --- 63점 직전(62점): 보너스 미달성 ---
	var gs := GameStateScript.new()
	gs.player_confirmed_scores[0] = [3, 6, 9, 12, 15, 17, 0, 0, 0, 0, 0, 0]  # 합 62
	for i in 6:
		gs.player_score_confirmed[0][i] = true

	r.expect_eq("62점: 상단 합계", gs.get_upper_section_total(0), 62)
	r.expect_eq("62점(63 직전): 보너스 미달성", gs.has_upper_bonus(0), false)
	r.expect_eq("62점: 63까지 남은 점수", gs.get_upper_bonus_remaining(0), 1)
	r.expect_eq("62점: 총점에 보너스 미포함", gs.get_player_total(0), 62)

	# --- 63점 정확히(경계값): 보너스 달성 ---
	gs.player_confirmed_scores[0][5] = 18  # Sixes를 18로 올려서 합 63
	r.expect_eq("63점(경계): 상단 합계", gs.get_upper_section_total(0), 63)
	r.expect_eq("63점(경계): 보너스 달성", gs.has_upper_bonus(0), true)
	r.expect_eq("63점: 63까지 남은 점수", gs.get_upper_bonus_remaining(0), 0)
	r.expect_eq("63점: 총점에 +35 포함(63+35=98)", gs.get_player_total(0), 98)

	# --- bonus_achieved는 "처음 달성하는 순간"에만 한 번 emit ---
	var gs2 := GameStateScript.new()
	gs2.start_turn()

	var emit_count := [0]  # 람다 클로저는 값 캡처라 int 대신 Array로 감싼다.
	GameEvents.bonus_achieved.connect(func(_player_index: int) -> void:
		emit_count[0] += 1)

	gs2.player_confirmed_scores[0] = [3, 6, 9, 12, 15, 0, 0, 0, 0, 0, 0, 0]  # Sixes 빼고 45
	for i in 5:
		gs2.player_score_confirmed[0][i] = true
	gs2.dice_results = [6, 6, 6, 1, 1]
	gs2.confirm_category(5)  # Sixes 확정 -> 45+18=63, 이 순간 보너스 달성

	r.expect_eq("보너스 달성 순간 bonus_achieved 1회 emit", emit_count[0], 1)

	# 다음 턴이 player 0에게 돌아오면 이미 달성한 보너스가 재emit되지 않아야 한다.
	if gs2.current_player == 1 and not gs2.game_over:
		var p1_category := 0
		while p1_category < GameStateScript.CATEGORY_NAMES.size() and gs2.player_score_confirmed[1][p1_category]:
			p1_category += 1
		if p1_category < GameStateScript.CATEGORY_NAMES.size():
			gs2.confirm_category(p1_category)  # player 1 턴 하나 흘려보내기

	if gs2.current_player == 0 and not gs2.game_over:
		var p0_category := 0
		while p0_category < GameStateScript.CATEGORY_NAMES.size() and gs2.player_score_confirmed[0][p0_category]:
			p0_category += 1
		if p0_category < GameStateScript.CATEGORY_NAMES.size():
			gs2.confirm_category(p0_category)  # 다시 player 0 턴에서 한 번 더 확정

	r.expect_eq("이미 달성한 보너스는 재emit되지 않음", emit_count[0], 1)
