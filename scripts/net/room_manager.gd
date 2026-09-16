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
##
## 2-6(§6)/2-6B(재대전) - 토큰이 있고 그 방의 연결 안 된 슬롯과 정확히
## 일치하면 방 상태와 무관하게 항상 그 슬롯으로 복귀시킨다(원래 있던
## player_index를 그대로 되찾음) - TRANSFERRING/IN_GAME 도중 재접속뿐
## 아니라 REMATCHING(재대전 대기) 중 재접속도 이 경로 하나로 처리한다.
## 토큰이 없거나 안 맞으면 신규 참가로 취급한다 - `accepts_lobby_actions()`
## (LOBBY/REMATCHING)일 때만 빈 자리에 앉힐 수 있고, 그 외
## (TRANSFERRING/IN_GAME)는 "자리가 없다"로 취급해 ROOM_FULL로 거부한다
## (§6 문구 그대로 - "게임이 이미 시작돼서"가 아니라 "들어갈 자리가
## 없어서" 거부라는 게 문서의 표현이다).
func join_room(code: String, peer_id: int, reconnect_token: String = "") -> Variant:
	var room: Room = rooms.get(code)
	if room == null:
		return NetProtocol.ERROR_ROOM_NOT_FOUND

	if not reconnect_token.is_empty():
		var slot_index := room.find_slot_by_reconnect_token(reconnect_token)
		if slot_index != -1:
			room.mark_slot_reconnected(slot_index, peer_id)
			peer_room[peer_id] = code
			return room

	if not room.accepts_lobby_actions():
		return NetProtocol.ERROR_ROOM_FULL

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
	if not room.accepts_lobby_actions():
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
##
## 2-6(§6)/2-6B(재대전) - `voluntary`가 그 사람이 스스로 나간 것인지
## (`leave()`, 언제든 즉시 완전히 비움) 아니면 뜻하지 않게 끊긴 것인지를
## 가른다. 뜻하지 않게 끊겼고 방이 TRANSFERRING/IN_GAME/REMATCHING이면
## 슬롯을 비우지 않고 재접속 유예로 넘긴다(`Room.mark_slot_disconnected()`) -
## REMATCHING(재대전 대기)도 포함한 이유는 "연결이 끊기면 슬롯을 살려둔다"는
## 원칙을 상태마다 다르게 두지 않기 위함이다(2-6B 설계 확정 - "언제
## 포기하는지"는 방 전체의 재대전 대기 시간(`Room.rematch_deadline_msec`)
## 하나로 판단하므로, 여기서 그레이스를 주는 것과 실제로 언제 내보내는지는
## 별개다). 그래서 그 경우엔 `is_empty()`가 false로 남아 방이 안 지워진다.
## `now_msec`은 Room이 시계를 직접 안 재도록(헤드리스 테스트에서 시간을
## 흉내낼 수 있게) 호출부(server_main.gd)가 넘긴다.
func remove_peer(peer_id: int, voluntary: bool = true, now_msec: int = 0) -> Dictionary:
	var code = peer_room.get(peer_id)
	peer_room.erase(peer_id)
	if code == null:
		return {"room": null, "slot_index": -1}

	var room: Room = rooms.get(code)
	if room == null:
		return {"room": null, "slot_index": -1}

	var slot_index := room.find_slot_by_peer(peer_id)
	if slot_index == -1:
		return {"room": room, "slot_index": -1}

	var keep_slot_for_reconnect := not voluntary and (room.state == Room.State.TRANSFERRING or room.state == Room.State.IN_GAME or room.state == Room.State.REMATCHING)
	if keep_slot_for_reconnect:
		room.mark_slot_disconnected(slot_index, now_msec)
	else:
		room.vacate_by_peer(peer_id)

	if room.is_empty():
		rooms.erase(code)
		return {"room": null, "slot_index": slot_index}

	return {"room": room, "slot_index": slot_index}


## 2-6B(같은 방에서 재대전) - 서버가 직접 강제로 슬롯을 비운다(재대전
## 대기 시간 초과로 "한 판 더"를 안 누른 사람을 내보낼 때 등 - 그 사람이
## 스스로 leave()를 보낸 게 아니다). `Room.vacate_slot()`만 부르면
## `peer_room`(peer_id -> 방 코드) 매핑이 안 지워져서, 그 사람이 계속
## 연결된 채라면 서버가 "이 peer는 아직 이 방에 있다"고 잘못 알고 있는
## 상태가 남는다 - `remove_peer()`와 같은 이유로 여기서 같이 정리한다.
func force_vacate_slot(room: Room, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= room.slots.size():
		return
	# null을 그대로 Dictionary 타입 변수에 대입하면 그 자리에서 런타임
	# 에러가 나서 바로 다음 줄의 null 검사가 무의미해진다(server_main.gd의
	# _service_rematch_rooms에서 실제로 겪은 함정과 같음) - 원본 배열
	# 원소를 먼저 검사한다.
	if room.slots[slot_index] == null:
		return
	var slot: Dictionary = room.slots[slot_index]
	var peer_id: int = slot["peer_id"]
	room.vacate_slot(slot_index)
	if peer_id != -1:
		peer_room.erase(peer_id)
	if room.is_empty():
		rooms.erase(room.code)


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
