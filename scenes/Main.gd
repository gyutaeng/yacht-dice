extends Control

# 화면 전환을 한 곳에서만 관리한다 - 이 셋 중 "지금 보여야 할 하나"만
# visible=true가 되고 나머지는 전부 visible=false가 된다(_show_screen()).
# 예전엔 버튼 핸들러마다 각자 visible을 켜고 꺼서, 하나를 끄는 걸 빠뜨리면
# 안 보여야 할 화면이 뒤에 투명하게 남아 클릭을 가로채는 버그가 있었다.
# GameOverOverlay는 GAME 위에 뜨는 모달이라 이 enum에 안 넣는다(별도 관리).
enum Screen { START, CHARACTER_SELECT, GAME }

const ROW_HEIGHT := 26.0
const SMALL_TAG_SIZE := 56.0
const PORTRAIT_FADE_DURATION := 0.3
const BOLD_FONT_PATH := "res://assets/fonts/Pretendard-Bold.otf"

# 효과음은 SfxBank가 special_hand_rolled를 직접 구독해서 재생한다(여기선 화면 연출만).
const SPECIAL_HAND_DISPLAY_DURATION := 1.5
const SPECIAL_HAND_FADE_DURATION := 0.15

var game_state: GameState

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

# score_labels[player][category] -> Label(확정/빈칸), preview_buttons[player][category] -> Button(미확정 미리보기, 누르면 확정)
var score_labels: Array = []
var preview_buttons: Array = []
var upper_bonus_labels: Array[Label] = []
var bonus_labels: Array[Label] = []
var total_labels: Array[Label] = []
var player_columns: Array[PanelContainer] = []
var small_tag_rows: Array[Control] = []

# player_character_assignments[player] -> CharacterProfile.
var player_character_assignments: Array[CharacterProfile] = []

# 큰 슬롯 크로스페이드 상태.
var _portrait_front_is_a: bool = true
var _current_portrait_player: int = -1
var _portrait_tween: Tween
var _label_tween: Tween
var _special_hand_tween: Tween

@onready var start_screen: Control = $StartScreen
@onready var game_screen: Control = $GameScreen
@onready var players_2_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players2Button
@onready var players_3_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players3Button
@onready var players_4_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players4Button
@onready var manage_characters_button: Button = $StartScreen/CenterContainer/VBox/ManageCharactersButton

@onready var character_select_screen = $CharacterSelectScreen

@onready var turn_label: Label = $GameScreen/Margin/MainHBox/RightColumn/TurnLabel
@onready var big_portrait_area: PanelContainer = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea
@onready var portrait_stack: Control = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack
@onready var portrait_texture_a: TextureRect = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack/PortraitTextureA
@onready var portrait_texture_b: TextureRect = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/PortraitStack/PortraitTextureB
@onready var big_name_label: Label = $GameScreen/Margin/MainHBox/LeftColumn/BigNameLabel
@onready var small_tags_row: HBoxContainer = $GameScreen/Margin/MainHBox/LeftColumn/SmallTagsRow
@onready var special_hand_label: Label = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea/SpecialHandLabel
@onready var input_blocker: Control = $GameScreen/InputBlocker

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

@onready var scoreboard_row: HBoxContainer = $GameScreen/Margin/MainHBox/RightColumn/ScoreboardRow

@onready var game_over_overlay: Control = $GameOverOverlay
@onready var game_over_panel: PanelContainer = $GameOverOverlay/CenterContainer/Panel
@onready var game_over_label: Label = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverLabel
@onready var restart_button: Button = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverButtonsRow/RestartButton
@onready var to_title_button: Button = $GameOverOverlay/CenterContainer/Panel/VBox/GameOverButtonsRow/ToTitleButton

@onready var quit_confirm_dialog: ConfirmationDialog = $QuitConfirmDialog

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

	character_select_screen.selection_confirmed.connect(_on_character_selection_confirmed)
	character_select_screen.back_requested.connect(_on_character_select_back)

	roll_button.pressed.connect(_on_roll_button_pressed)
	confirm_score_button.pressed.connect(_on_confirm_score_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	to_title_button.pressed.connect(_on_to_title_pressed)
	quit_confirm_dialog.confirmed.connect(_return_to_title)

	# GameEvents는 앱이 사는 동안 계속 살아있는 autoload라서, game_state처럼
	# 게임을 새로 시작할 때마다가 아니라 여기서 딱 한 번만 연결한다.
	GameEvents.special_hand_rolled.connect(_on_special_hand_rolled)

	for i in dice_labels.size():
		var label := dice_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_dice_gui_input.bind(i))

	debug_init_log.visible = BuildInfo.DEBUG_MODE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if game_screen.visible and not quit_confirm_dialog.visible:
			quit_confirm_dialog.popup_centered()
			get_viewport().set_input_as_handled()


## BuildInfo.DEBUG_MODE가 false면 아무것도 안 한다(콘솔 print도 포함) - 웹에서는
## 브라우저 콘솔의 print() 출력을 못 믿을 수 있어서(1-5 참고), 초기화 단계마다
## 화면 구석에도 한 줄씩 남긴다. 어느 줄까지 찍히고 멈췄는지가 "어디서 끊겼는지"다.
## debug_hotkeys.gd의 버튼/단축키와 마찬가지로 DEBUG_MODE 하나로 켜고 끈다.
func _debug_init_log(message: String) -> void:
	if not BuildInfo.DEBUG_MODE:
		return
	print("[초기화] %s" % message)
	if debug_init_log != null:
		debug_init_log.append_text("[%s] %s\n" % [Time.get_time_string_from_system(), message])


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


func _on_start_pressed(player_count: int) -> void:
	_show_screen(Screen.CHARACTER_SELECT)
	character_select_screen.configure(player_count)


func _on_character_select_back() -> void:
	_show_screen(Screen.START)


func _on_character_selection_confirmed(profiles: Array[CharacterProfile]) -> void:
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


func _start_new_game(profiles: Array[CharacterProfile]) -> void:
	_debug_init_log("게임 시작 초기화 시작 (인원 %d명)" % profiles.size())
	_debug_log_special_hand_subscribers()
	_clear_dynamic_nodes()

	game_over_overlay.visible = false
	_show_screen(Screen.GAME)
	roll_button.disabled = false
	selected_category = -1
	_reset_portrait_transition_state()

	var player_count := profiles.size()
	game_state = GameState.new(player_count)
	debug_hotkeys.game_state = game_state
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

	game_state.start_turn()
	_debug_init_log("첫 턴 시작 완료 - 초기화 끝")


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
	player_character_assignments.clear()


func _on_dice_gui_input(event: InputEvent, index: int) -> void:
	if not game_state.has_rolled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		game_state.toggle_lock(index)


func _on_roll_button_pressed() -> void:
	selected_category = -1
	game_state.roll()


func _on_select_category_pressed(index: int) -> void:
	selected_category = index
	_refresh_scoreboard_ui()
	_refresh_confirm_score_button()


func _on_confirm_score_pressed() -> void:
	if selected_category == -1:
		return
	var category := selected_category
	selected_category = -1
	game_state.confirm_category(category)


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
	roll_button.disabled = game_state.rolls_left <= 0


func _refresh_turn_ui() -> void:
	turn_label.text = "현재 턴: 플레이어 %d" % (game_state.current_player + 1)


func _refresh_character_area() -> void:
	var current := game_state.current_player

	if current != _current_portrait_player:
		_current_portrait_player = current
		var profile: CharacterProfile = player_character_assignments[current] if current < player_character_assignments.size() else null
		var label_text := (
			"플레이어 %d - %s" % [current + 1, profile.display_name] if profile != null
			else "플레이어 %d" % (current + 1)
		)
		_transition_portrait(profile, label_text)

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
	if selected_category == -1 or game_state.game_over or not game_state.has_rolled:
		confirm_score_button.disabled = true
		confirm_score_button.text = "점수 확정"
		return

	var category_name := GameState.CATEGORY_NAMES[selected_category]
	var points := game_state.preview_score(selected_category)
	confirm_score_button.disabled = false
	confirm_score_button.text = "%s %d점으로 확정" % [category_name, points]


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
