class_name GameState
extends RefCounted

signal state_changed

const MAX_ROLLS_PER_TURN := 3
const MIN_PLAYER_COUNT := 2
const MAX_PLAYER_COUNT := 4
const DEFAULT_PLAYER_COUNT := 2

# CATEGORY_NAMES에서 "Yacht"의 인덱스. yacht_scored 이벤트 판정에 쓴다.
const YACHT_CATEGORY_INDEX := 11

# special_hand_rolled 판정에 쓰는 나머지 "좋은 족보" 인덱스.
const FOUR_OF_A_KIND_CATEGORY_INDEX := 7
const FULL_HOUSE_CATEGORY_INDEX := 8
const LARGE_STRAIGHT_CATEGORY_INDEX := 10

# 앞쪽이 더 높은 우선순위. 야추는 포카드이기도 해서, 여러 개가 동시에
# 성립하면 이 순서에서 가장 앞의 것 하나만 special_hand_rolled로 띄운다.
const SPECIAL_HAND_PRIORITY: Array[int] = [
	YACHT_CATEGORY_INDEX,
	LARGE_STRAIGHT_CATEGORY_INDEX,
	FULL_HOUSE_CATEGORY_INDEX,
	FOUR_OF_A_KIND_CATEGORY_INDEX,
]

# 상단 섹션(Aces~Sixes) 보너스 규칙. 나중에 조정 가능하도록 상수로 뺐다.
const UPPER_BONUS_THRESHOLD := 63
const UPPER_BONUS_POINTS := 35
const UPPER_SECTION_SIZE := 6

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
var rolls_left: int = MAX_ROLLS_PER_TURN
var current_player: int = 0
var game_over: bool = false
var player_count: int = DEFAULT_PLAYER_COUNT

# 온라인 클라이언트가 화면을 그리기 위해 들고 있는 사본은 절대 스스로
# 진행하면 안 된다(docs/multiplayer.md §1 - "클라이언트는 GameState를
# 계산기로 쓰지 않는다"). read_only=true면 roll()/toggle_lock()/
# confirm_category()/start_turn()/auto_confirm_least_damaging()이 전부
# 아무 것도 안 하고 push_error로 시끄럽게 실패한다 - 이 프로젝트에서 지금
# 까지 난 사고(초기 야추 50점, queue_free, 특수 족보 연출)가 전부 "에러
# 없이 조용히 틀리는" 종류였어서, 어긋남은 반드시 소리 나게 실패해야
# 한다는 원칙을 여기 적용한다. 유일하게 통과하는 갱신 경로는
# apply_snapshot() - 서버가 보낸 스냅샷을 그대로 반영하는 용도다.
var read_only: bool = false

# dice_results의 기본값은 그 자체로 유효한(전부 같은) 조합이라, 한 번도 굴리기
# 전에는 이 플래그로 "아직 진짜 주사위 값이 아니다"를 구분한다. 이게 없으면
# Yacht 같은 족보가 시작하자마자 잡히는 문제가 재현된다.
var has_rolled: bool = false

# player_score_confirmed[player][category] / player_confirmed_scores[player][category]
var player_score_confirmed: Array = []
var player_confirmed_scores: Array = []
var player_bonus_achieved: Array[bool] = []

# SPECIAL_HAND_PRIORITY 안에서의 인덱스(랭크). -1이면 이번 턴엔 아직 아무것도 안 띄움.
# 랭크가 낮을수록(=더 앞 순위) 더 좋은 족보라서, "이미 띄운 것보다 더 좋은 게
# 새로 성립했을 때만" 다시 띄우는 기준으로 쓴다.
var _shown_special_hand_rank_this_turn: int = -1

# game_started는 한 판에 딱 한 번만 나가야 한다. start_turn()은 원래 게임당
# 한 번만 불리지만, 그 "한 번"이라는 보장을 호출 횟수가 아니라 이 플래그로
# 명시적으로 걸어둔다(나중에 서버 스냅샷 복원 등으로 start_turn()이 다시
# 불릴 일이 생겨도 인사말이 두 번 나가지 않도록).
var _game_started_emitted: bool = false

var _rng: RandomNumberGenerator
var _score_calculators: Array[Callable] = []


func _init(requested_player_count: int = DEFAULT_PLAYER_COUNT, rng: RandomNumberGenerator = null, read_only_state: bool = false) -> void:
	read_only = read_only_state
	if requested_player_count < MIN_PLAYER_COUNT or requested_player_count > MAX_PLAYER_COUNT:
		push_warning("GameState: 인원수 %d는 %d~%d 범위를 벗어나 거부됨. 기본값 %d로 시작." % [requested_player_count, MIN_PLAYER_COUNT, MAX_PLAYER_COUNT, DEFAULT_PLAYER_COUNT])
		player_count = DEFAULT_PLAYER_COUNT
	else:
		player_count = requested_player_count

	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	for p in player_count:
		player_score_confirmed.append(_make_bool_array(CATEGORY_NAMES.size(), false))
		player_confirmed_scores.append(_make_int_array(CATEGORY_NAMES.size(), 0))
		player_bonus_achieved.append(false)

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
	if read_only:
		push_error("GameState.start_turn(): read_only 인스턴스에서 호출됨 - 무시됨")
		return
	if not _game_started_emitted:
		_game_started_emitted = true
		GameEvents.game_started.emit(player_count)
	_begin_turn()
	state_changed.emit()


func roll() -> void:
	if read_only:
		push_error("GameState.roll(): read_only 인스턴스에서 호출됨 - 무시됨")
		return
	if rolls_left <= 0:
		return

	_roll_unlocked_dice()
	rolls_left -= 1
	_emit_dice_rolled()
	state_changed.emit()


func toggle_lock(index: int) -> void:
	if read_only:
		push_error("GameState.toggle_lock(): read_only 인스턴스에서 호출됨 - 무시됨")
		return
	dice_locked[index] = not dice_locked[index]
	GameEvents.die_held_changed.emit(current_player, index, dice_locked[index])
	state_changed.emit()


func confirm_category(category_index: int) -> void:
	if read_only:
		push_error("GameState.confirm_category(): read_only 인스턴스에서 호출됨 - 무시됨")
		return
	if not has_rolled or game_over or player_score_confirmed[current_player][category_index]:
		return

	var value := calculate_score(category_index, dice_results)
	player_confirmed_scores[current_player][category_index] = value
	player_score_confirmed[current_player][category_index] = true

	GameEvents.score_committed.emit(current_player, category_index, value)
	if value == 0:
		GameEvents.zero_scored.emit(current_player, category_index)
	if category_index == YACHT_CATEGORY_INDEX and value == 50:
		GameEvents.yacht_scored.emit(current_player)

	if not player_bonus_achieved[current_player] and has_upper_bonus(current_player):
		player_bonus_achieved[current_player] = true
		GameEvents.bonus_achieved.emit(current_player)

	GameEvents.turn_ended.emit(current_player)

	if _all_players_completed():
		game_over = true
		var scores: Array[int] = []
		for p in player_count:
			scores.append(get_player_total(p))
		GameEvents.game_ended.emit(get_winners(), scores)
	else:
		current_player = (current_player + 1) % player_count
		_begin_turn()

	state_changed.emit()


## 이 플레이어 대신 안전하게 한 수 두고 그 결과 카테고리를 돌려준다 - 반응
## 없는 플레이어를 대신 진행시켜야 하는 곳(디버그 단축키, 나중에 서버의
## 연결 끊김/턴 제한 시간 처리 - docs/multiplayer.md §6)이 전부 이 함수
## 하나를 통해서만 그 판단을 한다. 판단 로직을 여러 곳에 따로 두면 서버와
## 로컬이 다른 기준으로 "안전한 수"를 고르게 될 위험이 있어서, 여기 하나로
## 모았다 - 화면도 네트워크도 필요 없는 순수 규칙 로직이라 GameState가
## 있을 자리다(디버그 전용 파일에 있으면 안 됨 - 그 파일은 디버그 빌드
## 플래그가 꺼지면 자체가 비활성화되므로, 여기 있어야 항상 동작한다).
##
## 아직 한 번도 안 굴렸으면(has_rolled == false) 먼저 정확히 한 번만
## 굴린다 - 리롤은 안 한다(추가로 최적화하는 건 "안전하게 한 수 두는"
## 목적을 넘어서는 과한 자동 플레이라고 봄). 그 다음 확정 안 한 칸 중
## 지금 다이스로 가장 높은 점수를 주는 칸을 고른다. 전부 0점이면(성립하는
## 족보가 하나도 없으면) 어차피 뭘 골라도 0점이므로, 상단 섹션처럼 개별
## 배점 상한이 낮은 칸을 먼저 포기하는 셈이 되도록 **카테고리 인덱스가
## 낮은 쪽을 우선한다**(비교를 `>`로만 해서 동점이면 먼저 본 것, 즉
## CATEGORY_NAMES 앞쪽이 그대로 유지됨). 완벽한 최적 플레이가 아니라
## "언제 불러도 항상 같은 결과가 나오는 안전한 기본값"이 목적이다 -
## 테스트가 이 결정성에 의존한다.
##
## player_index가 지금 차례가 아니거나 게임이 이미 끝났으면 아무 것도 안
## 하고 -1을 돌려준다(호출부의 실수를 방어).
func auto_confirm_least_damaging(player_index: int) -> int:
	if read_only:
		push_error("GameState.auto_confirm_least_damaging(): read_only 인스턴스에서 호출됨 - 무시됨")
		return -1
	if player_index != current_player or game_over:
		push_warning("GameState.auto_confirm_least_damaging: 플레이어 %d는 지금 차례가 아니거나 게임이 이미 끝남" % player_index)
		return -1

	if not has_rolled:
		roll()

	var best_category := -1
	var best_score := -1
	for category in CATEGORY_NAMES.size():
		if player_score_confirmed[current_player][category]:
			continue
		var score := calculate_score(category, dice_results)
		if score > best_score:
			best_score = score
			best_category = category

	if best_category == -1:
		push_warning("GameState.auto_confirm_least_damaging: 확정 안 한 칸이 없음(game_over 판정과 모순되는 비정상 상태)")
		return -1

	confirm_category(best_category)
	return best_category


func is_category_confirmed(player: int, category_index: int) -> bool:
	return player_score_confirmed[player][category_index]


func get_confirmed_score(player: int, category_index: int) -> int:
	return player_confirmed_scores[player][category_index]


func preview_score(category_index: int) -> int:
	if not has_rolled:
		return 0
	return calculate_score(category_index, dice_results)


func calculate_score(category_index: int, dice: Array[int]) -> int:
	return _score_calculators[category_index].call(dice)


## 서버가 방 전원에게 방송하는 전체 스냅샷(docs/multiplayer.md §5)의
## 내용이다 - 순수 읽기라 read_only 여부와 무관하게 항상 호출 가능하다.
func get_state_snapshot() -> Dictionary:
	return {
		"dice_results": dice_results,
		"dice_locked": dice_locked,
		"rolls_left": rolls_left,
		"has_rolled": has_rolled,
		"current_player": current_player,
		"game_over": game_over,
		"player_count": player_count,
		"player_score_confirmed": player_score_confirmed,
		"player_confirmed_scores": player_confirmed_scores,
		"player_bonus_achieved": player_bonus_achieved,
	}


## get_state_snapshot()이 만든 것과 같은 모양의 Dictionary를 받아 필드를
## 통째로 덮어쓴다 - read_only 인스턴스가 상태를 갱신하는 유일한 경로다
## (read_only가 아니어도 막지는 않지만, 실제로 쓰는 곳은 온라인 클라이언트
## 사본뿐이다). JSON을 거쳐 온 값은 정수도 float가 되므로(2-3에서 이미
## 겪은 문제) 원소 하나하나를 명시적으로 int()/bool()에 통과시킨다 - 안
## 그러면 점수판에 "5.0"처럼 찍히는 조용한 버그가 생긴다.
func apply_snapshot(snapshot: Dictionary) -> void:
	var new_dice: Array[int] = []
	for v in snapshot.get("dice_results", []):
		new_dice.append(int(v))
	dice_results = new_dice

	var new_locked: Array[bool] = []
	for v in snapshot.get("dice_locked", []):
		new_locked.append(bool(v))
	dice_locked = new_locked

	rolls_left = int(snapshot.get("rolls_left", rolls_left))
	has_rolled = bool(snapshot.get("has_rolled", has_rolled))
	current_player = int(snapshot.get("current_player", current_player))
	game_over = bool(snapshot.get("game_over", game_over))
	player_count = int(snapshot.get("player_count", player_count))

	var new_score_confirmed: Array = []
	for player_flags in snapshot.get("player_score_confirmed", []):
		var row: Array[bool] = []
		for v in player_flags:
			row.append(bool(v))
		new_score_confirmed.append(row)
	player_score_confirmed = new_score_confirmed

	var new_confirmed_scores: Array = []
	for player_scores in snapshot.get("player_confirmed_scores", []):
		var row: Array[int] = []
		for v in player_scores:
			row.append(int(v))
		new_confirmed_scores.append(row)
	player_confirmed_scores = new_confirmed_scores

	var new_bonus: Array[bool] = []
	for v in snapshot.get("player_bonus_achieved", []):
		new_bonus.append(bool(v))
	player_bonus_achieved = new_bonus

	state_changed.emit()


func get_player_total(player: int) -> int:
	var total := 0
	for score in player_confirmed_scores[player]:
		total += score
	total += get_upper_bonus_points(player)
	return total


func get_upper_section_total(player: int) -> int:
	var total := 0
	for i in UPPER_SECTION_SIZE:
		total += player_confirmed_scores[player][i]
	return total


func has_upper_bonus(player: int) -> bool:
	return get_upper_section_total(player) >= UPPER_BONUS_THRESHOLD


func get_upper_bonus_points(player: int) -> int:
	return UPPER_BONUS_POINTS if has_upper_bonus(player) else 0


func get_upper_bonus_remaining(player: int) -> int:
	return max(UPPER_BONUS_THRESHOLD - get_upper_section_total(player), 0)


func get_winners() -> Array[int]:
	var totals: Array[int] = []
	for p in player_count:
		totals.append(get_player_total(p))

	var best := totals[0]
	for t in totals:
		if t > best:
			best = t

	var winners: Array[int] = []
	for p in player_count:
		if totals[p] == best:
			winners.append(p)
	return winners


func _begin_turn() -> void:
	GameEvents.turn_started.emit(current_player)

	rolls_left = MAX_ROLLS_PER_TURN
	has_rolled = false
	_shown_special_hand_rank_this_turn = -1
	for i in dice_locked.size():
		dice_locked[i] = false


func _roll_unlocked_dice() -> void:
	has_rolled = true
	for i in dice_results.size():
		if dice_locked[i]:
			continue
		dice_results[i] = _rng.randi_range(1, 6)


func _emit_dice_rolled() -> void:
	GameEvents.dice_rolled.emit(current_player, dice_results.duplicate(), rolls_left)
	_emit_special_hand_if_any()
	for i in CATEGORY_NAMES.size():
		if not player_score_confirmed[current_player][i]:
			GameEvents.score_previewed.emit(i, preview_score(i))


# 이번 굴리기에서 성립하는 "좋은 족보" 중 가장 높은 우선순위 하나만 골라 emit한다.
# 이미 확정한 칸은 후보에서 제외한다(그 칸은 다시 확정할 수 없으므로 띄워봐야 의미가
# 없다). 같은 턴에 이미 보여준 것과 같거나 더 낮은 순위면 다시 띄우지 않는다 —
# 리롤해도 여전히 풀하우스면 조용히 넘어가고, 거기서 야추로 올라가면 그때 띄운다.
func _emit_special_hand_if_any() -> void:
	for rank in SPECIAL_HAND_PRIORITY.size():
		var category := SPECIAL_HAND_PRIORITY[rank]
		if player_score_confirmed[current_player][category]:
			continue

		var points := calculate_score(category, dice_results)
		if points <= 0:
			continue

		if _shown_special_hand_rank_this_turn != -1 and rank >= _shown_special_hand_rank_this_turn:
			return

		_shown_special_hand_rank_this_turn = rank
		GameEvents.special_hand_rolled.emit(current_player, category, points)
		return


func _player_completed(player: int) -> bool:
	for confirmed in player_score_confirmed[player]:
		if not confirmed:
			return false
	return true


func _all_players_completed() -> bool:
	for p in player_count:
		if not _player_completed(p):
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
