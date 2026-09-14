extends Control

const ROW_HEIGHT := 26.0

var game_state: GameState

var locked_style := StyleBoxFlat.new()
var column_normal_style := StyleBoxFlat.new()
var column_highlight_style := StyleBoxFlat.new()
var row_divider_style := StyleBoxFlat.new()
var preview_button_style := StyleBoxFlat.new()
var selected_cell_style := StyleBoxFlat.new()
var game_over_panel_style := StyleBoxFlat.new()
var bold_font := FontVariation.new()

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

@onready var start_screen: Control = $StartScreen
@onready var game_screen: Control = $GameScreen
@onready var players_2_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players2Button
@onready var players_3_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players3Button
@onready var players_4_button: Button = $StartScreen/CenterContainer/VBox/PlayerCountRow/Players4Button

@onready var turn_label: Label = $GameScreen/Margin/MainHBox/RightColumn/TurnLabel
@onready var big_portrait_area: PanelContainer = $GameScreen/Margin/MainHBox/LeftColumn/BigPortraitArea
@onready var big_name_label: Label = $GameScreen/Margin/MainHBox/LeftColumn/BigNameLabel
@onready var small_tags_row: HBoxContainer = $GameScreen/Margin/MainHBox/LeftColumn/SmallTagsRow

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

	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.6

	big_portrait_area.add_theme_stylebox_override("panel", column_normal_style)

	players_2_button.pressed.connect(_on_start_pressed.bind(2))
	players_3_button.pressed.connect(_on_start_pressed.bind(3))
	players_4_button.pressed.connect(_on_start_pressed.bind(4))

	roll_button.pressed.connect(_on_roll_button_pressed)
	confirm_score_button.pressed.connect(_on_confirm_score_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	to_title_button.pressed.connect(_on_to_title_pressed)
	quit_confirm_dialog.confirmed.connect(_return_to_title)

	for i in dice_labels.size():
		var label := dice_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_dice_gui_input.bind(i))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if game_screen.visible and not quit_confirm_dialog.visible:
			quit_confirm_dialog.popup_centered()
			get_viewport().set_input_as_handled()


func _on_start_pressed(player_count: int) -> void:
	_start_new_game(player_count)


func _on_restart_pressed() -> void:
	_start_new_game(game_state.player_count)


func _on_to_title_pressed() -> void:
	_return_to_title()


func _return_to_title() -> void:
	_clear_dynamic_nodes()
	game_state = null
	debug_hotkeys.game_state = null

	game_screen.visible = false
	game_over_overlay.visible = false
	start_screen.visible = true


func _start_new_game(player_count: int) -> void:
	_clear_dynamic_nodes()

	start_screen.visible = false
	game_over_overlay.visible = false
	game_screen.visible = true
	roll_button.disabled = false
	selected_category = -1

	game_state = GameState.new(player_count)
	debug_hotkeys.game_state = game_state

	_build_character_area()
	_build_scoreboard()

	game_state.state_changed.connect(_on_state_changed)
	game_state.start_turn()


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


func _on_dice_gui_input(event: InputEvent, index: int) -> void:
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


func _build_character_area() -> void:
	for p in game_state.player_count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var tag := ColorRect.new()
		tag.custom_minimum_size = Vector2(24, 24)
		tag.color = Color(0.4, 0.4, 0.45, 1)
		row.add_child(tag)

		var name_label := Label.new()
		name_label.text = "플레이어 %d" % (p + 1)
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
		dice_labels[i].text = str(game_state.dice_results[i])
		if game_state.dice_locked[i]:
			dice_labels[i].add_theme_stylebox_override("normal", locked_style)
		else:
			dice_labels[i].remove_theme_stylebox_override("normal")


func _refresh_reroll_ui() -> void:
	reroll_label.text = "남은 리롤 횟수: %d" % game_state.rerolls_left
	roll_button.disabled = game_state.rerolls_left <= 0


func _refresh_turn_ui() -> void:
	turn_label.text = "현재 턴: 플레이어 %d" % (game_state.current_player + 1)


func _refresh_character_area() -> void:
	big_name_label.text = "플레이어 %d" % (game_state.current_player + 1)
	for p in small_tag_rows.size():
		small_tag_rows[p].visible = (p != game_state.current_player)


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
			elif p == current:
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
	if selected_category == -1 or game_state.game_over:
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
