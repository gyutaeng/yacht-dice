extends RefCounted

# 2-6B(같은 방에서 재대전, docs/multiplayer.md §3/§6) - REMATCHING 상태
# 전이와 "새 게임은 항상 완전히 깨끗하다"를 검증한다. 네트워크 없이
# Room/GameState 순수 로직만 - 실제 전송(2-5 파이프라인)은 실제 소켓
# 검증에서 다룬다.

const PEER_A := 100
const PEER_B := 200


func _make_in_game_room() -> Room:
	var room := Room.new("TEST", 2)
	room.seat_player(PEER_A)
	room.seat_player(PEER_B)
	room.state = Room.State.IN_GAME
	room.game_state.start_turn()
	return room


## auto_confirm_least_damaging()을 현재 턴 플레이어에게 반복 호출해서
## 게임을 끝까지 자동으로 돌린다(test_auto_confirm.gd와 같은 방식) -
## 카테고리 12개 × 인원수만큼 부르면 항상 끝난다(안전 여유로 조금 더 돌림).
func _play_out_game(room: Room) -> void:
	var max_calls := GameState.CATEGORY_NAMES.size() * room.capacity + 4
	var calls := 0
	while not room.game_state.game_over and calls < max_calls:
		room.game_state.auto_confirm_least_damaging(room.game_state.current_player)
		calls += 1


func run(r) -> void:
	r.begin_suite("Room 재대전(2-6B)")

	_test_accepts_lobby_actions(r)
	_test_begin_rematch_wait_resets_ready_and_sets_deadline(r)
	_test_begin_rematch_wait_keeps_meta_and_tokens(r)
	_test_rematch_wait_timeout(r)
	_test_clear_rematch_deadline(r)
	_test_start_new_game_resets_state(r)
	_test_start_new_game_keeps_same_rng(r)
	_test_three_consecutive_rounds_no_contamination(r)
	_test_not_ready_occupied_slots_basic(r)
	_test_not_ready_occupied_slots_ignores_ready(r)
	_test_not_ready_occupied_slots_skips_vacated_slot_during_rematch(r)


func _test_accepts_lobby_actions(r) -> void:
	var room := Room.new("TEST", 2)
	r.expect_true("LOBBY는 로비류 행동을 받음", room.accepts_lobby_actions())
	room.state = Room.State.TRANSFERRING
	r.expect_true("TRANSFERRING은 안 받음", not room.accepts_lobby_actions())
	room.state = Room.State.IN_GAME
	r.expect_true("IN_GAME은 안 받음", not room.accepts_lobby_actions())
	room.state = Room.State.REMATCHING
	r.expect_true("REMATCHING은 받음", room.accepts_lobby_actions())


func _test_begin_rematch_wait_resets_ready_and_sets_deadline(r) -> void:
	var room := _make_in_game_room()
	room.slots[0]["ready"] = true
	room.slots[1]["ready"] = true

	room.begin_rematch_wait(5000)
	r.expect_eq("REMATCHING으로 전환", room.state, Room.State.REMATCHING)
	r.expect_true("슬롯 0 준비 상태가 초기화됨", not room.slots[0]["ready"])
	r.expect_true("슬롯 1 준비 상태가 초기화됨", not room.slots[1]["ready"])
	r.expect_eq("대기 마감 시각 = now + 2분", room.rematch_deadline_msec, 5000 + NetProtocol.REMATCH_READY_TIMEOUT_MSEC)


func _test_begin_rematch_wait_keeps_meta_and_tokens(r) -> void:
	var room := _make_in_game_room()
	room.slots[0]["meta"] = {"id": "char-a", "display_name": "A", "pack_hash": ""}
	var token: String = room.slots[0]["reconnect_token"]

	room.begin_rematch_wait(1000)
	r.expect_eq("캐릭터 메타는 그대로 유지(안 바꾼 사람은 재전송 없음)", room.slots[0]["meta"]["id"], "char-a")
	r.expect_eq("재접속 토큰도 그대로", room.slots[0]["reconnect_token"], token)


func _test_rematch_wait_timeout(r) -> void:
	var room := _make_in_game_room()
	room.begin_rematch_wait(1000)
	r.expect_true("마감 전엔 타임아웃 아님", not room.is_rematch_wait_timed_out(1000 + NetProtocol.REMATCH_READY_TIMEOUT_MSEC - 1))
	r.expect_true("마감이 지나면 타임아웃", room.is_rematch_wait_timed_out(1000 + NetProtocol.REMATCH_READY_TIMEOUT_MSEC))


func _test_clear_rematch_deadline(r) -> void:
	var room := _make_in_game_room()
	room.begin_rematch_wait(1000)
	room.clear_rematch_deadline()
	r.expect_eq("clear 후엔 0", room.rematch_deadline_msec, 0)
	r.expect_true("0이면 타임아웃 판정 안 함", not room.is_rematch_wait_timed_out(999999999))


func _test_start_new_game_resets_state(r) -> void:
	var room := _make_in_game_room()
	_play_out_game(room)
	r.expect_true("한 판을 실제로 끝까지 돌림(사전 조건 확인)", room.game_state.game_over)

	var old_game_state := room.game_state
	room.start_new_game()
	r.expect_true("game_state 객체 자체가 새로 만들어짐", room.game_state != old_game_state)
	r.expect_true("game_over가 리셋됨", not room.game_state.game_over)
	r.expect_eq("첫 턴은 항상 플레이어 0", room.game_state.current_player, 0)
	for p in room.capacity:
		for c in GameState.CATEGORY_NAMES.size():
			r.expect_true("플레이어 %d 칸 %d가 미확정으로 리셋됨" % [p, c], not room.game_state.is_category_confirmed(p, c))


func _test_start_new_game_keeps_same_rng(r) -> void:
	var room := _make_in_game_room()
	var rng_before := room.rng
	room.start_new_game()
	r.expect_true("같은 rng 인스턴스를 재사용(시드를 방마다 한 번만 뽑는다는 원칙)", room.rng == rng_before)


## 사용자가 명시적으로 요청한 검증 - 같은 방에서 연속 3판을 돌려도 상태가
## 오염되지 않는지(누적 전적 없음, 매판 P1부터, 2-5 전송 관련 필드도
## 라운드마다 안 쌓임).
func _test_three_consecutive_rounds_no_contamination(r) -> void:
	var room := _make_in_game_room()

	for round_num in 3:
		_play_out_game(room)
		r.expect_true("%d판째 끝까지 진행됨" % (round_num + 1), room.game_state.game_over)

		var winners := room.game_state.get_winners()
		var scores_after: Array = []
		for p in room.capacity:
			scores_after.append(room.game_state.get_player_total(p))

		room.begin_rematch_wait(1000 + round_num)
		room.slots[0]["ready"] = true
		room.slots[1]["ready"] = true
		r.expect_true("%d판 종료 후 전원 준비되면 all_ready" % (round_num + 1), room.all_ready())

		room.state = Room.State.IN_GAME
		room.start_new_game()
		room.game_state.start_turn()

		r.expect_eq("%d판째 시작은 항상 플레이어 0" % (round_num + 2), room.game_state.current_player, 0)
		r.expect_eq("%d판째 시작 시 총점이 전부 0(누적 전적 없음)" % (round_num + 2), room.game_state.get_player_total(0), 0)
		r.expect_eq("2-5 전송 재시도 카운터가 라운드마다 안 쌓임(비어있음)", room.transfer_resend_request_counts.size(), 0)


func _test_not_ready_occupied_slots_basic(r) -> void:
	var room := _make_in_game_room()
	room.begin_rematch_wait(1000)
	r.expect_eq("둘 다 준비 안 하면 둘 다 목록에", room.not_ready_occupied_slots(), [0, 1])


func _test_not_ready_occupied_slots_ignores_ready(r) -> void:
	var room := _make_in_game_room()
	room.begin_rematch_wait(1000)
	room.slots[0]["ready"] = true
	r.expect_eq("준비된 슬롯은 빠짐", room.not_ready_occupied_slots(), [1])


## 실제로 서버를 죽였던 버그의 재현 조건 - 재대전 대기 중 한 명이
## [나가기](자발적 이탈)로 슬롯을 완전히 비우면 그 슬롯은 null이 된다.
## not_ready_occupied_slots()는 크래시 없이 남은 사람만 돌려줘야 한다.
## (이전 구현은 `var slot: Dictionary = room.slots[i]`처럼 null을 그대로
## 타입 있는 변수에 대입해서 "!= null" 검사보다 먼저 런타임 에러가 났고,
## 이게 server_main.gd의 _process() 안에서 매 프레임 반복돼 재대전
## 기능 전체가 조용히 멈췄다 - _service_rematch_rooms()가 이 함수를
## 쓰도록 고쳐서 같은 실수가 한 곳에서만 나게 만들었다.)
func _test_not_ready_occupied_slots_skips_vacated_slot_during_rematch(r) -> void:
	var room := _make_in_game_room()
	room.begin_rematch_wait(1000)
	room.vacate_by_peer(PEER_B)  # 슬롯 1을 자발적 이탈로 완전히 비움(null)

	var result := room.not_ready_occupied_slots()
	r.expect_eq("남아있는 슬롯 0만 반환(빈 슬롯 1은 제외, 크래시 없음)", result, [0])
