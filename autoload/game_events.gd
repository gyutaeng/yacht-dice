extends Node

# GameState가 방출하는 게임 이벤트를 받아서 UI/사운드/캐릭터 연출 등
# 서로 모르는 여러 구독자에게 전달하는 중앙 신호 버스.
# GameState는 이 시그널만 emit하고, 누가 듣는지는 전혀 모른다.
# Node를 상속하는 이유는 autoload 등록 요건 때문일 뿐, 씬 트리 기능은 쓰지 않는다.

signal turn_started(player_index: int)
signal dice_rolled(values: Array[int], reroll_left: int)
signal die_held_changed(index: int, held: bool)
signal score_previewed(category: int, points: int)
signal score_committed(player_index: int, category: int, points: int)
signal yacht_scored(player_index: int)
signal zero_scored(player_index: int, category: int)
signal bonus_achieved(player_index: int)
signal turn_ended(player_index: int)
signal game_ended(winners: Array[int], scores: Array[int])

# 캐릭터 보이스 매핑용 문자열 키. 시그널 이름과 1:1로 맞출 필요는 없고,
# "무슨 일이 일어났는지"를 게임 종류와 무관한 공통 어휘로 찾기 위한 것이다.
# 같은 캐릭터 팩이 요트다이스/마작 양쪽에서 다 동작하려면 게임별 네임스페이스가 필요하다.
const Common := {
	TURN_START = "common.turn_start",
	WIN = "common.win",
	LOSE = "common.lose",
}

const Yacht := {
	ROLL = "yacht.roll",
	REROLL = "yacht.reroll",
	HOLD = "yacht.hold",
	YACHT = "yacht.yacht",
	BIG_SCORE = "yacht.big_score",
	SMALL_SCORE = "yacht.small_score",
	ZERO = "yacht.zero",
	BONUS = "yacht.bonus",
}

# 리치마작을 붙일 때 여기에 Mahjong := { RIICHI = "mahjong.riichi", ... } 를 추가한다.
