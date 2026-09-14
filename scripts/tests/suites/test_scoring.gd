extends RefCounted

const GameStateScript = preload("res://scripts/game_state.gd")


func run(r) -> void:
	r.begin_suite("족보 점수 계산")

	var gs := GameStateScript.new()

	# --- Aces ~ Sixes: 정상 케이스 + "해당 숫자가 하나도 없으면 0점" ---
	r.expect_eq("Aces: 1이 2개", gs.calc_aces([1, 1, 3, 4, 5]), 2)
	r.expect_eq("Aces: 1이 하나도 없음 -> 0", gs.calc_aces([2, 3, 4, 5, 6]), 0)

	r.expect_eq("Deuces: 2가 3개", gs.calc_deuces([2, 2, 2, 5, 6]), 6)
	r.expect_eq("Deuces: 2가 하나도 없음 -> 0", gs.calc_deuces([1, 3, 4, 5, 6]), 0)

	r.expect_eq("Threes: 3이 2개", gs.calc_threes([3, 3, 1, 1, 1]), 6)
	r.expect_eq("Threes: 3이 하나도 없음 -> 0", gs.calc_threes([1, 2, 4, 5, 6]), 0)

	r.expect_eq("Fours: 4가 4개", gs.calc_fours([4, 4, 4, 4, 2]), 16)
	r.expect_eq("Fours: 4가 하나도 없음 -> 0", gs.calc_fours([1, 2, 3, 5, 6]), 0)

	r.expect_eq("Fives: 5가 2개", gs.calc_fives([5, 5, 1, 1, 1]), 10)
	r.expect_eq("Fives: 5가 하나도 없음 -> 0", gs.calc_fives([1, 2, 3, 4, 6]), 0)

	r.expect_eq("Sixes: 6이 5개(야추)", gs.calc_sixes([6, 6, 6, 6, 6]), 30)
	r.expect_eq("Sixes: 6이 하나도 없음 -> 0", gs.calc_sixes([1, 2, 3, 4, 5]), 0)

	# --- Choice: 조건 없이 항상 5개 합 ---
	r.expect_eq("Choice: 일반 합", gs.calc_choice([1, 2, 3, 4, 5]), 15)
	r.expect_eq("Choice: 야추도 그냥 합", gs.calc_choice([6, 6, 6, 6, 6]), 30)

	# --- Four of a Kind ---
	r.expect_eq("Four of a Kind: 정확히 4개 -> 5개 합", gs.calc_four_of_a_kind([3, 3, 3, 3, 5]), 17)
	r.expect_eq("Four of a Kind: 3개뿐 -> 0", gs.calc_four_of_a_kind([1, 1, 1, 2, 3]), 0)
	r.expect_eq("Four of a Kind: 야추(5개 같음)도 성립 -> 5개 합", gs.calc_four_of_a_kind([4, 4, 4, 4, 4]), 20)

	# --- Full House ---
	r.expect_eq("Full House: 3+2 정상", gs.calc_full_house([2, 2, 3, 3, 3]), 25)
	r.expect_eq("Full House: 조건 미달 -> 0", gs.calc_full_house([1, 1, 2, 3, 4]), 0)
	# 풀하우스와 포카드가 동시에 성립할 것처럼 보이는 경계 케이스:
	# 2,2,2,2,2는 "4개 이상 같음"이라 Four of a Kind는 성립하지만,
	# Full House는 "다른 두 숫자가 3개+2개"를 요구하는 표준 규칙이라 0점이다.
	r.expect_eq("Full House: 야추(2,2,2,2,2)는 3+2 조합이 아니므로 0", gs.calc_full_house([2, 2, 2, 2, 2]), 0)

	# --- Small Straight ---
	r.expect_eq("Small Straight: 1-2-3-4 연속", gs.calc_small_straight([1, 2, 3, 4, 6]), 15)
	r.expect_eq("Small Straight: 라지 스트레이트(1-2-3-4-5)도 스몰로 잡힘", gs.calc_small_straight([1, 2, 3, 4, 5]), 15)
	r.expect_eq("Small Straight: 라지 스트레이트(2-3-4-5-6)도 스몰로 잡힘", gs.calc_small_straight([2, 3, 4, 5, 6]), 15)
	r.expect_eq("Small Straight: 4연속 중 하나가 비어서 실패 -> 0", gs.calc_small_straight([1, 1, 2, 3, 5]), 0)

	# --- Large Straight ---
	r.expect_eq("Large Straight: 1-2-3-4-5", gs.calc_large_straight([1, 2, 3, 4, 5]), 30)
	r.expect_eq("Large Straight: 2-3-4-5-6", gs.calc_large_straight([2, 3, 4, 5, 6]), 30)
	r.expect_eq("Large Straight: 스몰 스트레이트 주사위는 라지로 안 잡힘 -> 0", gs.calc_large_straight([1, 2, 3, 4, 6]), 0)

	# --- Yacht ---
	r.expect_eq("Yacht: 5개 전부 같음", gs.calc_yacht([6, 6, 6, 6, 6]), 50)
	r.expect_eq("Yacht: 4개만 같음 -> 0", gs.calc_yacht([6, 6, 6, 6, 5]), 0)

	# --- 야추(4,4,4,4,4)일 때 12개 족보를 전부 한 번에 점검 ---
	var yacht_dice: Array[int] = [4, 4, 4, 4, 4]
	r.expect_eq("야추(4,4,4,4,4) - Aces", gs.calculate_score(0, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Deuces", gs.calculate_score(1, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Threes", gs.calculate_score(2, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Fours", gs.calculate_score(3, yacht_dice), 20)
	r.expect_eq("야추(4,4,4,4,4) - Fives", gs.calculate_score(4, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Sixes", gs.calculate_score(5, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Choice", gs.calculate_score(6, yacht_dice), 20)
	r.expect_eq("야추(4,4,4,4,4) - Four of a Kind", gs.calculate_score(7, yacht_dice), 20)
	r.expect_eq("야추(4,4,4,4,4) - Full House", gs.calculate_score(8, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Small Straight", gs.calculate_score(9, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Large Straight", gs.calculate_score(10, yacht_dice), 0)
	r.expect_eq("야추(4,4,4,4,4) - Yacht", gs.calculate_score(11, yacht_dice), 50)
