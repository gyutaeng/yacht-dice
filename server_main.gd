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

# 2-5(캐릭터 팩 전송) §2단계. 수집 창은 짧게(전원의 select_character가 이미
# 로비 단계에서 다 도착해 있으므로 request_character_pack은 거의 동시에
# 옴 - 네트워크 왕복 여유만 주면 됨). 타임아웃(NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC,
# 60초)을 넘기면 그 사람 캐릭터는 포기하고 기본 캐릭터로 대체한 뒤 게임을
# 시작한다(로비가 영원히 멈추면 안 됨) - 클라이언트도 카운트다운 표시에
# 같은 값을 써야 해서 NetProtocol(공유 파일)에 정의돼 있다.
const TRANSFER_COLLECT_MSEC := 1000

# 2-6(연결 끊김 감지, docs/multiplayer.md §6) - "WebSocket 레벨 ping/pong"
# 대신 애플리케이션 레벨 메시지로 직접 구현한다(2-5 후속 §8.5-6에서 얻은
# 교훈 - 엔진의 WebSocket 관련 동작을 검증 없이 믿지 않는다). 5초마다
# 확인된 접속 전원에게 ping을 보내고, 15초간 아무 메시지도(디코드 성공
# 여부와 무관) 안 온 접속은 끊는다.
const PING_INTERVAL_MSEC := 5000
const PING_TIMEOUT_MSEC := 15000

var peer := WebSocketMultiplayerPeer.new()
var room_manager := RoomManager.new()

# hello 확인 전인 접속을 추적한다 - 5초 안에 hello가 안 오면 끊는다(§2.0).
var _pending_since: Dictionary = {}  # peer_id -> Time.get_ticks_msec()
var _hello_confirmed: Dictionary = {}  # peer_id -> true

# 2-6 - 각 접속에서 마지막으로 뭐든 메시지가 온 시각. ping/pong 전용이
# 아니라 모든 메시지가 이걸 갱신한다(조용히 정상 진행 중인 접속을 pong
# 하나로만 판단하지 않기 위함).
var _last_seen_msec: Dictionary = {}  # peer_id(int) -> msec
var _next_ping_broadcast_msec: int = 0

# 2-6(턴 타임아웃/재접속 유예 카운트다운) - 방 코드별로 1초에 한 번만
# player_timer를 방송하기 위한 스로틀. Room 자신은 이 방송 주기를 몰라도
# 되므로(네트워크 개념) 서버 쪽에 둔다.
var _next_timer_broadcast_msec: Dictionary = {}  # room_code(String) -> msec

# 2-5 전송 버그 수정 - game_client.gd의 같은 필드와 같은 이유(outbound_buffer_size
# 기본값 65535바이트를 큰 청크 몇 개가 같은 프레임에 바로 넘긴다). 서버는
# peer 하나가 여러 접속을 다루므로 접속(peer_id)마다 별도 큐를 둔다 - 한
# 명에게 보낼 게 밀려도 다른 사람에게 보내는 건 영향받지 않는다. 각 항목은
# {"bytes": PackedByteArray, "on_sent": Callable}(2-5 후속 - game_client.gd와
# 같은 이유로 "큐에 넣음"과 "실제 put_packet() 성공"을 로그에서 구분한다).
var _outgoing_queues: Dictionary = {}  # peer_id(int) -> Array[Dictionary]

# 2-5 후속(청크 결측 조사) - 방 코드별로 "지금 릴레이 중인 해시가 전원에게
# 실제로 다 나갔는지"를 추적한다. {"hash": String, "expected": int(총
# 청크수 × 수신자수), "confirmed": int(실제 put_packet 성공 횟수),
# "uploader_done": bool(소유자로부터 마지막 순번까지 받았는지)}. 예전엔
# "소유자로부터 마지막 순번을 받았다"만 보고 "전송 완료"로 판정해서 다음
# 해시로 넘어갔다 - 실제로 수신자들에게 다 나갔는지는 확인 안 하고 있었다.
var _relay_confirm_state: Dictionary = {}  # room_code(String) -> Dictionary

# GameEvents 릴레이(2-4) - 서버 프로세스 전체에 GameEvents 인스턴스가
# 하나뿐이라 방마다 새로 구독하지 않는다. 지금 처리 중인 요청이 어느
# 방 것인지는 _active_room으로 표시하고, 그 방을 처리하는 동안 emit된
# 사건만 _pending_events에 쌓았다가 스냅샷을 보낸 "다음에" 방송한다
# (docs/multiplayer.md §1 - 스냅샷을 먼저 적용한 뒤에 이벤트를 방출해야
# 보이스 핸들러가 낡은 상태를 안 읽는다).
var _active_room: Room = null
var _pending_events: Array = []


## 이 목록은 scripts/net/game_event_relay.gd의 RELAYED_EVENTS와 정확히
## 일치해야 한다 - test_game_event_relay_classification.gd가 "그 목록에
## 있는 시그널은 실제로 GameEvents에 존재한다"까지는 검증하지만, "여기서
## 실제로 connect()했는가"는 사람이 이 함수를 RELAYED_EVENTS와 맞춰
## 관리해야 한다(연결 코드 자체를 리플렉션으로 생성하면 사건마다 payload
## 필드 이름이 달라서 오히려 더 복잡해짐 - 대신 목록 쪽은 테스트로 지킨다).
func _ready() -> void:
	GameEvents.dice_rolled.connect(_on_ge_dice_rolled)
	GameEvents.die_held_changed.connect(_on_ge_die_held_changed)
	GameEvents.special_hand_rolled.connect(_on_ge_special_hand_rolled)
	GameEvents.score_committed.connect(_on_ge_score_committed)
	GameEvents.yacht_scored.connect(_on_ge_yacht_scored)
	GameEvents.zero_scored.connect(_on_ge_zero_scored)
	GameEvents.bonus_achieved.connect(_on_ge_bonus_achieved)
	GameEvents.turn_ended.connect(_on_ge_turn_ended)
	GameEvents.turn_started.connect(_on_ge_turn_started)
	GameEvents.game_ended.connect(_on_ge_game_ended)
	GameEvents.game_started.connect(_on_ge_game_started)
	_start_server()


func _start_server() -> void:
	var port := _resolve_port()

	# 결측 청크 조사(2-5 후속) - create_server() 전에 설정해야 반영된다
	# (클라이언트 쪽에서 순서가 중요함을 확인한 것과 같은 이유). 서버는
	# 항상 네이티브라 print()를 그대로 믿을 수 있다(1-5의 "웹은 print()를
	# 못 믿는다"는 클라이언트 전용 문제).
	peer.set_inbound_buffer_size(NetProtocol.SERVER_INBOUND_BUFFER_BYTES)
	print("[서버] 받는 쪽 버퍼 설정: 요청 %d바이트 → 실제 %d바이트" % [NetProtocol.SERVER_INBOUND_BUFFER_BYTES, peer.get_inbound_buffer_size()])

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
	_flush_outgoing_queues()

	var now := Time.get_ticks_msec()
	for id in _pending_since.keys():
		if now - _pending_since[id] > NetProtocol.HELLO_TIMEOUT_SECONDS * 1000.0:
			print("[서버] peer %d: %.0f초 안에 hello가 안 와서 연결 종료" % [id, NetProtocol.HELLO_TIMEOUT_SECONDS])
			_pending_since.erase(id)
			peer.disconnect_peer(id)

	_service_ping_timeouts(now)
	_service_transferring_rooms(now)
	_service_in_game_rooms(now)
	_service_rematch_rooms(now)

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
	_last_seen_msec[id] = Time.get_ticks_msec()


func _on_peer_disconnected(id: int) -> void:
	print("[서버] 연결 해제: peer %d" % id)
	_pending_since.erase(id)
	_hello_confirmed.erase(id)
	_outgoing_queues.erase(id)
	_last_seen_msec.erase(id)
	_remove_peer_and_notify(id, "disconnected", false)


## 2-6(§6) - 5초마다 확인된 접속 전원에게 ping을 보내고, 15초간 아무
## 메시지도 안 온 접속은 직접 끊는다. 끊긴 뒤 정리는 기존
## _on_peer_disconnected 경로가 그대로 한다(여기서는 disconnect_peer()만
## 부른다).
func _service_ping_timeouts(now: int) -> void:
	if now >= _next_ping_broadcast_msec:
		_next_ping_broadcast_msec = now + PING_INTERVAL_MSEC
		for id in _hello_confirmed.keys():
			_send(id, NetProtocol.MSG_PING, {})

	for id in _last_seen_msec.keys().duplicate():
		if now - _last_seen_msec[id] > PING_TIMEOUT_MSEC:
			print("[서버] peer %d: %.0f초간 무응답 - 연결 종료" % [id, PING_TIMEOUT_MSEC / 1000.0])
			peer.disconnect_peer(id)


## 메시지 크기 상한(§2.0)을 넘으면 내용을 해석하지 않고 끊는다 - 다만 저수준
## 패킷 API 특성상 바이트 자체는 이미 peer.get_packet()으로 받은 뒤다(더
## 작은 크기를 미리 알아낼 방법이 없다). "해석하지 않는다"는 JSON으로
## 파싱해 필드를 들여다보지 않는다는 뜻이다.
func _handle_packet(sender_id: int, bytes: PackedByteArray) -> void:
	# 2-6(§6) - 어떤 메시지든 왔다는 것 자체가 "이 접속은 아직 살아있다"는
	# 증거다(디코드 성공 여부와 무관 - 깨진 메시지라도 살아있다는 뜻은 됨).
	_last_seen_msec[sender_id] = Time.get_ticks_msec()

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
		NetProtocol.MSG_REQUEST_CHARACTER_PACK:
			_handle_request_character_pack(sender_id, payload)
		NetProtocol.MSG_UPLOAD_PACK_CHUNK:
			_handle_upload_pack_chunk(sender_id, payload)
		NetProtocol.MSG_PACK_READY:
			_handle_pack_ready(sender_id, payload)
		NetProtocol.MSG_REQUEST_PACK_CHUNKS:
			_handle_request_pack_chunks(sender_id, payload)
		NetProtocol.MSG_PONG:
			pass  # 위에서 이미 _last_seen_msec를 갱신했으므로 할 일이 없다.
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


## 2-6(§6) - reconnect_token이 있고 방이 이미 LOBBY를 벗어났으면(TRANSFERRING/
## IN_GAME) 새 참가자가 아니라 재접속으로 처리된다(room_manager.join_room()이
## 판단). 재접속 성공 시 방 전원에게 player_reconnected를 알리고, 게임이
## 이미 진행 중이면(IN_GAME) 그 자리에서 바로 최신 state_snapshot도 하나
## 더 보내준다 - §5 "매번 전체 스냅샷" 원칙을 재접속에도 그대로 적용한 것.
func _handle_join_room(sender_id: int, payload: Dictionary) -> void:
	if room_manager.get_room_for_peer(sender_id) != null:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "이미 방에 들어가 있습니다.")
		return

	var code = payload.get("code")
	if typeof(code) != TYPE_STRING or code.is_empty():
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "방 코드가 필요합니다.")
		return

	var reconnect_token := str(payload.get("reconnect_token", ""))

	# 2-6B(재대전) - REMATCHING에서는 신규 참가(빈 슬롯을 채우는 새 사람)도
	# 가능해져서, "room.state != LOBBY면 재접속"이라는 예전 가정이 더 이상
	# 안 맞는다(REMATCHING인데 실제로는 신규 참가일 수 있음). 그래서
	# join_room()을 부르기 전에 토큰이 실제로 어느 슬롯과 일치하는지
	# 직접 확인해서 재접속 여부를 판단한다 - join_room() 안에서도 같은
	# 조회를 다시 하지만 순수 조회라 부작용이 없어 문제없다.
	var room_before_join := room_manager.get_room(code)
	var is_reconnect := room_before_join != null and not reconnect_token.is_empty() and room_before_join.find_slot_by_reconnect_token(reconnect_token) != -1

	var result = room_manager.join_room(code, sender_id, reconnect_token)
	if result is String:
		_send_error(sender_id, result, _join_error_message(result))
		return

	var room: Room = result
	var my_index := room.find_slot_by_peer(sender_id)
	var my_slot: Dictionary = room.slots[my_index]
	print("[서버] 방 %s %s: peer %d (슬롯 %d)" % [room.code, "재접속" if is_reconnect else "참가", sender_id, my_index])

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

	if is_reconnect:
		_broadcast_room(room, NetProtocol.MSG_PLAYER_RECONNECTED, {"player_index": my_index})
		if room.state == Room.State.IN_GAME:
			_send(sender_id, NetProtocol.MSG_STATE_SNAPSHOT, room.game_state.get_state_snapshot())
	else:
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
	if not room.accepts_lobby_actions():
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

	# pack_hash(2-5) - sha256 hex(64자 소문자 hex) 또는 빈 문자열(팩 없음)만
	# 허용한다. 형식이 다르면 신뢰하지 않고 그냥 "팩 없음"으로 취급한다 -
	# 이 값이 나중에 캐릭터 팩 전송 대상을 정하는 데 쓰이므로, 이상한
	# 값을 그대로 흘려보내면 안 된다(원칙 6).
	var pack_hash := str(meta.get("pack_hash", ""))
	if not _is_valid_pack_hash(pack_hash):
		pack_hash = ""

	var safe_meta := {"id": str(meta.get("id", "")), "display_name": display_name, "pack_hash": pack_hash}

	room.slots[slot_index]["meta"] = safe_meta
	_broadcast_room(room, NetProtocol.MSG_PLAYER_CHARACTER, {"player_index": slot_index, "meta": safe_meta})

	# 3번째 재대전 버그 조사(사용자 요청) - [한 판 더] 확정이 실제로 서버에
	# 도착하는지 눈으로 확인하기 위한 진단. 서버 콘솔은 DEBUG_MODE(클라이언트
	# 화면용 스위치)와 무관하게 항상 켜져 있다 - 베타 배포 후에도 운영자가
	# 유일하게 볼 수 있는 창이라 여기 묶으면 안 된다(사용자 지적, 다른
	# server_main.gd의 print()들도 전부 무조건 출력이라는 기존 관례와 통일).
	if room.state == Room.State.REMATCHING:
		print("[서버] 방 %s: 재대전 대기 중 슬롯 %d 캐릭터 갱신 수신(pack_hash=%s)" % [room.code, slot_index, ("있음" if pack_hash != "" else "없음")])


func _is_valid_pack_hash(value: String) -> bool:
	if value.is_empty():
		return true
	if value.length() != 64:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		var is_digit := c >= 48 and c <= 57  # '0'-'9'
		var is_lower_hex := c >= 97 and c <= 102  # 'a'-'f'
		if not (is_digit or is_lower_hex):
			return false
	return true


func _handle_ready(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return
	if not room.accepts_lobby_actions():
		_send_error(sender_id, NetProtocol.ERROR_GAME_ALREADY_STARTED, "이미 게임이 시작되었습니다.")
		return

	var ready_value = payload.get("ready")
	if typeof(ready_value) != TYPE_BOOL:
		_send_error(sender_id, NetProtocol.ERROR_INVALID_ARGUMENT, "ready 값이 올바르지 않습니다.")
		return

	var slot_index := room.find_slot_by_peer(sender_id)
	room.slots[slot_index]["ready"] = ready_value

	# 3번째 재대전 버그 조사(사용자 요청) - [한 판 더]를 눌렀을 때 실제로
	# 서버까지 ready 메시지가 오는지 확인용. 서버 콘솔 로그라 DEBUG_MODE와
	# 무관하게 항상 출력한다(위 _handle_select_character()와 같은 이유).
	if room.state == Room.State.REMATCHING:
		var ready_count := 0
		var occupied_count := 0
		for slot in room.slots:
			if slot != null:
				occupied_count += 1
				if slot["ready"]:
					ready_count += 1
		print("[서버] 방 %s: 재대전 준비 수신 - 슬롯 %d ready=%s (준비 %d/%d)" % [room.code, slot_index, ready_value, ready_count, occupied_count])

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


## 2-6(§6) - 명시적으로 나가는 것이므로 게임 도중이라도 재접속 유예 없이
## 바로 확정 이탈 처리한다(voluntary=true → RoomManager.remove_peer()가
## 그레이스 없이 완전히 슬롯을 비움).
func _handle_leave(sender_id: int, _payload: Dictionary) -> void:
	_remove_peer_and_notify(sender_id, "left", true)


func _remove_peer_and_notify(peer_id: int, reason: String, voluntary: bool) -> void:
	var result := room_manager.remove_peer(peer_id, voluntary, Time.get_ticks_msec())
	var room = result["room"]
	var slot_index: int = result["slot_index"]
	if room != null and slot_index != -1:
		_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": slot_index, "reason": reason})


## 정원이 다 차고 전원이 준비되면 자동으로 캐릭터 팩 전송 단계로 들어간다
## (§3). 2-6B - REMATCHING(재대전 대기)도 같은 조건으로 다음 판 전송
## 단계에 들어간다(`accepts_lobby_actions()`).
func _maybe_start_game(room: Room) -> void:
	if not room.accepts_lobby_actions() or not room.all_ready():
		return
	if room.state == Room.State.REMATCHING:
		# 서버 콘솔 로그(DEBUG_MODE 무관 - 위 _handle_ready()와 같은 이유).
		print("[서버] 방 %s: 재대전 전원 준비 완료 - 전송 단계로 진입" % room.code)
		room.clear_rematch_deadline()
	_begin_transferring(room)


## TRANSFERRING 상태로 들어가며 요청 수집 창을 연다(2-5 §2단계). 클라이언트는
## 이 메시지를 받으면 자기 캐시를 확인해서 필요한 것만 request_character_pack을
## 보낸다.
func _begin_transferring(room: Room) -> void:
	room.begin_transfer(Time.get_ticks_msec(), TRANSFER_COLLECT_MSEC)
	print("[서버] 방 %s 캐릭터 팩 전송 단계 진입" % room.code)
	_broadcast_room(room, NetProtocol.MSG_TRANSFERRING_STARTED, {})


## 매 프레임 TRANSFERRING 방들의 상태 기계를 진행시킨다(2-5 §2단계) - 수집
## 창이 끝났으면 큐를 만들고, 진행 중인 전송이 60초를 넘겼으면 포기하고
## 다음으로 넘어간다. 큐가 다 비면 곧장 게임을 시작하지 않고
## AWAITING_READY로 들어가 전원의 pack_ready를 기다린다(2-5 후속 - "마지막
## 청크를 릴레이 큐에 넣었다"와 "받는 쪽이 그걸로 프로필까지 확정했다"는
## 다른 시점이라, 전자만 보고 game_started를 보내면 검증이 덜 끝난 슬롯이
## 실루엣으로 굳어버린다). 로비가 영원히 멈추는 상황을 막는 핵심 로직이라
## 방 하나가 막혀도 나머지 방에는 영향이 없도록 방마다 독립적으로 처리한다.
func _service_transferring_rooms(now: int) -> void:
	for room in room_manager.rooms.values():
		if room.state != Room.State.TRANSFERRING:
			continue

		if room.transfer_state == Room.TransferState.COLLECTING and room.is_collection_expired(now):
			room.close_collection_and_build_queue()
			if room.transfer_state == Room.TransferState.AWAITING_READY:
				room.begin_awaiting_ready(now, NetProtocol.PACK_READY_TIMEOUT_MSEC)
			else:
				_advance_transfer(room, now)
			continue

		if room.transfer_state == Room.TransferState.TRANSFERRING_PACK:
			if room.is_current_transfer_timed_out(now, NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC):
				print("[서버] 방 %s: 해시 %s 전송이 %.0f초를 넘겨 포기함" % [room.code, room.transfer_current_hash, NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC / 1000.0])
				_broadcast_room(room, NetProtocol.MSG_PACK_TRANSFER_FAILED, {"hash": room.transfer_current_hash, "reason": "timeout"})
				_relay_confirm_state.erase(room.code)
				_advance_transfer(room, now)
				continue
			_warn_if_transfer_stalled(room, now)

		if room.transfer_state == Room.TransferState.AWAITING_READY:
			if room.all_players_pack_ready():
				print("[서버][전송] 방 %s: 전원 pack_ready 확인" % room.code)
				room.mark_transfer_done()
				_finish_transferring(room)
			elif room.is_pack_ready_timed_out(now):
				print("[서버][전송] 방 %s: pack_ready 대기 시간(%.0f초) 초과 - 그냥 진행" % [room.code, NetProtocol.PACK_READY_TIMEOUT_MSEC / 1000.0])
				room.mark_transfer_done()
				_finish_transferring(room)


## 멈춤 감지(사용자 신고 - 큰 팩에서 전송이 중간에 멈춤). 60초 타임아웃보다
## 훨씬 짧은 TRANSFER_STALL_WARNING_SEC(5초)마다 한 번씩만 경고를 반복해서
## 콘솔이 매 프레임 도배되지 않게 한다 - Room.mark_transfer_activity()가
## 청크가 실제로 릴레이될 때마다 경고 타이머를 리셋해준다.
func _warn_if_transfer_stalled(room: Room, now: int) -> void:
	var stall_ms := int(NetProtocol.TRANSFER_STALL_WARNING_SEC * 1000)
	if not room.is_transfer_stalled(now, stall_ms) or now < room.transfer_next_stall_warning_msec:
		return

	var stalled_sec := (now - room.transfer_last_chunk_msec) / 1000.0
	var queue_info: Array[String] = []
	for recipient_index in room.current_transfer_recipients():
		# room.slots[i]가 null(빈 슬롯 - 수신자가 그 사이 나감)일 수 있어서
		# 타입 있는 변수에 옮기기 전에 먼저 null인지 본다(server_main.gd의
		# _service_rematch_rooms에서 겪은 것과 같은 함정 - "!= null" 검사를
		# 대입 뒤에 하면 이미 늦다).
		if room.slots[recipient_index] == null:
			continue
		var recipient_slot: Dictionary = room.slots[recipient_index]
		var peer_id: int = recipient_slot["peer_id"]
		queue_info.append("peer %d 대기열 %d개" % [peer_id, _outgoing_queues.get(peer_id, []).size()])
	print("[서버][전송][경고] 방 %s: %.0f초간 진전 없음 - 마지막 청크 %d/%d(해시=%s), %s" % [
		room.code, stalled_sec, room.transfer_last_chunk_sequence + 1, room.transfer_last_chunk_total,
		room.transfer_current_hash.substr(0, 8), ", ".join(queue_info) if not queue_info.is_empty() else "(수신자 없음)",
	])
	room.transfer_next_stall_warning_msec = now + stall_ms


## 2-6(§6) - 매 프레임 IN_GAME 방들을 진행시킨다: (1) 재접속 유예가 끝난
## 슬롯을 "확정 이탈"로 넘기고 알린다, (2) 지금 턴인 사람이 확정 이탈이면
## 즉시, 아니면 60초가 지났을 때 auto_confirm_least_damaging()으로 대신
## 진행시킨다, (3) 1초 주기로 턴/재접속 카운트다운을 방송한다. 방 하나가
## 막혀도 나머지 방에 영향이 없도록 방마다 독립적으로 처리한다
## (_service_transferring_rooms()와 같은 패턴).
func _service_in_game_rooms(now: int) -> void:
	for room in room_manager.rooms.values():
		if room.state != Room.State.IN_GAME or room.game_state.game_over:
			continue

		for i in room.slots.size():
			if room.slots[i] == null:
				continue
			if room.is_grace_expired(i, now):
				room.mark_slot_departed(i)
				print("[서버] 방 %s: 슬롯 %d 재접속 유예(%.0f초) 종료 - 확정 이탈" % [room.code, i, NetProtocol.RECONNECT_GRACE_MSEC / 1000.0])
				_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": i, "reason": "timeout"})

		var current: int = room.game_state.current_player
		# slots[current] == null은 게임 도중 명시적으로 leave()한 경우다
		# (RoomManager.remove_peer()가 그레이스 없이 완전히 비움) - 이때는
		# reconnect_token도 같이 사라져서 다시 돌아올 수 없으므로 PAST_GRACE와
		# 똑같이(영원히) 즉시 자동 처리 대상이다.
		var current_gone: bool = room.slots[current] == null or room.slot_connection_state[current] == Room.ConnectionState.PAST_GRACE
		if current_gone or room.is_turn_timed_out(now):
			print("[서버] 방 %s: 슬롯 %d 턴 자동 처리(%s)" % [room.code, current, "이탈" if current_gone else "60초 시간 초과"])
			_mutate_and_broadcast(room, func(): room.game_state.auto_confirm_least_damaging(current))
			if room.game_state.game_over:
				room.clear_turn_deadline()
				room.begin_rematch_wait(now)
				continue

		if now < _next_timer_broadcast_msec.get(room.code, 0):
			continue
		_next_timer_broadcast_msec[room.code] = now + 1000

		var turn_player: int = room.game_state.current_player
		if room.turn_deadline_msec > 0 and room.slots[turn_player] != null and room.slot_connection_state[turn_player] != Room.ConnectionState.PAST_GRACE:
			var turn_secs := maxi(0, int(ceil((room.turn_deadline_msec - now) / 1000.0)))
			_broadcast_room(room, NetProtocol.MSG_PLAYER_TIMER, {"player_index": turn_player, "kind": "turn", "seconds_left": turn_secs})

		for i in room.slots.size():
			if room.slots[i] != null and room.slot_connection_state[i] == Room.ConnectionState.GRACE_PERIOD:
				var reconnect_secs := maxi(0, int(ceil((room.slot_disconnect_deadline_msec[i] - now) / 1000.0)))
				_broadcast_room(room, NetProtocol.MSG_PLAYER_TIMER, {"player_index": i, "kind": "reconnect", "seconds_left": reconnect_secs})


## 2-6B(같은 방에서 재대전) - 매 프레임 REMATCHING 방들을 진행시킨다.
## 대기 상한(NetProtocol.REMATCH_READY_TIMEOUT_MSEC, 2분)을 넘기면
## "한 판 더"를 안 누른(연결 여부와 무관 - 버튼을 안 눌렀거나 끊긴 채
## 안 돌아온 슬롯 전부 포함) 자리를 내보낸다. 그 뒤로는 원래 로비처럼
## 무기한 대기로 자연히 넘어간다(다시 채워지고 전원 준비되면
## _maybe_start_game()이 다음 판을 시작함).
func _service_rematch_rooms(now: int) -> void:
	for room in room_manager.rooms.values():
		if room.state != Room.State.REMATCHING:
			continue

		if room.is_rematch_wait_timed_out(now):
			# room이 room_manager.rooms.values()(타입 없는 Dictionary)의
			# 루프 변수라 Variant로 취급돼서, 반환 타입이 있는 메서드를
			# 불러도 := 로는 타입 추론이 안 된다(이 세션에서 반복된 함정) -
			# 명시적으로 타입을 적어준다.
			var not_ready_slots: Array = room.not_ready_occupied_slots()

			# 방송을 전부 먼저 끝내고 나서 비운다(2개 이상 슬롯이 한 번에
			# 시간 초과될 수 있음) - _broadcast_room()은 그 순간의
			# room.slots를 그대로 훑으므로, 한 슬롯을 먼저 비운 채로 다음
			# 슬롯의 이탈을 방송하면 이미 비워진 슬롯의 주인은(소켓은 아직
			# 열려 있는데도) 그 뒤에 나가는 사람들의 player_left를 못 받는다
			# (실제 소켓 검증에서 확인한 버그 - 2명이 동시에 타임아웃되면
			# 첫 번째로 처리된 사람이 두 번째 사람의 퇴장 알림을 놓쳤다).
			for i in not_ready_slots:
				print("[서버] 방 %s: 슬롯 %d 재대전 대기(%.0f초) 시간 초과 - 이탈 처리" % [room.code, i, NetProtocol.REMATCH_READY_TIMEOUT_MSEC / 1000.0])
				_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": i, "reason": "timeout"})
			for i in not_ready_slots:
				room_manager.force_vacate_slot(room, i)
			room.clear_rematch_deadline()
			continue

		if now < _next_timer_broadcast_msec.get(room.code, 0):
			continue
		_next_timer_broadcast_msec[room.code] = now + 1000

		var rematch_secs := maxi(0, int(ceil((room.rematch_deadline_msec - now) / 1000.0)))
		for i in room.not_ready_occupied_slots():
			_broadcast_room(room, NetProtocol.MSG_PLAYER_TIMER, {"player_index": i, "kind": "rematch", "seconds_left": rematch_secs})


## 큐에서 다음 해시를 꺼내 전송을 시작하거나(방 전체에 pack_upload_requested
## 방송 - 소유자는 이걸 보고 업로드를 시작하고, 나머지는 "누구를 기다리는지"
## UI를 갱신한다), 큐가 비었으면 AWAITING_READY로 들어간다(게임 시작은
## _service_transferring_rooms()가 전원 확인/타임아웃을 본 뒤에 한다).
func _advance_transfer(room: Room, now: int) -> void:
	var next_hash := room.start_next_transfer(now)
	if next_hash == "":
		room.begin_awaiting_ready(now, NetProtocol.PACK_READY_TIMEOUT_MSEC)
		return
	_broadcast_room(room, NetProtocol.MSG_PACK_UPLOAD_REQUESTED, {"hash": next_hash})


## 클라이언트가 "내가 받아야 할 팩을 전부 처리했다"고 보내는 영수증(2-5
## 후속). AWAITING_READY에 도달하기 전에(COLLECTING 등) 먼저 도착할 수
## 있으므로(받을 팩이 아예 없는 클라이언트는 transferring_started를 받자마자
## 보냄) transfer_state를 따지지 않고 방이 TRANSFERRING이기만 하면 받아준다 -
## Room.mark_pack_ready()는 begin_transfer()에서 딱 한 번만 초기화되는
## 집합에 기록하므로 이른 도착도 그대로 유효하다.
func _handle_pack_ready(sender_id: int, _payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null or room.state != Room.State.TRANSFERRING:
		return

	var slot_index := room.find_slot_by_peer(sender_id)
	if slot_index == -1:
		return

	room.mark_pack_ready(slot_index)
	print("[서버][전송] 방 %s: 슬롯 %d pack_ready 수신" % [room.code, slot_index])


## game_started 다음에 game_state.start_turn()을 실제로 호출해서 첫 턴을
## 연다 - 이게 없으면 turn_started(0)도 안 나가고 첫 스냅샷도 "아무것도
## 시작 안 한" 상태로 나간다. 2-6B - start_turn() 전에 항상
## room.start_new_game()으로 완전히 새 GameState를 만든다(처음 게임이든
## 재대전이든 예외 없이) - 지난 판 점수/굴림 상태가 한 조각도 안 남게
## 하기 위함이다.
func _finish_transferring(room: Room) -> void:
	room.state = Room.State.IN_GAME
	room.start_new_game()
	print("[서버] 방 %s 게임 시작 (인원 %d)" % [room.code, room.capacity])
	_broadcast_room(room, NetProtocol.MSG_GAME_STARTED, {"player_count": room.capacity})

	_mutate_and_broadcast(room, func(): room.game_state.start_turn())


## "owner_index 슬롯의 팩이 필요하다"는 요청. 수집 창이 아니거나 값이
## 이상해도 조용히 무시한다 - Room.register_pack_request()가 이미 그 검증을
## 하지만, 여기서도 room/슬롯 존재 여부는 한 번 더 확인한다(원칙 6).
func _handle_request_character_pack(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null or room.state != Room.State.TRANSFERRING:
		return

	var owner_index = _payload_int(payload, "owner_index")
	if owner_index == null:
		return

	var requester_index := room.find_slot_by_peer(sender_id)
	if requester_index == -1:
		return

	room.register_pack_request(requester_index, owner_index)


## 지금 순번인 소유자가 보낸 청크를 그 해시를 요청한 수신자들에게 그대로
## 릴레이한다(서버는 전체 바이트를 버퍼링하지 않는다 - 해시 검증은 받는 쪽이
## 전부 받은 뒤 직접 한다). total_bytes가 상한을 넘으면 그 자리에서 포기하고
## 다음 해시로 넘어간다 - 청크 개수만 믿지 않고 매 청크마다 검사한다(원칙 6).
##
## "전송 완료" 판정(2-5 후속, 확실한 버그 수정): 예전엔 소유자로부터 마지막
## 순번을 받은 시점에 곧바로 "완료"로 보고 다음 해시로 넘어갔다 - 이건
## "소유자가 다 보냈다"일 뿐 "수신자 전원에게 실제로 나갔다"가 아니다(이
## 프로젝트에서 "보냈다"를 "도착해서 쓸 수 있다"로 착각한 사고가 이미 두
## 번 있었다 - §8.5-1/§8.5-2, 이게 세 번째였다). 이제 _relay_confirm_state로
## "청크수 × 수신자수"만큼의 실제 put_packet() 성공을 다 셀 때까지 기다린
## 뒤에야(_maybe_finish_relay) 다음 해시로 넘어간다.
## 결측 청크 재전송(2-5 후속) - 받는 쪽이 결측을 알아챌 때쯤엔 서버가 이미
## 다음 해시로 넘어가 있는 경우가 대부분이라(정상 경로), 소유자 검증/수신자
## 조회를 "지금 진행 중인 해시"가 아니라 "그 해시의 진짜 소유자/요청자"
## 기준으로 한다(room.transfer_hash_owners/recipients_for_hash - 둘 다
## begin_transfer()에서만 초기화되어 지나간 해시에 대해서도 유효하다).
## 지금 진행 중인 해시(is_current_hash)일 때만 _relay_confirm_state로
## "전원에게 실제로 나갔는지"를 세어 다음 해시로 넘어갈지 판단한다 - 이미
## 지나간 해시의 재전송은 그 판정에 전혀 관여하지 않고 그냥 릴레이만 한다.
func _handle_upload_pack_chunk(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null or room.state != Room.State.TRANSFERRING:
		return

	var hash := str(payload.get("hash", ""))
	if hash.is_empty() or not room.transfer_hash_owners.has(hash):
		return
	if room.find_slot_by_peer(sender_id) != room.transfer_hash_owners[hash]:
		return

	var sequence = _payload_int(payload, "sequence")
	var total_chunks = _payload_int(payload, "total_chunks")
	var total_bytes = _payload_int(payload, "total_bytes")
	if sequence == null or total_chunks == null or total_bytes == null:
		return
	if total_chunks <= 0 or sequence < 0 or sequence >= total_chunks:
		return

	var is_current_hash := hash == room.transfer_current_hash and room.transfer_state == Room.TransferState.TRANSFERRING_PACK

	if is_current_hash and total_bytes > CharacterLimits.TOTAL_WARNING_BYTES:
		print("[서버][전송] 방 %s: 해시 %s가 상한(%s)을 넘어 전송을 포기함" % [room.code, hash, CharacterLimits.format_bytes(CharacterLimits.TOTAL_WARNING_BYTES)])
		_broadcast_room(room, NetProtocol.MSG_PACK_TRANSFER_FAILED, {"hash": hash, "reason": "oversized"})
		_relay_confirm_state.erase(room.code)
		_advance_transfer(room, Time.get_ticks_msec())
		return

	# 2-5 전송 진단(보내는 쪽/서버/받는 쪽 세 로그를 대조해 어디서 막혔는지
	# 가리기 위함) - 웹 클라이언트는 브라우저 콘솔이 안 보이므로 이 print()는
	# 항상 서버 콘솔(헤드리스 네이티브 프로세스)에만 찍힌다. 클라이언트 쪽
	# 진단은 online_screen.gd의 화면 로그(BuildInfo.DEBUG_MODE) 참고.
	var recipients := room.recipients_for_hash(hash)
	if is_current_hash:
		print("[서버][전송] 청크 수신 %d/%d(해시=%s, %d바이트, 소유자로부터 도착)" % [sequence + 1, total_chunks, hash.substr(0, 8), total_bytes])
		room.mark_transfer_activity(Time.get_ticks_msec(), sequence, total_chunks)
	else:
		print("[서버][전송] 재전송 청크 수신 %d/%d(해시=%s, %d바이트) - 지나간 해시라 진행 판정에는 영향 없음" % [sequence + 1, total_chunks, hash.substr(0, 8), total_bytes])

	var state: Dictionary = {}
	if is_current_hash:
		state = _relay_confirm_state.get(room.code, {})
		if state.get("hash", "") != hash:
			state = {"hash": hash, "expected": total_chunks * recipients.size(), "confirmed": 0, "uploader_done": false}
		_relay_confirm_state[room.code] = state

	var data := str(payload.get("data", ""))
	for recipient_index in recipients:
		# 같은 함정(위 _warn_if_transfer_stalled 참고) - null을 그대로
		# Dictionary 변수에 대입하면 그 자리에서 에러가 나서 바로 아래
		# null 검사가 무의미해진다. 원본 배열 원소를 먼저 검사한다.
		if room.slots[recipient_index] == null:
			continue
		var recipient_slot: Dictionary = room.slots[recipient_index]
		var peer_id: int = recipient_slot["peer_id"]
		var seq_display: int = sequence + 1
		var room_code: String = room.code
		var confirm_current := is_current_hash
		var on_sent := func() -> void:
			if confirm_current:
				print("[서버][전송] 청크 %d/%d 실제 송신 완료 → peer %d(해시=%s)" % [seq_display, total_chunks, peer_id, hash.substr(0, 8)])
				_mark_relay_confirmed(room_code, hash)
			else:
				print("[서버][전송] 재전송 청크 %d/%d 실제 송신 완료 → peer %d(해시=%s)" % [seq_display, total_chunks, peer_id, hash.substr(0, 8)])
		var sent_now := _send(peer_id, NetProtocol.MSG_PACK_CHUNK, {"hash": hash, "sequence": sequence, "total_chunks": total_chunks, "data": data}, on_sent)
		if not sent_now:
			print("[서버][전송] 청크 %d/%d peer %d에게 큐 적재(대기열 %d개) - 실제 전송은 나중에 위 '실제 송신 완료' 로그로 확인" % [seq_display, total_chunks, peer_id, _outgoing_queues.get(peer_id, []).size()])

	if is_current_hash:
		if sequence == total_chunks - 1:
			state["uploader_done"] = true
			_relay_confirm_state[room.code] = state
		_maybe_finish_relay(room, state)


## 결측 청크 재전송(2-5 후속) - 받는 쪽이 빠진 순번을 지정해 재전송을
## 요청하면, 서버는 바이트를 들고 있지 않으므로(§8.4 - 전체 바이트를
## 버퍼링하지 않는 설계를 그대로 유지) 그 해시의 소유자에게만 전달한다
## (방 전체 방송 아님 - 소유자 본인 외엔 이 정보로 할 일이 없다). 요청
## 횟수 상한은 Room.mark_chunk_resend_requested()가 독립적으로 강제한다
## (원칙 6 - 클라이언트 자체 상한을 그대로 믿지 않는다).
func _handle_request_pack_chunks(sender_id: int, payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null or room.state != Room.State.TRANSFERRING:
		return

	var hash := str(payload.get("hash", ""))
	if hash.is_empty() or not room.transfer_hash_owners.has(hash):
		return

	var requester_index := room.find_slot_by_peer(sender_id)
	if requester_index == -1:
		return

	var sequences_raw = payload.get("sequences")
	if typeof(sequences_raw) != TYPE_ARRAY or sequences_raw.is_empty():
		return

	var sequences: Array = []
	for value in sequences_raw:
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		var seq := int(value)
		if seq >= 0 and not sequences.has(seq):
			sequences.append(seq)
	if sequences.is_empty():
		return

	if not room.mark_chunk_resend_requested(hash, requester_index):
		print("[서버][전송] 방 %s: 슬롯 %d의 해시 %s 재전송 요청이 상한(%d회)을 넘어 무시함" % [room.code, requester_index, hash.substr(0, 8), NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH])
		return

	var owner_index: int = room.transfer_hash_owners[hash]
	if owner_index < 0 or owner_index >= room.slots.size() or room.slots[owner_index] == null:
		return

	print("[서버][전송] 방 %s: 슬롯 %d가 해시 %s의 청크 %s 재전송 요청" % [room.code, requester_index, hash.substr(0, 8), sequences])
	_send(room.slots[owner_index]["peer_id"], NetProtocol.MSG_PACK_CHUNKS_REQUESTED, {"hash": hash, "sequences": sequences})


## _send()/_flush_outgoing_queues()가 청크 하나의 put_packet()이 실제로
## 성공했을 때 부르는 콜백 - 확인 카운트를 올리고 전부 다 됐는지 본다.
func _mark_relay_confirmed(room_code: String, hash: String) -> void:
	var room := room_manager.get_room(room_code)
	if room == null:
		return
	var state: Dictionary = _relay_confirm_state.get(room_code, {})
	if state.get("hash", "") != hash:
		return  # 이미 다음 해시로 넘어간 뒤 뒤늦게 확인된 것 - 무시.
	state["confirmed"] = state.get("confirmed", 0) + 1
	_relay_confirm_state[room_code] = state
	_maybe_finish_relay(room, state)


## 소유자로부터 마지막 순번까지 받았고(uploader_done), 그 청크들이 수신자
## 전원에게 실제로 다 나간 것(confirmed >= expected)까지 확인되면 그때
## 다음 해시로 넘어간다.
func _maybe_finish_relay(room: Room, state: Dictionary) -> void:
	if not state.get("uploader_done", false):
		return
	if state.get("confirmed", 0) < state.get("expected", 0):
		return
	print("[서버][전송] 해시 %s 전송 완료 확인(청크×수신자 %d개 전부 실제 송신됨) - 다음 해시로 진행" % [str(state.get("hash", "")).substr(0, 8), state.get("expected", 0)])
	_relay_confirm_state.erase(room.code)
	_advance_transfer(room, Time.get_ticks_msec())


func _handle_request_roll(sender_id: int, _payload: Dictionary) -> void:
	var room := room_manager.get_room_for_peer(sender_id)
	if room == null:
		_send_error(sender_id, NetProtocol.ERROR_ROOM_NOT_FOUND, "방에 들어가 있지 않습니다.")
		return

	var err := room.validate_roll(sender_id)
	if err != "":
		_send_error(sender_id, err, _turn_error_message(err, "리롤 횟수를 모두 사용했습니다."))
		return

	room.reset_turn_deadline(Time.get_ticks_msec())
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

	room.reset_turn_deadline(Time.get_ticks_msec())
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

	room.reset_turn_deadline(Time.get_ticks_msec())
	_mutate_and_broadcast(room, func(): room.game_state.confirm_category(category))
	if room.game_state.game_over:
		room.clear_turn_deadline()
		room.begin_rematch_wait(Time.get_ticks_msec())


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


## 2-4C에서 추가 - 이게 빠져서 온라인 홀드 효과음이 안 났다.
func _on_ge_die_held_changed(player_index: int, index: int, held: bool) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_DIE_HELD_CHANGED, "payload": {"player_index": player_index, "index": index, "held": held}})


func _on_ge_special_hand_rolled(player_index: int, category: int, points: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_SPECIAL_HAND_ROLLED, "payload": {"player_index": player_index, "category": category, "points": points}})


## 2-4C에서 추가 - 지금은 구독자가 없지만("구독자 없음"은 제외 사유가
## 아님, game_event_relay.gd 참고) 나중에 확정 연출이 생기면 바로 쓸 수 있다.
func _on_ge_score_committed(player_index: int, category: int, points: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_SCORE_COMMITTED, "payload": {"player_index": player_index, "category": category, "points": points}})


## 2-4C에서 추가.
func _on_ge_yacht_scored(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_YACHT_SCORED, "payload": {"player_index": player_index}})


func _on_ge_zero_scored(player_index: int, category: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_ZERO_SCORED, "payload": {"player_index": player_index, "category": category}})


func _on_ge_bonus_achieved(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_BONUS_ACHIEVED, "payload": {"player_index": player_index}})


## 2-4C에서 추가.
func _on_ge_turn_ended(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_TURN_ENDED, "payload": {"player_index": player_index}})


## 2-6(§6 "턴 제한 시간") - 새 턴이 시작될 때마다 60초 카운트다운을 다시
## 잡는다. 단, 그 슬롯이 이미 "확정 이탈"(PAST_GRACE)이면 60초를 기다릴
## 이유가 없다 - 하지만 여기서 바로 auto_confirm_least_damaging()을 또
## 부르면 같은 _mutate_and_broadcast() 호출 스택 안에서 재귀적으로
## turn_started가 또 emit될 수 있으므로, 데드라인을 이미 지난 값으로만
## 세팅해두고 실제 처리는 _service_in_game_rooms()가 다음 프레임에
## "턴 시간 초과"로 자연스럽게 집어서 하게 한다(한 프레임 늦을 뿐 체감
## 차이는 없다).
func _on_ge_turn_started(player_index: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_TURN_STARTED, "payload": {"player_index": player_index}})

	var now := Time.get_ticks_msec()
	if _active_room.slots[player_index] == null or _active_room.slot_connection_state[player_index] == Room.ConnectionState.PAST_GRACE:
		_active_room.turn_deadline_msec = now - 1
	else:
		_active_room.reset_turn_deadline(now)


func _on_ge_game_ended(winners: Array, scores: Array) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_GAME_ENDED, "payload": {"winners": winners, "scores": scores}})


## 2-4C에서 추가 - GameState.start_turn()이 내는 신호다(로비가 다 찼을 때
## 보내는 MSG_GAME_STARTED와는 다른 메시지 - 이름이 겹치면 인사 연출이
## 두 번 트리거될 뻔했다. protocol.gd의 MSG_GAME_STATE_STARTED 주석 참고).
func _on_ge_game_started(player_count: int) -> void:
	if _active_room == null:
		return
	_pending_events.append({"type": NetProtocol.MSG_GAME_STATE_STARTED, "payload": {"player_count": player_count}})


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
## 반환값(bool)은 즉시 put_packet()에 성공했는지다(큐에 들어갔으면 false).
## on_sent가 유효하면, 실제로 put_packet()에 성공하는 순간(여기서
## 즉시든, _flush_outgoing_queues()에서 나중이든) 딱 한 번 호출한다 - 2-5
## 후속: "큐에 넣었다"를 "보냈다"로 찍던 로그를 실제 확인 시점으로 고친다.
func _send(peer_id: int, type: String, payload: Dictionary, on_sent: Callable = Callable()) -> bool:
	var ws_peer := peer.get_peer(peer_id)
	if ws_peer == null or ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false

	var bytes := NetProtocol.encode(type, payload)
	var queue: Array = _outgoing_queues.get(peer_id, [])
	if not queue.is_empty():
		queue.append({"bytes": bytes, "on_sent": on_sent})
		_outgoing_queues[peer_id] = queue
		return false

	peer.set_target_peer(peer_id)
	if peer.put_packet(bytes) != OK:
		queue.append({"bytes": bytes, "on_sent": on_sent})
		_outgoing_queues[peer_id] = queue
		return false

	if on_sent.is_valid():
		on_sent.call()
	return true


## _send()가 못 내보내고 큐에 쌓아둔 메시지를 매 프레임 다시 시도한다(2-5
## 전송 버그 수정 - 위 필드 주석 참고). 연결이 끊긴 상대의 큐는 그냥
## 버린다(peer_disconnected에서도 지우지만, 그 사이 프레임에 한 번 더
## 걸러지는 안전망).
func _flush_outgoing_queues() -> void:
	for peer_id in _outgoing_queues.keys():
		var queue: Array = _outgoing_queues[peer_id]
		var ws_peer := peer.get_peer(peer_id)
		if ws_peer == null or ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			_outgoing_queues.erase(peer_id)
			continue

		peer.set_target_peer(peer_id)
		while not queue.is_empty():
			var entry: Dictionary = queue[0]
			if peer.put_packet(entry["bytes"]) != OK:
				break
			queue.pop_front()
			var on_sent: Callable = entry.get("on_sent", Callable())
			if on_sent.is_valid():
				on_sent.call()

		if queue.is_empty():
			_outgoing_queues.erase(peer_id)


func _broadcast_room(room: Room, type: String, payload: Dictionary, exclude_peer_id: int = -1) -> void:
	for slot in room.slots:
		if slot != null and slot["peer_id"] != exclude_peer_id:
			_send(slot["peer_id"], type, payload)


func _send_error(peer_id: int, code: String, message: String) -> void:
	_send(peer_id, NetProtocol.MSG_ERROR, {"code": code, "message": message})
