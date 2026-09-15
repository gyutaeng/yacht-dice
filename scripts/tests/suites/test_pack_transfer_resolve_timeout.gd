extends RefCounted

# 2-5 후속(확실한 버그 수정) - PackTransferClient.wait_until_all_resolved()에
# 상한이 없어서, 청크 하나가 영영 안 오면(예: _on_pack_chunk_received()의
# "전부 모였는지" 검사가 계속 실패) online_screen.gd가 game_started를 받고도
# 게임 화면으로 영원히 못 넘어가는 확실한 버그가 있었다. "게임 화면으로
# 넘어가지 않는 경로는 존재하지 않는다"를 여기서 직접 검증한다 - 실제
# 10초를 기다리지 않도록 timeout_msec 매개변수에 짧은 값을 넣는다(같은
# 로직 경로를 그대로 탄다).

func run(r) -> void:
	r.begin_suite("PackTransferClient.wait_until_all_resolved() 상한 검증")

	await _test_never_hangs_when_a_hash_never_resolves(r)
	await _test_returns_immediately_when_nothing_pending(r)
	await _test_returns_immediately_once_hash_resolves_before_timeout(r)


## 반환값: [PackTransferClient, GameClient] - 둘 다 트리에 붙여야
## PackTransferClient._process()/get_tree()가 정상 동작한다.
func _make_pack_transfer() -> Array:
	var pack_transfer := PackTransferClient.new()
	Engine.get_main_loop().root.add_child(pack_transfer)
	var client := GameClient.new()
	Engine.get_main_loop().root.add_child(client)
	pack_transfer.configure(client)
	return [pack_transfer, client]


func _free_pack_transfer(pair: Array) -> void:
	pair[0].queue_free()
	pair[1].queue_free()


## 상대(슬롯 1)가 커스텀 팩을 가진 것으로 꾸미되, 청크를 하나도 안 보내서
## "영원히 결측"인 상태를 인위적으로 만든다 - 실제 버그(청크 하나가 안
## 옴)와 증상이 같다(_my_pending_hashes가 절대 안 빔).
func _test_never_hangs_when_a_hash_never_resolves(r) -> void:
	var pair := _make_pack_transfer()
	var pack_transfer: PackTransferClient = pair[0]
	var fake_hash := "c".repeat(64)
	var players := {
		0: {"meta": {"pack_hash": ""}, "ready": true},
		1: {"meta": {"pack_hash": fake_hash}, "ready": true},
	}
	pack_transfer.begin(0, null, PackedByteArray(), "", players)
	r.expect_true("begin() 직후엔 아직 처리 안 끝남(대상 해시가 대기 중)", not pack_transfer.is_all_resolved())

	# 람다가 지역 변수를 값으로 캡처해서 대입이 바깥에 반영 안 되는 문제를
	# 이 세션에서 여러 번 겪었다(GDScript 클로저 함정) - 배열에 담아 참조로
	# 공유해서 피한다.
	var captured := [-1, null]  # [player_index, profile]
	pack_transfer.profile_ready.connect(func(player_index: int, profile: CharacterProfile) -> void:
		captured[0] = player_index
		captured[1] = profile
	)

	# 실제 10초(NetProtocol.LOCAL_PACK_RESOLVE_TIMEOUT_MSEC) 대신 50ms로
	# 같은 로직 경로(시간 초과 -> 강제 실패 처리)만 빠르게 검증한다.
	await pack_transfer.wait_until_all_resolved(50)

	r.expect_true("타임아웃 후엔 반드시 전부 해결됨(게임 화면으로 못 넘어가는 경로 없음)", pack_transfer.is_all_resolved())
	r.expect_eq("타임아웃된 슬롯(1번)이 강제로 해결됨", captured[0], 1)
	r.expect_true("타임아웃된 슬롯은 기본 프로필로 대체됨(null 아님)", captured[1] != null)

	_free_pack_transfer(pair)


func _test_returns_immediately_when_nothing_pending(r) -> void:
	var pair := _make_pack_transfer()
	var pack_transfer: PackTransferClient = pair[0]
	pack_transfer.begin(0, null, PackedByteArray(), "", {0: {"meta": {"pack_hash": ""}, "ready": true}})
	r.expect_true("받을 게 없으면 begin() 직후 바로 다 끝남", pack_transfer.is_all_resolved())

	var start := Time.get_ticks_msec()
	await pack_transfer.wait_until_all_resolved(50)
	var elapsed := Time.get_ticks_msec() - start
	r.expect_true("이미 다 끝났으면 타임아웃(50ms)을 기다리지 않고 즉시 반환함", elapsed < 50)

	_free_pack_transfer(pair)


## 타임아웃 전에 실제로 해결되면(정상 케이스) 강제 처리 없이 곧바로
## 반환해야 한다 - 매 프레임 폴링 방식으로 바꾸면서 이 정상 경로가 여전히
## 빠르게 도는지 같이 확인한다.
func _test_returns_immediately_once_hash_resolves_before_timeout(r) -> void:
	var pair := _make_pack_transfer()
	var pack_transfer: PackTransferClient = pair[0]
	pack_transfer.begin(0, null, PackedByteArray(), "", {0: {"meta": {"pack_hash": ""}, "ready": true}})
	r.expect_true("받을 게 없으므로 이미 해결된 상태", pack_transfer.is_all_resolved())

	# 넉넉한 타임아웃(5000ms)을 줘도, 이미 해결돼 있으면 그 시간을 다
	# 기다리지 않고 즉시 반환해야 한다(폴링 루프의 첫 조건 검사에서 통과).
	var start := Time.get_ticks_msec()
	await pack_transfer.wait_until_all_resolved(5000)
	var elapsed := Time.get_ticks_msec() - start
	r.expect_true("이미 끝난 상태면 긴 타임아웃도 그냥 통과함", elapsed < 200)

	_free_pack_transfer(pair)
