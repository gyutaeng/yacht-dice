class_name OnlineGameController
extends RefCounted

# 게임 화면(scenes/Main.gd)이 방출하는 의도를 서버로 전송하는 "온라인"
# 백엔드. LocalGameController(scripts/game/local_game_controller.gd)와 같은
# 이름의 메서드(request_roll/request_hold/request_score/is_request_pending/
# leave_game)를 갖는 덕타이핑 계약이다 - Main.gd는 어느 컨트롤러가 붙어
# 있는지 모르고 이 메서드들만 부른다("리모컨" 패턴).
#
# game_state는 read_only GameState 사본이다 - 화면은 이걸 그대로 읽어서
# 그리기만 하고(docs/multiplayer.md §1), 실제 진행은 서버의 응답
# (state_snapshot_received)이 apply_snapshot()으로 채워준다. 절대 이
# game_state에 roll()/toggle_lock()/confirm_category()를 직접 호출하지
# 않는다 - read_only 가드가 있어 호출해도 push_error로 끝나지만,애초에
# 이 클래스는 그럴 필요가 없게 설계됐다.

var game_state: GameState
var my_player_index: int = -1

var _client: GameClient
var _request_pending: bool = false


func _init(client: GameClient, player_count: int, my_index: int) -> void:
	_client = client
	my_player_index = my_index
	game_state = GameState.new(player_count, null, true)

	_client.state_snapshot_received.connect(_on_state_snapshot_received)
	_client.server_error.connect(_on_server_error)

	# 서버가 GameEvents에 해당하는 사건을 보내오면 자기 로컬 GameEvents에
	# 그대로 다시 emit한다(문서 §1) - VoiceBank/SfxBank/CharacterStage/
	# 특수 족보 연출이 로컬이든 온라인이든 같은 시그널만 구독하면 되게
	# 하기 위함이다. 순서는 서버가 스냅샷을 먼저, 이벤트를 나중에 보내고
	# (server_main.gd) 패킷은 도착 순서대로 처리되므로, 여기서 별도로
	# 순서를 맞출 필요가 없다. 어느 GameEvents 시그널이 여기 있어야
	# 하는지는 scripts/net/game_event_relay.gd의 RELAYED_EVENTS가 기준이다
	# (2-4C - "게임에서 일어난 사건은 전부 전달한다").
	_client.dice_rolled.connect(func(p, v, r): GameEvents.dice_rolled.emit(p, v, r))
	_client.die_held_changed.connect(func(p, i, held): GameEvents.die_held_changed.emit(p, i, held))
	_client.special_hand_rolled.connect(func(p, c, pts): GameEvents.special_hand_rolled.emit(p, c, pts))
	_client.score_committed.connect(func(p, c, pts): GameEvents.score_committed.emit(p, c, pts))
	_client.yacht_scored.connect(func(p): GameEvents.yacht_scored.emit(p))
	_client.zero_scored.connect(func(p, c): GameEvents.zero_scored.emit(p, c))
	_client.bonus_achieved.connect(func(p): GameEvents.bonus_achieved.emit(p))
	_client.turn_ended.connect(func(p): GameEvents.turn_ended.emit(p))
	_client.turn_started.connect(func(p): GameEvents.turn_started.emit(p))
	_client.game_ended.connect(func(w, s): GameEvents.game_ended.emit(w, s))
	# game_state_started -> GameEvents.game_started로 이름이 바뀐다(로비
	# 종료 game_started와 겹치지 않게 네트워크 메시지 이름만 다르게 뒀을
	# 뿐, 로컬 GameEvents로 다시 emit할 때는 원래 이름을 그대로 쓴다).
	# 지금은 이 신호를 구독하는 로컬 코드가 없다(인사 연출은 Main.gd의
	# _enter_game()이 직접 호출) - "구독자가 없어서 생략"은 안 된다는
	# 규칙이라 그래도 릴레이한다.
	_client.game_state_started.connect(func(pc): GameEvents.game_started.emit(pc))


func request_roll() -> void:
	if _request_pending:
		return
	_request_pending = true
	_client.request_roll()


func request_hold(index: int) -> void:
	if _request_pending:
		return
	_request_pending = true
	_client.request_hold(index)


func request_score(category: int) -> void:
	if _request_pending:
		return
	_request_pending = true
	_client.request_score(category)


func is_request_pending() -> bool:
	return _request_pending


func leave_game() -> void:
	_client.leave()


## 2-4의 "리모컨" 구조 유지(사용자 지적) - 게임 종료 화면이 직접 온라인
## 여부를 몰라도 되도록, "이 화면에서 가능한 행동"을 여기서 정해서
## 넘겨준다. 온라인은 2-6B의 같은 방 재대전("한 판 더" - 전원이 눌러야
## 다음 판이 시작됨)과, 나가면 남은 사람에게 알려지는 "나가기"(leave_game()이
## 그대로 처리) 둘이다.
func get_game_over_actions() -> Array:
	return [
		{"id": "rematch", "label": "한 판 더"},
		{"id": "leave", "label": "나가기"},
	]


func _on_state_snapshot_received(snapshot: Dictionary) -> void:
	_request_pending = false
	game_state.apply_snapshot(snapshot)


## 에러든 정상 응답이든 다음 시도를 막으면 안 되므로 여기서도 풀어준다 -
## 서버가 거부한 요청은 다음 state_snapshot이 안 오기 때문에, snapshot
## 수신에만 기대면 연타 방지 플래그가 영원히 안 풀릴 수 있다.
func _on_server_error(_code: String, _message: String) -> void:
	_request_pending = false
