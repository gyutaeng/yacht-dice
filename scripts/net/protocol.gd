class_name NetProtocol
extends RefCounted

# 서버/클라이언트가 공유하는 메시지 봉투 규약(docs/multiplayer.md §2.0).
# 이 상수들은 두 프로세스가 같은 값을 가져야 하는 값이라 여기 한 곳에만 둔다 -
# 서버(server_main.gd)와 클라이언트(scripts/net/game_client.gd) 양쪽이 이
# 파일을 그대로 preload/참조해서 절대 따로 값을 베껴 적지 않는다.

const PROTOCOL_VERSION := 1
const MAX_MESSAGE_BYTES := 65536
const HELLO_TIMEOUT_SECONDS := 5.0

# 닉네임(display_name)은 남의 화면에 그대로 뜨는 값이라 클라이언트가 보낸
# 그대로 믿으면 안 된다(원칙 6). 상수/정리 함수를 여기 하나로 모아서
# 클라이언트(scenes/online/online_screen.gd)와 서버(server_main.gd) 양쪽이
# 같은 기준으로 검사하게 한다 - 클라이언트 쪽 검사는 UX(입력 즉시 막기)용,
# 서버 쪽 검사는 실제 방어선이다.
const MAX_DISPLAY_NAME_LENGTH := 12

# 클라이언트 -> 서버
const MSG_HELLO := "hello"
const MSG_CREATE_ROOM := "create_room"
const MSG_JOIN_ROOM := "join_room"
const MSG_SELECT_CHARACTER := "select_character"
const MSG_READY := "ready"
const MSG_SET_PLAYER_COUNT := "set_player_count"
const MSG_LEAVE := "leave"
const MSG_REQUEST_ROLL := "request_roll"
const MSG_REQUEST_HOLD := "request_hold"
const MSG_REQUEST_SCORE := "request_score"

# 서버 -> 클라이언트
const MSG_HELLO_ACK := "hello_ack"
const MSG_ROOM_CREATED := "room_created"
const MSG_ROOM_JOINED := "room_joined"
const MSG_PLAYER_JOINED := "player_joined"
const MSG_PLAYER_CHARACTER := "player_character"
const MSG_PLAYER_READY_CHANGED := "player_ready_changed"
const MSG_ROOM_PLAYER_COUNT_CHANGED := "room_player_count_changed"
const MSG_PLAYER_LEFT := "player_left"
const MSG_GAME_STARTED := "game_started"
const MSG_ERROR := "error"
const MSG_STATE_SNAPSHOT := "state_snapshot"
const MSG_DICE_ROLLED := "dice_rolled"
const MSG_SPECIAL_HAND_ROLLED := "special_hand_rolled"
const MSG_BONUS_ACHIEVED := "bonus_achieved"
const MSG_ZERO_SCORED := "zero_scored"
const MSG_TURN_STARTED := "turn_started"
const MSG_GAME_ENDED := "game_ended"

# 2-4C(GameEvents 전수 조사 이후 추가) - "게임에서 일어난 사건은 전부
# 전달한다"는 규칙(scripts/net/game_event_relay.gd 참고)에 따라 추가됨.
# MSG_GAME_STATE_STARTED는 GameState.start_turn()이 내는
# GameEvents.game_started(로컬 인사 연출용) 신호를 실어 나른다 - 로비가
# 다 찼을 때 이미 보내는 MSG_GAME_STARTED(위, player_count만 담는 별개의
# 메시지)와 이름이 겹치면 클라이언트가 같은 신호를 두 번(로비 종료 +
# 이 이벤트) 받아서 인사 연출이 두 번 시작될 뻔했다 - 그래서 일부러
# 다른 이름을 썼다.
const MSG_DIE_HELD_CHANGED := "die_held_changed"
const MSG_SCORE_COMMITTED := "score_committed"
const MSG_YACHT_SCORED := "yacht_scored"
const MSG_TURN_ENDED := "turn_ended"
const MSG_GAME_STATE_STARTED := "game_state_started"

# 문서(§2.0/§4/§7)에 이름이 있는 에러 코드.
const ERROR_PROTOCOL_MISMATCH := "PROTOCOL_MISMATCH"
const ERROR_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const ERROR_ROOM_FULL := "ROOM_FULL"
const ERROR_INVALID_ARGUMENT := "INVALID_ARGUMENT"

# 문서에는 이름이 없어서 이번 구현에서 채워 넣은 에러 코드 - 문서의 검증
# 항목(§4)은 이미 이 상황들을 요구하고 있지만 코드 이름까지 정해두진 않았다.
const ERROR_NOT_HOST := "NOT_HOST"
const ERROR_GAME_ALREADY_STARTED := "GAME_ALREADY_STARTED"

# 2-4에서 추가 - 문서 §7은 NOT_YOUR_TURN을 이름만 언급하고 정의는 안
# 해뒀다. NOT_IN_GAME은 문서에 이름조차 없어서 이번에 직접 정했다(방이
# 아직 로비/전송 단계인데 request_roll 등이 온 경우) - 리롤 소진/이미
# 확정된 칸/범위 밖 인덱스 등 나머지 세부 사유는 코드를 더 늘리지 않고
# INVALID_ARGUMENT를 재사용하고 message로 구분한다.
const ERROR_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const ERROR_NOT_IN_GAME := "NOT_IN_GAME"


## 메시지 하나를 JSON 봉투로 인코딩한다. 실패할 일이 없는 입력(Dictionary)만
## 받으므로 에러 반환 없이 항상 PackedByteArray를 돌려준다.
static func encode(type: String, payload: Dictionary) -> PackedByteArray:
	var envelope := {"type": type, "payload": payload}
	return JSON.stringify(envelope).to_utf8_buffer()


## 수신한 원본 바이트를 디코드한다. 형식이 안 맞으면(JSON 파싱 실패,
## 최상위가 Dictionary가 아님, type 필드가 String이 아님) null을 돌려준다 -
## 호출부(서버/클라이언트)는 null을 받으면 그 연결을 신뢰하지 않고 끊는다
## (원칙 6 - 외부 입력을 신뢰하지 않는다).
static func decode(bytes: PackedByteArray) -> Variant:
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	if not parsed.has("type") or typeof(parsed["type"]) != TYPE_STRING:
		return null
	if not parsed.has("payload") or typeof(parsed["payload"]) != TYPE_DICTIONARY:
		return null
	return parsed


## 줄바꿈/탭 등 제어문자(0x00~0x1F, 0x7F)를 제거하고 양끝 공백을 자른 뒤
## MAX_DISPLAY_NAME_LENGTH로 자른다. 빈 문자열이 될 수 있다(원본이 전부
## 제어문자였거나 공백뿐이었던 경우) - 그때 무엇으로 대체할지는 호출부가
## 정한다(클라이언트는 자기 슬롯 번호를, 서버는 실제 배정된 슬롯 번호를
## 알고 있어서 "플레이어 N" 문구를 각자 만들 수 있으므로 이 함수 책임이
## 아니다).
static func sanitize_display_name(raw: String) -> String:
	var filtered := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 0x20 and code != 0x7F:
			filtered += raw[i]

	filtered = filtered.strip_edges()
	if filtered.length() > MAX_DISPLAY_NAME_LENGTH:
		filtered = filtered.substr(0, MAX_DISPLAY_NAME_LENGTH)
	return filtered
