extends Node

# godot --headless res://scripts/tests/test_game_state_rng.tscn 로 실행.
# 같은 시드를 준 두 GameState가 같은 순서로 굴렸을 때 항상 같은 결과를 내는지 확인한다.
# (온라인 멀티플레이에서 서버 시드만으로 클라이언트가 결과를 재현할 수 있어야 하기 때문)
#
# GameState가 GameEvents(autoload) 시그널을 emit하므로, 오토로드가 등록되지 않는
# `godot --script <path>` 단독 실행 방식으로는 돌릴 수 없다(오토로드는 프로젝트를
# 정식으로 부팅할 때만 등록된다). 그래서 이 테스트는 SceneTree 스크립트가 아니라,
# 씬으로 만들어 `godot --headless <씬 경로>`로 실행하는 방식을 쓴다.
#
# class_name(GameState) 전역 캐시는 에디터를 한 번 연 뒤에만 채워지므로, 에디터 없이
# CLI에서 바로 돌려도 동작하도록 스크립트를 preload해서 직접 참조한다.
const GameStateScript = preload("res://scripts/game_state.gd")


func _ready() -> void:
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

	get_tree().quit(0 if ok else 1)


func _check(step: String, a: Array, b: Array) -> bool:
	if a == b:
		print("  [%s] 일치: %s" % [step, str(a)])
		return true
	printerr("  [%s] 불일치: a=%s b=%s" % [step, str(a), str(b)])
	return false
