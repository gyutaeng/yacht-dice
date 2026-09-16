extends RefCounted

# OnlineGameController를 소켓 없이 검증한다(2-4). GameClient를 실제 서버에
# 연결하지 않고(그러면 _process가 IDLE 상태에 머물러 있음) 그 시그널만
# 직접 emit해서 "서버가 이렇게 응답했다"를 흉내낸다 - 연타 방지
# (is_request_pending)와 GameEvents 재방출 두 가지가 핵심이다. 실제
# 소켓을 통한 전체 흐름(요청->스냅샷->화면 갱신)은 수동으로 서버를 띄워
# 검증했다(이 스위트는 그 대신이 아니라 보완).

func run(r) -> void:
	r.begin_suite("OnlineGameController")

	_test_request_pending_blocks_repeat_requests(r)
	_test_snapshot_clears_pending_and_updates_game_state(r)
	_test_server_error_also_clears_pending(r)
	_test_relays_events_into_local_game_events(r)
	_test_relays_die_held_changed(r)
	_test_relays_game_state_started_as_game_started(r)
	_test_dispose_disconnects_all_tracked_connections(r)
	_test_dispose_is_idempotent(r)
	_test_every_client_signal_connection_is_tracked(r)


func _make_controller() -> OnlineGameController:
	var client := GameClient.new()  # connect_to_server()를 안 불러서 IDLE 상태로 남는다 - 소켓 없음.
	return OnlineGameController.new(client, 2, 0)


func _test_request_pending_blocks_repeat_requests(r) -> void:
	var controller := _make_controller()
	r.expect_eq("처음엔 대기 중인 요청이 없음", controller.is_request_pending(), false)

	controller.request_roll()
	r.expect_eq("요청을 보내면 대기 상태가 됨", controller.is_request_pending(), true)

	# 응답 전에 또 눌러도(연타) 크래시 없이 무시되기만 하면 된다 - 여기서는
	# "여전히 pending"이라는 사실 자체가 두 번째 시도가 상태를 안 바꿨다는 증거.
	controller.request_roll()
	controller.request_hold(0)
	controller.request_score(0)
	r.expect_eq("응답 전 연타는 상태를 안 바꿈(여전히 대기 중)", controller.is_request_pending(), true)


func _test_snapshot_clears_pending_and_updates_game_state(r) -> void:
	var controller := _make_controller()
	controller.request_roll()

	var fake_snapshot := {
		"dice_results": [6, 6, 6, 6, 6],
		"dice_locked": [false, false, false, false, false],
		"rolls_left": 2,
		"has_rolled": true,
		"current_player": 1,
		"game_over": false,
		"player_count": 2,
		"player_score_confirmed": [[false, false, false, false, false, false, false, false, false, false, false, false], [false, false, false, false, false, false, false, false, false, false, false, false]],
		"player_confirmed_scores": [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
		"player_bonus_achieved": [false, false],
	}
	controller._client.state_snapshot_received.emit(fake_snapshot)

	r.expect_eq("스냅샷을 받으면 대기 상태가 풀림", controller.is_request_pending(), false)
	r.expect_eq("read_only game_state가 스냅샷 값으로 갱신됨", controller.game_state.dice_results, [6, 6, 6, 6, 6])
	r.expect_eq("current_player도 갱신됨", controller.game_state.current_player, 1)


func _test_server_error_also_clears_pending(r) -> void:
	var controller := _make_controller()
	controller.request_score(0)
	r.expect_eq("요청 직후엔 대기 중", controller.is_request_pending(), true)

	controller._client.server_error.emit(NetProtocol.ERROR_NOT_YOUR_TURN, "당신의 턴이 아닙니다.")

	r.expect_eq("서버가 거부해도(에러) 대기 상태가 풀림 - 안 그러면 다음 시도가 영원히 막힘", controller.is_request_pending(), false)


## 문서(§1)의 "서버 이벤트를 받으면 자기 로컬 GameEvents로 그대로 다시
## emit한다"를 검증한다 - 6개 중 대표로 dice_rolled/turn_started 두 개만
## 확인한다(나머지 4개도 online_game_controller.gd에서 같은 패턴).
func _test_relays_events_into_local_game_events(r) -> void:
	var controller := _make_controller()

	var dice_received: Array = []
	var turn_received: Array = []
	var on_dice := func(p, v, rr): dice_received.append([p, v, rr])
	var on_turn := func(p): turn_received.append(p)
	GameEvents.dice_rolled.connect(on_dice)
	GameEvents.turn_started.connect(on_turn)

	# GameClient.dice_rolled는 Array[int]로 타입이 고정돼 있다 - 실제
	# 코드(game_client.gd의 _to_int_array())는 항상 진짜 Array[int]를 만들어
	# emit하므로, 테스트도 일반 Array 리터럴이 아니라 그렇게 타입을 맞춰야
	# SfxBank 등 실제 구독자가 받는 것과 같은 조건이 된다(안 맞추면 엉뚱한
	# 타입 변환 에러가 남 - 이 테스트 자체의 문제였지 프로덕션 코드 문제는 아님).
	var dice_values: Array[int] = [1, 2, 3, 4, 5]
	controller._client.dice_rolled.emit(1, dice_values, 2)
	controller._client.turn_started.emit(1)

	GameEvents.dice_rolled.disconnect(on_dice)
	GameEvents.turn_started.disconnect(on_turn)

	r.expect_eq("dice_rolled가 로컬 GameEvents로 재방출됨", dice_received.size(), 1)
	r.expect_eq("turn_started가 로컬 GameEvents로 재방출됨", turn_received, [1])


## 2-4C에서 추가 - die_held_changed가 이 목록에서 빠져서 온라인 홀드
## 효과음이 안 나는 버그가 실제로 났었다(회귀 테스트).
func _test_relays_die_held_changed(r) -> void:
	var controller := _make_controller()
	var received: Array = []
	var on_held := func(p, i, held): received.append([p, i, held])
	GameEvents.die_held_changed.connect(on_held)

	controller._client.die_held_changed.emit(0, 2, true)

	GameEvents.die_held_changed.disconnect(on_held)
	r.expect_eq("die_held_changed가 로컬 GameEvents로 재방출됨", received, [[0, 2, true]])


## game_state_started(네트워크 메시지 이름)는 로컬 GameEvents로 다시 emit할
## 때 이름이 game_started로 바뀐다 - 로비 종료 game_started와 겹치지 않게
## 일부러 다르게 지은 이름이라, relay 지점에서 정확히 되돌아가는지 확인한다.
func _test_relays_game_state_started_as_game_started(r) -> void:
	var controller := _make_controller()
	var received: Array = []
	var on_started := func(pc): received.append(pc)
	GameEvents.game_started.connect(on_started)

	controller._client.game_state_started.emit(3)

	GameEvents.game_started.disconnect(on_started)
	r.expect_eq("game_state_started가 로컬 GameEvents.game_started로 재방출됨", received, [3])


## 친구 대상 실제 베타 테스트에서 발견된 버그(재대전/로비 재개설 시 캐릭터
## 보이스 중복 재생)의 재발 방지(후속 1) - dispose()가 실제로 client의
## 시그널 연결을 전부 끊는지 직접 확인한다. GameEvents로 다시 emit되는지가
## 아니라, client 쪽 연결 자체가 사라지는지를 본다(더 근본적인 확인).
func _test_dispose_disconnects_all_tracked_connections(r) -> void:
	var client := GameClient.new()
	var controller := OnlineGameController.new(client, 2, 0)

	r.expect_true("dispose() 전엔 turn_started에 연결이 있음", client.turn_started.get_connections().size() > 0)

	controller.dispose()

	r.expect_eq("dispose() 후 turn_started 연결이 전부 사라짐", client.turn_started.get_connections().size(), 0)
	r.expect_eq("dispose() 후 state_snapshot_received 연결도 전부 사라짐", client.state_snapshot_received.get_connections().size(), 0)
	r.expect_eq("dispose() 후 game_state_started 연결도 전부 사라짐", client.game_state_started.get_connections().size(), 0)


## 후속 1(사용자 지적) - dispose()는 Main.gd의 _return_to_title()과
## _enter_game() 두 곳에서 불릴 수 있는 경로가 있다(재대전은 _return_to_title()을
## 안 거치므로 _enter_game()에서도 한 번 더 방어적으로 부름). 실제로는
## active_controller가 null로 바뀌거나 교체되어 같은 인스턴스에 두 번
## 불릴 일이 지금 코드 경로상 없지만, 이 자체가 안전한지(연속 2회 호출해도
## 에러 없이 조용히 아무 일도 안 하는지)는 별개로 보장돼야 한다 - 이
## 프로젝트는 _process 안의 에러가 기능을 조용히 마비시키는 사고
## (_service_rematch_rooms)를 이미 겪었다.
func _test_dispose_is_idempotent(r) -> void:
	var client := GameClient.new()
	var controller := OnlineGameController.new(client, 2, 0)

	controller.dispose()
	# 여기서 "Signal is already connected"류 에러 없이 통과하면 성공 -
	# r.expect_*를 더 이상 못 부르는 크래시가 없다는 사실 자체가 증거다.
	controller.dispose()
	controller.dispose()

	r.expect_eq("연속 3회 dispose()해도 연결은 여전히 0개(에러 없이 안전)", client.turn_started.get_connections().size(), 0)


## 후속 2(사용자 지적) - "connect할 때 쌍을 저장한다"는 규약이 아니라
## 구조로 강제하고 싶다는 요청. OnlineGameController._connect_tracked()가
## 이 파일 안에서 _client 시그널에 연결하는 유일한 통로여야 한다 - 이
## 테스트는 GameClient가 스스로 선언한 모든 시그널(get_script_signal_list(),
## 상속받은 Node 시그널 제외)을 순회해서, 실제 연결 개수가 _relay_connections
## 장부에 기록된 개수와 정확히 같은지 리플렉션으로 확인한다. 이 테스트에
## 쓰는 client는 OnlineGameController 하나만 붙이고 online_screen.gd 등
## 다른 구독자를 붙이지 않은 "깨끗한" 인스턴스라서, 장부 밖에서 생긴
## 연결이 있으면 바로 드러난다 - 나중에 누가 _connect_tracked()를 안 거치고
## _client.xxx.connect(...)를 직접 추가하면 이 테스트가 실패한다.
func _test_every_client_signal_connection_is_tracked(r) -> void:
	var client := GameClient.new()
	var controller := OnlineGameController.new(client, 2, 0)

	var tracked_counts := {}
	for entry in controller._relay_connections:
		var sig: Signal = entry[0]
		var name := sig.get_name()
		tracked_counts[name] = tracked_counts.get(name, 0) + 1

	var mismatches: Array[String] = []
	for signal_info in client.get_script().get_script_signal_list():
		var sig_name: String = signal_info["name"]
		var actual: int = Signal(client, sig_name).get_connections().size()
		var tracked: int = tracked_counts.get(sig_name, 0)
		if actual != tracked:
			mismatches.append("%s(실제 %d개, 장부 %d개)" % [sig_name, actual, tracked])

	r.expect_eq("GameClient의 모든 시그널 연결이 _relay_connections 장부와 정확히 일치함(장부 밖 connect 없음)", mismatches, [])
