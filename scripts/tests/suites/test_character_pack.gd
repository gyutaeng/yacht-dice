extends RefCounted

# 1-7 캐릭터 팩(.zip 내보내기/가져오기)의 검증 로직을 다룬다. 이 기능은
# 남이 만든 파일을 그대로 여는 기능이라(원칙 6) 정상 케이스 하나보다
# 거부 케이스 쪽이 훨씬 중요하다 - manifest.json 스키마, 경로 탈출, 확장자
# 화이트리스트를 각각 따로 검증한다.
#
# user://characters/ 실제 폴더에 만들었다 지우는 통합 테스트라, 테스트마다
# 끝나면(성공하든 실패하든) 반드시 CharacterLibrary.delete()로 정리한다.

const TEST_ID_PREFIX := "test-character-pack-"


func run(r) -> void:
	r.begin_suite("CharacterLibrary 캐릭터 팩 내보내기/가져오기")

	await _test_round_trip_assigns_new_id(r)
	await _test_rejects_missing_manifest(r)
	await _test_rejects_invalid_manifest_schema(r)
	await _test_rejects_unsafe_paths(r)
	await _test_rejects_disallowed_extension(r)


func _make_test_profile(r, suffix: String) -> CharacterProfile:
	var profile := CharacterLibrary.create_new(TEST_ID_PREFIX + suffix)
	if profile == null:
		r.expect_true("테스트 프로필 생성 성공(%s)" % suffix, false)
	return profile


## entries: {zip 안 경로 -> PackedByteArray 또는 String(자동으로 UTF-8 바이트로 변환)}
func _zip_bytes_from_entries(entries: Dictionary) -> PackedByteArray:
	var tmp_path := "user://.test_pack_source_%d.zip" % Time.get_ticks_usec()
	var packer := ZIPPacker.new()
	packer.open(tmp_path)
	for entry_path in entries:
		var value = entries[entry_path]
		var bytes: PackedByteArray = value if value is PackedByteArray else String(value).to_utf8_buffer()
		packer.start_file(entry_path)
		packer.write_file(bytes)
		packer.close_file()
	packer.close()

	var file := FileAccess.open(tmp_path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	DirAccess.remove_absolute(tmp_path)
	return bytes


func _valid_manifest_json(display_name: String = "테스트 팩") -> String:
	return JSON.stringify({
		"format_version": CharacterProfile.FORMAT_VERSION,
		"id": "whatever",  # import_pack은 이 id를 그대로 안 쓰고 새로 발급하므로 아무 값이나 무방하다.
		"display_name": display_name,
		"portrait_file": "",
		"thumbnail_file": "",
		"voice_map": {},
		"volume_db": 0.0,
	})


func _test_round_trip_assigns_new_id(r) -> void:
	var original := _make_test_profile(r, "roundtrip")
	if original == null:
		return

	var portrait_bytes := PackedByteArray([1, 2, 3, 4])
	original.portrait_file = CharacterLibrary.save_asset_bytes(original.id, "", "portrait.png", portrait_bytes)
	original.thumbnail_file = CharacterLibrary.save_asset_bytes(original.id, "", "thumb.png", PackedByteArray([5, 6]))
	original.display_name = "왕복 테스트"
	CharacterLibrary.save_profile(original)

	var zip_bytes := CharacterLibrary.export_pack_bytes(original)
	r.expect_true("내보내기가 빈 바이트를 반환하지 않음", not zip_bytes.is_empty())

	var result := await CharacterLibrary.import_pack(zip_bytes)
	r.expect_true("정상 팩은 가져오기에 성공함", result["ok"])

	if result["ok"]:
		var imported: CharacterProfile = result["profile"]
		r.expect_true("가져온 캐릭터는 원본과 다른 id를 받음(덮어쓰지 않음)", imported.id != original.id)
		r.expect_eq("표시 이름이 그대로 전달됨", imported.display_name, "왕복 테스트")
		r.expect_true("thumbnail_file도 포함되어 전달됨", imported.thumbnail_file != "")

		var imported_portrait_path := CharacterLibrary.CHARACTERS_DIR.path_join(imported.id).path_join(imported.portrait_file)
		var imported_file := FileAccess.open(imported_portrait_path, FileAccess.READ)
		var imported_bytes := imported_file.get_buffer(imported_file.get_length()) if imported_file != null else PackedByteArray()
		if imported_file != null:
			imported_file.close()
		r.expect_eq("복사된 초상 파일의 내용이 원본과 동일함", imported_bytes, portrait_bytes)

		CharacterLibrary.delete(imported.id)

	CharacterLibrary.delete(original.id)


func _test_rejects_missing_manifest(r) -> void:
	var zip_bytes := _zip_bytes_from_entries({"portrait.png": PackedByteArray([1, 2, 3])})
	var result := await CharacterLibrary.import_pack(zip_bytes)
	r.expect_true("manifest.json이 없으면 거부함", not result["ok"])
	r.expect_true("실패 이유에 manifest.json이 언급됨", result["error"].contains("manifest.json"))


func _test_rejects_invalid_manifest_schema(r) -> void:
	var bad_manifest := JSON.stringify({"format_version": 999, "id": "x", "display_name": "y", "voice_map": {}})
	var zip_bytes := _zip_bytes_from_entries({"manifest.json": bad_manifest})
	var result := await CharacterLibrary.import_pack(zip_bytes)
	r.expect_true("알 수 없는 format_version이면 거부함", not result["ok"])


func _test_rejects_unsafe_paths(r) -> void:
	var cases := {
		"상위 폴더 탈출(..)": "../evil.png",
		"백슬래시 경로": "evil\\file.png",
		"절대 경로": "/evil.png",
	}
	for description in cases:
		var zip_bytes := _zip_bytes_from_entries({
			"manifest.json": _valid_manifest_json(),
			cases[description]: PackedByteArray([1, 2, 3]),
		})
		var result := await CharacterLibrary.import_pack(zip_bytes)
		r.expect_true("%s 경로가 있으면 거부함" % description, not result["ok"])


func _test_rejects_disallowed_extension(r) -> void:
	var zip_bytes := _zip_bytes_from_entries({
		"manifest.json": _valid_manifest_json(),
		"malware.exe": PackedByteArray([1, 2, 3]),
	})
	var result := await CharacterLibrary.import_pack(zip_bytes)
	r.expect_true("화이트리스트에 없는 확장자가 있으면 거부함", not result["ok"])
