extends Node2D

var dice_results: Array[int] = [1, 1, 1, 1, 1]

@onready var dice_labels: Array[Label] = [$Dice1, $Dice2, $Dice3, $Dice4, $Dice5]
@onready var roll_button: Button = $RollButton


func _ready() -> void:
	roll_button.pressed.connect(_on_roll_button_pressed)


func _on_roll_button_pressed() -> void:
	for i in dice_labels.size():
		var value := randi_range(1, 6)
		dice_results[i] = value
		dice_labels[i].text = str(value)
