extends Node

# ============================================================
# 개발용 단축키 — 정식 빌드에는 절대 들어가면 안 된다.
# BuildInfo.DEBUG_MODE가 false면 _ready()도 _input()도 아무 것도 안 해서,
# 키보드 단축키도 화면의 디버그 버튼도 전혀 안 나타난다. 노드 자체는 지우지
# 않고 그대로 트리에 남겨둔다 - Main.gd가 @onready로 들고 있는 참조가 나중에
# (예: greeting_active 갱신) 계속 유효해야 하기 때문이다. 에디터냐 export냐는
# 안 따진다 - DEBUG_MODE 하나로 통일했다(build_info.gd 참고). 정식 배포
# 전에는 반드시 그 값을 false로 되돌릴 것.
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
# Ctrl+Shift+S : 현재 플레이어 대신 GameState.auto_confirm_least_damaging()이
#                고른 가장 손해가 적은 칸을 즉시 확정하고 턴을 넘긴다(안
#                굴렸으면 한 번만 굴린 뒤 판단 - 자세한 기준은 그 함수의
#                문서 주석과 docs/multiplayer.md §6 참고).
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

# CharacterLimits는 이 파일 작성 시점에 막 추가된 class_name이라, 전역 스크립트
# 클래스 캐시가 아직 못 봤을 수 있는 배포 환경을 대비해 preload로 직접 참조한다.
const CharacterLimitsScript = preload("res://scripts/characters/character_limits.gd")

var game_state: GameState

# 자동 진행 중인지. Main.gd가 이 플래그를 보고 special_hand_rolled 연출을
# 건너뛴다 — 안 그러면 48턴짜리 자동 진행이 매번 1.5초씩 멈춰서 너무 느려진다.
var is_auto_playing: bool = false

# 반대 방향 플래그 - Main.gd가 게임 시작 인사 연출(1-4C) 중에 true로 세팅한다.
# DEBUG_MODE가 켜진 채로 테스트하는 동안 인사 연출 중 실수로 [끝까지 진행]
# 등을 눌러서 게임 상태가 연출과 어긋나게 꼬이는 걸 막는다 - 그런 상태를
# 진짜 버그로 착각하기 쉽다.
var greeting_active: bool = false

var _cache_stats_label: Label

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
		return
	_build_debug_button_panel()


func _input(event: InputEvent) -> void:
	# 예전엔 DEBUG_MODE가 false면 이 노드 자체를 queue_free()했는데, Main.gd가
	# 들고 있는 @onready var debug_hotkeys 참조가 그 뒤로도 살아있어서(같은
	# 프레임 안에서는 아직 안 지워짐) 나중에 그 참조를 건드리면(예:
	# is_auto_playing 읽기) "이미 해제된 인스턴스" 오류가 날 수 있었다 -
	# DEBUG_MODE=false 조합이 이번 세션 내내 한 번도 실제로 테스트된 적이
	# 없어서 잠복해 있던 버그다. 이제는 노드를 지우지 않고 그냥 아무 것도
	# 안 하게만 만든다 - 참조는 항상 유효하게 남는다.
	if not BuildInfo.DEBUG_MODE:
		return
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
	if greeting_active:
		print("[디버그] 게임 시작 인사 연출 중이라 무시함 - %s" % action)
		return

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

	# AssetLoader의 디코딩 캐시가 실제로 얼마나 찼는지 눈으로 보기 위한
	# 표시. 캐릭터를 여러 개 바꿔가며 볼 때(1-8 웹 테스트) 메모리 상한
	# 조정이 필요한지 실측하려고 넣었다 - 1초마다 갱신하면 충분하다
	# (매 프레임 갱신할 이유가 없음).
	_cache_stats_label = Label.new()
	_cache_stats_label.add_theme_font_size_override("font_size", 12)
	_cache_stats_label.modulate = Color(1.0, 1.0, 0.6)
	vbox.add_child(_cache_stats_label)
	_update_cache_stats_label()

	var stats_timer := Timer.new()
	stats_timer.wait_time = 1.0
	stats_timer.autostart = true
	stats_timer.timeout.connect(_update_cache_stats_label)
	add_child(stats_timer)

	for action: String in KEY_ACTIONS.values():
		var btn := Button.new()
		btn.text = BUTTON_LABELS[action]
		btn.custom_minimum_size = Vector2(104, 34)  # 처음엔 72x22로 만들었는데 웹에서 터치하기엔 너무 작았다.
		btn.add_theme_font_size_override("font_size", 15)
		btn.focus_mode = Control.FOCUS_NONE  # 눌러도 텍스트 입력 포커스를 뺏지 않게.
		btn.pressed.connect(_perform_action.bind(action))
		vbox.add_child(btn)


func _update_cache_stats_label() -> void:
	var stats := AssetLoader.get_cache_stats()
	_cache_stats_label.text = "캐시: 이미지 %d개/%s, 오디오 %d개/%s" % [
		stats["texture_count"], CharacterLimitsScript.format_bytes(stats["texture_bytes"]),
		stats["audio_count"], CharacterLimitsScript.format_bytes(stats["audio_bytes"]),
	]


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


## 어느 칸을 고를지의 판단(가장 손해가 적은 칸, 안 굴렸으면 한 번만 굴리는
## 것 포함)은 전부 GameState.auto_confirm_least_damaging()에 있다 - 여기서는
## 그 함수를 부르기만 한다. docs/multiplayer.md §6에서 정한 대로, 이 판단
## 로직이 DEBUG_MODE 뒤에 숨어 있으면 정식 출시 때 DEBUG_MODE를 false로
## 되돌리는 순간 서버의 AFK 자동 진행까지 같이 죽어버리므로, 절대 이
## 파일에 로직 본체를 두면 안 된다.
func _auto_confirm_one() -> void:
	game_state.auto_confirm_least_damaging(game_state.current_player)


func _auto_finish_game() -> void:
	is_auto_playing = true
	while not game_state.game_over:
		var category := game_state.auto_confirm_least_damaging(game_state.current_player)
		if category == -1:
			break  # 정상 상태라면 도달 안 함 - 무한 루프 방지용 방어 코드.
	is_auto_playing = false
