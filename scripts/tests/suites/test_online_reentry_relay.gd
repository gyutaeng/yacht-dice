extends RefCounted

# 친구 대상 실제 베타 테스트에서 발견 - 재대전([한 판 더])이든 결과 화면
# [나가기] -> 로비 -> 새 방 -> 새 게임이든, 브라우저를 새로고침하지 않은 채
# 온라인 게임에 두 번째로 들어가면 캐릭터 보이스가 두 번 재생됐다.
#
# 원인: _client(GameClient)는 세션 내내 단 하나의 인스턴스로 살아있는데,
# OnlineGameController는 게임에 진입할 때마다 새로 만들어지면서(Main.gd의
# _enter_game()) 그 _client의 turn_started 등 서버 이벤트 시그널에 매번
# 새 리스너를 추가만 하고 이전 것을 끊지 않았다(scripts/game/online_game_controller.gd).
# 그래서 두 번째 판부터 GameEvents가 중복으로 재방출됐다.
#
# 두 진입 경로(재대전/로비 재개설)는 Main.gd 안에서 서로 다른 코드를 타므로
# (재대전은 _return_to_title()을 거치지 않고, 로비 재개설은 거친다) 한쪽만
# 고치고 다른 쪽을 놓칠 수 있어 반드시 각각 별도로 검증한다.
#
# 후속 3(사용자 지적) - 처음엔 turn_started 하나만 셌는데, 문제는 12개
# 시그널 전체에서 났다(하나만 검사하면 나머지 11개 중 하나를 또 빠뜨려도
# 통과한다). 그래서 GameClient가 스스로 선언한 시그널 전부(get_script_signal_list())를
# 매 라운드 순회해서 딕셔너리로 비교한다 - 새 시그널이 추가돼도 이 목록에
# 자동으로 들어오므로 손으로 갱신할 목록이 없다.

func run(r) -> void:
	r.begin_suite("온라인 게임 재진입 시 GameEvents 릴레이 중복 연결 방지(회귀)")

	await Engine.get_main_loop().process_frame
	await _test_rematch_path_does_not_accumulate_connections(r)
	await _test_lobby_reopen_path_does_not_accumulate_connections(r)


func _make_profiles(count: int) -> Array[CharacterProfile]:
	var profiles: Array[CharacterProfile] = []
	for i in count:
		profiles.append(CharacterProfile.new())
	return profiles


func _instantiate_main() -> Node:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	return main


## client가 스스로 선언한 시그널(상속받은 Node 시그널 제외) 전부의 현재
## 연결 개수를 {시그널 이름 -> 개수} 딕셔너리로 뽑는다.
func _all_connection_counts(client: GameClient) -> Dictionary:
	var counts := {}
	for signal_info in client.get_script().get_script_signal_list():
		var sig_name: String = signal_info["name"]
		counts[sig_name] = Signal(client, sig_name).get_connections().size()
	return counts


## baseline과 다른 항목만 골라 "시그널명(1회차=X, 지금=Y)" 문자열 목록으로
## 만든다 - 실패했을 때 어느 시그널이 새는지 바로 보이게.
func _diff_counts(baseline: Dictionary, current: Dictionary) -> Array[String]:
	var diffs: Array[String] = []
	for sig_name in baseline.keys():
		var expected: int = baseline[sig_name]
		var actual: int = current.get(sig_name, 0)
		if actual != expected:
			diffs.append("%s(1회차=%d, 지금=%d)" % [sig_name, expected, actual])
	return diffs


## 재대전([한 판 더]) 경로 - Main.gd의 _start_rematch_flow()는
## _return_to_title()을 절대 거치지 않고 곧장 game_play_started를 다시
## emit한다(2-6B, online_screen.gd::confirm_rematch_character() ->
## _on_game_started()). 그래서 active_controller는 겹쳐 쓰이기만 하고,
## _enter_game()이 직접 dispose()를 부르지 않으면 이전 컨트롤러가 건
## 시그널을 정리할 기회가 아예 없었다.
func _test_rematch_path_does_not_accumulate_connections(r) -> void:
	var main := _instantiate_main()
	await Engine.get_main_loop().process_frame

	var client := GameClient.new()  # connect_to_server()를 안 불러 IDLE로 남음 - 소켓이 필요 없다.
	var baseline := {}
	for round_index in 3:
		main._on_online_game_play_started(client, 0, _make_profiles(2), false)
		await Engine.get_main_loop().process_frame
		var counts := _all_connection_counts(client)
		if round_index == 0:
			baseline = counts
			var total := 0
			for v in counts.values():
				total += v
			r.expect_true("최초 진입 - 시그널 연결이 1개 이상 생김(총 %d개)" % total, total >= 1)
		else:
			var diffs := _diff_counts(baseline, counts)
			r.expect_eq("재대전 %d회차 - 모든 시그널 연결 개수가 1회차와 동일" % (round_index + 1), diffs, [] as Array[String])

	main.get_parent().remove_child(main)
	main.free()


## 결과 화면 [나가기] -> 로비 -> 새 방 -> 새 게임 경로 - _return_to_title()을
## 거친다는 점만 재대전과 다르다. 같은 GameClient/OnlineGameController
## 조합을 쓰므로 재대전 경로와 별개로 확인해야 한다(사용자 요청 - 한쪽만
## 고치고 다른 쪽을 놓치는 사고를 잡기 위함).
func _test_lobby_reopen_path_does_not_accumulate_connections(r) -> void:
	var main := _instantiate_main()
	await Engine.get_main_loop().process_frame

	var client := GameClient.new()
	var baseline := {}
	for round_index in 3:
		main._on_online_game_play_started(client, 0, _make_profiles(2), false)
		await Engine.get_main_loop().process_frame
		var counts := _all_connection_counts(client)
		if round_index == 0:
			baseline = counts
			var total := 0
			for v in counts.values():
				total += v
			r.expect_true("최초 진입 - 시그널 연결이 1개 이상 생김(총 %d개)" % total, total >= 1)
		else:
			var diffs := _diff_counts(baseline, counts)
			r.expect_eq("로비 재개설 %d회차 - 모든 시그널 연결 개수가 1회차와 동일" % (round_index + 1), diffs, [] as Array[String])
		main._return_to_title()

	main.get_parent().remove_child(main)
	main.free()
