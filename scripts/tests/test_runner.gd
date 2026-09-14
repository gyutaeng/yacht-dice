extends Node

# godot --headless res://scripts/tests/test_runner.tscn 로 실행.
# --script 방식은 오토로드(GameEvents)를 등록하지 않아서 GameState를 참조하는
# 스크립트가 아예 컴파일되지 않는다. 반드시 씬으로 실행해야 한다.
#
# 새 테스트 스위트를 추가하려면 scripts/tests/suites/ 아래에
# `func run(r) -> void:` 하나를 갖는 스크립트를 만들고 SUITES 배열에 preload로 추가한다.

const TestReporterScript = preload("res://scripts/tests/test_reporter.gd")

const SUITES := [
	preload("res://scripts/tests/suites/test_initial_state.gd"),
	preload("res://scripts/tests/suites/test_scoring.gd"),
	preload("res://scripts/tests/suites/test_bonus.gd"),
	preload("res://scripts/tests/suites/test_rng_reproducibility.gd"),
	preload("res://scripts/tests/suites/test_multiplayer.gd"),
	preload("res://scripts/tests/suites/test_special_hands.gd"),
	preload("res://scripts/tests/suites/test_voice_bank.gd"),
]


func _ready() -> void:
	var reporter := TestReporterScript.new()

	for suite_script in SUITES:
		var suite = suite_script.new()
		suite.run(reporter)

	var ok := reporter.print_summary()
	get_tree().quit(0 if ok else 1)
