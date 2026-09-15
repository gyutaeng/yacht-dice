extends RefCounted

# Room.validate_roll/validate_hold/validate_score를 검증한다(2-4,
# docs/multiplayer.md §4). 네트워크 없이 순수 로직만 - RoomManager처럼
# server_main.gd가 결과 코드만 보고 실제 GameState 메서드를 부르거나
# error를 보낸다.

const PEER_A := 100
const PEER_B := 200


## 2인 방을 만들어 두 peer를 앉히고 게임을 실제로 시작시킨다(state_changed로
## 실제 GameState.start_turn()을 호출 - current_player=0, has_rolled=false).
func _make_started_room() -> Room:
	var room := Room.new("TEST", 2)
	room.seat_player(PEER_A)
	room.seat_player(PEER_B)
	room.state = Room.State.IN_GAME
	room.game_state.start_turn()
	return room


func run(r) -> void:
	r.begin_suite("Room 턴 검증(validate_roll/hold/score)")

	_test_validate_roll_success(r)
	_test_validate_roll_not_your_turn(r)
	_test_validate_roll_not_in_game(r)
	_test_validate_roll_no_rolls_left(r)

	_test_validate_hold_before_rolling(r)
	_test_validate_hold_success(r)
	_test_validate_hold_out_of_range(r)
	_test_validate_hold_not_your_turn(r)

	_test_validate_score_before_rolling(r)
	_test_validate_score_success(r)
	_test_validate_score_out_of_range_category(r)
	_test_validate_score_already_confirmed(r)
	_test_validate_score_not_your_turn(r)


func _test_validate_roll_success(r) -> void:
	var room := _make_started_room()
	r.expect_eq("현재 턴(슬롯 0)의 굴리기 요청은 통과", room.validate_roll(PEER_A), "")


func _test_validate_roll_not_your_turn(r) -> void:
	var room := _make_started_room()
	r.expect_eq("현재 턴이 아닌 사람의 굴리기 요청은 NOT_YOUR_TURN", room.validate_roll(PEER_B), NetProtocol.ERROR_NOT_YOUR_TURN)


func _test_validate_roll_not_in_game(r) -> void:
	var room := Room.new("TEST2", 2)
	room.seat_player(PEER_A)
	room.seat_player(PEER_B)
	# state는 기본값 LOBBY 그대로(게임이 아직 시작 안 됨).
	r.expect_eq("로비 단계에서 굴리기 요청은 NOT_IN_GAME", room.validate_roll(PEER_A), NetProtocol.ERROR_NOT_IN_GAME)


func _test_validate_roll_no_rolls_left(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	room.game_state.roll()
	room.game_state.roll()
	r.expect_eq("리롤을 다 쓴 뒤 굴리기 요청은 INVALID_ARGUMENT", room.validate_roll(PEER_A), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_hold_before_rolling(r) -> void:
	var room := _make_started_room()
	r.expect_eq("아직 안 굴렸는데 고정 요청은 INVALID_ARGUMENT(1-3B)", room.validate_hold(PEER_A, 0), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_hold_success(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("굴린 뒤 유효한 인덱스 고정 요청은 통과", room.validate_hold(PEER_A, 0), "")


func _test_validate_hold_out_of_range(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("범위 밖 인덱스(5)는 INVALID_ARGUMENT", room.validate_hold(PEER_A, 5), NetProtocol.ERROR_INVALID_ARGUMENT)
	r.expect_eq("범위 밖 인덱스(-1)는 INVALID_ARGUMENT", room.validate_hold(PEER_A, -1), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_hold_not_your_turn(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("현재 턴이 아닌 사람의 고정 요청은 NOT_YOUR_TURN", room.validate_hold(PEER_B, 0), NetProtocol.ERROR_NOT_YOUR_TURN)


func _test_validate_score_before_rolling(r) -> void:
	var room := _make_started_room()
	r.expect_eq("아직 안 굴렸는데 확정 요청은 INVALID_ARGUMENT", room.validate_score(PEER_A, 6), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_score_success(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("굴린 뒤 안 쓴 칸 확정 요청은 통과", room.validate_score(PEER_A, 6), "")


func _test_validate_score_out_of_range_category(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("범위 밖 카테고리(12)는 INVALID_ARGUMENT", room.validate_score(PEER_A, 12), NetProtocol.ERROR_INVALID_ARGUMENT)
	r.expect_eq("범위 밖 카테고리(-1)는 INVALID_ARGUMENT", room.validate_score(PEER_A, -1), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_score_already_confirmed(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	room.game_state.confirm_category(6)  # Choice 확정 - 턴이 넘어감(플레이어 1)
	room.game_state.roll()
	room.game_state.confirm_category(6)  # 플레이어 1도 Choice 확정 - 턴이 다시 0으로
	r.expect_eq("이미 확정된 칸(Choice)에 다시 확정 요청은 INVALID_ARGUMENT", room.validate_score(PEER_A, 6), NetProtocol.ERROR_INVALID_ARGUMENT)


func _test_validate_score_not_your_turn(r) -> void:
	var room := _make_started_room()
	room.game_state.roll()
	r.expect_eq("현재 턴이 아닌 사람의 확정 요청은 NOT_YOUR_TURN", room.validate_score(PEER_B, 6), NetProtocol.ERROR_NOT_YOUR_TURN)
