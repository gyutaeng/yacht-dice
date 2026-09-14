class_name CharacterProfile
extends Resource

# manifest.json의 스키마 버전. 나중에 필드가 바뀌면 올리고, from_dict()에서
# 이 값과 다르면(=모르는 버전이면) 거부한다. 캐릭터 팩을 파일로 주고받거나
# 네트워크로 보낼 일이 생기기 전에 미리 넣어둬야, 나중에 형식이 바뀌었을 때
# 이미 배포된 옛 팩과 새 팩을 구분할 수 있다.
const FORMAT_VERSION := 1

# 폴더 이름으로도 쓰이므로 영숫자와 하이픈만 허용한다.
@export var id: String = ""
@export var display_name: String = ""
# 프로필 폴더 기준 상대경로. 예: "portrait.png"
@export var portrait_file: String = ""
# 작은 초상(이름표 썸네일) 전용 이미지. 선택 항목 — 없으면 UI가 portrait_file로
# 폴백한다. 프로필 폴더 기준 상대경로.
@export var thumbnail_file: String = ""
# 이벤트 키(GameEvents.Common/Yacht 등의 값, 예: "yacht.yacht") -> 파일명 배열.
# 파일명은 voices/ 기준이 아니라 **프로필 폴더 기준** 상대경로로 통일한다.
# 즉 voices/ 안의 파일이라도 "laugh1.wav"가 아니라 "voices/laugh1.wav"라고 적는다.
# 배열인 이유는 같은 이벤트에 여러 보이스 후보를 두고 재생 시점에 무작위로
# 고르기 위함이다.
@export var voice_map: Dictionary = {}
@export var volume_db: float = 0.0

# 이 값은 manifest.json에 저장되지 않는다. res://characters/default처럼 내장
# 폴백에서 읽었는지, user://characters/ 아래 사용자 캐릭터에서 읽었는지에 따라
# CharacterLibrary가 로드 시점에 채워 넣는 런타임 전용 플래그다. UI가 이 값으로
# 편집/삭제 버튼을 막을 수 있다(내장 캐릭터는 고칠 수도 지울 수도 없으므로).
var is_builtin: bool = false


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"id": id,
		"display_name": display_name,
		"portrait_file": portrait_file,
		"thumbnail_file": thumbnail_file,
		"voice_map": voice_map,
		"volume_db": volume_db,
	}


# data가 스키마에 안 맞으면 예외를 던지지 않고 null을 반환한다(호출자가 건너뛸 수 있도록).
# context는 로그에 남길 출처(폴더 이름 등)이며 생략 가능하다.
static func from_dict(data: Dictionary, context: String = "") -> CharacterProfile:
	var label := context if context != "" else "(알 수 없음)"

	# JSON은 정수 리터럴도 float로 파싱해서 돌려주므로(예: 1 -> 1.0), int/float 둘 다 받아준다.
	var format_version_value = data.get("format_version")
	if not (format_version_value is int or format_version_value is float) or int(format_version_value) != FORMAT_VERSION:
		push_warning("CharacterProfile: %s - 알 수 없는 format_version(%s), 이 코드는 %d만 이해함" % [label, str(format_version_value), FORMAT_VERSION])
		return null

	var id_value = data.get("id")
	if not (id_value is String) or (id_value as String).is_empty():
		push_warning("CharacterProfile: %s - id 필드가 없거나 비어 있음" % label)
		return null
	var id_str: String = id_value
	if not is_valid_id(id_str):
		push_warning("CharacterProfile: %s - id \"%s\"에 허용되지 않는 문자가 있음(영숫자/하이픈만 가능)" % [label, id_str])
		return null

	var display_name_value = data.get("display_name")
	if not (display_name_value is String):
		push_warning("CharacterProfile: %s - display_name 필드가 없거나 문자열이 아님" % label)
		return null

	var voice_map_value = data.get("voice_map")
	if not (voice_map_value is Dictionary):
		push_warning("CharacterProfile: %s - voice_map 필드가 없거나 딕셔너리가 아님" % label)
		return null

	var volume_value = data.get("volume_db", 0.0)
	if not (volume_value is float or volume_value is int):
		push_warning("CharacterProfile: %s - volume_db가 숫자가 아님" % label)
		return null

	var portrait_value = data.get("portrait_file", "")
	var portrait_str: String = portrait_value if portrait_value is String else ""

	# 선택 항목이라 없어도 스키마 위반이 아니다 — 기존(이 필드가 생기기 전) 캐릭터도
	# 그대로 동작해야 하므로 빈 문자열로 기본 처리한다.
	var thumbnail_value = data.get("thumbnail_file", "")
	var thumbnail_str: String = thumbnail_value if thumbnail_value is String else ""

	var profile := CharacterProfile.new()
	profile.id = id_str
	profile.display_name = display_name_value
	profile.portrait_file = portrait_str
	profile.thumbnail_file = thumbnail_str
	profile.volume_db = float(volume_value)
	profile.voice_map = _sanitize_voice_map(voice_map_value)
	return profile


static func is_valid_id(candidate_id: String) -> bool:
	if candidate_id.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9-]+$")
	return regex.search(candidate_id) != null


# voice_map 최상위가 Dictionary가 아니면 from_dict에서 이미 프로필 전체를 거부한다.
# 여기서는 그 안의 개별 항목만 검사해서, 값이 배열이 아니거나 배열 안에 문자열이
# 아닌 항목이 섞여 있어도 프로필 전체를 버리지 않고 그 항목/원소만 조용히 걸러낸다.
static func _sanitize_voice_map(raw: Dictionary) -> Dictionary:
	var sanitized := {}
	for key in raw:
		if not (key is String):
			continue
		var value = raw[key]
		if not (value is Array):
			continue
		var filenames: Array[String] = []
		for entry in value:
			if entry is String:
				filenames.append(entry)
		sanitized[key] = filenames
	return sanitized
