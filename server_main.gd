extends Node

# 화면도 네트워크도 없이 GameState 하나만으로 한 판을 끝까지 돌릴 수 있는지
# 확인하기 위한 콘솔 진입점(docs/multiplayer.md §2-1). 실행:
#
#   godot --headless --path . res://server_main.tscn -- <인원수>
#
# <인원수>는 생략 가능(기본 2), 2~4 범위를 벗어나면 GameState._init()이
# 스스로 경고를 찍고 기본값 2로 시작한다.
#
# 명령: roll / hold <번호...> / score <족보키> / state / auto / quit

const GameStateScript = preload("res://scripts/game_state.gd")

const CATEGORY_KEYS := {
	"aces": 0,
	"deuces": 1,
	"threes": 2,
	"fours": 3,
	"fives": 4,
	"sixes": 5,
	"choice": 6,
	"four_of_a_kind": 7,
	"full_house": 8,
	"small_straight": 9,
	"large_straight": 10,
	"yacht": 11,
}

var game_state: GameState


## 서버 주사위 시드는 예측 가능하면 안 된다 - 이 값을 미리 알면 앞으로
## 나올 주사위를 전부 계산할 수 있어서, "서버가 굴리니까 치팅이 불가능하다"는
## Phase 2의 전제(docs/multiplayer.md §0)가 조작 없이도 무너진다. 그래서
## RandomNumberGenerator.randomize()(시각 기반) 대신, OS 엔트로피를 쓰는
## Crypto.generate_random_bytes()로 시드를 만든다.
## 이 함수는 server_main.gd(headless 서버 전용 진입점)에서만 쓴다 -
## docs/multiplayer.md §0에 따라 서버는 절대 Web export로 돌지 않고 항상
## 네이티브 headless 바이너리로만 돌기 때문에, Crypto의 웹 export 동작
## 여부는 이 경로에서는 따질 필요가 없다. 클라이언트 로컬(싱글) 모드는
## GameState._init()이 자체적으로 randomize()를 쓰는 기존 경로를 그대로
## 유지한다 - 다른 사람과 겨루는 게 아니라서 시드를 예측당해도 치팅 상대가
## 없다.
func _generate_secure_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(8)
	var seed_value := 0
	for b in bytes:
		seed_value = (seed_value << 8) | b
	return seed_value


func _ready() -> void:
	var player_count := GameState.DEFAULT_PLAYER_COUNT
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0].is_valid_int():
		player_count = args[0].to_int()

	var rng := RandomNumberGenerator.new()
	rng.seed = _generate_secure_seed()
	game_state = GameStateScript.new(player_count, rng)
	game_state.start_turn()

	print("=== 요트다이스 headless 서버 ===")
	print("명령: roll / hold <번호...> / score <족보키> / state / auto / quit")
	print("족보키: %s" % ", ".join(CATEGORY_KEYS.keys()))
	_print_state()
	_run_loop()

	get_tree().quit()


func _run_loop() -> void:
	# OS.read_string_from_stdin()은 줄 단위가 아니라 그 순간 버퍼에 들어와
	# 있는 만큼을 통째로 돌려준다 - 명령을 빠르게 이어 보내면(파이프 입력 등)
	# 한 번의 호출에 여러 줄이 개행 문자와 함께 섞여서 들어올 수 있으므로,
	# 직접 줄 단위로 잘라 큐에 쌓아두고 하나씩 처리한다.
	var pending_lines: Array[String] = []
	while true:
		if pending_lines.is_empty():
			var chunk := OS.read_string_from_stdin(1024)
			for part in chunk.split("\n"):
				var trimmed := part.strip_edges()
				if trimmed != "":
					pending_lines.append(trimmed)
			if pending_lines.is_empty():
				continue

		var line: String = pending_lines.pop_front()
		if not _handle_command(line):
			break
	print("서버를 종료합니다.")


func _handle_command(line: String) -> bool:
	var tokens := line.split(" ", false)
	var cmd := tokens[0].to_lower()
	var args := tokens.slice(1)

	match cmd:
		"roll":
			_cmd_roll()
		"hold":
			_cmd_hold(args)
		"score":
			_cmd_score(args)
		"state":
			_print_state()
		"auto":
			_cmd_auto()
		"quit", "exit":
			return false
		_:
			print("알 수 없는 명령입니다: '%s'. 사용 가능: roll, hold <번호...>, score <족보키>, state, auto, quit" % cmd)
	return true


func _cmd_roll() -> void:
	if game_state.game_over:
		print("게임이 이미 끝났습니다.")
		return
	if game_state.rolls_left <= 0:
		print("리롤 횟수를 모두 사용했습니다.")
		return

	game_state.roll()
	_print_state()


func _cmd_hold(args: Array) -> void:
	if game_state.game_over:
		print("게임이 이미 끝났습니다.")
		return
	if not game_state.has_rolled:
		print("아직 주사위를 굴리지 않았습니다.")
		return
	if args.is_empty():
		print("고정할 주사위 번호를 입력하세요. 예: hold 2 4")
		return

	var dice_count := game_state.dice_results.size()
	for a in args:
		if not (a as String).is_valid_int():
			print("주사위 번호는 숫자여야 합니다: '%s'" % a)
			continue
		var index := (a as String).to_int()
		if index < 1 or index > dice_count:
			print("주사위 번호는 1~%d 사이여야 합니다: %d" % [dice_count, index])
			continue
		game_state.toggle_lock(index - 1)

	_print_state()


func _cmd_score(args: Array) -> void:
	if game_state.game_over:
		print("게임이 이미 끝났습니다.")
		return
	if not game_state.has_rolled:
		print("아직 주사위를 굴리지 않았습니다.")
		return
	if args.is_empty():
		print("확정할 족보 이름을 입력하세요. 예: score full_house")
		return

	var key: String = args[0].to_lower()
	if not CATEGORY_KEYS.has(key):
		print("알 수 없는 족보 이름: '%s'. 사용 가능: %s" % [key, ", ".join(CATEGORY_KEYS.keys())])
		return

	var category: int = CATEGORY_KEYS[key]
	var player := game_state.current_player
	if game_state.is_category_confirmed(player, category):
		print("이미 확정된 칸입니다: %s" % GameState.CATEGORY_NAMES[category])
		return

	game_state.confirm_category(category)
	print("플레이어 %d: %s 확정 (%d점)" % [player + 1, GameState.CATEGORY_NAMES[category], game_state.get_confirmed_score(player, category)])

	if game_state.game_over:
		_print_game_over()
	else:
		_print_state()


func _cmd_auto() -> void:
	if game_state.game_over:
		print("게임이 이미 끝났습니다.")
		return

	var player := game_state.current_player
	var category := game_state.auto_confirm_least_damaging(player)
	if category == -1:
		print("자동 확정을 할 수 없는 상태입니다.")
		return

	print("플레이어 %d: 자동으로 %s 확정 (%d점)" % [player + 1, GameState.CATEGORY_NAMES[category], game_state.get_confirmed_score(player, category)])

	if game_state.game_over:
		_print_game_over()
	else:
		_print_state()


func _format_dice() -> String:
	var parts: Array[String] = []
	for i in game_state.dice_results.size():
		var text := "?" if not game_state.has_rolled else str(game_state.dice_results[i])
		if game_state.dice_locked[i]:
			text = "[%s]" % text
		parts.append(text)
	return " ".join(parts)


func _print_state() -> void:
	print("")
	print("=== 현재 상태 ===")
	print("턴: 플레이어 %d / 남은 굴리기: %d" % [game_state.current_player + 1, game_state.rolls_left])
	print("주사위: %s" % _format_dice())
	print("")

	for p in game_state.player_count:
		var marker := " (현재 턴)" if p == game_state.current_player else ""
		print("[플레이어 %d]%s" % [p + 1, marker])
		for c in GameState.CATEGORY_NAMES.size():
			var value_text := "-"
			if game_state.is_category_confirmed(p, c):
				value_text = str(game_state.get_confirmed_score(p, c))
			print("  %s%s" % [GameState.CATEGORY_NAMES[c].rpad(16), value_text])

		if game_state.has_upper_bonus(p):
			print("  상단 합계: %d (보너스 +%d 달성)" % [game_state.get_upper_section_total(p), GameState.UPPER_BONUS_POINTS])
		else:
			print("  상단 합계: %d (보너스까지 %d점 남음)" % [game_state.get_upper_section_total(p), game_state.get_upper_bonus_remaining(p)])
		print("  총점: %d" % game_state.get_player_total(p))
		print("")


func _print_game_over() -> void:
	print("=== 게임 종료 ===")
	var winners := game_state.get_winners()
	if winners.size() == 1:
		var winner: int = winners[0]
		print("승자: 플레이어 %d (총점 %d)" % [winner + 1, game_state.get_player_total(winner)])
	else:
		var names: Array[String] = []
		for w in winners:
			names.append("플레이어 %d" % (w + 1))
		print("공동 우승: %s (총점 %d)" % [", ".join(names), game_state.get_player_total(winners[0])])
