extends RefCounted

# 5번 버그 조사(사용자 신고) - 게임이 끝난 뒤 새로고침(F5)으로 세션 복귀를
# 시도할 때 "서버를 깨우는 중입니다"라는(Render 배포용, 콜드스타트 대비)
# 문구가 잘못 떴다 - attempt_session_resume()은 _reconnecting_after_disconnect를
# 켜지 않으므로 항상 "진짜 첫 접속"과 같은 문구로 빠졌기 때문이다. 실제
# 로컬 서버는 깨울 대상이 없어 이 문구가 실패 원인을 가렸다.
#
# 추가로 발견한 버그: 세션 복귀 시도가 재시도를 다 쓰고도 서버에 연결조차
# 못 하면(_reconnecting_after_disconnect와 달리) _resuming_session이 계속
# true로 남고 reconnect_exhausted도 안 나가서, 화면이 온라인 화면(연결
# 패널)에 마지막 메시지만 찍힌 채 조용히 멈췄다 - 사용자가 본 증상과 일치.

func run(r) -> void:
	r.begin_suite("온라인 재접속 안내 문구(세션 복귀/게임 도중/첫 접속 구분)")

	_test_label_picks_first_connection_by_default(r)
	_test_label_picks_mid_game_reconnect(r)
	_test_label_picks_session_resume(r)
	_test_label_prioritizes_mid_game_over_resume_if_both_set(r)
	await _test_exhausted_session_resume_returns_to_connect_panel(r)


func _make_screen() -> Control:
	var scene: PackedScene = load("res://scenes/online/online_screen.tscn")
	var screen := scene.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	return screen


func _test_label_picks_first_connection_by_default(r) -> void:
	var screen := _make_screen()
	r.expect_eq("아무 플래그도 없으면 '서버를 깨우는 중'(진짜 첫 접속)", screen._connection_retry_label(), "서버를 깨우는 중입니다(최대 1분)")
	screen.get_parent().remove_child(screen)
	screen.free()


func _test_label_picks_mid_game_reconnect(r) -> void:
	var screen := _make_screen()
	screen._reconnecting_after_disconnect = true
	r.expect_eq("게임 도중 끊김이면 '게임 도중 재접속 시도 중'", screen._connection_retry_label(), "게임 도중 재접속 시도 중")
	screen.get_parent().remove_child(screen)
	screen.free()


func _test_label_picks_session_resume(r) -> void:
	var screen := _make_screen()
	screen._resuming_session = true
	r.expect_eq("F5 세션 복귀 시도면 '이전 게임에 다시 연결하는 중'(로컬 서버는 깨울 대상이 없으므로 '서버를 깨우는 중'과 구분돼야 함)", screen._connection_retry_label(), "이전 게임에 다시 연결하는 중")
	screen.get_parent().remove_child(screen)
	screen.free()


## 이론상 두 플래그가 동시에 true일 일은 없지만(서로 다른 진입 경로),
## 우선순위가 정해져 있는지는 확인해둔다 - 조용히 둘 다 무시되는 경로가
## 없어야 한다.
func _test_label_prioritizes_mid_game_over_resume_if_both_set(r) -> void:
	var screen := _make_screen()
	screen._reconnecting_after_disconnect = true
	screen._resuming_session = true
	r.expect_eq("둘 다 켜져 있으면 게임 도중 재접속이 우선", screen._connection_retry_label(), "게임 도중 재접속 시도 중")
	screen.get_parent().remove_child(screen)
	screen.free()


## 세션 복귀 시도가 connect_to_server() 자체에 계속 실패해 재시도를 다
## 쓰면(서버가 응답하지 않는 상황 - 4번과 같은 근본 원인일 수 있음), 예전엔
## _resuming_session이 안 풀리고 화면도 그대로 멈췄다. ReconnectBackoff.attempt를
## 상한으로 직접 맞춰 "재시도를 이미 다 썼다"를 흉내내면 _on_connection_failed()가
## await 없이 곧장 소진 분기로 빠지므로 실제 타이머를 기다릴 필요가 없다.
func _test_exhausted_session_resume_returns_to_connect_panel(r) -> void:
	var screen := _make_screen()
	screen._resuming_session = true
	screen._reconnect_backoff.attempt = NetProtocol.MAX_RECONNECT_ATTEMPTS

	screen._on_connection_failed("테스트: 서버가 안 켜져 있음")
	await Engine.get_main_loop().process_frame

	r.expect_true("재시도 소진 - _resuming_session이 풀림", not screen._resuming_session)
	r.expect_true("재시도 소진 - 연결 패널로 돌아옴(온라인 화면에 멈춰 있지 않음)", screen._connect_panel.visible)

	screen.get_parent().remove_child(screen)
	screen.free()
