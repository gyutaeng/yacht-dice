class_name Room
extends RefCounted

# 방 하나 = GameState 인스턴스 하나 + 참가자 슬롯 + 로비 상태 기계
# (docs/multiplayer.md §1, §3). RoomManager가 코드로 찾아 라우팅하는
# 대상일 뿐, 네트워크(WebSocketMultiplayerPeer)는 전혀 모른다 - GameState가
# UI를 모르는 것과 같은 이유로, 헤드리스에서 그대로 테스트할 수 있게 하기
# 위함이다.

enum State { LOBBY, TRANSFERRING, IN_GAME, ENDED }

const RECONNECT_TOKEN_BYTES := 24

var code: String
var capacity: int
var state: State = State.LOBBY
var rng: RandomNumberGenerator
var game_state: GameState

# slots[i]는 i번 자리가 비어 있으면 null, 차 있으면
# {peer_id:int, meta:Dictionary, ready:bool, reconnect_token:String}.
# 길이는 항상 capacity와 같다 - set_player_count로 늘어나면 뒤에 null을
# 채우고, 줄어들면 뒤쪽의 빈 자리만 잘라낸다(_resize_slots 참고).
var slots: Array = []


func _init(room_code: String, player_count: int) -> void:
	code = room_code
	capacity = player_count
	rng = RandomNumberGenerator.new()
	rng.seed = SecureRandom.generate_seed()
	game_state = GameState.new(player_count, rng)
	slots.resize(player_count)


## 현재 채워진 슬롯 중 가장 낮은 인덱스를 방장으로 취급한다(문서에 명시가
## 없어 직접 정한 규칙 - 0번이 나가면 다음 사람이 자동으로 방장이 된다).
## 아무도 없으면 -1(방이 곧 정리될 상황이라 호출부가 미리 방어해야 함).
func host_index() -> int:
	for i in slots.size():
		if slots[i] != null:
			return i
	return -1


func is_full() -> bool:
	for slot in slots:
		if slot == null:
			return false
	return true


func occupied_count() -> int:
	var count := 0
	for slot in slots:
		if slot != null:
			count += 1
	return count


func is_empty() -> bool:
	return occupied_count() == 0


## 빈 자리 중 가장 낮은 인덱스에 peer_id를 앉히고 그 슬롯 인덱스를
## 돌려준다. 자리가 없으면 -1(호출부가 join 전에 is_full()로 미리 걸러야
## 하지만, 방어적으로 한 번 더 확인).
func seat_player(peer_id: int) -> int:
	for i in slots.size():
		if slots[i] == null:
			var token := Crypto.new().generate_random_bytes(RECONNECT_TOKEN_BYTES).hex_encode()
			slots[i] = {"peer_id": peer_id, "meta": {}, "ready": false, "reconnect_token": token}
			return i
	return -1


## 로비 중 leave/연결 끊김 - 그 슬롯을 완전히 비워서 다음 join_room이 채울
## 수 있게 한다(§3). 게임이 시작된 뒤(§6, 슬롯 유지+AFK)의 정교한 처리는
## 2-6 범위다 - 지금은 크래시만 안 나게 슬롯을 비우는 정도로 단순 처리한다.
func vacate_by_peer(peer_id: int) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["peer_id"] == peer_id:
			slots[i] = null
			return i
	return -1


func find_slot_by_peer(peer_id: int) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["peer_id"] == peer_id:
			return i
	return -1


func all_ready() -> bool:
	if not is_full():
		return false
	for slot in slots:
		if not slot["ready"]:
			return false
	return true


## 방장이 로비에서 인원수를 바꿀 때 부른다(set_player_count). 이미 들어온
## 인원보다 낮게는 호출부가 미리 막아야 한다(여기서는 방어적으로만 재확인).
## GameState._init()은 생성 시점에 주사위를 굴리지 않으므로(roll()을 실제로
## 부르기 전까지 RNG를 소모하지 않음), 같은 rng를 재사용해 새로 만들어도
## "방마다 시드를 한 번만 뽑는다"는 원칙이 깨지지 않는다.
func change_capacity(new_capacity: int) -> bool:
	if new_capacity < occupied_count():
		return false

	if new_capacity > slots.size():
		slots.resize(new_capacity)
	elif new_capacity < slots.size():
		slots = slots.slice(0, new_capacity)

	capacity = new_capacity
	game_state = GameState.new(new_capacity, rng)
	return true


## 턴 기반 요청(request_roll/hold/score) 검증 - docs/multiplayer.md §4.
## 네트워크를 몰라야 하므로(RoomManager와 같은 이유) 순수 로직으로 두고
## 빈 문자열(통과) 또는 NetProtocol 에러 코드 문자열을 돌려준다.
## server_main.gd는 이 결과만 보고 error 메시지를 만들거나 실제 GameState
## 메서드를 부른다.
func _validate_turn(peer_id: int) -> String:
	if state != State.IN_GAME or game_state.game_over:
		return NetProtocol.ERROR_NOT_IN_GAME
	if find_slot_by_peer(peer_id) != game_state.current_player:
		return NetProtocol.ERROR_NOT_YOUR_TURN
	return ""


func validate_roll(peer_id: int) -> String:
	var turn_error := _validate_turn(peer_id)
	if turn_error != "":
		return turn_error
	if game_state.rolls_left <= 0:
		return NetProtocol.ERROR_INVALID_ARGUMENT
	return ""


## has_rolled 검사는 1-3B에서 첫 굴림을 플레이어가 직접 하도록 바꾼 것과
## 짝을 이룬다 - 굴리기 전에는 고정할 주사위 값 자체가 없다.
func validate_hold(peer_id: int, index: int) -> String:
	var turn_error := _validate_turn(peer_id)
	if turn_error != "":
		return turn_error
	if index < 0 or index >= game_state.dice_results.size():
		return NetProtocol.ERROR_INVALID_ARGUMENT
	if not game_state.has_rolled:
		return NetProtocol.ERROR_INVALID_ARGUMENT
	return ""


func validate_score(peer_id: int, category: int) -> String:
	var turn_error := _validate_turn(peer_id)
	if turn_error != "":
		return turn_error
	if category < 0 or category >= GameState.CATEGORY_NAMES.size():
		return NetProtocol.ERROR_INVALID_ARGUMENT
	if not game_state.has_rolled:
		return NetProtocol.ERROR_INVALID_ARGUMENT
	var slot_index := find_slot_by_peer(peer_id)
	if game_state.is_category_confirmed(slot_index, category):
		return NetProtocol.ERROR_INVALID_ARGUMENT
	return ""


## 참가자 목록을 room_joined 응답의 players 필드 형태로 만든다
## (docs/multiplayer.md §2.2: Array[{player_index, meta, ready}]).
func players_summary() -> Array:
	var summary := []
	for i in slots.size():
		if slots[i] != null:
			summary.append({"player_index": i, "meta": slots[i]["meta"], "ready": slots[i]["ready"]})
	return summary
