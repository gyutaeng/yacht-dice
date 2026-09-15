class_name PackTransferClient
extends Node

# 클라이언트 쪽 캐릭터 팩 전송 상태 기계(2-5 §2단계, docs/multiplayer.md §8).
# online_screen.gd가 GameClient처럼 자식으로 하나 들고 있는다. 서버가 해시
# 하나씩만 순서대로 보내주므로("한 번에 하나씩") 이 클래스는 그 순서를
# 그대로 따라가기만 하면 되고 별도 스케줄링이 필요 없다.
#
# 슬롯(플레이어)별 상태는 SlotState로 추적하지만, 실제 네트워크 요청/버퍼는
# "해시" 단위다 - 같은 캐릭터를 고른 여러 슬롯이 있으면 요청도 버퍼도 하나만
# 쓰고, 완료되면 그 해시를 쓰는 슬롯 전원에게 동시에 profile_ready를 emit한다.

signal profile_ready(player_index: int, profile: CharacterProfile)
## 진행률/대기 표시(get_status_text())가 바뀔 때마다 emit - UI는 이 신호만
## 구독하고 실제 문구는 get_status_text()로 다시 조회한다.
signal progress_changed()
## 전송 단계별 진단 로그 - "웹은 브라우저 콘솔의 print()를 못 믿는다"(1-5)는
## 이유로 화면에 직접 찍어야 해서, GameEvents와 같은 패턴으로 emit만 하고
## 실제로 어디에 찍을지는 구독자(online_screen.gd)가 정한다.
## BuildInfo.DEBUG_MODE가 꺼져 있으면 _log()가 아예 emit하지 않는다 -
## 릴리스에서는 이 신호가 조용해야 한다(개발용 로그이지 사용자 대상
## 메시지가 아니다).
signal debug_log(text: String)

enum SlotState { NONE, WAITING, RECEIVING, DONE, FAILED }

var slot_states: Dictionary = {}  # player_index(int) -> SlotState
var current_waiting_hash: String = ""

var _client: GameClient
var _my_index: int = -1
var _my_pack_bytes: PackedByteArray = PackedByteArray()
var _my_pack_hash: String = ""
var _players: Dictionary = {}
var _resolved_profiles: Dictionary = {}  # player_index -> CharacterProfile

var _hash_to_players: Dictionary = {}  # hash(String) -> Array[int]
var _my_pending_hashes: Dictionary = {}  # hash(String) -> true, 아직 안 끝난 것만 남음
var _total_pending_count: int = 0
var _completed_count: int = 0
var _receive_buffers: Dictionary = {}  # hash(String) -> {"total_chunks": int, "chunks": Array}
var _current_transfer_deadline_msec: int = 0
var _pack_ready_sent: bool = false

# 카운트다운/멈춤 감지(사용자 신고 - "타임아웃까지 N초"가 60에서 안
# 내려감) - 원인은 get_status_text()가 진짜로 멈춘 게 아니라, 그걸 화면에
# 반영하는 online_screen.gd의 갱신이 progress_changed(청크 이벤트 등)에만
# 걸려 있어서 이벤트가 끊기면 화면도 같이 멈춘 것이었다(§실제 시간
# 계산 자체는 Time.get_ticks_msec() 기반이라 안 멈췄음). _process()에서
# 매 프레임 표시값이 바뀌었는지 직접 확인해서, 전송이 멈춰도 카운트다운은
# 계속 내려가게 한다.
var _last_displayed_remaining_sec: int = -1

# 멈춤 감지 - 마지막으로 "진전"(대기열이 줄었거나 청크를 받은 시각)을
# 기록해뒀다가, 일정 시간 이상 안 움직이면 화면/콘솔에 경고를 남긴다.
# 보내는 쪽(내 업로드 대기열)은 한 번에 하나만 활성화되므로 전역 값으로
# 충분하다.
var _last_send_queue_size: int = -1
var _last_send_progress_msec: int = 0
var _next_send_stall_warning_msec: int = 0

# 받는 쪽 멈춤 감지·결측 청크 재전송(2-5 후속) - 해시별로 따로 추적한다.
# "서버가 청크를 성공적으로 보내면 바로 다음 해시로 넘어간다"는 스케줄러
# 특성상, 내가 결측을 알아챌 때쯤엔 이미 current_waiting_hash가 다음 해시로
# 넘어가 있는 경우가 흔하다 - 그래서 current_waiting_hash 하나만 보지 않고
# _my_pending_hashes에 남은 해시 전부를 매 프레임 독립적으로 검사한다.
# 값은 해당 해시의 pack_upload_requested가 실제로 도착한 뒤에만 등록된다
# (아직 대기열에서 자기 차례를 못 받은 해시까지 "멈췄다"고 오판하지
# 않기 위함 - _check_receive_stall()이 등록 안 된 해시는 건너뛴다).
var _hash_last_chunk_msec: Dictionary = {}  # hash(String) -> int
var _hash_next_stall_warning_msec: Dictionary = {}  # hash(String) -> int

# 결측 청크 재전송(2-5 후속) - 해시별 재전송 요청 횟수. 서버도 독립적으로
# 같은 상한을 강제하지만(원칙 6), 여기서 먼저 세어두면 이미 포기한 해시에
# 계속 요청을 보내는 낭비를 피할 수 있다.
var _retransmit_attempts: Dictionary = {}  # hash(String) -> int


func _log(text: String) -> void:
	if BuildInfo.DEBUG_MODE:
		debug_log.emit(text)


## "[P2]" 또는 여러 슬롯이 같은 해시를 쓰면 "[P2,P3]" - 어느 슬롯 얘기인지
## 로그만 보고 바로 알 수 있게(사용자 요청 형식).
func _player_tag(hash: String) -> String:
	var players_with_hash: Array = _hash_to_players.get(hash, [])
	if players_with_hash.is_empty():
		return "[?]"
	var tags: Array[String] = []
	for player_index in players_with_hash:
		tags.append("P%d" % (player_index + 1))
	return "[%s]" % ",".join(tags)


func _format_commas(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	return result


## 카운트다운(1)과 멈춤 감지(2)를 진행 중인 전송과 무관하게 매 프레임
## 확인한다 - 둘 다 "청크 이벤트가 와야만 갱신되는" 예전 방식의 함정을
## 피하려고 일부러 이벤트가 아니라 시간(Time.get_ticks_msec())을 직접 본다.
## 받는 쪽 멈춤 감지는 current_waiting_hash 하나만 보지 않고 _my_pending_hashes
## 전부를 돈다(결측 청크 재전송, 2-5 후속) - 서버가 이미 다음 해시로 넘어간
## 뒤에도 이전 해시의 결측을 계속 감지해야 하기 때문이다.
func _process(_delta: float) -> void:
	if not current_waiting_hash.is_empty():
		var remaining := _remaining_timeout_seconds()
		if remaining != _last_displayed_remaining_sec:
			_last_displayed_remaining_sec = remaining
			progress_changed.emit()

		if current_waiting_hash == _my_pack_hash and not _my_pack_bytes.is_empty():
			_check_send_stall()

	for hash in _my_pending_hashes.keys():
		_check_receive_stall(hash)


## 보내는 쪽 멈춤 감지 - GameClient의 보내기 대기열 크기가 한동안 안
## 줄어들면(0으로 다 빠지지도 않고, 그렇다고 계속 줄지도 않으면) 경고한다.
## 큐가 늘어나기만 하는 것도 "정체"로 본다(줄어드는 방향으로만 진전 인정).
func _check_send_stall() -> void:
	var queue_size := _client.get_outgoing_queue_size()
	var now := Time.get_ticks_msec()

	if _last_send_queue_size == -1 or queue_size < _last_send_queue_size or queue_size == 0:
		_last_send_queue_size = queue_size
		_last_send_progress_msec = now
		_next_send_stall_warning_msec = 0
		return

	_last_send_queue_size = queue_size
	if queue_size <= 0:
		return

	var stalled_sec := (now - _last_send_progress_msec) / 1000.0
	if stalled_sec >= NetProtocol.TRANSFER_STALL_WARNING_SEC and now >= _next_send_stall_warning_msec:
		_log("[경고] %.0f초간 진전 없음 - 내 업로드 보내기 대기열이 %d개에서 안 줄어듦" % [stalled_sec, queue_size])
		_next_send_stall_warning_msec = now + int(NetProtocol.TRANSFER_STALL_WARNING_SEC * 1000)


## 받는 쪽 멈춤 감지(해시 단위) - 청크를 하나도 못 받은 채로 계속 대기 중인
## 경우도 포함한다(그게 바로 "소유자가 아예 안 보내고 있다"는 신호이고,
## 그럴수록 받는 쪽 화면에 반드시 떠야 한다). _hash_last_chunk_msec에 아직
## 등록 안 된 해시(서버가 아직 자기 차례를 안 줘서 대기열에 있는 해시)는
## 검사하지 않는다 - 시작도 안 한 걸 "멈췄다"고 오판하면 안 되기 때문이다.
func _check_receive_stall(hash: String) -> void:
	if not _hash_last_chunk_msec.has(hash):
		return

	var now := Time.get_ticks_msec()
	var last: int = _hash_last_chunk_msec[hash]
	var stalled_sec := (now - last) / 1000.0
	var next_warning: int = _hash_next_stall_warning_msec.get(hash, 0)
	if stalled_sec < NetProtocol.TRANSFER_STALL_WARNING_SEC or now < next_warning:
		return

	_log("[경고] %.0f초간 진전 없음 - %s" % [stalled_sec, _describe_hash_state(hash)])
	_hash_next_stall_warning_msec[hash] = now + int(NetProtocol.TRANSFER_STALL_WARNING_SEC * 1000)
	_maybe_request_missing_chunks(hash)


## 결측 청크 재전송(2-5 후속) - 멈춤 경고와 같은 주기로, 빠진 순번이 있으면
## 그것만 재전송을 요청한다. 청크를 하나도 못 받은 상태(소유자가 아예 안
## 보내는 중)나 전부 받았지만 검증/저장 단계에서 멈춘 상태는 순번을 특정할
## 수 없어 요청하지 않는다(_describe_hash_state()가 이미 이 두 경우를
## 구분해 보여주지만, 여기서는 결측 목록 자체가 필요해 직접 다시 뽑는다).
## 상한(NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH)을 넘기면 더 요청하지
## 않고 기존 로컬/서버 타임아웃이 그대로 이어받아 기본 캐릭터로 넘어간다.
func _maybe_request_missing_chunks(hash: String) -> void:
	if not _receive_buffers.has(hash):
		return
	var buf: Dictionary = _receive_buffers[hash]
	var chunks: Array = buf.get("chunks", [])
	var missing: Array[int] = []
	for i in chunks.size():
		if chunks[i] == null:
			missing.append(i)
	if missing.is_empty():
		return

	var attempts: int = _retransmit_attempts.get(hash, 0)
	if attempts >= NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH:
		_log("%s 재전송 요청 상한(%d회) 도달 - 더 요청하지 않고 기존 타임아웃에 맡김" % [_player_tag(hash), NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH])
		return

	_retransmit_attempts[hash] = attempts + 1
	_log("%s 결측 순번 %s 재전송 요청(%d/%d회째)" % [_player_tag(hash), missing, attempts + 1, NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH])
	_client.request_pack_chunks(hash, missing)


func configure(client: GameClient) -> void:
	_client = client
	_client.pack_upload_requested.connect(_on_pack_upload_requested)
	_client.pack_chunk_received.connect(_on_pack_chunk_received)
	_client.pack_transfer_failed.connect(_on_pack_transfer_failed)
	_client.pack_chunks_requested.connect(_on_pack_chunks_requested)


## GameClient.transferring_started를 받으면 online_screen.gd가 이 함수를
## 부른다(그 시점의 _players/내 프로필을 넘겨줘야 하므로 - PackTransferClient는
## 로비 상태를 직접 안 들고 있음). 캐시에 이미 있거나 내 것과 같은 해시는
## 네트워크 요청 없이 즉시 DONE으로 처리한다(2-5 §1단계 요구사항의 실제 적용).
func begin(my_index: int, my_profile: CharacterProfile, my_pack_bytes: PackedByteArray, my_pack_hash: String, players: Dictionary) -> void:
	_my_index = my_index
	_my_pack_bytes = my_pack_bytes
	_my_pack_hash = my_pack_hash
	_players = players

	slot_states.clear()
	_resolved_profiles.clear()
	_hash_to_players.clear()
	_my_pending_hashes.clear()
	_receive_buffers.clear()
	_retransmit_attempts.clear()
	_hash_last_chunk_msec.clear()
	_hash_next_stall_warning_msec.clear()
	current_waiting_hash = ""
	_completed_count = 0
	_pack_ready_sent = false
	_last_displayed_remaining_sec = -1
	_reset_stall_tracking()

	var requested_hashes := {}

	for player_index in players.keys():
		if player_index == my_index:
			continue
		var hash: String = str(players[player_index].get("meta", {}).get("pack_hash", ""))
		if hash.is_empty():
			slot_states[player_index] = SlotState.NONE
			_resolved_profiles[player_index] = _fallback_profile(player_index)
			continue

		if not _hash_to_players.has(hash):
			_hash_to_players[hash] = []
		_hash_to_players[hash].append(player_index)

		if hash == my_pack_hash and not my_pack_bytes.is_empty():
			_mark_resolved(player_index, hash, my_profile)
			continue

		var cached := ReceivedPackCache.load_cached(hash)
		if cached != null:
			_mark_resolved(player_index, hash, cached)
			continue

		slot_states[player_index] = SlotState.WAITING
		if not requested_hashes.has(hash):
			requested_hashes[hash] = true
			_my_pending_hashes[hash] = true
			_client.request_character_pack(player_index)

	_total_pending_count = _my_pending_hashes.size()
	_log("begin(): 내 해시=%s, 필요한 해시 %d개(%s)" % [
		_my_pack_hash.substr(0, 8) if not _my_pack_hash.is_empty() else "(없음)",
		_total_pending_count,
		", ".join(_my_pending_hashes.keys().map(func(h): return str(h).substr(0, 8))),
	])
	progress_changed.emit()
	_maybe_send_pack_ready()


func get_profile(player_index: int) -> CharacterProfile:
	return _resolved_profiles.get(player_index)


## 받을 팩이 있든 없든, 성공했든 실패했든 - "더 기다릴 게 없다"가 확정되는
## 순간(_my_pending_hashes가 비는 순간) 딱 한 번만 서버에 알린다(2-5 후속).
## 받을 게 아예 없는 클라이언트는 begin() 끝에서 바로 비어있으므로 즉시
## 전송된다 - 안 그러면 그 방은 영원히 시작되지 않는다.
func _maybe_send_pack_ready() -> void:
	if _pack_ready_sent or not _my_pending_hashes.is_empty():
		return
	_pack_ready_sent = true
	_log("모든 팩 처리 완료(성공/실패 포함) - pack_ready 전송")
	_client.send_pack_ready()


## 아직 처리 중인 해시가 남아있는지(online_screen.gd의 game_started 가드용).
func is_all_resolved() -> bool:
	return _my_pending_hashes.is_empty()


## _my_pending_hashes가 빌 때까지 기다리되, timeout_msec을 넘기면 남은
## 해시를 전부 강제로 포기(기본 캐릭터로 대체)하고 돌아온다(2-5 후속 -
## 이 대기에 상한이 없어서 청크 하나가 영영 안 오면 게임 화면으로 절대
## 못 넘어가던 확실한 버그를 고침). timeout_msec 기본값은
## NetProtocol.LOCAL_PACK_RESOLVE_TIMEOUT_MSEC - 테스트에서 짧은 값을
## 넣어 빠르게 검증할 수 있게 매개변수로 뺐다.
##
## await progress_changed처럼 "이벤트가 와야 깨어나는" 방식을 쓰지 않고
## 매 프레임 직접 확인한다 - 멈춘 상황이면 애초에 progress_changed가 다시
## 안 올 수 있으므로, 그 이벤트를 기다리는 방식으로는 타임아웃 판정 자체가
## 영원히 실행되지 않는다.
func wait_until_all_resolved(timeout_msec: int = NetProtocol.LOCAL_PACK_RESOLVE_TIMEOUT_MSEC) -> void:
	if _my_pending_hashes.is_empty():
		return

	for hash in _my_pending_hashes.keys():
		_log("대기 중인 해시 %s %s" % [_player_tag(hash), _describe_hash_state(hash)])

	var deadline := Time.get_ticks_msec() + timeout_msec
	while not _my_pending_hashes.is_empty():
		if Time.get_ticks_msec() >= deadline:
			_force_resolve_remaining_as_failed(timeout_msec)
			return
		await get_tree().process_frame


## 시간 안에 안 끝난 해시를 전부 강제로 실패 처리한다 - 원인이 무엇이든
## "게임 화면으로 못 넘어간다"는 경로가 있으면 안 된다.
func _force_resolve_remaining_as_failed(timeout_msec: int) -> void:
	for hash in _my_pending_hashes.keys().duplicate():
		_log("%s 로컬 처리 시간 초과(%.0f초) - %s - 강제로 기본 캐릭터로 대체하고 진행" % [
			_player_tag(hash), timeout_msec / 1000.0, _describe_hash_state(hash),
		])
		_resolve_hash_failed(hash)


## 해시 하나가 지금 어느 단계이고 왜 안 끝났는지 사람이 읽을 문자열로
## 요약한다(2-5 후속 - "처리 중인 해시가 남음"이라고만 하고 무엇이 왜
## 남았는지 안 보이던 문제 수정) - 청크가 일부 빠진 것과 전부 받았지만
## 검증/저장에 걸린 것을 구분해서 보여준다.
func _describe_hash_state(hash: String) -> String:
	if not _receive_buffers.has(hash):
		return "청크를 하나도 못 받음(업로드 요청이 아직 안 왔거나 소유자가 응답 안 함)"

	var buf: Dictionary = _receive_buffers[hash]
	var chunks: Array = buf.get("chunks", [])
	var total_chunks: int = buf.get("total_chunks", 0)
	var missing: Array = []
	for i in chunks.size():
		if chunks[i] == null:
			missing.append(i)

	if missing.is_empty() and total_chunks > 0:
		return "청크 %d/%d 전부 수신 완료, 검증/저장 단계에서 멈춤(아직 프로필이 안 나옴)" % [total_chunks, total_chunks]
	return "청크 %d/%d 수신, 결측 인덱스 %s%s" % [
		chunks.size() - missing.size(), total_chunks, missing.slice(0, 10),
		"..." if missing.size() > 10 else "",
	]


## 로비 화면에 보여줄 한 줄 문구. 지금 아무 전송도 진행 중이 아니면 빈 문자열.
func get_status_text() -> String:
	if current_waiting_hash.is_empty():
		return ""
	if current_waiting_hash == _my_pack_hash:
		return "내 캐릭터를 상대에게 전송하는 중..."

	var owner_name := _display_name_for_hash(current_waiting_hash)
	if not _my_pending_hashes.has(current_waiting_hash):
		return "%s님 캐릭터 준비 중..." % owner_name

	var buf: Dictionary = _receive_buffers.get(current_waiting_hash, {})
	var total_chunks: int = buf.get("total_chunks", 0)
	var received := 0
	for c in buf.get("chunks", []):
		if c != null:
			received += 1
	var remaining_sec := _remaining_timeout_seconds()

	# 전송(청크 수신)과 검증/저장은 서로 다른 단계다(2-5 후속) - 청크가
	# 100% 다 왔어도 validate_and_extract_pack()/캐시 저장이 아직 안
	# 끝났을 수 있는데, 예전엔 이 구간이 그냥 "100%"로만 보여서 화면만
	# 보면 다 끝난 것처럼 보였다("전송 100% 뒤에도 할 일이 남았다"는 게
	# 안 드러남). total_chunks > 0인데 결측이 없으면 전송 단계는 끝난 것.
	if total_chunks > 0 and received >= total_chunks:
		return "%s님의 캐릭터 저장 처리 중... (타임아웃까지 %d초)" % [owner_name, remaining_sec]

	var percent := int(100.0 * received / total_chunks) if total_chunks > 0 else 0
	return "%s님의 캐릭터 받는 중 (%d/%d) %d%% (타임아웃까지 %d초)" % [owner_name, _completed_count + 1, max(_total_pending_count, 1), percent, remaining_sec]


func _remaining_timeout_seconds() -> int:
	var remaining_msec: int = _current_transfer_deadline_msec - Time.get_ticks_msec()
	return maxi(0, int(ceil(remaining_msec / 1000.0)))


func _on_pack_upload_requested(hash: String) -> void:
	_current_transfer_deadline_msec = Time.get_ticks_msec() + NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC
	_reset_stall_tracking()

	if hash == _my_pack_hash and not _my_pack_bytes.is_empty():
		_log("pack_upload_requested(%s) - 내 팩(%d바이트), 업로드 시작" % [hash.substr(0, 8), _my_pack_bytes.size()])
		_upload_my_pack(hash)
	elif _hash_to_players.has(hash):
		_log("pack_upload_requested(%s) - 내가 요청한 해시, 수신 대기" % hash.substr(0, 8))
		# 결측 청크 재전송(2-5 후속) - 이 해시의 멈춤 감지 기준점을 지금
		# 등록한다. _check_receive_stall()은 이 등록이 없는 해시(아직 대기열
		# 순서를 못 받은 해시)는 건너뛴다 - 그래서 여기서 등록하기 전까지는
		# "멈췄다"고 오판하지 않는다.
		_hash_last_chunk_msec[hash] = Time.get_ticks_msec()
		_hash_next_stall_warning_msec[hash] = 0
		for player_index in _hash_to_players[hash]:
			if slot_states.get(player_index) == SlotState.WAITING:
				slot_states[player_index] = SlotState.RECEIVING
	else:
		_log("pack_upload_requested(%s) - 남의 전송(구경만)" % hash.substr(0, 8))

	current_waiting_hash = hash
	progress_changed.emit()


## 모든 청크를 한 번에 upload_pack_chunk()로 넘기지만, 실제 소켓 전송은
## GameClient가 프레임마다 나눠서 처리한다("실전송의 착각" 사고가 이미
## 두 번 있었다 - §8.5-1/§8.5-2 - "요청함"/"큐 적재"를 "나갔다"로 읽으면
## 안 되므로, 여기서는 on_sent 콜백이 실제로 불릴 때만 "실제 전송 완료"를
## 찍는다. 큐에 들어간 시점은 별도로 "큐 적재"라고 정확히 구분해서 남긴다.
func _upload_my_pack(hash: String) -> void:
	var total_bytes := _my_pack_bytes.size()
	var total_chunks := int(ceil(float(total_bytes) / NetProtocol.CHUNK_PAYLOAD_BYTES))
	total_chunks = max(total_chunks, 1)
	_log("업로드 시작: 청크 %d개(각 %d바이트 이하), 총 %d바이트 - 아래 로그는 모두 '실제로 나간' 시점 기준" % [total_chunks, NetProtocol.CHUNK_PAYLOAD_BYTES, total_bytes])
	for i in total_chunks:
		_send_chunk(hash, total_bytes, total_chunks, i)


## 결측 청크 재전송(2-5 후속) - 서버가 내 팩의 빠진 순번을 다시 보내달라고
## 전달하면, 요청받은 순번만 _my_pack_bytes(업로드 단계 내내 메모리에 그대로
## 있음)에서 다시 잘라 보낸다. 새 전송 경로를 만들지 않고 _upload_my_pack()과
## 같은 _send_chunk()를 재사용한다 - 청크 하나를 만들고 보내는 방식이
## "처음 보내는지 다시 보내는지"에 따라 달라질 이유가 없다.
func _on_pack_chunks_requested(hash: String, sequences: Array[int]) -> void:
	if hash != _my_pack_hash or _my_pack_bytes.is_empty():
		return

	var total_bytes := _my_pack_bytes.size()
	var total_chunks := int(ceil(float(total_bytes) / NetProtocol.CHUNK_PAYLOAD_BYTES))
	total_chunks = max(total_chunks, 1)
	_log("재전송 요청 받음(해시=%s): 순번 %s" % [hash.substr(0, 8), sequences])
	for seq in sequences:
		if seq < 0 or seq >= total_chunks:
			continue
		_send_chunk(hash, total_bytes, total_chunks, seq, "재전송 ")


## _upload_my_pack()/_on_pack_chunks_requested() 공유 - 청크 하나를 잘라
## 보내고, 실제 put_packet() 성공 시점에만 "실제 전송 완료" 로그를 남긴다
## (§8.5-4 - "요청함"/"큐 적재"를 "나갔다"로 읽으면 안 됨).
func _send_chunk(hash: String, total_bytes: int, total_chunks: int, index: int, log_prefix: String = "") -> void:
	var start := index * NetProtocol.CHUNK_PAYLOAD_BYTES
	var end := mini(start + NetProtocol.CHUNK_PAYLOAD_BYTES, total_bytes)
	var chunk := _my_pack_bytes.slice(start, end)
	var seq_display := index + 1
	var on_sent := func() -> void:
		_log("%s청크 %d/%d 실제 전송 완료(해시=%s)" % [log_prefix, seq_display, total_chunks, hash.substr(0, 8)])
	var sent_now := _client.upload_pack_chunk(hash, index, total_chunks, total_bytes, Marshalls.raw_to_base64(chunk), on_sent)
	if not sent_now:
		_log("%s청크 %d/%d 큐 적재(대기열 %d개) - 실제 전송은 나중에 위 로그로 확인" % [log_prefix, seq_display, total_chunks, _client.get_outgoing_queue_size()])


func _on_pack_chunk_received(hash: String, sequence: int, total_chunks: int, data_base64: String) -> void:
	if not _receive_buffers.has(hash):
		_receive_buffers[hash] = {"total_chunks": total_chunks, "chunks": []}
	var buf: Dictionary = _receive_buffers[hash]
	buf["total_chunks"] = total_chunks
	var chunks: Array = buf["chunks"]
	if chunks.size() < total_chunks:
		chunks.resize(total_chunks)
	if sequence < 0 or sequence >= chunks.size():
		_log("청크 수신했지만 sequence(%d)가 범위 밖(총 %d개) - 무시함" % [sequence, total_chunks])
		return
	chunks[sequence] = Marshalls.base64_to_raw(data_base64)
	_hash_last_chunk_msec[hash] = Time.get_ticks_msec()
	_hash_next_stall_warning_msec[hash] = 0
	if sequence == 0 or sequence == total_chunks - 1 or (sequence + 1) % 10 == 0:
		_log("청크 %d/%d 수신함(해시=%s)" % [sequence + 1, total_chunks, hash.substr(0, 8)])
	progress_changed.emit()

	for c in chunks:
		if c == null:
			return  # 아직 다 안 옴.

	_log("청크 %d개 전부 수신 완료 - 검증 시작" % total_chunks)
	await _finalize_received_pack(hash, chunks)


## 압축 해제/디코딩이 한 프레임에 몰리지 않도록 CharacterLibrary에 self(Node)를
## 넘겨서 파일 하나 풀 때마다 한 프레임씩 기다린다(2-5 §웹에서 화면이 안
## 멈추게, 1-8에서 지적된 문제의 연장). 서버가 해시를 하나씩만 순서대로
## 보내주므로 이 함수도 한 번에 팩 하나만 처리한다 - 동시에 여러 명 분을
## 처리할 일이 없다.
func _finalize_received_pack(hash: String, chunks: Array) -> void:
	var tag := _player_tag(hash)
	var combined := PackedByteArray()
	for c in chunks:
		combined.append_array(c)
	_log("%s 팩 수신 완료 (%s바이트)" % [tag, _format_commas(combined.size())])

	var actual_hash := ReceivedPackCache.sha256_hex(combined)
	if actual_hash != hash:
		_log("%s 해시 대조 실패: 요청=%s 실제=%s" % [tag, hash.substr(0, 8), actual_hash.substr(0, 8)])
		push_warning("PackTransferClient: 받은 팩의 해시가 요청한 값과 다름 - 조용히 기본 캐릭터로 대체함(hash=%s)" % hash)
		_resolve_hash_failed(hash)
		return
	_log("%s 해시 대조 OK" % tag)

	var validated: Dictionary = await CharacterLibrary.validate_and_extract_pack(combined, self)
	if not validated["ok"]:
		_log("%s 검증 실패: %s" % [tag, validated["error"]])
		push_warning("PackTransferClient: 받은 팩 검증 실패 - 조용히 기본 캐릭터로 대체함(hash=%s, error=%s)" % [hash, validated["error"]])
		_resolve_hash_failed(hash)
		return
	var extracted: Dictionary = validated["extracted"]
	_log("%s 검증 OK (파일 %d개)" % [tag, extracted.size()])

	var profile := ReceivedPackCache.store(hash, extracted, validated["manifest_profile"])
	if profile.asset_base_dir != "":
		_log("%s 캐시 저장 OK → %s" % [tag, profile.asset_base_dir])
	else:
		_log("%s 캐시 저장 실패 - 메모리 전용으로 사용(디스크 쓰기 막힘, 이번 판 한정)" % tag)
	_log("%s 프로필 로드 OK (이름: %s)" % [tag, profile.display_name])

	_mark_resolved_for_hash(hash, profile)
	_finish_pending(hash)


func _on_pack_transfer_failed(hash: String, reason: String) -> void:
	_log("%s 서버가 전송 포기 알림(사유=%s) - 기본 캐릭터로 대체" % [_player_tag(hash), reason])
	_resolve_hash_failed(hash)


func _resolve_hash_failed(hash: String) -> void:
	for player_index in _hash_to_players.get(hash, []):
		slot_states[player_index] = SlotState.FAILED
		_resolved_profiles[player_index] = _fallback_profile(player_index)
		profile_ready.emit(player_index, _resolved_profiles[player_index])
	_finish_pending(hash)


func _mark_resolved_for_hash(hash: String, profile: CharacterProfile) -> void:
	for player_index in _hash_to_players.get(hash, []):
		_mark_resolved(player_index, hash, profile)


func _mark_resolved(player_index: int, hash: String, profile: CharacterProfile) -> void:
	slot_states[player_index] = SlotState.DONE
	_resolved_profiles[player_index] = profile
	profile_ready.emit(player_index, profile)


func _finish_pending(hash: String) -> void:
	_receive_buffers.erase(hash)
	_retransmit_attempts.erase(hash)
	_hash_last_chunk_msec.erase(hash)
	_hash_next_stall_warning_msec.erase(hash)
	if _my_pending_hashes.has(hash):
		_my_pending_hashes.erase(hash)
		_completed_count += 1
	if current_waiting_hash == hash:
		current_waiting_hash = ""
		_reset_stall_tracking()
	progress_changed.emit()
	_maybe_send_pack_ready()


## 보내는 쪽(내 업로드) 멈춤 감지 기준점만 초기화한다 - 받는 쪽은 해시별로
## 따로 관리하므로(_hash_last_chunk_msec) 여기서 건드리지 않는다.
func _reset_stall_tracking() -> void:
	_last_send_queue_size = -1
	_last_send_progress_msec = Time.get_ticks_msec()
	_next_send_stall_warning_msec = 0


func _fallback_profile(player_index: int) -> CharacterProfile:
	var profile := CharacterProfile.new()
	var display_name: String = str(_players.get(player_index, {}).get("meta", {}).get("display_name", ""))
	profile.display_name = display_name if not display_name.is_empty() else "플레이어 %d" % (player_index + 1)
	return profile


func _display_name_for_hash(hash: String) -> String:
	var players_with_hash: Array = _hash_to_players.get(hash, [])
	if players_with_hash.is_empty():
		return "상대"
	var player_index: int = players_with_hash[0]
	var name: String = str(_players.get(player_index, {}).get("meta", {}).get("display_name", ""))
	return name if not name.is_empty() else "플레이어 %d" % (player_index + 1)
