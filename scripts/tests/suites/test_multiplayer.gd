extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("다인수(2~4명) 게임 진행")

	_test_turn_cycle(r, 2)
	_test_turn_cycle(r, 3)
	_test_turn_cycle(r, 4)
	_test_single_player_completion_does_not_end_game(r)
	_test_game_ended_only_when_all_complete(r)
	_test_tied_winners(r)
	_test_solo_winner(r)
	_test_invalid_player_count_rejected(r)
	_test_bonus_is_per_player_independent(r)


func _test_turn_cycle(r, player_count: int) -> void:
	var gs := GameStateScript.new(player_count)
	gs.start_turn()

	var sequence: Array[int] = []
	for k in player_count * 2:
		sequence.append(gs.current_player)
		gs.roll()  # 이제 확정 전에 실제로 굴려야 has_rolled 가드를 통과한다
		gs.confirm_category(k)  # k < 2*player_count <= 8, 12개 항목 안에서 전부 서로 다른 칸

	var expected: Array[int] = []
	for k in player_count * 2:
		expected.append(k % player_count)

	r.expect_eq("%d인: 턴이 0->1->...->0으로 정확히 순환" % player_count, sequence, expected)


func _test_single_player_completion_does_not_end_game(r) -> void:
	var gs := GameStateScript.new(4)
	gs.start_turn()

	# player0의 11칸을 미리 확정된 상태로 세팅하고, 마지막 한 칸만 실제 confirm_category로 확정한다.
	for i in range(GameStateScript.CATEGORY_NAMES.size() - 1):
		gs.player_score_confirmed[0][i] = true
		gs.player_confirmed_scores[0][i] = 1
	gs.roll()
	gs.confirm_category(GameStateScript.CATEGORY_NAMES.size() - 1)

	r.expect_eq("4인: player0만 12칸을 다 채워도 game_over는 false", gs.game_over, false)
	r.expect_eq("4인: player0 완주 후 턴은 player1로 넘어감", gs.current_player, 1)


func _test_game_ended_only_when_all_complete(r) -> void:
	var gs := GameStateScript.new(2)
	gs.start_turn()

	var emit_count := [0]
	var handler := func(_winners, _scores): emit_count[0] += 1
	GameEvents.game_ended.connect(handler)

	# player0만 완주 (아직 player1은 미확정) -> game_ended가 아직 emit되면 안 된다.
	for i in range(GameStateScript.CATEGORY_NAMES.size() - 1):
		gs.player_score_confirmed[0][i] = true
	gs.roll()
	gs.confirm_category(GameStateScript.CATEGORY_NAMES.size() - 1)

	r.expect_eq("player0만 완주: game_ended emit 횟수", emit_count[0], 0)
	r.expect_eq("player0만 완주: game_over는 false", gs.game_over, false)
	r.expect_eq("턴은 player1로 넘어감", gs.current_player, 1)

	# 이제 player1도 마저 완주시킨다 -> 그 순간에만 game_ended가 emit되어야 한다.
	for i in range(GameStateScript.CATEGORY_NAMES.size() - 1):
		gs.player_score_confirmed[1][i] = true
	gs.roll()
	gs.confirm_category(GameStateScript.CATEGORY_NAMES.size() - 1)

	r.expect_eq("둘 다 완주: game_ended emit 횟수", emit_count[0], 1)
	r.expect_eq("둘 다 완주: game_over는 true", gs.game_over, true)

	GameEvents.game_ended.disconnect(handler)


func _test_tied_winners(r) -> void:
	var gs := GameStateScript.new(3)
	gs.player_confirmed_scores[0][6] = 50  # Choice
	gs.player_confirmed_scores[1][6] = 50
	gs.player_confirmed_scores[2][6] = 30

	r.expect_eq("3명 중 2명 공동 최고점 -> winners에 둘 다 포함", gs.get_winners(), [0, 1])


func _test_solo_winner(r) -> void:
	var gs := GameStateScript.new(3)
	gs.player_confirmed_scores[0][6] = 50
	gs.player_confirmed_scores[1][6] = 30
	gs.player_confirmed_scores[2][6] = 10

	var winners := gs.get_winners()
	r.expect_eq("단독 1위: winners 길이는 1", winners.size(), 1)
	r.expect_eq("단독 1위: winners 내용", winners, [0])


func _test_invalid_player_count_rejected(r) -> void:
	var gs_one := GameStateScript.new(1)
	r.expect_eq("인원수 1 요청 -> 거부되고 기본값 2", gs_one.player_count, 2)

	var gs_five := GameStateScript.new(5)
	r.expect_eq("인원수 5 요청 -> 거부되고 기본값 2", gs_five.player_count, 2)


func _test_bonus_is_per_player_independent(r) -> void:
	var gs := GameStateScript.new(2)
	gs.player_confirmed_scores[0] = [3, 6, 9, 12, 15, 18, 0, 0, 0, 0, 0, 0]  # 상단 합 63
	for i in 6:
		gs.player_score_confirmed[0][i] = true
	# player1은 아무것도 확정하지 않은 상태로 둔다.

	r.expect_eq("player0는 보너스 달성", gs.has_upper_bonus(0), true)
	r.expect_eq("player1은 영향 없이 보너스 미달성", gs.has_upper_bonus(1), false)
	r.expect_eq("player1 총점은 그대로 0", gs.get_player_total(1), 0)
