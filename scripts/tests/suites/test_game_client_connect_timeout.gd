extends RefCounted

# 콜드 스타트 재접속 예산 후속(사용자 지적, 2026-09-17) - "각 연결 시도가
# 실패로 판정되기까지 걸리는 시간"이 지금까지 명시된 적이 없어서, 서버가
# 응답 없이 그냥 걸려있으면(콜드 스타트 도중 등) GameClient가 CONNECTING/
# AWAITING_HELLO_ACK 상태에서 영원히 멈춰 재시도 루프로 절대 안 넘어갔다.
# GameClient.CONNECT_TIMEOUT_SEC를 명시하고, 그 상한을 넘기면 직접
# connection_failed/disconnected를 emit하도록 고쳤다 - 실제 네트워크
# 없이 _connecting_since_msec을 과거 시각으로 조작해서(실제로 10초를
# 기다리지 않고) 검증한다.

func run(r) -> void:
	r.begin_suite("GameClient 연결 시도 타임아웃(콜드 스타트 재접속 예산)")
	_test_timeout_fires_connection_failed_on_first_ever_attempt(r)
	_test_timeout_fires_disconnected_after_prior_success(r)
	_test_ever_hello_acknowledged_survives_reset(r)
	_test_budget_matches_user_confirmed_safe_value(r)


func _make_client() -> GameClient:
	var client := GameClient.new()
	Engine.get_main_loop().root.add_child(client)
	return client


func _free_client(client: GameClient) -> void:
	client.get_parent().remove_child(client)
	client.free()


## 진짜 첫 접속(이 클라이언트가 hello_ack를 한 번도 받은 적 없음)이 타임아웃되면
## connection_failed로 나가야 한다 - online_screen.gd가 이걸 받아야 재시도
## 백오프 루프(_on_connection_failed)를 탄다.
func _test_timeout_fires_connection_failed_on_first_ever_attempt(r) -> void:
	var client := _make_client()
	# GDScript 람다는 바깥 지역 변수를 값으로 캡처한다(이 프로젝트에서
	# 여러 번 반복된 함정, CLAUDE.md 참고) - Dictionary로 박싱해서 우회.
	var seen := {"failed_reason": "", "disconnected": false}
	client.connection_failed.connect(func(reason): seen["failed_reason"] = reason)
	client.disconnected.connect(func(): seen["disconnected"] = true)

	client._state = GameClient.State.CONNECTING
	client._connecting_since_msec = Time.get_ticks_msec() - int((GameClient.CONNECT_TIMEOUT_SEC + 1.0) * 1000)
	client._process(0.016)

	r.expect_eq("첫 접속 타임아웃 - connection_failed가 나감", seen["failed_reason"] != "", true)
	r.expect_eq("첫 접속 타임아웃 - disconnected는 안 나감", seen["disconnected"], false)
	r.expect_eq("타임아웃 후 상태가 IDLE로 리셋됨", client._state, GameClient.State.IDLE)
	_free_client(client)


## 이전에 hello_ack를 한 번이라도 받은 적 있는 클라이언트(게임 도중
## 재접속 시도)가 이번 재시도에서 또 타임아웃되면 disconnected로 나가야
## 한다 - _game_already_entered가 true인 online_screen.gd가 "조용히
## 재접속"(백오프 유지) 경로를 계속 타게 하기 위함. _reset()이
## _ever_hello_acknowledged를 지워버리면 이 경로가 깨진다(실제로 겪을
## 뻔한 회귀 - 아래 세 번째 테스트가 그 지점을 직접 검증한다).
func _test_timeout_fires_disconnected_after_prior_success(r) -> void:
	var client := _make_client()
	var seen := {"failed": false, "disconnected": false}
	client.connection_failed.connect(func(_reason): seen["failed"] = true)
	client.disconnected.connect(func(): seen["disconnected"] = true)

	client._ever_hello_acknowledged = true
	client._state = GameClient.State.CONNECTING
	client._connecting_since_msec = Time.get_ticks_msec() - int((GameClient.CONNECT_TIMEOUT_SEC + 1.0) * 1000)
	client._process(0.016)

	r.expect_eq("이전에 성공한 적 있는 클라이언트의 재시도 타임아웃 - disconnected가 나감", seen["disconnected"], true)
	r.expect_eq("이 경로에서는 connection_failed가 안 나감", seen["failed"], false)
	_free_client(client)


## 실제로 회귀를 밟을 뻔했던 지점 - _reset()은 connect_to_server()가 재시도
## 때마다 매번 부르는데, 여기서 _ever_hello_acknowledged를 지워버리면
## "게임 도중 재접속을 시도하다 그 재시도 자체가 또 실패"하는 흔한 경우에
## "이 세션은 한 번도 성공한 적 없다"로 잘못 보여 connection_failed로
## 잘못 빠진다(원래 disconnected여야 함) - 직접 재현해서 확인한다.
func _test_ever_hello_acknowledged_survives_reset(r) -> void:
	var client := _make_client()
	client._ever_hello_acknowledged = true
	client._reset()
	r.expect_eq("_reset() 이후에도 _ever_hello_acknowledged가 유지됨", client._ever_hello_acknowledged, true)
	_free_client(client)


## Render 공식 안내("50 seconds or more") 대비 안전 마진 확인 - 실측으로
## 확인된 대로(연결 시도가 CONNECT_TIMEOUT_SEC를 다 못 채우고 빨리 실패할
## 수 있음) 총 대기 시간을 안정적으로 보장하는 건 각 시도의 소요 시간이
## 아니라 백오프 합 그 자체다 - 그래서 이 값만으로 검증한다(CONNECT_TIMEOUT_SEC는
## 여기 계산에 안 넣는다 - 있으면 늘어날 수 있는 보너스일 뿐, 있다고
## 가정하면 안 되는 값이기 때문). 나중에 누가 MAX_RECONNECT_ATTEMPTS나
## 백오프 값을 조정하면서 이 마진을 깨면 여기서 바로 잡힌다.
func _test_budget_matches_user_confirmed_safe_value(r) -> void:
	var backoff := ReconnectBackoff.new()
	var backoff_sum_sec := 0.0
	while backoff.has_attempts_left():
		backoff_sum_sec += backoff.next_delay_sec()

	r.expect_eq("백오프 합이 95초(1+2+4+8+16+16+16+16+16)", backoff_sum_sec, 95.0)
	r.expect_eq("총 재시도 횟수가 9회(NetProtocol.MAX_RECONNECT_ATTEMPTS)", NetProtocol.MAX_RECONNECT_ATTEMPTS, 9)
	r.expect_true("백오프 합만으로도 Render 공식 안내(50초 이상)에 충분한 여유(45초 이상)", backoff_sum_sec - 50.0 >= 45.0)
