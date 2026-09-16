extends RefCounted

# 친구 대상 실제 베타 테스트 후속(사용자 지적) - has_room_to_send_now()의
# margin 계산("메시지 크기 + 청크 하나만큼의 여유")이 buffer_limit보다 큰
# 조합이면, 그 메시지는 버퍼가 완전히 빈 상태에서도 영원히 "여유 없음"
# 판정을 받는다 - put_packet()을 아예 안 부르고 큐에만 계속 쌓이는,
# 에러 로그 한 줄 없는 조용한 정체(데드락)다. 실제로 이 세션의 테스트
# 작성 중에도 TINY_OUTBOUND_BUFFER_BYTES를 50000으로 잡았다가 이 조건에
# 걸려 테스트 자체가 영원히 멈춘 적이 있다(test_pack_relay_buffer_overflow.gd
# 주석 참고, 지금은 100000으로 수정됨) - 사람이 실수로 밟기 쉬운 조합임이
# 실제로 증명된 값이라 그대로 재사용한다.
#
# 이 테스트는 NetProtocol.can_chunk_ever_be_sent()(순수 판정)와, 그 판정이
# server_main.gd/game_client.gd가 시작 시점에 실제로 쓰는 것과 같은 방식
# (peer.set_outbound_buffer_size() 후 get_outbound_buffer_size()로 되읽은
# 값)으로 걸어도 똑같이 동작하는지 확인한다 - _start_server()/
# connect_to_server() 안의 get_tree().quit()/connection_failed.emit() 자체는
# 여기서 직접 트리거하지 않는다(전자는 공유 테스트 러너 전체를 죽이고,
# 후자는 실제 소켓 연결 흐름이 필요해서 이 순수 로직 테스트의 범위 밖).

const MISCONFIGURED_BUFFER_BYTES := 50000  # 청크 하나(약 43.8KB)+여유(약 43.8KB)를 감당 못 함.


func run(r) -> void:
	r.begin_suite("데드락 방지 안전장치 - 오설정된 버퍼가 조용히 안 멈추고 즉시 드러남")
	_test_pure_logic_detects_undersized_buffer(r)
	_test_pure_logic_accepts_production_constants(r)
	_test_server_peer_reveals_undersized_configuration(r)
	_test_client_peer_reveals_undersized_configuration(r)


func _test_pure_logic_detects_undersized_buffer(r) -> void:
	r.expect_eq(
		"청크 하나(+여유)를 못 담는 버퍼는 false",
		NetProtocol.can_chunk_ever_be_sent(MISCONFIGURED_BUFFER_BYTES),
		false
	)
	r.expect_eq(
		"버퍼가 0이면(제한 없음 관례) true",
		NetProtocol.can_chunk_ever_be_sent(0),
		true
	)


func _test_pure_logic_accepts_production_constants(r) -> void:
	r.expect_eq(
		"서버 실제 상수(1MB)는 청크를 감당함",
		NetProtocol.can_chunk_ever_be_sent(NetProtocol.SERVER_OUTBOUND_BUFFER_BYTES),
		true
	)
	r.expect_eq(
		"클라이언트 실제 상수(1MB)는 청크를 감당함",
		NetProtocol.can_chunk_ever_be_sent(NetProtocol.CLIENT_OUTBOUND_BUFFER_BYTES),
		true
	)


## server_main.gd를 트리에 안 넣고(네트워크 미시작) peer만 직접 조작해서,
## _start_server()가 실제로 확인하는 것과 같은 조합(get_outbound_buffer_size()로
## 되읽은 실제 값)을 검사한다 - 엔진이 요청값을 그대로 안 받아들이고
## 반올림/보정할 가능성까지 포함해서 "실제로 걸리는 값"으로 확인한다.
func _test_server_peer_reveals_undersized_configuration(r) -> void:
	var server_script: GDScript = load("res://server_main.gd")
	var server = server_script.new()
	server.peer.set_outbound_buffer_size(MISCONFIGURED_BUFFER_BYTES)
	var actual: int = server.peer.get_outbound_buffer_size()

	r.expect_true(
		"서버 - 오설정된 버퍼(요청 %d바이트 -> 실제 %d바이트)는 시작 시점 검사에 걸림" % [MISCONFIGURED_BUFFER_BYTES, actual],
		not NetProtocol.can_chunk_ever_be_sent(actual)
	)

	server.peer.set_outbound_buffer_size(NetProtocol.SERVER_OUTBOUND_BUFFER_BYTES)
	r.expect_true(
		"서버 - 실제 배포 값(1MB)은 시작 시점 검사를 통과함",
		NetProtocol.can_chunk_ever_be_sent(server.peer.get_outbound_buffer_size())
	)


func _test_client_peer_reveals_undersized_configuration(r) -> void:
	var client := GameClient.new()
	client._peer.set_outbound_buffer_size(MISCONFIGURED_BUFFER_BYTES)
	var actual: int = client._peer.get_outbound_buffer_size()

	r.expect_true(
		"클라이언트 - 오설정된 버퍼(요청 %d바이트 -> 실제 %d바이트)는 연결 시점 검사에 걸림" % [MISCONFIGURED_BUFFER_BYTES, actual],
		not NetProtocol.can_chunk_ever_be_sent(actual)
	)

	client._peer.set_outbound_buffer_size(NetProtocol.CLIENT_OUTBOUND_BUFFER_BYTES)
	r.expect_true(
		"클라이언트 - 실제 배포 값(1MB)은 연결 시점 검사를 통과함",
		NetProtocol.can_chunk_ever_be_sent(client._peer.get_outbound_buffer_size())
	)
