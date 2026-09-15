class_name GameClient
extends Node

# 클라이언트 쪽 WebSocketMultiplayerPeer + 프로토콜 상태 기계. UI(온라인
# 화면)는 이 노드의 시그널만 구독한다 - GameEvents 패턴과 같은 이유로,
# 방출자(이 클래스)는 구독자를 몰라야 한다.
#
# 게임 진행 메시지(request_roll 등)는 2-4에서 추가한다 - 이번 단계는
# 연결/방 관리 메시지까지만 다룬다.

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
		NetProtocol.MSG_ERROR:
			var code := str(payload.get("code", ""))
			if code == NetProtocol.ERROR_PROTOCOL_MISMATCH:
				_suppress_next_disconnect = true
			server_error.emit(code, str(payload.get("message", "")))
