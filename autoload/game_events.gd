extends Node

# GameState가 방출하는 게임 이벤트를 받아서 UI/사운드/캐릭터 연출 등
# 서로 모르는 여러 구독자에게 전달하는 중앙 신호 버스.
# GameState는 이 시그널만 emit하고, 누가 듣는지는 전혀 모른다.
# Node를 상속하는 이유는 autoload 등록 요건 때문일 뿐, 씬 트리 기능은 쓰지 않는다.

signal game_started(player_count: int)
signal turn_started(player_index: int)
signal dice_rolled(player_index: int, values: Array[int], reroll_left: int)
signal die_held_changed(player_index: int, index: int, held: bool)
signal score_previewed(category: int, points: int)
signal score_committed(player_index: int, category: int, points: int)
signal yacht_scored(player_index: int)
signal zero_scored(player_index: int, category: int)
signal bonus_achieved(player_index: int)
signal turn_ended(player_index: int)
signal game_ended(winners: Array[int], scores: Array[int])

# 주사위를 굴린 "직후"(확정 시점이 아니라) 좋은 족보가 성립하면 방출된다.
# 연출/보이스 양쪽이 이 시그널 하나만 구독하면 되고, 어느 쪽도 서로를 몰라야 한다.
signal special_hand_rolled(player_index: int, category: int, points: int)

# 캐릭터 보이스 매핑용 문자열 키. 시그널 이름과 1:1로 맞출 필요는 없고,
# "무슨 일이 일어났는지"를 게임 종류와 무관한 공통 어휘로 찾기 위한 것이다.
# 같은 캐릭터 팩이 요트다이스/마작 양쪽에서 다 동작하려면 게임별 네임스페이스가 필요하다.
const Common := {
	GAME_START = "common.game_start",
	TURN_START = "common.turn_start",
	WIN = "common.win",
	LOSE = "common.lose",
}

const Yacht := {
	YACHT = "yacht.yacht",
	FOUR_OF_A_KIND = "yacht.four_of_a_kind",
	FULL_HOUSE = "yacht.full_house",
	LARGE_STRAIGHT = "yacht.large_straight",
	ZERO = "yacht.zero",
	BONUS = "yacht.bonus",
}

# 리치마작을 붙일 때 여기에 Mahjong := { RIICHI = "mahjong.riichi", ... } 를 추가한다.

# 1-6 캐릭터 편집 UI가 이 테이블을 그대로 읽어서 보이스 매핑 행을 자동 생성한다.
# "key"는 위 Common/Yacht 값과 정확히 같아야 하고(test_voice_bank.gd가 이 일치를
# 검증한다), 순서는 UI에 표시될 순서다. 실제로 보이스를 붙일 수 있는 이벤트만
# 여기 올린다 — yacht.roll/hold처럼 너무 자주 울리는 건 GameEvents 시그널은
# 남아 있어도 이 테이블에서는 뺐다(효과음/연출 전용으로만 쓰임).
const VOICE_EVENTS := [
	{
		"key": Common.GAME_START,
		"label": "게임 시작 인사",
		"description": "게임이 시작되고 첫 턴이 시작되기 전, 한 판에 한 번만 재생됩니다.",
	},
	{
		"key": Common.TURN_START,
		"label": "내 차례",
		"description": "자기 차례가 되었을 때 재생됩니다.",
	},
	{
		"key": Common.WIN,
		"label": "승리",
		"description": "게임에서 1등으로 이겼을 때 재생됩니다.",
	},
	{
		"key": Common.LOSE,
		"label": "패배",
		"description": "게임에서 최하위 점수로 졌을 때 재생됩니다.",
	},
	{
		"key": Yacht.YACHT,
		"label": "야추",
		"description": "주사위를 굴려 야추(같은 눈 5개)가 나왔을 때 재생됩니다.",
	},
	{
		"key": Yacht.LARGE_STRAIGHT,
		"label": "라지 스트레이트",
		"description": "주사위를 굴려 라지 스트레이트가 나왔을 때 재생됩니다.",
	},
	{
		"key": Yacht.FULL_HOUSE,
		"label": "풀 하우스",
		"description": "주사위를 굴려 풀 하우스가 나왔을 때 재생됩니다.",
	},
	{
		"key": Yacht.FOUR_OF_A_KIND,
		"label": "포 카드",
		"description": "주사위를 굴려 포 카드(같은 눈 4개 이상)가 나왔을 때 재생됩니다.",
	},
	{
		"key": Yacht.BONUS,
		"label": "상단 보너스",
		"description": "상단 섹션 합계 63점을 넘겨 보너스를 처음 달성했을 때 재생됩니다.",
	},
	{
		"key": Yacht.ZERO,
		"label": "야추 포기",
		"description": "야추 칸을 0점으로 포기할 때 재생됩니다. 다른 칸을 0점으로 확정할 때는 재생되지 않습니다.",
	},
]
