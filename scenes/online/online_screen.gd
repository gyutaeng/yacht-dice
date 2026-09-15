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
signal game_play_started(client: GameClient, my_index: int, profiles: Array[CharacterProfile])

## [캐릭터 선택] 버튼을 누르면 emit한다 - Main.gd가 1-6의
## CharacterSelectScreen을 1인분(configure(1))만 빌려 보여주고, 결과를
## set_my_profile()로 돌려준다(2-4B). 새 캐릭터 선택 화면을 따로 안 만든다.
signal character_select_requested()

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


func _ready() -> void:
	add_child(_client)
	add_child(_pack_transfer)
	_pack_transfer.configure(_client)
	_pack_transfer.progress_changed.connect(_on_transfer_progress_changed)
	_pack_transfer.profile_ready.connect(_on_pack_profile_ready)
	_pack_transfer.debug_log.connect(_append_transfer_debug_log)
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
	_client.server_error.connect(_on_server_error)
	_client.disconnected.connect(_on_disconnected)

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
func _connect_and_then(action: Callable) -> void:
	if _connected:
		action.call()
		return

	_pending_action = action
	_connect_status_label.text = "서버에 연결하는 중..."
	_client.connect_to_server(_server_address_edit.text.strip_edges())


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
	_show_connect_panel()


func _on_ready_button_pressed() -> void:
	var current: bool = _players.get(_my_index, {}).get("ready", false)
	_client.set_ready(not current)


func _on_host_set_player_count(count: int) -> void:
	_client.set_player_count(count)


func _on_connection_failed(reason: String) -> void:
	_pending_action = Callable()
	_connect_status_label.text = reason


func _on_hello_acknowledged() -> void:
	_connected = true
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		action.call()


func _on_room_created(code: String, player_count: int, _reconnect_token: String) -> void:
	_room_code = code
	_capacity = player_count
	_my_index = 0
	_players = {0: {"meta": {}, "ready": false}}
	# 발급된 토큰은 저장까지만 한다(2-6에서 실제 재접속 매칭 구현) - 지금은
	# 새로고침 후 복귀 UI가 없어도 저장은 해둔다.
	SessionStore.save(code, _reconnect_token, 0)
	_client.select_character(_my_character_meta())
	_show_lobby_panel()


func _on_room_joined(players: Array, my_index: int, reconnect_token: String, player_count: int) -> void:
	_my_index = my_index
	_capacity = player_count
	_players.clear()
	for entry in players:
		_players[int(entry["player_index"])] = {"meta": entry.get("meta", {}), "ready": entry.get("ready", false)}
	SessionStore.save(_room_code, reconnect_token, my_index)
	_client.select_character(_my_character_meta())
	_show_lobby_panel()


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

	if not _pack_transfer.is_all_resolved():
		if BuildInfo.DEBUG_MODE:
			_append_transfer_debug_log("game_started 도착했지만 아직 처리 중인 해시가 남음(서버의 pack_ready 대기를 놓쳤거나 타임아웃) - 로컬에서 마저 기다림")
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
			_append_transfer_debug_log("[P%d] game_started 도착 시점에 PackTransferClient.get_profile(%d)이 아직 null - 전송/검증이 안 끝난 상태에서 슬롯이 확정됨(기본 프로필로 대체)" % [i + 1, i])
		var profile := CharacterProfile.new()
		var display_name: String = _players.get(i, {}).get("meta", {}).get("display_name", "")
		profile.display_name = display_name if not display_name.is_empty() else "플레이어 %d" % (i + 1)
		profiles.append(profile)

	game_play_started.emit(_client, _my_index, profiles)


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


func _on_server_error(_code: String, message: String) -> void:
	if _lobby_panel.visible:
		_lobby_status_label.text = message
	else:
		_connect_status_label.text = message


func _on_disconnected() -> void:
	_show_connect_panel()
	_connect_status_label.text = "서버와의 연결이 끊어졌습니다."


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
