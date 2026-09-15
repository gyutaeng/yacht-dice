extends RefCounted

# GameState.auto_confirm_least_damaging()을 검증한다(docs/multiplayer.md §6에서
# 정한 대로 GameState의 정식 함수로 승격한 것 - debug_hotkeys.gd는 이제
# 이 함수를 부르기만 하는 껍데기라 따로 테스트할 판단 로직이 없다).
#
# 다이스를 정확히 통제해야 하는 테스트가 많다 - GameState.dice_results는
# 공개 배열이라 roll()로 has_rolled를 먼저 true로 만든 뒤 원하는 값으로
# 덮어쓰는 방식을 쓴다(debug_hotkeys.gd의 _force_hand()와 같은 기법).

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("GameState.auto_confirm_least_damaging()")

	_test_rolls_exactly_once_when_not_rolled(r)
	_test_is_deterministic_with_same_seed(r)
	_test_picks_lowest_index_when_all_remaining_score_zero(r)
	_test_picks_only_remaining_category_regardless_of_score(r)
	_test_picks_highest_scoring_category_when_available(r)
	_test_picks_lowest_index_on_score_tie(r)
	_test_independent_of_debug_mode(r)


## has_rolled == false인 상태로 부르면 정확히 한 번만 굴려야 한다(리롤 없음).
## 확정 후 턴이 넘어가면 _begin_turn()이 rolls_left/has_rolled를 다음
## 플레이어 것으로 리셋해버려서 관찰이 불가능해지므로, 이 호출이 "게임의
## 마지막 수"가 되도록(모든 칸이 이미 확정된 상태로) 만들어서 game_over
## 분기(턴 안 넘어감)를 타게 한다 - 그래야 roll() 직후의 rolls_left/has_rolled가
## 그대로 남아 관찰할 수 있다.
func _test_rolls_exactly_once_when_not_rolled(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var state := GameStateScript.new(2, rng)
	state.start_turn()

	for c in GameState.CATEGORY_NAMES.size():
		state.player_score_confirmed[0][c] = true
		if c != GameState.CATEGORY_NAMES.size() - 1:
			state.player_score_confirmed[1][c] = true
	state.current_player = 1

	r.expect_eq("호출 전 아직 안 굴린 상태(테스트 전제)", state.has_rolled, false)

	var category := state.auto_confirm_least_damaging(1)

	r.expect_eq("이 확정으로 게임이 끝남(테스트 전제 확인 - 턴이 안 넘어가야 관찰 가능)", state.game_over, true)
	r.expect_eq("정확히 한 번만 굴려져서 rolls_left가 MAX-1", state.rolls_left, GameState.MAX_ROLLS_PER_TURN - 1)
	r.expect_true("굴린 상태로 표시됨", state.has_rolled)
	r.expect_eq("남은 유일한 칸(마지막 인덱스)이 선택됨", category, GameState.CATEGORY_NAMES.size() - 1)


func _test_is_deterministic_with_same_seed(r) -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var state_a := GameStateScript.new(2, rng_a)
	state_a.start_turn()

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777
	var state_b := GameStateScript.new(2, rng_b)
	state_b.start_turn()

	var category_a := state_a.auto_confirm_least_damaging(0)
	var category_b := state_b.auto_confirm_least_damaging(0)

	r.expect_eq("같은 시드로 같은 다이스가 나옴(테스트 전제)", state_a.dice_results, state_b.dice_results)
	r.expect_eq("같은 시드·같은 상황이면 같은 카테고리를 고름", category_a, category_b)


## 다이스 [1,2,3,4,6]으로 0점이 아닌 칸(Aces/Deuces/Threes/Fours/Sixes/Choice/
## Small Straight)을 미리 확정해서 후보에서 빼면, 남는 건 전부 이 다이스로
## 0점인 칸(Fives/Four of a Kind/Full House/Large Straight/Yacht = 인덱스
## 4,7,8,10,11)뿐이다 - 이 중 인덱스가 가장 낮은 4(Fives)를 골라야 한다.
func _test_picks_lowest_index_when_all_remaining_score_zero(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var state := GameStateScript.new(2, rng)
	state.start_turn()
	state.roll()
	var forced_dice: Array[int] = [1, 2, 3, 4, 6]
	state.dice_results = forced_dice

	for c in [0, 1, 2, 3, 5, 6, 9]:
		state.player_score_confirmed[0][c] = true

	r.expect_eq("이 다이스로 남은 후보가 전부 0점임(테스트 전제)", state.calculate_score(4, forced_dice), 0)

	var category := state.auto_confirm_least_damaging(0)
	r.expect_eq("전부 0점이면 인덱스가 가장 낮은 칸(Fives=4)을 포기", category, 4)


func _test_picks_only_remaining_category_regardless_of_score(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var state := GameStateScript.new(2, rng)
	state.start_turn()

	for c in GameState.CATEGORY_NAMES.size():
		if c != 8:  # Full House만 남긴다.
			state.player_score_confirmed[0][c] = true

	var category := state.auto_confirm_least_damaging(0)
	r.expect_eq("남은 칸이 하나뿐이면 점수와 무관하게 그 칸을 고름", category, 8)


## 다이스 [1,1,1,1,1]이면 Yacht(50점)가 다른 어떤 칸보다도 확실히 높다
## (Choice/Four of a Kind는 둘 다 sum(dice)=5라 서로 동점이 되지만, Yacht의
## 50점에는 못 미친다 - 그래서 이 다이스를 골랐다: Choice와 Four of a
## Kind는 4장 이상이 같을 때 둘 다 "다이스 합"으로 정의가 같아서 항상
## 동점이 되므로, 그 둘 사이의 우선순위를 테스트하려면 여기서 하듯 둘 다
## 이기는 확실한 1위(Yacht)가 있는 상황을 골라야 한다).
func _test_picks_highest_scoring_category_when_available(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var state := GameStateScript.new(2, rng)
	state.start_turn()
	state.roll()
	var forced_dice: Array[int] = [1, 1, 1, 1, 1]
	state.dice_results = forced_dice

	r.expect_eq("Yacht는 이 다이스로 50점(테스트 전제)", state.calculate_score(GameState.YACHT_CATEGORY_INDEX, forced_dice), 50)
	r.expect_eq("Choice는 5점뿐(테스트 전제 - Yacht보다 훨씬 낮음)", state.calculate_score(6, forced_dice), 5)

	var category := state.auto_confirm_least_damaging(0)
	r.expect_eq("가장 높은 점수를 주는 칸(Yacht=50)을 고름", category, GameState.YACHT_CATEGORY_INDEX)


## 다이스 [6,6,6,6,2]는 Choice(=sum(dice)=26)와 Four of a Kind(4장 이상
## 같을 때도 sum(dice)와 같은 정의라 역시 26)가 정확히 동점이 되는 조합이다
## - 이 둘 중 무엇을 고르는지가 "동점이면 카테고리 인덱스가 낮은 쪽을
## 우선한다"는 타이브레이크 규칙(auto_confirm_least_damaging의 비교를 `>`로만
## 해서 먼저 본 것이 유지되게 한 구현)을 직접 검증하는 유일한 자리다.
## [1,1,1,1,1] 테스트(_test_picks_highest_scoring_category_when_available)는
## 단독 1위(Yacht) 경로만 지키므로 이 규칙까지는 못 잡는다.
##
## 경고: 이 테스트는 위 타이브레이크 규칙에 고정돼 있다. 나중에 규칙을
## 의도적으로 바꾸면(예: 배점 상한이 낮은 칸부터 우선하는 다른 기준으로
## 바꾸는 등) 이 테스트가 깨진다 - 깨지면 그게 의도한 변경인지부터
## 확인할 것.
func _test_picks_lowest_index_on_score_tie(r) -> void:
	var forced_dice: Array[int] = [6, 6, 6, 6, 2]

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 11
	var state_a := GameStateScript.new(2, rng_a)
	state_a.start_turn()
	state_a.roll()
	state_a.dice_results = forced_dice

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 11
	var state_b := GameStateScript.new(2, rng_b)
	state_b.start_turn()
	state_b.roll()
	state_b.dice_results = forced_dice

	r.expect_eq(
		"Choice와 Four of a Kind가 이 다이스로 정확히 동점(테스트 전제)",
		state_a.calculate_score(6, forced_dice),
		state_a.calculate_score(GameState.FOUR_OF_A_KIND_CATEGORY_INDEX, forced_dice)
	)

	var category_a := state_a.auto_confirm_least_damaging(0)
	var category_b := state_b.auto_confirm_least_damaging(0)

	r.expect_eq("동점이면 인덱스가 낮은 칸(Choice=6)을 고름", category_a, 6)
	r.expect_eq("같은 입력으로 두 번 호출해도 같은 칸을 고름", category_a, category_b)


## DEBUG_MODE는 const라 테스트 중에 값을 바꿔볼 수 없다 - 대신 game_state.gd
## 소스 자체가 BuildInfo/DEBUG_MODE를 전혀 참조하지 않는지 확인한다.
## docs/multiplayer.md §6의 요구사항("판단 로직이 디버그 스위치 뒤에 숨어
## 있으면 안 된다")을 코드 수준에서 보장하는 회귀 테스트다.
func _test_independent_of_debug_mode(r) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	r.expect_true(
		"game_state.gd는 BuildInfo/DEBUG_MODE를 전혀 참조하지 않음",
		not source.contains("DEBUG_MODE") and not source.contains("BuildInfo")
	)
