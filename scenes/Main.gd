extends Node2D

var game_state: GameState

var locked_style := StyleBoxFlat.new()

var score_labels: Array[Label] = []
var confirm_buttons: Array[Button] = []
var upper_bonus_label: Label
var bonus_label: Label

@onready var dice_labels: Array[Label] = [$Dice1, $Dice2, $Dice3, $Dice4, $Dice5]
@onready var roll_button: Button = $RollButton
@onready var new_turn_button: Button = $NewTurnButton
@onready var reroll_label: Label = $RerollLabel
@onready var turn_label: Label = $TurnLabel
@onready var score_list: VBoxContainer = $ScoreboardScroll/ScoreList
@onready var total_score_label: Label = $TotalScoreLabel
@onready var game_over_label: Label = $GameOverLabel


func _ready() -> void:
	locked_style.bg_color = Color(0.2, 0.6, 0.2, 0.5)
	locked_style.border_color = Color(0.1, 0.9, 0.1)
	locked_style.border_width_left = 3
	locked_style.border_width_top = 3
	locked_style.border_width_right = 3
	locked_style.border_width_bottom = 3

	roll_button.pressed.connect(_on_roll_button_pressed)
	new_turn_button.pressed.connect(_on_new_turn_button_pressed)

	for i in dice_labels.size():
		var label := dice_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_dice_gui_input.bind(i))

	game_state = GameState.new()
	_build_scoreboard()
	game_state.state_changed.connect(_on_state_changed)
	game_state.start_turn()


func _on_dice_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		game_state.toggle_lock(index)


func _on_roll_button_pressed() -> void:
	game_state.roll()


func _on_new_turn_button_pressed() -> void:
	game_state.start_turn()


func _build_scoreboard() -> void:
	for i in GameState.CATEGORY_NAMES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var name_label := Label.new()
		name_label.text = GameState.CATEGORY_NAMES[i]
		name_label.custom_minimum_size = Vector2(200, 0)
		row.add_child(name_label)

		var score_label := Label.new()
		score_label.text = "0"
		score_label.custom_minimum_size = Vector2(60, 0)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(score_label)
		score_labels.append(score_label)

		var confirm_button := Button.new()
		confirm_button.text = "이 항목으로 확정"
		confirm_button.pressed.connect(_on_confirm_pressed.bind(i))
		row.add_child(confirm_button)
		confirm_buttons.append(confirm_button)

		score_list.add_child(row)

	var upper_bonus_row := HBoxContainer.new()
	upper_bonus_label = Label.new()
	upper_bonus_label.custom_minimum_size = Vector2(660, 0)
	upper_bonus_row.add_child(upper_bonus_label)
	score_list.add_child(upper_bonus_row)

	var bonus_row := HBoxContainer.new()
	bonus_label = Label.new()
	bonus_label.custom_minimum_size = Vector2(660, 0)
	bonus_row.add_child(bonus_label)
	score_list.add_child(bonus_row)


func _on_confirm_pressed(index: int) -> void:
	game_state.confirm_category(index)


func _on_state_changed() -> void:
	_refresh_dice_ui()
	_refresh_reroll_ui()
	_refresh_turn_ui()
	_refresh_scoreboard_ui()
	_refresh_bonus_ui()
	_refresh_total_ui()
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


func _refresh_scoreboard_ui() -> void:
	var player := game_state.current_player
	for i in GameState.CATEGORY_NAMES.size():
		if game_state.is_category_confirmed(player, i):
			score_labels[i].text = str(game_state.get_confirmed_score(player, i))
			confirm_buttons[i].disabled = true
		else:
			score_labels[i].text = str(game_state.preview_score(i))
			confirm_buttons[i].disabled = false


func _refresh_bonus_ui() -> void:
	var player := game_state.current_player
	var upper_total := game_state.get_upper_section_total(player)
	var threshold := GameState.UPPER_BONUS_THRESHOLD
	var achieved := game_state.has_upper_bonus(player)

	if achieved:
		upper_bonus_label.text = "상단 합계 (현재 %d / %d) — 보너스 달성!" % [upper_total, threshold]
	else:
		var remaining := game_state.get_upper_bonus_remaining(player)
		upper_bonus_label.text = "상단 합계 (현재 %d / %d, %d점 남음)" % [upper_total, threshold, remaining]

	bonus_label.text = "보너스 +%d" % GameState.UPPER_BONUS_POINTS
	if achieved:
		bonus_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		bonus_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))


func _refresh_total_ui() -> void:
	var player := game_state.current_player
	total_score_label.text = "플레이어 %d 합계: %d" % [player + 1, game_state.get_player_total(player)]


func _refresh_game_over_ui() -> void:
	if not game_state.game_over:
		return

	roll_button.disabled = true
	new_turn_button.disabled = true
	for button in confirm_buttons:
		button.disabled = true

	var total_p1 := game_state.get_player_total(0)
	var total_p2 := game_state.get_player_total(1)
	var winner := game_state.get_winner()

	var result_text: String
	if winner == 0:
		result_text = "플레이어 1 승리"
	elif winner == 1:
		result_text = "플레이어 2 승리"
	else:
		result_text = "무승부"

	game_over_label.text = "게임 종료! %s\n플레이어 1: %d점 / 플레이어 2: %d점" % [result_text, total_p1, total_p2]
	game_over_label.visible = true
