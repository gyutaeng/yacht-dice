extends Node2D

const MAX_REROLLS := 2

var dice_results: Array[int] = [1, 1, 1, 1, 1]
var dice_locked: Array[bool] = [false, false, false, false, false]
var rerolls_left: int = MAX_REROLLS

var locked_style := StyleBoxFlat.new()

@onready var dice_labels: Array[Label] = [$Dice1, $Dice2, $Dice3, $Dice4, $Dice5]
@onready var roll_button: Button = $RollButton
@onready var new_turn_button: Button = $NewTurnButton
@onready var reroll_label: Label = $RerollLabel


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

	_update_reroll_label()


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

	for i in dice_labels.size():
		if dice_locked[i]:
			continue
		var value := randi_range(1, 6)
		dice_results[i] = value
		dice_labels[i].text = str(value)

	rerolls_left -= 1
	_update_reroll_label()
	if rerolls_left <= 0:
		roll_button.disabled = true


func _on_new_turn_button_pressed() -> void:
	rerolls_left = MAX_REROLLS
	roll_button.disabled = false

	for i in dice_labels.size():
		dice_locked[i] = false
		_update_dice_visual(i)

	_update_reroll_label()


func _update_reroll_label() -> void:
	reroll_label.text = "남은 리롤 횟수: %d" % rerolls_left
