class_name NetProtocol
extends RefCounted

# 서버/클라이언트가 공유하는 메시지 봉투 규약(docs/multiplayer.md §2.0).
# 이 상수들은 두 프로세스가 같은 값을 가져야 하는 값이라 여기 한 곳에만 둔다 -
# 서버(server_main.gd)와 클라이언트(scripts/net/game_client.gd) 양쪽이 이
# 파일을 그대로 preload/참조해서 절대 따로 값을 베껴 적지 않는다.

const PROTOCOL_VERSION := 1
const MAX_MESSAGE_BYTES := 65536
const HELLO_TIMEOUT_SECONDS := 5.0

# 2-5(캐릭터 팩 전송) §8 - 청크 페이로드(인코딩 전 원본)는 32KB다. 64KB(=
# MAX_MESSAGE_BYTES)가 아니다 - Base64가 원본을 약 1.33배로 불리고 봉투
# (타입/순번/총 개수 등 JSON 필드)까지 더해야 하므로, 32KB로 잡아야
# 인코딩 후(약 43KB)에도 MAX_MESSAGE_BYTES 안에 넉넉히 들어온다.
const CHUNK_PAYLOAD_BYTES := 32768

# 서버가 실제로 강제하는 상한이지만, 클라이언트(PackTransferClient)도 로비
# 화면에 "타임아웃까지 N초" 카운트다운을 보여주려면 같은 값을 알아야 해서
# 여기 공유 파일에 둔다(HELLO_TIMEOUT_SECONDS와 같은 이유).
const PACK_TRANSFER_TIMEOUT_MSEC := 60000

# 2-5 후속(전송 완료를 "발송"이 아니라 "영수증"으로 확인) - 마지막 청크를
# 네트워크로 보낸 것과, 받는 쪽이 그걸 실제로 검증·저장·프로필 확정까지
# 끝낸 것은 다른 시점이다(웹 프리징 방지를 위해 파일마다 프레임을 쉬므로
# 여러 프레임 걸림). 서버는 전원이 pack_ready를 보낼 때까지 game_started를
# 미룬다 - 그 대기의 상한이 이 값이다. PACK_TRANSFER_TIMEOUT_MSEC(업로더가
# 네트워크로 다 보낼 시간)과 의미가 달라서 재사용하지 않고 따로 둔다 -
# 이건 이미 다운로드된 바이트를 로컬에서 푸는 시간이라 훨씬 빨리 끝나야
# 정상이고, 나중에 실측해서 독립적으로 줄일 수 있어야 한다.
const PACK_READY_TIMEOUT_MSEC := 60000

# 멈춤 감지(사용자 신고 - 큰 팩에서 전송이 중간에 멈춤) - 보내는 쪽/받는
# 쪽/서버 셋 다 "마지막으로 진전이 있었던 시각"을 기록해뒀다가 이 시간
# 이상 안 움직이면 화면/콘솔에 경고를 남긴다. 60초 전송 타임아웃보다 훨씬
# 짧게 잡아서(5초) "느린 것"과 "완전히 멈춘 것"을 구분하는 조기 경보로
# 쓴다 - 타임아웃 자체를 대체하지 않는다(그건 그대로 60초 뒤에 포기하고
# 기본 캐릭터로 넘어감).
const TRANSFER_STALL_WARNING_SEC := 5.0

# 2-5 후속(확실한 버그 수정) - online_screen.gd가 game_started를 받았는데
# PackTransferClient에 아직 처리 중인 해시가 남아있으면 기다리는 방어선
# (wait_until_all_resolved())에 상한이 없었다 - 청크 하나가 영영 안 와서
# _on_pack_chunk_received()의 "전부 모였는지" 검사가 계속 실패하면
# 클라이언트가 게임 화면으로 영원히 못 넘어갔다. 서버는 이미 PACK_READY_TIMEOUT_MSEC
# (60초)를 기다린 뒤에야 game_started를 보내므로, 그 이후에 클라이언트가
# 또 60초를 기다리는 건 의미가 없다 - 훨씬 짧게 잡고, 넘기면 남은 해시를
# 강제로 포기(기본 캐릭터로 대체)하고 진행한다.
const LOCAL_PACK_RESOLVE_TIMEOUT_MSEC := 10000

# 2-5 후속(결측 청크 단위 재전송) - 청크 하나가 사라져도 팩 전체(최대
# 15MB)를 포기하지 않고, 받는 쪽이 멈춤을 감지했을 때(TRANSFER_STALL_WARNING_SEC
# 주기) 빠진 순번만 지정해서 다시 요청한다. 두 값 다 "무한 반복 방지"용
# 상한이고, 서로 독립적으로 강제된다(클라이언트 자체 제한을 서버가 그대로
# 믿지 않는다 - 원칙 6) - 클라이언트가 상한을 넘기면 더 요청하지 않고
# 기존 로컬/서버 타임아웃이 그대로 이어받아 기본 캐릭터로 넘어간다.
const MAX_CHUNK_RESEND_REQUESTS_PER_HASH := 3

# 결측 청크 조사(2-5 후속, 사용자 가설) - WebSocketPeer의 받는 쪽 버퍼
# 기본값(65535바이트)은 청크 하나(Base64 후 약 43.8KB)를 1.46개밖에 못
# 담는다 - 두 개가 연달아 도착하면 두 번째가 밀려날 여지가 있다는 가설을
# 검증하기 위해 클라이언트(GameClient)의 받는 쪽 버퍼만 넉넉하게 키운다
# (서버는 이번 조사 대상이 아니라 안 건드림 - 실제 로그에서 서버는 손실이
# 없었다). 네이티브에서는 `WebSocketMultiplayerPeer.set_inbound_buffer_size()`
# 로 그대로 반영됨을 직접 확인했지만(기본 65535 → 설정값 그대로 유지),
# 웹(HTML5) export에서도 이 설정이 실제로 반영되는지는 이 상수를 넣은
# 빌드를 브라우저에서 돌려봐야 알 수 있다 - 무시되더라도 그 자체가
# 중요한 정보다(그러면 문제는 이 설정으로 못 건드리는 더 아래 계층에 있다는 뜻).
const CLIENT_INBOUND_BUFFER_BYTES := 1024 * 1024

# 결측 청크 조사(2-5 후속) - 실제로 원인이 이걸로 확정됐다(사용자가 웹
# 빌드로 재전송 요청 0건 성공을 확인함, docs/multiplayer.md §8.5-6). 지금은
# 업로드가 한 번에 한 명(Room.transfer_current_owner)뿐이라 서버가 실제로
# 넘친 적은 없지만, 여러 방이 동시에 전송 중이면 한 서버 프로세스가 받는
# 총량이 늘어나므로 클라이언트와 같은 값으로 미리 넉넉하게 잡아둔다.
const SERVER_INBOUND_BUFFER_BYTES := 1024 * 1024

# 실제 베타 테스트에서 발견 - 받는 쪽 버퍼만 키우고 **보내는 쪽**
# (outbound_buffer_size)은 기본값 65535바이트로 남아있었다. 서버가
# 캐릭터 팩을 릴레이할 때 43KB짜리 청크를 여러 개 연달아 내보내면
# 이 작은 버퍼가 계속 넘쳐서 청크가 새는 원인이 됐다(§8.5-7). 클라이언트
# (업로드하는 쪽)도 같은 문제를 겪으므로 같은 값을 공유한다.
const CLIENT_OUTBOUND_BUFFER_BYTES := 1024 * 1024
const SERVER_OUTBOUND_BUFFER_BYTES := 1024 * 1024

# 2-6(연결 끊김/재접속/턴 타임아웃, docs/multiplayer.md §6) - 자기 턴에
# 계속 아무 요청도 안 보내면(연결 여부와 무관하게) 서버가 대신 한 수 두는
# 시간 한도. 클라이언트도 카운트다운 표시에 같은 값을 써야 해서 공유한다.
const TURN_TIMEOUT_MSEC := 60000

# 2-6(§6) - 연결이 끊긴 뒤 같은 토큰으로 돌아올 수 있는 유예 시간
# (TRANSFERRING/IN_GAME 중 끊긴 경우 - 이 두 단계는 "다른 사람이 지금
# 이 사람을 기다리고 있는" 상황이라 짧게 잡는다). 이 안에 안 돌아오면
# "확정 이탈"로 넘어가 그때부터는 매턴 즉시 자동 처리된다(넘어간 뒤에도
# 재접속 자체는 계속 허용함 - 사용자 확인). 원래 2분이었으나 실제로
# 친구와 플레이해보니 너무 길어서 60초(TURN_TIMEOUT_MSEC과 같은 값)로
# 줄였다(사용자 지적). 두 값이 같아지면 "턴이 막 시작된 직후 끊기면 유예
# 만료와 턴 시간 초과가 같은 시점에 겹칠 수 있다"는 경계가 생기는데,
# server_main.gd의 _service_in_game_rooms()는 이 둘을 하나의 if(OR)로
# 묶어서 처리하므로 겹쳐도 턴은 정확히 한 번만 처리된다 - 이 불변식은
# test_room_connection.gd의 grace_expiry_and_turn_timeout_coincide 테스트로
# 고정해뒀다.
#
# 친구 대상 실제 베타 테스트 후속(사용자 지적) - 예전 주석은 "REMATCHING
# (재대전 대기) 중 끊긴 경우도 이 값 하나로 처리한다"고 적혀 있었지만
# 사실이 아니었다: RECONNECT_GRACE_MSEC 기반 유예 만료(is_grace_expired())는
# server_main.gd의 _service_in_game_rooms()에서만 검사되는데, 그 함수는
# room.state != IN_GAME인 방을 통째로 건너뛴다 - 그래서 REMATCHING 중에는
# 이 60초 시계가 설정만 되고 한 번도 확인되지 않는 죽은 값이었고, 실제로는
# 아래 REMATCH_READY_TIMEOUT_MSEC(2분, 방 전체 기준) 하나가 사실상의
# 상한이었다. "우연히 60초보다 넉넉하다"에 기대는 건 다음에 누가
# _service_in_game_rooms()의 상태 필터를 무심코 넓히면 조용히 60초로
# 줄어드는 사고를 만들 수 있어서, 아래 POST_GAME_RECONNECT_GRACE_MSEC을
# 새로 만들고 Room.grace_expired_disconnected_slots()로 REMATCHING 전용
# 검사를 명시적으로 추가했다(server_main.gd::_service_rematch_rooms()).
const IN_GAME_RECONNECT_GRACE_MSEC := 60000

# 위 IN_GAME_RECONNECT_GRACE_MSEC과 같은 개념이지만 REMATCHING(재대전
# 대기 - 결과 화면을 보고 있는 그 순간) 전용이다. 게임 도중과 달리 이
# 단계에서는 다른 사람이 이 사람의 턴을 기다리는 게 아니므로(사용자 지적 -
# "게임 중에는 다른 사람이 기다리지만 결과 화면에서는 아무도 기다리지
# 않는다") 재접속 유예를 더 넉넉하게 준다. `RoomManager.remove_peer()`가
# room.state를 보고 IN_GAME/POST_GAME 중 어느 유예를 쓸지 고르고,
# `Room.begin_rematch_wait()`는 게임이 막 끝나는 순간 이미 끊긴 채였던
# 슬롯의 유예도 이 값 기준으로 다시 잡아준다(안 그러면 게임 도중 확보했던
# 60초의 나머지 몇 초만 남은 채로 결과 화면에 들어가게 된다).
const POST_GAME_RECONNECT_GRACE_MSEC := 180000

# 2-6B(같은 방에서 재대전, docs/multiplayer.md §3/§6) - 게임이 끝나고
# REMATCHING으로 들어가면, "연결은 멀쩡한데 그냥 준비 버튼을 안 누른"
# 사람을 방 전체 기준으로 얼마나 기다려줄지. 끊긴 사람은 이제 이 값이
# 아니라 POST_GAME_RECONNECT_GRACE_MSEC(위, 3분)으로 개별적으로 관리된다
# (Room.not_ready_connected_slots()가 연결된 사람만 이 타이머 대상으로
# 골라낸다) - 그래서 두 값이 서로 다른 것(2분/3분)이 이제는 실제로 각자
# 의미가 있다(예전엔 REMATCH_READY_TIMEOUT_MSEC이 끊긴 사람에게도 사실상
# 유일한 상한이라 두 값의 차이가 무의미했다).
const REMATCH_READY_TIMEOUT_MSEC := 120000

# 2-6 - 첫 접속(배포 환경이 무료 플랜이라 유휴 시 서버가 잠들고 깨어나는 데
# 최대 1분 걸림)과 게임 도중 재접속 양쪽에 공용으로 쓰는 재시도 상한
# (ReconnectBackoff). 상수 하나로 묶어서 "재시도 로직을 따로 안 만든다"는
# 원칙을 지킨다.
const MAX_RECONNECT_ATTEMPTS := 5

# 2-6(연결 끊김 감지, docs/multiplayer.md §6) - "WebSocket 레벨 ping/pong"
# 대신 애플리케이션 레벨 메시지로 직접 구현한다(2-5 후속 §8.5-6에서 얻은
# 교훈 - 엔진의 WebSocket 관련 동작을 검증 없이 믿지 않는다). 서버가 5초마다
# 확인된 접속 전원에게 ping을 보내고, 15초간 아무 메시지도(디코드 성공
# 여부와 무관) 안 온 접속은 끊는다. 원래 server_main.gd 안에만 있었는데,
# 4번/5번 조사(사용자 요청 - 클라이언트에도 핑 간격 계측 추가)로
# game_client.gd도 같은 간격 값을 참조해야 해서 공유 파일로 옮겼다.
const PING_INTERVAL_MSEC := 5000
const PING_TIMEOUT_MSEC := 15000


## 청크 하나가 실제로 얼마나 큰 메시지가 되는지 대략 추정한다(Base64 인코딩
## ceil(n/3)*4 + JSON 봉투 오버헤드 어림값 200바이트) - CLIENT_INBOUND_BUFFER_BYTES
## 대비 "몇 개까지 버티는지"를 CHUNK_PAYLOAD_BYTES가 바뀌어도 다시 계산할
## 필요 없이 항상 최신 값으로 보여주기 위함(PackTransferClient의 "이번 전송
## 중 최대 대기 M개(버퍼 한계 약 N개)" 로그가 이 함수를 쓴다).
static func estimate_encoded_chunk_bytes() -> int:
	return int(ceil(float(CHUNK_PAYLOAD_BYTES) / 3.0) * 4.0) + 200


## 확정 2 후속(사용자 지적) - `_send()`가 put_packet()을 바로 시도해도
## 안전한지 판단하는 유일한 기준. 처음엔 "버퍼에 조금이라도 남아있으면
## 무조건 큐로"였는데, 이러면 한 프레임에 패킷 하나만 나가서 1MB로 키운
## 버퍼가 사실상 무의미해지고 팩 전송이 느려진다(사용자 지적 - 실측으로
## 확인됨, docs/multiplayer.md §8.5-7). 그래서 "지금 버퍼에 남은 양 +
## 이번에 보낼 바이트 + 여유"가 실제 한도를 넘지 않으면 바로 보낸다 -
## 여유는 청크 하나(estimate_encoded_chunk_bytes())만큼 항상 남겨둔다.
## 이 프로토콜에서 청크가 가장 큰 메시지 종류이므로, "한 번 더 최대
## 크기 메시지가 와도 여유가 있다"는 걸 보장하는 셈이다.
static func has_room_to_send_now(buffered_amount: int, message_size: int, buffer_limit: int) -> bool:
	if buffer_limit <= 0:
		return true  # 0 이하는 "제한 없음"이라는 뜻(WebSocketPeer 자체 관례).
	return buffered_amount + message_size + estimate_encoded_chunk_bytes() <= buffer_limit


## 데드락 방지 안전장치(친구 대상 베타 후속, 사용자 지적) - has_room_to_send_now()의
## margin 계산("메시지 크기 + 청크 하나만큼의 여유")이 buffer_limit보다 큰
## 조합이면, 그 메시지는 버퍼가 완전히 빈 상태(buffered_amount=0)에서도
## 영원히 "여유 없음" 판정을 받는다 - put_packet()도 안 부르고 큐에만
## 계속 쌓이는, 에러 로그 한 줄 없는 조용한 정체다. 청크가 이 프로토콜에서
## 가장 큰 메시지이므로, "청크 하나가 빈 버퍼에도 못 들어가는 조합인가"만
## 확인하면 다른 모든 메시지(청크보다 작음)도 안전함이 보장된다. 서버/
## 클라이언트가 실제로 쓸 outbound_buffer_size를 정한 직후(연결/서버
## 생성 전) 이 함수로 확인해서, 거짓이면 그 자리에서 중단하는 게 나중에
## 전송 도중 조용히 멈추는 것보다 훨씬 빨리·명확하게 실패한다.
static func can_chunk_ever_be_sent(buffer_limit: int) -> bool:
	return has_room_to_send_now(0, estimate_encoded_chunk_bytes(), buffer_limit)

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

# 2-5(캐릭터 팩 전송) §2단계 - client -> server.
const MSG_REQUEST_CHARACTER_PACK := "request_character_pack"
const MSG_UPLOAD_PACK_CHUNK := "upload_pack_chunk"

# 2-5 후속 - "내가 받아야 할 팩을 전부 처리했다"는 영수증(성공/실패/애초에
# 받을 게 없었음 전부 포함 - "더 기다릴 게 없다"는 뜻이지 "전부 성공했다"는
# 뜻이 아니다). 서버는 방 전원에게서 이걸 받은 뒤에만 game_started를 보낸다.
const MSG_PACK_READY := "pack_ready"

# 2-5 후속(결측 청크 단위 재전송) - 특정 순번들이 안 왔을 때 그것만 다시
# 보내달라는 요청. 서버는 이 요청을 방 전체에 방송하지 않고 그 해시의
# 소유자에게만 전달한다(MSG_PACK_CHUNKS_REQUESTED, 아래).
const MSG_REQUEST_PACK_CHUNKS := "request_pack_chunks"

# 2-6(§6) - 서버의 ping에 대한 응답. 별도 페이로드 없음 - 서버는 이 메시지
# 자체가 아니라 "어떤 메시지든 왔다"는 사실로 마지막 통신 시각을 갱신하므로
# (조용히 유휴 상태인 정상 접속을 pong 하나로만 판단하지 않기 위함), pong은
# "나 아직 응답할 수 있다"는 확인일 뿐 별도 처리 로직이 없다.
const MSG_PONG := "pong"

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

# 2-5(캐릭터 팩 전송) §2단계 - server -> client. pack_upload_requested/
# pack_transfer_failed는 관련자에게만 보내지 않고 방 전체에 방송한다 -
# 요청을 안 한 사람도 "지금 누구 걸 기다리는지" UI를 갱신해야 하고, 그
# 판단(내 해시인가/내가 요청한 해시인가/그냥 구경만 하는가)은 각 클라이언트가
# 이미 알고 있는 정보(자기 해시, 자기가 보낸 요청)만으로 로컬에서 할 수
# 있어서 서버가 수신자 목록을 따로 알려줄 필요가 없다.
const MSG_TRANSFERRING_STARTED := "transferring_started"
const MSG_PACK_UPLOAD_REQUESTED := "pack_upload_requested"
const MSG_PACK_CHUNK := "pack_chunk"
const MSG_PACK_TRANSFER_FAILED := "pack_transfer_failed"

# 2-5 후속(결측 청크 단위 재전송) - MSG_REQUEST_PACK_CHUNKS를 소유자에게만
# 전달하는 메시지(위 MSG_PACK_UPLOAD_REQUESTED 등과 달리 방 전체 방송이
# 아니다 - 소유자 본인 외에는 이 정보로 할 일이 없다).
const MSG_PACK_CHUNKS_REQUESTED := "pack_chunks_requested"

# 2-6(§6) - 끊김 감지용 애플리케이션 레벨 ping. 방 전체가 아니라 접속
# 하나하나에 보내므로 방송이 아니다(server_main.gd가 각 peer에게 개별
# 전송). 페이로드 없음.
const MSG_PING := "ping"

# 2-6(§6) - "재접속 유예 중이던 플레이어가 돌아왔을 때 전원에게"(문서에
# 이미 이름이 정의돼 있었음, 이번에 실제로 구현).
const MSG_PLAYER_RECONNECTED := "player_reconnected"

# 2-6 - 턴 제한/재접속 유예 카운트다운을 화면에 보여주기 위한 신규 메시지
# (문서 §6에는 없던 요구사항 - 이번에 추가). kind는 "turn"(그 슬롯이 지금
# 턴 제한 카운트다운 중), "reconnect"(그 슬롯이 재접속 유예 카운트다운
# 중), "rematch"(2-6B - 게임 종료 후 재대전 대기 카운트다운, player_index는
# 아직 준비 안 한 슬롯) 셋 중 하나. 초 단위 정수만 담는 작은 메시지라
# 방 전체에 1초 주기로 방송해도 부담이 없다(2-5 후속 §8.5-6에서 확인한
# 메시지 크기 기준).
const MSG_PLAYER_TIMER := "player_timer"

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
