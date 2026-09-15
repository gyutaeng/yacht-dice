class_name ReceivedPackCache
extends RefCounted

# 온라인에서 받은 남의 캐릭터 팩을 user://characters/와 완전히 분리된 자리에
# 캐시한다(2-5) - user://characters/는 "내" 캐릭터 목록이라 남의 캐릭터가
# 섞이면 안 된다. 해시(sha256, 팩 바이트 전체 기준)를 폴더 이름으로 써서
# "같은 캐릭터를 이미 받은 적 있는지"를 파일 하나 존재 여부로 바로 확인할
# 수 있다 - 재접속해도 디스크(웹은 IndexedDB)에 남아있으니 다시 안 받는다.
#
const CACHE_DIR := "user://cache/received"
const MANIFEST_FILENAME := "manifest.json"

# 최대 팩 크기(CharacterLimits.TOTAL_WARNING_BYTES, 15MB)의 4배 - 한 판에
# 최대 3명분을 받지만, 여러 판에 걸쳐 마주친 상대 몇 명 분량을 넉넉히
# 보관해서 재접속/재대전 때 다시 안 받게 하는 게 목적이다.
const MAX_CACHE_BYTES := 4 * 15 * 1024 * 1024


static func sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## 이 해시의 팩을 이미 캐시하고 있으면 true - 있으면 네트워크로 다시 안
## 받고 로컬 것을 그대로 쓴다(2-5 §1단계 요구사항).
static func has_cached(hash: String) -> bool:
	if hash.is_empty():
		return false
	return FileAccess.file_exists(_dir_for(hash).path_join(MANIFEST_FILENAME))


## 이미 캐시된 해시를 CharacterProfile로 돌려준다(없으면 null). asset_base_dir을
## 채워서 CharacterLibrary.load_profile_texture()/load_profile_audio()가 여기서
## 읽게 한다.
static func load_cached(hash: String) -> CharacterProfile:
	var dir_path := _dir_for(hash)
	var manifest_path := dir_path.path_join(MANIFEST_FILENAME)
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return null

	var profile := CharacterProfile.from_dict(parsed, "캐시(%s)" % hash)
	if profile == null:
		return null
	profile.asset_base_dir = dir_path
	return profile


## CharacterLibrary.validate_and_extract_pack()이 이미 검증까지 마친 결과를
## user://cache/received/<hash>/에 쓴다(디스크 쓰기 실패 시 profile.asset_bytes를
## 채워 그 판 한정 메모리 전용으로 되돌아간다 - 2-5 §저장이 막힌 환경, 안
## 보이는 것보다 낫다). manifest_profile.id는 그대로 두지 않고 hash로
## 바꾼다 - 여러 사람이 보낸 서로 다른 팩이 우연히 같은 id 문자열을 가질 수
## 있어도(내보낸 사람이 정한 값이라 겹칠 수 있음) 폴더 이름(해시) 자체가
## 충돌하지 않는 고유 키이므로, profile.id도 그 키와 맞춰 혼동을 없앤다.
static func store(hash: String, extracted: Dictionary, manifest_profile: CharacterProfile) -> CharacterProfile:
	var profile := CharacterProfile.new()
	profile.id = hash
	profile.display_name = manifest_profile.display_name
	profile.portrait_file = manifest_profile.portrait_file
	profile.thumbnail_file = manifest_profile.thumbnail_file
	profile.voice_map = manifest_profile.voice_map.duplicate(true)
	profile.volume_db = manifest_profile.volume_db
	profile.is_builtin = false

	var dir_path := _dir_for(hash)
	if not _write_files(dir_path, extracted) or not _write_manifest(dir_path, profile):
		profile.asset_bytes = extracted.duplicate()
		return profile

	profile.asset_base_dir = dir_path
	_evict_if_needed()
	return profile


static func _write_files(dir_path: String, extracted: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		return false
	for relative_path in extracted:
		var full_path: String = dir_path.path_join(relative_path)
		if DirAccess.make_dir_recursive_absolute(full_path.get_base_dir()) != OK:
			return false
		var out_file := FileAccess.open(full_path, FileAccess.WRITE)
		if out_file == null:
			return false
		out_file.store_buffer(extracted[relative_path])
		out_file.close()
	return true


static func _write_manifest(dir_path: String, profile: CharacterProfile) -> bool:
	var file := FileAccess.open(dir_path.path_join(MANIFEST_FILENAME), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(profile.to_dict(), "\t"))
	file.close()
	return true


## MAX_CACHE_BYTES를 넘으면 manifest.json 수정 시각이 가장 오래된 해시
## 폴더부터 지운다(방금 store()한 것도 후보에 포함되지만, 그건 항상 지금
## 막 쓴 것이라 가장 최근이므로 실제로 안 지워진다).
static func _evict_if_needed() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return

	var entries: Array = []  # [{hash, size, modified_msec}]
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var hash_dir := CACHE_DIR.path_join(entry)
			var manifest_path := hash_dir.path_join(MANIFEST_FILENAME)
			entries.append({
				"hash": entry,
				"size": _dir_size(hash_dir),
				"modified": FileAccess.get_modified_time(manifest_path),
			})
		entry = dir.get_next()
	dir.list_dir_end()

	var total := 0
	for e in entries:
		total += e["size"]
	if total <= MAX_CACHE_BYTES:
		return

	entries.sort_custom(func(a, b): return a["modified"] < b["modified"])
	for e in entries:
		if total <= MAX_CACHE_BYTES:
			break
		_remove_dir_recursive(_dir_for(e["hash"]))
		total -= e["size"]


static func _dir_size(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var total := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := dir_path.path_join(entry)
			if dir.current_is_dir():
				total += _dir_size(full_path)
			else:
				var file := FileAccess.open(full_path, FileAccess.READ)
				if file != null:
					total += file.get_length()
					file.close()
		entry = dir.get_next()
	dir.list_dir_end()
	return total


## CharacterLibrary._remove_dir_recursive()와 같은 구현이지만 안전 접두사가
## CACHE_DIR이라 별도로 둔다(그쪽은 user://characters/ 전용으로 하드코딩돼
## 있어 재사용할 수 없음).
static func _remove_dir_recursive(dir_path: String) -> bool:
	var safe_prefix := CACHE_DIR + "/"
	if not dir_path.begins_with(safe_prefix):
		push_error("ReceivedPackCache: 안전하지 않은 삭제 경로라 거부함 - %s" % dir_path)
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


static func _dir_for(hash: String) -> String:
	return CACHE_DIR.path_join(hash)
