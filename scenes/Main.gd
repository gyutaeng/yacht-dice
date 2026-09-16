extends Control

# 화면 전환을 한 곳에서만 관리한다 - 이 셋 중 "지금 보여야 할 하나"만
# visible=true가 되고 나머지는 전부 visible=false가 된다(_show_screen()).
# 예전엔 버튼 핸들러마다 각자 visible을 켜고 꺼서, 하나를 끄는 걸 빠뜨리면
# 안 보여야 할 화면이 뒤에 투명하게 남아 클릭을 가로채는 버그가 있었다.
# GameOverOverlay는 GAME 위에 뜨는 모달이라 이 enum에 안 넣는다(별도 관리).
enum Screen { START, CHARACTER_SELECT, GAME, ONLINE }

const ROW_HEIGHT := 26.0
const SMALL_TAG_SIZE := 56.0
const PORTRAIT_FADE_DURATION := 0.3
const BOLD_FONT_PATH := "res://assets/fonts/Pretendard-Bold.otf"

# 효과음은 SfxBank가 special_hand_rolled를 직접 구독해서 재생한다(여기선 화면 연출만).
const SPECIAL_HAND_DISPLAY_DURATION := 1.5
const SPECIAL_HAND_FADE_DURATION := 0.15

var game_state: GameState

# "리모컨" 패턴(2-4) - 화면은 로컬을 조종하는지 서버에 요청을 보내는지
# 모른다. 버튼이 눌리면 이 컨트롤러의 request_*()만 부른다. 어느
# 컨트롤러를 붙일지는 _enter_game()과 그걸 부르는 두 진입점
# (_start_new_game/_on_online_game_play_started) 한 곳에서만 정해진다 -
# 화면 코드 안에는 if 온라인 분기가 없다. LocalGameController/
# OnlineGameController(scripts/game/)는 같은 이름의 메서드만 맞춘
# 덕타이핑 계약이라 정적 타입을 안 붙인다.
var active_controller
# 온라인일 때만 "내 슬롯 번호"(0-based) - 로컬은 -1(턴 제한 없음).
# GameState/GameClient가 아니라 이 값만 화면이 직접 들고 읽는다.
var my_player_index: int = -1

# 온라인 로비의 [캐릭터 선택]이 1-6의 CharacterSelectScreen을 그대로
# 빌려 쓸 때(2-4B), 그 결과가 로컬 새 게임 시작인지 온라인 캐릭터
# 선택인지 구분하는 플래그. 기본값 false라 로컬 흐름은 코드 경로가
# 전혀 안 바뀐다. 분기는 이 플래그를 보는 두 핸들러 안에서만 일어난다.
var _character_select_for_online: bool = false

# 2-6B(같은 방에서 재대전) - _character_select_for_online이 true인 두
# 경우(로비 사전 선택 vs 게임 종료 후 [한 판 더]) 중 후자를 표시한다.
# 이게 true면 확정 시점에 online_screen.confirm_rematch_character()로
# 보내서 select_character+ready(true)까지 자동으로 나가게 한다.
var _character_select_for_rematch: bool = false

var locked_style := StyleBoxFlat.new()
var column_normal_style := StyleBoxFlat.new()
var column_highlight_style := StyleBoxFlat.new()
var row_divider_style := StyleBoxFlat.new()
var preview_button_style := StyleBoxFlat.new()
var selected_cell_style := StyleBoxFlat.new()
var game_over_panel_style := StyleBoxFlat.new()
var bold_font: Font  # 확정된 점수 표시용. Pretendard Bold를 그대로 쓴다(_ready에서 로드).

# 점수판에서 "선택"만 된 상태(아직 확정 아님). 주사위를 다시 굴리면 해제된다.
var selected_category: int = -1

## 빠른 진행 버튼(DEBUG_MODE, 온라인 전용)이 굴리기->확정을 순서대로 처리하는
## 중인지 - 연타로 두 번 겹쳐 들어가는 것만 막는다(그 외 버튼 활성화 여부는
## _is_my_turn()/is_request_pending()이 이미 담당).
var _quick_progress_running: bool = false

# score_labels[player][category] -> Label(확정/빈칸), preview_buttons[player][category] -> Button(미확정 미리보기, 누르면 확정)
var score_labels: Array = []
var preview_buttons: Array = []
var upper_bonus_labels: Array[Label] = []
var bonus_labels: Array[Label] = []
var total_labels: Array[Label] = []
var player_columns: Array[PanelContainer] = []
var small_tag_rows: Array[Control] = []
# connection_status_labels[p] - 그 플레이어 칸 밑에 붙는 연결 상태 문구
# (2-6, docs/multiplayer.md §6). 로컬 게임에서는 관련 신호가 전혀 안 와서
# 항상 빈 채로 숨겨져 있다 - 온라인 전용 표시다.
var connection_status_labels: Array[Label] = []
# player_index -> true, "확정 이탈"(reason="timeout")로 통보받은 슬롯.
# 하나라도 있으면 [로비로 나가기] 버튼을 보여준다(2-6).
var _departed_player_indices: Dictionary = {}
# 2-6 - 온라인 게임 중인 GameClient. player_left/player_reconnected/
# player_timer를 직접 구독하기 위해 들고 있는다(online_screen이 이미
# _client를 갖고 있지만, 게임 화면에서 벌어지는 일이라 Main.gd가 직접
# 구독하는 게 자연스럽다).
var _online_client: GameClient = null
# 2-6 - 시작 시 SessionStore에서 읽은 세션. 다이얼로그에서 "예"를 누르면
# 이걸 그대로 online_screen.attempt_session_resume()에 넘긴다.
var _pending_saved_session: Dictionary = {}

# player_character_assignments[player] -> CharacterProfile.
var player_character_assignments: Array[CharacterProfile] = []

# 큰 슬롯 크로스페이드 상태.
var _portrait_front_is_a: bool = true
var _current_portrait_player: int = -1
var _portrait_tween: Tween
var _label_tween: Tween
var _special_hand_tween: Tween

# 게임 시작 인사 연출(1-4C) 진행 중인지. 이 동안 InputBlocker가 입력을
# 막고, 클릭/키 입력은 건너뛰기로 처리하며, 디버그 버튼도 무시된다
# (debug_hotkeys.greeting_active로 전달).
var _greeting_active: bool = false

@onready var start_screen: Control = $StartScreen
@onready var game_screen: Control = $GameScreen
@onready var mode_choice_row: HBoxContainer = $StartScreen/CenterContainer/VBox/ModeChoiceRow
@onready var local_game_button: Button = $StartScreen/CenterContainer/VBox/ModeChoiceRow/LocalGameButton
@onready var online_game_button: Button = $StartScreen/CenterContainer/VBox/ModeChoiceRow/OnlineGameButton
@onready var local_game_panel: VBoxContainer = $StartScreen/CenterContainer/VBox/LocalGamePanel
@onready var local_back_button: Button = $StartScreen/CenterContainer/VBox/LocalGamePanel/LocalBackButton
@onready var players_2_button: Button = $StartScreen/CenterContainer/VBox/LocalGamePanel/PlayerCountRow/Players2Button
@onready var players_3_button: Button = $StartScreen/CenterContainer/VBox/LocalGamePanel/PlayerCountRow/Players3Button
@onready var players_4_button: Button = $StartScreen/CenterContainer/VBox/LocalGamePanel/PlayerCountRow/Players4Button
@onready var manage_characters_button: Button = $StartScreen/CenterContainer/VBox/ManageCharactersButton

@onready var character_select_screen = $CharacterSelectScreen
@onready var online_screen = $OnlineScreen

@onready var turn_label: Label = $GameScreen/Margin/MainHBox/RightColumn/TurnLabel
@onready var turn_countdown_label: Label = $GameScreen/Margin/MainHBox/RightColumn/TurnCountdownLabel
@onready var leave_to_lobby_button: Button = $GameScreen/Margin/MainHBox/RightColumn/LeaveToLobbyButton
@onready var big_portrait_area: PanelContainer = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea
@onready var portrait_stack: Control = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack
@onready var portrait_texture_a: TextureRect = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack/PortraitTextureA
@onready var portrait_texture_b: TextureRect = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack/PortraitTextureB
@onready var big_name_label: Label = $GameScreen/Margin/MainHBox/LeftColumn/BigNameLabel
@onready var small_tags_row: HBoxContainer = $GameScreen/Margin/MainHBox/LeftColumn/SmallTagsRow
@onready var special_hand_label: Label = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/SpecialHandLabel
@onready var input_blocker: Control = $GameScreen/InputBlocker
@onready var greeting_skip_button: Button = $GameScreen/InputBlocker/GreetingSkipButton

@onready var dice_labels: Array[Label] = [
	$GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/DiceRow/Dice1,
	$GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/DiceRow/Dice2,
	$GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/DiceRow/Dice3,
	$GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/DiceRow/Dice4,
	$GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/DiceRow/Dice5,
]
@onready var reroll_label: Label = $GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/RerollLabel
@onready var roll_button: Button = $GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/ButtonsRow/RollButton
@onready var confirm_score_button: Button = $GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/ButtonsRow/ConfirmScoreButton
## DEBUG_MODE 전용, 온라인에서만 보임(2-6/2-6B 테스트 편의) - 아래
## _on_quick_progress_button_pressed() 참고.
@onready var quick_progress_button: Button = $GameScreen/Margin/MainHBox/RightColumn/DiceAndControls/ButtonsRow/QuickProgressButton

@onready var scoreboard_row: HBoxContainer = $GameScreen/Margin/MainHBox/RightColumn/ScoreboardRow

@onready var game_over_overlay: Control = $GameOverOverlay
@onready var game_over_panel: PanelContainer = $GameOverOverlay/CenterContainer/Panel
@onready var game_over_label: Label = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverLabel
@onready var restart_button: Button = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverButtonsRow/RestartButton
@onready var rematch_button: Button = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverButtonsRow/RematchButton
@onready var to_title_button: Button = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverButtonsRow/ToTitleButton

@onready var quit_confirm_dialog: ConfirmationDialog = $QuitConfirmDialog

# 2-6(연결 끊김/재접속/턴 타임아웃, docs/multiplayer.md §6).
@onready var reconnect_overlay: Control = $ReconnectOverlay
@onready var reconnect_status_label: Label = $ReconnectOverlay/Banner/HBox/StatusLabel
@onready var reconnect_overlay_leave_button: Button = $ReconnectOverlay/Banner/HBox/OverlayLeaveButton
@onready var session_resume_dialog: ConfirmationDialog = $SessionResumeDialog

@onready var debug_hotkeys = $DebugHotkeys

## BuildInfo.DEBUG_MODE일 때만 보이는 화면 좌상단 진단 로그(res://scenes/Main.tscn의
## DebugInitLog 노드). 에디터에서 재현이 안 되고 export 빌드(특히 웹)에서만 나는
## 버그를 잡을 때 쓴다 - 자세한 건 _debug_init_log() 참고.
@onready var debug_init_log: RichTextLabel = $DebugInitLog


func _ready() -> void:
	locked_style.bg_color = Color(0.2, 0.6, 0.2, 0.5)
	locked_style.border_color = Color(0.1, 0.9, 0.1)
	locked_style.border_width_left = 3
	locked_style.border_width_top = 3
	locked_style.border_width_right = 3
	locked_style.border_width_bottom = 3

	column_normal_style.bg_color = Color(1, 1, 1, 0.03)
	column_normal_style.border_color = Color(1, 1, 1, 0.15)
	column_normal_style.border_width_left = 1
	column_normal_style.border_width_top = 1
	column_normal_style.border_width_right = 1
	column_normal_style.border_width_bottom = 1

	column_highlight_style.bg_color = Color(0.25, 0.45, 0.85, 0.35)
	column_highlight_style.border_color = Color(0.35, 0.6, 1.0)
	column_highlight_style.border_width_left = 3
	column_highlight_style.border_width_top = 3
	column_highlight_style.border_width_right = 3
	column_highlight_style.border_width_bottom = 3

	row_divider_style.bg_color = Color(0, 0, 0, 0)
	row_divider_style.border_color = Color(1, 1, 1, 0.12)
	row_divider_style.border_width_bottom = 1

	preview_button_style.bg_color = Color(1, 1, 1, 0.08)
	preview_button_style.border_color = Color(1, 1, 1, 0.35)
	preview_button_style.border_width_left = 1
	preview_button_style.border_width_top = 1
	preview_button_style.border_width_right = 1
	preview_button_style.border_width_bottom = 1
	preview_button_style.content_margin_left = 6
	preview_button_style.content_margin_right = 6
	preview_button_style.content_margin_top = 1
	preview_button_style.content_margin_bottom = 1

	selected_cell_style.bg_color = Color(1.0, 0.75, 0.2, 0.35)
	selected_cell_style.border_color = Color(1.0, 0.8, 0.3)
	selected_cell_style.border_width_left = 2
	selected_cell_style.border_width_top = 2
	selected_cell_style.border_width_right = 2
	selected_cell_style.border_width_bottom = 2
	selected_cell_style.content_margin_left = 6
	selected_cell_style.content_margin_right = 6
	selected_cell_style.content_margin_top = 1
	selected_cell_style.content_margin_bottom = 1

	game_over_panel_style.bg_color = Color(0.12, 0.12, 0.14, 0.97)
	game_over_panel_style.border_color = Color(1, 1, 1, 0.2)
	game_over_panel_style.border_width_left = 1
	game_over_panel_style.border_width_top = 1
	game_over_panel_style.border_width_right = 1
	game_over_panel_style.border_width_bottom = 1
	game_over_panel_style.content_margin_left = 32
	game_over_panel_style.content_margin_right = 32
	game_over_panel_style.content_margin_top = 24
	game_over_panel_style.content_margin_bottom = 24
	game_over_panel.add_theme_stylebox_override("panel", game_over_panel_style)

	bold_font = load(BOLD_FONT_PATH)
	special_hand_label.add_theme_font_override("font", bold_font)

	big_portrait_area.add_theme_stylebox_override("panel", column_normal_style)

	portrait_texture_a.modulate.a = 1.0
	portrait_texture_b.modulate.a = 0.0
	# 처음 전환이 걸리는 시점엔 방금 보이게 된 GameScreen의 레이아웃이 아직
	# 계산 전이라 portrait_stack.size가 (0,0)일 수 있다. 그래서 크기가 실제로
	# 잡힐 때(그리고 창 크기가 바뀔 때도) 현재 텍스처를 다시 맞춘다.
	portrait_stack.resized.connect(_on_portrait_stack_resized)

	players_2_button.pressed.connect(_on_start_pressed.bind(2))
	players_3_button.pressed.connect(_on_start_pressed.bind(3))
	players_4_button.pressed.connect(_on_start_pressed.bind(4))
	manage_characters_button.pressed.connect(_on_manage_characters_pressed)

	local_game_button.pressed.connect(_on_local_game_button_pressed)
	local_back_button.pressed.connect(_on_local_back_button_pressed)
	online_game_button.pressed.connect(_on_online_game_button_pressed)

	character_select_screen.selection_confirmed.connect(_on_character_selection_confirmed)
	character_select_screen.back_requested.connect(_on_character_select_back)

	online_screen.back_requested.connect(_on_online_back_requested)
	online_screen.game_play_started.connect(_on_online_game_play_started)
	online_screen.character_select_requested.connect(_on_online_character_select_requested)

	# 2-6(§6) - 온라인 화면이 통제하는 접속 재시도 상태를 게임 화면 위
	# 배너로 보여준다(화면 전환은 안 함 - 로비로 안 튕기는 게 핵심).
	online_screen.connection_status_changed.connect(_on_connection_status_changed)
	online_screen.game_reconnected.connect(_on_game_reconnected)
	online_screen.reconnect_exhausted.connect(_on_reconnect_exhausted)
	leave_to_lobby_button.pressed.connect(_return_to_title)
	reconnect_overlay_leave_button.pressed.connect(_return_to_title)

	roll_button.pressed.connect(_on_roll_button_pressed)
	confirm_score_button.pressed.connect(_on_confirm_score_pressed)
	quick_progress_button.pressed.connect(_on_quick_progress_button_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	rematch_button.pressed.connect(_on_rematch_button_pressed)
	to_title_button.pressed.connect(_on_to_title_pressed)
	quit_confirm_dialog.confirmed.connect(_return_to_title)

	# GameEvents는 앱이 사는 동안 계속 살아있는 autoload라서, game_state처럼
	# 게임을 새로 시작할 때마다가 아니라 여기서 딱 한 번만 연결한다.
	GameEvents.special_hand_rolled.connect(_on_special_hand_rolled)
	# 2-6(§6) - 새 턴이 시작되면 이전 턴의 카운트다운 문구는 의미가 없다.
	# 로컬 게임에서는 이 라벨이 애초에 한 번도 안 보이므로(player_timer가
	# 안 오니까) 매턴 숨기는 게 항상 안전하다.
	GameEvents.turn_started.connect(func(_p): turn_countdown_label.visible = false)

	# VoiceBank도 마찬가지로 앱 생애주기 내내 사는 autoload다 - 인사 연출
	# 시퀀스 시그널도 여기서 한 번만 연결한다.
	VoiceBank.greeting_step_started.connect(_on_greeting_step_started)
	VoiceBank.greeting_sequence_finished.connect(_on_greeting_sequence_finished)

	greeting_skip_button.pressed.connect(_on_greeting_skip_button_pressed)

	for i in dice_labels.size():
		var label := dice_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_dice_gui_input.bind(i))

	debug_init_log.visible = BuildInfo.DEBUG_MODE

	# 2-6(§6) - 저장된 세션이 있으면 "돌아가시겠어요?"를 묻는다. 거절해도
	# 세션 파일은 그대로 둔다(§6에 "거절 시 삭제" 조건이 없음 - 다음에
	# 다시 물어볼 수 있게).
	session_resume_dialog.confirmed.connect(_on_session_resume_confirmed)
	var saved_session = SessionStore.load()
	if saved_session != null:
		_pending_saved_session = saved_session
		session_resume_dialog.popup_centered()


func _unhandled_input(event: InputEvent) -> void:
	# 인사 연출 중에는 키보드 입력을 전부 무시한다(ESC 포함) - [인사 건너뛰기]
	# 버튼을 눌러야만 건너뛰어진다. 연출을 구경하고 싶은 사람이 아무 키나
	# 눌러서(또는 ESC로 종료 확인을 열려다) 실수로 건너뛰는 일이 없게 하기
	# 위함이다. 연출이 끝나면(_greeting_active=false) 이 분기를 안 타므로
	# ESC가 원래대로 종료 확인을 띄운다.
	if _greeting_active and event is InputEventKey:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if game_screen.visible and not quit_confirm_dialog.visible:
			quit_confirm_dialog.popup_centered()
			get_viewport().set_input_as_handled()


## 화면에 보이는 줄은 최근 것만 유지한다 - 안 그러면 DEBUG_MODE를 켜둔 채로
## 게임을 여러 판 계속 돌릴 때(1-8 웹 테스트처럼) 이 라벨에 텍스트가 무한히
## 쌓인다. append_text() 대신 배열에 최근 줄만 들고 있다가 매번 통째로
## 다시 그린다 - 30줄이면 문자열 합치기 비용이 무시할 만하다.
const DEBUG_LOG_MAX_LINES := 30
var _debug_log_lines: Array[String] = []


## BuildInfo.DEBUG_MODE가 false면 아무것도 안 한다(콘솔 print도 포함) - 웹에서는
## 브라우저 콘솔의 print() 출력을 못 믿을 수 있어서(1-5 참고), 초기화 단계마다
## 화면 구석에도 한 줄씩 남긴다. 어느 줄까지 찍히고 멈췄는지가 "어디서 끊겼는지"다.
## debug_hotkeys.gd의 버튼/단축키와 마찬가지로 DEBUG_MODE 하나로 켜고 끈다.
func _debug_init_log(message: String) -> void:
	if not BuildInfo.DEBUG_MODE:
		return
	print("[초기화] %s" % message)
	if debug_init_log == null:
		return

	_debug_log_lines.append("[%s] %s" % [Time.get_time_string_from_system(), message])
	if _debug_log_lines.size() > DEBUG_LOG_MAX_LINES:
		_debug_log_lines.pop_front()

	debug_init_log.text = "\n".join(_debug_log_lines)
	debug_init_log.scroll_to_line(debug_init_log.get_line_count() - 1)


## 게임을 새로 시작할 때마다 이전 판의 로그가 남아있으면 "어디서 끊겼는지"를
## 읽기 힘들어지므로 비운다.
func _clear_debug_log() -> void:
	_debug_log_lines.clear()
	if debug_init_log != null:
		debug_init_log.text = ""


## 웹에서 특수족보 연출만 안 뜨던 버그를 잡을 때 만든 진단 - GameEvents.special_hand_rolled에
## 실제로 몇 개가, 누가 연결돼 있는지 찍는다. 개수가 기대(SfxBank/VoiceBank/Main
## 셋)보다 적으면 "Main.gd의 _ready()가 connect()에 도달하기 전에 멈춘다"는 뜻이고,
## 개수가 맞는데도 연출이 안 뜨면 "연결은 됐고 핸들러 안에서 멈춘다"는 뜻이다.
func _debug_log_special_hand_subscribers() -> void:
	if not BuildInfo.DEBUG_MODE:
		return
	var connections := GameEvents.special_hand_rolled.get_connections()
	var names: Array[String] = []
	for c in connections:
		var callable: Callable = c["callable"]
		var target := callable.get_object()
		var target_name := "<null>"
		if target != null:
			target_name = target.name if (target is Node) else target.get_class()
		names.append("%s.%s" % [target_name, callable.get_method()])
	_debug_init_log("special_hand_rolled 구독자 수=%d, 목록=%s" % [connections.size(), names])


## 셋 중 하나만 보이게 하는 유일한 통로. 새 화면을 추가하게 되면 여기 enum과
## 이 함수에만 추가하면 된다 - 개별 핸들러에서 직접 .visible을 건드리지 말 것.
func _show_screen(screen: Screen) -> void:
	start_screen.visible = (screen == Screen.START)
	character_select_screen.visible = (screen == Screen.CHARACTER_SELECT)
	game_screen.visible = (screen == Screen.GAME)
	online_screen.visible = (screen == Screen.ONLINE)

	# 온라인 로비(ONLINE)와 온라인 게임(GAME + my_player_index != -1) 양쪽
	# 다 디버그 단축키 버튼을 숨긴다 - 온라인 화면에 "야추 강제" 버튼이
	# 떠 있으면 안 된다(2-4에서 사용자가 지적). 분기는 이 한 곳뿐이다.
	var is_online_screen := screen == Screen.ONLINE or (screen == Screen.GAME and my_player_index != -1)
	debug_hotkeys.set_panel_visible(not is_online_screen)


func _on_start_pressed(player_count: int) -> void:
	_show_screen(Screen.CHARACTER_SELECT)
	character_select_screen.configure(player_count)


func _on_character_select_back() -> void:
	if _character_select_for_online:
		_character_select_for_online = false
		_show_screen(Screen.ONLINE)
	else:
		_show_screen(Screen.START)


## 2-6(§6) - 시작 화면 다이얼로그에서 "예"를 눌렀을 때. 온라인 화면으로
## 전환하고 복귀 시도를 맡긴다 - 실패(방이 이미 정리됨 등)해도 조용히
## 평소 시작 화면으로 남는다(online_screen.attempt_session_resume() 참고).
func _on_session_resume_confirmed() -> void:
	var saved := _pending_saved_session
	_pending_saved_session = {}
	_show_screen(Screen.ONLINE)
	online_screen.attempt_session_resume(saved)


## [로컬 게임]/[온라인 게임] 중 하나를 고르기 전의 기본 상태로 되돌린다 -
## 온라인 화면에서 뒤로 나올 때처럼 "완전히 다른 모드에서 돌아온" 경우에만
## 쓴다. 로컬 인원수 화면(캐릭터 선택 등)에서 뒤로 오는 경로는 이 함수를
## 안 거치므로 LocalGamePanel이 계속 보인 채로 남는다(의도한 동작).
func _show_mode_choice() -> void:
	mode_choice_row.visible = true
	local_game_panel.visible = false


func _on_local_game_button_pressed() -> void:
	mode_choice_row.visible = false
	local_game_panel.visible = true


func _on_local_back_button_pressed() -> void:
	_show_mode_choice()


func _on_online_game_button_pressed() -> void:
	online_screen.reset_to_start()
	_show_screen(Screen.ONLINE)


func _on_online_back_requested() -> void:
	_show_screen(Screen.START)
	_show_mode_choice()


## 온라인 로비의 [캐릭터 선택] 버튼 - 1-6의 CharacterSelectScreen을 1인분만
## 잠깐 빌려 쓴다(새 화면을 안 만듦). 결과는 _on_character_selection_confirmed()가
## _character_select_for_online 플래그를 보고 온라인 쪽으로 돌려준다.
func _on_online_character_select_requested() -> void:
	_character_select_for_online = true
	character_select_screen.configure(1)
	_show_screen(Screen.CHARACTER_SELECT)


## 2-6B(같은 방에서 재대전) - 게임 종료 화면의 [한 판 더]. 로비의 [캐릭터
## 선택]과 완전히 같은 화면 흐름을 타되(2-4B 재사용, 새 로직 없음),
## 확정 시점에 "이미 방 안이니 바로 전송+준비까지 자동으로 보낸다"만
## 다르다 - 그 구분을 _character_select_for_rematch로 표시해둔다.
func _on_rematch_button_pressed() -> void:
	_character_select_for_rematch = true
	_on_online_character_select_requested()


func _on_character_selection_confirmed(profiles: Array[CharacterProfile]) -> void:
	if _character_select_for_online:
		_character_select_for_online = false
		if _character_select_for_rematch:
			_character_select_for_rematch = false
			online_screen.confirm_rematch_character(profiles[0])
		else:
			online_screen.set_my_profile(profiles[0])
		_show_screen(Screen.ONLINE)
	else:
		_start_new_game(profiles)


## 캐릭터 편집 화면은 위 3화면과 달리 "덮어씌우는 오버레이"라 Screen enum에
## 안 넣었다 - 대신 (1) 뒤 화면을 확실히 숨기고 (2) 편집 화면 루트에 화면
## 전체를 덮는 불투명 배경 + mouse_filter STOP을 둬서(character_editor.tscn)
## 이중으로 막는다. 시작 화면에서만 열리므로 닫을 때 시작 화면으로 되돌리면 된다.
func _on_manage_characters_pressed() -> void:
	start_screen.visible = false

	var editor_scene: PackedScene = load("res://scenes/character_editor/character_editor.tscn")
	var editor_instance: Control = editor_scene.instantiate()
	# 동적으로 인스턴스화한 씬이라 정적 타입을 모른다 - 문자열 기반 connect로
	# 컴파일 타임 멤버 검사를 피한다(캐릭터 편집 화면은 Main.gd가 몰라도 되는
	# 독립된 화면이라 class_name으로 엮을 필요가 없다).
	editor_instance.connect("closed", func() -> void:
		remove_child(editor_instance)
		editor_instance.queue_free()
		start_screen.visible = true
	)
	add_child(editor_instance)


func _on_restart_pressed() -> void:
	_start_new_game(player_character_assignments.duplicate())


func _on_to_title_pressed() -> void:
	_return_to_title()


func _return_to_title() -> void:
	if active_controller != null:
		active_controller.leave_game()
	active_controller = null
	my_player_index = -1

	# 2-6(§6) - 스스로 나가는 것이므로 재접속 세션을 끝낸다(끝난 게임에
	# 돌아가겠냐고 다음에 또 물어보지 않게). 이 함수는 로컬 게임 종료에도
	# 쓰이므로 깨끗한(비어있는) SessionStore.clear() 자체는 항상 안전하다.
	SessionStore.clear()
	_disconnect_online_client_signals()
	reconnect_overlay.visible = false
	leave_to_lobby_button.visible = false
	_departed_player_indices.clear()

	_clear_dynamic_nodes()
	_reset_portrait_transition_state()
	game_state = null
	debug_hotkeys.game_state = null
	VoiceBank.configure([])

	game_over_overlay.visible = false
	_show_screen(Screen.START)


func _reset_portrait_transition_state() -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()

	_current_portrait_player = -1
	portrait_texture_a.texture = null
	portrait_texture_b.texture = null
	portrait_texture_a.modulate.a = 1.0
	portrait_texture_b.modulate.a = 0.0
	_portrait_front_is_a = true
	big_name_label.modulate.a = 1.0

	if _special_hand_tween != null and _special_hand_tween.is_valid():
		_special_hand_tween.kill()
	special_hand_label.visible = false
	input_blocker.visible = false

	# 이론상 새 게임/재시작은 이전 판의 인사 연출이 끝난 뒤에만 가능하지만,
	# 방어적으로 여기서도 정리한다(VoiceBank.configure()의 방어적 초기화와 같은 이유).
	_greeting_active = false
	debug_hotkeys.greeting_active = false
	greeting_skip_button.visible = false


func _start_new_game(profiles: Array[CharacterProfile]) -> void:
	var controller := LocalGameController.new()
	controller.start(profiles.size())
	_enter_game(controller, profiles)


## online_screen이 서버의 game_started를 받아 로비를 끝내면 이걸 부른다
## (online_screen.gd의 game_play_started 시그널). profiles는 닉네임만 채운
## 빈 CharacterProfile 배열이다(2-3이 정한 v1 온라인 범위, 문서 §8).
## 2-6B(같은 방에서 재대전) - 재대전이 성공하면 같은 GameClient로 이
## 함수가 또 불린다(로비 종료 game_started가 다시 옴). 매번 새로
## connect()하면 두 번째 판부터 신호가 중복 연결되므로, 먼저 이전 구독을
## 확실히 끊고 다시 건다(_disconnect_online_client_signals()는 이미 2-6에서
## idempotent하게 만들어둔 헬퍼 - 그대로 재사용).
## is_resume(2-6 후속) - F5 등으로 이미 진행 중이던 게임에 복귀하는
## 경우다. 이때는 게임 시작 인사를 다시 틀지 않는다(이미 지나간 연출).
func _on_online_game_play_started(client: GameClient, my_index: int, profiles: Array[CharacterProfile], is_resume: bool) -> void:
	_disconnect_online_client_signals()
	_online_client = client
	_online_client.player_left.connect(_on_online_player_left)
	_online_client.player_reconnected.connect(_on_online_player_reconnected)
	_online_client.player_timer.connect(_on_online_player_timer)

	var controller := OnlineGameController.new(client, profiles.size(), my_index)
	_enter_game(controller, profiles, my_index, is_resume)


## 2-6(§6) - 다음 온라인 세션을 시작하기 전에(또는 로컬/타이틀로 돌아갈 때)
## 이전 세션의 구독을 확실히 끊는다 - 안 그러면 온라인 게임을 여러 번
## 오갈 때 콜백이 중복 호출된다.
func _disconnect_online_client_signals() -> void:
	if _online_client == null:
		return
	if _online_client.player_left.is_connected(_on_online_player_left):
		_online_client.player_left.disconnect(_on_online_player_left)
	if _online_client.player_reconnected.is_connected(_on_online_player_reconnected):
		_online_client.player_reconnected.disconnect(_on_online_player_reconnected)
	if _online_client.player_timer.is_connected(_on_online_player_timer):
		_online_client.player_timer.disconnect(_on_online_player_timer)
	_online_client = null


## 2-6(§6 "화면 표시") - 다른 플레이어의 연결 상태를 그 사람 칸 밑에
## 지속적으로 표시한다("한 번 뜨고 사라지는 토스트가 아니라 계속 붙어
## 있는 형태"). reason="disconnected"는 재접속 유예 중(약하게 표시),
## "timeout"은 확정 이탈(자동 진행 중이라고 계속 표시 + [로비로 나가기]
## 노출).
func _on_online_player_left(player_index: int, reason: String) -> void:
	if player_index < 0 or player_index >= connection_status_labels.size():
		return
	var label := connection_status_labels[player_index]
	if reason == "timeout":
		label.text = "나갔습니다 (자동 진행 중)"
		label.visible = true
		_departed_player_indices[player_index] = true
		leave_to_lobby_button.visible = true
	elif reason == "disconnected":
		label.text = "연결 끊김 - 재접속 대기 중"
		label.visible = true


func _on_online_player_reconnected(player_index: int) -> void:
	if player_index < 0 or player_index >= connection_status_labels.size():
		return
	connection_status_labels[player_index].visible = false
	_departed_player_indices.erase(player_index)
	leave_to_lobby_button.visible = not _departed_player_indices.is_empty()


## 2-6(§6, 새 요구사항) - 턴 제한/재접속 유예 카운트다운을 같은 메시지로
## 받는다(NetProtocol.MSG_PLAYER_TIMER). "turn"은 화면 상단 턴 라벨
## 옆으로, "reconnect"는 그 플레이어 칸 밑 문구에 남은 시간을 이어 붙인다.
func _on_online_player_timer(player_index: int, kind: String, seconds_left: int) -> void:
	if kind == "turn":
		turn_countdown_label.text = "(응답 없으면 %d초 후 자동 진행)" % seconds_left
		turn_countdown_label.visible = true
	elif kind == "reconnect" and player_index >= 0 and player_index < connection_status_labels.size():
		connection_status_labels[player_index].text = "연결 끊김 - 재접속 대기 중 (%d초)" % seconds_left
		connection_status_labels[player_index].visible = true


## 2-6(§6) - online_screen이 재접속을 시도/포기/성공할 때마다 배너를
## 갱신한다. 화면 전환은 절대 안 한다(_show_screen()을 안 부름) - 로비로
## 튕기지 않는 게 핵심 요구사항이다.
func _on_connection_status_changed() -> void:
	var text: String = online_screen.get_connection_status_text()
	reconnect_status_label.text = text
	reconnect_overlay.visible = text != ""
	reconnect_overlay_leave_button.visible = false


func _on_game_reconnected() -> void:
	reconnect_overlay.visible = false


func _on_reconnect_exhausted() -> void:
	reconnect_status_label.text = "재접속에 실패했습니다."
	reconnect_overlay.visible = true
	reconnect_overlay_leave_button.visible = true


## 로컬/온라인 공용 게임 진입 로직("리모컨"이 어느 컨트롤러에 꽂히는지
## 정하는 유일한 지점). 이 아래는 2-3 이전부터 있던 화면 배선 그대로다 -
## Phase 1 연출 코드(VoiceBank/SfxBank/_build_character_area/_build_scoreboard/
## 인사 연출)는 한 줄도 안 바뀐다.
## skip_greeting(2-6 후속) - F5 등으로 이미 진행 중이던 게임에 복귀할 때
## true - 이미 지나간 인사 연출을 다시 틀지 않는다.
func _enter_game(controller, profiles: Array[CharacterProfile], my_index: int = -1, skip_greeting: bool = false) -> void:
	_clear_debug_log()
	_debug_init_log("게임 시작 초기화 시작 (인원 %d명)" % profiles.size())
	_debug_log_special_hand_subscribers()
	_clear_dynamic_nodes()

	game_over_overlay.visible = false
	active_controller = controller
	my_player_index = my_index
	_show_screen(Screen.GAME)
	roll_button.disabled = false
	selected_category = -1
	_reset_portrait_transition_state()

	game_state = controller.game_state
	# 온라인 사본은 절대 debug_hotkeys에 물리지 않는다 - read_only 가드
	# 덕에 물려도 조용히 틀리진 않지만, 애초에 서버를 거치지 않고 화면
	# 상태를 건드릴 길을 만들지 않는다(2-4에서 사용자가 명시).
	debug_hotkeys.game_state = (game_state if my_index == -1 else null)
	_debug_init_log("캐릭터 배정 완료")

	player_character_assignments = profiles
	VoiceBank.configure(player_character_assignments)
	_debug_init_log("보이스뱅크 설정 완료")

	_build_character_area()
	_debug_init_log("초상화 영역 생성 완료")

	_build_scoreboard()
	_debug_init_log("점수판 생성 완료")

	game_state.state_changed.connect(_on_state_changed)
	_debug_init_log("시그널 연결 완료")

	# 로컬은 여기서 첫 턴을 직접 연다. 온라인은 서버가 이미 game_started
	# 직후 game_state.start_turn()을 불러 첫 스냅샷을 보내는 중이므로
	# 여기서 또 부르면 안 된다(read_only라 애초에 막히기도 한다).
	if my_index == -1:
		game_state.start_turn()
	_debug_init_log("첫 턴 시작 완료 - 초기화 끝")

	if skip_greeting:
		# 인사 연출을 아예 안 켜므로, 연출이 "정상 종료"됐을 때 하는 뒷정리
		# (입력 차단 해제, 지금 턴 플레이어로 초상 맞추기)만 그대로 재사용한다.
		_on_greeting_sequence_finished()
		_debug_init_log("게임 복귀 - 인사 연출 건너뜀")
	else:
		_start_greeting_sequence()
		_debug_init_log("게임 시작 인사 연출 시작")


func _clear_dynamic_nodes() -> void:
	for child in scoreboard_row.get_children():
		scoreboard_row.remove_child(child)
		child.queue_free()

	for child in small_tags_row.get_children():
		small_tags_row.remove_child(child)
		child.queue_free()

	score_labels.clear()
	preview_buttons.clear()
	upper_bonus_labels.clear()
	bonus_labels.clear()
	total_labels.clear()
	player_columns.clear()
	small_tag_rows.clear()
	connection_status_labels.clear()
	player_character_assignments.clear()
	_departed_player_indices.clear()
	leave_to_lobby_button.visible = false
	turn_countdown_label.visible = false
	quick_progress_button.visible = false
	_quick_progress_running = false


## 내 턴인지 확인한다(로컬은 항상 true - 전원이 한 화면을 같이 쓰므로
## 턴 제한이 없다). 서버도 검사하지만 UI에서도 막는다(2-4에서 사용자가
## 요구한 사항) - 남의 턴에 버튼을 눌러도 애초에 반응하지 않는다.
func _is_my_turn() -> bool:
	return my_player_index == -1 or my_player_index == game_state.current_player


func _on_dice_gui_input(event: InputEvent, index: int) -> void:
	if not game_state.has_rolled or not _is_my_turn() or active_controller.is_request_pending():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		active_controller.request_hold(index)


func _on_roll_button_pressed() -> void:
	selected_category = -1
	active_controller.request_roll()


func _on_select_category_pressed(index: int) -> void:
	selected_category = index
	_refresh_scoreboard_ui()
	_refresh_confirm_score_button()


func _on_confirm_score_pressed() -> void:
	if selected_category == -1:
		return
	var category := selected_category
	selected_category = -1
	active_controller.request_score(category)


func _on_portrait_stack_resized() -> void:
	_refit_portrait_rect(portrait_texture_a)
	_refit_portrait_rect(portrait_texture_b)


func _refit_portrait_rect(rect: TextureRect) -> void:
	if rect.texture == null:
		return
	TextureFit.fit(rect, rect.texture, portrait_stack.size, false, 1.0)


func _transition_portrait(profile: CharacterProfile, label_text: String) -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()

	var front_rect := portrait_texture_a if _portrait_front_is_a else portrait_texture_b
	var back_rect := portrait_texture_b if _portrait_front_is_a else portrait_texture_a
	_portrait_front_is_a = not _portrait_front_is_a

	TextureFit.fit(back_rect, CharacterPortrait.resolve_display_texture(profile), portrait_stack.size, false, 1.0)
	back_rect.modulate.a = 0.0

	_portrait_tween = create_tween()
	_portrait_tween.set_parallel(true)
	_portrait_tween.set_trans(Tween.TRANS_SINE)
	_portrait_tween.set_ease(Tween.EASE_IN_OUT)
	_portrait_tween.tween_property(front_rect, "modulate:a", 0.0, PORTRAIT_FADE_DURATION)
	_portrait_tween.tween_property(back_rect, "modulate:a", 1.0, PORTRAIT_FADE_DURATION)

	_label_tween = create_tween()
	_label_tween.set_trans(Tween.TRANS_SINE)
	_label_tween.set_ease(Tween.EASE_IN_OUT)
	_label_tween.tween_property(big_name_label, "modulate:a", 0.0, PORTRAIT_FADE_DURATION / 2.0)
	_label_tween.tween_callback(func() -> void: big_name_label.text = label_text)
	_label_tween.tween_property(big_name_label, "modulate:a", 1.0, PORTRAIT_FADE_DURATION / 2.0)


func _player_label_text(player_index: int, profile: CharacterProfile) -> String:
	if profile != null:
		return "플레이어 %d - %s" % [player_index + 1, profile.display_name]
	return "플레이어 %d" % (player_index + 1)


## 게임 시작 인사 연출(1-4C)을 시작한다 - 입력을 막고 VoiceBank에 순차 재생을
## 맡긴다. 아무도 인사 보이스가 없으면(기본 캐릭터만 있는 경우 등)
## VoiceBank.play_greeting_sequence()가 그 자리에서 동기적으로 끝까지 돌아
## _on_greeting_sequence_finished()까지 호출하고 돌아오므로, 이 함수가
## 리턴할 때쯤엔 이미 _greeting_active가 다시 false일 수 있다 - 그래서
## 화면에는 차단이 전혀 안 보인다.
func _start_greeting_sequence() -> void:
	_greeting_active = true
	debug_hotkeys.greeting_active = true
	input_blocker.visible = true
	greeting_skip_button.visible = true
	VoiceBank.play_greeting_sequence()


## VoiceBank가 실제로 재생을 시작한 플레이어마다 한 번씩 emit하는 신호에
## 반응해서 큰 슬롯을 그 플레이어로 전환한다("소개" 연출). 매핑이 없어서
## 건너뛴 플레이어는 애초에 이 신호 자체가 안 온다.
func _on_greeting_step_started(player_index: int) -> void:
	if player_index == _current_portrait_player:
		return
	_current_portrait_player = player_index
	var profile: CharacterProfile = player_character_assignments[player_index] if player_index < player_character_assignments.size() else null
	_transition_portrait(profile, _player_label_text(player_index, profile))


## 인사 연출이 끝나면(정상 종료/건너뛰기/전원 매핑 없음 전부 포함) 반드시
## 여기가 불린다 - 입력을 반드시 풀어야 한다(안 풀리면 게임이 멈춘 것처럼
## 보인다). 첫 턴 플레이어(항상 0번)로 화면을 되돌린다.
func _on_greeting_sequence_finished() -> void:
	_greeting_active = false
	debug_hotkeys.greeting_active = false
	input_blocker.visible = false
	greeting_skip_button.visible = false

	var first_turn_player := game_state.current_player if game_state != null else 0
	if first_turn_player != _current_portrait_player:
		_current_portrait_player = first_turn_player
		var profile: CharacterProfile = player_character_assignments[first_turn_player] if first_turn_player < player_character_assignments.size() else null
		_transition_portrait(profile, _player_label_text(first_turn_player, profile))


## [인사 건너뛰기] 버튼을 눌러야만 건너뛰어진다 - 화면 클릭이나 키보드로는
## 안 된다(연출을 보고 싶은 사람이 실수로 건너뛰지 않도록).
func _on_greeting_skip_button_pressed() -> void:
	VoiceBank.request_skip_greeting()


func _on_special_hand_rolled(_player_index: int, category: int, _points: int) -> void:
	# 어떤 조건 검사보다도 먼저 찍는다 - 이 줄이 아예 안 찍히면 "핸들러 자체가
	# 안 불림"이고, 이 줄은 찍히는데 그 다음이 안 되면 "핸들러 안에서 멈춤"이다.
	_debug_init_log("_on_special_hand_rolled 호출됨 (category=%s)" % category)
	if debug_hotkeys.is_auto_playing:
		return  # F10 자동 진행 중엔 매번 1.5초씩 멈추면 안 되니 건너뛴다.
	_play_special_hand_effect(category)


# 캐릭터 보이스와 효과음은 이 함수가 아니라 GameEvents.special_hand_rolled를 각자
# 직접 구독해서 따로 반응한다(VoiceBank/SfxBank). 여기서는 화면 연출만 맡는다.
func _play_special_hand_effect(category: int) -> void:
	_debug_init_log("특수족보 연출 시작: %s (label.visible=%s, rect=%s, global_rect=%s)" % [
		GameState.CATEGORY_NAMES[category], special_hand_label.visible,
		special_hand_label.size, special_hand_label.get_global_rect()
	])

	if _special_hand_tween != null and _special_hand_tween.is_valid():
		_special_hand_tween.kill()

	special_hand_label.text = GameState.CATEGORY_NAMES[category]
	special_hand_label.modulate.a = 0.0
	special_hand_label.visible = true
	input_blocker.visible = true

	var hold_duration := SPECIAL_HAND_DISPLAY_DURATION - 2.0 * SPECIAL_HAND_FADE_DURATION

	_special_hand_tween = create_tween()
	_special_hand_tween.tween_property(special_hand_label, "modulate:a", 1.0, SPECIAL_HAND_FADE_DURATION)
	_special_hand_tween.tween_callback(func() -> void: _debug_init_log("특수족보 연출 - 페이드인 끝, modulate.a=%s" % special_hand_label.modulate.a))
	_special_hand_tween.tween_interval(hold_duration)
	_special_hand_tween.tween_property(special_hand_label, "modulate:a", 0.0, SPECIAL_HAND_FADE_DURATION)
	_special_hand_tween.tween_callback(func() -> void:
		special_hand_label.visible = false
		input_blocker.visible = false
		_debug_init_log("특수족보 연출 종료"))


func _build_character_area() -> void:
	for p in game_state.player_count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var profile: CharacterProfile = player_character_assignments[p] if p < player_character_assignments.size() else null
		var shown_name := profile.display_name if profile != null else "플레이어 %d" % (p + 1)

		var thumb_clip := Control.new()
		thumb_clip.custom_minimum_size = Vector2(SMALL_TAG_SIZE, SMALL_TAG_SIZE)
		thumb_clip.clip_contents = true
		row.add_child(thumb_clip)

		var thumb := TextureRect.new()
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb_clip.add_child(thumb)
		# 전용 thumbnail_file이 있으면 가운데 기준으로, portrait_file/실루엣 폴백이면
		# 세로로 긴 일러스트일 수 있으니 얼굴이 있을 위쪽 기준으로 잘라낸다.
		var thumb_anchor := 0.5 if CharacterPortrait.thumbnail_should_center_crop(profile) else 0.0
		TextureFit.fit(thumb, CharacterPortrait.resolve_thumbnail_texture(profile), Vector2(SMALL_TAG_SIZE, SMALL_TAG_SIZE), true, thumb_anchor)

		var name_label := Label.new()
		name_label.text = "P%d %s" % [p + 1, shown_name]
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)

		small_tags_row.add_child(row)
		small_tag_rows.append(row)


func _make_row_label(text: String, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_stylebox_override("normal", row_divider_style)
	return label


func _build_scoreboard() -> void:
	var label_column := VBoxContainer.new()
	label_column.custom_minimum_size = Vector2(140, 0)
	label_column.add_theme_constant_override("separation", 0)
	scoreboard_row.add_child(label_column)

	label_column.add_child(_make_row_label(""))

	for i in GameState.CATEGORY_NAMES.size():
		label_column.add_child(_make_row_label(GameState.CATEGORY_NAMES[i]))

	label_column.add_child(_make_row_label("상단 합계"))
	label_column.add_child(_make_row_label("보너스"))
	label_column.add_child(_make_row_label("총점"))

	for p in game_state.player_count:
		var column := PanelContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scoreboard_row.add_child(column)
		player_columns.append(column)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 0)
		column.add_child(vbox)

		vbox.add_child(_make_row_label("플레이어 %d" % (p + 1), HORIZONTAL_ALIGNMENT_CENTER))

		# 2-6(§6 "화면 표시") - 연결 상태 문구. 로컬 게임/평소 온라인
		# 게임에서는 관련 신호가 안 오므로 계속 숨겨진 채로 남는다.
		var connection_label := Label.new()
		connection_label.visible = false
		connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		connection_label.add_theme_font_size_override("font_size", 11)
		connection_label.add_theme_color_override("font_color", Color(1, 0.7, 0.4, 1))
		vbox.add_child(connection_label)
		connection_status_labels.append(connection_label)

		var player_score_labels: Array[Label] = []
		var player_preview_buttons: Array[Button] = []

		for i in GameState.CATEGORY_NAMES.size():
			var label := Label.new()
			label.custom_minimum_size = Vector2(0, ROW_HEIGHT)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_stylebox_override("normal", row_divider_style)
			vbox.add_child(label)
			player_score_labels.append(label)

			var preview_button := Button.new()
			preview_button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
			preview_button.add_theme_font_size_override("font_size", 13)
			preview_button.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
			preview_button.add_theme_stylebox_override("normal", preview_button_style)
			preview_button.add_theme_stylebox_override("hover", preview_button_style)
			preview_button.add_theme_stylebox_override("pressed", preview_button_style)
			preview_button.add_theme_stylebox_override("focus", preview_button_style)
			preview_button.visible = false
			preview_button.pressed.connect(_on_select_category_pressed.bind(i))
			vbox.add_child(preview_button)
			player_preview_buttons.append(preview_button)

		score_labels.append(player_score_labels)
		preview_buttons.append(player_preview_buttons)

		var upper_label := _make_row_label("", HORIZONTAL_ALIGNMENT_CENTER)
		vbox.add_child(upper_label)
		upper_bonus_labels.append(upper_label)

		var bonus_label := _make_row_label("", HORIZONTAL_ALIGNMENT_CENTER)
		vbox.add_child(bonus_label)
		bonus_labels.append(bonus_label)

		var total_label := _make_row_label("", HORIZONTAL_ALIGNMENT_CENTER)
		vbox.add_child(total_label)
		total_labels.append(total_label)


func _on_state_changed() -> void:
	_refresh_dice_ui()
	_refresh_reroll_ui()
	_refresh_turn_ui()
	_refresh_character_area()
	_refresh_scoreboard_ui()
	_refresh_confirm_score_button()
	_refresh_quick_progress_button()
	_refresh_game_over_ui()


func _refresh_dice_ui() -> void:
	for i in dice_labels.size():
		dice_labels[i].text = str(game_state.dice_results[i]) if game_state.has_rolled else "?"
		if game_state.dice_locked[i]:
			dice_labels[i].add_theme_stylebox_override("normal", locked_style)
		else:
			dice_labels[i].remove_theme_stylebox_override("normal")


func _refresh_reroll_ui() -> void:
	reroll_label.text = "남은 굴리기: %d" % game_state.rolls_left
	roll_button.disabled = game_state.rolls_left <= 0 or not _is_my_turn() or active_controller.is_request_pending()


func _refresh_turn_ui() -> void:
	turn_label.text = "현재 턴: 플레이어 %d" % (game_state.current_player + 1)


func _refresh_character_area() -> void:
	var current := game_state.current_player

	if current != _current_portrait_player:
		_current_portrait_player = current
		var profile: CharacterProfile = player_character_assignments[current] if current < player_character_assignments.size() else null
		_transition_portrait(profile, _player_label_text(current, profile))

	for p in small_tag_rows.size():
		small_tag_rows[p].visible = (p != current)


func _refresh_scoreboard_ui() -> void:
	var current := game_state.current_player

	for p in game_state.player_count:
		player_columns[p].add_theme_stylebox_override(
			"panel", column_highlight_style if p == current else column_normal_style
		)

		for i in GameState.CATEGORY_NAMES.size():
			var label: Label = score_labels[p][i]
			var button: Button = preview_buttons[p][i]

			if game_state.is_category_confirmed(p, i):
				label.text = str(game_state.get_confirmed_score(p, i))
				label.add_theme_font_size_override("font_size", 16)
				label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
				label.add_theme_font_override("font", bold_font)
				label.visible = true
				button.visible = false
			elif p == current and game_state.has_rolled:
				button.text = str(game_state.preview_score(i))
				label.visible = false
				button.visible = true
				var cell_style := selected_cell_style if i == selected_category else preview_button_style
				button.add_theme_stylebox_override("normal", cell_style)
				button.add_theme_stylebox_override("hover", cell_style)
				button.add_theme_stylebox_override("pressed", cell_style)
				button.add_theme_stylebox_override("focus", cell_style)
			else:
				label.text = ""
				label.visible = true
				button.visible = false

		var upper_total := game_state.get_upper_section_total(p)
		var achieved := game_state.has_upper_bonus(p)
		if achieved:
			upper_bonus_labels[p].text = "%d/%d" % [upper_total, GameState.UPPER_BONUS_THRESHOLD]
		else:
			upper_bonus_labels[p].text = "%d/%d(%d남음)" % [
				upper_total, GameState.UPPER_BONUS_THRESHOLD, game_state.get_upper_bonus_remaining(p)
			]

		bonus_labels[p].text = "+%d" % GameState.UPPER_BONUS_POINTS
		if achieved:
			bonus_labels[p].add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			bonus_labels[p].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		total_labels[p].text = str(game_state.get_player_total(p))


func _refresh_confirm_score_button() -> void:
	if selected_category == -1 or game_state.game_over or not game_state.has_rolled or not _is_my_turn():
		confirm_score_button.disabled = true
		confirm_score_button.text = "점수 확정"
		return

	var category_name := GameState.CATEGORY_NAMES[selected_category]
	var points := game_state.preview_score(selected_category)
	confirm_score_button.disabled = active_controller.is_request_pending()
	confirm_score_button.text = "%s %d점으로 확정" % [category_name, points]


## DEBUG_MODE + 온라인일 때만 보인다(2-4에서 정한 "온라인엔 디버그 UI를
## 숨긴다"는 원칙의 명시적 예외 - 사용자 요청). 로컬 게임에는 이미 Ctrl+Shift+A
## 같은 디버그 자동 진행이 있어서 이 버튼이 필요 없다.
func _refresh_quick_progress_button() -> void:
	var should_show := BuildInfo.DEBUG_MODE and my_player_index != -1 and not game_state.game_over
	quick_progress_button.visible = should_show
	if should_show:
		quick_progress_button.disabled = _quick_progress_running or not _is_my_turn() or active_controller.is_request_pending()


## 내 턴을 한 번에 끝낸다: 안 굴렸으면 굴리고, 빈 칸 중 아무거나(가장 낮은
## 인덱스) 하나 확정한다. 딱 한 턴만 처리하고 멈춘다 - 상대 턴까지 자동으로
## 넘기면 재대전/연결 끊김 시나리오를 눈으로 확인하려던 목적을 오히려
## 가리게 된다. 새 네트워크 메시지는 안 만들고 기존 request_roll/
## request_score를 그대로 보낸다 - 서버 입장에서는 사람이 빠르게 클릭한
## 것과 구별되지 않고, 권한 검사(내 턴인지 등)도 그대로 통과해야 한다.
func _on_quick_progress_button_pressed() -> void:
	if _quick_progress_running or active_controller == null:
		return
	if not _is_my_turn() or active_controller.is_request_pending():
		return

	_quick_progress_running = true
	_refresh_quick_progress_button()

	if not game_state.has_rolled:
		active_controller.request_roll()
		while active_controller.is_request_pending():
			await get_tree().process_frame

	if _is_my_turn() and not game_state.game_over and game_state.has_rolled:
		var category := _find_open_category_for_quick_progress()
		if category != -1:
			active_controller.request_score(category)
			while active_controller.is_request_pending():
				await get_tree().process_frame

	_quick_progress_running = false
	_refresh_quick_progress_button()


func _find_open_category_for_quick_progress() -> int:
	for i in GameState.CATEGORY_NAMES.size():
		if not game_state.is_category_confirmed(my_player_index, i):
			return i
	return -1


func _refresh_game_over_ui() -> void:
	if not game_state.game_over:
		return

	roll_button.disabled = true
	confirm_score_button.disabled = true
	for player_buttons in preview_buttons:
		for button in player_buttons:
			button.visible = false

	var winners := game_state.get_winners()
	var result_text: String
	if winners.size() == 1:
		result_text = "플레이어 %d 승리" % (winners[0] + 1)
	elif winners.size() == game_state.player_count:
		result_text = "무승부"
	else:
		var names: Array[String] = []
		for w in winners:
			names.append("플레이어 %d" % (w + 1))
		result_text = "공동 우승: %s" % ", ".join(names)

	game_over_label.text = "게임 종료!\n%s\n%s" % [result_text, _build_score_summary_text()]
	game_over_overlay.visible = true

	# 로컬은 "다시 하기"(바로 새 판), 온라인은 2-6B의 "한 판 더"(같은
	# 방에서 재대전 - 전원이 눌러야 시작됨)를 쓴다. "타이틀로"/"나가기"는
	# 항상 둘 다에서 보인다.
	restart_button.visible = (my_player_index == -1)
	rematch_button.visible = (my_player_index != -1)


func _build_score_summary_text() -> String:
	# 플레이어 1,2 / (줄바꿈) / 3,4 처럼 두 명씩 묶어서 어색한 위치에서
	# autowrap이 끊기지 않고 항상 깔끔한 지점에서 줄이 바뀌게 한다.
	var entries: Array[String] = []
	for p in game_state.player_count:
		entries.append("플레이어 %d: %d점" % [p + 1, game_state.get_player_total(p)])

	var lines: Array[String] = []
	var pair: Array[String] = []
	for entry in entries:
		pair.append(entry)
		if pair.size() == 2:
			lines.append(" / ".join(pair))
			pair.clear()
	if not pair.is_empty():
		lines.append(" / ".join(pair))

	return "\n".join(lines)
