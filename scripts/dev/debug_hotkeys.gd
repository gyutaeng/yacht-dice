extends Node

# ============================================================
# 개발용 단축키 — 정식 빌드에는 절대 들어가면 안 된다.
# OS.has_feature("editor")가 거짓이면(=에디터에서 실행한 게 아니면) _ready()에서
# 자기 자신을 즉시 지워버려서, 배포 빌드에는 이 노드 자체가 남지 않는다.
#
# 전부 Ctrl+Shift 조합을 쓴다 — F8/F9/F10/F11 등 단독 기능키는 Godot 에디터
# 자신의 중지/단계 실행 단축키와 겹쳐서, 게임 창에 포커스가 있어도 에디터가
# 먼저 가로채 버린다(F8을 누르면 게임이 그냥 꺼짐).
#
# Ctrl+Shift+1 : 현재 플레이어의 주사위를 야추로 강제 지정.
# Ctrl+Shift+2 : 라지 스트레이트로 강제 지정.
# Ctrl+Shift+3 : 풀 하우스로 강제 지정.
# Ctrl+Shift+4 : 포카드로 강제 지정.
#                (넷 다 순환이 아니라 직접 지정이다 — 원하는 족보를 바로 띄워야
#                테스트가 빠르다. 실제 game_state.roll() 경로를 그대로 타므로
#                special_hand_rolled 연출·보이스가 진짜 이벤트로 뜬다.)
# Ctrl+Shift+S : 현재 플레이어의 미확정 항목 중 첫 번째를 지금 점수로 즉시
#                확정하고 턴을 넘긴다.
# Ctrl+Shift+A : 게임이 끝날 때까지 위 확정을 반복해서 게임 종료 화면까지
#                바로 간다(48턴짜리 4인 게임을 매번 손으로 클릭하지 않고
#                승리/패배 연출·보이스를 테스트하기 위한 것).
#
# 포커스가 LineEdit/TextEdit(1-6의 캐릭터 이름 입력 칸 등)에 있으면 아무 것도
# 하지 않는다 — 글자를 치다가 단축키가 오작동하면 안 된다.
#
# _unhandled_input()이 아니라 _input()을 쓴다: 어떤 Control이 포커스를 들고
# 있어도 무조건 먼저 받도록 해서, UI 쪽 변경으로 단축키가 조용히 안 먹는 일이
# 없게 하기 위함이다(단, 텍스트 입력 위젯에 포커스가 있을 때는 위 이유로 예외).
# ============================================================

var game_state: GameState

# 자동 진행 중인지. Main.gd가 이 플래그를 보고 special_hand_rolled 연출을
# 건너뛴다 — 안 그러면 48턴짜리 자동 진행이 매번 1.5초씩 멈춰서 너무 느려진다.
var is_auto_playing: bool = false

const KEY_ACTIONS := {
	KEY_1: "force_yacht",
	KEY_2: "force_large_straight",
	KEY_3: "force_full_house",
	KEY_4: "force_four_of_a_kind",
	KEY_S: "auto_confirm_one",
	KEY_A: "auto_finish_game",
}

const ACTION_LOGS := {
	"force_yacht": "[디버그] Ctrl+Shift+1 눌림 - 야추로 강제 지정",
	"force_large_straight": "[디버그] Ctrl+Shift+2 눌림 - 라지 스트레이트로 강제 지정",
	"force_full_house": "[디버그] Ctrl+Shift+3 눌림 - 풀 하우스로 강제 지정",
	"force_four_of_a_kind": "[디버그] Ctrl+Shift+4 눌림 - 포카드로 강제 지정",
	"auto_confirm_one": "[디버그] Ctrl+Shift+S 눌림 - 빈 칸 하나 자동 확정",
	"auto_finish_game": "[디버그] Ctrl+Shift+A 눌림 - 게임 끝까지 자동 진행",
}

const FORCED_HAND_DICE := {
	"force_yacht": [6, 6, 6, 6, 6],
	"force_large_straight": [1, 2, 3, 4, 5],
	"force_full_house": [3, 3, 3, 5, 5],
	"force_four_of_a_kind": [2, 2, 2, 2, 5],
}


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not (event.ctrl_pressed and event.shift_pressed):
		return

	var action: String = KEY_ACTIONS.get(event.keycode, "")
	if action == "":
		return

	if _focus_is_text_input():
		return  # 텍스트 입력 중엔(캐릭터 이름 칸 등) 단축키가 발동하면 안 된다.

	print(ACTION_LOGS[action])
	get_viewport().set_input_as_handled()

	if game_state == null:
		print("[디버그] game_state가 아직 없음(게임 시작 전) - 무시")
		return
	if game_state.game_over:
		print("[디버그] 이미 게임 종료됨 - 무시")
		return

	match action:
		"force_yacht", "force_large_straight", "force_full_house", "force_four_of_a_kind":
			_force_hand(FORCED_HAND_DICE[action])
		"auto_confirm_one":
			_auto_confirm_one()
		"auto_finish_game":
			_auto_finish_game()


func _focus_is_text_input() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _force_hand(dice: Array) -> void:
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
