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
