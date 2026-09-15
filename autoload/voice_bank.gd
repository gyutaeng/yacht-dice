extends Node

# 캐릭터 프로필의 voice_map(이벤트 키 -> 파일명 배열)을 읽어서 GameEvents가
# 방출하는 게임 이벤트에 맞는 보이스를 재생하는 autoload.
#
# GameEvents만 구독하고 GameState/Main을 전혀 참조하지 않는다(원칙 5) — 어떤
# 게임 이벤트가 언제 일어났는지만 알면 되고, 그걸 누가 왜 일으켰는지는 몰라도 된다.
# 오디오 디코딩은 전부 AssetLoader를 거친다(원칙 3) — 여기서 FileAccess를 직접 열지 않는다.
#
# 여기서 반응하는 이벤트는 GameEvents.VOICE_EVENTS에 있는 10개뿐이다. 굴림/고정/
# 점수 크기 같은 건 너무 자주 일어나서 보이스 대상에서 빠졌다(SfxBank가 대신
# 효과음으로 반응한다) — 시그널 자체는 여전히 GameEvents에 남아 있다.

const VOICE_CROSSFADE_DURATION := 0.1
const VOICE_FADE_OUT_DB := -40.0

# 게임 시작 인사를 플레이어 순서대로 하나씩 재생하는 사이(1-4C). 이 시퀀스의
# 진행 상황은 Main.gd가 시각 연출(초상 전환)과 입력 차단에 쓴다 - 여기서는
# "언제 누가 인사하고 언제 다 끝났는지"만 알려주고, 화면을 어떻게 할지는
# 전혀 모른다(원칙 5와 같은 정신 - VoiceBank는 오디오만, Main은 화면만).
signal greeting_step_started(player_index: int)
signal greeting_sequence_finished()

# 시퀀스 내부에서만 쓰는 합류 신호 - 한 플레이어의 인사가 "끝났다"고 볼 수
# 있는 경우가 둘이다: 보이스가 자연히 다 재생됐거나(AudioStreamPlayer.finished),
# 사용자가 건너뛰기를 눌렀거나. 둘 다 여기로 모아서 play_greeting_sequence()의
# await 지점 하나만 신경 쓰면 되게 한다.
signal _greeting_advance()

const GREETING_GAP_DURATION := 0.3  # 인사와 인사 사이에 쉬는 시간(초). 바로 이어붙이면 너무 급하게 들린다.

# 이벤트 키별 우선순위. 숫자가 클수록 더 중요하다. 재생 중인 슬롯의 우선순위보다
# 낮은 요청은 무시된다 — 승리 보이스가 다른 소리에 끊기면 안 되므로.
const PRIORITY_ENDING := 100  # common.win, common.lose
const PRIORITY_YACHT := 90
const PRIORITY_SPECIAL_HAND := 80  # 라지 스트레이트/풀 하우스/포카드/보너스
const PRIORITY_ZERO := 60
const PRIORITY_GAME_START := 30
const PRIORITY_TURN_START := 20

# player_slots[player] -> 그 플레이어 전용 AudioStreamPlayer. configure()가
# player_count만큼 만든다. 내 캐릭터와 남의 캐릭터 보이스가 서로 안 끊기고
# 각자 재생되어야 하므로 슬롯을 공유하지 않는다.
var player_slots: Array[AudioStreamPlayer] = []

var _player_profiles: Array[CharacterProfile] = []

# 슬롯별 "지금 재생 중인 소리의 우선순위"(대기 중이면 0).
var _current_priority: Array[int] = []

# _last_played[player][event_key] -> 그 이벤트에서 마지막으로 고른 파일명.
# 같은 파일이 연속으로 두 번 뽑히지 않게 하는 데 쓴다.
var _last_played: Array[Dictionary] = []

var _slot_tweens: Array[Tween] = []

var _event_priority: Dictionary = {}

# 인사 시퀀스 진행 상태. _greeting_current_player는 "지금 대기 중인 슬롯이
# 몇 번 플레이어인지"(대기 중이 아니면 -1) - 건너뛰기가 그 슬롯을 정확히
# 멈추고 정리하는 데 필요하다.
var _greeting_active: bool = false
var _greeting_skip_requested: bool = false
var _greeting_current_player: int = -1


func _ready() -> void:
	_event_priority[GameEvents.Common.WIN] = PRIORITY_ENDING
	_event_priority[GameEvents.Common.LOSE] = PRIORITY_ENDING
	_event_priority[GameEvents.Yacht.YACHT] = PRIORITY_YACHT
	_event_priority[GameEvents.Yacht.LARGE_STRAIGHT] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.FULL_HOUSE] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.FOUR_OF_A_KIND] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.BONUS] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.ZERO] = PRIORITY_ZERO
	_event_priority[GameEvents.Common.GAME_START] = PRIORITY_GAME_START
	_event_priority[GameEvents.Common.TURN_START] = PRIORITY_TURN_START

	GameEvents.turn_started.connect(_on_turn_started)
	GameEvents.special_hand_rolled.connect(_on_special_hand_rolled)
	GameEvents.bonus_achieved.connect(_on_bonus_achieved)
	GameEvents.zero_scored.connect(_on_zero_scored)
	GameEvents.game_ended.connect(_on_game_ended)


## 새 게임을 시작할 때(또는 타이틀로 돌아갈 때 profiles=[]로) Main이 호출한다.
## player_count만큼 슬롯을 새로 만들고 이전 상태(우선순위/마지막 재생 파일/트윈)를 전부 비운다.
func configure(profiles: Array[CharacterProfile]) -> void:
	for i in player_slots.size():
		if _slot_tweens[i] != null and _slot_tweens[i].is_valid():
			_slot_tweens[i].kill()
		player_slots[i].stop()
		player_slots[i].queue_free()

	player_slots.clear()
	_slot_tweens.clear()
	_current_priority.clear()
	_last_played.clear()

	# 이론상 새 게임은 이전 게임의 인사 시퀀스가 끝난 뒤에만 시작되지만,
	# 방어적으로 여기서도 정리한다 - 남아있으면 새 게임의 인사가 시작부터
	# "이미 진행 중"으로 오판될 수 있다.
	_greeting_active = false
	_greeting_skip_requested = false
	_greeting_current_player = -1

	_player_profiles = profiles

	for p in profiles.size():
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.finished.connect(_on_slot_finished.bind(p))
		player_slots.append(player)
		_slot_tweens.append(null)
		_current_priority.append(0)
		_last_played.append({})


## Main.gd가 game_state.start_turn() 직후 딱 한 번 부른다. 플레이어 순서대로
## 인사를 하나씩 재생하고(절대 안 겹침), 매핑이 없는 플레이어는 대기 없이
## 바로 다음으로 건너뛴다. 전원이 매핑이 없으면 await 지점을 한 번도 안
## 거치고 이 함수가 그 자리에서 끝까지 돌아 greeting_sequence_finished를
## 동기적으로 emit한다 - Main.gd가 이 함수를 부르기 직전에 입력 차단을
## 켜놨어도, 같은 프레임 안에서 도로 꺼지므로 화면엔 아예 안 보인다.
func play_greeting_sequence() -> void:
	if _greeting_active:
		return  # 정상적으론 안 일어나지만(한 판에 한 번만 호출됨), 방어적으로.

	_greeting_active = true
	_greeting_skip_requested = false

	var player_count := _player_profiles.size()
	for p in player_count:
		if _greeting_skip_requested:
			break

		if not _play_for_player(p, GameEvents.Common.GAME_START):
			continue  # 매핑 없음 - 대기도, 화면 전환 요청도 없이 바로 다음.

		greeting_step_started.emit(p)
		_greeting_current_player = p
		player_slots[p].finished.connect(_on_greeting_natural_finish, CONNECT_ONE_SHOT)
		await _greeting_advance
		_greeting_current_player = -1

		if _greeting_skip_requested:
			break
		if p < player_count - 1:
			await get_tree().create_timer(GREETING_GAP_DURATION).timeout

	_greeting_active = false
	greeting_sequence_finished.emit()


## 인사 연출 중 건너뛰기 요청. 이미 끝났거나(연출 중이 아님) 이미 건너뛰기
## 요청이 들어온 상태면 아무 것도 안 한다 - 빠르게 두 번 눌러도
## greeting_sequence_finished가 두 번 나가지 않도록 하는 가드.
func request_skip_greeting() -> void:
	if not _greeting_active or _greeting_skip_requested:
		return
	_greeting_skip_requested = true

	if _greeting_current_player != -1:
		var p := _greeting_current_player
		var player := player_slots[p]
		if player.finished.is_connected(_on_greeting_natural_finish):
			player.finished.disconnect(_on_greeting_natural_finish)
		player.stop()
		# AudioStreamPlayer.stop()은 finished를 emit하지 않는다 - 그냥 두면
		# 이 슬롯의 _current_priority가 PRIORITY_GAME_START에 영원히 멈춰
		# 있어서, 건너뛴 뒤로 그 플레이어의 다른 보이스(내 차례 등, 더 낮은
		# 우선순위)가 전부 조용히 무시되는 버그가 된다. finished가 했을 일을
		# 직접 해준다.
		_on_slot_finished(p)
		_greeting_current_player = -1

	_greeting_advance.emit()


func _on_greeting_natural_finish() -> void:
	_greeting_advance.emit()


func _on_turn_started(player_index: int) -> void:
	_play_for_player(player_index, GameEvents.Common.TURN_START)


func _on_special_hand_rolled(player_index: int, category: int, _points: int) -> void:
	var key := event_key_for_category(category)
	if key != "":
		_play_for_player(player_index, key)


func _on_bonus_achieved(player_index: int) -> void:
	_play_for_player(player_index, GameEvents.Yacht.BONUS)


# 야추 칸을 0점으로 포기할 때만 반응한다. 다른 칸의 0점은 흔한 일이라 무시한다.
func _on_zero_scored(player_index: int, category: int) -> void:
	if category == GameState.YACHT_CATEGORY_INDEX:
		_play_for_player(player_index, GameEvents.Yacht.ZERO)


func _on_game_ended(winners: Array[int], scores: Array[int]) -> void:
	if _player_profiles.is_empty():
		return
	var pick := pick_win_lose_players(winners, scores)
	_play_game_end_sequence(pick.winner, pick.loser)


func _on_slot_finished(player_index: int) -> void:
	if player_index < _current_priority.size():
		_current_priority[player_index] = 0


## GameState.SPECIAL_HAND_PRIORITY에 있는 카테고리 인덱스를 보이스 이벤트 키로 옮긴다.
## 그 네 개가 아니면(폴백으로 다른 항목이 올 일은 없지만 방어적으로) "".
func event_key_for_category(category: int) -> String:
	match category:
		GameState.YACHT_CATEGORY_INDEX:
			return GameEvents.Yacht.YACHT
		GameState.LARGE_STRAIGHT_CATEGORY_INDEX:
			return GameEvents.Yacht.LARGE_STRAIGHT
		GameState.FULL_HOUSE_CATEGORY_INDEX:
			return GameEvents.Yacht.FULL_HOUSE
		GameState.FOUR_OF_A_KIND_CATEGORY_INDEX:
			return GameEvents.Yacht.FOUR_OF_A_KIND
	return ""


## winners/scores로부터 승리 보이스를 재생할 플레이어(랜덤 하나)와 패배 보이스를
## 재생할 플레이어(최하위 점수 중 랜덤 하나)를 고른다. 전원 동점(winners 크기가
## 인원수와 같음)이면 진 사람이 없으므로 loser=-1. 실제 재생/순서는
## _play_game_end_sequence()가 맡는다 — 이 함수는 "누구를 고를지"만 결정한다.
func pick_win_lose_players(winners: Array[int], scores: Array[int]) -> Dictionary:
	var winner: int = winners[randi() % winners.size()]

	if winners.size() == scores.size():
		return {"winner": winner, "loser": -1}

	var lowest: int = scores[0]
	for s in scores:
		lowest = min(lowest, s)
	var losers: Array[int] = []
	for p in scores.size():
		if scores[p] == lowest:
			losers.append(p)

	return {"winner": winner, "loser": losers[randi() % losers.size()]}


# 승리 보이스와 패배 보이스는 절대 겹치면 안 된다(순차 재생). 승리 보이스가
# 실제로 재생을 시작했으면 그 슬롯이 자연히 끝날 때(finished)까지 기다렸다가
# 패배 보이스를 재생하고, 매핑이 없어 시작조차 안 됐으면 곧바로 넘어간다.
# winner_index와 loser_index는 승부가 갈린 이상(all-tied가 아닌 이상) 항상
# 서로 다른 플레이어이므로 서로 다른 슬롯을 쓴다 — 자기 자신을 끊을 일이 없다.
func _play_game_end_sequence(winner_index: int, loser_index: int) -> void:
	var win_started := _play_for_player(winner_index, GameEvents.Common.WIN)

	if loser_index == -1:
		return

	if win_started:
		player_slots[winner_index].finished.connect(
			func() -> void: _play_for_player(loser_index, GameEvents.Common.LOSE),
			CONNECT_ONE_SHOT
		)
	else:
		_play_for_player(loser_index, GameEvents.Common.LOSE)


## candidates 중 하나를 무작위로 고르되, last_played와 같은 파일은(후보가 2개
## 이상일 때) 이번엔 피한다. candidates가 비어 있으면 "".
func pick_voice_file(candidates: Array, last_played: String) -> String:
	if candidates.is_empty():
		return ""
	if candidates.size() == 1:
		return candidates[0]

	var pool: Array = candidates
	if last_played != "":
		pool = candidates.filter(func(f): return f != last_played)
		if pool.is_empty():
			pool = candidates

	return pool[randi() % pool.size()]


## 실제로 재생을 시작했으면 true, (매핑 없음/우선순위 낮음/파일 로딩 실패 등으로)
## 아무 일도 안 했으면 false를 반환한다 — 승패 보이스 순차 재생에서 "재생이
## 시작됐는지"를 판단하는 데 쓴다.
func _play_for_player(player_index: int, event_key: String) -> bool:
	if event_key == "" or player_index < 0 or player_index >= player_slots.size():
		return false

	var profile: CharacterProfile = _player_profiles[player_index] if player_index < _player_profiles.size() else null
	if profile == null:
		return false

	var candidates: Array = profile.voice_map.get(event_key, [])
	if candidates.is_empty():
		return false  # 매핑이 없으면 조용히 무시한다. 캐릭터가 모든 이벤트에 보이스를 두지는 않는다.

	var priority: int = _event_priority.get(event_key, 0)
	if priority < _current_priority[player_index]:
		return false  # 재생 중인 보이스보다 우선순위가 낮은 요청은 무시.

	var last: String = _last_played[player_index].get(event_key, "")
	var filename := pick_voice_file(candidates, last)
	if filename == "":
		return false
	_last_played[player_index][event_key] = filename

	var stream := CharacterLibrary.load_profile_audio(profile, filename)
	if stream == null:
		return false

	_replace_slot_voice(player_index, stream, priority)
	return true


func _replace_slot_voice(player_index: int, stream: AudioStream, priority: int) -> void:
	var player := player_slots[player_index]

	if _slot_tweens[player_index] != null and _slot_tweens[player_index].is_valid():
		_slot_tweens[player_index].kill()
		player.volume_db = 0.0  # 진행 중이던 페이드를 죽였으니 기준 볼륨으로 되돌려둔다.

	if player.playing:
		var fade := create_tween()
		fade.tween_property(player, "volume_db", VOICE_FADE_OUT_DB, VOICE_CROSSFADE_DURATION)
		fade.tween_callback(func() -> void:
			player.stop()
			player.volume_db = 0.0
			player.stream = stream
			player.play())
		_slot_tweens[player_index] = fade
	else:
		player.stream = stream
		player.play()

	_current_priority[player_index] = priority
