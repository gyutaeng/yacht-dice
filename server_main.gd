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

# 2-7(Render 상시 배포 사전 조사) - Render의 Web Service는 자기가 정한
# 포트를 이 이름의 환경변수로 컨테이너에 주입하고, 그 포트로 리슨하는지
# 감시해서 안 하면 배포를 실패로 처리한다(우리가 정하는 게 아니라 Render
# 쪽 표준 - `docs/deployment_checklist.md` "2-7 사전 조사" §2). 로컬
# 개발용 YACHT_DICE_PORT보다 우선순위를 높게 둔다 - Render 환경에서는
# YACHT_DICE_PORT를 아무도 설정 안 하므로 실제로 충돌하지 않는다.
const RENDER_PORT_ENV_VAR := "PORT"

# 확정 2 회귀 테스트 전용 - CLI 인자/환경변수를 거치지 않고 포트/버퍼를
# 강제로 지정한다(-1이면 평소처럼 CLI/환경변수/기본값 순으로 정함). 이
# 스크립트를 코드로 직접 .new()해서 붙이는 헤드리스 테스트에서만 쓴다 -
# 실제 배포 진입점(res://server_main.tscn)은 이 값을 절대 안 건드린다.
var port_override: int = -1
var outbound_buffer_override_bytes: int = -1

# 2-5(캐릭터 팩 전송) §2단계. 수집 창은 짧게(전원의 select_character가 이미
# 로비 단계에서 다 도착해 있으므로 request_character_pack은 거의 동시에
# 옴 - 네트워크 왕복 여유만 주면 됨). 타임아웃(NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC,
# 60초)을 넘기면 그 사람 캐릭터는 포기하고 기본 캐릭터로 대체한 뒤 게임을
# 시작한다(로비가 영원히 멈추면 안 됨) - 클라이언트도 카운트다운 표시에
# 같은 값을 써야 해서 NetProtocol(공유 파일)에 정의돼 있다.
const TRANSFER_COLLECT_MSEC := 1000

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

# 2-7 사전 조사(연결 유지 시간 실측 준비) - Render 무료 플랜에서 WebSocket
# 연결이 얼마나 유지되는지가 이 계획의 최대 변수라, 실제 배포 전에
# 로컬에서 먼저 로그 형식을 만들어둔다. _connected_since_msec는 접속
# 시각, _last_sent_msec는 "마지막으로 실제 put_packet()이 성공한 시각"
# (put_packet 반환값을 못 믿는다는 게 확정 2에서 이미 밝혀졌으므로,
# _send()/_flush_outgoing_queues()가 실제 성공을 확인한 지점에서만 갱신한다).
# _last_seen_msec(위, 이미 있음)를 "마지막 수신"으로 그대로 재사용한다 -
# 별도 필드를 안 만든 이유는 그 필드가 이미 정확히 같은 뜻(뭐든 메시지가
# 온 시각)이기 때문이다.
var _connected_since_msec: Dictionary = {}  # peer_id(int) -> msec
var _last_sent_msec: Dictionary = {}  # peer_id(int) -> msec
var _next_connection_heartbeat_msec: int = 0
const CONNECTION_HEARTBEAT_INTERVAL_MSEC := 30000

# 사용자 신고("두 번째 게임 도중 서버 접속이 끊김", 재현 조건 미상) 조사용 -
# WebSocketMultiplayerPeer의 peer_disconnected(id)는 사유를 안 주므로,
# 서버가 스스로 끊는 경로(hello 타임아웃/ping 무응답)에서만 이유를 미리
# 적어두고, 없으면 "상대가 스스로 닫음(또는 네트워크 오류)"로 남긴다.
var _disconnect_reason: Dictionary = {}  # peer_id(int) -> String

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

# 데드락 방지 안전장치 2/3(친구 대상 베타 후속) - 위 시작 시점 검사(1/3)가
# 못 잡는 경로(예: 실행 중 buffer_limit이 예상과 다르게 동작하는 미지의
# 사례)까지 대비한 마지막 관측 장치다. peer_id별 보내기 대기열 길이가
# TRANSFER_STALL_WARNING_SEC 동안 안 줄면(늘기만 해도 정체로 봄 - 줄어드는
# 방향으로만 "진전" 인정) 경고를 남긴다. pack_transfer_client.gd의
# _check_send_stall()과 같은 판단 기준이지만 그건 팩 전송(응용 계층)
# 전용이고, 이건 소켓 큐 자체(전송 계층)를 보므로 팩 전송이 아닌 다른
# 메시지가 막혀도 잡는다.
var _outgoing_stall_last_size: Dictionary = {}  # peer_id(int) -> int
var _outgoing_stall_last_progress_msec: Dictionary = {}  # peer_id(int) -> int
var _outgoing_stall_next_warning_msec: Dictionary = {}  # peer_id(int) -> int

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

	# 확정 3(실제 베타 테스트) - 받는 쪽만 키우고 보내는 쪽은 기본값(65535)
	# 그대로였다. 서버는 캐릭터 팩을 릴레이할 때 43KB짜리 청크를 연달아
	# 내보내므로 이 버퍼가 계속 넘쳤다 - 아래 확정 2의 대기열 수정과
	# 별개로, 버퍼 자체를 키워 애초에 넘칠 압력을 줄인다(버퍼는 압력을
	# 줄이는 것이고 대기열 수정이 진짜 해결이라는 점은 그대로 유효함).
	var outbound_bytes := outbound_buffer_override_bytes if outbound_buffer_override_bytes > 0 else NetProtocol.SERVER_OUTBOUND_BUFFER_BYTES
	peer.set_outbound_buffer_size(outbound_bytes)
	print("[서버] 보내는 쪽 버퍼 설정: 요청 %d바이트 → 실제 %d바이트" % [outbound_bytes, peer.get_outbound_buffer_size()])

	# 데드락 방지 안전장치 1/3(친구 대상 베타 후속, 사용자 지적) - 아래
	# has_room_to_send_now()가 이 buffer_limit 조합에서 청크 하나조차
	# 영원히 못 보내는 상태(빈 버퍼에도 여유 없음 판정)라면, 그건 나중에
	# 팩 전송 도중 에러 없이 조용히 멈추는 것으로만 드러난다 - 시작
	# 시점에 미리 확인해서 그 자리에서 크게 실패하는 게 훨씬 낫다.
	if not NetProtocol.can_chunk_ever_be_sent(peer.get_outbound_buffer_size()):
		printerr("[서버] 설정 오류: 보내는 쪽 버퍼(%d바이트)가 청크 하나(약 %d바이트 추정)조차 빈 상태에서도 못 담습니다 - 이대로면 캐릭터 팩 전송이 에러 없이 영원히 멈춥니다. NetProtocol.SERVER_OUTBOUND_BUFFER_BYTES/CHUNK_PAYLOAD_BYTES 값을 확인하세요." % [peer.get_outbound_buffer_size(), NetProtocol.estimate_encoded_chunk_bytes()])
		get_tree().quit(1)
		return

	var err := peer.create_server(port)
	if err != OK:
		if err == ERR_ALREADY_IN_USE:
			# 사용자 신고("서버를 껐다 켰더니 접속이 안 됨") 조사용 - 로컬
			# 재현으로는 이 경로 자체가 이미 명확하게 실패함을 확인했지만
			# (조용히 성공한 것처럼 보이지 않음), 콘솔을 훑어보는 사람이
			# 바로 알아보도록 포트 충돌 전용 문구를 따로 냈다.
			printerr("[서버] 포트 %d이(가) 이미 사용 중입니다 - 다른 서버 프로세스가 이미 떠 있는지 확인하세요." % port)
		else:
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
			_disconnect_reason[id] = "hello 타임아웃(%.0f초)" % NetProtocol.HELLO_TIMEOUT_SECONDS
			_pending_since.erase(id)
			peer.disconnect_peer(id)

	_service_ping_timeouts(now)
	_service_connection_heartbeat(now)
	_service_transferring_rooms(now)
	_service_in_game_rooms(now)
	_service_rematch_rooms(now)

	while peer.get_available_packet_count() > 0:
		var sender_id := peer.get_packet_peer()
		var bytes := peer.get_packet()
		_handle_packet(sender_id, bytes)


func _resolve_port() -> int:
	if port_override > 0:
		return port_override

	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0].is_valid_int():
		return args[0].to_int()

	# 2-7 - Render 표준 환경변수가 로컬 개발용보다 우선한다. 순서가
	# 중요하다: CLI 인자(테스트/수동 실행이 가장 명시적인 의도) →
	# PORT(Render가 실제로 트래픽을 연결해줄 포트, 무시하면 배포가
	# 죽은 것으로 처리됨) → YACHT_DICE_PORT(로컬 전용, 계속 유지) →
	# 기본값.
	var render_port := OS.get_environment(RENDER_PORT_ENV_VAR)
	if render_port != "" and render_port.is_valid_int():
		return render_port.to_int()

	var env_value := OS.get_environment(PORT_ENV_VAR)
	if env_value != "" and env_value.is_valid_int():
		return env_value.to_int()

	return DEFAULT_PORT


func _on_peer_connected(id: int) -> void:
	print("[서버] 접속: peer %d" % id)
	_pending_since[id] = Time.get_ticks_msec()
	_last_seen_msec[id] = Time.get_ticks_msec()
	_connected_since_msec[id] = Time.get_ticks_msec()


## 사용자 신고("두 번째 게임 도중 서버 접속이 끊김") 조사용 - 사유(우리가
## 먼저 끊었으면 그 이유, 아니면 "상대가 스스로 닫음")와 마지막으로 뭐든
## 메시지를 받은 지 얼마나 지났는지를 항상 남긴다. 재현되면 이 로그로
## "핑이 안 와서 서버가 끊었다"/"상대가 갑자기 사라졌다(네트워크 이상 등
## 엔진이 사유를 안 주는 경우)"를 최소한 구분할 수 있다.
func _on_peer_disconnected(id: int) -> void:
	var now := Time.get_ticks_msec()
	var last_seen: int = _last_seen_msec.get(id, -1)
	var elapsed_text := ("%.1f초 전" % ((now - last_seen) / 1000.0)) if last_seen >= 0 else "기록 없음"
	var reason: String = _disconnect_reason.get(id, "상대가 스스로 닫음(또는 네트워크 오류 - 엔진이 구체적 사유를 안 줌)")
	var connected_since: int = _connected_since_msec.get(id, -1)
	var total_alive_text := ("%.1f" % ((now - connected_since) / 1000.0)) if connected_since >= 0 else "?"
	print("[서버][연결계측] 연결 해제: peer %d, 총 유지 %s초, 사유=%s, 마지막 수신=%s" % [id, total_alive_text, reason, elapsed_text])
	_disconnect_reason.erase(id)
	_pending_since.erase(id)
	_hello_confirmed.erase(id)
	_outgoing_queues.erase(id)
	_last_seen_msec.erase(id)
	_connected_since_msec.erase(id)
	_last_sent_msec.erase(id)
	_remove_peer_and_notify(id, "disconnected", false)


## 2-6(§6) - 5초마다 확인된 접속 전원에게 ping을 보내고, 15초간 아무
## 메시지도 안 온 접속은 직접 끊는다. 끊긴 뒤 정리는 기존
## _on_peer_disconnected 경로가 그대로 한다(여기서는 disconnect_peer()만
## 부른다).
func _service_ping_timeouts(now: int) -> void:
	if now >= _next_ping_broadcast_msec:
		_next_ping_broadcast_msec = now + NetProtocol.PING_INTERVAL_MSEC
		for id in _hello_confirmed.keys():
			_send(id, NetProtocol.MSG_PING, {})

	for id in _last_seen_msec.keys().duplicate():
		if now - _last_seen_msec[id] > NetProtocol.PING_TIMEOUT_MSEC:
			print("[서버] peer %d: %.0f초간 무응답 - 연결 종료" % [id, NetProtocol.PING_TIMEOUT_MSEC / 1000.0])
			_disconnect_reason[id] = "핑 무응답(%.0f초)" % (NetProtocol.PING_TIMEOUT_MSEC / 1000.0)
			peer.disconnect_peer(id)


## 2-7 사전 조사(연결 유지 시간 실측 준비) - 30초마다, 아무 일이 없어도
## 지금 붙어있는 접속 전부의 유지 시간을 찍는다. Render 무료 플랜에서
## 유휴 연결이 몇 분 만에 끊기는지 알아내려면 "언제부터 붙어있었는지"
## 기록이 계속 남아야 한다 - 연결이 끊긴 뒤(_on_peer_disconnected)에
## 남기는 로그만으로는 "얼마나 버티다 끊겼는지"는 알아도 "지금 몇 초째
## 살아있는지"를 실시간으로 못 보므로 별도로 필요하다. 마지막 수신/송신
## 시각을 같이 남기는 이유는 유휴(우리 쪽에서 아무것도 안 보내고 안
## 받은 채 방치) 때문에 끊기는 것과 그냥 시간 자체가 다 돼서 끊기는 것을
## 구분하기 위함이다 - 예를 들어 ping을 5초마다 계속 보내는데도(마지막
## 송신이 항상 5초 이내) 특정 시점에 끊기면 "유휴 타임아웃"이 아니라
## "하드 타임 리밋"이라는 뜻이 된다.
func _service_connection_heartbeat(now: int) -> void:
	if now < _next_connection_heartbeat_msec:
		return
	_next_connection_heartbeat_msec = now + CONNECTION_HEARTBEAT_INTERVAL_MSEC

	var connection_count := _connected_since_msec.size()
	for id in _connected_since_msec.keys():
		var connected_since: int = _connected_since_msec[id]
		var alive_sec := (now - connected_since) / 1000.0
		var last_seen: int = _last_seen_msec.get(id, -1)
		var last_seen_text := ("%.1f초 전" % ((now - last_seen) / 1000.0)) if last_seen >= 0 else "기록 없음"
		var last_sent: int = _last_sent_msec.get(id, -1)
		var last_sent_text := ("%.1f초 전" % ((now - last_sent) / 1000.0)) if last_sent >= 0 else "기록 없음"
		print("[서버][연결계측] 유지: peer %d, %.1f초 경과, 현재 접속 수 %d, 마지막 수신=%s, 마지막 송신=%s" % [id, alive_sec, connection_count, last_seen_text, last_sent_text])


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

	# 1번 버그 조사(사용자 요청) - "리스너가 두 겹이라 ready 메시지가 두 번
	# 가서 토글이 뒤집혔을 수 있다"는 가설을 대비한 경고. 실제로 여기 ready는
	# 토글이 아니라 매번 절대값(true/false)을 그대로 받아 그대로 저장하므로
	# 메시지가 정확히 같은 값으로 중복돼도 상태가 뒤집히진 않지만, 중복 자체가
	# 있었는지는 이 로그로 확인할 수 있다 - 같은 peer가 같은 값을 연달아
	# 보내면(중간에 다른 값이 낀 적 없이) 누른 적 없는데 메시지가 한 번 더
	# 갔다는 뜻이다.
	var previous_ready = room.slots[slot_index]["ready"]
	if previous_ready == ready_value:
		print("[서버][경고] 방 %s: 슬롯 %d에서 동일한 ready 값(%s)이 연속으로 수신됨 - 메시지 중복 의심" % [room.code, slot_index, ready_value])

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
				print("[서버] 방 %s: 슬롯 %d 재접속 유예(%.0f초) 종료 - 확정 이탈" % [room.code, i, NetProtocol.IN_GAME_RECONNECT_GRACE_MSEC / 1000.0])
				_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": i, "reason": "timeout"})

		# 친구 대상 실제 베타 테스트 후속(사용자 지적) - 점유 슬롯 전원이
		# 확정 이탈했으면 볼 사람도 결과를 받을 사람도 없다. 그런데도 예전
		# 코드는 턴 자동 처리로 게임을 끝까지(그리고 그 뒤 재대전 대기
		# 2~3분까지) 계속 진행시켰다 - Render 무료 플랜에서는 이게 실제
		# 비용이다(방이 계속 "바쁜" 상태로 남아 유휴 정지에 안 들어감).
		# 남은 턴을 마저 진행하지 않고 이 자리에서 바로 방을 해제한다.
		if room.all_occupied_slots_past_grace():
			_tear_down_abandoned_room(room, "점유 슬롯 전원 확정 이탈")
			continue

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


## 친구 대상 실제 베타 테스트 후속(사용자 지적) - 볼 사람이 아무도 없는
## 방을 즉시 완전히 정리한다. `RoomManager.force_vacate_slot()`이 슬롯을
## 하나씩 비우고(마지막 슬롯이 비는 순간 `rooms`에서 자동으로 지워짐 -
## `Room` 자체가 `RefCounted`라 그 뒤로는 참조가 없어 곧바로 GC 대상이
## 되므로 `game_state`/`transfer_*` 등 Room 내부 필드는 따로 안 지워도
## 된다), 방 코드에 매인 서버 레벨 상태(`_relay_confirm_state`/
## `_next_timer_broadcast_msec`)도 같이 지운다 - 안 지우면 서버를 오래
## 켜둘수록(방 코드가 계속 새로 발급되므로) 이 두 Dictionary가 조금씩
## 샌다.
func _tear_down_abandoned_room(room: Room, reason: String) -> void:
	print("[서버] 방 %s 해제: %s" % [room.code, reason])
	for i in room.slots.size():
		if room.slots[i] != null:
			room_manager.force_vacate_slot(room, i)
	_relay_confirm_state.erase(room.code)
	_next_timer_broadcast_msec.erase(room.code)


## 2-6B(같은 방에서 재대전) - 매 프레임 REMATCHING 방들을 진행시킨다.
## 서로 독립적인 두 타임아웃을 본다: (1) 끊긴 채 자기 몫의 유예
## (NetProtocol.POST_GAME_RECONNECT_GRACE_MSEC, 3분)가 다 된 슬롯 - 방
## 전체 대기와 무관하게 그 슬롯 하나만 내보낸다. (2) 방 전체 대기 상한
## (NetProtocol.REMATCH_READY_TIMEOUT_MSEC, 2분)을 넘기면 "연결은 멀쩡한데
## 그냥 준비를 안 누른" 슬롯을 전부 내보낸다(끊긴 슬롯은 이제 (1)로
## 따로 관리되므로 여기 대상이 아니다 - Room.not_ready_connected_slots()
## 참고). 두 타임아웃 다, 그 뒤로는 원래 로비처럼 무기한 대기로 자연히
## 넘어간다(다시 채워지고 전원 준비되면 _maybe_start_game()이 다음 판을
## 시작함).
func _service_rematch_rooms(now: int) -> void:
	for room in room_manager.rooms.values():
		if room.state != Room.State.REMATCHING:
			continue

		# (1) 끊긴 슬롯의 개별 유예 - room이 room_manager.rooms.values()
		# (타입 없는 Dictionary)의 루프 변수라 Variant로 취급돼서, 반환
		# 타입이 있는 메서드를 불러도 := 로는 타입 추론이 안 된다(이
		# 세션에서 반복된 함정) - 명시적으로 타입을 적어준다.
		var grace_expired_slots: Array = room.grace_expired_disconnected_slots(now)
		if not grace_expired_slots.is_empty():
			# 방송을 전부 먼저 끝내고 나서 비운다(아래 (2)와 같은 이유 -
			# _broadcast_room()이 그 순간의 room.slots를 그대로 훑으므로,
			# 한 슬롯을 먼저 비운 채로 다음 슬롯의 이탈을 방송하면 이미
			# 비워진 슬롯의 주인이 그 뒤 퇴장 알림을 못 받는다).
			for i in grace_expired_slots:
				print("[서버] 방 %s: 슬롯 %d 재대전 대기 중 재접속 유예(%.0f초) 종료 - 확정 이탈" % [room.code, i, NetProtocol.POST_GAME_RECONNECT_GRACE_MSEC / 1000.0])
				_broadcast_room(room, NetProtocol.MSG_PLAYER_LEFT, {"player_index": i, "reason": "timeout"})
			for i in grace_expired_slots:
				room_manager.force_vacate_slot(room, i)
			# force_vacate_slot()이 방을 비웠으면(전원 이탈) rooms에서 이미
			# 지워졌으므로 이 방은 더 건드리지 않는다.
			if not room_manager.rooms.values().has(room):
				continue

		# (2) 방 전체 대기 상한 - "연결된 채 준비 안 한" 슬롯만 대상이다.
		if room.is_rematch_wait_timed_out(now):
			var not_ready_slots: Array = room.not_ready_connected_slots()

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
	if room == null:
		_log_ignored(NetProtocol.MSG_PACK_READY, "방을 찾을 수 없음", sender_id)
		return
	if room.state != Room.State.TRANSFERRING:
		_log_ignored(NetProtocol.MSG_PACK_READY, "TRANSFERRING 상태가 아님", sender_id, room)
		return

	var slot_index := room.find_slot_by_peer(sender_id)
	if slot_index == -1:
		_log_ignored(NetProtocol.MSG_PACK_READY, "이 peer의 슬롯을 못 찾음", sender_id, room)
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
	if room == null:
		_log_ignored(NetProtocol.MSG_REQUEST_CHARACTER_PACK, "방을 찾을 수 없음", sender_id)
		return
	if room.state != Room.State.TRANSFERRING:
		_log_ignored(NetProtocol.MSG_REQUEST_CHARACTER_PACK, "TRANSFERRING 상태가 아님", sender_id, room)
		return

	var owner_index = _payload_int(payload, "owner_index")
	if owner_index == null:
		_log_ignored(NetProtocol.MSG_REQUEST_CHARACTER_PACK, "owner_index 형식이 올바르지 않음", sender_id, room)
		return

	var requester_index := room.find_slot_by_peer(sender_id)
	if requester_index == -1:
		_log_ignored(NetProtocol.MSG_REQUEST_CHARACTER_PACK, "이 peer의 슬롯을 못 찾음", sender_id, room)
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
	if room == null:
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "방을 찾을 수 없음", sender_id)
		return
	if room.state != Room.State.TRANSFERRING:
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "TRANSFERRING 상태가 아님", sender_id, room)
		return

	var hash := str(payload.get("hash", ""))
	if hash.is_empty() or not room.transfer_hash_owners.has(hash):
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "알 수 없는 해시(%s)" % hash, sender_id, room)
		return
	if room.find_slot_by_peer(sender_id) != room.transfer_hash_owners[hash]:
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "이 해시의 소유자가 아님(해시=%s)" % hash, sender_id, room)
		return

	var sequence = _payload_int(payload, "sequence")
	var total_chunks = _payload_int(payload, "total_chunks")
	var total_bytes = _payload_int(payload, "total_bytes")
	if sequence == null or total_chunks == null or total_bytes == null:
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "sequence/total_chunks/total_bytes 형식이 올바르지 않음", sender_id, room)
		return
	if total_chunks <= 0 or sequence < 0 or sequence >= total_chunks:
		_log_ignored(NetProtocol.MSG_UPLOAD_PACK_CHUNK, "sequence(%s)가 범위 밖(총 %s개)" % [sequence, total_chunks], sender_id, room)
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

	# 확정 2(실제 베타 테스트 - 청크 유실) - 예전엔 "확인된 개수"만 셌다
	# (confirmed += 1, expected = total_chunks * recipients.size()). 그런데
	# 받는 쪽이 결측을 알아채고 request_pack_chunks로 재전송을 요청하면,
	# 소유자가 같은 순번을 다시 업로드해서 이 함수가 그 순번에 대해 또
	# 불린다 - 그 시점에도 room.transfer_current_hash가 아직 안 바뀌었으면
	# (진행이 막혀 있었으니 흔한 경우) is_current_hash가 다시 true가 되어
	# 같은 (순번,수신자) 쌍의 on_sent가 두 번 잡힌다. 개수만 세면 이 중복이
	# 다른 진짜 미확인 쌍의 몫까지 채워버려서, confirmed가 expected에 도달해
	# "전부 실제 송신됨"으로 오판할 수 있다 - 실제로 로그에서 확인된 사고다
	# (18개가 실제로는 못 갔는데 "59개 전부 송신됨"이 찍힘). 이제 각
	# (순번,수신자) 쌍의 성공 여부를 Dictionary 플래그로 정확히 추적한다 -
	# 같은 쌍이 두 번 잡혀도 같은 키에 true를 두 번 쓸 뿐 개수가 안 늘어나므로,
	# 진짜로 아직 안 간 쌍이 하나라도 있으면 완료 판정이 흔들리지 않는다.
	var state: Dictionary = {}
	if is_current_hash:
		state = _relay_confirm_state.get(room.code, {})
		if state.get("hash", "") != hash:
			# 친구 대상 실제 베타 테스트 후속(사용자 요청) - 완료 로그에 실제
			# 걸린 시간을 남기려면 시작 시각을 여기서(그 해시의 첫 청크가
			# 도착한 순간) 찍어둬야 한다 - 지금까지의 측정은 전부 루프백
			# (같은 프로세스 안 소켓)뿐이라 실제 네트워크 상의 수치가 필요하다.
			state = {"hash": hash, "recipients": recipients.duplicate(), "total_chunks": total_chunks, "total_bytes": total_bytes, "confirmed": {}, "uploader_done": false, "started_msec": Time.get_ticks_msec()}
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
		var confirmed_recipient_index: int = recipient_index
		var confirmed_sequence: int = sequence
		var on_sent := func() -> void:
			if confirm_current:
				print("[서버][전송] 청크 %d/%d 실제 송신 완료 → peer %d(해시=%s)" % [seq_display, total_chunks, peer_id, hash.substr(0, 8)])
				_mark_relay_confirmed(room_code, hash, confirmed_recipient_index, confirmed_sequence)
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
	if room == null:
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "방을 찾을 수 없음", sender_id)
		return
	if room.state != Room.State.TRANSFERRING:
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "TRANSFERRING 상태가 아님", sender_id, room)
		return

	var hash := str(payload.get("hash", ""))
	if hash.is_empty() or not room.transfer_hash_owners.has(hash):
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "알 수 없는 해시(%s)" % hash, sender_id, room)
		return

	var requester_index := room.find_slot_by_peer(sender_id)
	if requester_index == -1:
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "이 peer의 슬롯을 못 찾음", sender_id, room)
		return

	var sequences_raw = payload.get("sequences")
	if typeof(sequences_raw) != TYPE_ARRAY or sequences_raw.is_empty():
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "sequences가 비어있거나 배열이 아님", sender_id, room)
		return

	var sequences: Array = []
	for value in sequences_raw:
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		var seq := int(value)
		if seq >= 0 and not sequences.has(seq):
			sequences.append(seq)
	if sequences.is_empty():
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "유효한 sequence가 하나도 없음", sender_id, room)
		return

	if not room.mark_chunk_resend_requested(hash, requester_index):
		print("[서버][전송] 방 %s: 슬롯 %d의 해시 %s 재전송 요청이 상한(%d회)을 넘어 무시함" % [room.code, requester_index, hash.substr(0, 8), NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH])
		return

	var owner_index: int = room.transfer_hash_owners[hash]
	if owner_index < 0 or owner_index >= room.slots.size() or room.slots[owner_index] == null:
		_log_ignored(NetProtocol.MSG_REQUEST_PACK_CHUNKS, "해시 소유자 슬롯이 이미 비어있음", sender_id, room)
		return

	print("[서버][전송] 방 %s: 슬롯 %d가 해시 %s의 청크 %s 재전송 요청" % [room.code, requester_index, hash.substr(0, 8), sequences])
	_send(room.slots[owner_index]["peer_id"], NetProtocol.MSG_PACK_CHUNKS_REQUESTED, {"hash": hash, "sequences": sequences})


## _send()/_flush_outgoing_queues()가 청크 하나의 put_packet()이 실제로
## 성공했을 때 부르는 콜백 - (순번,수신자) 쌍 하나를 플래그로 표시하고
## 전부 다 됐는지 본다. 같은 쌍이 재전송 등으로 두 번 불려도(위
## _handle_upload_pack_chunk() 주석 참고) 같은 키에 true를 두 번 쓸 뿐이라
## 안전하다(확정 2).
func _mark_relay_confirmed(room_code: String, hash: String, recipient_index: int, sequence: int) -> void:
	var room := room_manager.get_room(room_code)
	if room == null:
		return
	var state: Dictionary = _relay_confirm_state.get(room_code, {})
	if state.get("hash", "") != hash:
		return  # 이미 다음 해시로 넘어간 뒤 뒤늦게 확인된 것 - 무시.
	var confirmed: Dictionary = state.get("confirmed", {})
	var seqs: Dictionary = confirmed.get(recipient_index, {})
	seqs[sequence] = true
	confirmed[recipient_index] = seqs
	state["confirmed"] = confirmed
	_relay_confirm_state[room_code] = state
	_maybe_finish_relay(room, state)


## 확정 2(실제 베타 테스트) - "몇 개 확인됐는지" 개수가 아니라, 이 해시를
## 요청한 수신자 전원에 대해 total_chunks개 순번이 빠짐없이 개별
## 확인됐는지를 직접 순회해서 판정한다. 재전송으로 같은 쌍이 중복
## 확인돼도(Dictionary라 개수가 안 늘어남) 다른 쌍이 하나라도 안 됐으면
## 절대 true가 안 된다.
func _all_relay_pairs_confirmed(state: Dictionary) -> bool:
	var confirmed: Dictionary = state.get("confirmed", {})
	var total_chunks: int = state.get("total_chunks", 0)
	for recipient_index in state.get("recipients", []):
		var seqs: Dictionary = confirmed.get(recipient_index, {})
		if seqs.size() < total_chunks:
			return false
	return true


## 소유자로부터 마지막 순번까지 받았고(uploader_done), 그 청크들이 수신자
## 전원에게 실제로 다 나간 것(_all_relay_pairs_confirmed())까지 확인되면
## 그때 다음 해시로 넘어간다.
func _maybe_finish_relay(room: Room, state: Dictionary) -> void:
	if not state.get("uploader_done", false):
		return
	if not _all_relay_pairs_confirmed(state):
		return
	var total_pairs: int = state.get("total_chunks", 0) * state.get("recipients", []).size()
	# 친구 대상 실제 베타 테스트 후속(사용자 요청) - 소요 시간을 남긴다.
	# 지금까지 이 세션에서 측정한 시간(예: 59청크/1.9MB 비교)은 전부
	# 같은 프로세스 안 루프백 소켓 기준이라 실제 네트워크에서는 이보다
	# 오래 걸릴 수 있다 - 실측이 필요하다는 게 사용자 지적.
	var duration_sec := (Time.get_ticks_msec() - int(state.get("started_msec", Time.get_ticks_msec()))) / 1000.0
	print("[서버][전송] 해시 %s 전송 완료 (%d청크, %d바이트, %.1f초) - 청크×수신자 %d개 전부 실제 송신됨(개별 확인), 다음 해시로 진행" % [str(state.get("hash", "")).substr(0, 8), state.get("total_chunks", 0), state.get("total_bytes", 0), duration_sec, total_pairs])
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
## 확정 2(실제 베타 테스트 - 청크 유실) - `put_packet()`의 반환값은 보내는
## 쪽 버퍼가 넘칠 때 이 초과를 알려주지 않는다는 게 직접 재현으로 확인된
## 사실이다(Godot 4.7.2, WebSocketMultiplayerPeer). 버퍼가 이미 꽉 찬
## 상태에서 `put_packet()`을 또 부르면 엔진 콘솔에는
## `Condition "... > outbound_buffer_size" is true. Returning: ERR_OUT_OF_MEMORY`
## 가 찍히지만, `put_packet()` 자체는 그래도 `OK`(0)를 돌려준다 - 그 바이트는
## 조용히 사라진다. 그래서 반환값을 사후에 확인하는 기존 방식은 이
## 실패 유형을 절대 못 잡는다(직접 만든 최소 재현 스크립트로 10번 연속
## put_packet()을 불러 확인함 - 5번째부터 버퍼가 찼는데도 10번 전부 OK를
## 반환했고, 실제로 도착한 건 5번째 것 하나뿐이었다).
##
## 그래서 반환값 대신 `get_current_outbound_buffered_amount()`로 "지금
## 이미 못 나간 데이터가 버퍼에 얼마나 남아있는지"를 **호출 전에 미리**
## 확인한다(`NetProtocol.has_room_to_send_now()`). 확정 2 후속(사용자
## 지적) - 처음엔 "조금이라도 남아있으면 무조건 큐로" 했는데, 그러면
## 프레임당 패킷 하나만 나가서 1MB로 키운 버퍼가 사실상 무의미해지고
## 팩 전송이 크게 느려진다(실측 - 아래 참고). 지금은 "남은 양 + 이번 크기 +
## 청크 하나만큼의 여유"가 실제 한도를 넘지 않으면 바로 보낸다.
func _send(peer_id: int, type: String, payload: Dictionary, on_sent: Callable = Callable()) -> bool:
	var ws_peer := peer.get_peer(peer_id)
	if ws_peer == null or ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false

	var bytes := NetProtocol.encode(type, payload)
	var queue: Array = _outgoing_queues.get(peer_id, [])
	var has_room := NetProtocol.has_room_to_send_now(ws_peer.get_current_outbound_buffered_amount(), bytes.size(), ws_peer.get_outbound_buffer_size())
	if not queue.is_empty() or not has_room:
		queue.append({"bytes": bytes, "on_sent": on_sent})
		_outgoing_queues[peer_id] = queue
		return false

	peer.set_target_peer(peer_id)
	if peer.put_packet(bytes) != OK:
		# 반환값 자체를 못 믿는다는 게 위에서 확인된 사실이지만, 그렇다고
		# 이 검사를 없애지는 않는다 - 다른 이유(예: 연결이 그 사이 끊김)로
		# 진짜 에러가 나는 경우까지 놓치면 안 되므로 방어적으로 유지한다.
		queue.append({"bytes": bytes, "on_sent": on_sent})
		_outgoing_queues[peer_id] = queue
		return false

	_last_sent_msec[peer_id] = Time.get_ticks_msec()
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
			_outgoing_stall_last_size.erase(peer_id)
			_outgoing_stall_last_progress_msec.erase(peer_id)
			_outgoing_stall_next_warning_msec.erase(peer_id)
			continue

		peer.set_target_peer(peer_id)
		while not queue.is_empty():
			# 확정 2 후속 - put_packet() 전에 버퍼에 여유가 있는지 먼저
			# 확인한다(반환값만으로는 못 믿는다는 게 실측으로 확인된 사실 -
			# 위 _send() 주석 참고). "조금이라도 남아있으면 무조건 대기"가
			# 아니라 has_room_to_send_now()로 "이 항목 하나는 지금 보내도
			# 안전한지"를 판단한다 - 그래야 한 프레임에 여러 개를 몰아
			# 보낼 수 있어 1MB 버퍼가 실제로 의미 있게 쓰인다. 여유가 없으면
			# 이번 프레임은 여기서 멈추고 다음 프레임에 다시 확인한다.
			var entry: Dictionary = queue[0]
			if not NetProtocol.has_room_to_send_now(ws_peer.get_current_outbound_buffered_amount(), entry["bytes"].size(), ws_peer.get_outbound_buffer_size()):
				break
			if peer.put_packet(entry["bytes"]) != OK:
				break
			_last_sent_msec[peer_id] = Time.get_ticks_msec()
			queue.pop_front()
			var on_sent: Callable = entry.get("on_sent", Callable())
			if on_sent.is_valid():
				on_sent.call()

		_check_outgoing_stall(peer_id, queue.size(), ws_peer)

		if queue.is_empty():
			_outgoing_queues.erase(peer_id)


## 데드락 방지 안전장치 2/3 - 위 필드 주석 참고. queue_size가 0이면(이번
## 프레임에 다 빠졌으면) 정체 추적을 지운다 - 다음 정체는 처음부터 다시
## 잰다. 큐가 줄지 않고 유지되거나 늘어나기만 하면 진전이 아니다.
func _check_outgoing_stall(peer_id: int, queue_size: int, ws_peer: WebSocketPeer) -> void:
	if queue_size == 0:
		_outgoing_stall_last_size.erase(peer_id)
		_outgoing_stall_last_progress_msec.erase(peer_id)
		_outgoing_stall_next_warning_msec.erase(peer_id)
		return

	var now := Time.get_ticks_msec()
	var last_size: int = _outgoing_stall_last_size.get(peer_id, -1)
	if last_size == -1 or queue_size < last_size:
		_outgoing_stall_last_size[peer_id] = queue_size
		_outgoing_stall_last_progress_msec[peer_id] = now
		_outgoing_stall_next_warning_msec.erase(peer_id)
		return

	_outgoing_stall_last_size[peer_id] = queue_size
	var last_progress: int = _outgoing_stall_last_progress_msec.get(peer_id, now)
	var stalled_sec := (now - last_progress) / 1000.0
	var next_warning: int = _outgoing_stall_next_warning_msec.get(peer_id, 0)
	if stalled_sec < NetProtocol.TRANSFER_STALL_WARNING_SEC or now < next_warning:
		return

	var waiting_bytes := 0
	var queue: Array = _outgoing_queues.get(peer_id, [])
	if not queue.is_empty():
		waiting_bytes = queue[0]["bytes"].size()
	printerr("[서버][경고] peer %d 보내기 대기열 %.0f초간 진전 없음 - 대기열 %d개, 버퍼 사용량 %d/%d바이트, 맨 앞 메시지 %d바이트" % [peer_id, stalled_sec, queue_size, ws_peer.get_current_outbound_buffered_amount(), ws_peer.get_outbound_buffer_size(), waiting_bytes])
	_outgoing_stall_next_warning_msec[peer_id] = now + int(NetProtocol.TRANSFER_STALL_WARNING_SEC * 1000)


func _broadcast_room(room: Room, type: String, payload: Dictionary, exclude_peer_id: int = -1) -> void:
	for slot in room.slots:
		if slot != null and slot["peer_id"] != exclude_peer_id:
			_send(slot["peer_id"], type, payload)


func _send_error(peer_id: int, code: String, message: String) -> void:
	# 1번 버그 조사(사용자 요청) - "왜 클릭이 안 먹히는지" 조사할 때 서버가
	# 실제로 거부 응답을 보냈는지가 클라이언트 로그만으로는 안 보일 수 있다
	# (2-4B 이전 온라인 화면처럼 지금 안 보이는 패널의 라벨에 문구가 써지는
	# 경우 등) - 서버 콘솔에도 항상 남겨서 클라이언트가 받았는지와 무관하게
	# "서버가 거부를 시도했다" 자체를 확인할 수 있게 한다.
	print("[서버][에러 응답] peer=%d code=%s message=%s" % [peer_id, code, message])
	_send(peer_id, NetProtocol.MSG_ERROR, {"code": code, "message": message})


## 1번 버그 조사(사용자 요청 - "조용히 버려지는 경로를 하나도 남기지
## 마라") - 검증에 실패해 메시지를 그냥 버리는(에러 응답조차 안 보내는)
## 모든 지점이 이 함수를 거친다. 이 프로젝트는 "보냈는데 도착 안 함"으로
## 이미 여러 번 데었다(§8.5-1~4) - "도착했는데 조용히 버려짐"은 그
## 사촌이라 흔적을 하나도 안 남기면 똑같이 못 잡는다.
func _log_ignored(message_type: String, reason: String, sender_id: int, room: Room = null) -> void:
	var room_code: String = room.code if room != null else "(없음)"
	var room_state: String = Room.State.keys()[room.state] if room != null else "-"
	print("[서버][무시됨] 메시지=%s 사유=%s peer=%d 방=%s 상태=%s" % [message_type, reason, sender_id, room_code, room_state])
