extends Node2D

const MAX_REROLLS := 2
const NUM_PLAYERS := 2

const CATEGORY_NAMES: Array[String] = [
	"Aces",
	"Deuces",
	"Threes",
	"Fours",
	"Fives",
	"Sixes",
	"Choice",
	"Four of a Kind",
	"Full House",
	"Small Straight",
	"Large Straight",
	"Yacht",
]

var dice_results: Array[int] = [1, 1, 1, 1, 1]
var dice_locked: Array[bool] = [false, false, false, false, false]
var rerolls_left: int = MAX_REROLLS

var locked_style := StyleBoxFlat.new()

var score_calculators: Array[Callable] = []
var score_labels: Array[Label] = []
var confirm_buttons: Array[Button] = []

# player_score_confirmed[player][category] / player_confirmed_scores[player][category]
var player_score_confirmed: Array = []
var player_confirmed_scores: Array = []
var current_player: int = 0
var game_over: bool = false

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

	score_calculators = [
		calc_aces,
		calc_deuces,
		calc_threes,
		calc_fours,
		calc_fives,
		calc_sixes,
		calc_choice,
		calc_four_of_a_kind,
		calc_full_house,
		calc_small_straight,
		calc_large_straight,
		calc_yacht,
	]

	for p in NUM_PLAYERS:
		player_score_confirmed.append(_make_bool_array(CATEGORY_NAMES.size(), false))
		player_confirmed_scores.append(_make_int_array(CATEGORY_NAMES.size(), 0))

	_build_scoreboard()
	_roll_dice()
	_update_reroll_label()
	_update_score_previews()
	_update_total_score()
	turn_label.text = "현재 턴: 플레이어 %d" % (current_player + 1)


func _on_dice_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dice_locked[index] = not dice_locked[index]
		_update_dice_visual(index)


func _update_dice_visual(index: int) -> void:
	var label := dice_labels[index]
	if dice_locked[index]:
		label.add_theme_stylebox_override("normal", locked_style)
	else:
		label.remove_theme_stylebox_override("normal")


func _on_roll_button_pressed() -> void:
	if rerolls_left <= 0:
		return

	_roll_dice()

	rerolls_left -= 1
	_update_reroll_label()
	_update_score_previews()
	if rerolls_left <= 0:
		roll_button.disabled = true


func _roll_dice() -> void:
	for i in dice_labels.size():
		if dice_locked[i]:
			continue
		var value := randi_range(1, 6)
		dice_results[i] = value
		dice_labels[i].text = str(value)


func _on_new_turn_button_pressed() -> void:
	_reset_dice_state()


func _reset_dice_state() -> void:
	rerolls_left = MAX_REROLLS
	roll_button.disabled = false

	for i in dice_labels.size():
		dice_locked[i] = false
		_update_dice_visual(i)

	_roll_dice()
	_update_reroll_label()
	_update_score_previews()


func _update_reroll_label() -> void:
	reroll_label.text = "남은 리롤 횟수: %d" % rerolls_left


func _build_scoreboard() -> void:
	for i in CATEGORY_NAMES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var name_label := Label.new()
		name_label.text = CATEGORY_NAMES[i]
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


func _on_confirm_pressed(index: int) -> void:
	if game_over or player_score_confirmed[current_player][index]:
		return

	var value: int = score_calculators[index].call(dice_results)
	player_confirmed_scores[current_player][index] = value
	player_score_confirmed[current_player][index] = true
	score_labels[index].text = str(value)
	confirm_buttons[index].disabled = true

	_update_total_score()

	if _player_completed(0) and _player_completed(1):
		game_over = true
		_show_game_over()
		return

	_switch_to_player(1 - current_player)


func _player_completed(player: int) -> bool:
	for confirmed in player_score_confirmed[player]:
		if not confirmed:
			return false
	return true


func _switch_to_player(player: int) -> void:
	current_player = player
	turn_label.text = "현재 턴: 플레이어 %d" % (player + 1)
	_refresh_scoreboard_ui()
	_reset_dice_state()
	_update_total_score()


func _refresh_scoreboard_ui() -> void:
	for i in CATEGORY_NAMES.size():
		if player_score_confirmed[current_player][i]:
			score_labels[i].text = str(player_confirmed_scores[current_player][i])
			confirm_buttons[i].disabled = true
		else:
			confirm_buttons[i].disabled = false


func _update_total_score() -> void:
	total_score_label.text = "플레이어 %d 합계: %d" % [current_player + 1, _player_total(current_player)]


func _player_total(player: int) -> int:
	var total := 0
	for score in player_confirmed_scores[player]:
		total += score
	return total


func _show_game_over() -> void:
	roll_button.disabled = true
	new_turn_button.disabled = true
	for button in confirm_buttons:
		button.disabled = true

	var total_p1 := _player_total(0)
	var total_p2 := _player_total(1)

	var result_text: String
	if total_p1 > total_p2:
		result_text = "플레이어 1 승리"
	elif total_p2 > total_p1:
		result_text = "플레이어 2 승리"
	else:
		result_text = "무승부"

	game_over_label.text = "게임 종료! %s\n플레이어 1: %d점 / 플레이어 2: %d점" % [result_text, total_p1, total_p2]
	game_over_label.visible = true


func _update_score_previews() -> void:
	for i in CATEGORY_NAMES.size():
		if player_score_confirmed[current_player][i]:
			continue
		var value: int = score_calculators[i].call(dice_results)
		score_labels[i].text = str(value)


func _make_bool_array(size: int, value: bool) -> Array[bool]:
	var arr: Array[bool] = []
	for i in size:
		arr.append(value)
	return arr


func _make_int_array(size: int, value: int) -> Array[int]:
	var arr: Array[int] = []
	for i in size:
		arr.append(value)
	return arr


func calc_aces(dice: Array[int]) -> int:
	return _count_value(dice, 1) * 1


func calc_deuces(dice: Array[int]) -> int:
	return _count_value(dice, 2) * 2


func calc_threes(dice: Array[int]) -> int:
	return _count_value(dice, 3) * 3


func calc_fours(dice: Array[int]) -> int:
	return _count_value(dice, 4) * 4


func calc_fives(dice: Array[int]) -> int:
	return _count_value(dice, 5) * 5


func calc_sixes(dice: Array[int]) -> int:
	return _count_value(dice, 6) * 6


func calc_choice(dice: Array[int]) -> int:
	return _sum(dice)


func calc_four_of_a_kind(dice: Array[int]) -> int:
	var counts := _count_all(dice)
	for value in counts:
		if counts[value] >= 4:
			return _sum(dice)
	return 0


func calc_full_house(dice: Array[int]) -> int:
	var counts := _count_all(dice)
	var counts_sorted := counts.values()
	counts_sorted.sort()
	if counts_sorted == [2, 3]:
		return 25
	return 0


func calc_small_straight(dice: Array[int]) -> int:
	var unique_values := {}
	for d in dice:
		unique_values[d] = true

	var straights := [[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]]
	for straight in straights:
		var has_all := true
		for v in straight:
			if not unique_values.has(v):
				has_all = false
				break
		if has_all:
			return 15
	return 0


func calc_large_straight(dice: Array[int]) -> int:
	var sorted_dice := dice.duplicate()
	sorted_dice.sort()
	if sorted_dice == [1, 2, 3, 4, 5] or sorted_dice == [2, 3, 4, 5, 6]:
		return 30
	return 0


func calc_yacht(dice: Array[int]) -> int:
	for d in dice:
		if d != dice[0]:
			return 0
	return 50


func _count_value(dice: Array[int], value: int) -> int:
	var count := 0
	for d in dice:
		if d == value:
			count += 1
	return count


func _count_all(dice: Array[int]) -> Dictionary:
	var counts := {}
	for d in dice:
		counts[d] = counts.get(d, 0) + 1
	return counts


func _sum(dice: Array[int]) -> int:
	var total := 0
	for d in dice:
		total += d
	return total
