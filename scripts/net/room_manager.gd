class_name RoomManager
extends RefCounted

# 방 코드로 Room을 찾아 라우팅하는 순수 로직(RefCounted, 네트워크를 전혀
# 모른다) - server_main.gd가 실제 패킷을 받으면 이 클래스의 메서드를 부르고
# 결과만 받아 전송을 담당한다. GameState가 UI를 모르는 것과 같은 분리라,
# 헤드리스 테스트에서 실제 소켓 없이 그대로 검증할 수 있다.

const MIN_PLAYER_COUNT := GameState.MIN_PLAYER_COUNT
const MAX_PLAYER_COUNT := GameState.MAX_PLAYER_COUNT

# 헷갈리는 0/O, 1/I를 제외한 4자리 영숫자 방 코드.
const ROOM_CODE_LENGTH := 4
const ROOM_CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

var rooms: Dictionary = {}  # code(String) -> Room
var peer_room: Dictionary = {}  # peer_id(int) -> code(String)

var _code_rng := RandomNumberGenerator.new()


func _init() -> void:
	# 방 코드는 비밀이 아니라(docs/multiplayer.md §6) 추측 저항성이 필요
	# 없다 - 충돌만 안 나면 되므로 일반 RNG로 충분하다(SecureRandom은
	# 방마다 새로 뽑는 주사위 시드처럼 "예측하면 치팅이 되는" 값에만 쓴다).
	_code_rng.randomize()


static func is_valid_player_count(count: int) -> bool:
	return count >= MIN_PLAYER_COUNT and count <= MAX_PLAYER_COUNT


func get_room(code: String) -> Room:
	return rooms.get(code)


func get_room_for_peer(peer_id: int) -> Room:
	if not peer_room.has(peer_id):
		return null
	return rooms.get(peer_room[peer_id])


## 새 방을 만들고 만든 사람을 0번 슬롯에 앉힌다. player_count는 호출부가
## 미리 is_valid_player_count()로 검증했다고 가정한다.
func create_room(player_count: int, creator_peer_id: int) -> Room:
	var code := _generate_unique_code()
	var room := Room.new(code, player_count)
	room.seat_player(creator_peer_id)
	rooms[code] = room
	peer_room[creator_peer_id] = code
	return room


## join_room 처리. 성공하면 Room을, 실패하면 NetProtocol의 에러 코드
## 문자열을 돌려준다(§4: 방 존재/자리 있음/게임 미시작 검사).
func join_room(code: String, peer_id: int) -> Variant:
	var room: Room = rooms.get(code)
	if room == null:
		return NetProtocol.ERROR_ROOM_NOT_FOUND
	if room.state != Room.State.LOBBY:
		return NetProtocol.ERROR_GAME_ALREADY_STARTED
	if room.is_full():
		return NetProtocol.ERROR_ROOM_FULL

	room.seat_player(peer_id)
	peer_room[peer_id] = code
	return room


## set_player_count 처리. 성공하면 null, 실패하면 에러 코드 문자열.
func set_player_count(peer_id: int, new_count: int) -> Variant:
	var room := get_room_for_peer(peer_id)
	if room == null:
		return NetProtocol.ERROR_ROOM_NOT_FOUND
	if room.state != Room.State.LOBBY:
		return NetProtocol.ERROR_GAME_ALREADY_STARTED
	if room.find_slot_by_peer(peer_id) != room.host_index():
		return NetProtocol.ERROR_NOT_HOST
	if not is_valid_player_count(new_count) or new_count < room.occupied_count():
		return NetProtocol.ERROR_INVALID_ARGUMENT

	room.change_capacity(new_count)
	return null


## leave 메시지 또는 연결 끊김. 그 peer가 있던 방과 슬롯 인덱스를
## {room, slot_index} 형태로 돌려준다(빈 방이 되면 즉시 정리하고 room은
## null로 - 호출부가 브로드캐스트 대상이 없다는 걸 알 수 있게). 그 peer가
## 어느 방에도 없었으면 room/slot_index 둘 다 null/-1.
func remove_peer(peer_id: int) -> Dictionary:
	var code = peer_room.get(peer_id)
	peer_room.erase(peer_id)
	if code == null:
		return {"room": null, "slot_index": -1}

	var room: Room = rooms.get(code)
	if room == null:
		return {"room": null, "slot_index": -1}

	var slot_index := room.vacate_by_peer(peer_id)
	if room.is_empty():
		rooms.erase(code)
		return {"room": null, "slot_index": slot_index}

	return {"room": room, "slot_index": slot_index}


func _generate_unique_code() -> String:
	var code := _random_code()
	while rooms.has(code):
		code = _random_code()
	return code


func _random_code() -> String:
	var chars := PackedStringArray()
	for i in ROOM_CODE_LENGTH:
		var index := _code_rng.randi_range(0, ROOM_CODE_ALPHABET.length() - 1)
		chars.append(ROOM_CODE_ALPHABET[index])
	return "".join(chars)
