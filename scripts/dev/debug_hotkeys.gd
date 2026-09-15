extends Node

# ============================================================
# 개발용 단축키 — 정식 빌드에는 절대 들어가면 안 된다.
# BuildInfo.DEBUG_MODE가 false면 _ready()에서 자기 자신을 즉시 지워버려서,
# 이 값이 false인 빌드에는 이 노드 자체가(키보드 단축키도 아래 디버그 버튼도)
# 남지 않는다. 에디터냐 export냐는 안 따진다 - DEBUG_MODE 하나로 통일했다
# (build_info.gd 참고). 정식 배포 전에는 반드시 그 값을 false로 되돌릴 것.
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
#
# DEBUG_MODE일 때는 화면 구석에 같은 동작을 하는 버튼도 띄운다
# (_build_debug_button_panel()) - 브라우저는 Ctrl+숫자 조합을 자체 단축키로
# 먼저 가로채는 경우가 많아서(크롬 Ctrl+1~8은 탭 전환) 웹에서는 키보드 단축키를
# 아예 못 믿는다. 버튼은 키와 똑같이 _perform_action()을 호출하므로 동작이
# 완전히 같다 - 데스크톱 에디터에서는 키가 더 빠르니 그대로 쓰고, 웹에서는
# 버튼으로 확실하게 누른다.
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

const DEBUG_BUTTON_MARGIN := 12.0

# 디버그 버튼에 쓸 짧은 라벨. KEY_ACTIONS와 순서를 맞춰서 버튼 순서가 위 주석의
# Ctrl+Shift+1~4/S/A 순서와 같게 한다.
const BUTTON_LABELS := {
	"force_yacht": "야추",
	"force_large_straight": "라지",
	"force_full_house": "풀하우스",
	"force_four_of_a_kind": "포카드",
	"auto_confirm_one": "한 칸 확정",
	"auto_finish_game": "끝까지 진행",
}


func _ready() -> void:
	if not BuildInfo.DEBUG_MODE:
		queue_free()
		return
	_build_debug_button_panel()


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

	get_viewport().set_input_as_handled()
	_perform_action(action)


## 키보드 단축키와 디버그 버튼이 공유하는 실제 동작. 어느 쪽으로 들어와도
## 완전히 같은 경로를 타게 해서 "버튼이 키와 다르게 동작"하는 일이 없게 한다.
func _perform_action(action: String) -> void:
	print(ACTION_LOGS[action])

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


## 웹에서 Ctrl+Shift+숫자가 브라우저에 가로채여 안 먹는 문제 대응용 - 화면
## 우하단에 작게 버튼 6개를 띄운다. CanvasLayer를 쓰는 이유: 이 노드(DebugHotkeys)는
## Control이 아닌 평범한 Node라 부모의 레이아웃 트리에 안 얽매이고, CanvasLayer는
## 어떤 부모 밑에 있든 화면 좌표계에 독립적으로 그려지므로 Main.tscn 쪽을 전혀
## 안 건드리고 여기서만 완결된다.
func _build_debug_button_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100  # InputBlocker 등 게임 UI보다 확실히 위.
	add_child(layer)

	# 우하단 모서리에 고정하되, 이 시점엔 버튼을 아직 안 넣어서 크기를 모른다.
	# anchor_*=1(우하단 모서리)에 offset_left/right를 같은 값으로 둬서 앵커
	# 사각형 자체를 폭 0인 점으로 만들고, grow_direction을 BEGIN(왼쪽/위로
	# 자라는 방향)으로 주면 나중에 버튼이 늘어나 최소 크기가 커져도 항상 이
	# 점을 기준으로 화면 안쪽으로만 자란다 - 그래서 크기 계산 순서나 창 크기
	# 변화와 무관하게 절대 화면 밖으로 잘리지 않는다. (버튼을 72x22->104x34로
	# 키우면서 set_anchors_and_offsets_preset(MODE_MINSIZE)를 쓰다가 버튼을
	# 넣기 전 크기(0,0) 기준으로 앵커가 고정돼버려서 패널이 화면 밖으로
	# 밀려나는 버그가 났다 - 그 수정.)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vbox.offset_left = -DEBUG_BUTTON_MARGIN
	vbox.offset_right = -DEBUG_BUTTON_MARGIN
	vbox.offset_top = -DEBUG_BUTTON_MARGIN
	vbox.offset_bottom = -DEBUG_BUTTON_MARGIN
	vbox.modulate = Color(1, 1, 1, 0.8)
	vbox.add_theme_constant_override("separation", 4)
	layer.add_child(vbox)

	for action: String in KEY_ACTIONS.values():
		var btn := Button.new()
		btn.text = BUTTON_LABELS[action]
		btn.custom_minimum_size = Vector2(104, 34)  # 처음엔 72x22로 만들었는데 웹에서 터치하기엔 너무 작았다.
		btn.add_theme_font_size_override("font_size", 15)
		btn.focus_mode = Control.FOCUS_NONE  # 눌러도 텍스트 입력 포커스를 뺏지 않게.
		btn.pressed.connect(_perform_action.bind(action))
		vbox.add_child(btn)


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
