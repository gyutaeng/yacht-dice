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

const GREETING_GAP_DURATION := 0.3  # 인사와 인사 사이에 쉬는 시간(초). 바로 이어붙이면 너무 급하게 들린다.

# 인사/보이스 요청이 대기열에서 버려지기까지 최대로 기다리는 시간(밀리초).
# 넘기면 재생 안 하고 버린다 - 때를 놓친 대사("이미 주사위를 굴린 뒤에
# 나오는 내 차례!")는 안 하는 게 낫다. 실제로 들어보고 조정할 값이라 상수로 뺐다.
const VOICE_WAIT_TIMEOUT_MSEC := 1500

# 이벤트 키별 우선순위. 숫자가 클수록 더 중요하다. 전역으로 딱 하나만
# 재생되므로(아래 _global_active_* 참고), 이 값은 슬롯이 아니라 시스템
# 전체에서 "지금 나는 소리보다 이게 더 중요한가"를 판단하는 데 쓴다.
const PRIORITY_ENDING := 100  # common.win, common.lose
const PRIORITY_YACHT := 90
const PRIORITY_SPECIAL_HAND := 80  # 라지 스트레이트/풀 하우스/포카드/보너스
const PRIORITY_ZERO := 60
const PRIORITY_GAME_START := 30
const PRIORITY_TURN_START := 20

# player_slots[player] -> 그 플레이어 전용 AudioStreamPlayer. configure()가
# player_count만큼 만든다. 슬롯 자체는 캐릭터별 볼륨(profile.volume_db)을
# 쓰기 위해 플레이어별로 유지하지만, 실제로 소리를 낼 수 있는 슬롯은
# 전역으로 한 번에 하나뿐이다(아래 _global_active_player) - 그래야 서로
# 다른 플레이어의 보이스가 겹치지 않는다.
var player_slots: Array[AudioStreamPlayer] = []

var _player_profiles: Array[CharacterProfile] = []

# _last_played[player][event_key] -> 그 이벤트에서 마지막으로 고른 파일명.
# 같은 파일이 연속으로 두 번 뽑히지 않게 하는 데 쓴다.
var _last_played: Array[Dictionary] = []

var _slot_tweens: Array[Tween] = []

var _event_priority: Dictionary = {}

# ============================================================
# 전역 재생 상태. 어느 슬롯이든 실제로 소리 내는 건 한 번에 하나뿐이라는
# 규칙을 여기 세 변수가 전부 표현한다.
#
# _global_active_player: 지금 실제로(또는 방금 교체가 결정된 채로 페이드
# 전환 중) 소리 내고 있는 슬롯. 아무도 안 낼 때 -1.
# _global_active_priority: 그 소리의 우선순위 - 새 요청과 비교하는 기준.
# _pending_request: 대기 하나(그 이상은 안 둠). 재생 중인 것보다 우선순위가
# 같거나 낮은 요청이 여기 들어오고, 재생 중인 게 끝나는 순간에만 소비된다
# (그 순간 나이가 VOICE_WAIT_TIMEOUT_MSEC을 넘었으면 재생 안 하고 버림).
# 대기 중에 또 요청이 오면 우선순위가 더 높은 쪽만 남긴다.
# ============================================================
var _global_active_player: int = -1
var _global_active_priority: int = 0
var _pending_request: Dictionary = {}

# ============================================================
# 시퀀스(인사/승패) 진행 상태. 재생 자체는 전부 _request_voice() 하나를
# 거치고, AudioStreamPlayer.finished 구독도 configure()의 _on_slot_finished
# 한 곳뿐이다 - 시퀀스는 "지금 몇 번째 단계인지"만 들고 있다가, 자기 단계가
# 끝났다는 걸 _on_slot_finished로부터 통보받으면 다음 단계를 요청한다.
# 이렇게 하나로 모아두면(원래는 일반 요청/인사/승패가 각자 finished를
# 구독해서 셋이 따로 놀았다) 게임이 끝나는 순간처럼 여러 경로가 동시에
# 반응할 수 있는 상황에서도 항상 하나의 순서로만 처리된다.
#
# 인사는 플레이어 0..N-1을 순서대로 도니까 "몇 번째 단계"가 곧 "플레이어
# 번호"라 _greeting_step_index 하나로 충분하다. 승패는 승자/패자가 어느
# 플레이어인지 무작위로 정해지므로 _ending_steps(순서 목록)가 따로 필요하다.
# ============================================================
var _greeting_active: bool = false
var _greeting_skip_requested: bool = false
var _greeting_step_index: int = -1

var _ending_steps: Array = []  # [{"player": int, "event_key": String}, ...]
var _ending_step_index: int = -1
var _ending_step_player: int = -1  # 지금 이 시퀀스가 기다리고 있는 플레이어(없으면 -1).


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
	_last_played.clear()

	# 이론상 새 게임은 이전 게임의 시퀀스/대기가 전부 끝난 뒤에만 시작되지만,
	# 방어적으로 여기서도 정리한다 - 남아있으면 새 게임 시작부터 "이미 뭔가
	# 재생/진행 중"으로 오판될 수 있다.
	_global_active_player = -1
	_global_active_priority = 0
	_pending_request = {}
	_greeting_active = false
	_greeting_skip_requested = false
	_greeting_step_index = -1
	_ending_steps = []
	_ending_step_index = -1
	_ending_step_player = -1

	_player_profiles = profiles

	for p in profiles.size():
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.finished.connect(_on_slot_finished.bind(p))
		player_slots.append(player)
		_slot_tweens.append(null)
		_last_played.append({})


## Main.gd가 game_state.start_turn() 직후 딱 한 번 부른다. 플레이어 순서대로
## 인사를 하나씩 요청하고(_request_voice를 거치므로 절대 안 겹침), 매핑이
## 없는 플레이어는 대기 없이 바로 다음으로 건너뛴다. 전원이 매핑이 없으면
## 재귀 호출이 그 자리에서 끝까지 돌아 greeting_sequence_finished를
## 동기적으로 emit한다 - Main.gd가 이 함수를 부르기 직전에 입력 차단을
## 켜놨어도, 같은 프레임 안에서 도로 꺼지므로 화면엔 아예 안 보인다.
func play_greeting_sequence() -> void:
	if _greeting_active:
		return  # 정상적으론 안 일어나지만(한 판에 한 번만 호출됨), 방어적으로.

	_greeting_active = true
	_greeting_skip_requested = false
	_greeting_step_index = -1
	_advance_greeting()


## 다음 인사 단계로 넘어간다. 건너뛰기가 걸렸거나 전원을 다 돌았으면 여기서
## 시퀀스를 끝낸다. 매핑이 없는 플레이어는 재생을 요청조차 안 하므로(대기할
## finished가 없으므로) 곧바로 재귀해서 다음 단계로 넘어간다 - 이게 바로
## "대기 없이 건너뛴다"의 구현이다.
func _advance_greeting() -> void:
	_greeting_step_index += 1

	if _greeting_skip_requested or _greeting_step_index >= _player_profiles.size():
		_greeting_active = false
		greeting_sequence_finished.emit()
		return

	var p := _greeting_step_index
	if not _play_for_player(p, GameEvents.Common.GAME_START):
		_advance_greeting()
		return

	greeting_step_started.emit(p)
	# 이 단계가 자연히 끝나면 _on_slot_finished가 _greeting_step_index와
	# 일치하는 걸 보고 0.3초 뒤에 _advance_greeting()을 다시 불러준다.


## 인사 연출 중 건너뛰기 요청. 이미 끝났거나(연출 중이 아님) 이미 건너뛰기
## 요청이 들어온 상태면 아무 것도 안 한다 - 빠르게 두 번 눌러도
## greeting_sequence_finished가 두 번 나가지 않도록 하는 가드.
func request_skip_greeting() -> void:
	if not _greeting_active or _greeting_skip_requested:
		return
	_greeting_skip_requested = true

	if _global_active_player == _greeting_step_index:
		# AudioStreamPlayer.stop()은 finished를 emit하지 않는다 - 그래서
		# _on_slot_finished를 거치지 않고 전역 상태를 여기서 직접 정리한다.
		player_slots[_global_active_player].stop()
		_global_active_player = -1
		_global_active_priority = 0

	_advance_greeting()  # 건너뛰기 플래그가 섰으므로 곧장 종료 처리로 빠진다.
	_try_play_pending()  # 혹시 대기 중이던 게 있으면 여기서 이어서 재생.


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


## player_slots[player_index].finished에 연결되는 유일한 곳(configure()에서
## .bind(player_index)로 한 번만 연결됨) - 이 프로젝트에서 AudioStreamPlayer의
## finished를 직접 구독하는 곳은 여기뿐이다. 인사/승패 시퀀스는 여기서
## 통보만 받고, 실제 다음 재생 요청은 항상 _request_voice()를 거친다.
func _on_slot_finished(player_index: int) -> void:
	if player_index != _global_active_player:
		return  # 이미 다른 요청에 밀려난 뒤 뒤늦게 온 신호(방어적) - 무시.

	_global_active_player = -1
	_global_active_priority = 0

	if _greeting_active and player_index == _greeting_step_index:
		if _greeting_skip_requested:
			_advance_greeting()
		else:
			get_tree().create_timer(GREETING_GAP_DURATION).timeout.connect(_advance_greeting, CONNECT_ONE_SHOT)
		return

	if player_index == _ending_step_player:
		_advance_ending()
		return

	_try_play_pending()


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


# 승리 보이스와 패배 보이스는 절대 겹치면 안 된다(순차 재생) - 인사와 같은
# _advance_ending()/_on_slot_finished 경로를 탄다. winner_index와 loser_index는
# 승부가 갈린 이상(all-tied가 아닌 이상) 항상 서로 다른 플레이어이므로
# 서로 다른 슬롯을 쓴다 — 자기 자신을 끊을 일이 없다.
func _play_game_end_sequence(winner_index: int, loser_index: int) -> void:
	_ending_steps = [{"player": winner_index, "event_key": GameEvents.Common.WIN}]
	if loser_index != -1:
		_ending_steps.append({"player": loser_index, "event_key": GameEvents.Common.LOSE})
	_ending_step_index = -1
	_advance_ending()


## 인사의 _advance_greeting()과 같은 구조 - 매핑이 없어 재생이 시작조차
## 안 된 단계는 대기 없이 곧바로 다음 단계로 넘어간다(원래 코드의 "매핑이
## 없으면 곧바로 넘어간다"와 동일). 승패는 간격(0.3초) 없이 바로 이어붙인다
## (인사와 다른 점 - 원래부터 그랬음).
func _advance_ending() -> void:
	_ending_step_index += 1
	if _ending_step_index >= _ending_steps.size():
		_ending_step_player = -1
		return

	var step: Dictionary = _ending_steps[_ending_step_index]
	if not _play_for_player(step["player"], step["event_key"]):
		_advance_ending()
		return

	_ending_step_player = step["player"]


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


## 이 이벤트에 쓸 파일이 정해졌고(디코딩까지 성공) _request_voice()에 넘겼으면
## true, (매핑 없음/파일 로딩 실패 등으로) 아무 요청도 안 보냈으면 false를
## 반환한다 - true라고 해서 "지금 당장 소리가 난다"는 뜻은 아니다. 대기열에
## 들어갔다가 나중에 재생될 수도, 너무 오래 기다려 버려질 수도 있다(전역
## 재생 규칙은 _request_voice() 참고). 인사/승패 시퀀스는 이 반환값으로
## "다음 단계로 곧장 넘어갈지(false), 이 슬롯이 끝나길 기다릴지(true)"를 정한다.
func _play_for_player(player_index: int, event_key: String) -> bool:
	if event_key == "" or player_index < 0 or player_index >= player_slots.size():
		return false

	var profile: CharacterProfile = _player_profiles[player_index] if player_index < _player_profiles.size() else null
	if profile == null:
		return false

	var candidates: Array = profile.voice_map.get(event_key, [])
	if candidates.is_empty():
		return false  # 매핑이 없으면 조용히 무시한다. 캐릭터가 모든 이벤트에 보이스를 두지는 않는다.

	var last: String = _last_played[player_index].get(event_key, "")
	var filename := pick_voice_file(candidates, last)
	if filename == "":
		return false
	_last_played[player_index][event_key] = filename

	var stream := CharacterLibrary.load_profile_audio(profile, filename)
	if stream == null:
		return false

	var priority: int = _event_priority.get(event_key, 0)
	_request_voice(player_index, event_key, priority, stream)
	return true


## 어느 슬롯이든 전역으로 한 번에 하나만 소리 낸다는 규칙을 지키는 유일한
## 진입점. 재생 중인 게 없으면 즉시 재생하고, 있으면 우선순위를 비교해서
## 더 높으면 교체(0.1초 페이드), 같거나 낮으면 대기열에 넣는다(대기는
## 하나뿐 - 기존 대기보다 우선순위가 높을 때만 교체).
func _request_voice(player_index: int, event_key: String, priority: int, stream: AudioStream) -> void:
	if _global_active_player == -1:
		_start_playing_stream(player_index, stream, priority)
		return

	if priority > _global_active_priority:
		_preempt_and_play(player_index, priority, stream)
		return

	if _pending_request.is_empty() or priority > _pending_request["priority"]:
		_pending_request = {
			"player": player_index,
			"event_key": event_key,
			"priority": priority,
			"stream": stream,
			"queued_at_msec": Time.get_ticks_msec(),
		}


## 재생 중이던 슬롯(old_player_index = 지금까지의 _global_active_player)을
## 0.1초 페이드아웃으로 끄고, 다 꺼진 뒤에(지금 하던 대로) 새 슬롯에서
## 재생을 시작한다. 전역 상태는 "교체를 결정한 시점"에 바로 새 값으로
## 갱신한다 - 그래야 페이드가 끝나기 전에 또 다른 요청이 들어와도 정확한
## 우선순위와 비교된다. 이 슬롯에 이미 진행 중이던 페이드가 있으면(예:
## 같은 플레이어가 연달아 더 높은 우선순위로 교체되는 경우) 새 페이드를
## 시작하기 전에 먼저 죽인다 - 안 그러면 두 트윈이 겹쳐 볼륨이 튄다.
func _preempt_and_play(new_player_index: int, new_priority: int, new_stream: AudioStream) -> void:
	var old_player_index := _global_active_player
	var old_player := player_slots[old_player_index]

	_global_active_player = new_player_index
	_global_active_priority = new_priority

	if _slot_tweens[old_player_index] != null and _slot_tweens[old_player_index].is_valid():
		_slot_tweens[old_player_index].kill()
	old_player.volume_db = 0.0  # 방금 죽였거나 원래 없던 트윈 기준으로 볼륨을 초기화.

	var fade := create_tween()
	fade.tween_property(old_player, "volume_db", VOICE_FADE_OUT_DB, VOICE_CROSSFADE_DURATION)
	fade.tween_callback(func() -> void:
		old_player.stop()
		old_player.volume_db = 0.0
		_start_playing_stream(new_player_index, new_stream, new_priority))
	_slot_tweens[old_player_index] = fade


## 지금 아무것도 안 나고 있을 때(또는 위 페이드가 끝났을 때) 바로 재생을
## 시작한다. 이 슬롯에 죽지 않은 트윈이 남아있으면(드물지만 방어적으로)
## 먼저 죽이고 볼륨을 초기화한다.
func _start_playing_stream(player_index: int, stream: AudioStream, priority: int) -> void:
	if _slot_tweens[player_index] != null and _slot_tweens[player_index].is_valid():
		_slot_tweens[player_index].kill()
	var player := player_slots[player_index]
	player.volume_db = 0.0
	player.stream = stream
	player.play()
	_global_active_player = player_index
	_global_active_priority = priority


## 재생 중이던 슬롯이 비었을 때(_on_slot_finished/request_skip_greeting) 대기
## 중이던 요청이 있으면 이어서 재생한다. 그 사이 시퀀스가 이미 다음 요청을
## 넣어서 슬롯이 다시 찼으면(_global_active_player != -1) 아무 것도 안 한다.
## 대기가 VOICE_WAIT_TIMEOUT_MSEC을 넘겼으면 재생하지 않고 버린다 - 때를
## 놓친 대사는 안 하는 게 낫다.
func _try_play_pending() -> void:
	if _global_active_player != -1 or _pending_request.is_empty():
		return

	var request: Dictionary = _pending_request
	_pending_request = {}

	var age_msec: int = Time.get_ticks_msec() - request["queued_at_msec"]
	if age_msec > VOICE_WAIT_TIMEOUT_MSEC:
		if BuildInfo.DEBUG_MODE:
			print("[VoiceBank] %s 대기 %.1f초 초과로 버림" % [request["event_key"], age_msec / 1000.0])
		return

	_start_playing_stream(request["player"], request["stream"], request["priority"])
