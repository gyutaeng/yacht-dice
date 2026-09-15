extends RefCounted

# CharacterLibrary의 파일 저장/정리 로직만 다룬다(scan/create_new/delete/
# duplicate_profile은 이미 오래 써온 기존 기능이라 여기서 새로 검증하지 않음).
# 1-6에서 새로 추가한 두 가지를 검증한다: save_asset_bytes()의 이름 충돌
# 처리, 그리고 save_profile()이 manifest가 안 가리키는 파일을 정리하는지.
#
# user://characters/ 실제 폴더에 만들었다 지우는 통합 테스트라, 테스트마다
# 끝나면(성공하든 실패하든) 반드시 CharacterLibrary.delete()로 정리한다.

const TEST_ID_PREFIX := "test-character-library-"


func run(r) -> void:
	r.begin_suite("CharacterLibrary 파일 저장/정리")

	_test_save_asset_bytes_and_collision(r)
	_test_cleanup_removes_unreferenced_files(r)
	_test_cleanup_keeps_referenced_files(r)
	_test_cleanup_removes_empty_voices_dir(r)


func _make_test_profile(r, suffix: String) -> CharacterProfile:
	var profile := CharacterLibrary.create_new(TEST_ID_PREFIX + suffix)
	if profile == null:
		r.expect_true("테스트 프로필 생성 성공(%s)" % suffix, false)
	return profile


func _test_save_asset_bytes_and_collision(r) -> void:
	var profile := _make_test_profile(r, "collision")
	if profile == null:
		return

	var bytes := PackedByteArray([1, 2, 3])
	var first := CharacterLibrary.save_asset_bytes(profile.id, "", "portrait.png", bytes)
	r.expect_eq("첫 저장은 원래 이름 그대로", first, "portrait.png")

	var second := CharacterLibrary.save_asset_bytes(profile.id, "", "portrait.png", bytes)
	r.expect_eq("이름이 겹치면 -2가 붙음(확장자 유지)", second, "portrait-2.png")

	var voice := CharacterLibrary.save_asset_bytes(profile.id, "voices", "laugh.wav", bytes)
	r.expect_eq("voices 서브디렉터리는 상대경로에 voices/가 붙음", voice, "voices/laugh.wav")

	CharacterLibrary.delete(profile.id)


func _test_cleanup_removes_unreferenced_files(r) -> void:
	var profile := _make_test_profile(r, "orphan")
	if profile == null:
		return

	CharacterLibrary.save_asset_bytes(profile.id, "", "unused.png", PackedByteArray([1, 2, 3]))
	# profile.portrait_file을 안 채웠으니 unused.png는 어디에도 참조되지 않는다.
	CharacterLibrary.save_profile(profile)

	var still_exists := FileAccess.file_exists(
		CharacterLibrary.CHARACTERS_DIR.path_join(profile.id).path_join("unused.png")
	)
	r.expect_true("참조 안 된 파일은 저장 시 삭제됨", not still_exists)

	CharacterLibrary.delete(profile.id)


func _test_cleanup_keeps_referenced_files(r) -> void:
	var profile := _make_test_profile(r, "keep")
	if profile == null:
		return

	var saved_name := CharacterLibrary.save_asset_bytes(profile.id, "", "portrait.png", PackedByteArray([1, 2, 3]))
	profile.portrait_file = saved_name
	CharacterLibrary.save_profile(profile)

	var still_exists := FileAccess.file_exists(
		CharacterLibrary.CHARACTERS_DIR.path_join(profile.id).path_join("portrait.png")
	)
	r.expect_true("참조된 파일은 저장 후에도 남아있음", still_exists)

	CharacterLibrary.delete(profile.id)


func _test_cleanup_removes_empty_voices_dir(r) -> void:
	var profile := _make_test_profile(r, "emptyvoices")
	if profile == null:
		return

	CharacterLibrary.save_asset_bytes(profile.id, "voices", "temp.wav", PackedByteArray([1, 2, 3]))
	# voice_map을 안 채웠으니 temp.wav는 참조되지 않고, 결국 voices/ 폴더도 빈다.
	CharacterLibrary.save_profile(profile)

	var voices_dir_exists := DirAccess.dir_exists_absolute(
		CharacterLibrary.CHARACTERS_DIR.path_join(profile.id).path_join("voices")
	)
	r.expect_true("파일 정리 후 빈 voices 폴더도 같이 지워짐", not voices_dir_exists)

	CharacterLibrary.delete(profile.id)
