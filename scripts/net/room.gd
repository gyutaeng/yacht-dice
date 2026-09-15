class_name Room
extends RefCounted

# 방 하나 = GameState 인스턴스 하나 + 참가자 슬롯 + 로비 상태 기계
# (docs/multiplayer.md §1, §3). RoomManager가 코드로 찾아 라우팅하는
# 대상일 뿐, 네트워크(WebSocketMultiplayerPeer)는 전혀 모른다 - GameState가
# UI를 모르는 것과 같은 이유로, 헤드리스에서 그대로 테스트할 수 있게 하기
# 위함이다.

enum State { LOBBY, TRANSFERRING, IN_GAME, ENDED }

# 2-5(캐릭터 팩 전송) - TRANSFERRING 상태 안의 세부 단계. COLLECTING(요청
# 수집 중) -> TRANSFERRING_PACK(해시 하나를 전송 중) -> ...(큐가 빌 때까지
# 반복)... -> AWAITING_READY(더 보낼 해시는 없지만, 받는 쪽이 검증·저장·
# 프로필 확정까지 실제로 끝냈는지 전원의 확인을 기다림) -> DONE(전원 확인
# 또는 대기 시간 초과, IN_GAME으로 넘어갈 준비 완료). 한 번에 해시 하나만
# 처리한다 - 방 전체 스케줄러를 이렇게 단순화하면 "한 수신자가 동시에
# 두 개를 받지 않는다"는 요구사항이 저절로 만족된다(서로 다른 소유자의
# 업로드가 동시에 진행되지 않는 대가는 있지만, 한 방에 최대 3개뿐이라
# 순서대로 처리해도 감당할 만하다).
#
# AWAITING_READY가 왜 필요한가(2-5 후속 버그 수정): 마지막 청크를 릴레이
# 큐에 넣은 시점과, 받는 쪽이 그 바이트를 실제로 검증·해제·캐시 저장까지
# 끝낸 시점은 다르다(웹 프리징 방지를 위해 파일 하나당 프레임을 쉬므로
# 여러 프레임 걸림 - 실측: 파일 4개 팩에서 3프레임 차이). 큐가 비었다고
# 바로 game_started를 보내면 "보냈다"를 "받는 쪽이 이미 다 처리해서 쓸 수
# 있다"로 착각하는 것과 같다(WebSocket 보내기 대기열 버그와 같은 패턴,
# 한 단계 위) - 그래서 전원이 pack_ready(자기 몫을 전부 처리했다는 영수증)
# 를 보낼 때까지 한 단계 더 기다린다.
enum TransferState { COLLECTING, TRANSFERRING_PACK, AWAITING_READY, DONE }

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

# 2-5(캐릭터 팩 전송) - TRANSFERRING 상태일 때만 의미가 있다. 서버
# (server_main.gd)의 _service_transferring_rooms()가 이 필드들만 보고
# 진행시킨다 - Room 자신은 시간(OS.get_ticks_msec())을 스스로 재지 않고
# 값만 들고 있어서 헤드리스 테스트에서 시간을 자유롭게 흉내낼 수 있다.
var transfer_state: TransferState = TransferState.COLLECTING
# transfer_queue: Array[String] - 아직 처리 안 한 해시들(순서대로 하나씩 처리).
var transfer_queue: Array = []
# transfer_requesters: Dictionary{String -> Array[int]} - 해시별로 그 팩을
# 요청한 플레이어 인덱스 목록(수집 창 동안 request_character_pack으로 쌓임).
var transfer_requesters: Dictionary = {}
var transfer_current_hash: String = ""
var transfer_current_owner: int = -1
var transfer_collect_until_msec: int = 0
var transfer_current_started_msec: int = 0
# transfer_hash_owners: Dictionary{String -> int} - begin_transfer() 시점에
# compute_needed_hashes()로 한 번 고정한다. 수집 창 동안 슬롯이 바뀔 일이
# 없으므로(캐릭터는 LOBBY에서만 바꿀 수 있음) 매번 다시 계산할 필요가 없다.
var transfer_hash_owners: Dictionary = {}

# 2-5 후속(AWAITING_READY) - transfer_ready_peers: Dictionary{int -> true},
# pack_ready를 보낸 슬롯 인덱스 집합. begin_transfer()에서 딱 한 번만
# 비운다 - AWAITING_READY 진입 시점에 비우면 안 된다. 받을 팩이 없는
# 클라이언트는 서버가 아직 COLLECTING 중일 때도 곧바로 pack_ready를 보낼
# 수 있는데, 그 이른 도착을 나중에 지워버리면 그 슬롯은 영원히 준비
# 안 된 것으로 남는다.
var transfer_ready_peers: Dictionary = {}
var transfer_ready_deadline_msec: int = 0

# 멈춤 감지(2-5 후속 - 사용자 신고: 큰 팩에서 전송이 중간에 멈춤) -
# transfer_current_started_msec("이 해시 전송을 언제 시작했나")와 달리
# 이건 "마지막으로 청크가 실제로 오간 게 언제인가"다. 청크가 오는 동안은
# 계속 갱신되고, 멈추면 이 값이 정지해서 경과 시간이 늘어난다.
var transfer_last_chunk_msec: int = 0
var transfer_last_chunk_sequence: int = -1
var transfer_last_chunk_total: int = 0
var transfer_next_stall_warning_msec: int = 0

# 결측 청크 재전송(2-5 후속) - "해시:요청자" 조합별 요청 횟수. 클라이언트의
# 자체 상한(NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH)을 서버가 그대로
# 믿지 않고 독립적으로 다시 강제한다(원칙 6). begin_transfer()에서만 비운다 -
# 이미 지나간 해시의 요청 횟수도 그 방의 전송이 끝날 때까지는 유지돼야
# 상한이 의미가 있다.
var transfer_resend_request_counts: Dictionary = {}


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


## 2-5(캐릭터 팩 전송) - 이 방에 지금 존재하는 캐릭터 팩 해시가 몇 개고
## 각각 누구 것인지(가장 낮은 슬롯 인덱스 기준)를 계산한다. 순수 함수라
## 네트워크/시간과 무관하게 헤드리스로 검증할 수 있다 - "같은 캐릭터를
## 고른 사람끼리는 해시가 같아서 한 번만 소유자로 잡힌다"는 요구사항이
## 여기서 자연히 만족된다(먼저 본 낮은 인덱스가 유지되도록 in 검사로 구현).
## 빈 문자열(팩 없음, 내장 기본 캐릭터)은 결과에서 제외한다.
func compute_needed_hashes() -> Dictionary:
	var owners := {}
	for i in slots.size():
		if slots[i] == null:
			continue
		var pack_hash: String = str(slots[i]["meta"].get("pack_hash", ""))
		if pack_hash.is_empty():
			continue
		if not owners.has(pack_hash):
			owners[pack_hash] = i
	return owners


## TRANSFERRING 단계로 들어가며 요청 수집 창을 연다(2-5 §2단계). 시간은
## server_main.gd(Time.get_ticks_msec())가 넘겨준다 - Room 자신은 시계를
## 몰라야 헤드리스 테스트에서 시간을 자유롭게 흉내낼 수 있다.
## transfer_hash_owners는 여기서 한 번만 고정한다(LOBBY에서만 캐릭터를
## 바꿀 수 있으므로 수집 도중 값이 바뀔 일이 없음).
func begin_transfer(now_msec: int, collect_ms: int) -> void:
	state = State.TRANSFERRING
	transfer_state = TransferState.COLLECTING
	transfer_hash_owners = compute_needed_hashes()
	transfer_requesters = {}
	transfer_queue = []
	transfer_current_hash = ""
	transfer_current_owner = -1
	transfer_collect_until_msec = now_msec + collect_ms
	transfer_ready_peers = {}
	transfer_ready_deadline_msec = 0
	transfer_resend_request_counts = {}


## "owner_index 슬롯의 팩이 필요하다"는 클라이언트 요청을 기록한다. 클라이언트가
## 엉뚱한(또는 이미 지나간) owner_index를 보내도 조용히 무시한다(원칙 6 -
## 클라이언트 신고를 그대로 믿지 않는다). 여러 슬롯이 같은 해시를 갖고 있으면
## (같은 캐릭터를 고른 경우) 클라이언트가 어느 슬롯을 owner_index로 지목했든
## transfer_hash_owners에 미리 고정해둔 대표 소유자 하나로 귀결된다.
func register_pack_request(requester_index: int, owner_index: int) -> void:
	if transfer_state != TransferState.COLLECTING:
		return
	if owner_index < 0 or owner_index >= slots.size() or slots[owner_index] == null:
		return
	var pack_hash: String = str(slots[owner_index]["meta"].get("pack_hash", ""))
	if pack_hash.is_empty() or not transfer_hash_owners.has(pack_hash):
		return

	if not transfer_requesters.has(pack_hash):
		transfer_requesters[pack_hash] = []
	if not transfer_requesters[pack_hash].has(requester_index):
		transfer_requesters[pack_hash].append(requester_index)


func is_collection_expired(now_msec: int) -> bool:
	return transfer_state == TransferState.COLLECTING and now_msec >= transfer_collect_until_msec


## 수집 창을 닫고 큐를 구성한다 - 실제로 요청이 들어온 해시만 큐에 오른다
## (아무도 필요 없다고 한 해시를 전송할 이유는 없다). 큐가 비어도 바로
## DONE이 아니라 AWAITING_READY로 간다 - 받을 팩이 하나도 없는 방(전원
## 기본 캐릭터 등)도 예외 없이 pack_ready 확인 단계를 거친다(호출부가
## begin_awaiting_ready()로 마감 시각을 잡아줘야 한다).
func close_collection_and_build_queue() -> void:
	transfer_queue = transfer_requesters.keys()
	transfer_state = TransferState.TRANSFERRING_PACK if not transfer_queue.is_empty() else TransferState.AWAITING_READY


## 큐에서 다음 해시를 꺼내 진행 중 상태로 만들고 그 해시를 돌려준다. 큐가
## 비어 있으면(전부 처리 완료) AWAITING_READY로 전환하고 빈 문자열을
## 돌려준다(호출부가 begin_awaiting_ready()로 마감 시각을 잡아줘야 한다).
func start_next_transfer(now_msec: int) -> String:
	if transfer_queue.is_empty():
		transfer_state = TransferState.AWAITING_READY
		transfer_current_hash = ""
		transfer_current_owner = -1
		return ""

	transfer_current_hash = transfer_queue.pop_front()
	transfer_current_owner = transfer_hash_owners.get(transfer_current_hash, -1)
	transfer_current_started_msec = now_msec
	transfer_state = TransferState.TRANSFERRING_PACK
	transfer_last_chunk_msec = now_msec
	transfer_last_chunk_sequence = -1
	transfer_last_chunk_total = 0
	transfer_next_stall_warning_msec = 0
	return transfer_current_hash


## 지금 전송 중인 해시를 요청했던 플레이어 인덱스 목록(pack_chunk를 받을 대상).
func current_transfer_recipients() -> Array:
	return recipients_for_hash(transfer_current_hash)


## 결측 청크 재전송(2-5 후속) - 어떤 해시든(지금 처리 중이 아니라 이미
## 큐를 지나간 해시라도) 그 해시를 요청했던 플레이어 인덱스 목록을 돌려준다.
## transfer_requesters는 begin_transfer()에서만 비워지므로 지나간 해시의
## 요청자 목록도 그대로 남아있다.
func recipients_for_hash(pack_hash: String) -> Array:
	return transfer_requesters.get(pack_hash, [])


## 결측 청크 재전송(2-5 후속) - "해시:요청자" 조합이 상한
## (NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH) 안이면 카운트를 올리고
## true, 이미 상한을 넘겼으면 카운트를 건드리지 않고 false를 돌려준다.
## 호출부(server_main.gd)는 false면 요청을 조용히 무시한다.
func mark_chunk_resend_requested(pack_hash: String, requester_index: int) -> bool:
	var key := "%s:%d" % [pack_hash, requester_index]
	var count: int = transfer_resend_request_counts.get(key, 0)
	if count >= NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH:
		return false
	transfer_resend_request_counts[key] = count + 1
	return true


func is_current_transfer_timed_out(now_msec: int, timeout_ms: int) -> bool:
	return transfer_state == TransferState.TRANSFERRING_PACK and now_msec - transfer_current_started_msec > timeout_ms


## 멈춤 감지(사용자 신고 - 큰 팩에서 중간에 멈춤) - server_main.gd가 청크를
## 하나 릴레이할 때마다 불러서 "마지막 진전 시각"을 갱신한다. 새 경고를
## 다시 받을 수 있게 stall_warning 타이머도 같이 초기화한다.
func mark_transfer_activity(now_msec: int, sequence: int, total_chunks: int) -> void:
	transfer_last_chunk_msec = now_msec
	transfer_last_chunk_sequence = sequence
	transfer_last_chunk_total = total_chunks
	transfer_next_stall_warning_msec = 0


func is_transfer_stalled(now_msec: int, stall_ms: int) -> bool:
	return transfer_state == TransferState.TRANSFERRING_PACK and now_msec - transfer_last_chunk_msec >= stall_ms


## AWAITING_READY 진입 시 마감 시각을 잡는다. transfer_ready_peers는 여기서
## 안 건드린다(begin_transfer()에서만 비움 - 위 필드 주석 참고).
func begin_awaiting_ready(now_msec: int, timeout_ms: int) -> void:
	transfer_ready_deadline_msec = now_msec + timeout_ms


func mark_pack_ready(player_index: int) -> void:
	transfer_ready_peers[player_index] = true


## 지금 채워진 슬롯 전원이 pack_ready를 보냈는지. 슬롯이 비어있으면
## (플레이어가 나갔으면) 그 자리는 검사 대상에서 빠진다.
func all_players_pack_ready() -> bool:
	for i in slots.size():
		if slots[i] != null and not transfer_ready_peers.has(i):
			return false
	return true


func is_pack_ready_timed_out(now_msec: int) -> bool:
	return transfer_state == TransferState.AWAITING_READY and now_msec >= transfer_ready_deadline_msec


## AWAITING_READY -> DONE. 전원 확인됐거나(all_players_pack_ready())
## 대기 시간을 넘겨 포기했을 때(is_pack_ready_timed_out()) 호출부가 부른다.
func mark_transfer_done() -> void:
	transfer_state = TransferState.DONE


func is_transfer_done() -> bool:
	return transfer_state == TransferState.DONE
