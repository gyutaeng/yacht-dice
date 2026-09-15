extends RefCounted

# NetProtocol.encode()/decode()를 검증한다(2-3, docs/multiplayer.md §2.0).
# 실제 소켓 없이 순수 인코딩/디코딩만 다룬다 - 소켓 자체는 server_main.gd/
# game_client.gd를 실제로 띄워 수동 테스트한다(자동화하기 어려움).

func run(r) -> void:
	r.begin_suite("NetProtocol")

	_test_round_trip(r)
	_test_decode_rejects_malformed_json(r)
	_test_decode_rejects_non_object_top_level(r)
	_test_decode_rejects_missing_type(r)
	_test_max_message_bytes_is_enforceable(r)
	_test_sanitize_display_name_removes_control_chars(r)
	_test_sanitize_display_name_truncates(r)
	_test_sanitize_display_name_strips_edges(r)
	_test_sanitize_display_name_all_control_chars_becomes_empty(r)


## JSON은 정수/실수를 구분하지 않아서, Godot의 JSON.parse_string()은 숫자를
## 항상 float로 돌려준다(정수로 보냈어도 왕복하면 float가 된다) - 그래서
## 기대값도 1이 아니라 1.0으로 적는다. 스칼라 비교(1 == 1.0)는 GDScript가
## 알아서 같다고 보지만, Dictionary 안에 든 값은 타입까지 정확히 맞아야
## 이 테스트가 실제로 검증하려는 "그대로 왕복하는지"를 정직하게 반영한다.
func _test_round_trip(r) -> void:
	var bytes := NetProtocol.encode("hello", {"protocol_version": 1})
	var decoded = NetProtocol.decode(bytes)

	r.expect_true("디코드 결과가 null이 아님", decoded != null)
	r.expect_eq("type이 그대로 왕복함", decoded["type"], "hello")
	r.expect_eq("payload가 그대로 왕복함(숫자는 float가 됨)", decoded["payload"], {"protocol_version": 1.0})


func _test_decode_rejects_malformed_json(r) -> void:
	var decoded = NetProtocol.decode("{이건 JSON이 아니다".to_utf8_buffer())
	r.expect_eq("깨진 JSON은 null", decoded, null)


func _test_decode_rejects_non_object_top_level(r) -> void:
	var decoded = NetProtocol.decode(JSON.stringify([1, 2, 3]).to_utf8_buffer())
	r.expect_eq("최상위가 배열이면 null", decoded, null)


func _test_decode_rejects_missing_type(r) -> void:
	var decoded = NetProtocol.decode(JSON.stringify({"payload": {}}).to_utf8_buffer())
	r.expect_eq("type 필드가 없으면 null", decoded, null)


## MAX_MESSAGE_BYTES 자체는 서버가 소켓에서 받은 크기를 직접 비교하는
## 값이라(server_main.gd) 여기서 실행까지 검증할 수는 없다 - 적어도 상수가
## 의도한 크기(64KB)인지, 그리고 그보다 큰 메시지를 실제로 인코딩할 수
## 있는지(=서버 쪽 크기 검사가 실제로 걸릴 만한 입력을 만들 수 있는지)만
## 확인한다.
func _test_max_message_bytes_is_enforceable(r) -> void:
	r.expect_eq("MAX_MESSAGE_BYTES는 64KB", NetProtocol.MAX_MESSAGE_BYTES, 65536)

	var oversized_payload := {"data": "x".repeat(NetProtocol.MAX_MESSAGE_BYTES)}
	var bytes := NetProtocol.encode("select_character", oversized_payload)
	r.expect_true("상한을 넘는 메시지도 인코딩 자체는 됨(서버가 크기로 걸러냄)", bytes.size() > NetProtocol.MAX_MESSAGE_BYTES)


## 닉네임은 남의 화면에 그대로 뜨는 값이라(원칙 6) 클라이언트/서버가 같은
## 기준으로 걸러야 한다 - 이 함수가 그 공유 기준이다.
func _test_sanitize_display_name_removes_control_chars(r) -> void:
	var raw := "야추\n왕\t\r초보"
	r.expect_eq("줄바꿈/탭 등 제어문자가 제거됨", NetProtocol.sanitize_display_name(raw), "야추왕초보")


func _test_sanitize_display_name_truncates(r) -> void:
	var raw := "가나다라마바사아자차카타파하"  # 14자
	r.expect_eq("MAX_DISPLAY_NAME_LENGTH(12자)로 잘림", NetProtocol.sanitize_display_name(raw).length(), NetProtocol.MAX_DISPLAY_NAME_LENGTH)


func _test_sanitize_display_name_strips_edges(r) -> void:
	r.expect_eq("양끝 공백이 제거됨", NetProtocol.sanitize_display_name("  호스트  "), "호스트")


func _test_sanitize_display_name_all_control_chars_becomes_empty(r) -> void:
	r.expect_eq("제어문자/공백만 있으면 빈 문자열(호출부가 기본값을 채움)", NetProtocol.sanitize_display_name("\n\t  \r"), "")
