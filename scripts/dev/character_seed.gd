extends Node

# ============================================================
# 개발용 — 정식 빌드에는 절대 들어가면 안 된다.
# 캐릭터 생성 UI(1-6)가 아직 없어서, F:/Godot/test_assets/의 이미지로 테스트
# 캐릭터 3개를 user://characters/ 아래에 미리 만들어 둔다. 1-3(캐릭터 자리
# 배정)을 테스트하기 위한 임시 방편이다.
#
# OS.has_feature("editor")가 거짓이면(배포 빌드) _ready()에서 즉시 자기
# 자신을 지워서 아무 일도 하지 않는다.
#
# 1-6에서 진짜 캐릭터 생성 UI가 생기면 이 스크립트는 통째로 지운다.
# ============================================================

const TEST_ASSET_DIR := "F:/Godot/test_assets"

const SEED_CHARACTERS := [
	{"display_name": "테스트A", "portrait_source": "BON.png"},
	{"display_name": "테스트B", "portrait_source": "Betako.png"},
	# 비율이 이상한(가로로 긴) 이미지가 들어와도 레이아웃이 안 깨지는지 보려고 일부러 넣는다.
	{"display_name": "가로이미지", "portrait_source": "landscape_wide.png"},
]


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()
		return

	for entry in SEED_CHARACTERS:
		if _find_by_display_name(entry.display_name) != null:
			print("CharacterSeed: '%s'는 이미 있어서 건너뜀" % entry.display_name)
			continue
		_create_seed_character(entry.display_name, entry.portrait_source)

	queue_free()  # 시드 작업은 1회성이라 끝나면 자기 자신을 지운다.


func _find_by_display_name(display_name: String) -> CharacterProfile:
	for profile in CharacterLibrary.scan():
		if profile.display_name == display_name:
			return profile
	return null


func _create_seed_character(display_name: String, portrait_source_filename: String) -> void:
	var profile := CharacterLibrary.create_new(display_name)
	if profile == null:
		push_error("CharacterSeed: '%s' 생성 실패" % display_name)
		return

	var source_path := TEST_ASSET_DIR.path_join(portrait_source_filename)
	var bytes := AssetLoader.read_validated_image_bytes(source_path)
	if bytes.is_empty():
		push_error("CharacterSeed: '%s'의 초상화를 읽지 못함 - %s" % [display_name, source_path])
		return

	var portrait_filename := "portrait.%s" % portrait_source_filename.get_extension().to_lower()
	var dest_path := CharacterLibrary.CHARACTERS_DIR.path_join(profile.id).path_join(portrait_filename)
	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		push_error("CharacterSeed: '%s'의 초상화 파일을 쓸 수 없음 - %s" % [display_name, dest_path])
		return
	file.store_buffer(bytes)
	file.close()

	profile.portrait_file = portrait_filename
	CharacterLibrary.save_profile(profile)

	print("CharacterSeed: '%s' 생성 완료 (id=%s, portrait=%s)" % [display_name, profile.id, portrait_filename])
