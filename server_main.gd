extends Node

# 온라인 멀티플레이 전용 서버 진입점(docs/multiplayer.md, 2-3). 실행:
#
#   godot --headless --path . res://server_main.tscn -- <포트>
#
# 포트는 CLI 인자(생략 가능) -> YACHT_DICE_PORT 환경변수 -> 기본값 8910
# 순서로 정해진다.
#
# 2-1에서 이 파일은 GameState 하나를 콘솔 명령(roll/hold/score/...)으로
# 조종하는 headless 검증 도구였다. 이제 실제 서버를 붙이므로 그 REPL은
# 완전히 대체됐다 - OS.read_string_from_stdin()은 블로킹이라 _process()
# 안에서 폴링해야 하는 서버 루프와 같이 쓸 수 없다(2-1에서 실측 확인).
# 그래서 서버 종료는 콘솔 명령이 아니라 프로세스를 직접 끊는 방식(Ctrl+C)이다.
#
# 이 파일은 "패킷을 받아서 RoomManager를 부르고 결과를 다시 패킷으로
# 보낸다"는 배선 역할만 한다 - 방/참가자 상태를 직접 들고 있지 않는다
# (RoomManager/Room이 네트워크를 몰라야 헤드리스로 테스트할 수 있으므로).

const DEFAULT_PORT := 8910
const PORT_ENV_VAR := "YACHT_DICE_PORT"

var peer := WebSocketMultiplayerPeer.new()
var room_manager := RoomManager.new()

# hello 확인 전인 접속을 추적한다 - 5초 안에 hello가 안 오면 끊는다(§2.0).
var _pending_since: Dictionary = {}  # peer_id -> Time.get_ticks_msec()
var _hello_confirmed: Dictionary = {}  # peer_id -> true

# GameEvents 릴레이(2-4) - 서버 프로세스 전체에 GameEvents 인스턴스가
# 하나뿐이라 방마다 새로 구독하지 않는다. 지금 처리 중인 요청이 어느
# 방 것인지는 _active_room으로 표시하고, 그 방을 처리하는 동안 emit된
# 사건만 _pending_events에 쌓았다가 스냅샷을 보낸 "다음에" 방송한다
# (docs/multiplayer.md §1 - 스냅샷을 먼저 적용한 뒤에 이벤트를 방출해야
# 보이스 핸들러가 낡은 상태를 안 읽는다).
var _active_room: Room = null
var _pending_events: Array = []


func _ready() -> void:
	GameEvents.dice_rolled.connect(_on_ge_dice_rolled)
	GameEvents.special_hand_rolled.connect(_on_ge_special_hand_rolled)
	GameEvents.bonus_achieved.connect(_on_ge_bonus_achieved)
	GameEvents.zero_scored.connect(_on_ge_zero_scored)
	GameEvents.turn_started.connect(_on_ge_turn_started)
	GameEvents.game_ended.connect(_on_ge_game_ended)
	_start_server()


func _start_server() -> void:
	var port := _resolve_port()
	var err := peer.create_server(port)
	if err != OK:
		printerr("[서버] %d번 포트에서 시작할 수 없습니다 (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return

	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)

	print("=== 요트다이스 서버 시작 (포트 %d) ===" % port)


func _process(_delta: float) -> void:
	peer.poll()

	var now := Time.get_ticks_msec()
	for id in _pending_since.keys():
		if now - _pending_since[id] > NetProtocol.HELLO_TIMEOUT_SECONDS * 1000.0:
			print("[서버] peer %d: %.0f초 안에 hello가 안 와서 연결 종료" % [id, NetProtocol.HELLO_TIMEOUT_SECONDS])
			_pending_since.erase(id)
			peer.disconnect_peer(id)

	while peer.get_available_packet_count() > 0:
		var sender_id := peer.get_packet_peer()
		var bytes := peer.get_packet()
		_handle_packet(sender_id, bytes)


func _resolve_port() -> int:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0].is_valid_int():
		return args[0].to_int()

	var env_value := OS.get_environment(PORT_ENV_VAR)
	if env_value != "" and env_value.is_valid_int():
		return env_value.to_int()

	return DEFAULT_PORT


func _on_peer_connected(id: int) -> void:
	print("[서버] 접속: peer %d" % id)
	_pending_since[id] = Time.get_ticks_msec()


func _on_peer_disconnected(id: int) -> void:
	print("[서버] 연결 해제: peer %d" % id)
	_pending_since.erase(id)
	_hello_confirmed.erase(id)
	_remove_peer_and_notify(id, "disconnected")


## 메시지 크기 상한(§2.0)을 넘으면 내용을 해석하지 않고 끊는다 - 다만 저수준
## 패킷 API 특성상 바이트 자체는 이미 peer.get_packet()으로 받은 뒤다(더
## 작은 크기를 미리 알아낼 방법이 없다). "해석하지 않는다"는 JSON으로
## 파싱해 필드를 들여다보지 않는다는 뜻이다.
func _handle_packet(sender_id: int, bytes: PackedByteArray) -> void:
	if bytes.size() > NetProtocol.MAX_MESSAGE_BYTES:
		print("[서버] peer %d: 메시지 크기 초과(%d바이트) - 연결 종료" % [sender_id, bytes.size()])
		peer.disconnect_peer(sender_id)
		return

	var msg = NetProtocol.decode(bytes)
	if msg == null:
		print("[서버] peer %d: 메시지 형식이 올바르지 않음 - 연결 종료" % sender_id)
		peer.disconnect_peer(sender_id)
		return

	var type: String = msg["type"]
	var payload: Dictionary = msg["payload"]

	if not _hello_confirmed.get(sender_id, false):
		if type != NetProtocol.MSG_HELLO:
			print("[서버] peer %d: hello 전에 다른 메시지(%s) 수신 - 연결 종료" % [sender_id, type])
			peer.disconnect_peer(sender_id)
			return
		_handle_hello(sender_id, payload)
		return

	match type:
		NetProtocol.MSG_CREATE_ROOM:
			_handle_create_room(sender_id, payload)
		NetProtocol.MSG_JOIN_ROOM:
			_handle_join_room(sender_id, payload)
		NetProtocol.MSG_SELECT_CHARACTER:
			_handle_select_character(sender_id, payload)
		NetProtocol.MSG_READY:
			_handle_ready(sender_id, payload)
		NetProtocol.MSG_SET_PLAYER_COUNT:
			_handle_set_player_count(sender_id, payload)
		NetProtocol.MSG_LEAVE:
			_handle_leave(sender_id, payload)
		NetProtocol.MSG_REQUEST_ROLL:
			_handle_request_roll(sender_id, payload)
		NetProtocol.MSG_REQUEST_HOLD:
			_handle_request_hold(sender_id, payload)
		NetProtocol.MSG_REQUEST_SCORE:
			_handle_request_score(sender_id, payload)
		NetProtocol.MSG_HELLO:
			pass  # 이미 확인된 접속이 다시 보내면 그냥 무시한다.
		_:
			_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "알 수 없는 메시지 타입입니다: %s" % type)


func _handle_hello(sender_id: int, payload: Dictionary) -> void:
	var version = payload.get("protocol_version")
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		print("[서버] peer %d: hello에 protocol_version이 없거나 잘못됨 - 연결 종료" % sender_id)
		peer.disconnect_peer(sender_id)
		return

	if int(version) != NetProtocol.PROTOCOL_VERSION:
		print("[서버] peer %d: 버전 불일치(받음=%s, 서버=%d) - 연결 종료" % [sender_id, version, NetProtocol.PROTOCOL_VERSION])
		_send_error(sender_id, NetProtocol.ERROR_PROTOCOL_MISMATCH, "게임 버전이 다릅니다. 새로고침해 주세요.")
		peer.disconnect_peer(sender_id)
		return

	_hello_confirmed[sender_id] = true
	_pending_since.erase(sender_id)
	_send(sender_id, NetProtocol.MSG_HELLO_ACK, {"protocol_version": NetProtocol.PROTOCOL_VERSION})


func _handle_create_room(sender_id: int, payload: Dictionary) -> void:
	if room_manager.get_room_for_peer(sender_id) != null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "이미 방에 들어가 있습니다.")
		return

	var count = _payload_int(payload, "player_count")
	if count == null or not RoomManager.is_valid_player_count(count):
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "인원수는 2~4명 사이여야 합니다.")
		return

	var room := room_manager.create_room(count, sender_id)
	print("[서버] 방 생성: %s (인원 %d, 만든 사람 peer %d)" % [room.code, count, sender_id])

	var slot: Dictionary = room.slots[0]
	_send(sender_id, NetProtocol.MSG_ROOM_CREATED, {
		"code": room.code,
		"player_count": room.capacity,
		"reconnect_token": slot["reconnect_token"],
	})


## reconnect_token이 페이로드에 와도(§2.1 join_room 선택 필드) 2-3 범위에서는
## 아직 검증하지 않는다 - 실제 재접속 매칭은 2-6에서 구현한다. 지금은 토큰
## 유무와 무관하게 항상 새 참가자로 처리한다.
func _handle_join_room(sender_id: int, payload: Dictionary) -> void:
	if room_manager.get_room_for_peer(sender_id) != null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "이미 방에 들어가 있습니다.")
		return

	var code = payload.get("code")
	if typeof(code) != TYPE_STRING or code.is_empty():
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "방 코드가 필요합니다.")
		return

	var result = room_manager.join_room(code, sender_id)
	if result is String:
		_send_error(sender_id, result, _join_error_message(result))
		return

	var room: Room = result
	var my_index := room.find_slot_by_peer(sender_id)
	var my_slot: Dictionary = room.slots[my_index]
	print("[서버] 방 %s 참가: peer %d (슬롯 %d)" % [room.code, sender_id, my_index])

	_send(sender_id, NetProtocol.MSG_ROOM_JOINED, {
		"players": room.players_summary(),
		"my_index": my_index,
		"reconnect_token": my_slot["reconnect_token"],
		# 문서(§2.2)의 room_joined 페이로드엔 없던 필드다 - 클라이언트가
		# "인원 N/M"을 그리려면 목표 인원(capacity)을 알아야 하는데
		# players 배열(현재 참가자)만으로는 알 수 없어서 추가했다. 기본값
		# 있는 선택적 필드 추가라 §2.0 규칙상 버전을 안 올려도 된다.
		"player_count": room.capacity,
	})
	_broadcast_room(room, NetProtocol.MSG_PLAYER_JOINED, {"player_index": my_index, "meta": {}}, sender_id)


func _join_error_message(code: String) -> String:
	match code:
		NetProtocol.ERROR_ROOM_NOT_FOUND:
			return "그런 방을 찾을 수 없습니다."
		NetProtocol.ERROR_ROOM_FULL:
			return "방이 꽉 찼습니다."
		NetProtocol.ERROR_GAME_ALREADY_STARTED:
			return "이미 게임이 시작된 방입니다."
		_:
			return "방에 들어갈 수 없습니다."


func _handle_select_character(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return
	if room.state != Room.State.LOBBY:
		_send_error(sender_id, NetProtocol.ERROR_GAME_ALREADY_STARTED, "이미 게임이 시작되어 캐릭터를 바꿀 수 없습니다.")
		return

	var meta = payload.get("meta")
	if typeof(meta) != TYPE_DICTIONARY:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "캐릭터 정보 형식이 올바르지 않습니다.")
		return

	# v1은 id/display_name만 의미 있게 쓴다(docs/multiplayer.md §8) - 그 외
	# 필드가 와도 무시한다. display_name은 클라이언트가 뭘 보냈든 신뢰하지
	# 않는다(원칙 6) - 남의 화면에 그대로 뜨는 값이라 클라이언트 쪽 검사만
	# 믿으면 안 된다. 제어문자 제거·길이 제한은 NetProtocol에 클라이언트와
	# 공유하는 기준으로 정의되어 있고, 정리 후 빈 문자열이면(제어문자만
	# 보냈거나 공백뿐이었으면) 서버가 슬롯 번호로 기본값을 만든다.
	var slot_index := room.find_slot_by_peer(sender_id)
	var display_name := NetProtocol.sanitize_display_name(str(meta.get("display_name", "")))
	if display_name.is_empty():
		display_name = "플레이어 %d" % (slot_index + 1)
	var safe_meta := {"id": str(meta.get("id", "")), "display_name": display_name}

	room.slots[slot_index]["meta"] = safe_meta
	_broadcast_room(room, NetProtocol.MSG_PLAYER_CHARACTER, {"player_index": slot_index, "meta": safe_meta})


func _handle_ready(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return
	if room.state != Room.State.LOBBY:
		_send_error(sender_id, NetProtocol.ERROR_GAME_ALREADY_STARTED, "이미 게임이 시작되었습니다.")
		return

	var ready_value = payload.get("ready")
	if typeof(ready_value) != TYPE_BOOL:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "ready 값이 올바르지 않습니다.")
		return

	var slot_index := room.find_slot_by_peer(sender_id)
	room.slots[slot_index]["ready"] = ready_value
	_broadcast_room(room, NetProtocol.MSG_PLAYER_READY_CHANGED, {"player_index": slot_index, "ready": ready_value})

	_maybe_start_game(room)


func _handle_set_player_count(sender_id: int, payload: Dictionary) -> void:
	var count = _payload_int(payload, "player_count")
	if count == null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "인원수 값이 올바르지 않습니다.")
		return

	var result = room_manager.set_player_count(sender_id, count)
	if result != null:
		_send_error(sender_id, result, _set_player_count_error_message(result))
		return

	var room := room_manager.get_room_for_peer(sender_id)
	_broadcast_room(room, NetProtocol.MSG_ROOM_PLAYER_COUNT_CHANGED, {"player_count": room.capacity})
	_maybe_start_game(room)


func _set_player_count_error_message(code: String) -> String:
	match code:
		NetProtocol.ERROR_ROOM_NOT_FOUND:
			return "방에 들어가 있지 않습니다."
		NetProtocol.ERROR_GAME_ALREADY_STARTED:
			return "이미 게임이 시작되었습니다."
		NetProtocol.ERROR_NOT_HOST:
			return "방장만 인원수를 바꿀 수 있습니다."
		NetProtocol.ERROR_INVALID_ARGUMENT:
			return "인원수는 2~4명, 이미 들어온 인원보다는 낮출 수 없습니다."
		_:
			return "인원수를 바꿀 수 없습니다."


func _handle_leave(sender_id: int, _payload: Dictionary) -> void:
	_remove_peer_and_notify(sender_id, "left")


func _remove_peer_and_notify(peer_id: int, reason: String) -> void:
	var result := room_manager.remove_peer(peer_id)
	var room = result["room"]
	var slot_index: int = result["slot_index"]
	if room != null and slot_index != -1:
		_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": slot_index, "reason": reason})


## 정원이 다 차고 전원이 준비되면 자동 시작한다(§3). v1은 transferring에서
## 실제로 전송할 캐릭터 자산이 없으므로(§8) 상태 기계를 거치되 즉시
## 통과한다. game_started 다음에 game_state.start_turn()을 실제로 호출해서
## 첫 턴을 연다 - 이게 없으면 turn_started(0)도 안 나가고 첫 스냅샷도
## "아무것도 시작 안 한" 상태로 나간다.
func _maybe_start_game(room: Room) -> void:
	if room.state != Room.State.LOBBY or not room.all_ready():
		return

	room.state = Room.State.TRANSFERRING
	room.state = Room.State.IN_GAME
	print("[서버] 방 %s 게임 시작 (인원 %d)" % [room.code, room.capacity])
	_broadcast_room(room, NetProtocol.MSG_GAME_STARTED, {"player_count": room.capacity})

	_mutate_and_broadcast(room, func(): room.game_state.start_turn())


func _handle_request_roll(sender_id: int, _payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return

	var err := room.validate_roll(sender_id)
	if err != "":
		_send_error(sender_id, err, _turn_error_message(err, "리롤 횟수를 모두 사용했습니다."))
		return

	_mutate_and_broadcast(room, func(): room.game_state.roll())


func _handle_request_hold(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return

	var index = _payload_int(payload, "index")
	if index == null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "주사위 번호가 올바르지 않습니다.")
		return

	var err := room.validate_hold(sender_id, index)
	if err != "":
		_send_error(sender_id, err, _turn_error_message(err, "주사위 번호가 올바르지 않거나 아직 굴리지 않았습니다."))
		return

	_mutate_and_broadcast(room, func(): room.game_state.toggle_lock(index))


func _handle_request_score(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return

	var category = _payload_int(payload, "category")
	if category == null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "족보 값이 올바르지 않습니다.")
		return

	var err := room.validate_score(sender_id, category)
	if err != "":
		_send_error(sender_id, err, _turn_error_message(err, "그 칸은 지금 확정할 수 없습니다(이미 확정됐거나 아직 안 굴렸습니다)."))
		return

	_mutate_and_broadcast(room, func(): room.game_state.confirm_category(category))
	if room.game_state.game_over:
		room.state = Room.State.ENDED


func _turn_error_message(code: String, invalid_argument_message: String) -> String:
	match code:
		NetProtocol.ERROR_NOT_IN_GAME:
			return "게임이 진행 중이 아닙니다."
		NetProtocol.ERROR_NOT_YOUR_TURN:
			return "당신의 턴이 아닙니다."
		NetProtocol.ERROR_INVALID_ARGUMENT:
			return invalid_argument_message
		_:
			return "요청을 처리할 수 없습니다."


## mutate가 room.game_state를 실제로 진행시키는 동안 emit되는 GameEvents
## 6종(_on_ge_*)을 _pending_events에 모았다가, 스냅샷을 먼저 보낸 "다음에"
## 순서대로 방송한다(docs/multiplayer.md §1 - 스냅샷 먼저, 이벤트는 그
## 다음). WebSocket은 TCP 기반이라 순서가 보장되므로 클라이언트는 받은
## 순서 그대로 처리하기만 하면 된다.
func _mutate_and_broadcast(room: Room, mutate: Callable) -> void:
	_active_room = room
	_pending_events = []
	mutate.call()
	_active_room = null

	_broadcast_room(room, NetProtocol.MSG_STATE_SNAPSHOT, room.game_state.get_state_snapshot())
	for event in _pending_events:
		_broadcast_room(room, event["type"], event["payload"])
	_pending_events.clear()


func _on_ge_dice_rolled(player_index: int, values: Array, rerolls_left: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_DICE_ROLLED, "payload": {"player_index": player_index, "values": values, "rerolls_left": rerolls_left}})


func _on_ge_special_hand_rolled(player_index: int, category: int, points: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_SPECIAL_HAND_ROLLED, "payload": {"player_index": player_index, "category": category, "points": points}})


func _on_ge_bonus_achieved(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_BONUS_ACHIEVED, "payload": {"player_index": player_index}})


func _on_ge_zero_scored(player_index: int, category: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_ZERO_SCORED, "payload": {"player_index": player_index, "category": category}})


func _on_ge_turn_started(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_TURN_STARTED, "payload": {"player_index": player_index}})


func _on_ge_game_ended(winners: Array, scores: Array) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_GAME_ENDED, "payload": {"winners": winners, "scores": scores}})


func _payload_int(payload: Dictionary, key: String) -> Variant:
	if not payload.has(key):
		return null
	var value = payload[key]
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return null
	return int(value)


## 방 전원에게 알리는 도중(_broadcast_room) 그중 한 명의 연결이 이미
## 끊긴 상태일 수 있다(예: 한 방의 두 참가자가 거의 동시에 나가면, 한쪽을
## 정리하며 보내는 알림이 이미 닫히는 중인 다른 쪽으로 갈 수 있음) - 실제로
## 수동 테스트 중 발견했다. 크래시는 아니지만(엔진이 ERROR 로그만 남기고
## 계속 진행) 콘솔이 지저분해지므로, 보내기 전에 그 peer의 소켓이 아직
## 열려 있는지 먼저 확인한다.
func _send(peer_id: int, type: String, payload: Dictionary) -> void:
	var ws_peer := peer.get_peer(peer_id)
	if ws_peer == null or ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.set_target_peer(peer_id)
	peer.put_packet(NetProtocol.encode(type, payload))


func _broadcast_room(room: Room, type: String, payload: Dictionary, exclude_peer_id: int = -1) -> void:
	for slot in room.slots:
		if slot != null and slot["peer_id"] != exclude_peer_id:
			_send(slot["peer_id"], type, payload)


func _send_error(peer_id: int, code: String, message: String) -> void:
	_send(peer_id, NetProtocol.MSG_ERROR, {"code": code, "message": message})
