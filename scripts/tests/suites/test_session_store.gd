extends RefCounted

# SessionStore.save()/load()/clear()의 왕복을 검증한다(2-3,
# docs/multiplayer.md §6 "클라이언트 쪽 재접속 정보 저장"). 실제
# user://session.json 파일에 쓰고 지우는 통합 테스트라, 시작 전에 기존
# 값이 있으면 백업했다가 끝나면 되돌린다(다른 테스트/실제 세션 파일을
# 건드리지 않기 위함 - test_character_library.gd의 정리 관례와 같은 이유).

func run(r) -> void:
	var backup = SessionStore.load()

	r.begin_suite("SessionStore")
	_test_load_returns_null_when_absent(r)
	_test_save_then_load_round_trip(r)
	_test_clear_removes_file(r)

	if backup != null:
		SessionStore.save(backup["code"], backup["reconnect_token"], backup["player_index"])
	else:
		SessionStore.clear()


func _test_load_returns_null_when_absent(r) -> void:
	SessionStore.clear()
	r.expect_eq("저장된 세션이 없으면 null", SessionStore.load(), null)


func _test_save_then_load_round_trip(r) -> void:
	SessionStore.save("AB3F", "token-abc-123", 1)
	var loaded = SessionStore.load()

	r.expect_true("저장 후 읽으면 null이 아님", loaded != null)
	r.expect_eq("방 코드가 그대로 왕복함", loaded["code"], "AB3F")
	r.expect_eq("재접속 토큰이 그대로 왕복함", loaded["reconnect_token"], "token-abc-123")
	r.expect_eq("player_index가 그대로 왕복함", loaded["player_index"], 1)


func _test_clear_removes_file(r) -> void:
	SessionStore.save("K9Q2", "token-xyz", 0)
	SessionStore.clear()
	r.expect_eq("clear() 후에는 다시 null", SessionStore.load(), null)
