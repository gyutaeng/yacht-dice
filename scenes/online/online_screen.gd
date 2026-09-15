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

## 내가 고른 캐릭터(2-4B) - 게임 화면이 처음 뜰 때 CharacterLibrary의
## 첫 항목(내장 기본 포함이라 항상 1개 이상)으로 기본값을 잡아둬서,
## [캐릭터 선택]을 안 눌러도 항상 유효한 프로필이 붙어 있게 한다.
var _my_profile: CharacterProfile

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

var _my_index: int = -1
var _room_code: String = ""
var _capacity: int = 0
var _players: Dictionary = {}  # player_index(int) -> {meta: Dictionary, ready: bool}
var _pending_action: Callable = Callable()
var _connected := false


func _ready() -> void:
	add_child(_client)
	_server_address_edit.text = DEFAULT_SERVER_URL

	var default_profiles := CharacterLibrary.get_selectable_profiles()
	if not default_profiles.is_empty():
		_my_profile = default_profiles[0]
	_refresh_my_character_display()

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
	return {"id": id, "display_name": display_name}


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


## 내 슬롯만 내가 실제로 고른 CharacterProfile을 그대로 쓴다(2-4B) - 내
## 캐릭터는 이미 이 컴퓨터에 있으니 네트워크로 받을 필요가 없다. 남의
## 슬롯은 여전히 닉네임만 채운 빈 CharacterProfile(voice_map 비어있음,
## 실루엣 폴백)이다 - 2-3이 정한 v1 범위(문서 §8) 그대로, 2-5에서 실제
## 캐릭터 팩이 오가면 채워진다. 이 배열이 그대로 VoiceBank.configure()/
## _build_character_area()/_build_scoreboard()로 넘어가므로(2-4에서 이미
## 뚫어놓은 경로) 그 함수들은 손댈 필요가 없다 - 로컬에서 "일부만 캐릭터를
## 설정한 다인 게임"과 입력 모양이 똑같다.
func _on_game_started(player_count: int) -> void:
	print("[온라인] 게임 시작! (%d인)" % player_count)

	var profiles: Array[CharacterProfile] = []
	for i in player_count:
		if i == _my_index and _my_profile != null:
			profiles.append(_my_profile)
			continue
		var profile := CharacterProfile.new()
		var display_name: String = _players.get(i, {}).get("meta", {}).get("display_name", "")
		profile.display_name = display_name if not display_name.is_empty() else "플레이어 %d" % (i + 1)
		profiles.append(profile)

	game_play_started.emit(_client, _my_index, profiles)


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
