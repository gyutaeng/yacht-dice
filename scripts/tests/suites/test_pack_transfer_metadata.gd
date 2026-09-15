extends RefCounted

# 2-5(캐릭터 팩 전송) 1단계 - 실제 바이트 전송 없이, 메타데이터(pack_hash)만으로
# "누구 것을 받아야 하는지"를 정하는 순수 로직을 검증한다. 네트워크/디스크
# I/O가 필요한 부분(ReceivedPackCache.has_cached()의 파일 존재 확인 정도만
# 예외)은 여기서 다루지 않는다 - 2단계에서 실제 서버+클라이언트 수동 확인으로
# 커버할 예정.

const HASH_A := "a1b2c3d4e5f60000000000000000000000000000000000000000000000000a"
const HASH_B := "b1b2c3d4e5f60000000000000000000000000000000000000000000000000b"


func run(r) -> void:
	r.begin_suite("캐릭터 팩 전송 메타데이터(Room.compute_needed_hashes/ReceivedPackCache)")

	_test_compute_needed_hashes_dedupes_same_hash(r)
	_test_compute_needed_hashes_ignores_empty_hash(r)
	_test_compute_needed_hashes_ignores_empty_slots(r)
	_test_compute_needed_hashes_multiple_distinct_hashes(r)
	_test_received_pack_cache_miss_for_unknown_hash(r)
	_test_received_pack_cache_miss_for_empty_hash(r)

	_test_transfer_scheduler_full_round_trip(r)
	_test_transfer_scheduler_ignores_unrequested_hash(r)
	_test_transfer_scheduler_ignores_invalid_owner_index(r)
	_test_transfer_scheduler_timeout(r)
	_test_transfer_scheduler_empty_queue_finishes_immediately(r)

	_test_awaiting_ready_blocks_until_everyone_acks(r)
	_test_awaiting_ready_early_ack_before_queue_drains_still_counts(r)
	_test_awaiting_ready_timeout_lets_stragglers_go(r)
	_test_awaiting_ready_ignores_empty_slots(r)

	_test_stall_detection_not_stalled_right_after_start(r)
	_test_stall_detection_stalled_after_no_activity(r)
	_test_stall_detection_activity_resets_stall(r)
	_test_stall_detection_not_applicable_outside_transferring_pack(r)

	_test_recipients_for_hash_works_after_hash_is_no_longer_current(r)
	_test_mark_chunk_resend_requested_allows_up_to_limit(r)
	_test_mark_chunk_resend_requested_is_per_hash_and_per_requester(r)
	_test_mark_chunk_resend_requested_resets_on_new_transfer(r)


func _make_room_with_hashes(hashes: Array) -> Room:
	var room := Room.new("TEST", hashes.size())
	for i in hashes.size():
		var peer_id := 100 + i
		room.seat_player(peer_id)
		room.slots[i]["meta"] = {"id": "char_%d" % i, "display_name": "P%d" % i, "pack_hash": hashes[i]}
	return room


func _test_compute_needed_hashes_dedupes_same_hash(r) -> void:
	# 같은 캐릭터를 고른 두 슬롯 - 해시가 같으므로 소유자는 낮은 인덱스(0) 하나로만 잡혀야 한다.
	var room := _make_room_with_hashes([HASH_A, HASH_A])
	var owners := room.compute_needed_hashes()
	r.expect_eq("같은 해시는 소유자가 하나만 결정됨", owners.size(), 1)
	r.expect_eq("소유자는 더 낮은 슬롯 인덱스(0)", owners[HASH_A], 0)


func _test_compute_needed_hashes_ignores_empty_hash(r) -> void:
	# 내장 기본 캐릭터(팩 없음)를 고른 슬롯은 결과에서 제외돼야 한다.
	var room := _make_room_with_hashes(["", HASH_A])
	var owners := room.compute_needed_hashes()
	r.expect_eq("빈 해시는 무시되고 하나만 남음", owners.size(), 1)
	r.expect_eq("남은 해시의 소유자는 슬롯 1", owners[HASH_A], 1)


func _test_compute_needed_hashes_ignores_empty_slots(r) -> void:
	# 아직 아무도 안 앉은 빈 슬롯이 있어도 죽지 않아야 한다.
	var room := Room.new("TEST", 3)
	room.seat_player(100)
	room.slots[0]["meta"] = {"id": "char_0", "display_name": "P0", "pack_hash": HASH_A}
	var owners := room.compute_needed_hashes()
	r.expect_eq("빈 슬롯은 무시하고 앉은 슬롯만 계산", owners.size(), 1)
	r.expect_eq("소유자는 슬롯 0", owners[HASH_A], 0)


func _test_compute_needed_hashes_multiple_distinct_hashes(r) -> void:
	var room := _make_room_with_hashes([HASH_A, HASH_B, HASH_A])
	var owners := room.compute_needed_hashes()
	r.expect_eq("서로 다른 해시 2개가 각각 잡힘", owners.size(), 2)
	r.expect_eq("HASH_A의 소유자는 슬롯 0", owners[HASH_A], 0)
	r.expect_eq("HASH_B의 소유자는 슬롯 1", owners[HASH_B], 1)


func _test_received_pack_cache_miss_for_unknown_hash(r) -> void:
	r.expect_true("캐시에 없는 해시는 has_cached()가 false", not ReceivedPackCache.has_cached(HASH_A))


func _test_received_pack_cache_miss_for_empty_hash(r) -> void:
	r.expect_true("빈 문자열 해시는 has_cached()가 false", not ReceivedPackCache.has_cached(""))


func _test_transfer_scheduler_full_round_trip(r) -> void:
	# 슬롯 0=HASH_A 소유, 슬롯 1=HASH_B 소유, 슬롯 2는 팩 없음(기본 캐릭터).
	# 슬롯 2가 둘 다 요청하는 전형적인 시나리오를 처음부터 끝까지 돌려본다.
	var room := _make_room_with_hashes([HASH_A, HASH_B, ""])
	room.begin_transfer(1000, 500)
	r.expect_eq("begin_transfer 직후엔 COLLECTING", room.transfer_state, Room.TransferState.COLLECTING)
	r.expect_true("수집 시간(1500) 전엔 만료 아님", not room.is_collection_expired(1400))
	r.expect_true("수집 시간(1500)이 지나면 만료", room.is_collection_expired(1500))

	room.register_pack_request(2, 0)
	room.register_pack_request(2, 1)
	room.close_collection_and_build_queue()
	r.expect_eq("요청된 해시 2개가 큐에 오름", room.transfer_queue.size(), 2)

	var first_hash := room.start_next_transfer(1500)
	r.expect_true("첫 해시는 HASH_A 또는 HASH_B 중 하나", first_hash == HASH_A or first_hash == HASH_B)
	r.expect_eq("TRANSFERRING_PACK 상태로 전환", room.transfer_state, Room.TransferState.TRANSFERRING_PACK)
	r.expect_eq("소유자는 transfer_hash_owners와 일치", room.transfer_current_owner, room.transfer_hash_owners[first_hash])
	r.expect_eq("수신자는 슬롯 2 하나", room.current_transfer_recipients(), [2])

	var second_hash := room.start_next_transfer(1600)
	r.expect_true("두 번째 해시는 첫 번째와 다름", second_hash != first_hash)

	var third := room.start_next_transfer(1700)
	r.expect_eq("큐가 비면 빈 문자열", third, "")
	r.expect_eq("큐 소진 후엔 곧장 DONE이 아니라 AWAITING_READY(2-5 후속)", room.transfer_state, Room.TransferState.AWAITING_READY)


func _test_transfer_scheduler_ignores_unrequested_hash(r) -> void:
	# 아무도 요청 안 한 해시는 큐에 안 오른다(요청이 실제로 있어야만 전송).
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	r.expect_true("요청이 하나도 없으면 큐가 빔", room.transfer_queue.is_empty())
	r.expect_eq("요청 없는 방은 AWAITING_READY(전원 pack_ready는 별도로 확인)", room.transfer_state, Room.TransferState.AWAITING_READY)


func _test_transfer_scheduler_ignores_invalid_owner_index(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.register_pack_request(1, 99)  # 범위 밖 인덱스 - 무시돼야 함.
	room.register_pack_request(1, 1)  # 팩 없는 슬롯(빈 해시) - 무시돼야 함.
	room.close_collection_and_build_queue()
	r.expect_true("엉뚱한 owner_index 요청은 전부 무시됨", room.transfer_queue.is_empty())


func _test_transfer_scheduler_timeout(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 100)
	room.register_pack_request(1, 0)
	room.close_collection_and_build_queue()
	room.start_next_transfer(200)
	var timeout_ms := NetProtocol.PACK_TRANSFER_TIMEOUT_MSEC
	r.expect_true("60초 전엔 타임아웃 아님", not room.is_current_transfer_timed_out(200 + timeout_ms - 1000, timeout_ms))
	r.expect_true("60초가 지나면 타임아웃", room.is_current_transfer_timed_out(200 + timeout_ms + 1, timeout_ms))


func _test_transfer_scheduler_empty_queue_finishes_immediately(r) -> void:
	var room := _make_room_with_hashes(["", ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	r.expect_eq("아무도 팩이 없으면 곧장 AWAITING_READY로(받을 게 없어도 pack_ready 확인은 거침)", room.transfer_state, Room.TransferState.AWAITING_READY)


func _test_awaiting_ready_blocks_until_everyone_acks(r) -> void:
	var room := _make_room_with_hashes(["", ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	room.begin_awaiting_ready(500, 60000)

	r.expect_true("아무도 아직 pack_ready를 안 보냈으면 전원 확인 실패", not room.all_players_pack_ready())
	room.mark_pack_ready(0)
	r.expect_true("한 명만 보냈으면 아직 전원 확인 실패", not room.all_players_pack_ready())
	room.mark_pack_ready(1)
	r.expect_true("전원이 보냈으면 확인 성공", room.all_players_pack_ready())

	r.expect_eq("mark_transfer_done() 전엔 아직 AWAITING_READY", room.transfer_state, Room.TransferState.AWAITING_READY)
	room.mark_transfer_done()
	r.expect_true("mark_transfer_done() 후엔 DONE", room.is_transfer_done())


## 받을 팩이 없는 클라이언트는 서버가 아직 COLLECTING/TRANSFERRING_PACK인
## 동안에도 pack_ready를 보낼 수 있다 - 그 이른 도착이 나중에 AWAITING_READY에
## 들어가도 유효해야 한다(transfer_ready_peers는 begin_transfer()에서만 리셋됨).
func _test_awaiting_ready_early_ack_before_queue_drains_still_counts(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	# 슬롯 1(팩 없음)은 아직 COLLECTING 단계인데도 곧바로 pack_ready를 보낸다.
	room.mark_pack_ready(1)

	room.register_pack_request(1, 0)
	room.close_collection_and_build_queue()
	room.start_next_transfer(500)
	room.start_next_transfer(600)  # 큐 소진 -> AWAITING_READY
	room.begin_awaiting_ready(600, 60000)

	r.expect_true("이른 pack_ready가 안 지워지고 남아있음", not room.all_players_pack_ready())
	room.mark_pack_ready(0)
	r.expect_true("나머지 한 명도 보내면 전원 확인 성공", room.all_players_pack_ready())


func _test_awaiting_ready_timeout_lets_stragglers_go(r) -> void:
	var room := _make_room_with_hashes(["", ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	room.begin_awaiting_ready(500, 1000)
	room.mark_pack_ready(0)  # 슬롯 1은 끝까지 안 보냄.

	r.expect_true("타임아웃 전엔 아직 시간 초과 아님", not room.is_pack_ready_timed_out(500 + 999))
	r.expect_true("타임아웃이 지나면 안 온 사람이 있어도 진행 가능", room.is_pack_ready_timed_out(500 + 1001))
	r.expect_true("여전히 전원 확인은 실패 상태(그래도 서버는 진행함)", not room.all_players_pack_ready())


func _test_awaiting_ready_ignores_empty_slots(r) -> void:
	# 슬롯 하나가 빈 방(인원수 3이지만 2명만 참가) - 빈 슬롯은 검사 대상이 아니다.
	var room := Room.new("TEST", 3)
	room.seat_player(100)
	room.seat_player(101)
	room.slots[0]["meta"] = {"id": "", "display_name": "P0", "pack_hash": ""}
	room.slots[1]["meta"] = {"id": "", "display_name": "P1", "pack_hash": ""}
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	room.begin_awaiting_ready(500, 60000)

	room.mark_pack_ready(0)
	room.mark_pack_ready(1)
	r.expect_true("빈 슬롯(2번)은 확인 대상이 아니라 둘만 보내도 전원 확인 성공", room.all_players_pack_ready())


func _test_stall_detection_not_stalled_right_after_start(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.register_pack_request(1, 0)
	room.close_collection_and_build_queue()
	room.start_next_transfer(500)
	r.expect_true("전송 시작 직후엔 멈춤 아님", not room.is_transfer_stalled(500, 5000))
	r.expect_true("5초가 안 지났으면 멈춤 아님", not room.is_transfer_stalled(500 + 4999, 5000))


func _test_stall_detection_stalled_after_no_activity(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.register_pack_request(1, 0)
	room.close_collection_and_build_queue()
	room.start_next_transfer(500)
	r.expect_true("진전 없이 5초가 지나면 멈춤으로 판정", room.is_transfer_stalled(500 + 5000, 5000))


func _test_stall_detection_activity_resets_stall(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.register_pack_request(1, 0)
	room.close_collection_and_build_queue()
	room.start_next_transfer(500)

	room.mark_transfer_activity(4000, 2, 10)  # 청크 3/10이 4000ms 시점에 옴.
	r.expect_true("방금 진전이 있었으면 멈춤 아님", not room.is_transfer_stalled(4000 + 4999, 5000))
	r.expect_true("그 시점 기준으로 다시 5초가 지나야 멈춤", room.is_transfer_stalled(4000 + 5001, 5000))
	r.expect_eq("마지막 청크 정보가 기록됨", room.transfer_last_chunk_sequence, 2)
	r.expect_eq("총 청크 수도 기록됨", room.transfer_last_chunk_total, 10)


func _test_stall_detection_not_applicable_outside_transferring_pack(r) -> void:
	# AWAITING_READY 등 다른 단계에서는 "멈춤"이라는 개념 자체가 없다
	# (기다리는 게 청크가 아니라 pack_ready이므로).
	var room := _make_room_with_hashes(["", ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()  # 곧장 AWAITING_READY로.
	r.expect_true("AWAITING_READY에서는 청크 멈춤 판정이 적용 안 됨", not room.is_transfer_stalled(999999, 5000))


## 결측 청크 재전송(2-5 후속) - 서버가 다음 해시로 넘어간 뒤에도(더 이상
## transfer_current_hash가 아니어도) 그 해시를 요청했던 사람 목록을 여전히
## 조회할 수 있어야 재전송 릴레이가 가능하다.
func _test_recipients_for_hash_works_after_hash_is_no_longer_current(r) -> void:
	var room := _make_room_with_hashes([HASH_A, HASH_B, ""])
	room.begin_transfer(0, 500)
	room.register_pack_request(2, 0)  # HASH_A 요청
	room.register_pack_request(2, 1)  # HASH_B 요청
	room.close_collection_and_build_queue()

	var first_hash := room.start_next_transfer(500)
	room.start_next_transfer(600)  # 큐가 다음 해시로 넘어감 - first_hash는 더 이상 current가 아님.

	r.expect_eq("지나간 해시라도 요청자 목록을 그대로 조회 가능", room.recipients_for_hash(first_hash), [2])
	r.expect_eq("모르는 해시는 빈 배열", room.recipients_for_hash("없는해시"), [])


func _test_mark_chunk_resend_requested_allows_up_to_limit(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)

	for i in NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH:
		r.expect_true("상한(%d회) 전엔 허용됨(%d번째)" % [NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH, i + 1], room.mark_chunk_resend_requested(HASH_A, 1))
	r.expect_true("상한을 넘으면 거부됨", not room.mark_chunk_resend_requested(HASH_A, 1))


func _test_mark_chunk_resend_requested_is_per_hash_and_per_requester(r) -> void:
	var room := _make_room_with_hashes([HASH_A, HASH_B, ""])
	room.begin_transfer(0, 500)

	for i in NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH:
		room.mark_chunk_resend_requested(HASH_A, 2)
	r.expect_true("한 해시의 상한과 무관하게 다른 해시는 별도로 허용됨", room.mark_chunk_resend_requested(HASH_B, 2))
	r.expect_true("같은 해시라도 다른 요청자는 별도로 허용됨", room.mark_chunk_resend_requested(HASH_A, 0))


func _test_mark_chunk_resend_requested_resets_on_new_transfer(r) -> void:
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	for i in NetProtocol.MAX_CHUNK_RESEND_REQUESTS_PER_HASH:
		room.mark_chunk_resend_requested(HASH_A, 1)
	r.expect_true("상한 도달 확인", not room.mark_chunk_resend_requested(HASH_A, 1))

	room.begin_transfer(1000, 500)  # 새 전송 라운드 - 카운터가 초기화돼야 함.
	r.expect_true("begin_transfer()로 카운터가 초기화됨", room.mark_chunk_resend_requested(HASH_A, 1))
