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
	r.expect_true("큐 소진 후 DONE", room.is_transfer_done())


func _test_transfer_scheduler_ignores_unrequested_hash(r) -> void:
	# 아무도 요청 안 한 해시는 큐에 안 오른다(요청이 실제로 있어야만 전송).
	var room := _make_room_with_hashes([HASH_A, ""])
	room.begin_transfer(0, 500)
	room.close_collection_and_build_queue()
	r.expect_true("요청이 하나도 없으면 큐가 비고 바로 DONE", room.transfer_queue.is_empty())
	r.expect_true("요청 없는 방은 DONE", room.is_transfer_done())


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
	r.expect_true("아무도 팩이 없으면 즉시 DONE", room.is_transfer_done())
