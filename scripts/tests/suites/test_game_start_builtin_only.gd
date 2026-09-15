extends RefCounted

# 1-6 버그 회귀 테스트: 사용자 캐릭터가 하나도 없어서 모든 플레이어에게
# 내장 기본 캐릭터(portrait_file/thumbnail_file이 둘 다 빈 문자열)만 배정되는
# 경우에도 게임 시작이 끝까지 정상적으로 진행되는지 확인한다.
#
# 이 경로는 웹에서 처음 실행하는 사용자(user://에 아무 캐릭터도 없음)가 항상
# 겪는 조건과 정확히 같다. 개발 중인 데스크톱은 이전 세션에서 만든 테스트
# 캐릭터가 계속 남아있어서 이 경로를 우연히 한 번도 안 타봤을 수 있다 -
# 그래서 실제 CharacterLibrary.scan() 결과에 기대지 않고, 내장 기본 캐릭터만
# 직접 넘겨서 이 조건을 항상 재현한다.


func run(r) -> void:
	r.begin_suite("게임 시작 - 내장 기본 캐릭터만 있을 때(사용자 캐릭터 0개)")

	var fallback := CharacterLibrary.get_builtin_fallback()
	r.expect_true("내장 기본 캐릭터를 읽을 수 있음", fallback != null)
	if fallback == null:
		return

	r.expect_eq("내장 기본 캐릭터는 스탠딩 이미지가 없음(이 테스트의 전제)", fallback.portrait_file, "")
	r.expect_eq("내장 기본 캐릭터는 썸네일도 없음(이 테스트의 전제)", fallback.thumbnail_file, "")

	# test_runner가 아직 자기 자신의 _ready()(=이 run() 호출) 안에 있어서
	# get_tree().root가 "자식 설정 중"으로 잡혀있다 - 한 프레임 기다려야
	# add_child()가 통과한다.
	await Engine.get_main_loop().process_frame

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame  # main._ready()가 실행되어 @onready 노드들이 채워지도록 기다린다.

	var profiles: Array[CharacterProfile] = [fallback, fallback]
	main._start_new_game(profiles)

	r.expect_true("game_state가 생성됨", main.game_state != null)
	r.expect_eq("점수판 컬럼이 인원수만큼 생성됨", main.player_columns.size(), 2)
	r.expect_eq("초상화 영역 행이 인원수만큼 생성됨", main.small_tag_rows.size(), 2)
	r.expect_true("초기화가 끝까지 진행되어 굴리기 버튼이 활성화됨", not main.roll_button.disabled)
	r.expect_true("첫 턴 시작까지 끝나서 dice_results가 채워짐", main.game_state.dice_results.size() == 5)

	main.get_parent().remove_child(main)
	main.free()
