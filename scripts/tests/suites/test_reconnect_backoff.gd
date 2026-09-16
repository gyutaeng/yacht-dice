extends RefCounted

# 2-6(연결 끊김/재접속) - ReconnectBackoff의 지수 백오프 수열과 상한을
# 검증한다. 첫 접속(서버 기상 대기)과 게임 도중 재접속 양쪽에서 이
# 클래스 하나만 재사용하므로, 순수 계산 로직만 여기서 확실히 검증해둔다.

func run(r) -> void:
	r.begin_suite("ReconnectBackoff")

	_test_delay_sequence_doubles_then_caps(r)
	_test_attempt_count_increases_on_each_call(r)
	_test_has_attempts_left_before_limit(r)
	_test_has_attempts_left_false_after_limit(r)
	_test_reset_clears_attempt_count(r)


func _test_delay_sequence_doubles_then_caps(r) -> void:
	var backoff := ReconnectBackoff.new()
	var delays: Array[float] = []
	for i in 6:
		delays.append(backoff.next_delay_sec())
	r.expect_eq("1번째 지연 1초", delays[0], 1.0)
	r.expect_eq("2번째 지연 2초", delays[1], 2.0)
	r.expect_eq("3번째 지연 4초", delays[2], 4.0)
	r.expect_eq("4번째 지연 8초", delays[3], 8.0)
	r.expect_eq("5번째 지연 16초(상한)", delays[4], 16.0)
	r.expect_eq("6번째도 16초에서 안 더 늘어남", delays[5], 16.0)


func _test_attempt_count_increases_on_each_call(r) -> void:
	var backoff := ReconnectBackoff.new()
	r.expect_eq("시작은 0회", backoff.attempt, 0)
	backoff.next_delay_sec()
	r.expect_eq("한 번 부르면 1회", backoff.attempt, 1)
	backoff.next_delay_sec()
	r.expect_eq("두 번 부르면 2회", backoff.attempt, 2)


func _test_has_attempts_left_before_limit(r) -> void:
	var backoff := ReconnectBackoff.new()
	for i in NetProtocol.MAX_RECONNECT_ATTEMPTS - 1:
		backoff.next_delay_sec()
	r.expect_true("상한 도달 전에는 아직 시도 가능", backoff.has_attempts_left())


func _test_has_attempts_left_false_after_limit(r) -> void:
	var backoff := ReconnectBackoff.new()
	for i in NetProtocol.MAX_RECONNECT_ATTEMPTS:
		backoff.next_delay_sec()
	r.expect_true("상한에 도달하면 더 이상 시도 못 함", not backoff.has_attempts_left())


func _test_reset_clears_attempt_count(r) -> void:
	var backoff := ReconnectBackoff.new()
	backoff.next_delay_sec()
	backoff.next_delay_sec()
	backoff.reset()
	r.expect_eq("reset() 후엔 다시 0회", backoff.attempt, 0)
	r.expect_eq("다음 지연도 다시 1초부터", backoff.next_delay_sec(), 1.0)
