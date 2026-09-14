extends SceneTree

# godot --headless --script res://scripts/tests/test_game_state_rng.gd 로 실행.
# 같은 시드를 준 두 GameState가 같은 순서로 굴렸을 때 항상 같은 결과를 내는지 확인한다.
# (온라인 멀티플레이에서 서버 시드만으로 클라이언트가 결과를 재현할 수 있어야 하기 때문)
#
# class_name(GameState) 전역 캐시는 에디터를 한 번 연 뒤에만 채워지므로, 에디터 없이
# CLI에서 바로 돌려도 동작하도록 스크립트를 preload해서 직접 참조한다.
const GameStateScript = preload("res://scripts/game_state.gd")


func _init() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345

	var state_a := GameStateScript.new(rng_a)
	var state_b := GameStateScript.new(rng_b)

	var ok := true

	state_a.start_turn()
	state_b.start_turn()
	ok = ok and _check("start_turn", state_a.dice_results, state_b.dice_results)

	state_a.toggle_lock(0)
	state_b.toggle_lock(0)
	state_a.roll()
	state_b.roll()
	ok = ok and _check("roll #1 (0번 주사위 고정)", state_a.dice_results, state_b.dice_results)

	state_a.roll()
	state_b.roll()
	ok = ok and _check("roll #2", state_a.dice_results, state_b.dice_results)

	if ok:
		print("PASS: seed=12345로 만든 두 GameState가 같은 순서로 굴렸을 때 항상 같은 결과를 냈습니다.")
	else:
		printerr("FAIL: 같은 시드인데 결과가 달랐습니다. 위 로그를 확인하세요.")

	quit(0 if ok else 1)


func _check(step: String, a: Array, b: Array) -> bool:
	if a == b:
		print("  [%s] 일치: %s" % [step, str(a)])
		return true
	printerr("  [%s] 불일치: a=%s b=%s" % [step, str(a), str(b)])
	return false
