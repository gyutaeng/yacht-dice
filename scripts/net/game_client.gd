class_name GameClient
extends Node

# 클라이언트 쪽 WebSocketMultiplayerPeer + 프로토콜 상태 기계. UI(온라인
# 화면)는 이 노드의 시그널만 구독한다 - GameEvents 패턴과 같은 이유로,
# 방출자(이 클래스)는 구독자를 몰라야 한다.
#
signal connection_failed(reason: String)
signal hello_acknowledged()
signal room_created(code: String, player_count: int, reconnect_token: String)
signal room_joined(players: Array, my_index: int, reconnect_token: String, player_count: int)
signal player_joined(player_index: int, meta: Dictionary)
signal player_character_changed(player_index: int, meta: Dictionary)
signal player_ready_changed(player_index: int, ready: bool)
signal room_player_count_changed(player_count: int)
signal player_left(player_index: int, reason: String)
signal game_started(player_count: int)
signal server_error(code: String, message: String)
signal disconnected()

# 2-4: 실제 게임 진행(docs/multiplayer.md §2.2). state_snapshot은 매번
# 전체 상태를 담고 있어서(§5) OnlineGameController가 read_only GameState에
# 그대로 apply_snapshot()한다. 나머지 6개는 "사건"이라 스냅샷 비교로는
# 재현할 수 없고(§1) 서버가 스냅샷 뒤에 별도로 보낸다 - 클라이언트는 받은
# 순서 그대로(스냅샷 먼저) 처리하기만 하면 된다.
signal state_snapshot_received(snapshot: Dictionary)
signal dice_rolled(player_index: int, values: Array[int], rerolls_left: int)
signal special_hand_rolled(player_index: int, category: int, points: int)
signal bonus_achieved(player_index: int)
signal zero_scored(player_index: int, category: int)
signal turn_started(player_index: int)
signal game_ended(winners: Array[int], scores: Array[int])

enum State { IDLE, CONNECTING, AWAITING_HELLO_ACK, CONNECTED }

var _peer := WebSocketMultiplayerPeer.new()
var _state: State = State.IDLE
var _ever_connected := false

# PROTOCOL_MISMATCH를 받으면 서버가 곧바로 연결을 끊는다(§2.0) - 그 직후의
# 일반적인 disconnected 신호까지 같이 쏘면 UI가 "게임 버전이 다릅니다"
# 메시지를 "연결이 끊어졌습니다" 같은 일반 문구로 덮어써 버릴 수 있어서,
# 이 경우엔 뒤따라오는 disconnected를 한 번 건너뛴다.
var _suppress_next_disconnect := false


func _process(_delta: float) -> void:
	if _state == State.IDLE:
		return

	_peer.poll()
	var status := _peer.get_connection_status()

	if status == MultiplayerPeer.CONNECTION_CONNECTED and _state == State.CONNECTING:
		_state = State.AWAITING_HELLO_ACK
		_ever_connected = true
		_send(NetProtocol.MSG_HELLO, {"protocol_version": NetProtocol.PROTOCOL_VERSION})

	if status == MultiplayerPeer.CONNECTION_DISCONNECTED and _state != State.IDLE:
		var was_ever_connected := _ever_connected
		var suppress := _suppress_next_disconnect
		_reset()
		if suppress:
			pass
		elif was_ever_connected:
			disconnected.emit()
		else:
			connection_failed.emit("서버에 연결할 수 없습니다. 주소를 확인해 주세요.")
		return

	while _peer.get_available_packet_count() > 0:
		_handle_packet(_peer.get_packet())


func connect_to_server(url: String) -> void:
	_reset()
	var err := _peer.create_client(url)
	if err != OK:
		connection_failed.emit("서버 주소가 올바르지 않습니다.")
		return
	_state = State.CONNECTING


func create_room(player_count: int) -> void:
	_send(NetProtocol.MSG_CREATE_ROOM, {"player_count": player_count})


func join_room(code: String) -> void:
	_send(NetProtocol.MSG_JOIN_ROOM, {"code": code})


func select_character(meta: Dictionary) -> void:
	_send(NetProtocol.MSG_SELECT_CHARACTER, {"meta": meta})


func set_ready(ready: bool) -> void:
	_send(NetProtocol.MSG_READY, {"ready": ready})


func set_player_count(player_count: int) -> void:
	_send(NetProtocol.MSG_SET_PLAYER_COUNT, {"player_count": player_count})


func leave() -> void:
	_send(NetProtocol.MSG_LEAVE, {})


func request_roll() -> void:
	_send(NetProtocol.MSG_REQUEST_ROLL, {})


func request_hold(index: int) -> void:
	_send(NetProtocol.MSG_REQUEST_HOLD, {"index": index})


func request_score(category: int) -> void:
	_send(NetProtocol.MSG_REQUEST_SCORE, {"category": category})


func close() -> void:
	_reset()


func _reset() -> void:
	_peer.close()
	_peer = WebSocketMultiplayerPeer.new()
	_state = State.IDLE
	_ever_connected = false
	_suppress_next_disconnect = false


func _send(type: String, payload: Dictionary) -> void:
	if _state == State.IDLE or _state == State.CONNECTING:
		return
	_peer.put_packet(NetProtocol.encode(type, payload))


## GameEvents의 dice_rolled/game_ended는 Array[int]로 타입이 고정돼 있어서
## (autoload/game_events.gd) JSON을 거쳐 float가 된 배열을 그대로 못
## 넘긴다 - 원소 단위로 int()에 통과시켜 진짜 Array[int]를 만든다.
func _to_int_array(raw: Array) -> Array[int]:
	var result: Array[int] = []
	for v in raw:
		result.append(int(v))
	return result


func _handle_packet(bytes: PackedByteArray) -> void:
	var msg = NetProtocol.decode(bytes)
	if msg == null:
		return

	var type: String = msg["type"]
	var payload: Dictionary = msg["payload"]

	match type:
		NetProtocol.MSG_HELLO_ACK:
			_state = State.CONNECTED
			hello_acknowledged.emit()
		NetProtocol.MSG_ROOM_CREATED:
			room_created.emit(payload.get("code", ""), int(payload.get("player_count", 0)), payload.get("reconnect_token", ""))
		NetProtocol.MSG_ROOM_JOINED:
			room_joined.emit(payload.get("players", []), int(payload.get("my_index", -1)), payload.get("reconnect_token", ""), int(payload.get("player_count", 0)))
		NetProtocol.MSG_PLAYER_JOINED:
			player_joined.emit(int(payload.get("player_index", -1)), payload.get("meta", {}))
		NetProtocol.MSG_PLAYER_CHARACTER:
			player_character_changed.emit(int(payload.get("player_index", -1)), payload.get("meta", {}))
		NetProtocol.MSG_PLAYER_READY_CHANGED:
			player_ready_changed.emit(int(payload.get("player_index", -1)), bool(payload.get("ready", false)))
		NetProtocol.MSG_ROOM_PLAYER_COUNT_CHANGED:
			room_player_count_changed.emit(int(payload.get("player_count", 0)))
		NetProtocol.MSG_PLAYER_LEFT:
			player_left.emit(int(payload.get("player_index", -1)), str(payload.get("reason", "")))
		NetProtocol.MSG_GAME_STARTED:
			game_started.emit(int(payload.get("player_count", 0)))
		NetProtocol.MSG_STATE_SNAPSHOT:
			state_snapshot_received.emit(payload)
		NetProtocol.MSG_DICE_ROLLED:
			dice_rolled.emit(int(payload.get("player_index", -1)), _to_int_array(payload.get("values", [])), int(payload.get("rerolls_left", 0)))
		NetProtocol.MSG_SPECIAL_HAND_ROLLED:
			special_hand_rolled.emit(int(payload.get("player_index", -1)), int(payload.get("category", -1)), int(payload.get("points", 0)))
		NetProtocol.MSG_BONUS_ACHIEVED:
			bonus_achieved.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_ZERO_SCORED:
			zero_scored.emit(int(payload.get("player_index", -1)), int(payload.get("category", -1)))
		NetProtocol.MSG_TURN_STARTED:
			turn_started.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_GAME_ENDED:
			game_ended.emit(_to_int_array(payload.get("winners", [])), _to_int_array(payload.get("scores", [])))
		NetProtocol.MSG_ERROR:
			var code := str(payload.get("code", ""))
			if code == NetProtocol.ERROR_PROTOCOL_MISMATCH:
				_suppress_next_disconnect = true
			server_error.emit(code, str(payload.get("message", "")))
