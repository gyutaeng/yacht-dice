extends Node

# 캐릭터와 무관한, 게임에 내장된 효과음(주사위 굴림/고정, 특수 족보). 캐릭터
# 팩에 넣지 않는다 — 캐릭터마다 주사위 소리가 달라지면 이상하다. VoiceBank(캐릭터
# 보이스)와 완전히 분리된 AudioStreamPlayer를 쓰므로 서로 끊지 않는다.
#
# 경로/볼륨을 전부 이 파일 상단에 상수로 모아둔다 — 나중에 실제 파일을 넣거나
# 볼륨을 조정할 때 건드릴 곳이 여기 하나뿐이도록.

const DICE_ROLL_SFX_PATH := "res://assets/sfx/dice_roll.wav"
const DICE_HOLD_SFX_PATH := "res://assets/sfx/dice_hold.wav"
const YACHT_SFX_PATH := "res://assets/sfx/yacht.wav"
const SPECIAL_HAND_SFX_PATH := "res://assets/sfx/special_hand.wav"

const DICE_ROLL_VOLUME_DB := 0.0
const DICE_HOLD_VOLUME_DB := 0.0
const YACHT_VOLUME_DB := -6.0
const SPECIAL_HAND_VOLUME_DB := -6.0

var _dice_roll_player: AudioStreamPlayer
var _dice_hold_player: AudioStreamPlayer
var _special_hand_player: AudioStreamPlayer  # 야추/기타 특수 족보가 동시에 날 일은 없어서 하나로 공용.

var _dice_roll_stream: AudioStream
var _dice_hold_stream: AudioStream
var _yacht_stream: AudioStream
var _special_hand_stream: AudioStream


func _ready() -> void:
	_dice_roll_player = _make_player(DICE_ROLL_VOLUME_DB)
	_dice_hold_player = _make_player(DICE_HOLD_VOLUME_DB)
	_special_hand_player = _make_player(0.0)  # 재생 시점에 야추/기타에 따라 볼륨을 따로 맞춘다.

	_dice_roll_stream = _load_optional(DICE_ROLL_SFX_PATH)
	_dice_hold_stream = _load_optional(DICE_HOLD_SFX_PATH)
	_yacht_stream = _load_optional(YACHT_SFX_PATH)
	_special_hand_stream = _load_optional(SPECIAL_HAND_SFX_PATH)

	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.die_held_changed.connect(_on_die_held_changed)
	GameEvents.special_hand_rolled.connect(_on_special_hand_rolled)


func _make_player(volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume_db
	add_child(player)
	return player


## 이 파일들은 게임에 내장된 res:// 리소스라 항상 load()로 읽는다 -
## AssetLoader(바이트 기반)는 사용자가 올린 user:// 파일 전용이다. res:// 안의
## .wav는 export 시 임포터가 변환한 리소스로 pck에 들어가고 원본 바이트는
## 아예 안 들어가므로, FileAccess로 원본을 읽으려 하면 에디터에서는(원본이
## 프로젝트 폴더에 그대로 있어서) 되지만 export된 빌드에서는 조용히 실패한다.
##
## 파일이 아직 없으면(지금 dice_roll.wav/dice_hold.wav/yacht.wav가 그렇다) 경고 없이
## null을 돌려준다 — 나중에 파일을 채워 넣을 자리이지, 에러 상황이 아니다.
func _load_optional(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _on_dice_rolled(_player_index: int, _values: Array[int], _reroll_left: int) -> void:
	_play(_dice_roll_player, _dice_roll_stream)


func _on_die_held_changed(_player_index: int, _index: int, _held: bool) -> void:
	# 고정/해제는 빠르게 연타될 수 있으니, 이전 소리를 끊고 새로 재생해서 겹쳐
	# 쌓이지 않게 한다.
	_dice_hold_player.stop()
	_play(_dice_hold_player, _dice_hold_stream)


func _on_special_hand_rolled(_player_index: int, category: int, _points: int) -> void:
	if category == GameState.YACHT_CATEGORY_INDEX:
		_special_hand_player.volume_db = YACHT_VOLUME_DB
		_play(_special_hand_player, _yacht_stream)
	else:
		_special_hand_player.volume_db = SPECIAL_HAND_VOLUME_DB
		_play(_special_hand_player, _special_hand_stream)


func _play(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null:
		return
	player.stream = stream
	player.play()
