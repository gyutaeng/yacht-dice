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
## 결측 청크 조사(2-5 후속) - "웹은 브라우저 콘솔의 print()를 못 믿는다"(1-5)는
## 이유로 PackTransferClient와 같은 패턴을 쓴다. BuildInfo.DEBUG_MODE가
## 꺼져 있으면 emit 자체를 안 한다.
signal debug_log(text: String)

# 2-4: 실제 게임 진행(docs/multiplayer.md §2.2). state_snapshot은 매번
# 전체 상태를 담고 있어서(§5) OnlineGameController가 read_only GameState에
# 그대로 apply_snapshot()한다. 나머지는 "사건"이라 스냅샷 비교로는
# 재현할 수 없고(§1) 서버가 스냅샷 뒤에 별도로 보낸다 - 클라이언트는 받은
# 순서 그대로(스냅샷 먼저) 처리하기만 하면 된다.
#
# 어떤 GameEvents 시그널이 여기 대응 시그널을 갖는지는
# scripts/net/game_event_relay.gd의 RELAYED_EVENTS가 기준이다(2-4C -
# "게임에서 일어난 사건은 전부 전달한다", 예외는 score_previewed 하나뿐).
signal state_snapshot_received(snapshot: Dictionary)
signal dice_rolled(player_index: int, values: Array[int], rerolls_left: int)
signal die_held_changed(player_index: int, index: int, held: bool)
signal special_hand_rolled(player_index: int, category: int, points: int)
signal score_committed(player_index: int, category: int, points: int)
signal yacht_scored(player_index: int)
signal zero_scored(player_index: int, category: int)
signal bonus_achieved(player_index: int)
signal turn_ended(player_index: int)
signal turn_started(player_index: int)
signal game_ended(winners: Array[int], scores: Array[int])
## GameState.start_turn()이 내는 GameEvents.game_started를 실어 나른다 -
## 로비가 다 찼을 때 오는 game_started(위, player_count만 담김)와는 다른
## 신호다. 이름이 같으면 클라이언트가 게임 시작을 두 번(로비 종료 +
## 이 이벤트) 받아서 인사 연출이 두 번 시작될 뻔했다(2-4C) - 그래서
## 시그널 이름 자체를 다르게 뒀다.
signal game_state_started(player_count: int)

# 2-5(캐릭터 팩 전송) §2단계.
signal transferring_started()
signal pack_upload_requested(hash: String)
signal pack_chunk_received(hash: String, sequence: int, total_chunks: int, data_base64: String)
signal pack_transfer_failed(hash: String, reason: String)
## 결측 청크 재전송(2-5 후속) - 서버가 내 팩의 빠진 순번을 다시 보내달라고
## 전달한다(방 전체 방송이 아니라 소유자인 나에게만 온다).
signal pack_chunks_requested(hash: String, sequences: Array[int])

enum State { IDLE, CONNECTING, AWAITING_HELLO_ACK, CONNECTED }

var _peer := WebSocketMultiplayerPeer.new()
var _state: State = State.IDLE
var _ever_connected := false

# 2-5 전송 버그 수정 - WebSocketMultiplayerPeer의 기본 outbound_buffer_size는
# 65535바이트(직접 확인함)뿐이라, 32KB 청크를 Base64로 감싼 약 43KB짜리
# 메시지 두 개만 같은 프레임에 연달아 보내도 버퍼가 넘친다. put_packet()은
# 이때 크래시하지 않고 조용히 에러 코드만 돌려주는데, 그 반환값을 확인하지
# 않으면 두 번째 청크부터 통째로 사라진다("전체의 2%(청크 1개)에서 멈춘다"는
# 증상의 직접 원인). 그래서 모든 전송을 이 큐를 거치게 하고, 실패하면
# 버리지 않고 다음 프레임에 다시 시도한다 - poll()이 매 프레임 버퍼를
# 비워주므로 결국은 다 나간다. 순서 보장을 위해 큐가 비어있을 때만 즉시
# 전송을 시도하고, 그 외엔 항상 큐 맨 뒤에 붙인다(먼저 넣은 게 항상 먼저 나감).
#
# 각 항목은 {"bytes": PackedByteArray, "on_sent": Callable}이다(2-5 후속 -
# "put_packet에 성공한 시점"과 "큐에 넣은 시점"을 로그에서 구분해달라는
# 요청). on_sent는 그 메시지가 실제로 put_packet()에 성공한 순간(즉시든,
# 나중에 큐에서 빠져나갈 때든) 딱 한 번 호출된다 - 호출부가 이 안에서
# "실제로 나갔다"는 로그를 남긴다. 이 프로젝트에서 "보냈다"를 "도착해서
# 쓸 수 있다"로 착각한 사고가 이미 두 번 있었다(§8.5-1/§8.5-2) - 로그
# 자체가 그 착각을 만들면 다음 사람이 또 같은 실수를 반복한다.
var _outgoing_queue: Array = []

# PROTOCOL_MISMATCH를 받으면 서버가 곧바로 연결을 끊는다(§2.0) - 그 직후의
# 일반적인 disconnected 신호까지 같이 쏘면 UI가 "게임 버전이 다릅니다"
# 메시지를 "연결이 끊어졌습니다" 같은 일반 문구로 덮어써 버릴 수 있어서,
# 이 경우엔 뒤따라오는 disconnected를 한 번 건너뛴다.
var _suppress_next_disconnect := false

# 결측 청크 조사(2-5 후속) - 받는 쪽 버퍼(1MB, 청크 하나당 약 43.8KB라
# 약 23개 여유)에 실제로 얼마나 가까이 갔는지 알아야 다음에 팩이 더
# 커지거나 청크 수가 늘어도 안전한지 판단할 수 있다. PackTransferClient가
# 해시 하나를 받기 시작할 때 reset_peak_available()로 비우고, 끝날 때
# get_peak_available()로 최댓값을 읽어 요약 로그를 남긴다.
var _peak_available := 0


func _log(text: String) -> void:
	if BuildInfo.DEBUG_MODE:
		debug_log.emit(text)


func _process(_delta: float) -> void:
	if _state == State.IDLE:
		return

	_peer.poll()
	_flush_outgoing_queue()
	var status := _peer.get_connection_status()

	if status == MultiplayerPeer.CONNECTION_CONNECTED and _state == State.CONNECTING:
		_state = State.AWAITING_HELLO_ACK
		_ever_connected = true
		# 결측 청크 조사 - 실제 핸드셰이크가 끝난 뒤에도 값이 유지되는지
		# 다시 한번 되읽는다(연결 전 설정이 실제 소켓 생성 시점에 리셋되는
		# 플랫폼별 차이가 있을 수 있어서 두 시점 다 확인).
		_log("연결 완료 후 받는 쪽 버퍼: %d바이트" % _peer.get_inbound_buffer_size())
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

	# 결측 청크 조사(2-5 후속, 사용자 요청 계측) - 이 프레임에 큐에 쌓여
	# 있던 개수와 실제로 꺼낸 개수를 그대로 찍는다(정상이어도 찍음 -
	# "대기==꺼냄"이 매번 성립하는 것 자체가 while 루프에는 문제가 없다는
	# 증거이고, 그런데도 청크가 사라진다면 문제는 이 지점 아래(엔진/전송
	# 계층이거나 아래 decode 실패 쪽)에 있다는 뜻이다). 대기가 0인 프레임은
	# 로그가 넘치므로 건너뛴다.
	var available := _peer.get_available_packet_count()
	_peak_available = maxi(_peak_available, available)
	var drained := 0
	while _peer.get_available_packet_count() > 0:
		_handle_packet(_peer.get_packet())
		drained += 1
	if available > 0:
		_log("프레임 %d: 대기 %d개 → %d개 꺼냄" % [Engine.get_process_frames(), available, drained])


func connect_to_server(url: String) -> void:
	_reset()
	# 결측 청크 조사(2-5 후속, 사용자 가설 검증) - create_client() 전에
	# 설정해야 반영된다(네이티브에서 직접 확인함 - 연결 후에 바꾸면 이미
	# 진행 중인 연결엔 적용 안 될 수 있음). 실제로 반영됐는지는 곧바로
	# get_inbound_buffer_size()로 되읽어 로그로 남긴다 - 웹에서 이 설정
	# 자체가 무시될 수 있다는 가능성까지 포함해서 확인하기 위함이다.
	_peer.set_inbound_buffer_size(NetProtocol.CLIENT_INBOUND_BUFFER_BYTES)
	_log("받는 쪽 버퍼 설정: 요청 %d바이트 → 실제 %d바이트(get_inbound_buffer_size() 되읽음)" % [NetProtocol.CLIENT_INBOUND_BUFFER_BYTES, _peer.get_inbound_buffer_size()])

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


func request_character_pack(owner_index: int) -> void:
	_send(NetProtocol.MSG_REQUEST_CHARACTER_PACK, {"owner_index": owner_index})


## 반환값(bool)은 즉시 전송됐는지(true) 아니면 큐에 들어갔는지(false)다 -
## 호출부가 "큐 적재" 로그를 남기고 싶을 때 참고한다. 실제 "전송 완료"
## 확인은 반환값이 아니라 on_sent 콜백으로 한다(즉시든 나중이든 정확히
## 그 순간에 한 번만 불림).
func upload_pack_chunk(hash: String, sequence: int, total_chunks: int, total_bytes: int, data_base64: String, on_sent: Callable = Callable()) -> bool:
	return _send(NetProtocol.MSG_UPLOAD_PACK_CHUNK, {"hash": hash, "sequence": sequence, "total_chunks": total_chunks, "total_bytes": total_bytes, "data": data_base64}, on_sent)


func send_pack_ready() -> void:
	_send(NetProtocol.MSG_PACK_READY, {})


## 결측 청크 재전송(2-5 후속) - 빠진 순번을 지정해서 다시 보내달라고
## 요청한다. 서버가 요청 횟수 상한을 독립적으로 강제하므로(원칙 6) 여기서는
## 그대로 전송만 한다 - 상한은 호출부(PackTransferClient)가 미리 확인한다.
func request_pack_chunks(hash: String, sequences: Array[int]) -> void:
	_send(NetProtocol.MSG_REQUEST_PACK_CHUNKS, {"hash": hash, "sequences": sequences})


func close() -> void:
	_reset()


func _reset() -> void:
	_peer.close()
	_peer = WebSocketMultiplayerPeer.new()
	_state = State.IDLE
	_ever_connected = false
	_suppress_next_disconnect = false
	_outgoing_queue.clear()


## 지금 보내기 대기 중인 메시지 수 - 진단 로그용(PackTransferClient가
## "청크 N을 대기열에 넣음" 같은 문구를 만들 때 참고).
func get_outgoing_queue_size() -> int:
	return _outgoing_queue.size()


## 결측 청크 조사(2-5 후속) - 마지막으로 비운 뒤 관찰된 "대기 개수"의
## 최댓값. 받는 쪽 버퍼가 실제로 얼마나 여유 있었는지 판단하는 용도라
## 값을 지우지 않고 그대로 돌려준다(호출부가 필요할 때 reset_peak_available()
## 로 직접 비운다).
func get_peak_available() -> int:
	return _peak_available


func reset_peak_available() -> void:
	_peak_available = 0


## 반환값(bool)은 즉시 put_packet()에 성공했는지다 - 큐에 들어갔으면 false.
## on_sent가 유효하면, 실제로 put_packet()에 성공하는 그 순간(여기서
## 즉시든, _flush_outgoing_queue()에서 나중이든) 딱 한 번 호출한다.
func _send(type: String, payload: Dictionary, on_sent: Callable = Callable()) -> bool:
	if _state == State.IDLE or _state == State.CONNECTING:
		return false

	var bytes := NetProtocol.encode(type, payload)
	if not _outgoing_queue.is_empty():
		_outgoing_queue.append({"bytes": bytes, "on_sent": on_sent})
		return false

	if _peer.put_packet(bytes) != OK:
		_outgoing_queue.append({"bytes": bytes, "on_sent": on_sent})
		return false

	if on_sent.is_valid():
		on_sent.call()
	return true


func _flush_outgoing_queue() -> void:
	while not _outgoing_queue.is_empty():
		var entry: Dictionary = _outgoing_queue[0]
		if _peer.put_packet(entry["bytes"]) != OK:
			break
		_outgoing_queue.pop_front()
		var on_sent: Callable = entry.get("on_sent", Callable())
		if on_sent.is_valid():
			on_sent.call()


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
		# 결측 청크 조사(2-5 후속) - 지금까지 이 실패는 완전히 조용했다.
		# get_available_packet_count()/get_packet()은 이 패킷을 정상적으로
		# 꺼낸 것으로 집계되므로, 위 "대기 N개 → N개 꺼냄" 로그만으로는 이
		# 지점에서 버려지는 걸 못 잡는다 - 바이트가 손상/절단된 채 도착하면
		# (JSON 파싱 실패) 여기서 아무 흔적도 안 남기고 사라졌다.
		_log("[경고] 디코드 실패로 패킷 버림(%d바이트) - JSON 파싱 실패이거나 필드 누락. 바이트 앞부분: %s" % [bytes.size(), bytes.slice(0, mini(bytes.size(), 60)).get_string_from_utf8()])
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
		NetProtocol.MSG_DIE_HELD_CHANGED:
			die_held_changed.emit(int(payload.get("player_index", -1)), int(payload.get("index", -1)), bool(payload.get("held", false)))
		NetProtocol.MSG_SPECIAL_HAND_ROLLED:
			special_hand_rolled.emit(int(payload.get("player_index", -1)), int(payload.get("category", -1)), int(payload.get("points", 0)))
		NetProtocol.MSG_SCORE_COMMITTED:
			score_committed.emit(int(payload.get("player_index", -1)), int(payload.get("category", -1)), int(payload.get("points", 0)))
		NetProtocol.MSG_YACHT_SCORED:
			yacht_scored.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_ZERO_SCORED:
			zero_scored.emit(int(payload.get("player_index", -1)), int(payload.get("category", -1)))
		NetProtocol.MSG_BONUS_ACHIEVED:
			bonus_achieved.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_TURN_ENDED:
			turn_ended.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_TURN_STARTED:
			turn_started.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_GAME_ENDED:
			game_ended.emit(_to_int_array(payload.get("winners", [])), _to_int_array(payload.get("scores", [])))
		NetProtocol.MSG_GAME_STATE_STARTED:
			game_state_started.emit(int(payload.get("player_count", 0)))
		NetProtocol.MSG_TRANSFERRING_STARTED:
			transferring_started.emit()
		NetProtocol.MSG_PACK_UPLOAD_REQUESTED:
			pack_upload_requested.emit(str(payload.get("hash", "")))
		NetProtocol.MSG_PACK_CHUNK:
			pack_chunk_received.emit(str(payload.get("hash", "")), int(payload.get("sequence", -1)), int(payload.get("total_chunks", 0)), str(payload.get("data", "")))
		NetProtocol.MSG_PACK_TRANSFER_FAILED:
			pack_transfer_failed.emit(str(payload.get("hash", "")), str(payload.get("reason", "")))
		NetProtocol.MSG_PACK_CHUNKS_REQUESTED:
			pack_chunks_requested.emit(str(payload.get("hash", "")), _to_int_array(payload.get("sequences", [])))
		NetProtocol.MSG_ERROR:
			var code := str(payload.get("code", ""))
			if code == NetProtocol.ERROR_PROTOCOL_MISMATCH:
				_suppress_next_disconnect = true
			server_error.emit(code, str(payload.get("message", "")))
