extends RefCounted

# 2-6(연결 끊김/재접속/턴 타임아웃, docs/multiplayer.md §6) - Room의 연결
# 상태 전이(CONNECTED/GRACE_PERIOD/PAST_GRACE)와 턴 데드라인 계산을
# 검증한다. 네트워크/시간 모두 순수 로직이라(now_msec을 직접 넘김) 헤드리스로
# 그대로 확인할 수 있다.

const PEER_A := 100
const PEER_B := 200


func _make_in_game_room() -> Room:
	var room := Room.new("TEST", 2)
	room.seat_player(PEER_A)
	room.seat_player(PEER_B)
	room.state = Room.State.IN_GAME
	return room


func run(r) -> void:
	r.begin_suite("Room 연결 상태/턴 타임아웃(2-6)")

	_test_new_slot_starts_connected(r)
	_test_mark_slot_disconnected_sets_grace_period(r)
	_test_grace_expiry(r)
	_test_mark_slot_reconnected_restores_connected(r)
	_test_mark_slot_departed_sets_past_grace(r)
	_test_find_slot_by_reconnect_token_ignores_connected_slots(r)
	_test_find_slot_by_reconnect_token_finds_disconnected_slot(r)
	_test_find_slot_by_reconnect_token_wrong_token(r)
	_test_reconnect_after_past_grace_still_works(r)

	_test_turn_deadline_not_timed_out_right_after_reset(r)
	_test_turn_deadline_timed_out_after_60_seconds(r)
	_test_turn_deadline_zero_means_no_timer(r)
	_test_clear_turn_deadline(r)


func _test_new_slot_starts_connected(r) -> void:
	var room := _make_in_game_room()
	r.expect_eq("새로 앉은 슬롯은 CONNECTED", room.slot_connection_state[0], Room.ConnectionState.CONNECTED)


func _test_mark_slot_disconnected_sets_grace_period(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	r.expect_eq("연결이 끊기면 GRACE_PERIOD", room.slot_connection_state[0], Room.ConnectionState.GRACE_PERIOD)
	r.expect_eq("peer_id는 -1로 비워짐", room.slots[0]["peer_id"], -1)
	r.expect_true("슬롯 자체는 안 비워짐(meta/토큰 유지)", room.slots[0] != null)
	r.expect_eq("마감 시각은 now + 2분", room.slot_disconnect_deadline_msec[0], 1000 + NetProtocol.RECONNECT_GRACE_MSEC)


func _test_grace_expiry(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	r.expect_true("유예 시간 전엔 만료 아님", not room.is_grace_expired(0, 1000 + NetProtocol.RECONNECT_GRACE_MSEC - 1))
	r.expect_true("유예 시간이 지나면 만료", room.is_grace_expired(0, 1000 + NetProtocol.RECONNECT_GRACE_MSEC))


func _test_mark_slot_reconnected_restores_connected(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	room.mark_slot_reconnected(0, 999)
	r.expect_eq("재접속하면 다시 CONNECTED", room.slot_connection_state[0], Room.ConnectionState.CONNECTED)
	r.expect_eq("새 peer_id로 갱신됨", room.slots[0]["peer_id"], 999)
	r.expect_eq("마감 시각 초기화", room.slot_disconnect_deadline_msec[0], 0)


func _test_mark_slot_departed_sets_past_grace(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	room.mark_slot_departed(0)
	r.expect_eq("유예 만료 후 확정 이탈은 PAST_GRACE", room.slot_connection_state[0], Room.ConnectionState.PAST_GRACE)


func _test_find_slot_by_reconnect_token_ignores_connected_slots(r) -> void:
	var room := _make_in_game_room()
	var token: String = room.slots[0]["reconnect_token"]
	r.expect_eq("CONNECTED인 슬롯은 토큰이 맞아도 매칭 안 됨(자리 뺏기 방지)", room.find_slot_by_reconnect_token(token), -1)


func _test_find_slot_by_reconnect_token_finds_disconnected_slot(r) -> void:
	var room := _make_in_game_room()
	var token: String = room.slots[0]["reconnect_token"]
	room.mark_slot_disconnected(0, 1000)
	r.expect_eq("GRACE_PERIOD인 슬롯은 토큰으로 찾을 수 있음", room.find_slot_by_reconnect_token(token), 0)


func _test_find_slot_by_reconnect_token_wrong_token(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	r.expect_eq("틀린 토큰은 -1", room.find_slot_by_reconnect_token("엉뚱한-토큰"), -1)
	r.expect_eq("빈 토큰도 -1", room.find_slot_by_reconnect_token(""), -1)


## 2-6 설계 확정 - 유예가 끝나 확정 이탈로 넘어간 뒤에도 같은 토큰이면
## 다시 찾을 수 있어야 한다(사용자 확인).
func _test_reconnect_after_past_grace_still_works(r) -> void:
	var room := _make_in_game_room()
	var token: String = room.slots[0]["reconnect_token"]
	room.mark_slot_disconnected(0, 1000)
	room.mark_slot_departed(0)
	r.expect_eq("확정 이탈 후에도 토큰으로 여전히 찾을 수 있음", room.find_slot_by_reconnect_token(token), 0)


func _test_turn_deadline_not_timed_out_right_after_reset(r) -> void:
	var room := _make_in_game_room()
	room.reset_turn_deadline(1000)
	r.expect_true("리셋 직후엔 타임아웃 아님", not room.is_turn_timed_out(1000))
	r.expect_true("59.9초 후도 아직 아님", not room.is_turn_timed_out(1000 + NetProtocol.TURN_TIMEOUT_MSEC - 1))


func _test_turn_deadline_timed_out_after_60_seconds(r) -> void:
	var room := _make_in_game_room()
	room.reset_turn_deadline(1000)
	r.expect_true("60초가 지나면 타임아웃", room.is_turn_timed_out(1000 + NetProtocol.TURN_TIMEOUT_MSEC))


func _test_turn_deadline_zero_means_no_timer(r) -> void:
	var room := _make_in_game_room()
	r.expect_true("아직 한 번도 리셋 안 했으면 타임아웃 판정 자체가 없음", not room.is_turn_timed_out(999999999))


func _test_clear_turn_deadline(r) -> void:
	var room := _make_in_game_room()
	room.reset_turn_deadline(1000)
	room.clear_turn_deadline()
	r.expect_eq("clear 후엔 0", room.turn_deadline_msec, 0)
	r.expect_true("0이면 타임아웃 판정 안 함", not room.is_turn_timed_out(999999999))
