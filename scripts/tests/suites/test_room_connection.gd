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
	_test_grace_expiry_and_turn_timeout_coincide_processes_turn_once(r)

	_test_all_occupied_slots_past_grace_false_when_empty_room(r)
	_test_all_occupied_slots_past_grace_false_when_one_connected(r)
	_test_all_occupied_slots_past_grace_false_when_one_still_in_grace_period(r)
	_test_all_occupied_slots_past_grace_true_when_all_past_grace(r)
	_test_all_occupied_slots_past_grace_ignores_vacated_slots(r)


func _test_new_slot_starts_connected(r) -> void:
	var room := _make_in_game_room()
	r.expect_eq("새로 앉은 슬롯은 CONNECTED", room.slot_connection_state[0], Room.ConnectionState.CONNECTED)


func _test_mark_slot_disconnected_sets_grace_period(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	r.expect_eq("연결이 끊기면 GRACE_PERIOD", room.slot_connection_state[0], Room.ConnectionState.GRACE_PERIOD)
	r.expect_eq("peer_id는 -1로 비워짐", room.slots[0]["peer_id"], -1)
	r.expect_true("슬롯 자체는 안 비워짐(meta/토큰 유지)", room.slots[0] != null)
	r.expect_eq("마감 시각은 now + 재접속 유예", room.slot_disconnect_deadline_msec[0], 1000 + NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC)


func _test_grace_expiry(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_disconnected(0, 1000)
	r.expect_true("유예 시간 전엔 만료 아님", not room.is_grace_expired(0, 1000 + NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC - 1))
	r.expect_true("유예 시간이 지나면 만료", room.is_grace_expired(0, 1000 + NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC))


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


## 재접속 유예를 턴 제한과 같은 60초로 낮추면서(사용자 지적) 생긴 경계
## 상황 - 자기 턴이 시작된 직후 끊기면 "유예 만료(확정 이탈)"와 "턴 시간
## 초과"가 정확히 같은 시점에 겹칠 수 있다. server_main.gd의
## _service_in_game_rooms()가 실제로 하는 순서를 그대로 재현한다:
## ①모든 슬롯의 그레이스 만료를 먼저 처리(mark_slot_departed) →
## ②"현재 턴 플레이어가 이탈했거나(current_gone) 또는 턴 시간 초과"를
## 하나의 if로 묶어 auto_confirm_least_damaging()을 부른다. 이 if가
## 하나뿐이라(OR 조건 두 개가 각각 따로 부르지 않음) 두 조건이 동시에
## 참이어도 호출은 항상 한 번뿐이다 - 이 테스트는 그 불변식을 박아둔다.
## (이 함수가 실제 server_main.gd 코드를 그대로 부르는 게 아니라 같은
## 순서를 재현한 것이라, 그쪽 로직이 바뀌면 이 테스트도 같이 살펴봐야
## 한다 - 실제 서버 흐름은 실제 소켓으로도 별도 확인했다.)
func _test_grace_expiry_and_turn_timeout_coincide_processes_turn_once(r) -> void:
	r.expect_eq("전제 - 재접속 유예와 턴 제한이 정확히 같은 값(60초)이어야 이 경계가 생김", NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC, NetProtocol.TURN_TIMEOUT_MSEC)

	var room := _make_in_game_room()
	room.game_state.start_turn()
	var t0 := 1_000_000
	room.mark_slot_disconnected(0, t0)  # 0번 슬롯(지금 턴 플레이어)이 끊김.
	room.reset_turn_deadline(t0)  # 같은 순간 턴도 막 시작된 상황을 재현.

	var starting_player: int = room.game_state.current_player
	r.expect_eq("시작 시점엔 0번 플레이어 턴", starting_player, 0)

	var now2: int = t0 + NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC  # == t0 + TURN_TIMEOUT_MSEC(위에서 확인함).

	# --- server_main.gd _service_in_game_rooms()와 같은 순서 ---
	for i in room.slots.size():
		if room.slots[i] == null:
			continue
		if room.is_grace_expired(i, now2):
			room.mark_slot_departed(i)

	var current: int = room.game_state.current_player
	var current_gone: bool = room.slots[current] == null or room.slot_connection_state[current] == Room.ConnectionState.PAST_GRACE
	var processed_count := 0
	if current_gone or room.is_turn_timed_out(now2):
		room.game_state.auto_confirm_least_damaging(current)
		processed_count += 1

	r.expect_eq("두 조건이 동시에 참이어도 턴 처리는 정확히 한 번", processed_count, 1)
	r.expect_eq("현재 플레이어가 정확히 한 칸만 넘어감(두 칸 아님)", room.game_state.current_player, (starting_player + 1) % 2)
	r.expect_true("0번 플레이어의 확정 칸이 정확히 하나만 생김", room.game_state.player_score_confirmed[0].count(true) == 1)


## 친구 대상 실제 베타 테스트 후속(사용자 지적) - 점유 슬롯 전원이 확정
## 이탈했을 때만 true여야 한다. 방금 만든 방(둘 다 CONNECTED)은 당연히
## false.
func _test_all_occupied_slots_past_grace_false_when_empty_room(r) -> void:
	var room := Room.new("TEST", 2)
	r.expect_true("아무도 안 앉은 방은 '전원 이탈'이 아니라 '애초에 없음'", not room.all_occupied_slots_past_grace())


func _test_all_occupied_slots_past_grace_false_when_one_connected(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_departed(0)
	r.expect_true("한 명(슬롯 1)이 아직 연결돼 있으면 false", not room.all_occupied_slots_past_grace())


func _test_all_occupied_slots_past_grace_false_when_one_still_in_grace_period(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_departed(0)
	room.mark_slot_disconnected(1, 1000)  # 슬롯 1은 아직 유예 중(GRACE_PERIOD) - PAST_GRACE 아님.
	r.expect_true("한 명이 아직 유예 중(재접속 가능)이면 false", not room.all_occupied_slots_past_grace())


func _test_all_occupied_slots_past_grace_true_when_all_past_grace(r) -> void:
	var room := _make_in_game_room()
	room.mark_slot_departed(0)
	room.mark_slot_departed(1)
	r.expect_true("점유된 슬롯 전부가 확정 이탈이면 true", room.all_occupied_slots_past_grace())


## 슬롯 하나가 자발적 이탈(leave())로 완전히 비워진(null) 상태라면 "점유된"
## 슬롯이 아니므로 판정 대상에서 빠져야 한다 - 나머지 한 명만 확정
## 이탈이어도 true가 나와야 정상(빈 슬롯은 "아직 연결돼 있을지도 모르는
## 사람"이 아니라 그냥 없는 자리이므로).
func _test_all_occupied_slots_past_grace_ignores_vacated_slots(r) -> void:
	var room := _make_in_game_room()
	room.vacate_by_peer(PEER_A)  # 슬롯 0을 자발적 이탈로 완전히 비움(null).
	room.mark_slot_departed(1)
	r.expect_true("빈 슬롯은 제외하고, 남은 점유 슬롯만으로 판단", room.all_occupied_slots_past_grace())
