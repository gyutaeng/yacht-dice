extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("RNG 재현성 (같은 시드 -> 같은 결과)")

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345

	var state_a := GameStateScript.new(2, rng_a)
	var state_b := GameStateScript.new(2, rng_b)

	state_a.start_turn()
	state_b.start_turn()
	r.expect_eq("start_turn() 직후: 아직 안 굴린 상태(has_rolled=false)", state_a.has_rolled, false)
	r.expect_eq("start_turn() 직후: 아직 안 굴린 상태(has_rolled=false)", state_b.has_rolled, false)

	state_a.roll()
	state_b.roll()
	r.expect_eq("첫 굴리기 결과 일치(같은 시드)", state_a.dice_results, state_b.dice_results)

	state_a.toggle_lock(0)
	state_b.toggle_lock(0)
	state_a.roll()
	state_b.roll()
	r.expect_eq("두 번째 굴리기(0번 고정) 결과 일치", state_a.dice_results, state_b.dice_results)

	state_a.roll()
	state_b.roll()
	r.expect_eq("세 번째 굴리기 결과 일치", state_a.dice_results, state_b.dice_results)

	var dice_before_extra := state_a.dice_results.duplicate()
	state_a.roll()  # 턴당 MAX_ROLLS_PER_TURN(3)를 다 썼으니 네 번째는 거부되어야 한다
	r.expect_eq("네 번째 굴리기는 거부되어 주사위가 그대로임", state_a.dice_results, dice_before_extra)
