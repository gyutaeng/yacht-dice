extends RefCounted

# 게임 결과 화면(캐릭터 썸네일 + 순위 목록 + 리모컨 방식 버튼)을 검증한다.
# test_game_start_builtin_only.gd와 같은 방식으로 Main.tscn을 실제
# add_child해서 확인한다 - GameState.player_confirmed_scores를 직접 편집해
# 원하는 점수 구성(공동 1위 포함)을 결정적으로 만든다(get_player_total()이
# player_score_confirmed는 안 보고 순수 합산만 하므로 안전하다).

const TEST_ID_PREFIX := "test-game-over-ui-"


func run(r) -> void:
	r.begin_suite("게임 결과 화면(캐릭터 썸네일/순위/리모컨 버튼)")

	await Engine.get_main_loop().process_frame

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame

	var thumb_profile := CharacterLibrary.create_new(TEST_ID_PREFIX + "thumb")
	var plain_profile := CharacterLibrary.create_new(TEST_ID_PREFIX + "plain")
	if thumb_profile == null or plain_profile == null:
		r.expect_true("테스트 프로필 생성 성공", false)
		_cleanup(main, [thumb_profile, plain_profile])
		return

	# 썸네일 있는 캐릭터 하나(실제 CharacterPortrait 경로 확인용), 나머지는
	# 이미지 없음(실루엣 폴백 경로 확인용) - 1-3B의 그 폴백이 그대로 타는지 본다.
	thumb_profile.thumbnail_file = CharacterLibrary.save_asset_bytes(thumb_profile.id, "", "thumb.png", PackedByteArray([1, 2, 3, 4]))
	CharacterLibrary.save_profile(thumb_profile)

	var profiles: Array[CharacterProfile] = [thumb_profile, plain_profile, plain_profile, plain_profile]
	main._start_new_game(profiles)

	var gs: GameState = main.game_state
	r.expect_eq("4인 게임으로 시작됨", gs.player_count, 4)

	# 공동 1위(0,1) / 3위(2) / 4위(3)를 결정적으로 만든다. get_player_total()은
	# player_confirmed_scores 배열을 그대로 합산할 뿐이라(+ 상단 보너스),
	# 카테고리 하나에만 넣어도 충분하다 - 인덱스 6("Choice")은 하단 섹션이라
	# 상단 보너스(63점 이상 +35점) 계산에 안 걸린다(0~5가 상단).
	const SCORE_CATEGORY := 6
	gs.player_confirmed_scores[0][SCORE_CATEGORY] = 100
	gs.player_confirmed_scores[1][SCORE_CATEGORY] = 100
	gs.player_confirmed_scores[2][SCORE_CATEGORY] = 60
	gs.player_confirmed_scores[3][SCORE_CATEGORY] = 10
	main._departed_player_indices[3] = true  # 2-6으로 도중에 나간 사람 시뮬레이션.

	main._build_game_over_results_list()
	await Engine.get_main_loop().process_frame  # 썸네일 박스 resized -> TextureFit.fit()까지 기다림.

	var rows: Array = main.game_over_results_list.get_children()
	r.expect_eq("결과 행이 인원수만큼 생성됨(4인)", rows.size(), 4)

	_check_row(r, rows[0], "1위", "100점", false, "공동 1위 - 첫 번째 행")
	_check_row(r, rows[1], "1위", "100점", false, "공동 1위 - 두 번째 행")
	_check_row(r, rows[2], "3위", "60점", false, "공동 1위 다음은 3위(2위 없음)")
	_check_row(r, rows[3], "4위", "10점", true, "4위 + 도중에 나간 사람 표시")

	# 썸네일 박스 크기가 상수와 일치하는지(사용자 요청 - 96px, 상수로 관리).
	var first_thumb_box: Control = rows[0].get_child(0).get_child(0)
	r.expect_eq("썸네일 박스 크기가 RESULT_THUMBNAIL_SIZE와 일치", first_thumb_box.custom_minimum_size, Vector2(main.RESULT_THUMBNAIL_SIZE, main.RESULT_THUMBNAIL_SIZE))

	# 4인 화면이 흔한 창 높이 안에 들어오는지 확인(사용자 요청) - 게임 종료
	# 패널 전체의 최소 높이를 실측해서 720px보다 확연히 작은지 본다.
	var panel_min_height: float = main.game_over_panel.get_combined_minimum_size().y
	print("[테스트][측정] 4인 게임 결과 패널 최소 높이 = %.1fpx (RESULT_THUMBNAIL_SIZE=%.0f)" % [panel_min_height, main.RESULT_THUMBNAIL_SIZE])
	r.expect_true("4인 결과 패널 높이가 작은 창(650px)에도 들어감", panel_min_height < 650.0)

	# 리모컨 구조(사용자 지적) - 화면은 로컬/온라인을 모르고, 컨트롤러가
	# 내놓는 액션 목록 그대로 버튼을 만든다.
	main._rebuild_game_over_buttons()
	var local_buttons: Array = main.game_over_buttons_row.get_children()
	r.expect_eq("로컬은 버튼 2개", local_buttons.size(), 2)
	r.expect_eq("로컬 첫 버튼은 다시 하기", local_buttons[0].text, "다시 하기")
	r.expect_eq("로컬 둘째 버튼은 처음으로", local_buttons[1].text, "처음으로")

	var dummy_client := GameClient.new()
	var online_controller := OnlineGameController.new(dummy_client, 4, 0)
	main.active_controller = online_controller
	main._rebuild_game_over_buttons()
	var online_buttons: Array = main.game_over_buttons_row.get_children()
	r.expect_eq("온라인은 버튼 2개", online_buttons.size(), 2)
	r.expect_eq("온라인 첫 버튼은 한 판 더", online_buttons[0].text, "한 판 더")
	r.expect_eq("온라인 둘째 버튼은 나가기", online_buttons[1].text, "나가기")

	_cleanup(main, [thumb_profile, plain_profile])


func _check_row(r, row: Control, expected_rank: String, expected_score: String, expect_departed_marker: bool, context: String) -> void:
	var hbox: HBoxContainer = row.get_child(0)
	var rank_label: Label = hbox.get_child(1)
	var name_label: Label = hbox.get_child(2)
	var score_label: Label = hbox.get_child(3)

	r.expect_eq("%s - 순위 표시" % context, rank_label.text, expected_rank)
	r.expect_eq("%s - 점수 표시" % context, score_label.text, expected_score)
	r.expect_eq("%s - (나감) 표시 여부" % context, name_label.text.contains("(나감)"), expect_departed_marker)


func _cleanup(main: Node, profiles: Array) -> void:
	for profile in profiles:
		if profile != null:
			CharacterLibrary.delete(profile.id)
	main.get_parent().remove_child(main)
	main.free()
