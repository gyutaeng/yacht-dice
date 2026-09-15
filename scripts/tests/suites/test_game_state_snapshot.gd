extends RefCounted

# GameState의 read_only 가드와 get_state_snapshot()/apply_snapshot() 왕복을
# 검증한다(2-4, docs/multiplayer.md §1/§5). read_only 인스턴스는 화면을
# 그리기 위한 사본일 뿐 스스로 진행하면 안 된다 - "조용히 실패"가 아니라
# "상태가 절대 안 바뀐다"는 걸 기능으로 확인한다(push_error 자체는 이
# 테스트 하네스로 가로챌 방법이 없어서 결과로만 확인).

func run(r) -> void:
	r.begin_suite("GameState read_only / snapshot")

	_test_default_is_not_read_only(r)
	_test_read_only_roll_is_noop(r)
	_test_read_only_toggle_lock_is_noop(r)
	_test_read_only_confirm_category_is_noop(r)
	_test_read_only_start_turn_is_noop(r)
	_test_read_only_auto_confirm_is_noop(r)
	_test_snapshot_round_trip(r)
	_test_snapshot_fields_are_typed_correctly(r)


func _test_default_is_not_read_only(r) -> void:
	var state := GameState.new(2)
	r.expect_eq("read_only 인자를 안 넘기면 기본값은 false", state.read_only, false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	state = GameState.new(2, rng)
	r.expect_eq("(player_count, rng) 두 인자만 넘겨도 read_only는 false(기존 호출부 전부 이 형태)", state.read_only, false)


func _make_read_only_state(player_count: int = 2) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return GameState.new(player_count, rng, true)


func _test_read_only_roll_is_noop(r) -> void:
	var state := _make_read_only_state()
	var dice_before := state.dice_results.duplicate()
	var rolls_before := state.rolls_left
	var has_rolled_before := state.has_rolled

	state.roll()

	r.expect_eq("read_only에서 roll()해도 주사위가 그대로", state.dice_results, dice_before)
	r.expect_eq("read_only에서 roll()해도 rolls_left가 그대로", state.rolls_left, rolls_before)
	r.expect_eq("read_only에서 roll()해도 has_rolled가 그대로", state.has_rolled, has_rolled_before)


func _test_read_only_toggle_lock_is_noop(r) -> void:
	var state := _make_read_only_state()
	var locked_before := state.dice_locked.duplicate()

	state.toggle_lock(0)

	r.expect_eq("read_only에서 toggle_lock()해도 고정 상태가 그대로", state.dice_locked, locked_before)


func _test_read_only_confirm_category_is_noop(r) -> void:
	var state := _make_read_only_state()
	# has_rolled=false라 원래도 confirm_category가 통과 못 하지만, read_only
	# 가드가 has_rolled 검사보다 먼저 걸리는지 명확히 하기 위해 has_rolled를
	# 강제로 true로 만들어 조건을 통과시켜본다(그래도 안 바뀌어야 함).
	state.has_rolled = true
	var confirmed_before = state.player_score_confirmed[0].duplicate()
	var scores_before = state.player_confirmed_scores[0].duplicate()

	state.confirm_category(0)

	r.expect_eq("read_only에서 confirm_category()해도 확정 여부가 그대로", state.player_score_confirmed[0], confirmed_before)
	r.expect_eq("read_only에서 confirm_category()해도 점수가 그대로", state.player_confirmed_scores[0], scores_before)


func _test_read_only_start_turn_is_noop(r) -> void:
	var state := _make_read_only_state()
	var rolls_before := state.rolls_left
	var locked_before := state.dice_locked.duplicate()

	state.start_turn()

	r.expect_eq("read_only에서 start_turn()해도 rolls_left가 그대로", state.rolls_left, rolls_before)
	r.expect_eq("read_only에서 start_turn()해도 고정 상태가 그대로", state.dice_locked, locked_before)


func _test_read_only_auto_confirm_is_noop(r) -> void:
	var state := _make_read_only_state()
	var has_rolled_before := state.has_rolled

	var result := state.auto_confirm_least_damaging(0)

	r.expect_eq("read_only에서 auto_confirm_least_damaging()은 -1을 돌려줌", result, -1)
	r.expect_eq("read_only에서 auto_confirm_least_damaging()해도 has_rolled가 그대로", state.has_rolled, has_rolled_before)


## 진짜 GameState를 몇 수 진행시킨 뒤 스냅샷을 떠서 read_only 사본에
## 적용하면 화면에 필요한 모든 필드가 똑같아야 한다.
func _test_snapshot_round_trip(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var source := GameState.new(2, rng)
	source.start_turn()
	source.roll()
	source.toggle_lock(0)
	source.roll()
	source.confirm_category(6)  # Choice - 항상 유효(0점이어도 확정 가능)

	var snapshot := source.get_state_snapshot()

	var target := _make_read_only_state()
	target.apply_snapshot(snapshot)

	r.expect_eq("dice_results가 그대로 왕복함", target.dice_results, source.dice_results)
	r.expect_eq("dice_locked가 그대로 왕복함", target.dice_locked, source.dice_locked)
	r.expect_eq("rolls_left가 그대로 왕복함", target.rolls_left, source.rolls_left)
	r.expect_eq("has_rolled가 그대로 왕복함", target.has_rolled, source.has_rolled)
	r.expect_eq("current_player가 그대로 왕복함", target.current_player, source.current_player)
	r.expect_eq("game_over가 그대로 왕복함", target.game_over, source.game_over)
	r.expect_eq("player_count가 그대로 왕복함", target.player_count, source.player_count)
	r.expect_eq("player_score_confirmed가 그대로 왕복함", target.player_score_confirmed, source.player_score_confirmed)
	r.expect_eq("player_confirmed_scores가 그대로 왕복함", target.player_confirmed_scores, source.player_confirmed_scores)
	r.expect_eq("player_bonus_achieved가 그대로 왕복함", target.player_bonus_achieved, source.player_bonus_achieved)
	r.expect_eq("점수 조회 함수도 정상 동작(get_confirmed_score)", target.get_confirmed_score(0, 6), source.get_confirmed_score(0, 6))
	r.expect_eq("총점 계산도 정상 동작(get_player_total)", target.get_player_total(0), source.get_player_total(0))


## JSON을 실제로 거치면 정수가 float가 된다(2-3에서 겪은 문제) -
## apply_snapshot()이 이걸 다시 int/bool로 되돌리는지 직접 확인한다.
## get_state_snapshot()이 만든 Dictionary를 JSON.stringify()->parse_string()으로
## 실제로 왕복시켜서 진짜 네트워크 상황과 같은 타입 섞임을 재현한다.
func _test_snapshot_fields_are_typed_correctly(r) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var source := GameState.new(2, rng)
	source.start_turn()
	source.roll()
	source.confirm_category(5)  # Sixes

	var snapshot_via_json = JSON.parse_string(JSON.stringify(source.get_state_snapshot()))

	var target := _make_read_only_state()
	target.apply_snapshot(snapshot_via_json)

	r.expect_eq("dice_results 원소가 진짜 int(float 아님)", typeof(target.dice_results[0]), TYPE_INT)
	r.expect_eq("rolls_left가 진짜 int", typeof(target.rolls_left), TYPE_INT)
	r.expect_eq("current_player가 진짜 int", typeof(target.current_player), TYPE_INT)
	r.expect_eq("player_confirmed_scores 원소가 진짜 int(float 아님)", typeof(target.player_confirmed_scores[0][5]), TYPE_INT)
	r.expect_eq("player_score_confirmed 원소가 진짜 bool", typeof(target.player_score_confirmed[0][5]), TYPE_BOOL)
	r.expect_eq("has_rolled가 진짜 bool", typeof(target.has_rolled), TYPE_BOOL)
	r.expect_eq("JSON 왕복 후에도 점수 값 자체는 정확함", target.get_confirmed_score(0, 5), source.get_confirmed_score(0, 5))
