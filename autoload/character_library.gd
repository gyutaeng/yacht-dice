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

# 1-7 캐릭터 팩(.zip으로 내보내기/가져오기). 포맷은 docs/character_pack.md에
# 문서화되어 있다 - Phase 2에서 네트워크로 이 zip을 그대로 전송할 예정이라
# 여기 상수를 바꾸면 그 문서도 같이 갱신할 것.
const PACK_FILE_SUFFIX := ".ydchar.zip"
const PACK_ALLOWED_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3", "json"]
const PACK_MAX_UNCOMPRESSED_BYTES := 50 * 1024 * 1024  # 50MB - 압축률 폭탄 방지용 상한.

const CharacterProfileScript = preload("res://scripts/characters/character_profile.gd")
const CharacterLimitsScript = preload("res://scripts/characters/character_limits.gd")


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
##
## 2-5에서 asset_bytes/asset_base_dir 두 분기가 추가됐다(순서: is_builtin ->
## asset_bytes -> asset_base_dir -> 기본 user://characters/<id>) - 온라인으로
## 받은 캐릭터(CharacterProfile)를 표현하는 값들이라, VoiceBank/CharacterPortrait/
## voice_mapping_panel.gd 세 호출부는 이 분기 확장만으로 그대로 동작한다.
func load_profile_texture(profile: CharacterProfile, filename: String) -> Texture2D:
	if profile == null or filename.is_empty():
		return null
	if profile.is_builtin:
		var path := BUILTIN_FALLBACK_PATH.path_join(filename)
		return load(path) if ResourceLoader.exists(path) else null
	if not profile.asset_bytes.is_empty():
		if not profile.asset_bytes.has(filename):
			return null
		return AssetLoader.load_texture_from_bytes(profile.asset_bytes[filename])
	var base_dir := profile.asset_base_dir if profile.asset_base_dir != "" else CHARACTERS_DIR.path_join(profile.id)
	return AssetLoader.load_texture_from_path(base_dir.path_join(filename))


func load_profile_audio(profile: CharacterProfile, filename: String) -> AudioStream:
	if profile == null or filename.is_empty():
		return null
	if profile.is_builtin:
		var path := BUILTIN_FALLBACK_PATH.path_join(filename)
		return load(path) if ResourceLoader.exists(path) else null
	if not profile.asset_bytes.is_empty():
		if not profile.asset_bytes.has(filename):
			return null
		return AssetLoader.load_audio_from_bytes(profile.asset_bytes[filename])
	var base_dir := profile.asset_base_dir if profile.asset_base_dir != "" else CHARACTERS_DIR.path_join(profile.id)
	return AssetLoader.load_audio_from_path(base_dir.path_join(filename))


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
	_delete_unreferenced_in_dir(dir_path, "", _referenced_files(profile))


## manifest.json이 실제로 가리키는 파일 집합(프로필 폴더 기준 상대경로 -> true).
## 저장 시 고아 파일 정리(_cleanup_unreferenced_files)와 팩 내보내기
## (export_pack_bytes) 둘 다 "이 캐릭터에 실제로 필요한 파일이 뭔지"를 같은
## 기준으로 판단해야 하므로 여기 하나로 모은다 - thumbnail_file을 빠뜨리면
## 내보내기에서도 똑같이 빠지는 사고를 막기 위함.
func _referenced_files(profile: CharacterProfile) -> Dictionary:
	var referenced := {MANIFEST_FILENAME: true}
	if profile.portrait_file != "":
		referenced[profile.portrait_file] = true
	if profile.thumbnail_file != "":
		referenced[profile.thumbnail_file] = true
	for key in profile.voice_map:
		for filename in profile.voice_map[key]:
			referenced[filename] = true
	return referenced


## profile이 실제로 디스크에서 차지하는 전체 용량(바이트) - 초상+썸네일+보이스
## 전부 합. 편집 화면의 "현재 캐릭터 용량" 표시와 팩 가져오기 시의 크기 경고가
## 함께 쓴다. _referenced_files()가 "지금 이 프로필이 실제로 가리키는 파일이
## 뭔지"를 이미 계산해주므로 그 파일들의 디스크 상 크기만 더하면 된다 -
## 아직 save_profile()로 저장 안 한 상태(방금 고른 파일이 디스크엔 있지만
## manifest.json엔 아직 안 적힌 시점)에도 정확하다.
func compute_pack_size(profile: CharacterProfile) -> int:
	if profile == null:
		return 0

	var dir_path := CHARACTERS_DIR.path_join(profile.id)
	var total := 0
	for relative_path in _referenced_files(profile).keys():
		var file := FileAccess.open(dir_path.path_join(relative_path), FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	return total


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


## profile을 하나의 zip 바이트로 묶는다(파일 포맷은 docs/character_pack.md
## 참고). manifest.json은 디스크 파일을 그대로 복사하지 않고 profile.to_dict()로
## 새로 쓴다 - 그래야 아직 디스크에 반영 안 된 값이 하나도 없다는 보장 없이도
## (호출부가 export 전에 save_profile을 이미 했다는 것에 의존하지 않고) 항상
## 지금 메모리 상의 최신 상태와 일치한다. 나머지 파일은 _referenced_files()가
## 가리키는 것만 담는다(고아 파일은 애초에 안 담김).
func export_pack_bytes(profile: CharacterProfile) -> PackedByteArray:
	if profile == null or profile.is_builtin:
		push_error("CharacterLibrary.export_pack_bytes: 내장 캐릭터는 내보낼 수 없음")
		return PackedByteArray()

	var dir_path := CHARACTERS_DIR.path_join(profile.id)
	var referenced := _referenced_files(profile)

	var tmp_path := "user://.tmp_export_%d.zip" % Time.get_ticks_usec()
	var packer := ZIPPacker.new()
	if packer.open(tmp_path) != OK:
		push_error("CharacterLibrary.export_pack_bytes: 임시 zip을 열 수 없음 - %s" % tmp_path)
		return PackedByteArray()

	_zip_write_entry(packer, MANIFEST_FILENAME, JSON.stringify(profile.to_dict(), "\t").to_utf8_buffer())

	for relative_path in referenced.keys():
		if relative_path == MANIFEST_FILENAME:
			continue
		var file := FileAccess.open(dir_path.path_join(relative_path), FileAccess.READ)
		if file == null:
			push_warning("CharacterLibrary.export_pack_bytes: 파일을 읽을 수 없어 건너뜀 - %s" % relative_path)
			continue
		_zip_write_entry(packer, relative_path, file.get_buffer(file.get_length()))
		file.close()

	packer.close()

	var zip_bytes := PackedByteArray()
	var zip_file := FileAccess.open(tmp_path, FileAccess.READ)
	if zip_file != null:
		zip_bytes = zip_file.get_buffer(zip_file.get_length())
		zip_file.close()
	DirAccess.remove_absolute(tmp_path)

	return zip_bytes


# ZIPPacker.start_file()의 modified_time 기본값(0)은 "시각 없음"이 아니라
# 그 순간의 실제 시각으로 해석된다(DOS 타임스탬프, 2초 단위) - 그래서
# 같은 캐릭터를 다시 내보내도 파일 내용은 완전히 같은데 zip 로컬/중앙
# 헤더의 시각 필드만 달라져 sha256(pack_hash)이 매번 바뀌었다(재대전마다
# 캐릭터가 다시 전송되던 원인, 실측: 1.5초 간격 재수출 시 257바이트 중
# 딱 2바이트만 달랐고 그 위치가 각각 로컬/중앙 헤더의 시각 필드였음).
# pack_hash는 "내용이 같으면 항상 같아야" 캐시가 의미가 있으므로, 항상
# 같은 고정값(1)을 넘겨 시각을 완전히 지운다 - 어떤 값이든 상관없고
# 매 호출 동일하기만 하면 된다.
const ZIP_ENTRY_PERMISSIONS := 420  # start_file() 기본값과 동일(0o644) - 그대로 유지
const ZIP_ENTRY_FIXED_MTIME := 1  # 0이 아니기만 하면 됨(0은 "현재 시각"으로 해석됨)


func _zip_write_entry(packer: ZIPPacker, entry_name: String, bytes: PackedByteArray) -> void:
	packer.start_file(entry_name, ZIP_ENTRY_PERMISSIONS, ZIP_ENTRY_FIXED_MTIME)
	packer.write_file(bytes)
	packer.close_file()


## zip 바이트를 검증하고 메모리로만 풀어낸다(디스크에 아무것도 안 씀) -
## 로컬 가져오기(import_pack)와 2-5(네트워크로 받은 캐릭터 팩)가 이 신뢰
## 검증 로직을 공유한다. 남이 만든 파일이므로 내용을 전혀 신뢰하지
## 않는다(원칙 6) - 아래를 전부 통과해야만 "ok": true를 돌려준다:
## - manifest.json이 있고 CharacterProfile 스키마를 통과해야 한다.
## - 모든 항목의 경로가 안전해야 한다(".."/절대경로/백슬래시 금지 - zip slip 방지).
## - 모든 항목의 확장자가 화이트리스트 안에 있어야 한다.
## - 압축을 푼 전체 크기가 PACK_MAX_UNCOMPRESSED_BYTES(50MB)를 넘으면 안 된다.
##   (ZIPReader에는 압축 해제 전에 크기만 미리 물어볼 방법이 없어서, 항목을 하나
##   읽을 때마다 즉시 크기를 누적 검사한다 - 항목 하나가 통째로 거대한 경우
##   그 한 번의 read_file() 호출 자체가 메모리를 크게 잡을 수 있다는 한계는
##   있지만, "여러 항목의 합이 상한을 넘는" 흔한 폭탄은 디스크에 쓰기 전에 막는다.)
##
## yield_node를 넘기면 파일을 하나 풀 때마다 한 프레임 기다린다(2-5 - 온라인
## 에서 최대 3명분 팩을 받을 때 압축 해제+디코딩이 한 프레임에 몰려 웹
## 브라우저가 얼어붙는 걸 막기 위함, 1-8에서 지적된 문제의 연장). 로컬
## 가져오기는 파일 하나를 사용자가 직접 고른 단발성 동작이라 넘기지 않는다.
## 이 함수는 await를 포함하므로 항상 `await`로 호출해야 한다(GDScript는
## yield_node가 null이라 실제로 한 번도 안 멈추는 경우에도 정적으로 요구한다).
##
## 반환값: {"ok": bool, "error": String, "manifest_profile": CharacterProfile,
## "extracted": Dictionary(프로필 폴더 기준 상대경로 -> PackedByteArray)}.
func validate_and_extract_pack(zip_bytes: PackedByteArray, yield_node: Node = null) -> Dictionary:
	if zip_bytes.is_empty():
		return _extract_error("빈 파일입니다.")

	var tmp_path := "user://.tmp_import_%d.zip" % Time.get_ticks_usec()
	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		return _extract_error("임시 파일을 만들 수 없습니다.")
	tmp_file.store_buffer(zip_bytes)
	tmp_file.close()

	var reader := ZIPReader.new()
	if reader.open(tmp_path) != OK:
		DirAccess.remove_absolute(tmp_path)
		return _extract_error("zip 파일을 열 수 없습니다. 손상되었거나 zip 형식이 아닙니다.")

	var entries := reader.get_files()
	if not entries.has(MANIFEST_FILENAME):
		reader.close()
		DirAccess.remove_absolute(tmp_path)
		return _extract_error("manifest.json이 없습니다. 캐릭터 팩(.ydchar.zip) 파일이 맞는지 확인하세요.")

	var file_entries: Array[String] = []
	for entry_path in entries:
		if entry_path.ends_with("/"):
			continue  # 디렉터리 항목 자체는 검사할 내용이 없으니 건너뜀.
		if not _is_safe_pack_path(entry_path):
			reader.close()
			DirAccess.remove_absolute(tmp_path)
			return _extract_error("안전하지 않은 경로가 들어 있어 거부합니다: \"%s\"" % entry_path)
		var ext := entry_path.get_extension().to_lower()
		if not PACK_ALLOWED_EXTENSIONS.has(ext):
			reader.close()
			DirAccess.remove_absolute(tmp_path)
			return _extract_error("허용되지 않는 파일 형식이 들어 있어 거부합니다: \"%s\"" % entry_path)
		file_entries.append(entry_path)

	var manifest_bytes := reader.read_file(MANIFEST_FILENAME)
	var parsed = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		reader.close()
		DirAccess.remove_absolute(tmp_path)
		return _extract_error("manifest.json이 올바른 JSON 형식이 아닙니다.")

	var manifest_profile := CharacterProfileScript.from_dict(parsed, "가져온 팩")
	if manifest_profile == null:
		reader.close()
		DirAccess.remove_absolute(tmp_path)
		return _extract_error("manifest.json의 형식이 올바르지 않습니다(버전 또는 필드 오류).")

	var extracted: Dictionary = {}  # 프로필 폴더 기준 상대경로 -> PackedByteArray
	var total_bytes := manifest_bytes.size()
	for entry_path in file_entries:
		if entry_path == MANIFEST_FILENAME:
			continue
		var bytes := reader.read_file(entry_path)
		total_bytes += bytes.size()
		if total_bytes > PACK_MAX_UNCOMPRESSED_BYTES:
			reader.close()
			DirAccess.remove_absolute(tmp_path)
			return _extract_error("압축을 풀었을 때 크기가 50MB를 넘어 거부합니다.")
		extracted[entry_path] = bytes
		if yield_node != null:
			await yield_node.get_tree().process_frame

	reader.close()
	DirAccess.remove_absolute(tmp_path)

	_drop_missing_references(manifest_profile, extracted)
	return {"ok": true, "error": "", "manifest_profile": manifest_profile, "extracted": extracted}


func _extract_error(message: String) -> Dictionary:
	push_warning("CharacterLibrary.validate_and_extract_pack: %s" % message)
	return {"ok": false, "error": message, "manifest_profile": null, "extracted": {}}


## 남이 만든 zip 파일을 여는 기능이므로 내용을 전혀 신뢰하지 않는다(원칙 6) -
## 실제 검증은 validate_and_extract_pack()이 하고, 여기서는 그 결과를 디스크에
## 쓰는 것만 담당한다. id는 항상 새로 발급한다 - 기존 캐릭터를 덮어쓰지
## 않는다. 반환값: {"ok": bool, "error": String, "profile": CharacterProfile}
## (실패 시 profile은 null).
func import_pack(zip_bytes: PackedByteArray) -> Dictionary:
	var validated := await validate_and_extract_pack(zip_bytes)
	if not validated["ok"]:
		return {"ok": false, "error": validated["error"], "profile": null}

	var manifest_profile: CharacterProfile = validated["manifest_profile"]
	var extracted: Dictionary = validated["extracted"]

	var new_id := _generate_unique_id(manifest_profile.id)
	var dest_dir := CHARACTERS_DIR.path_join(new_id)
	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK:
		return _import_error("캐릭터 폴더를 만들 수 없습니다.")

	for relative_path in extracted:
		var full_path: String = dest_dir.path_join(relative_path)
		if DirAccess.make_dir_recursive_absolute(full_path.get_base_dir()) != OK:
			_remove_dir_recursive(dest_dir)
			return _import_error("파일을 저장할 폴더를 만들 수 없습니다: \"%s\"" % relative_path)
		var out_file := FileAccess.open(full_path, FileAccess.WRITE)
		if out_file == null:
			_remove_dir_recursive(dest_dir)
			return _import_error("파일을 쓸 수 없습니다: \"%s\"" % relative_path)
		out_file.store_buffer(extracted[relative_path])
		out_file.close()

	var new_profile := CharacterProfileScript.new()
	new_profile.id = new_id
	new_profile.display_name = manifest_profile.display_name
	new_profile.portrait_file = manifest_profile.portrait_file
	new_profile.thumbnail_file = manifest_profile.thumbnail_file
	new_profile.voice_map = manifest_profile.voice_map.duplicate(true)
	new_profile.volume_db = manifest_profile.volume_db

	if not save_profile(new_profile):
		_remove_dir_recursive(dest_dir)
		return _import_error("manifest.json을 저장할 수 없습니다.")

	return {"ok": true, "error": "", "profile": new_profile, "warning": _pack_size_advisory(new_profile, extracted)}


## 가져오기는 이미 통과한(신뢰 검증 완료) 팩에 대해 "거부"가 아니라 "권고"만
## 한다 - 편집 화면에서 새로 올릴 때 쓰는 것과 같은 CharacterLimits 기준을
## 재사용하되, 남이 이미 만든 파일이니 못 쓰게 막을 이유는 없다. 문제가 하나도
## 없으면 빈 문자열을 돌려준다.
func _pack_size_advisory(profile: CharacterProfile, extracted: Dictionary) -> String:
	var issues: Array[String] = []

	if profile.portrait_file != "" and extracted.has(profile.portrait_file):
		var bytes: PackedByteArray = extracted[profile.portrait_file]
		var texture := AssetLoader.load_texture_from_bytes(bytes)
		if texture != null:
			var check := CharacterLimitsScript.check_image(texture.get_width(), texture.get_height(), bytes.size(), "portrait")
			if not check["ok"]:
				issues.append("스탠딩 이미지 - %s" % check["message"])

	if profile.thumbnail_file != "" and extracted.has(profile.thumbnail_file):
		var bytes: PackedByteArray = extracted[profile.thumbnail_file]
		var texture := AssetLoader.load_texture_from_bytes(bytes)
		if texture != null:
			var check := CharacterLimitsScript.check_image(texture.get_width(), texture.get_height(), bytes.size(), "thumbnail")
			if not check["ok"]:
				issues.append("썸네일 - %s" % check["message"])

	for key in profile.voice_map:
		for filename in profile.voice_map[key]:
			if not extracted.has(filename):
				continue
			var bytes: PackedByteArray = extracted[filename]
			var duration_sec := 0.0
			var stream := AssetLoader.load_audio_from_bytes(bytes)
			if stream != null:
				duration_sec = stream.get_length()
			var check := CharacterLimitsScript.check_voice(bytes.size(), filename, duration_sec)
			if not check["ok"]:
				issues.append("보이스(%s) - %s" % [filename.get_file(), check["message"]])

	var total := compute_pack_size(profile)
	if total > CharacterLimitsScript.TOTAL_WARNING_BYTES:
		issues.append("전체 용량 %s로 권장 상한(%s)을 넘었습니다. 온라인에서 상대에게 전송되지 않을 수 있습니다." % [
			CharacterLimitsScript.format_bytes(total), CharacterLimitsScript.format_bytes(CharacterLimitsScript.TOTAL_WARNING_BYTES)
		])

	return "\n\n".join(issues)


## manifest이 가리키는데 실제로는 zip 안에 없던 파일은 조용히 참조를 지운다
## (팩 전체를 거부하는 대신). 이런 팩은 애초에 우리 exporter가 만든 게
## 아니거나 손상된 것이지만, 초상/보이스 하나가 없다고 캐릭터 전체를 못 쓰게
## 할 필요는 없다 - CharacterPortrait/VoiceBank가 어차피 파일이 없으면 폴백
## 처리를 이미 하고 있다.
func _drop_missing_references(profile: CharacterProfile, extracted: Dictionary) -> void:
	if profile.portrait_file != "" and not extracted.has(profile.portrait_file):
		push_warning("CharacterLibrary.import_pack: portrait_file이 zip에 없어 무시함 - %s" % profile.portrait_file)
		profile.portrait_file = ""
	if profile.thumbnail_file != "" and not extracted.has(profile.thumbnail_file):
		push_warning("CharacterLibrary.import_pack: thumbnail_file이 zip에 없어 무시함 - %s" % profile.thumbnail_file)
		profile.thumbnail_file = ""

	var sanitized_voice_map := {}
	for key in profile.voice_map:
		var kept: Array[String] = []
		for filename in profile.voice_map[key]:
			if extracted.has(filename):
				kept.append(filename)
			else:
				push_warning("CharacterLibrary.import_pack: 보이스 파일이 zip에 없어 무시함 - %s" % filename)
		if not kept.is_empty():
			sanitized_voice_map[key] = kept
	profile.voice_map = sanitized_voice_map


## zip 항목 경로가 프로필 폴더 밖으로 나가지 않는지 검사한다(zip slip 방지).
## ZIPReader/Godot의 경로 함수는 항상 "/"만 경로 구분자로 다루므로 백슬래시
## 자체는 여기서 당장 탈출에 못 쓰이지만, 이 문자가 들어있는 zip은 다른 도구
## (Windows 탐색기 등에서 그대로 풀 때)에서 위험할 수 있어 방어적으로 같이 거부한다.
func _is_safe_pack_path(path: String) -> bool:
	if path.is_empty():
		return false
	if path.contains("\\") or path.contains(".."):
		return false
	if path.is_absolute_path():
		return false
	return true


func _import_error(message: String) -> Dictionary:
	push_warning("CharacterLibrary.import_pack: %s" % message)
	return {"ok": false, "error": message, "profile": null}


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
