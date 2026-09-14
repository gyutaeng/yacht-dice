extends Node

# 캐릭터 프로필의 voice_map(이벤트 키 -> 파일명 배열)을 읽어서 GameEvents가
# 방출하는 게임 이벤트에 맞는 보이스를 재생하는 autoload.
#
# GameEvents만 구독하고 GameState/Main을 전혀 참조하지 않는다(원칙 5) — 어떤
# 게임 이벤트가 언제 일어났는지만 알면 되고, 그걸 누가 왜 일으켰는지는 몰라도 된다.
# 오디오 디코딩은 전부 AssetLoader를 거친다(원칙 3) — 여기서 FileAccess를 직접 열지 않는다.

const VOICE_CROSSFADE_DURATION := 0.1
const VOICE_FADE_OUT_DB := -40.0

# score_committed의 점수로 "큰 점수"/"작은 점수" 보이스를 가를 기준.
# 0점은 여기 안 걸리게 SMALL_SCORE_THRESHOLD보다 크다는 조건을 따로 둔다
# (0점은 zero_scored가 전담 — 안 그러면 0점 확정마다 SMALL_SCORE와 ZERO가
# 동시에 요청되어 우선순위 싸움이 생긴다).
const BIG_SCORE_THRESHOLD := 25
const SMALL_SCORE_THRESHOLD := 5

# 이벤트 키별 우선순위. 숫자가 클수록 더 중요하다. 재생 중인 슬롯의 우선순위보다
# 낮은 요청은 무시된다 — 승리 보이스가 주사위 굴리는 소리에 끊기면 안 되므로.
const PRIORITY_HIGH := 100
const PRIORITY_SPECIAL_HAND := 80
const PRIORITY_SCORE := 60
const PRIORITY_SMALL_SCORE := 40
const PRIORITY_TURN_START := 20
const PRIORITY_AMBIENT := 10

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


func _ready() -> void:
	_event_priority[GameEvents.Common.WIN] = PRIORITY_HIGH
	_event_priority[GameEvents.Common.LOSE] = PRIORITY_HIGH
	_event_priority[GameEvents.Yacht.YACHT] = PRIORITY_HIGH
	_event_priority[GameEvents.Yacht.LARGE_STRAIGHT] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.FULL_HOUSE] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.FOUR_OF_A_KIND] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.BONUS] = PRIORITY_SPECIAL_HAND
	_event_priority[GameEvents.Yacht.ZERO] = PRIORITY_SCORE
	_event_priority[GameEvents.Yacht.BIG_SCORE] = PRIORITY_SCORE
	_event_priority[GameEvents.Yacht.SMALL_SCORE] = PRIORITY_SMALL_SCORE
	_event_priority[GameEvents.Common.TURN_START] = PRIORITY_TURN_START
	_event_priority[GameEvents.Yacht.ROLL] = PRIORITY_AMBIENT
	_event_priority[GameEvents.Yacht.REROLL] = PRIORITY_AMBIENT
	_event_priority[GameEvents.Yacht.HOLD] = PRIORITY_AMBIENT

	# score_previewed는 절대 구독하지 않는다 — 한 번 굴릴 때마다 미확정 항목 수만큼
	# 방출되므로, 구독하면 캐릭터가 쉴 새 없이 떠들게 된다.
	GameEvents.turn_started.connect(_on_turn_started)
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.die_held_changed.connect(_on_die_held_changed)
	GameEvents.special_hand_rolled.connect(_on_special_hand_rolled)
	GameEvents.bonus_achieved.connect(_on_bonus_achieved)
	GameEvents.score_committed.connect(_on_score_committed)
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

	_player_profiles = profiles

	for p in profiles.size():
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.finished.connect(_on_slot_finished.bind(p))
		player_slots.append(player)
		_slot_tweens.append(null)
		_current_priority.append(0)
		_last_played.append({})


func _on_turn_started(player_index: int) -> void:
	_play_for_player(player_index, GameEvents.Common.TURN_START)


func _on_dice_rolled(player_index: int, _values: Array[int], reroll_left: int) -> void:
	var is_first_roll := reroll_left == GameState.MAX_ROLLS_PER_TURN - 1
	var key := GameEvents.Yacht.ROLL if is_first_roll else GameEvents.Yacht.REROLL
	_play_for_player(player_index, key)


func _on_die_held_changed(player_index: int, _index: int, _held: bool) -> void:
	_play_for_player(player_index, GameEvents.Yacht.HOLD)


func _on_special_hand_rolled(player_index: int, category: int, _points: int) -> void:
	var key := event_key_for_category(category)
	if key != "":
		_play_for_player(player_index, key)


func _on_bonus_achieved(player_index: int) -> void:
	_play_for_player(player_index, GameEvents.Yacht.BONUS)


func _on_score_committed(player_index: int, _category: int, points: int) -> void:
	var key := classify_score_event(points)
	if key != "":
		_play_for_player(player_index, key)


func _on_zero_scored(player_index: int, _category: int) -> void:
	_play_for_player(player_index, GameEvents.Yacht.ZERO)


# 게임 종료는 플레이어별 이벤트가 아니라 한 번만 emit되므로, 슬롯을 전부 돌면서
# 승자/패자 보이스를 각자 튼다 — 끝나는 순간 캐릭터들이 다같이 반응하는 게 자연스럽다.
func _on_game_ended(winners: Array[int], _scores: Array[int]) -> void:
	for p in _player_profiles.size():
		var key := GameEvents.Common.WIN if winners.has(p) else GameEvents.Common.LOSE
		_play_for_player(p, key)


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


## 확정 점수를 "큰 점수"/"작은 점수" 보이스 이벤트 키로 분류한다. 어느 쪽에도
## 안 걸리면(중간 점수, 또는 0점) "".
func classify_score_event(points: int) -> String:
	if points >= BIG_SCORE_THRESHOLD:
		return GameEvents.Yacht.BIG_SCORE
	if points > 0 and points <= SMALL_SCORE_THRESHOLD:
		return GameEvents.Yacht.SMALL_SCORE
	return ""


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


func _play_for_player(player_index: int, event_key: String) -> void:
	if event_key == "" or player_index < 0 or player_index >= player_slots.size():
		return

	var profile: CharacterProfile = _player_profiles[player_index] if player_index < _player_profiles.size() else null
	if profile == null:
		return

	var candidates: Array = profile.voice_map.get(event_key, [])
	if candidates.is_empty():
		return  # 매핑이 없으면 조용히 무시한다. 캐릭터가 모든 이벤트에 보이스를 두지는 않는다.

	var priority: int = _event_priority.get(event_key, 0)
	if priority < _current_priority[player_index]:
		return  # 재생 중인 보이스보다 우선순위가 낮은 요청은 무시.

	var last: String = _last_played[player_index].get(event_key, "")
	var filename := pick_voice_file(candidates, last)
	if filename == "":
		return
	_last_played[player_index][event_key] = filename

	var base_dir := CharacterLibrary.BUILTIN_FALLBACK_PATH if profile.is_builtin else CharacterLibrary.CHARACTERS_DIR.path_join(profile.id)
	var stream := AssetLoader.load_audio_from_path(base_dir.path_join(filename))
	if stream == null:
		return

	_replace_slot_voice(player_index, stream, priority)


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
