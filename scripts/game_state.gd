class_name GameState
extends RefCounted

signal state_changed

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
var current_player: int = 0
var game_over: bool = false

# player_score_confirmed[player][category] / player_confirmed_scores[player][category]
var player_score_confirmed: Array = []
var player_confirmed_scores: Array = []

var _rng: RandomNumberGenerator
var _score_calculators: Array[Callable] = []


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	for p in NUM_PLAYERS:
		player_score_confirmed.append(_make_bool_array(CATEGORY_NAMES.size(), false))
		player_confirmed_scores.append(_make_int_array(CATEGORY_NAMES.size(), 0))

	_score_calculators = [
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


func start_turn() -> void:
	_begin_turn()
	state_changed.emit()


func roll() -> void:
	if rerolls_left <= 0:
		return

	_roll_unlocked_dice()
	rerolls_left -= 1
	state_changed.emit()


func toggle_lock(index: int) -> void:
	dice_locked[index] = not dice_locked[index]
	state_changed.emit()


func confirm_category(category_index: int) -> void:
	if game_over or player_score_confirmed[current_player][category_index]:
		return

	var value := calculate_score(category_index, dice_results)
	player_confirmed_scores[current_player][category_index] = value
	player_score_confirmed[current_player][category_index] = true

	if _player_completed(0) and _player_completed(1):
		game_over = true
	else:
		current_player = 1 - current_player
		_begin_turn()

	state_changed.emit()


func is_category_confirmed(player: int, category_index: int) -> bool:
	return player_score_confirmed[player][category_index]


func get_confirmed_score(player: int, category_index: int) -> int:
	return player_confirmed_scores[player][category_index]


func preview_score(category_index: int) -> int:
	return calculate_score(category_index, dice_results)


func calculate_score(category_index: int, dice: Array[int]) -> int:
	return _score_calculators[category_index].call(dice)


func get_player_total(player: int) -> int:
	var total := 0
	for score in player_confirmed_scores[player]:
		total += score
	return total


func get_winner() -> int:
	var total_p0 := get_player_total(0)
	var total_p1 := get_player_total(1)
	if total_p0 > total_p1:
		return 0
	if total_p1 > total_p0:
		return 1
	return -1


func _begin_turn() -> void:
	rerolls_left = MAX_REROLLS
	for i in dice_locked.size():
		dice_locked[i] = false
	_roll_unlocked_dice()


func _roll_unlocked_dice() -> void:
	for i in dice_results.size():
		if dice_locked[i]:
			continue
		dice_results[i] = _rng.randi_range(1, 6)


func _player_completed(player: int) -> bool:
	for confirmed in player_score_confirmed[player]:
		if not confirmed:
			return false
	return true


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
