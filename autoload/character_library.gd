extends Node

# 캐릭터 프로필을 user://characters/<id>/ 아래에서 읽고 쓰는 autoload.
#
# 웹(HTML5) export에서도 동작해야 하므로 DirAccess/FileAccess만 사용하고,
# OS.get_user_data_dir() 등으로 네이티브 경로를 직접 조합하지 않는다.
# user://는 데스크톱에서는 실제 폴더지만 웹 export에서는 IndexedDB로
# 매핑되는 Godot의 가상 경로이며, DirAccess/FileAccess는 두 경우 모두
# 동일하게 동작한다.

const CHARACTERS_DIR := "user://characters"
const MANIFEST_FILENAME := "manifest.json"
const BUILTIN_FALLBACK_PATH := "res://characters/default"

const CharacterProfileScript = preload("res://scripts/characters/character_profile.gd")


## user://characters/ 아래의 "사용자" 캐릭터만 반환한다. 내장 기본 캐릭터는
## 절대 섞지 않는다 — 그걸 섞으면 사용자가 캐릭터를 하나라도 만드는 순간
## 목록에서 조용히 사라지고, 편집 화면에는 고치거나 지울 수 없는 내장 캐릭터에
## 삭제 버튼이 달리는 문제가 생긴다. 캐릭터가 하나도 없으면 빈 배열을 반환한다.
## 캐릭터 편집/관리 화면은 이 함수를 쓴다.
func scan() -> Array[CharacterProfile]:
	var profiles: Array[CharacterProfile] = []

	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var profile := _load_profile_from_dir(CHARACTERS_DIR.path_join(entry), entry, false)
				if profile != null:
					profiles.append(profile)
			entry = dir.get_next()
		dir.list_dir_end()

	return profiles


## 내장 기본 캐릭터 + scan() 결과를 합쳐서 반환한다. 게임 시작 시 캐릭터를
## 고르는 화면처럼 "항상 고를 게 하나는 있어야 하는" 곳에서 이 함수를 쓴다.
func get_selectable_profiles() -> Array[CharacterProfile]:
	var profiles: Array[CharacterProfile] = []

	var fallback := get_builtin_fallback()
	if fallback != null:
		profiles.append(fallback)

	profiles.append_array(scan())
	return profiles


func load_profile(id: String) -> CharacterProfile:
	return _load_profile_from_dir(CHARACTERS_DIR.path_join(id), id, false)


func get_builtin_fallback() -> CharacterProfile:
	return _load_profile_from_dir(BUILTIN_FALLBACK_PATH, "default", true)


func save_profile(profile: CharacterProfile) -> bool:
	if profile == null or not CharacterProfileScript.is_valid_id(profile.id):
		push_error("CharacterLibrary.save_profile: 유효하지 않은 프로필(또는 id)입니다.")
		return false

	var dir_path := CHARACTERS_DIR.path_join(profile.id)
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		push_error("CharacterLibrary.save_profile: 폴더 생성 실패 - %s" % dir_path)
		return false

	var manifest_path := dir_path.path_join(MANIFEST_FILENAME)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("CharacterLibrary.save_profile: manifest.json을 열 수 없음 - %s" % manifest_path)
		return false

	file.store_string(JSON.stringify(profile.to_dict(), "\t"))
	file.close()
	return true


func create_new(display_name: String) -> CharacterProfile:
	var id := _generate_unique_id(display_name)

	var profile := CharacterProfileScript.new()
	profile.id = id
	profile.display_name = display_name
	profile.portrait_file = ""
	profile.voice_map = {}
	profile.volume_db = 0.0

	if not save_profile(profile):
		return null
	return profile


func delete(id: String) -> bool:
	var dir_path := CHARACTERS_DIR.path_join(id)
	if not DirAccess.dir_exists_absolute(dir_path):
		push_error("CharacterLibrary.delete: 존재하지 않는 캐릭터 - %s" % id)
		return false
	return _remove_dir_recursive(dir_path)


## Node에 이미 duplicate()가 내장되어 있어서(시그니처가 달라 오버라이드 불가) 이름을 다르게 뒀다.
func duplicate_profile(id: String) -> CharacterProfile:
	var source_dir := CHARACTERS_DIR.path_join(id)
	if not DirAccess.dir_exists_absolute(source_dir):
		push_error("CharacterLibrary.duplicate_profile: 존재하지 않는 캐릭터 - %s" % id)
		return null

	var source_profile := load_profile(id)
	if source_profile == null:
		push_error("CharacterLibrary.duplicate_profile: 원본 manifest를 읽을 수 없음 - %s" % id)
		return null

	var new_id := _generate_unique_id(id + "-copy")
	var dest_dir := CHARACTERS_DIR.path_join(new_id)

	if not _copy_dir_recursive(source_dir, dest_dir):
		push_error("CharacterLibrary.duplicate_profile: 폴더 복사 실패 - %s -> %s" % [source_dir, dest_dir])
		return null

	var new_profile := CharacterProfileScript.new()
	new_profile.id = new_id
	new_profile.display_name = source_profile.display_name
	new_profile.portrait_file = source_profile.portrait_file
	new_profile.voice_map = source_profile.voice_map.duplicate(true)
	new_profile.volume_db = source_profile.volume_db

	if not save_profile(new_profile):
		return null
	return new_profile


func _load_profile_from_dir(dir_path: String, context: String, is_builtin: bool) -> CharacterProfile:
	var manifest_path := dir_path.path_join(MANIFEST_FILENAME)
	if not FileAccess.file_exists(manifest_path):
		return null

	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_warning("CharacterLibrary: %s - manifest.json을 열 수 없음" % context)
		return null

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("CharacterLibrary: %s - manifest.json이 올바른 JSON 객체가 아님" % context)
		return null

	var profile := CharacterProfileScript.from_dict(parsed, context)
	if profile != null:
		profile.is_builtin = is_builtin
	return profile


func _generate_unique_id(seed_text: String) -> String:
	var base_id := _slugify(seed_text)
	if base_id.is_empty():
		base_id = "character"

	var candidate := base_id
	var suffix := 2
	while DirAccess.dir_exists_absolute(CHARACTERS_DIR.path_join(candidate)):
		candidate = "%s-%d" % [base_id, suffix]
		suffix += 1

	return candidate


func _slugify(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9-]+")
	var slug := regex.sub(text, "-", true)
	return slug.strip_edges().lstrip("-").rstrip("-")


# DirAccess에는 재귀 삭제가 없어서 직접 구현한다: 파일은 바로 지우고,
# 하위 폴더는 먼저 재귀적으로 비운 뒤에 그 폴더 자체를 지운다.
#
# 안전장치: dir_path가 "user://characters/" 아래(그 폴더 자체는 제외)가
# 아니면 아무것도 하지 않고 false를 반환한다. 경로 계산을 잘못해서 엉뚱한
# 폴더가 통째로 삭제되는 사고를 막기 위함이다.
func _remove_dir_recursive(dir_path: String) -> bool:
	var safe_prefix := CHARACTERS_DIR + "/"
	if not dir_path.begins_with(safe_prefix) or dir_path == safe_prefix:
		push_error("CharacterLibrary: 안전하지 않은 삭제 경로라 거부함 - %s" % dir_path)
		return false

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := dir_path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full_path)
			else:
				DirAccess.remove_absolute(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

	return DirAccess.remove_absolute(dir_path) == OK


# DirAccess에는 재귀 복사도 없어서 직접 구현한다. 파일 복사는 DirAccess.copy_absolute를 쓴다.
func _copy_dir_recursive(source_dir: String, dest_dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK:
		return false

	var dir := DirAccess.open(source_dir)
	if dir == null:
		return false

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var source_path := source_dir.path_join(entry)
			var dest_path := dest_dir.path_join(entry)
			if dir.current_is_dir():
				if not _copy_dir_recursive(source_path, dest_path):
					dir.list_dir_end()
					return false
			else:
				if DirAccess.copy_absolute(source_path, dest_path) != OK:
					dir.list_dir_end()
					return false
		entry = dir.get_next()
	dir.list_dir_end()

	return true
