class_name LocalGameController
extends RefCounted

# 게임 화면(scenes/Main.gd)이 방출하는 의도를 실제로 실행하는 "로컬" 백엔드.
# OnlineGameController(scripts/game/online_game_controller.gd)와 같은 이름의
# 메서드(request_roll/request_hold/request_score/is_request_pending/
# leave_game)를 갖는 덕타이핑 계약이다 - 이 프로젝트에는 추상 인터페이스
# 클래스 선례가 없어서 별도 기반 클래스를 만들지 않았다. Main.gd는 어느
# 컨트롤러가 붙어 있는지 모르고 이 메서드들만 부른다("리모컨" 패턴).
#
# 로컬은 서버가 없으므로 요청이 곧바로 GameState를 직접 진행시킨다 -
# 네트워크 왕복이 없어 연타 방지(is_request_pending)도 필요 없다.

var game_state: GameState
var my_player_index: int = -1  # 로컬은 전원이 한 화면을 같이 쓰므로 턴 제한이 없다


func start(player_count: int) -> void:
	game_state = GameState.new(player_count)


func request_roll() -> void:
	game_state.roll()


func request_hold(index: int) -> void:
	game_state.toggle_lock(index)


func request_score(category: int) -> void:
	game_state.confirm_category(category)


func is_request_pending() -> bool:
	return false


func leave_game() -> void:
	pass  # 나갈 서버가 없다.
