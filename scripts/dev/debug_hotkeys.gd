extends Node

# ============================================================
# 개발용 단축키 — 정식 빌드에는 절대 들어가면 안 된다.
# OS.has_feature("editor")가 거짓이면(=에디터에서 실행한 게 아니면) _ready()에서
# 자기 자신을 즉시 지워버려서, 배포 빌드에는 이 노드 자체가 남지 않는다.
#
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


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_F9 and event.keycode != KEY_F10:
		return

	if event.keycode == KEY_F9:
		print("[디버그] F9 눌림")
	else:
		print("[디버그] F10 눌림")

	get_viewport().set_input_as_handled()

	if game_state == null:
		print("[디버그] game_state가 아직 없음(게임 시작 전) - 무시")
		return
	if game_state.game_over:
		print("[디버그] 이미 게임 종료됨 - 무시")
		return

	if event.keycode == KEY_F9:
		_auto_confirm_one()
	else:
		_auto_finish_game()


func _auto_confirm_one() -> void:
	var category := _find_open_category()
	if category != -1:
		game_state.confirm_category(category)


func _auto_finish_game() -> void:
	while not game_state.game_over:
		var category := _find_open_category()
		if category == -1:
			break
		game_state.confirm_category(category)


func _find_open_category() -> int:
	for i in GameState.CATEGORY_NAMES.size():
		if not game_state.player_score_confirmed[game_state.current_player][i]:
			return i
	return -1
