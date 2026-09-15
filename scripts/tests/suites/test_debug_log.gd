extends RefCounted

# DEBUG_MODE를 켜둔 채로 게임을 여러 판 계속 돌리면(1-8 웹 테스트처럼) 화면
# 좌상단 진단 로그(DebugInitLog)가 무한히 자라던 문제의 회귀 테스트. 최근
# DEBUG_LOG_MAX_LINES(30)줄만 남고, 새 게임을 시작하면 이전 판의 로그가
# 비워지는지 확인한다.


func run(r) -> void:
	r.begin_suite("Main 디버그 로그 상한")

	# test_runner가 아직 자기 자신의 _ready() 안에 있어서 get_tree().root가
	# "자식 설정 중"으로 잡혀있다 - 한 프레임 기다려야 add_child()가 통과한다.
	await Engine.get_main_loop().process_frame

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame

	for i in main.DEBUG_LOG_MAX_LINES + 10:
		main._debug_init_log("테스트 줄 %d" % i)
	r.expect_eq("최근 DEBUG_LOG_MAX_LINES줄만 남음", main._debug_log_lines.size(), main.DEBUG_LOG_MAX_LINES)
	r.expect_true("가장 오래된 줄은 밀려나 사라짐", not main._debug_log_lines[0].contains("테스트 줄 0"))

	var fallback := CharacterLibrary.get_builtin_fallback()
	var profiles: Array[CharacterProfile] = [fallback, fallback]
	main._start_new_game(profiles)
	r.expect_true("새 게임을 시작하면 이전 판 로그는 비워지고 새 로그만 남음", main._debug_log_lines.size() < main.DEBUG_LOG_MAX_LINES)
	for line in main._debug_log_lines:
		r.expect_true("남은 줄에 이전 판의 테스트 줄이 섞여있지 않음", not line.contains("테스트 줄"))

	main.get_parent().remove_child(main)
	main.free()
