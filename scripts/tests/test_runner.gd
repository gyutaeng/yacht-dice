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
	preload("res://scripts/tests/suites/test_file_picker.gd"),
	preload("res://scripts/tests/suites/test_character_library.gd"),
	preload("res://scripts/tests/suites/test_character_pack.gd"),
	preload("res://scripts/tests/suites/test_character_limits.gd"),
	preload("res://scripts/tests/suites/test_asset_loader.gd"),
	preload("res://scripts/tests/suites/test_character_editor_scene.gd"),
	preload("res://scripts/tests/suites/test_debug_log.gd"),
	preload("res://scripts/tests/suites/test_game_start_builtin_only.gd"),
	preload("res://scripts/tests/suites/test_auto_confirm.gd"),
	preload("res://scripts/tests/suites/test_protocol.gd"),
	preload("res://scripts/tests/suites/test_session_store.gd"),
	preload("res://scripts/tests/suites/test_room_manager.gd"),
	preload("res://scripts/tests/suites/test_game_state_snapshot.gd"),
	preload("res://scripts/tests/suites/test_room_gameplay.gd"),
	preload("res://scripts/tests/suites/test_online_game_controller.gd"),
	preload("res://scripts/tests/suites/test_game_event_relay_classification.gd"),
	preload("res://scripts/tests/suites/test_pack_transfer_metadata.gd"),
	preload("res://scripts/tests/suites/test_pack_transfer_resolve_timeout.gd"),
]


func _ready() -> void:
	var reporter := TestReporterScript.new()

	# await로 대기하는 이유: 대부분의 스위트는 동기로 끝나지만, 씬 하나를
	# 통째로 add_child해서 실제 _ready()를 태워봐야 하는 통합 테스트(예:
	# test_game_start_builtin_only.gd)는 프레임을 기다려야 한다. run()이
	# await를 안 쓰면 이 await는 그냥 한 틱만에 통과하므로 기존 스위트에는
	# 영향이 없다.
	for suite_script in SUITES:
		var suite = suite_script.new()
		await suite.run(reporter)

	var ok := reporter.print_summary()
	get_tree().quit(0 if ok else 1)
