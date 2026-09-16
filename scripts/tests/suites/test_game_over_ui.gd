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

	# --- 3번째 재대전 버그 회귀(사용자 요청 - "테스트가 UI를 지나가게") ---
	# get_game_over_actions()의 액션 id를 _on_game_over_action_pressed()에
	# 직접 먹여서, 실제로 화면이 바뀌고 game_over_overlay가 닫히는지까지
	# 확인한다. "leave"는 게임 상태를 완전히 정리하므로 항상 마지막에 돌린다.
	main.active_controller = online_controller
	main.game_over_overlay.visible = true
	main._on_game_over_action_pressed("rematch")
	r.expect_true("rematch 액션 - GameOverOverlay가 닫힘", not main.game_over_overlay.visible)
	r.expect_true("rematch 액션 - 캐릭터 선택 화면으로 전환됨", main.character_select_screen.visible)
	r.expect_true("rematch 액션 - 게임 화면은 가려짐", not main.game_screen.visible)

	# --- "화면 상태 대신 방 상태로 판단"(사용자 요청) ---
	# _on_online_player_left()가 game_over_overlay.visible 같은 화면
	# 상태가 아니라 game_state.game_over(서버 스냅샷을 미러링한 실제 게임
	# 데이터)로 판단하는지 확인한다. 재대전 대기 중(game_over=true)에
	# 누가 나가면 온라인 로비로 돌려보내고, 게임이 아직 진행 중이면
	# (game_over=false, 기존 2-6 시나리오) 화면을 안 바꾼다.
	# game_state는 아직 살아있다(restart/leave 전이라 안 지워짐).
	main.game_state.game_over = true
	main._show_screen(2)  # GAME - 재대전 대기 화면(게임 화면 위 오버레이) 상태를 재현.
	main._on_online_player_left(1, "left")
	r.expect_true("재대전 대기 중 이탈 - 온라인 로비 화면으로 전환됨", main.online_screen.visible)

	main.game_state.game_over = false
	main._show_screen(2)  # GAME
	main._on_online_player_left(2, "left")
	r.expect_true("게임 진행 중 이탈(기존 2-6) - 화면은 그대로 GAME", main.game_screen.visible)
	r.expect_true("게임 진행 중 이탈 - 로비로 튕기지 않음", not main.online_screen.visible)

	main.game_over_overlay.visible = true
	main._on_game_over_action_pressed("restart")
	r.expect_true("restart 액션 - GameOverOverlay가 닫힘", not main.game_over_overlay.visible)
	r.expect_true("restart 액션 - 게임 화면으로 전환됨", main.game_screen.visible)

	main.game_over_overlay.visible = true
	main._on_game_over_action_pressed("leave")
	r.expect_true("leave 액션 - GameOverOverlay가 닫힘", not main.game_over_overlay.visible)
	r.expect_true("leave 액션 - 시작 화면으로 전환됨", main.start_screen.visible)

	# --- 불변식(사용자 요청) ---
	# "_show_screen()을 어떤 화면으로 부르든, 호출 후에는 game_over_overlay가
	# 닫혀 있다"를 네 화면 전부에 대해 확인한다. reconnect_overlay도 같은
	# 종류의 구멍이라 같이 검사한다(3번째 재대전 버그 조사에서 함께 발견).
	# 나중에 화면 구성이 하나 늘어도 이 테스트가 자동으로 잡아준다.
	# Screen enum 순서(Main.gd - class_name이 없어 정수로 씀):
	# START=0, CHARACTER_SELECT=1, GAME=2, ONLINE=3.
	for screen_id in [0, 1, 2, 3]:
		main.game_over_overlay.visible = true
		main.reconnect_overlay.visible = true
		main._show_screen(screen_id)
		r.expect_true("_show_screen(%d) 후 game_over_overlay 닫힘" % screen_id, not main.game_over_overlay.visible)
		r.expect_true("_show_screen(%d) 후 reconnect_overlay 닫힘" % screen_id, not main.reconnect_overlay.visible)

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
