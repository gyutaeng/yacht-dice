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


func _test_join_room_after_start(r) -> void:
	var room_manager := RoomManager.new()
	var room := room_manager.create_room(2, 1)
	room_manager.join_room(room.code, 2)
	room.state = Room.State.IN_GAME

	var result = room_manager.join_room(room.code, 3)
	r.expect_eq("게임 시작 후 참가는 GAME_ALREADY_STARTED", result, NetProtocol.ERROR_GAME_ALREADY_STARTED)


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


## 방마다 SecureRandom.generate_seed()를 새로 호출해서 시드를 뽑으므로,
## 두 방의 시드가 우연히 같을 확률은 사실상 0이다(64비트 공간) - 그래서
## "서로 다르다"를 직접 비교해서 "매번 새로 뽑는다"는 걸 확인한다.
func _test_rooms_get_different_seeds(r) -> void:
	var room_manager := RoomManager.new()
	var room_a := room_manager.create_room(2, 1)
	var room_b := room_manager.create_room(2, 2)

	r.expect_true("서로 다른 방은 RNG 인스턴스도 다름", room_a.rng != room_b.rng)
	r.expect_true("서로 다른 방은 시드 값도 다름", room_a.rng.seed != room_b.rng.seed)
