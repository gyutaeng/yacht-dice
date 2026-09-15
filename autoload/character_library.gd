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


## 프로필의 파일 하나(초상/썸네일/보이스)를 읽는 진입점을 여기 하나로 모은다.
## 내장 프로필(res://characters/default)과 사용자 프로필(user://characters/<id>)은
## 읽는 방법이 달라야 한다:
## - 내장(res://): export 시 Godot 임포터가 원본을 변환된 리소스로 바꿔 pck에
##   넣고 원본 바이트는 안 들어간다. 그래서 반드시 load()로 읽는다. 에디터에서
##   실행하면 원본이 프로젝트 폴더에 그대로 있어서 FileAccess로도 되는 것처럼
##   보이지만, export된 빌드에서는 조용히 실패한다(SfxBank가 이 버그를 겪었다).
## - 사용자(user://): 임포트를 거치지 않은 원본 그대로라, AssetLoader의
##   바이트 기반 시그니처 판별로 읽어야 한다(확장자를 안 믿음, 원칙 3·6).
## 이 둘을 헷갈리면 안 되므로 "어느 쪽 파일을 읽을지" 자체를 함수 호출부가
## 신경 쓰지 않도록 profile.is_builtin으로 여기서 한 번에 분기한다.
func load_profile_texture(profile: CharacterProfile, filename: String) -> Texture2D:
	if profile == null or filename.is_empty():
		return null
	if profile.is_builtin:
		var path := BUILTIN_FALLBACK_PATH.path_join(filename)
		return load(path) if ResourceLoader.exists(path) else null
	return AssetLoader.load_texture_from_path(CHARACTERS_DIR.path_join(profile.id).path_join(filename))


func load_profile_audio(profile: CharacterProfile, filename: String) -> AudioStream:
	if profile == null or filename.is_empty():
		return null
	if profile.is_builtin:
		var path := BUILTIN_FALLBACK_PATH.path_join(filename)
		return load(path) if ResourceLoader.exists(path) else null
	return AssetLoader.load_audio_from_path(CHARACTERS_DIR.path_join(profile.id).path_join(filename))


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


## 저장 = manifest.json 갱신 + 그 manifest가 더 이상 가리키지 않는 파일 정리.
## "제거" 버튼 등은 profile 필드만 지웠다가 여기서 한 번에 반영된다 - 별도의
## "삭제 예정" 상태를 안 둬도, 저장에 실패하면(return false) 아무 파일도
## 안 지워지므로 안전하다(정리는 manifest 쓰기가 성공한 뒤에만 실행됨).
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

	_cleanup_unreferenced_files(profile)
	return true


## 프로필 폴더 안 파일 중 portrait_file/thumbnail_file/voice_map 어디에도 안
## 걸린 것을 지운다. 이미지를 여러 번 바꿔보고 저장 안 하고 나가도 고아
## 파일이 안 쌓이게 하려고, 매 저장마다 실행한다(직접 지우는 게 아니라 "지금
## manifest 기준으로 필요 없는 것"을 다시 계산해서 지우는 방식이라 상태를
## 따로 들고 다닐 필요가 없다). dir_path는 항상 이 함수 안에서 profile.id로
## 직접 만들기 때문에(호출부가 경로를 넘기지 않음) CHARACTERS_DIR 바깥을 건드릴 수 없다.
func _cleanup_unreferenced_files(profile: CharacterProfile) -> void:
	var dir_path := CHARACTERS_DIR.path_join(profile.id)

	var referenced := {MANIFEST_FILENAME: true}
	if profile.portrait_file != "":
		referenced[profile.portrait_file] = true
	if profile.thumbnail_file != "":
		referenced[profile.thumbnail_file] = true
	for key in profile.voice_map:
		for filename in profile.voice_map[key]:
			referenced[filename] = true

	_delete_unreferenced_in_dir(dir_path, "", referenced)


func _delete_unreferenced_in_dir(root_dir: String, relative_prefix: String, referenced: Dictionary) -> void:
	var current_dir := root_dir if relative_prefix == "" else root_dir.path_join(relative_prefix)
	var dir := DirAccess.open(current_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var relative_path := entry if relative_prefix == "" else relative_prefix.path_join(entry)
			if dir.current_is_dir():
				_delete_unreferenced_in_dir(root_dir, relative_path, referenced)
				var sub_dir := DirAccess.open(root_dir.path_join(relative_path))
				if sub_dir != null and sub_dir.get_files().is_empty() and sub_dir.get_directories().is_empty():
					DirAccess.remove_absolute(root_dir.path_join(relative_path))
			elif not referenced.has(relative_path):
				DirAccess.remove_absolute(root_dir.path_join(relative_path))
		entry = dir.get_next()
	dir.list_dir_end()


## FilePicker로 받은 바이트를 프로필 폴더 아래에 저장한다. subdir는 이미지는
## ""(프로필 폴더 바로 아래), 보이스는 "voices"를 넘긴다. 이름이 겹치면
## "portrait-2.png"처럼 뒤에 숫자를 붙인다. 반환값은 manifest에 그대로 적을 수
## 있는 "프로필 폴더 기준 상대경로"(예: "voices/laugh-2.wav")이고, 실패하면 "".
##
## 디스크에는 바로 쓰지만 manifest.json에는 아직 안 적혀 있으므로, 저장하지
## 않고 나가면 이 파일은 참조되지 않는 채로 남는다 - 그게 바로 save_profile()의
## 정리 대상이라 별도 롤백 로직이 필요 없다.
func save_asset_bytes(profile_id: String, subdir: String, desired_filename: String, bytes: PackedByteArray) -> String:
	var dir_path := CHARACTERS_DIR.path_join(profile_id)
	if subdir != "":
		dir_path = dir_path.path_join(subdir)

	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		push_error("CharacterLibrary.save_asset_bytes: 폴더 생성 실패 - %s" % dir_path)
		return ""

	var final_name := _unique_filename(dir_path, desired_filename)
	var file := FileAccess.open(dir_path.path_join(final_name), FileAccess.WRITE)
	if file == null:
		push_error("CharacterLibrary.save_asset_bytes: 파일을 쓸 수 없음 - %s" % dir_path.path_join(final_name))
		return ""

	file.store_buffer(bytes)
	file.close()

	return final_name if subdir == "" else subdir.path_join(final_name)


## dir_path 안에서 desired_filename과 안 겹치는 이름을 찾는다("확장자 보존 +
## -2, -3 ... 붙이기"). _generate_unique_id()와 목적은 같지만 그쪽은 폴더
## 이름(확장자 없음, 슬러그화)용이라 그대로 못 쓴다.
func _unique_filename(dir_path: String, desired_filename: String) -> String:
	var base := desired_filename.get_basename()
	var ext := desired_filename.get_extension()

	var candidate := desired_filename
	var suffix := 2
	while FileAccess.file_exists(dir_path.path_join(candidate)):
		candidate = "%s-%d.%s" % [base, suffix, ext] if ext != "" else "%s-%d" % [base, suffix]
		suffix += 1

	return candidate


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
	new_profile.thumbnail_file = source_profile.thumbnail_file
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
