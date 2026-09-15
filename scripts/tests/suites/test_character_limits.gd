extends RefCounted

# CharacterLimits(스탠딩/썸네일/보이스 업로드 권장 상한)와, 그 상한이
# CharacterLibrary(용량 합계 계산, 팩 가져오기 경고)와 올바르게 맞물리는지를
# 검증한다.
#
# user://characters/ 실제 폴더에 만들었다 지우는 통합 테스트라, 테스트마다
# 끝나면(성공하든 실패하든) 반드시 CharacterLibrary.delete()로 정리한다.

const TEST_ID_PREFIX := "test-character-limits-"


func run(r) -> void:
	r.begin_suite("CharacterLimits 업로드 제한")

	_test_format_bytes(r)
	_test_ui_limits_never_exceed_asset_loader_limits(r)
	_test_check_image_within_limits(r)
	_test_check_image_dimension_exceeded_allows_resize(r)
	_test_check_image_bytes_exceeded_blocks_without_resize(r)
	_test_check_voice_within_limit(r)
	_test_check_voice_wav_gets_advisory(r)
	_test_check_voice_non_wav_no_advisory(r)
	_test_check_voice_exceeds_limit(r)
	_test_compute_pack_size(r)
	await _test_import_warns_on_oversized_portrait(r)


func _make_test_profile(r, suffix: String) -> CharacterProfile:
	var profile := CharacterLibrary.create_new(TEST_ID_PREFIX + suffix)
	if profile == null:
		r.expect_true("테스트 프로필 생성 성공(%s)" % suffix, false)
	return profile


func _test_format_bytes(r) -> void:
	r.expect_eq("정확히 4MB는 소수점 없이 표기", CharacterLimits.format_bytes(4 * 1024 * 1024), "4MB")
	var twelve_point_four_mb := int(12.4 * 1024 * 1024)
	r.expect_eq("소수점이 있으면 한 자리까지 표기", CharacterLimits.format_bytes(twelve_point_four_mb), "12.4MB")
	r.expect_eq("1MB 미만은 KB로 표기", CharacterLimits.format_bytes(44 * 1024), "44KB")


## AssetLoader의 상한은 "기술적 최후 방어선"이라, 사용자에게 안내하는
## CharacterLimits의 권장 상한이 그보다 커지면 모순이 생긴다(최후 방어선보다
## 관대한 권장 한도). 상수를 손볼 때 이 관계가 깨지지 않는지 항상 확인한다.
func _test_ui_limits_never_exceed_asset_loader_limits(r) -> void:
	r.expect_true("스탠딩 상한이 AssetLoader 이미지 상한 이하", CharacterLimits.PORTRAIT_MAX_BYTES <= AssetLoader.MAX_IMAGE_BYTES)
	r.expect_true("썸네일 상한이 AssetLoader 이미지 상한 이하", CharacterLimits.THUMBNAIL_MAX_BYTES <= AssetLoader.MAX_IMAGE_BYTES)
	r.expect_true("보이스 상한이 AssetLoader 오디오 상한 이하", CharacterLimits.VOICE_MAX_BYTES <= AssetLoader.MAX_AUDIO_BYTES)


func _test_check_image_within_limits(r) -> void:
	var check := CharacterLimits.check_image(1024, 1536, 1 * 1024 * 1024, "portrait")
	r.expect_true("한도 안이면 통과", check["ok"])


func _test_check_image_dimension_exceeded_allows_resize(r) -> void:
	var check := CharacterLimits.check_image(3840, 5120, 1 * 1024 * 1024, "portrait")
	r.expect_true("픽셀 초과면 거부됨", not check["ok"])
	r.expect_true("픽셀 초과는 자동 축소 대상", check["can_auto_resize"])
	r.expect_true("메시지에 실제 픽셀 크기가 들어감", check["message"].contains("3840x5120"))
	r.expect_true("메시지에 한도가 들어감", check["message"].contains("2048"))


func _test_check_image_bytes_exceeded_blocks_without_resize(r) -> void:
	var check := CharacterLimits.check_image(1024, 1536, 12 * 1024 * 1024, "portrait")
	r.expect_true("용량 초과면 거부됨", not check["ok"])
	r.expect_true("픽셀은 정상이니 자동 축소 대상 아님", not check["can_auto_resize"])


func _test_check_voice_within_limit(r) -> void:
	var check := CharacterLimits.check_voice(512 * 1024, "laugh.ogg")
	r.expect_true("한도 안이면 통과", check["ok"])


func _test_check_voice_wav_gets_advisory(r) -> void:
	var check := CharacterLimits.check_voice(512 * 1024, "laugh.wav")
	r.expect_true("WAV는 한도 안이어도 권고 문구가 붙음", check["advisory"] != "")


func _test_check_voice_non_wav_no_advisory(r) -> void:
	var check := CharacterLimits.check_voice(512 * 1024, "laugh.ogg")
	r.expect_eq("OGG는 권고 문구 없음", check["advisory"], "")


func _test_check_voice_exceeds_limit(r) -> void:
	var check := CharacterLimits.check_voice(2 * 1024 * 1024, "laugh.wav")
	r.expect_true("용량 초과면 거부됨", not check["ok"])


func _test_compute_pack_size(r) -> void:
	var profile := _make_test_profile(r, "size")
	if profile == null:
		return

	var portrait_bytes := PackedByteArray()
	portrait_bytes.resize(1000)
	var voice_bytes := PackedByteArray()
	voice_bytes.resize(2000)

	profile.portrait_file = CharacterLibrary.save_asset_bytes(profile.id, "", "portrait.png", portrait_bytes)
	var voice_name := CharacterLibrary.save_asset_bytes(profile.id, "voices", "laugh.wav", voice_bytes)
	profile.voice_map = {"common.my_turn": [voice_name]}
	CharacterLibrary.save_profile(profile)

	# manifest.json 자체도 합계에 포함되므로 정확히 3000바이트가 아니라 그 이상이다.
	var total := CharacterLibrary.compute_pack_size(profile)
	r.expect_true("초상+보이스+manifest 크기가 전부 합산됨", total >= 3000)

	CharacterLibrary.delete(profile.id)


func _test_import_warns_on_oversized_portrait(r) -> void:
	var profile := _make_test_profile(r, "importwarn")
	if profile == null:
		return

	# 4096x1 픽셀짜리 PNG를 실제로 인코딩해서 넣는다 - CharacterLimits가 실제
	# 디코딩된 텍스처 크기를 보고 판단하므로, 진짜로 그 크기인 이미지가 필요하다.
	var oversized_image := Image.create(4096, 1, false, Image.FORMAT_RGB8)
	var oversized_bytes := oversized_image.save_png_to_buffer()
	profile.portrait_file = CharacterLibrary.save_asset_bytes(profile.id, "", "portrait.png", oversized_bytes)
	CharacterLibrary.save_profile(profile)

	var zip_bytes := CharacterLibrary.export_pack_bytes(profile)
	var result := await CharacterLibrary.import_pack(zip_bytes)

	r.expect_true("한도를 넘어도 가져오기는 허용됨", result["ok"])
	if result["ok"]:
		r.expect_true("경고 메시지가 채워짐", result["warning"] != "")
		r.expect_true("경고 메시지가 픽셀 초과를 언급함", result["warning"].contains("4096"))
		CharacterLibrary.delete(result["profile"].id)

	CharacterLibrary.delete(profile.id)
