extends RefCounted

# 친구 대상 실제 베타 테스트 후속(사용자 지적) - 서버 로그에 "슬롯 0에서
# 동일한 ready 값이 연속으로 수신됨"이 실제로 찍혔다. 근본 원인은
# _on_ready_button_pressed()가 로컬 캐시(_players, 서버 echo로만 갱신됨)만
# 읽고 보내기 전에 갱신하지 않아서, 왕복 시간 안에 이 핸들러가 두 번
# 불리면(웹 브라우저의 터치+마우스 클릭 중복 이벤트 등) 둘 다 같은 값을
# 보냈던 것(online_screen.gd 참고). 이제는 보내는 즉시 로컬 캐시도
# 낙관적으로 갱신한다 - 이 테스트는 서버 왕복 없이 핸들러를 연달아 두 번
# 불러서, 두 번째 호출이 첫 번째와 다른 값을 보내는지(제대로 토글되는지)
# 확인한다.

func run(r) -> void:
	r.begin_suite("온라인 준비 버튼 - 연속 호출이 같은 값을 두 번 안 보냄")
	_test_double_press_toggles_instead_of_repeating(r)
	_test_game_ended_resets_local_ready_cache(r)


func _make_screen() -> Control:
	var scene: PackedScene = load("res://scenes/online/online_screen.tscn")
	var screen := scene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	return screen


## 서버 echo(player_ready_changed)가 오기 전에 핸들러가 연달아 두 번
## 불렸다고 가정한다(연결 안 된 GameClient라 set_ready()의 실제 전송은
## 조용히 무시되지만, 그건 이 테스트의 관심사가 아니다 - _players 로컬
## 캐시가 매 호출마다 실제로 뒤집히는지만 본다).
func _test_double_press_toggles_instead_of_repeating(r) -> void:
	var screen := _make_screen()
	screen._my_index = 0
	screen._players = {0: {"meta": {}, "ready": false}}

	screen._on_ready_button_pressed()
	var after_first: bool = screen._players[0]["ready"]
	r.expect_eq("첫 호출: false -> true", after_first, true)

	screen._on_ready_button_pressed()
	var after_second: bool = screen._players[0]["ready"]
	r.expect_eq("두 번째 호출(왕복 전에 또 불려도): true -> false, 같은 값 반복 아님", after_second, false)

	screen.get_parent().remove_child(screen)
	screen.free()


## 크래시 재현 테스트 후속(사용자 지적, 실제 로그로 확인) - 위 수정으로도
## 서버의 "동일한 ready 값이 연속으로 수신됨" 경고가 그대로 찍혔다. 진짜
## 원인은 다른 곳: 서버의 Room.begin_rematch_wait()가 게임이 끝나는
## 순간 전원의 ready를 false로 되돌리는데, 그걸 클라이언트에 알리는
## 메시지가 따로 없다 - 그래서 게임이 막 끝난 시점 로컬 _players 캐시는
## 그 판을 시작할 때의 값(항상 true)을 그대로 들고 있다가, 재대전
## 대기 화면에서 준비 버튼을 처음 누르면 "이미 true인 걸 false로" 토글한
## 값이 나가는데 서버는 이미 false라 중복이 됐다(위 수정은 "같은 클릭
## 안에서의 중복 이벤트"만 막았을 뿐, "서버와 로컬 캐시가 애초에
## 어긋나 있는 것"은 다른 문제라 안 막혔다). game_ended를 받으면 로컬
## 캐시도 서버와 같이 리셋하는지 확인한다.
func _test_game_ended_resets_local_ready_cache(r) -> void:
	var screen := _make_screen()
	screen._players = {
		0: {"meta": {}, "ready": true},
		1: {"meta": {}, "ready": true},
	}

	screen._on_game_ended([0], [150])

	r.expect_eq("game_ended 이후 슬롯 0 ready가 false로 리셋됨", screen._players[0]["ready"], false)
	r.expect_eq("game_ended 이후 슬롯 1 ready도 false로 리셋됨", screen._players[1]["ready"], false)

	screen.get_parent().remove_child(screen)
	screen.free()
