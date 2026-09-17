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

# 2-6(연결 끊김/재접속/턴 타임아웃, docs/multiplayer.md §6).
signal player_reconnected(player_index: int)
## kind는 "turn"(그 슬롯이 지금 턴 제한 카운트다운 중) 또는
## "reconnect"(그 슬롯이 재접속 유예 카운트다운 중).
signal player_timer(player_index: int, kind: String, seconds_left: int)

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

# 데드락 방지 안전장치 2/3(친구 대상 베타 후속) - server_main.gd의 같은
# 필드/함수와 같은 이유(그쪽 주석 참고) - 시작 시점 검사(1/3)가 못 잡는
# 경로까지 대비한 마지막 관측 장치. 서버는 접속마다 별도 큐지만 클라이언트는
# 서버 하나뿐이라 스칼라로 충분하다.
var _outgoing_stall_last_size: int = -1
var _outgoing_stall_last_progress_msec: int = 0
var _outgoing_stall_next_warning_msec: int = 0

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

# 4번/5번 조사(사용자 요청) - Cloudflare 임시 터널이 범인인지 서버 자체
# 문제인지를 나중에 로그 세 개(서버 콘솔/클라이언트 화면 로그/cloudflared
# 창)를 시각으로 맞춰서 가려낼 수 있어야 한다. 서버가 `_last_seen_msec`로
# "마지막으로 뭐든 온 시각"을 재는 것과 같은 개념을 클라이언트에도 둔다.
var _last_received_msec: int = 0
# 핑 간격 계측 - 진짜 왕복 시간(RTT)은 아니다(현재 프로토콜은 서버가 보낸
# ping에 클라이언트가 pong만 돌려줄 뿐, 그 pong이 서버에 도착하기까지 걸린
# 시간을 클라이언트가 알 방법이 없다 - RTT는 서버 쪽에서만 잴 수 있음).
# 대신 "직전 ping으로부터 몇 ms 만에 다음 ping이 왔는가"를 잰다 - 서버는
# PING_INTERVAL_MSEC(5초)마다 보내므로, 이 값이 계속 5000ms 근처면 연결이
# 정상이고 크게 벌어지면(터널이 지연시키거나 끊기기 직전이면) 바로 보인다.
var _last_ping_received_msec: int = -1

# 4번/5번 조사 - close_code/close_reason은 연결이 끊긴 "그 순간"
# (peer_disconnected 시그널)에만 안전하게 읽을 수 있다. _process()에서
# get_connection_status()로 DISCONNECTED를 감지한 시점엔 엔진이 이미
# 내부 peer 목록에서 지워버려 get_peer()가 에러를 낸다(실제로 겪음 -
# "Condition "!peers_map.has(p_id)" is true" 콘솔 에러) - 그래서 신호
# 시점에 미리 캡처해뒀다가 _process()는 이 값만 읽는다.
var _last_close_code: int = -1
var _last_close_reason: String = ""


func _ready() -> void:
	_wire_peer_signals()


func _log(text: String) -> void:
	if BuildInfo.DEBUG_MODE:
		debug_log.emit(text)


## _peer가 (재)생성될 때마다 불러야 한다 - peer_disconnected는 그 순간의
## close_code/close_reason을 놓치지 않고 캡처하는 유일한 지점이다.
func _wire_peer_signals() -> void:
	_peer.peer_disconnected.connect(_on_ws_peer_disconnected)


func _on_ws_peer_disconnected(id: int) -> void:
	var closed_peer := _peer.get_peer(id)
	_last_close_code = closed_peer.get_close_code() if closed_peer != null else -1
	_last_close_reason = closed_peer.get_close_reason() if closed_peer != null else ""


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
		# 4번/5번 조사(사용자 요청) - close_code/close_reason은
		# _on_ws_peer_disconnected()가 peer_disconnected 시그널 시점에 미리
		# 캡처해둔 값이다(위 주석 참고 - 여기서 다시 get_peer()를 부르면
		# 이미 늦어서 에러가 난다). WebSocket 표준 종료 코드 1000=정상 종료,
		# 1001=상대가 떠남, 1006=비정상 종료(정상적인 종료 프레임 없이 끊김 -
		# 터널이 그냥 죽었을 때 전형적으로 이 코드가 남는다. kill -9로 서버를
		# 강제 종료해 직접 재현했을 때도 정상 종료 프레임이 없어 -1(코드 없음)
		# 로 남는 것까지 확인했다).
		var elapsed_sec := ((Time.get_ticks_msec() - _last_received_msec) / 1000.0) if _last_received_msec > 0 else -1.0
		if elapsed_sec >= 0:
			_log("[연결끊김] close_code=%d close_reason=%s 마지막 수신 후 %.1f초" % [_last_close_code, _last_close_reason, elapsed_sec])
		else:
			_log("[연결끊김] close_code=%d close_reason=%s (한 번도 메시지를 못 받음)" % [_last_close_code, _last_close_reason])
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

	# 확정 3(실제 베타 테스트) - 보내는 쪽(내가 캐릭터 팩 소유자일 때 업로드)도
	# 기본값(65535)이었다. 43KB짜리 청크를 연달아 올리면 이 버퍼가 넘친다 -
	# 아래 _flush_outgoing_queue()의 재시도가 결국은 다 보내주지만, 버퍼를
	# 키워 애초에 넘칠 압력 자체를 줄인다.
	_peer.set_outbound_buffer_size(NetProtocol.CLIENT_OUTBOUND_BUFFER_BYTES)
	_log("보내는 쪽 버퍼 설정: 요청 %d바이트 → 실제 %d바이트(get_outbound_buffer_size() 되읽음)" % [NetProtocol.CLIENT_OUTBOUND_BUFFER_BYTES, _peer.get_outbound_buffer_size()])

	# 데드락 방지 안전장치 1/3(친구 대상 베타 후속, 사용자 지적) - server_main.gd의
	# 같은 검사와 이유가 같다(protocol.gd의 can_chunk_ever_be_sent() 참고).
	# 클라이언트도 캐릭터 팩을 업로드하는 쪽이 될 수 있으므로 같은 조합
	# 오류가 여기서도 조용한 정체를 만들 수 있다.
	if not NetProtocol.can_chunk_ever_be_sent(_peer.get_outbound_buffer_size()):
		_log("[치명적 설정 오류] 보내는 쪽 버퍼(%d바이트)가 청크 하나(약 %d바이트 추정)조차 빈 상태에서도 못 담습니다 - 연결하지 않습니다." % [_peer.get_outbound_buffer_size(), NetProtocol.estimate_encoded_chunk_bytes()])
		connection_failed.emit("클라이언트 설정 오류로 연결할 수 없습니다.")
		return

	var err := _peer.create_client(url)
	if err != OK:
		connection_failed.emit("서버 주소가 올바르지 않습니다.")
		return
	_state = State.CONNECTING


func create_room(player_count: int) -> void:
	_send(NetProtocol.MSG_CREATE_ROOM, {"player_count": player_count})


## reconnect_token은 게임 도중(TRANSFERRING/IN_GAME) 끊겼다 돌아올 때만
## 채운다 - 로비 단계의 평범한 참가는 빈 문자열 그대로 보낸다(§6).
func join_room(code: String, reconnect_token: String = "") -> void:
	_send(NetProtocol.MSG_JOIN_ROOM, {"code": code, "reconnect_token": reconnect_token})


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
	_wire_peer_signals()
	_state = State.IDLE
	_ever_connected = false
	_suppress_next_disconnect = false
	_outgoing_queue.clear()
	_last_received_msec = 0
	_last_ping_received_msec = -1
	_last_close_code = -1
	_last_close_reason = ""
	_outgoing_stall_last_size = -1
	_outgoing_stall_last_progress_msec = 0
	_outgoing_stall_next_warning_msec = 0


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


## 확정 2(실제 베타 테스트 - 청크 유실) - `put_packet()`의 반환값은 보내는
## 쪽 버퍼가 넘칠 때 이 초과를 알려주지 않는다(직접 최소 재현 스크립트로
## 확인한 Godot 4.7.2 엔진 동작 - 버퍼가 이미 찬 상태에서 또 불러도
## `put_packet()`은 OK를 돌려주면서 그 바이트를 조용히 버린다. 엔진
## 콘솔에는 `Returning: ERR_OUT_OF_MEMORY`가 찍히지만 그건 내부 로그일
## 뿐 `put_packet()`의 반환값에는 안 실린다). 그래서 반환값을 사후에
## 확인하는 대신 `get_current_outbound_buffered_amount()`로 "지금 이미
## 못 나간 데이터가 얼마나 있는지"를 **호출 전에 미리** 확인한다
## (`NetProtocol.has_room_to_send_now()`) - 서버 쪽 `_send()`와 같은 이유,
## 같은 방식(server_main.gd 참고). 확정 2 후속(사용자 지적) - "조금이라도
## 남아있으면 무조건 큐로"가 아니라 "남은 양 + 이번 크기 + 청크 하나
## 여유"가 한도를 안 넘으면 바로 보낸다 - 안 그러면 1MB로 키운 버퍼가
## 프레임당 패킷 하나만 나가서 사실상 무의미해진다(실측 - 아래 참고).
##
## 반환값(bool)은 즉시 put_packet()에 성공했는지다 - 큐에 들어갔으면 false.
## on_sent가 유효하면, 실제로 put_packet()에 성공하는 그 순간(여기서
## 즉시든, _flush_outgoing_queue()에서 나중이든) 딱 한 번 호출한다.
func _send(type: String, payload: Dictionary, on_sent: Callable = Callable()) -> bool:
	if _state == State.IDLE or _state == State.CONNECTING:
		return false

	var bytes := NetProtocol.encode(type, payload)
	var server_peer := _peer.get_peer(1)  # 클라이언트에게 서버는 항상 peer id 1.
	var has_room := server_peer == null or NetProtocol.has_room_to_send_now(server_peer.get_current_outbound_buffered_amount(), bytes.size(), server_peer.get_outbound_buffer_size())
	if not _outgoing_queue.is_empty() or not has_room:
		_outgoing_queue.append({"bytes": bytes, "on_sent": on_sent})
		return false

	if _peer.put_packet(bytes) != OK:
		# 반환값 자체를 못 믿는다는 게 위에서 확인된 사실이지만, 다른
		# 이유(예: 연결이 그 사이 끊김)로 진짜 에러가 나는 경우까지 놓치면
		# 안 되므로 방어적으로 유지한다.
		_outgoing_queue.append({"bytes": bytes, "on_sent": on_sent})
		return false

	if on_sent.is_valid():
		on_sent.call()
	return true


func _flush_outgoing_queue() -> void:
	# 웹 탭 비가시화 조사 후속(2026-09-17) - 큐가 비어있으면 볼 일이 없는데도
	# 매 프레임 무조건 get_peer(1)을 불렀다. 서버가 이미 이 접속을 끊은
	# 직후(예: 탭이 백그라운드에 있다 돌아온 첫 프레임)엔 엔진의 내부 peer
	# 맵에서 이 ID가 이미 지워진 상태라, 없는 ID로 get_peer()를 부르면
	# 엔진이 콘솔에 "Condition "!peers_map.has(p_id)" is true" ERROR를
	# 찍는다(기능엔 영향 없음 - 바로 다음 줄에서 정상적으로 연결 끊김이
	# 감지됨. 실제 소켓으로 재현 확인함, docs/multiplayer.md §12). 큐가
	# 비어있을 땐 애초에 이 값을 안 쓰므로, 조회 자체를 건너뛰어 이
	# 노이즈를 없앤다.
	if _outgoing_queue.is_empty():
		return

	var server_peer := _peer.get_peer(1)
	while not _outgoing_queue.is_empty():
		# 확정 2 후속 - put_packet() 전에 버퍼에 여유가 있는지 먼저 확인한다
		# (위 _send() 주석 참고) - "조금이라도 남아있으면 무조건 대기"가
		# 아니라 has_room_to_send_now()로 "이 항목 하나는 지금 보내도
		# 안전한지"를 판단해서, 한 프레임에 여러 개를 몰아 보낼 수 있게
		# 한다(1MB 버퍼를 실제로 활용). 여유가 없으면 이번 프레임은 여기서
		# 멈추고 다음 프레임에 다시 확인한다.
		var entry: Dictionary = _outgoing_queue[0]
		if server_peer != null and not NetProtocol.has_room_to_send_now(server_peer.get_current_outbound_buffered_amount(), entry["bytes"].size(), server_peer.get_outbound_buffer_size()):
			break
		if _peer.put_packet(entry["bytes"]) != OK:
			break
		_outgoing_queue.pop_front()
		var on_sent: Callable = entry.get("on_sent", Callable())
		if on_sent.is_valid():
			on_sent.call()

	_check_outgoing_stall(_outgoing_queue.size(), server_peer)


## 데드락 방지 안전장치 2/3 - server_main.gd의 _check_outgoing_stall()과
## 같은 판단 기준(TRANSFER_STALL_WARNING_SEC 동안 안 줄면 경고, 줄어드는
## 방향으로만 진전 인정). queue_size가 0이면 정체 추적을 지운다.
func _check_outgoing_stall(queue_size: int, server_peer: WebSocketPeer) -> void:
	if queue_size == 0:
		_outgoing_stall_last_size = -1
		return

	var now := Time.get_ticks_msec()
	if _outgoing_stall_last_size == -1 or queue_size < _outgoing_stall_last_size:
		_outgoing_stall_last_size = queue_size
		_outgoing_stall_last_progress_msec = now
		_outgoing_stall_next_warning_msec = 0
		return

	_outgoing_stall_last_size = queue_size
	var stalled_sec := (now - _outgoing_stall_last_progress_msec) / 1000.0
	if stalled_sec < NetProtocol.TRANSFER_STALL_WARNING_SEC or now < _outgoing_stall_next_warning_msec:
		return

	var waiting_bytes := 0
	if not _outgoing_queue.is_empty():
		waiting_bytes = _outgoing_queue[0]["bytes"].size()
	var buffered := server_peer.get_current_outbound_buffered_amount() if server_peer != null else -1
	var limit := server_peer.get_outbound_buffer_size() if server_peer != null else -1
	_log("[경고] %.0f초간 진전 없음 - 내 보내기 대기열 %d개, 버퍼 사용량 %d/%d바이트, 맨 앞 메시지 %d바이트" % [stalled_sec, queue_size, buffered, limit, waiting_bytes])
	_outgoing_stall_next_warning_msec = now + int(NetProtocol.TRANSFER_STALL_WARNING_SEC * 1000)


## GameEvents의 dice_rolled/game_ended는 Array[int]로 타입이 고정돼 있어서
## (autoload/game_events.gd) JSON을 거쳐 float가 된 배열을 그대로 못
## 넘긴다 - 원소 단위로 int()에 통과시켜 진짜 Array[int]를 만든다.
func _to_int_array(raw: Array) -> Array[int]:
	var result: Array[int] = []
	for v in raw:
		result.append(int(v))
	return result


func _handle_packet(bytes: PackedByteArray) -> void:
	# 4번/5번 조사 - 서버의 _last_seen_msec과 같은 개념(뭐든 왔다는 것
	# 자체가 이 접속이 아직 살아있다는 증거, 디코드 성공 여부와 무관).
	_last_received_msec = Time.get_ticks_msec()

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
		NetProtocol.MSG_PING:
			# 2-6(§6) - 시그널 없이 바로 응답한다. "나 아직 살아있다"는
			# 확인일 뿐이라 UI가 알 필요 없는 배선 수준의 응답이다.
			# 4번/5번 조사 - 진짜 RTT는 아니지만(위 _last_ping_received_msec
			# 주석 참고) ping 간격이 정상(5초 근처)에서 벗어나면 연결이
			# 이미 흔들리고 있다는 신호라 로그로 남긴다.
			var now := Time.get_ticks_msec()
			if _last_ping_received_msec > 0:
				_log("[핑] 직전 ping으로부터 %dms 만에 수신(정상은 %d ms 근처)" % [now - _last_ping_received_msec, NetProtocol.PING_INTERVAL_MSEC])
			_last_ping_received_msec = now
			_send(NetProtocol.MSG_PONG, {})
		NetProtocol.MSG_PLAYER_RECONNECTED:
			player_reconnected.emit(int(payload.get("player_index", -1)))
		NetProtocol.MSG_PLAYER_TIMER:
			player_timer.emit(int(payload.get("player_index", -1)), str(payload.get("kind", "")), int(payload.get("seconds_left", 0)))
		NetProtocol.MSG_ERROR:
			var code := str(payload.get("code", ""))
			if code == NetProtocol.ERROR_PROTOCOL_MISMATCH:
				_suppress_next_disconnect = true
			server_error.emit(code, str(payload.get("message", "")))
