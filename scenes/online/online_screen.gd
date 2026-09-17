extends Control

# 온라인 게임 화면(2-3/2-4, docs/multiplayer.md). character_select_panel.gd처럼
# Main.tscn에 자식으로 들어가는 자체 완결형 화면 - GameClient를 직접 들고
# 있고, 밖으로는 back_requested/game_play_started 두 시그널만 낸다.

signal back_requested()

## 서버의 game_started(로비 종료)를 받으면 emit한다 - Main.gd가 이걸 받아
## OnlineGameController를 만들고 Screen.GAME(로컬과 같은 게임 화면)으로
## 전환한다. GameClient는 그대로 넘겨준다 - 이 노드(online_screen)는
## Screen.GAME으로 바뀌면 visible=false가 될 뿐 트리에서 안 사라지므로
## _client(자식 노드)의 _process()는 계속 돌아 패킷을 받는다.
## is_resume: F5 등으로 이미 진행 중이던 게임에 복귀하는 경우 true - Main.gd가
## 이 값으로 게임 시작 인사 연출을 다시 틀지 말지 정한다(이미 지나간 연출).
signal game_play_started(client: GameClient, my_index: int, profiles: Array[CharacterProfile], is_resume: bool)

## [캐릭터 선택] 버튼을 누르면 emit한다 - Main.gd가 1-6의
## CharacterSelectScreen을 1인분(configure(1))만 빌려 보여주고, 결과를
## set_my_profile()로 돌려준다(2-4B). 새 캐릭터 선택 화면을 따로 안 만든다.
signal character_select_requested()

# 2-6(연결 끊김/재접속, docs/multiplayer.md §6).
## 접속 상태 문구가 바뀔 때마다 emit한다 - PackTransferClient의
## progress_changed/get_status_text()와 같은 패턴. Main.gd가 게임 화면
## 위의 재접속 배너 표시 여부/문구를 이걸로 갱신한다.
signal connection_status_changed()
## 게임 도중 끊겼다가 같은 세션으로 다시 붙는 데 성공했을 때(로비 패널을
## 다시 보여주지 않는 조용한 재접속) emit한다 - Main.gd는 배너만 지우면
## 된다(화면 전환 없음).
signal game_reconnected()
## 재접속 재시도를 상한(NetProtocol.MAX_RECONNECT_ATTEMPTS)까지 다
## 써버리고도 못 붙었을 때 emit한다 - Main.gd가 "로비로 나가기" 선택지를
## 보여준다.
signal reconnect_exhausted()

const DEFAULT_SERVER_URL := "ws://127.0.0.1:8910"

var _client: GameClient = GameClient.new()
var _pack_transfer: PackTransferClient = PackTransferClient.new()

## 내가 고른 캐릭터(2-4B) - 게임 화면이 처음 뜰 때 CharacterLibrary의
## 첫 항목(내장 기본 포함이라 항상 1개 이상)으로 기본값을 잡아둬서,
## [캐릭터 선택]을 안 눌러도 항상 유효한 프로필이 붙어 있게 한다.
var _my_profile: CharacterProfile

## 내 캐릭터 팩(2-5 §1단계) - 내장 기본 캐릭터는 내보낼 수 없으므로
## 그때는 둘 다 빈 값이다("팩 없음, 기본 캐릭터 사용"이라는 뜻이고
## 남들도 그렇게 해석한다). 캐릭터를 고른 시점에 미리 압축+해시까지
## 끝내둔다 - 나중에 업로드 요청(2단계)이 와도 재압축 없이 바로 보낼 수
## 있게.
var _my_pack_bytes: PackedByteArray = PackedByteArray()
var _my_pack_hash: String = ""

@onready var _connect_panel: VBoxContainer = $CenterContainer/VBox/ConnectPanel
@onready var _server_address_edit: LineEdit = $CenterContainer/VBox/ConnectPanel/ServerRow/ServerAddressEdit
@onready var _my_thumbnail: TextureRect = $CenterContainer/VBox/ConnectPanel/MyCharacterRow/ThumbnailClip/ThumbnailTexture
@onready var _my_thumbnail_clip: Control = $CenterContainer/VBox/ConnectPanel/MyCharacterRow/ThumbnailClip
@onready var _my_name_label: Label = $CenterContainer/VBox/ConnectPanel/MyCharacterRow/NameLabel
@onready var _select_character_button: Button = $CenterContainer/VBox/ConnectPanel/MyCharacterRow/SelectCharacterButton
@onready var _connect_status_label: Label = $CenterContainer/VBox/ConnectPanel/ConnectStatusLabel
@onready var _create_room_button: Button = $CenterContainer/VBox/ConnectPanel/ActionButtonsRow/CreateRoomButton
@onready var _join_room_button: Button = $CenterContainer/VBox/ConnectPanel/ActionButtonsRow/JoinRoomButton
@onready var _create_room_count_row: HBoxContainer = $CenterContainer/VBox/ConnectPanel/CreateRoomCountRow
@onready var _join_room_row: HBoxContainer = $CenterContainer/VBox/ConnectPanel/JoinRoomRow
@onready var _code_edit: LineEdit = $CenterContainer/VBox/ConnectPanel/JoinRoomRow/CodeEdit
@onready var _join_confirm_button: Button = $CenterContainer/VBox/ConnectPanel/JoinRoomRow/JoinConfirmButton
@onready var _connect_back_button: Button = $CenterContainer/VBox/ConnectPanel/ConnectBackButton

@onready var _lobby_panel: VBoxContainer = $CenterContainer/VBox/LobbyPanel
@onready var _room_code_label: Label = $CenterContainer/VBox/LobbyPanel/RoomCodeLabel
@onready var _capacity_label: Label = $CenterContainer/VBox/LobbyPanel/CapacityLabel
@onready var _host_count_row: HBoxContainer = $CenterContainer/VBox/LobbyPanel/HostCountRow
@onready var _participants_list: VBoxContainer = $CenterContainer/VBox/LobbyPanel/ParticipantsList
@onready var _ready_button: Button = $CenterContainer/VBox/LobbyPanel/ReadyButton
@onready var _lobby_status_label: Label = $CenterContainer/VBox/LobbyPanel/LobbyStatusLabel
@onready var _leave_button: Button = $CenterContainer/VBox/LobbyPanel/LeaveButton

## 2-5 전송 버그(청크가 하나만 나가고 멈추던 문제) 조사용 - 브라우저 콘솔은
## print()가 안 닿으므로(1-5) 화면에 직접 남긴다. Main.gd의
## `_debug_init_log()`와 같은 패턴(최근 N줄만 유지, DEBUG_MODE로 켜고 끔).
const DEBUG_LOG_MAX_LINES := 40
@onready var _transfer_debug_log: RichTextLabel = $TransferDebugLog
var _transfer_debug_log_lines: Array[String] = []

var _my_index: int = -1
var _room_code: String = ""
var _capacity: int = 0
var _players: Dictionary = {}  # player_index(int) -> {meta: Dictionary, ready: bool}
var _pending_action: Callable = Callable()
var _connected := false

# 2-6(§6) - 첫 접속(서버 기상 대기)/게임 도중 재접속 공용 재시도 로직.
var _reconnect_backoff := ReconnectBackoff.new()
## SessionStore에 저장하는 것과 별개로 살아있는 동안 바로 쓸 수 있게 들고
## 있는다(재접속 시 join_room(code, token)에 그대로 씀).
var _my_reconnect_token: String = ""
## 게임 화면으로 넘어간 적이 한 번이라도 있으면 true - 그 뒤의 disconnected는
## "로비 이탈"이 아니라 "게임 도중 끊김"으로 다뤄야 한다(재시도 대상).
var _game_already_entered := false
## 지금 진행 중인 connect_to_server() 재시도가 "게임 도중 끊겨서 돌아오는
## 것"인지 구분한다(문구/성공 시 처리가 다름 - 로비 재진입이 아니라 조용히
## 이어붙기만 함).
var _reconnecting_after_disconnect := false
## Main.gd의 시작 다이얼로그에서 "예"를 눌러 이전 세션으로 복귀를 시도
## 중인지(2-6) - 이때는 room_joined가 와도 로비 패널을 보여주지 않고
## 곧바로 게임 화면 진입 절차(캐릭터 팩 확인 → game_play_started)를 탄다.
var _resuming_session := false
var _connection_status_text := ""


func _ready() -> void:
	add_child(_client)
	add_child(_pack_transfer)
	_pack_transfer.configure(_client)
	_pack_transfer.progress_changed.connect(_on_transfer_progress_changed)
	_pack_transfer.profile_ready.connect(_on_pack_profile_ready)
	_pack_transfer.debug_log.connect(_append_transfer_debug_log)
	# 결측 청크 조사(2-5 후속) - GameClient의 패킷 수신 계측(대기/꺼냄 개수,
	# decode 실패)도 같은 화면 로그로 보이게 한다. 웹 빌드는 브라우저 콘솔의
	# print()를 못 믿으므로(1-5) 이 화면 로그가 유일하게 믿을 수 있는 창구다.
	_client.debug_log.connect(_append_transfer_debug_log)
	_transfer_debug_log.visible = BuildInfo.DEBUG_MODE
	_server_address_edit.text = DEFAULT_SERVER_URL

	var default_profiles := CharacterLibrary.get_selectable_profiles()
	set_my_profile(default_profiles[0] if not default_profiles.is_empty() else null)

	_create_room_button.pressed.connect(func() -> void: _create_room_count_row.visible = true)
	_join_room_button.pressed.connect(func() -> void: _join_room_row.visible = true)
	_connect_back_button.pressed.connect(_on_connect_back_pressed)
	_join_confirm_button.pressed.connect(_on_join_confirm_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_ready_button.pressed.connect(_on_ready_button_pressed)
	_select_character_button.pressed.connect(func() -> void: character_select_requested.emit())
	# character_select_panel.gd와 같은 이유 - 처음 그려질 때는 클립 박스
	# 크기가 아직 (0,0)일 수 있어서, 실제 크기가 잡히면 다시 맞춘다.
	_my_thumbnail_clip.resized.connect(_refresh_my_character_display)

	for count in [2, 3, 4]:
		var create_button: Button = _create_room_count_row.get_node("Create%dButton" % count)
		create_button.pressed.connect(_on_create_count_selected.bind(count))
		var host_button: Button = _host_count_row.get_node("Count%dButton" % count)
		host_button.pressed.connect(_on_host_set_player_count.bind(count))

	_client.connection_failed.connect(_on_connection_failed)
	_client.hello_acknowledged.connect(_on_hello_acknowledged)
	_client.room_created.connect(_on_room_created)
	_client.room_joined.connect(_on_room_joined)
	_client.player_joined.connect(_on_player_joined)
	_client.player_character_changed.connect(_on_player_character_changed)
	_client.player_ready_changed.connect(_on_player_ready_changed)
	_client.room_player_count_changed.connect(_on_room_player_count_changed)
	_client.player_left.connect(_on_player_left)
	_client.transferring_started.connect(_on_transferring_started)
	_client.game_started.connect(_on_game_started)
	_client.game_ended.connect(_on_game_ended)
	_client.server_error.connect(_on_server_error)
	_client.disconnected.connect(_on_disconnected)
	# 2-6B(같은 방에서 재대전) - "rematch" 종류의 카운트다운만 여기서
	# 받는다("turn"/"reconnect"는 게임 화면 쪽 관심사라 Main.gd가 직접
	# _client를 구독한다, 2-6).
	_client.player_timer.connect(_on_player_timer)

	_show_connect_panel()


## Main.gd가 [온라인 게임]을 누를 때마다 부른다 - 이전 접속을 정리하고
## 처음 상태로 되돌린다.
func reset_to_start() -> void:
	_client.close()
	_show_connect_panel()


## Main.gd가 1-6의 CharacterSelectScreen(1인분)에서 고른 결과를 돌려줄 때
## 부른다(2-4B) - character_select_requested를 emit한 뒤 대응.
func set_my_profile(profile: CharacterProfile) -> void:
	_my_profile = profile

	# 내장 기본 캐릭터는 내보낼 수 없다(CharacterLibrary.export_pack_bytes()가
	# 거부함) - 그때는 "팩 없음"으로 둔다. 압축은 여기서 한 번만 하고
	# 결과를 들고 있는다(선택할 때마다 다시 압축하지 않음).
	if profile != null and not profile.is_builtin:
		_my_pack_bytes = CharacterLibrary.export_pack_bytes(profile)
		_my_pack_hash = ReceivedPackCache.sha256_hex(_my_pack_bytes) if not _my_pack_bytes.is_empty() else ""
	else:
		_my_pack_bytes = PackedByteArray()
		_my_pack_hash = ""

	_refresh_my_character_display()


## 2-6B(같은 방에서 재대전) - Main.gd의 [한 판 더] → CharacterSelectScreen
## 흐름이 확정되면 이걸 부른다(로비 진입 전의 평범한 캐릭터 사전 선택은
## 그대로 set_my_profile()만 쓴다 - 그때는 아직 방이 없어서 보낼 곳이
## 없다). 이미 방 안이므로 캐릭터 선택 직후 바로 전송하고, "캐릭터 선택
## 화면으로 돌아갔다가 준비 상태가 된다"는 사용자 표현 그대로 준비까지
## 자동으로 보낸다(따로 [준비 완료]를 또 누르게 하지 않음). 해시가
## 지난 판과 같으면 전송 자체가 안 걸린다(2-5 캐시) - 여기서 새로 할 일이
## 없다.
func confirm_rematch_character(profile: CharacterProfile) -> void:
	set_my_profile(profile)
	_client.select_character(_my_character_meta())
	_client.set_ready(true)
	# 3번째 재대전 버그 조사(사용자 요청) - [한 판 더] 확정이 실제로
	# select_character/ready를 서버로 보내는지 확인용 진단.
	if BuildInfo.DEBUG_MODE:
		print("[클라] 한 판 더 확정 - select_character + ready(true) 전송함")


## 2-6B - 재대전 대기 카운트다운(kind="rematch")만 로비 상태 문구에
## 표시한다. "turn"/"reconnect"는 게임 화면 몫이라 여기서는 무시한다.
## 로비 패널이 안 보일 때(예: 아직 캐릭터 선택 화면에 있을 때)는 다음에
## 로비 패널을 다시 보여줄 때 자연히 최신 값으로 덮어써지므로 무시해도
## 된다.
func _on_player_timer(_player_index: int, kind: String, seconds_left: int) -> void:
	if kind != "rematch" or not _lobby_panel.visible:
		return
	_lobby_status_label.text = "다음 판 대기 중 (%d초 안에 준비 안 하면 나간 것으로 처리됩니다)" % seconds_left


## character_select_panel.gd의 슬롯 썸네일 갱신과 같은 방식
## (CharacterPortrait.resolve_thumbnail_texture()/TextureFit.fit()) -
## 새 로직 없이 그대로 재사용한다.
func _refresh_my_character_display() -> void:
	if _my_profile == null:
		_my_name_label.text = "캐릭터 없음"
		return

	_my_name_label.text = _my_profile.display_name
	var center_crop := CharacterPortrait.thumbnail_should_center_crop(_my_profile)
	TextureFit.fit(_my_thumbnail, CharacterPortrait.resolve_thumbnail_texture(_my_profile), _my_thumbnail_clip.size, true, 0.5 if center_crop else 0.0)


func _show_connect_panel() -> void:
	_connected = false
	_pending_action = Callable()
	_my_index = -1
	_room_code = ""
	_capacity = 0
	_players.clear()
	_game_already_entered = false
	_reconnecting_after_disconnect = false
	_resuming_session = false
	_reconnect_backoff.reset()
	_set_connection_status("")

	_create_room_count_row.visible = false
	_join_room_row.visible = false
	_connect_status_label.text = ""
	_connect_panel.visible = true
	_lobby_panel.visible = false


func _show_lobby_panel() -> void:
	_connect_panel.visible = false
	_lobby_panel.visible = true
	_room_code_label.text = _room_code
	_lobby_status_label.text = ""
	_refresh_lobby_ui()


## 아직 서버에 연결/hello 확인이 안 됐으면 먼저 연결하고, 끝나면 action을
## 실행한다. 이미 연결되어 있으면 바로 실행한다 - [방 만들기]/[방 참가]
## 양쪽에서 같은 흐름을 타므로 여기 하나로 모았다.
##
## 2-6(§6, 배포 환경 - Render 무료 플랜은 유휴 시 서버가 잠들고 깨어나는
## 데 최대 1분 걸림) - 연결 실패(connection_failed)가 오면
## ReconnectBackoff로 자동 재시도한다. 게임 도중 재접속과 같은
## ReconnectBackoff/재시도 루프(_on_connection_failed)를 공유한다.
func _connect_and_then(action: Callable) -> void:
	if _connected:
		action.call()
		return

	_reconnect_backoff.reset()
	_pending_action = action
	_set_connection_status("")
	_connect_status_label.text = "서버에 연결하는 중..."
	_client.connect_to_server(_server_address_edit.text.strip_edges())


func _set_connection_status(text: String) -> void:
	_connection_status_text = text
	connection_status_changed.emit()


## Main.gd가 게임 화면 위 재접속 배너에 표시할 문구 - 비어 있으면 배너를
## 숨긴다(PackTransferClient.get_status_text()와 같은 패턴).
func get_connection_status_text() -> String:
	return _connection_status_text


func _on_connect_back_pressed() -> void:
	_client.close()
	back_requested.emit()


func _on_create_count_selected(count: int) -> void:
	_connect_and_then(func() -> void: _client.create_room(count))


func _on_join_confirm_pressed() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		_connect_status_label.text = "방 코드를 입력하세요."
		return
	_room_code = code
	_connect_and_then(func() -> void: _client.join_room(code))


func _on_leave_pressed() -> void:
	_client.leave()
	SessionStore.clear()
	_show_connect_panel()


## 친구 대상 실제 베타 테스트 후속(사용자 지적) - 서버가 "슬롯 0에서
## 동일한 ready 값이 연속으로 수신됨"을 경고한 근본 원인. 예전엔 `current`를
## `_players`(서버 echo로만 갱신되는 캐시)에서 읽기만 하고 로컬 값은 안
## 바꿨다 - 그래서 왕복 시간 안에 이 핸들러가 두 번 불리면(웹 브라우저가
## 탭 하나를 터치+마우스 클릭 두 이벤트로 겹쳐 보내는 경우가 실제로 있음 -
## Godot HTML5 export의 알려진 특성) 둘 다 같은 `current`를 읽어 같은 값을
## 두 번 보낸다. ready가 절대값이라 지금은 상태가 안 뒤집히지만, 두 번째
## 클릭이 "진짜 토글 의도"였다면(빠르게 두 번 눌러 켰다 끄려 함) 서버에는
## 같은 값만 두 번 가고 의도한 두 번째 토글이 사라진다 - 그래서 보내는
## 즉시 로컬 캐시도 낙관적으로 갱신해서, 그 다음 호출(진짜 두 번째 클릭이든
## 중복 이벤트든)은 이미 뒤집힌 값을 기준으로 판단하게 한다.
func _on_ready_button_pressed() -> void:
	var current: bool = _players.get(_my_index, {}).get("ready", false)
	var next := not current
	if _players.has(_my_index):
		_players[_my_index]["ready"] = next
		_refresh_lobby_ui()
	_client.set_ready(next)


func _on_host_set_player_count(count: int) -> void:
	_client.set_player_count(count)


## 지금 어떤 상황으로 재시도 중인지에 따라 다른 안내 문구를 고른다 - 순수
## 판단 로직만 따로 빼서(_on_connection_failed()의 await/타이머와 분리)
## 실제 타이머를 기다리지 않고도 헤드리스로 바로 검증할 수 있게 했다
## (test_online_reconnect_messages.gd).
func _connection_retry_label() -> String:
	if _reconnecting_after_disconnect:
		return "게임 도중 재접속 시도 중"
	if _resuming_session:
		return "이전 게임에 다시 연결하는 중"
	return "서버를 깨우는 중입니다(최대 1분)"


## 2-6(§6) - 첫 접속(서버 기상 대기)/게임 도중 재접속/세션 복귀(F5) 공용
## 재시도 루프. ReconnectBackoff가 상한에 닿을 때까지 지수 백오프로 계속
## 다시 붙어본다.
##
## 5번 버그 조사(사용자 신고 - 게임이 끝난 뒤 새로고침하면 "서버를 깨우는
## 중"이라는 안내가 뜨고 방으로 못 돌아옴) - room.gd의 재접속 수락 로직
## 자체는 REMATCHING을 TRANSFERRING/IN_GAME과 동일하게(오히려 재대전 대기
## 시간 2분으로 더 넉넉하게) 받아주도록 이미 짜여 있어서(RoomManager.join_room()
## 의 토큰 매칭이 "방 상태와 무관하게" 항상 먼저 확인됨 - 방 상태로 거부하는
## 코드가 없음을 직접 확인했다), 이 증상은 join_room 요청이 서버에 도달하기도
## 전에 connect_to_server() 자체가 실패하고 있다는 뜻이다(바로 이 함수가
## 불리는 경로). 즉 진짜 원인은 room.gd가 아니라 "그 시점에 서버가 응답하지
## 않았다"일 가능성이 높다 - 4번(두 번째 게임 도중 서버 접속이 끊김)과 같은
## 근본 원인일 수 있다(취소된 4번을 로그만 남기고 다음 재현을 기다리는 이유).
##
## 그와 별개로 여기 문구 자체에도 실제 버그가 있었다: attempt_session_resume()
## (F5로 이전 세션에 복귀 시도)은 _reconnecting_after_disconnect를 안 켜므로
## 항상 else 분기로 빠져 "서버를 깨우는 중입니다"가 떴다 - 이 서버는 사용자
## 자신의 로컬 서버라 깨울 대상이 없는데도, Render 배포용으로 쓰려던 문구가
## 세션 복귀 시도에도 그대로 붙어 실패 원인을 가렸다. _connection_retry_label()에
## _resuming_session 분기를 추가해 세 가지 상황(게임 도중 재접속/세션
## 복귀/진짜 첫 접속)에 각각 다른 안내가 나가게 정리했다.
func _on_connection_failed(reason: String) -> void:
	if _reconnect_backoff.has_attempts_left():
		var attempt_no := _reconnect_backoff.attempt + 1
		var delay := _reconnect_backoff.next_delay_sec()
		var status_text := "%s - 재시도 %d/%d, %.0f초 후" % [_connection_retry_label(), attempt_no, NetProtocol.MAX_RECONNECT_ATTEMPTS, delay]
		_connect_status_label.text = status_text
		_set_connection_status(status_text)
		await get_tree().create_timer(delay).timeout
		_client.connect_to_server(_server_address_edit.text.strip_edges())
		return

	var msg := reason if reason != "" else "서버에 연결할 수 없습니다."
	_connect_status_label.text = msg
	_pending_action = Callable()
	_set_connection_status("")
	if _reconnecting_after_disconnect:
		_reconnecting_after_disconnect = false
		reconnect_exhausted.emit()
	elif _resuming_session:
		# 예전엔 이 분기가 없어서 _resuming_session이 계속 true로 남고,
		# 화면은 온라인 화면(연결 패널)에 위 msg만 찍힌 채 조용히
		# 멈춰 있었다(사용자가 본 증상과 일치) - _on_server_error()의
		# 세션 복귀 실패 처리와 같은 방식으로 확실히 연결 화면으로
		# 되돌린다.
		_resuming_session = false
		SessionStore.clear()
		_show_connect_panel()


func _on_hello_acknowledged() -> void:
	_connected = true
	_reconnect_backoff.reset()
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		action.call()


func _on_room_created(code: String, player_count: int, reconnect_token: String) -> void:
	_room_code = code
	_capacity = player_count
	_my_index = 0
	_players = {0: {"meta": {}, "ready": false}}
	_my_reconnect_token = reconnect_token
	SessionStore.save(code, reconnect_token, 0)
	_client.select_character(_my_character_meta())
	_show_lobby_panel()


## 2-6(§6) - 이 핸들러는 세 가지 경우 모두를 받는다: (1) 평범한 새 참가
## (2) 게임 도중 끊겼다가 같은 세션으로 조용히 돌아온 경우
## (_reconnecting_after_disconnect) (3) 앱을 새로 켜서(F5 등) 저장된
## 세션으로 복귀를 시도한 경우(_resuming_session). (2)/(3)는 로비 패널을
## 다시 보여주지 않는다 - 이미 게임이 진행 중이라 로비로 돌아갈 이유가 없다.
func _on_room_joined(players: Array, my_index: int, reconnect_token: String, player_count: int) -> void:
	_my_index = my_index
	_capacity = player_count
	_players.clear()
	for entry in players:
		_players[int(entry["player_index"])] = {"meta": entry.get("meta", {}), "ready": entry.get("ready", false)}
	_my_reconnect_token = reconnect_token
	SessionStore.save(_room_code, reconnect_token, my_index)

	if _reconnecting_after_disconnect:
		_reconnecting_after_disconnect = false
		_reconnect_backoff.reset()
		_set_connection_status("")
		game_reconnected.emit()
		return

	if _resuming_session:
		_resuming_session = false
		# 새로고침(F5)으로 앱 자체가 처음부터 다시 뜬 것이므로, _ready()가
		# 잡아둔 _my_profile은 "내가 고르던 캐릭터"가 아니라 그냥 기본값
		# (get_selectable_profiles()[0])이다 - 그대로 두면 화면엔 항상
		# 기본 캐릭터로 보인다. 서버가 room_joined에 실어 보내주는 내 슬롯의
		# meta.id(끊기기 전에 select_character로 보냈던 그 값)로 로컬
		# CharacterLibrary에서 같은 캐릭터를 다시 찾아 복원한다 - 이미 내
		# 컴퓨터에 있는 캐릭터라 네트워크 요청이 필요 없다. 못 찾으면(그
		# 사이 캐릭터를 지웠거나 시크릿 모드 등) set_my_profile()을 안
		# 부르고 그대로 둬서 기본 캐릭터로 남는다 - 딱 그 경우에만.
		var my_id := str(_players.get(_my_index, {}).get("meta", {}).get("id", ""))
		if not my_id.is_empty():
			var restored := _find_profile_by_id(my_id)
			if restored != null:
				set_my_profile(restored)

		# 로비 종료 흐름은 _on_transferring_started()가 begin()을 이미
		# 불러뒀지만, 복귀 흐름은 그 이벤트를 다시 못 받으므로(이미 지난
		# 사건) 여기서 직접 불러 필요한 팩 요청을 시작한다 - 위에서 복원한
		# _my_profile/_my_pack_hash를 그대로 넘기므로, 남들이 나와 같은
		# 캐릭터를 골랐으면 그 사람 몫도 네트워크 없이 바로 풀린다. 방이
		# 아직 TRANSFERRING 단계일 수도 있지만(새로고침 타이밍이 아주 나쁜
		# 경우), 그 경우도 포함해 "이미 IN_GAME"으로 간주하고 곧장 게임
		# 화면 진입 절차를 탄다 - 극히 드문 경계 상황이라 정교하게 나누지
		# 않는다(그 경우 첫 실제 상태 스냅샷이 도착할 때까지 점수판이
		# 잠깐 기본값으로 보일 수 있는 정도).
		_pack_transfer.begin(_my_index, _my_profile, _my_pack_bytes, _my_pack_hash, _players)
		await _resolve_profiles_and_enter_game(player_count, true)
		return

	_client.select_character(_my_character_meta())
	_show_lobby_panel()


## 2-6(§6) - Main.gd가 시작 시 저장된 세션을 발견하고 사용자가 "예"를
## 눌렀을 때 부른다. 실패(방이 이미 정리됨 등)해도 사용자에게 알릴 필요는
## 없다(§6 - "혹시 몰라서" 물어본 것이라 실패도 자연스러운 결과) -
## _on_server_error()가 방 화면에 문구만 남기고, 재시도 소진 시엔
## reconnect_exhausted가 그대로 처리한다.
func attempt_session_resume(saved: Dictionary) -> void:
	_room_code = str(saved.get("code", ""))
	_my_reconnect_token = str(saved.get("reconnect_token", ""))
	if _room_code.is_empty() or _my_reconnect_token.is_empty():
		SessionStore.clear()
		return

	_resuming_session = true
	_reconnect_backoff.reset()
	_connect_status_label.text = "이전 게임에 다시 연결하는 중..."
	_pending_action = func() -> void:
		_client.join_room(_room_code, _my_reconnect_token)
	_client.connect_to_server(_server_address_edit.text.strip_edges())


## 세션 복귀 시 서버가 알려준 내 캐릭터 id로 로컬 CharacterLibrary에서
## 같은 캐릭터를 다시 찾는다(내장 기본 캐릭터의 id "default" 포함 -
## get_selectable_profiles()가 그것도 같이 돌려준다). 못 찾으면 null.
func _find_profile_by_id(id: String) -> CharacterProfile:
	for profile in CharacterLibrary.get_selectable_profiles():
		if profile.id == id:
			return profile
	return null


## 서버가 최종 검증/기본값 부여를 다시 하므로(server_main.gd, 원칙 6 -
## 클라이언트만 믿지 않는다) 여기서 하는 정리는 UX용이다. id는 문서가
## 이미 정의해둔 필드에 처음으로 실제 값을 채우는 것뿐이라 프로토콜
## 변경이 아니다(2-4B) - 2-5에서 캐릭터 팩을 요청할 때 쓸 수 있게 미리
## 채워둔다.
func _my_character_meta() -> Dictionary:
	var display_name := ""
	var id := ""
	if _my_profile != null:
		display_name = NetProtocol.sanitize_display_name(_my_profile.display_name)
		id = _my_profile.id
	if display_name.is_empty():
		display_name = "플레이어 %d" % (_my_index + 1)
	return {"id": id, "display_name": display_name, "pack_hash": _my_pack_hash}


func _on_player_joined(player_index: int, meta: Dictionary) -> void:
	_players[player_index] = {"meta": meta, "ready": false}
	_refresh_lobby_ui()


func _on_player_character_changed(player_index: int, meta: Dictionary) -> void:
	if not _players.has(player_index):
		_players[player_index] = {"meta": meta, "ready": false}
	else:
		_players[player_index]["meta"] = meta
	_refresh_lobby_ui()


func _on_player_ready_changed(player_index: int, ready: bool) -> void:
	if _players.has(player_index):
		_players[player_index]["ready"] = ready
	_refresh_lobby_ui()


## 2-6B 후속(친구 대상 베타 재현, "ready 중복 근본 원인 수정"이 실제로는
## 안 듣던 문제) - 서버의 Room.begin_rematch_wait()는 게임이 끝나는
## 순간 전원의 ready를 false로 되돌리지만, 그 사실을 알리는 메시지가
## 따로 없다(player_ready_changed 브로드캐스트 없음 - 새 메시지를 안 만들고
## 조용히 리셋하는 설계). 그래서 게임 종료 직후 로컬 `_players` 캐시는
## 그 판을 시작할 때의 값(항상 true - 전원 준비돼야 게임이 시작되므로)을
## 그대로 들고 있다가, 재대전 대기 화면에서 준비 버튼을 처음 누르면
## "이미 true인 걸 false로" 토글한 값이 나가는데 서버는 이미 false라
## "동일한 ready 값이 연속으로 수신됨" 경고가 뜬다 - 로그 노이즈로
## 끝나지 않고 실제 버그이기도 하다: 버튼 라벨이 "준비 취소"(캐시가
## true라서)로 잘못 떠서, 유저는 이미 준비된 줄 알고 아무것도 안
## 누르지만 서버는 준비 안 된 상태로 남아 재대전 대기 타임아웃(2분)에
## 강제 퇴장될 수 있다. `game_ended`(서버가 `begin_rematch_wait()`를
## 부르는 바로 그 순간 함께 오는 신호)를 받으면 클라이언트도 로컬
## 캐시를 똑같이 리셋해서 서버와 다시 맞춘다 - 새 네트워크 메시지를
## 안 만들고 이미 오는 신호에 맞춰 로컬만 고치는 방식.
func _on_game_ended(_winners: Array, _scores: Array) -> void:
	for player_index in _players.keys():
		_players[player_index]["ready"] = false
	_refresh_lobby_ui()


func _on_room_player_count_changed(player_count: int) -> void:
	_capacity = player_count
	_refresh_lobby_ui()


func _on_player_left(player_index: int, _reason: String) -> void:
	_players.erase(player_index)
	_refresh_lobby_ui()


## 서버가 로비를 다 채우고 전송 단계로 들어갔다는 신호(2-5 §2단계) - 화면
## 전환은 안 하고(로비 화면에 그대로 머무름) 상태 문구만 바꾼다. 실제
## "누구 걸 받을지" 판단은 PackTransferClient.begin()이 한다.
func _on_transferring_started() -> void:
	_lobby_status_label.text = "캐릭터를 주고받는 중..."
	_pack_transfer.begin(_my_index, _my_profile, _my_pack_bytes, _my_pack_hash, _players)


func _on_transfer_progress_changed() -> void:
	if not _lobby_panel.visible:
		return
	var status := _pack_transfer.get_status_text()
	if status != "":
		_lobby_status_label.text = status


func _on_pack_profile_ready(_player_index: int, _profile: CharacterProfile) -> void:
	_on_transfer_progress_changed()


## PackTransferClient.debug_log를 화면에 받아 적는다(Main.gd의
## _debug_init_log()와 같은 패턴) - BuildInfo.DEBUG_MODE가 false면 노드 자체가
## 안 보이지만, 로그 수집 자체는 계속한다(나중에 켜도 최근 기록이 남게).
func _append_transfer_debug_log(text: String) -> void:
	print("[전송] %s" % text)
	if _transfer_debug_log == null:
		return

	_transfer_debug_log_lines.append("[%s] %s" % [Time.get_time_string_from_system(), text])
	if _transfer_debug_log_lines.size() > DEBUG_LOG_MAX_LINES:
		_transfer_debug_log_lines.pop_front()

	_transfer_debug_log.text = "\n".join(_transfer_debug_log_lines)


## 내 슬롯만 내가 실제로 고른 CharacterProfile을 그대로 쓴다(2-4B) - 내
## 캐릭터는 이미 이 컴퓨터에 있으니 네트워크로 받을 필요가 없다. 남의 슬롯은
## PackTransferClient가 2-5 §2단계에서 이미 전송을 마치고(또는 캐시 재사용,
## 또는 실패 시 기본 캐릭터로 대체) 확정해둔 프로필을 그대로 쓴다 - 서버가
## game_started를 보낼 때는 이미 방 전체의 전송이 끝난(성공이든 실패든)
## 뒤이므로 get_profile()이 항상 값을 갖고 있어야 하지만, 혹시 몰라 null이면
## 닉네임만 채운 빈 CharacterProfile로 방어적으로 폴백한다. 이 배열이 그대로
## VoiceBank.configure()/_build_character_area()/_build_scoreboard()로
## 넘어가므로(2-4에서 이미 뚫어놓은 경로) 그 함수들은 손댈 필요가 없다.
## 서버가 이제 전원의 pack_ready를 받은 뒤에만 game_started를 보내므로
## (2-5 후속) 이 시점엔 보통 이미 전부 끝나 있어야 한다. 그래도 클라이언트
## 쪽에도 한 겹 더 방어선을 둔다 - 아직 처리 중인 해시가 남아있으면
## PackTransferClient.LOCAL_PACK_RESOLVE_TIMEOUT_MSEC(10초)까지만 기다렸다가
## 강제로 포기한다(2-5 후속 버그 수정 - 청크 하나가 영영 안 와서 "전부
## 모였는지" 검사가 계속 실패하면 이 대기가 무한정 이어지던 확실한 버그가
## 있었다). "게임 화면으로 안 넘어가는 경로는 없다"가 여기서 보장된다.
func _on_game_started(player_count: int) -> void:
	print("[온라인] 게임 시작! (%d인)" % player_count)
	await _resolve_profiles_and_enter_game(player_count, false)


## 로비 종료(_on_game_started)와 세션 복귀(_on_room_joined의 _resuming_session
## 분기, attempt_session_resume()) 양쪽이 공유하는 꼬리 부분(2-6) - "이제
## 실제 게임 화면으로 넘어갈 준비를 한다"는 점이 똑같다: 아직 처리 중인
## 캐릭터 팩 해시가 있으면 마저 기다리고, 슬롯별 프로필을 조립해
## game_play_started를 emit한다. 복귀 흐름은 이 함수를 부르기 전에
## _pack_transfer.begin()을 직접 호출해서 필요한 팩 요청을 먼저 시작해둬야
## 한다(로비 종료 흐름은 _on_transferring_started()가 이미 해뒀음).
## is_resume은 그대로 game_play_started에 실어 Main.gd에 전달한다 - 복귀
## 흐름에서는 인사 연출을 다시 틀면 안 된다(이미 지나간 연출).
func _resolve_profiles_and_enter_game(player_count: int, is_resume: bool) -> void:
	_game_already_entered = true

	if not _pack_transfer.is_all_resolved():
		if BuildInfo.DEBUG_MODE:
			_append_transfer_debug_log("아직 처리 중인 해시가 남음(서버의 pack_ready 대기를 놓쳤거나 타임아웃, 또는 방금 재접속) - 로컬에서 마저 기다림")
		await _pack_transfer.wait_until_all_resolved()

	var profiles: Array[CharacterProfile] = []
	for i in player_count:
		if i == _my_index and _my_profile != null:
			profiles.append(_my_profile)
			continue
		var resolved := _pack_transfer.get_profile(i)
		if resolved != null:
			profiles.append(resolved)
			_debug_log_slot_connection(i, resolved)
			continue
		if BuildInfo.DEBUG_MODE:
			_append_transfer_debug_log("[P%d] PackTransferClient.get_profile(%d)이 아직 null - 전송/검증이 안 끝난 상태에서 슬롯이 확정됨(기본 프로필로 대체)" % [i + 1, i])
		var profile := CharacterProfile.new()
		var display_name: String = _players.get(i, {}).get("meta", {}).get("display_name", "")
		profile.display_name = display_name if not display_name.is_empty() else "플레이어 %d" % (i + 1)
		profiles.append(profile)

	game_play_started.emit(_client, _my_index, profiles, is_resume)


## 사용자 요청 진단(2-5) - "팩은 도착했는데 아무도 안 쓴다"는 증상을 잡기
## 위한 마지막 확인 지점. get_profile()이 non-null을 돌려줬어도, 실제로
## 초상이 로드되는지/보이스가 몇 개 매핑됐는지까지 봐야 "저장은 됐는데
## 실제 연결에서 빠졌는지"를 구분할 수 있다.
func _debug_log_slot_connection(player_index: int, profile: CharacterProfile) -> void:
	if not BuildInfo.DEBUG_MODE:
		return
	var portrait_ok := false
	if profile.portrait_file != "":
		portrait_ok = CharacterLibrary.load_profile_texture(profile, profile.portrait_file) != null
	var voice_count := 0
	for key in profile.voice_map:
		voice_count += profile.voice_map[key].size()
	_append_transfer_debug_log("[P%d] 슬롯 %d에 연결됨 / 초상 %s / 보이스 %d개 매핑" % [
		player_index + 1, player_index,
		"OK" if portrait_ok else ("없음" if profile.portrait_file == "" else "로드 실패(%s)" % profile.portrait_file),
		voice_count,
	])


## 2-6(§6) - 세션 복귀 시도가 서버 쪽 사유(방이 이미 정리됨 등)로
## 실패하면 조용히 포기한다("혹시 몰라서" 물어본 것이라 실패도 자연스러운
## 결과 - 사용자에게 에러 문구를 보여줄 필요가 없다). 저장된 세션도
## 지워서 다음에 또 물어보지 않게 한다.
func _on_server_error(_code: String, message: String) -> void:
	if _resuming_session:
		_resuming_session = false
		SessionStore.clear()
		_show_connect_panel()
		return
	if _reconnecting_after_disconnect:
		# 소켓은 다시 붙었지만 서버가 그 방을 이미 정리한 경우(서버 재시작
		# 등, §9 범위 밖) - 재시도로는 해결 안 되는 실패이므로 바로 포기한다.
		_reconnecting_after_disconnect = false
		SessionStore.clear()
		_set_connection_status("")
		reconnect_exhausted.emit()
		return
	if _lobby_panel.visible:
		_lobby_status_label.text = message
	else:
		_connect_status_label.text = message


## 2-6(§6) - 게임 화면에 한 번이라도 들어간 뒤(_game_already_entered)의
## 끊김은 "로비 이탈"이 아니라 "게임 도중 끊김"이다 - 로비로 튕기지 않고
## (_show_connect_panel()을 안 부름) 조용히 재접속을 시도한다. Main.gd는
## connection_status_changed로 게임 화면 위 배너만 갱신한다. 게임 시작
## 전(로비 단계) 끊김은 기존 동작(연결 패널로 되돌아감) 그대로 둔다.
func _on_disconnected() -> void:
	if not _game_already_entered:
		_show_connect_panel()
		_connect_status_label.text = "서버와의 연결이 끊어졌습니다."
		return

	_reconnecting_after_disconnect = true
	_reconnect_backoff.reset()
	_set_connection_status("연결이 끊어졌습니다. 재접속 시도 중...")
	_pending_action = func() -> void:
		_client.join_room(_room_code, _my_reconnect_token)
	_client.connect_to_server(_server_address_edit.text.strip_edges())


func _lowest_occupied_index() -> int:
	var lowest := -1
	for index in _players.keys():
		if lowest == -1 or index < lowest:
			lowest = index
	return lowest


func _refresh_lobby_ui() -> void:
	_capacity_label.text = "인원 %d/%d" % [_players.size(), _capacity]

	var am_host := _my_index != -1 and _my_index == _lowest_occupied_index()
	_host_count_row.visible = am_host
	if am_host:
		for count in [2, 3, 4]:
			var button: Button = _host_count_row.get_node("Count%dButton" % count)
			button.disabled = count < _players.size()

	for child in _participants_list.get_children():
		_participants_list.remove_child(child)
		child.queue_free()

	for i in _capacity:
		var label := Label.new()
		if _players.has(i):
			var entry: Dictionary = _players[i]
			var display_name: String = entry["meta"].get("display_name", "")
			if display_name.is_empty():
				display_name = "(닉네임 없음)"
			var ready_text := "준비 완료" if entry["ready"] else "대기 중"
			var mine := " (나)" if i == _my_index else ""
			label.text = "P%d %s%s - %s" % [i + 1, display_name, mine, ready_text]
		else:
			label.text = "P%d (비어 있음)" % (i + 1)
		_participants_list.add_child(label)

	var my_ready: bool = _players.get(_my_index, {}).get("ready", false)
	_ready_button.text = "준비 취소" if my_ready else "준비 완료"
