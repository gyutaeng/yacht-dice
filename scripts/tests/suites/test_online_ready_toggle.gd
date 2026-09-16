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
