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
## 전송 단계별 진단 로그(2-5 전송 버그 조사용) - "웹은 브라우저 콘솔의
## print()를 못 믿는다"(1-5)는 이유로 화면에 직접 찍어야 해서, GameEvents와
## 같은 패턴으로 emit만 하고 실제로 어디에 찍을지는 구독자(online_screen.gd)가
## 정한다. BuildInfo.DEBUG_MODE와 무관하게 항상 emit한다 - 화면에 찍을지
## 말지는 구독자 쪽에서 그 플래그로 걸러도 되고, 문제가 재발하면 언제든
## 켤 수 있게 로직 자체에서 로그를 걸러내지 않는다.
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


func configure(client: GameClient) -> void:
	_client = client
	_client.pack_upload_requested.connect(_on_pack_upload_requested)
	_client.pack_chunk_received.connect(_on_pack_chunk_received)
	_client.pack_transfer_failed.connect(_on_pack_transfer_failed)


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
	current_waiting_hash = ""
	_completed_count = 0

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
	debug_log.emit("begin(): 내 해시=%s, 필요한 해시 %d개(%s)" % [
		_my_pack_hash.substr(0, 8) if not _my_pack_hash.is_empty() else "(없음)",
		_total_pending_count,
		", ".join(_my_pending_hashes.keys().map(func(h): return str(h).substr(0, 8))),
	])
	progress_changed.emit()


func get_profile(player_index: int) -> CharacterProfile:
	return _resolved_profiles.get(player_index)


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
	var percent := int(100.0 * received / total_chunks) if total_chunks > 0 else 0
	var remaining_sec := _remaining_timeout_seconds()
	return "%s님의 캐릭터 받는 중 (%d/%d) %d%% (타임아웃까지 %d초)" % [owner_name, _completed_count + 1, max(_total_pending_count, 1), percent, remaining_sec]


func _remaining_timeout_seconds() -> int:
	var remaining_msec: int = _current_transfer_deadline_msec - Time.get_ticks_msec()
	return maxi(0, int(ceil(remaining_msec / 1000.0)))


func _on_pack_upload_requested(hash: String) -> void:
	_current_transfer_deadline_msec = Time.get_ticks_msec() + NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC

	if hash == _my_pack_hash and not _my_pack_bytes.is_empty():
		debug_log.emit("pack_upload_requested(%s) - 내 팩(%d바이트), 업로드 시작" % [hash.substr(0, 8), _my_pack_bytes.size()])
		_upload_my_pack(hash)
	elif _hash_to_players.has(hash):
		debug_log.emit("pack_upload_requested(%s) - 내가 요청한 해시, 수신 대기" % hash.substr(0, 8))
		for player_index in _hash_to_players[hash]:
			if slot_states.get(player_index) == SlotState.WAITING:
				slot_states[player_index] = SlotState.RECEIVING
	else:
		debug_log.emit("pack_upload_requested(%s) - 남의 전송(구경만)" % hash.substr(0, 8))

	current_waiting_hash = hash
	progress_changed.emit()


## put_packet()의 반환값(대기열 여부)을 매 청크마다 확인하지 않는다 - 실제
## 흐름 제어는 game_client.gd의 _outgoing_queue가 담당하므로(2-5 전송 버그
## 수정 - 대기열이 가득 차도 put_packet()이 조용히 실패하는 대신 큐에
## 쌓였다가 다음 프레임에 다시 시도됨), 여기서는 큐 깊이를 로그로만
## 남긴다. 모든 청크를 한 번에 upload_pack_chunk()로 넘기지만, 실제
## 소켓 전송은 GameClient가 프레임마다 나눠서 처리한다.
func _upload_my_pack(hash: String) -> void:
	var total_bytes := _my_pack_bytes.size()
	var total_chunks := int(ceil(float(total_bytes) / NetProtocol.CHUNK_PAYLOAD_BYTES))
	total_chunks = max(total_chunks, 1)
	debug_log.emit("업로드 시작: 청크 %d개(각 %d바이트 이하), 총 %d바이트" % [total_chunks, NetProtocol.CHUNK_PAYLOAD_BYTES, total_bytes])
	for i in total_chunks:
		var start := i * NetProtocol.CHUNK_PAYLOAD_BYTES
		var end := mini(start + NetProtocol.CHUNK_PAYLOAD_BYTES, total_bytes)
		var chunk := _my_pack_bytes.slice(start, end)
		_client.upload_pack_chunk(hash, i, total_chunks, total_bytes, Marshalls.raw_to_base64(chunk))
		var queued := _client.get_outgoing_queue_size()
		if i == 0 or i == total_chunks - 1 or queued > 0:
			debug_log.emit("청크 %d/%d 전송 요청함 - 보내기 대기열 %d개" % [i + 1, total_chunks, queued])


func _on_pack_chunk_received(hash: String, sequence: int, total_chunks: int, data_base64: String) -> void:
	if not _receive_buffers.has(hash):
		_receive_buffers[hash] = {"total_chunks": total_chunks, "chunks": []}
	var buf: Dictionary = _receive_buffers[hash]
	buf["total_chunks"] = total_chunks
	var chunks: Array = buf["chunks"]
	if chunks.size() < total_chunks:
		chunks.resize(total_chunks)
	if sequence < 0 or sequence >= chunks.size():
		debug_log.emit("청크 수신했지만 sequence(%d)가 범위 밖(총 %d개) - 무시함" % [sequence, total_chunks])
		return
	chunks[sequence] = Marshalls.base64_to_raw(data_base64)
	if sequence == 0 or sequence == total_chunks - 1 or (sequence + 1) % 10 == 0:
		debug_log.emit("청크 %d/%d 수신함(해시=%s)" % [sequence + 1, total_chunks, hash.substr(0, 8)])
	progress_changed.emit()

	for c in chunks:
		if c == null:
			return  # 아직 다 안 옴.

	debug_log.emit("청크 %d개 전부 수신 완료 - 검증 시작" % total_chunks)
	await _finalize_received_pack(hash, chunks)


## 압축 해제/디코딩이 한 프레임에 몰리지 않도록 CharacterLibrary에 self(Node)를
## 넘겨서 파일 하나 풀 때마다 한 프레임씩 기다린다(2-5 §웹에서 화면이 안
## 멈추게, 1-8에서 지적된 문제의 연장). 서버가 해시를 하나씩만 순서대로
## 보내주므로 이 함수도 한 번에 팩 하나만 처리한다 - 동시에 여러 명 분을
## 처리할 일이 없다.
func _finalize_received_pack(hash: String, chunks: Array) -> void:
	var combined := PackedByteArray()
	for c in chunks:
		combined.append_array(c)

	var actual_hash := ReceivedPackCache.sha256_hex(combined)
	if actual_hash != hash:
		debug_log.emit("해시 불일치! 요청=%s 실제=%s(%d바이트) - 조용히 기본 캐릭터로 대체" % [hash.substr(0, 8), actual_hash.substr(0, 8), combined.size()])
		push_warning("PackTransferClient: 받은 팩의 해시가 요청한 값과 다름 - 조용히 기본 캐릭터로 대체함(hash=%s)" % hash)
		_resolve_hash_failed(hash)
		return

	var validated: Dictionary = await CharacterLibrary.validate_and_extract_pack(combined, self)
	if not validated["ok"]:
		debug_log.emit("팩 검증 실패(%s) - 조용히 기본 캐릭터로 대체" % validated["error"])
		push_warning("PackTransferClient: 받은 팩 검증 실패 - 조용히 기본 캐릭터로 대체함(hash=%s, error=%s)" % [hash, validated["error"]])
		_resolve_hash_failed(hash)
		return

	var profile := ReceivedPackCache.store(hash, validated["extracted"], validated["manifest_profile"])
	debug_log.emit("전송 완료 - 해시=%s, 저장 위치=%s" % [hash.substr(0, 8), profile.asset_base_dir if profile.asset_base_dir != "" else "(메모리 전용)"])
	_mark_resolved_for_hash(hash, profile)
	_finish_pending(hash)


func _on_pack_transfer_failed(hash: String, reason: String) -> void:
	debug_log.emit("서버가 전송 포기 알림(해시=%s, 사유=%s) - 기본 캐릭터로 대체" % [hash.substr(0, 8), reason])
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
	if _my_pending_hashes.has(hash):
		_my_pending_hashes.erase(hash)
		_completed_count += 1
	if current_waiting_hash == hash:
		current_waiting_hash = ""
	progress_changed.emit()


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
