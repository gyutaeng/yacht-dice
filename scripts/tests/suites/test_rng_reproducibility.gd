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
	r.expect_eq("start_turn() 직후 주사위 일치", state_a.dice_results, state_b.dice_results)

	state_a.toggle_lock(0)
	state_b.toggle_lock(0)
	state_a.roll()
	state_b.roll()
	r.expect_eq("roll #1(0번 고정) 결과 일치", state_a.dice_results, state_b.dice_results)

	state_a.roll()
	state_b.roll()
	r.expect_eq("roll #2 결과 일치", state_a.dice_results, state_b.dice_results)
