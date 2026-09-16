extends RefCounted

# RoomManager/Room의 순수 로직을 검증한다(2-3, docs/multiplayer.md §3/§4/§6).
# 네트워크(WebSocketMultiplayerPeer)는 전혀 쓰지 않는다 - peer_id는 그냥
# 임의의 정수로 대신한다(RoomManager는 그게 실제 소켓 peer인지 몰라도
# 된다). 매 테스트마다 새 RoomManager를 만들어 서로 영향이 없게 한다.

const FORBIDDEN_CHARS := "01OI"


func run(r) -> void:
	r.begin_suite("RoomManager")

	_test_room_code_shape(r)
	_test_is_valid_player_count(r)
	_test_join_room_success(r)
	_test_join_room_not_found(r)
	_test_join_room_full(r)
	_test_join_room_after_start(r)
	_test_set_player_count_success(r)
	_test_set_player_count_not_host(r)
	_test_set_player_count_out_of_range(r)
	_test_set_player_count_below_occupied(r)
	_test_set_player_count_after_start(r)
	_test_leave_frees_slot_and_reseats(r)
	_test_empty_room_auto_cleanup(r)
	_test_rooms_get_different_seeds(r)

	_test_involuntary_disconnect_in_game_keeps_slot(r)
	_test_involuntary_disconnect_does_not_empty_room(r)
	_test_voluntary_leave_in_game_fully_vacates(r)
	_test_involuntary_disconnect_in_lobby_fully_vacates(r)
	_test_reconnect_with_valid_token_restores_slot(r)
	_test_reconnect_with_wrong_token_is_room_full(r)
	_test_reconnect_with_empty_token_is_room_full(r)

	_test_join_room_during_rematching_allows_fresh_join(r)
	_test_join_room_during_rematching_prefers_token_match(r)
	_test_involuntary_disconnect_during_rematching_keeps_slot(r)
	_test_disconnect_during_rematching_uses_post_game_grace(r)
	_test_disconnect_during_in_game_uses_in_game_grace(r)
	_test_force_vacate_slot_on_already_empty_slot_does_not_crash(r)
	_test_force_vacate_slot_out_of_range_does_not_crash(r)


func _test_room_code_shape(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)

	r.expect_eq("방 코드는 4자리", room.code.length(), RoomManager.ROOM_CODE_LENGTH)

	var has_forbidden := false
	for c in FORBIDDEN_CHARS:
		if room.code.contains(c):
			has_forbidden = true
	r.expect_true("방 코드에 0/O/1/I가 없음", not has_forbidden)


func _test_is_valid_player_count(r) -> void:
	r.expect_true("1명은 무효", not RoomManager.is_valid_player_count(1))
	r.expect_true("2명은 유효", RoomManager.is_valid_player_count(2))
	r.expect_true("4명은 유효", RoomManager.is_valid_player_count(4))
	r.expect_true("5명은 무효", not RoomManager.is_valid_player_count(5))


func _test_join_room_success(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(3, 1)

	var result = room_manager.join_room(room.code, 2)
	r.expect_true("정상 참가는 Room을 돌려줌", result is Room)
	r.expect_eq("참가 후 인원 2명", room.occupied_count(), 2)
	r.expect_eq("두 번째 참가자는 슬롯 1번", room.find_slot_by_peer(2), 1)


func _test_join_room_not_found(r) -> void:
	var room_manager := RoomManager.new()
	var result = room_manager.join_room("ZZZZ", 1)
	r.expect_eq("없는 방 코드는 ROOM_NOT_FOUND", result, NetProtocol.ERROR_ROOM_NOT_FOUND)


func _test_join_room_full(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)

	var result = room_manager.join_room(room.code, 3)
	r.expect_eq("꽉 찬 방은 ROOM_FULL", result, NetProtocol.ERROR_ROOM_FULL)


## 2-6(§6) - 게임이 시작된 뒤 토큰 없이 들어오려 하면 "자리가 없다"로
## 취급해 ROOM_FULL로 거부한다(재접속 토큰이 있으면 다른 경로 -
## test_room_reconnect.gd 참고). 예전엔 GAME_ALREADY_STARTED였지만, §6
## 문구("자리가 없으면 거부")에 맞춰 통일했다.
func _test_join_room_after_start(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	var result = room_manager.join_room(room.code, 3)
	r.expect_eq("게임 시작 후 토큰 없이 참가는 ROOM_FULL", result, NetProtocol.ERROR_ROOM_FULL)


func _test_set_player_count_success(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(4, 1)

	var result = room_manager.set_player_count(1, 2)
	r.expect_eq("방장이 범위 안으로 낮추면 성공(null)", result, null)
	r.expect_eq("capacity가 실제로 바뀜", room.capacity, 2)
	r.expect_eq("슬롯 배열 크기도 같이 줄어듦", room.slots.size(), 2)


func _test_set_player_count_not_host(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(3, 1)
	room_manager.join_room(room.code, 2)

	var result = room_manager.set_player_count(2, 2)
	r.expect_eq("방장이 아니면 NOT_HOST", result, NetProtocol.ERROR_NOT_HOST)


func _test_set_player_count_out_of_range(r) -> void:
	var room_manager := RoomManager.new()
	room_manager.create_room(2, 1)

	r.expect_eq("5명은 INVALID_ARGUMENT", room_manager.set_player_count(1, 5), NetProtocol.ERROR_INVALID_ARGUMENT)
	r.expect_eq("1명은 INVALID_ARGUMENT", room_manager.set_player_count(1, 1), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_set_player_count_below_occupied(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(4, 1)
	room_manager.join_room(room.code, 2)
	room_manager.join_room(room.code, 3)

	var result = room_manager.set_player_count(1, 2)
	r.expect_eq("이미 들어온 인원(3명)보다 낮추면 INVALID_ARGUMENT", result, NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_set_player_count_after_start(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	var result = room_manager.set_player_count(1, 3)
	r.expect_eq("게임 시작 후에는 GAME_ALREADY_STARTED", result, NetProtocol.ERROR_GAME_ALREADY_STARTED)


func _test_leave_frees_slot_and_reseats(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(3, 1)
	room_manager.join_room(room.code, 2)

	var removed := room_manager.remove_peer(2)
	r.expect_eq("나간 슬롯 인덱스는 1번", removed["slot_index"], 1)
	r.expect_eq("그 슬롯이 비워짐", room.slots[1], null)

	room_manager.join_room(room.code, 3)
	r.expect_eq("새 참가자가 빈 슬롯(1번)을 다시 채움", room.find_slot_by_peer(3), 1)


func _test_empty_room_auto_cleanup(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	var code := room.code

	room_manager.remove_peer(1)
	r.expect_eq("전원이 나가면 방이 정리됨", room_manager.get_room(code), null)


## 2-6(§6) - 게임 도중(IN_GAME) 뜻하지 않게 끊기면(voluntary=false) 슬롯을
## 완전히 안 비우고 재접속 유예로 넘긴다.
func _test_involuntary_disconnect_in_game_keeps_slot(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	var result := room_manager.remove_peer(2, false, 1000)
	r.expect_eq("슬롯 인덱스는 그대로 1번", result["slot_index"], 1)
	r.expect_true("슬롯 자체는 안 비워짐", room.slots[1] != null)
	r.expect_eq("연결 상태는 GRACE_PERIOD", room.slot_connection_state[1], Room.ConnectionState.GRACE_PERIOD)


func _test_involuntary_disconnect_does_not_empty_room(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room.state = Room.State.IN_GAME
	var code := room.code

	# 방을 만든 사람(슬롯 0) 혼자인 방에서 끊겨도, 슬롯이 안 비워지므로
	# occupied_count가 그대로라 방이 정리되지 않는다.
	room_manager.remove_peer(1, false, 1000)
	r.expect_true("게임 도중 끊기면 방이 안 지워짐", room_manager.get_room(code) != null)


## 명시적으로 나가는 것(leave())은 게임 도중이라도 그레이스 없이 즉시
## 완전히 비운다.
func _test_voluntary_leave_in_game_fully_vacates(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	room_manager.remove_peer(2, true, 1000)
	r.expect_eq("슬롯이 완전히 비워짐", room.slots[1], null)


func _test_involuntary_disconnect_in_lobby_fully_vacates(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	# room.state는 기본값 LOBBY 그대로.

	room_manager.remove_peer(2, false, 1000)
	r.expect_eq("로비 중 끊김은 재접속 유예 없이 바로 비워짐", room.slots[1], null)


func _test_reconnect_with_valid_token_restores_slot(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME
	var token: String = room.slots[1]["reconnect_token"]

	room_manager.remove_peer(2, false, 1000)
	var result = room_manager.join_room(room.code, 999, token)
	r.expect_true("올바른 토큰이면 Room을 돌려줌(에러 문자열 아님)", result is Room)
	r.expect_eq("같은 슬롯(1번)으로 복귀", room.find_slot_by_peer(999), 1)
	r.expect_eq("연결 상태가 다시 CONNECTED", room.slot_connection_state[1], Room.ConnectionState.CONNECTED)


func _test_reconnect_with_wrong_token_is_room_full(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME
	room_manager.remove_peer(2, false, 1000)

	var result = room_manager.join_room(room.code, 999, "틀린-토큰")
	r.expect_eq("틀린 토큰은 ROOM_FULL", result, NetProtocol.ERROR_ROOM_FULL)


func _test_reconnect_with_empty_token_is_room_full(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME
	room_manager.remove_peer(2, false, 1000)

	var result = room_manager.join_room(room.code, 999)
	r.expect_eq("토큰 없이는(빈 문자열) ROOM_FULL", result, NetProtocol.ERROR_ROOM_FULL)


## 2-6B - REMATCHING 중엔 나갔던 사람이 아니라 완전히 새로운 사람이
## 빈 슬롯을 채워 들어올 수도 있어야 한다(사람이 모자란 재대전 로비).
func _test_join_room_during_rematching_allows_fresh_join(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME
	room_manager.remove_peer(2, true, 1000)  # 자발적 퇴장 - 슬롯 완전히 비워짐
	room.state = Room.State.REMATCHING

	var result = room_manager.join_room(room.code, 999)
	r.expect_true("토큰 없이도 REMATCHING 중엔 새로 참가 가능", result is Room)
	r.expect_eq("빈 슬롯(1번)에 배정됨", room.find_slot_by_peer(999), 1)


## 같은 REMATCHING 상태여도, 토큰이 실제로 일치하면 신규 참가가 아니라
## 재접속으로 처리돼야 한다(빈 슬롯을 엉뚱한 사람이 먼저 채가면 안 됨).
func _test_join_room_during_rematching_prefers_token_match(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME
	var token: String = room.slots[1]["reconnect_token"]
	room_manager.remove_peer(2, false, 1000)  # 비자발적 - 그레이스 유지
	room.state = Room.State.REMATCHING

	var result = room_manager.join_room(room.code, 999, token)
	r.expect_true("토큰이 맞으면 REMATCHING 중에도 재접속으로 처리", result is Room)
	r.expect_eq("원래 슬롯(1번)으로 복귀", room.find_slot_by_peer(999), 1)
	r.expect_eq("연결 상태가 다시 CONNECTED", room.slot_connection_state[1], Room.ConnectionState.CONNECTED)


## 2-6B(추천안) - 재대전 대기 중 끊긴 사람도 2-6과 같은 원칙(연결이
## 끊기면 슬롯을 살려 재접속을 기다림)을 그대로 적용받는다.
func _test_involuntary_disconnect_during_rematching_keeps_slot(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.REMATCHING

	var result := room_manager.remove_peer(2, false, 1000)
	r.expect_eq("슬롯 인덱스는 그대로 1번", result["slot_index"], 1)
	r.expect_true("슬롯 자체는 안 비워짐", room.slots[1] != null)
	r.expect_eq("연결 상태는 GRACE_PERIOD", room.slot_connection_state[1], Room.ConnectionState.GRACE_PERIOD)


## 친구 대상 실제 베타 테스트 후속(사용자 지적) - 예전엔 REMATCHING 중
## 끊겨도 IN_GAME과 같은 유예(60초, RECONNECT_GRACE_MSEC)가 설정됐지만
## 실제로는 아무 서비스 루프도 그 유예를 확인하지 않는 죽은 값이었다
## (REMATCH_READY_TIMEOUT_MSEC(2분)이 사실상의 유일한 상한). 이제는 명시적으로
## POST_GAME_RECONNECT_GRACE_MSEC(3분)이 설정되고 실제로 확인된다
## (server_main.gd::_service_rematch_rooms()의 grace_expired_disconnected_slots() 호출).
func _test_disconnect_during_rematching_uses_post_game_grace(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.REMATCHING

	room_manager.remove_peer(2, false, 5000)
	r.expect_eq("REMATCHING 중 끊기면 POST_GAME 유예로 마감 시각이 잡힘", room.slot_disconnect_deadline_msec[1], 5000 + NetProtocol.POST_GAME_RECONNECT_GRACE_MSEC)


## 대조군 - IN_GAME 중 끊기면 여전히 짧은 유예(IN_GAME_RECONNECT_GRACE_MSEC,
## 60초)가 그대로 적용된다(다른 사람이 이 사람의 턴을 실제로 기다리므로).
func _test_disconnect_during_in_game_uses_in_game_grace(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	room_manager.remove_peer(2, false, 5000)
	r.expect_eq("IN_GAME 중 끊기면 IN_GAME 유예로 마감 시각이 잡힘", room.slot_disconnect_deadline_msec[1], 5000 + NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC)


## 2-6B - 이미 빈 슬롯을 다시 force_vacate_slot()하면(예: 같은 슬롯이
## 두 타임아웃 처리 경로에서 겹쳐 걸리는 경우) 조용히 아무 일도 안 해야
## 한다. 예전엔 `var slot: Dictionary = room.slots[slot_index]`가 null을
## 그대로 타입 있는 변수에 대입해서 이 호출 자체가 런타임 에러였다
## (server_main.gd의 _service_rematch_rooms를 매 프레임 멈추게 한 것과
## 같은 함정).
func _test_force_vacate_slot_on_already_empty_slot_does_not_crash(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)

	room_manager.force_vacate_slot(room, 1)
	r.expect_true("슬롯 1 비워짐", room.slots[1] == null)

	room_manager.force_vacate_slot(room, 1)  # 이미 빈 슬롯을 또 비움 - 크래시 없어야 함
	r.expect_true("두 번째 호출도 크래시 없이 그대로 빈 채로 유지", room.slots[1] == null)


func _test_force_vacate_slot_out_of_range_does_not_crash(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)

	room_manager.force_vacate_slot(room, 99)  # 범위 밖 인덱스 - 크래시 없어야 함
	r.expect_true("범위 밖 인덱스는 조용히 무시됨(슬롯 0 그대로)", room.slots[0] != null)


## 방마다 SecureRandom.generate_seed()를 새로 호출해서 시드를 뽑으므로,
## 두 방의 시드가 우연히 같을 확률은 사실상 0이다(64비트 공간) - 그래서
## "서로 다르다"를 직접 비교해서 "매번 새로 뽑는다"는 걸 확인한다.
func _test_rooms_get_different_seeds(r) -> void:
	var room_manager := RoomManager.new()
	var room_a := room_manager.create_room(2, 1)
	var room_b := room_manager.create_room(2, 2)

	r.expect_true("서로 다른 방은 RNG 인스턴스도 다름", room_a.rng != room_b.rng)
	r.expect_true("서로 다른 방은 시드 값도 다름", room_a.rng.seed != room_b.rng.seed)
