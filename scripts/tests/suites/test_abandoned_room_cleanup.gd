extends RefCounted

# 친구 대상 실제 베타 테스트 후속(사용자 지적) - 점유 슬롯 전원이 확정
# 이탈했는데도 서버가 턴 자동 처리로 게임을 끝까지(그리고 재대전 대기
# 2~3분까지) 진행시키던 문제. server_main.gd의 _service_in_game_rooms()가
# 이제 이 상황을 감지하면 즉시 방을 통째로 해제한다
# (Room.all_occupied_slots_past_grace() + _tear_down_abandoned_room()).
# 실제 소켓 없이 server_main.gd 인스턴스를 직접 만들고 Room 상태를
# 조작해서 확인한다(test_pack_relay_buffer_overflow.gd와 같은 패턴).

const PEER_A := 111
const PEER_B := 222


func run(r) -> void:
	r.begin_suite("확정 2/3 후속 - 전원 확정 이탈 시 방 즉시 해제")
	_test_room_torn_down_when_all_occupied_slots_past_grace(r)
	_test_room_not_torn_down_when_one_slot_still_connected(r)
	_test_no_turn_processing_after_teardown(r)


func _make_server() -> Node:
	var server_script: GDScript = load("res://server_main.gd")
	var server = server_script.new()
	server.port_override = 39777  # 실제로 리슨하지 않도록 _start_server()를 안 부르는 대신, 이 테스트는 add_child() 자체를 안 한다(아래 참고).
	return server


## server_main.gd는 _ready()에서 곧바로 _start_server()를 불러 실제 소켓을
## 연다 - 이 테스트는 네트워크가 필요 없으므로 add_child()로 트리에 넣지
## 않고 스크립트 인스턴스만 만들어 순수 로직(room_manager, _service_in_game_rooms())만
## 직접 호출한다. GameEvents 구독도 _ready()에서 일어나므로 트리에 안
## 넣으면 같이 안 걸린다(다른 테스트의 GameEvents 상태를 오염시키지 않음).
func _make_room_with_both_past_grace(server: Node) -> Room:
	var room: Room = server.room_manager.create_room(2, PEER_A)
	server.room_manager.join_room(room.code, PEER_B)
	room.state = Room.State.IN_GAME
	room.game_state.start_turn()
	room.mark_slot_departed(0)
	room.mark_slot_departed(1)
	return room


func _test_room_torn_down_when_all_occupied_slots_past_grace(r) -> void:
	var server := _make_server()
	var room := _make_room_with_both_past_grace(server)
	var code := room.code

	server._service_in_game_rooms(Time.get_ticks_msec())

	r.expect_true("전원 확정 이탈 시 room_manager.rooms에서 방이 사라짐", not server.room_manager.rooms.has(code))
	r.expect_eq("peer_room 매핑도 같이 정리됨(슬롯 0)", server.room_manager.peer_room.has(PEER_A), false)
	r.expect_eq("peer_room 매핑도 같이 정리됨(슬롯 1)", server.room_manager.peer_room.has(PEER_B), false)


func _test_room_not_torn_down_when_one_slot_still_connected(r) -> void:
	var server := _make_server()
	var room: Room = server.room_manager.create_room(2, PEER_A)
	server.room_manager.join_room(room.code, PEER_B)
	room.state = Room.State.IN_GAME
	room.game_state.start_turn()
	room.mark_slot_departed(0)
	# 슬롯 1은 그대로 CONNECTED - 아직 누군가 보고 있을 수 있다.

	server._service_in_game_rooms(Time.get_ticks_msec())

	r.expect_true("한 명이라도 연결돼 있으면 방을 안 지움", server.room_manager.rooms.has(room.code))


## 방이 해제된 뒤에는 room_manager.rooms에 그 코드 자체가 없으므로
## _service_in_game_rooms()를 몇 번을 더 불러도 그 방에 대해서는 아무
## 일도 안 일어난다(순회 대상에서 빠짐) - "게임을 끝까지 자동 진행"하던
## 예전 동작이 재발하지 않는지 확인한다.
func _test_no_turn_processing_after_teardown(r) -> void:
	var server := _make_server()
	var room := _make_room_with_both_past_grace(server)
	var code := room.code
	var confirmed_before: int = room.game_state.player_score_confirmed[0].count(true) + room.game_state.player_score_confirmed[1].count(true)

	server._service_in_game_rooms(Time.get_ticks_msec())
	server._service_in_game_rooms(Time.get_ticks_msec() + 100)
	server._service_in_game_rooms(Time.get_ticks_msec() + 200)

	r.expect_true("방이 사라진 뒤엔 순회 대상에서도 빠짐", not server.room_manager.rooms.has(code))
	r.expect_eq("해제된 뒤엔 그 게임 상태의 확정 칸 수가 안 늘어남(턴 자동 처리가 더 안 일어남)", confirmed_before, 0)
