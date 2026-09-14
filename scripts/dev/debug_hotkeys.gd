extends Node

# ============================================================
# 개발용 단축키 — 정식 빌드에는 절대 들어가면 안 된다.
# OS.has_feature("editor")가 거짓이면(=에디터에서 실행한 게 아니면) _ready()에서
# 자기 자신을 즉시 지워버려서, 배포 빌드에는 이 노드 자체가 남지 않는다.
#
# F8  : 현재 플레이어의 주사위를 특정 족보가 되도록 강제 지정한다. 누를 때마다
#       야추 -> 라지 스트레이트 -> 풀 하우스 -> 포카드 순으로 순환한다. 실제
#       game_state.roll() 경로를 그대로 타므로 special_hand_rolled 연출·보이스가
#       진짜 이벤트로 뜬다(야추처럼 잘 안 나오는 족보를 손으로 맞추기 번거로워서).
# F9  : 현재 플레이어의 미확정 항목 중 첫 번째를 지금 점수로 즉시 확정하고 턴을 넘긴다.
# F10 : 게임이 끝날 때까지 F9 동작을 반복해서 게임 종료 화면까지 바로 간다.
#       (48턴짜리 4인 게임을 매번 손으로 클릭하지 않고 승리/패배 연출·보이스를
#       테스트하기 위한 것)
#
# _unhandled_input()이 아니라 _input()을 쓴다: 어떤 Control이 포커스를 들고
# 있어도 무조건 먼저 받도록 해서, UI 쪽 변경으로 단축키가 조용히 안 먹는 일이
# 없게 하기 위함이다.
# ============================================================

var game_state: GameState

# F10 자동 진행 중인지. Main.gd가 이 플래그를 보고 special_hand_rolled 연출을
# 건너뛴다 — 안 그러면 48턴짜리 자동 진행이 매번 1.5초씩 멈춰서 너무 느려진다.
var is_auto_playing: bool = false

# F8을 누를 때마다 여기서 하나씩 순환해서 고른다.
const FORCED_HAND_DICE: Array = [
	[6, 6, 6, 6, 6],  # Yacht
	[1, 2, 3, 4, 5],  # Large Straight
	[3, 3, 3, 5, 5],  # Full House
	[2, 2, 2, 2, 5],  # Four of a Kind
]
var _forced_hand_cycle_index: int = 0


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_F8 and event.keycode != KEY_F9 and event.keycode != KEY_F10:
		return

	match event.keycode:
		KEY_F8:
			print("[디버그] F8 눌림")
		KEY_F9:
			print("[디버그] F9 눌림")
		KEY_F10:
			print("[디버그] F10 눌림")

	get_viewport().set_input_as_handled()

	if game_state == null:
		print("[디버그] game_state가 아직 없음(게임 시작 전) - 무시")
		return
	if game_state.game_over:
		print("[디버그] 이미 게임 종료됨 - 무시")
		return

	match event.keycode:
		KEY_F8:
			_cycle_forced_hand()
		KEY_F9:
			_auto_confirm_one()
		KEY_F10:
			_auto_finish_game()


func _cycle_forced_hand() -> void:
	var dice: Array = FORCED_HAND_DICE[_forced_hand_cycle_index]
	_forced_hand_cycle_index = (_forced_hand_cycle_index + 1) % FORCED_HAND_DICE.size()

	for i in 5:
		game_state.dice_results[i] = dice[i]
		if not game_state.dice_locked[i]:
			game_state.toggle_lock(i)
	game_state.roll()


func _auto_confirm_one() -> void:
	_ensure_rolled()
	var category := _find_open_category()
	if category != -1:
		game_state.confirm_category(category)


func _auto_finish_game() -> void:
	is_auto_playing = true
	while not game_state.game_over:
		_ensure_rolled()
		var category := _find_open_category()
		if category == -1:
			break
		game_state.confirm_category(category)
	is_auto_playing = false


func _ensure_rolled() -> void:
	if not game_state.has_rolled:
		game_state.roll()


func _find_open_category() -> int:
	for i in GameState.CATEGORY_NAMES.size():
		if not game_state.player_score_confirmed[game_state.current_player][i]:
			return i
	return -1
