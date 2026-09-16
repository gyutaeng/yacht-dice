extends RefCounted

# 확정 2 회귀 테스트(실제 베타 테스트에서 발견된 청크 유실 버그) - 보내는
# 쪽 버퍼를 일부러 아주 작게 만들어 put_packet() 실패/재시도 경로를
# 강제로 자주 타게 만든 뒤에도, 수신 측이 모든 청크를 빠짐없이 받는지
# 실제 로컬 소켓으로 확인한다.
#
# 원인 요약(서버 콘솔 로그로 확정): 예전 코드는 "확인된 개수"만 셌다
# (confirmed += 1). 받는 쪽이 결측을 알아채고 request_pack_chunks로
# 재전송을 요청하면 같은 (순번,수신자) 쌍이 두 번 확인될 수 있는데,
# 개수만 세면 이 중복이 다른 진짜 미확인 쌍의 몫까지 채워버려서
# "전부 실제 송신됨"으로 오판했다(59개 중 18개가 실제로는 못 갔는데도
# "59개 전부 송신됨"이 찍힘). server_main.gd가 이제 각 (순번,수신자)
# 쌍의 성공 여부를 Dictionary 플래그로 정확히 추적한다
# (_all_relay_pairs_confirmed()) - 이 테스트는 그 수정이 실제 소켓
# 환경에서도 (버퍼가 넘치는 압박 속에서) 여전히 모든 청크를 온전히
# 전달하는지 확인한다.
#
# 테스트 구조: 실제 GameClient 하나(수신자 역할)만 진짜 소켓으로 붙이고,
# 소유자 쪽은 실제 클라이언트를 안 만들고 server_main.gd의 Room 상태를
# 직접 조작해서 "이미 팩 전송 단계에 들어와 있다"를 흉내낸 뒤
# _handle_upload_pack_chunk()를 반복 호출한다(실제 소유자가 빠르게
# 여러 청크를 연달아 올리는 것과 같은 부하 패턴).

const TEST_PORT := 39123
# 실제 버그가 났던 규모(NetProtocol.CHUNK_PAYLOAD_BYTES=32KB 청크, Base64 후
# 약 43.8KB)를 그대로 재현한다 - 작은 청크(수백 바이트~수 KB)로는 실제로
# put_packet()이 한 번도 실패하지 않는 것을 실측으로 확인했다(로컬 소켓의
# OS 커널 버퍼가 그 정도는 순식간에 비워버림). 버퍼를 청크 하나(43.8KB)보다
# 작게 잡아서 첫 청크부터 확실히 넘치게 만든다.
## 실제 패킷 크기는 원본 바이트가 아니라 Base64 인코딩 + JSON 봉투를 씌운
## 크기다(32768바이트 원본 -> 약 43.8KB). `NetProtocol.has_room_to_send_now()`가
## "이번 크기 + 청크 하나만큼의 여유"를 요구하므로(확정 2 후속), 버퍼가
## 패킷 하나(43.8KB) + 여유(43.8KB)를 감당할 만큼은 돼야 데드락 없이
## "몇 개는 바로 나가고, 그 다음부터는 큐에서 기다렸다 나간다"는 원래
## 재현하려는 조건이 된다 - 그래서 100000바이트로 잡는다(총 30개(약
## 1.3MB)보다는 훨씬 작아 재시도 경로를 확실히 강제하면서도, 한 항목이
## 절대 못 나가는 상황은 안 만든다).
const TINY_OUTBOUND_BUFFER_BYTES := 100000
const CHUNK_RAW_BYTES := 32768
const TOTAL_CHUNKS := 30
const OWNER_SLOT := 1
const RECIPIENT_SLOT := 0
const FAKE_OWNER_PEER_ID := 999999


func run(r) -> void:
	r.begin_suite("확정 2 회귀 - 보내는 쪽 버퍼가 넘쳐도 청크가 전부 도착함")
	await _test_all_chunks_arrive_despite_tiny_outbound_buffer(r)


func _test_all_chunks_arrive_despite_tiny_outbound_buffer(r) -> void:
	var server_script: GDScript = load("res://server_main.gd")
	var server = server_script.new()
	server.port_override = TEST_PORT
	server.outbound_buffer_override_bytes = TINY_OUTBOUND_BUFFER_BYTES
	Engine.get_main_loop().root.add_child(server)
	await Engine.get_main_loop().process_frame

	var recipient := GameClient.new()
	Engine.get_main_loop().root.add_child(recipient)

	# 스칼라 값을 람다 안에서 대입하려면 박싱해야 한다 - GDScript 람다는
	# 바깥 지역 변수를 값으로 캡처해서, 람다 안에서 대입해도 바깥에 반영
	# 안 된다(이 프로젝트에서 여러 번 반복된 함정, docs/multiplayer.md
	# §8.5 - 검증 스크립트 자체에서 실제로 다시 밟아서 확인함). Dictionary/
	# Array처럼 참조 타입은 내용만 바꾸면 되므로 이 문제가 없다.
	var received_chunks: Dictionary = {}  # sequence(int) -> data_base64(String)
	var flags := {"transfer_failed_reason": "", "hello_ok": false, "room_code": ""}
	recipient.pack_chunk_received.connect(func(_h, seq, _tc, data): received_chunks[seq] = data)
	recipient.pack_transfer_failed.connect(func(_h, reason): flags["transfer_failed_reason"] = reason)
	recipient.hello_acknowledged.connect(func(): flags["hello_ok"] = true)
	recipient.room_created.connect(func(code, _pc, _tok): flags["room_code"] = code)
	recipient.connect_to_server("ws://127.0.0.1:%d" % TEST_PORT)

	if not await _wait_until(func(): return flags["hello_ok"], 5.0, "hello_acknowledged"):
		r.expect_true("서버 연결/hello 완료(사전 조건)", false)
		_cleanup(server, recipient)
		return

	recipient.create_room(2)
	if not await _wait_until(func(): return flags["room_code"] != "", 5.0, "room_created"):
		r.expect_true("방 생성 완료(사전 조건)", false)
		_cleanup(server, recipient)
		return

	# 소유자(슬롯 1)는 실제 소켓 없이 방 상태를 직접 조작해 자리만 채운다 -
	# 이 테스트가 검증하려는 건 "서버가 받은 청크를 수신자에게 릴레이하는
	# 경로"이지 업로드 경로가 아니므로, 실제 GameClient를 하나 더 안 만들어도
	# 충분하다.
	var room: Room = server.room_manager.get_room(flags["room_code"])
	room.seat_player(FAKE_OWNER_PEER_ID)
	# room_manager.get_room_for_peer()가 room.slots가 아니라 이 매핑을 보고
	# 방을 찾으므로, 가짜 소유자도 여기 등록해야 _handle_upload_pack_chunk()가
	# "방을 찾을 수 없음"으로 조용히 무시하지 않는다.
	server.room_manager.peer_room[FAKE_OWNER_PEER_ID] = room.code

	const TEST_HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd"
	room.state = Room.State.TRANSFERRING
	room.transfer_state = Room.TransferState.TRANSFERRING_PACK
	room.transfer_current_hash = TEST_HASH
	room.transfer_hash_owners = {TEST_HASH: OWNER_SLOT}
	room.transfer_requesters = {TEST_HASH: [RECIPIENT_SLOT]}

	# 실제 소유자가 빠르게 연달아 올리는 것과 같은 부하 패턴 - 한 프레임 안에
	# 전부 호출해서 보내는 쪽 버퍼가 확실히 넘치도록 강제한다.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var expected_data: Dictionary = {}  # sequence -> data_base64(보낸 그대로 왔는지 대조용)
	for seq in TOTAL_CHUNKS:
		var raw := PackedByteArray()
		raw.resize(CHUNK_RAW_BYTES)
		for i in raw.size():
			raw[i] = rng.randi() % 256
		var data_b64 := Marshalls.raw_to_base64(raw)
		expected_data[seq] = data_b64
		server._handle_upload_pack_chunk(FAKE_OWNER_PEER_ID, {
			"hash": TEST_HASH,
			"sequence": seq,
			"total_chunks": TOTAL_CHUNKS,
			"total_bytes": CHUNK_RAW_BYTES * TOTAL_CHUNKS,
			"data": data_b64,
		})

	var all_arrived := await _wait_until(func(): return received_chunks.size() >= TOTAL_CHUNKS, 10.0, "모든 청크 수신")

	r.expect_eq("전송 실패 통보를 받지 않음", flags["transfer_failed_reason"], "")
	r.expect_true("보내는 쪽 버퍼(%d바이트)가 넘쳐도 %d개 청크가 전부 도착함(받은 개수=%d)" % [TINY_OUTBOUND_BUFFER_BYTES, TOTAL_CHUNKS, received_chunks.size()], all_arrived)

	if all_arrived:
		var corrupted: Array[int] = []
		for seq in TOTAL_CHUNKS:
			if received_chunks.get(seq, "") != expected_data[seq]:
				corrupted.append(seq)
		r.expect_eq("도착한 청크 내용도 보낸 것과 정확히 일치함(순번 뒤바뀜/손상 없음)", corrupted, [] as Array[int])

	_cleanup(server, recipient)


## 조건이 참이 될 때까지 최대 timeout_sec초(실제 시계 기준) 기다린다.
## 타임아웃되면 false - 실제 소켓 테스트라 소켓 왕복에 진짜 시간이
## 걸린다. 프레임 카운트로 기다리면(예: await process_frame을 N번)
## 헤드리스 엔진이 프레임을 얼마나 빨리 도는지에 따라 실제 경과 시간이
## 들쭉날쭉해서(실측 - 300프레임을 기다려도 hello_acknowledged가 안 옴)
## 신뢰할 수 없다 - 그래서 실제 타이머(create_timer)로 폴링한다.
func _wait_until(condition: Callable, timeout_sec: float, _label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await Engine.get_main_loop().create_timer(0.02).timeout
	return condition.call()


func _cleanup(server: Node, recipient: Node) -> void:
	recipient.close()
	recipient.get_parent().remove_child(recipient)
	recipient.free()
	server.peer.close()  # 리스닝 포트를 즉시 반환 - 안 그러면 다음 실행까지 점유될 수 있음.
	server.get_parent().remove_child(server)
	server.free()
