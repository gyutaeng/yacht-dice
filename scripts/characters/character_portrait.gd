class_name CharacterPortrait
extends RefCounted

# 프로필의 어느 파일(portrait_file/thumbnail_file)을 읽어야 하는지, 못 읽으면
# 무엇으로 대신할지를 결정하는 순수 로직. Main.gd(게임 화면)와 캐릭터 선택
# 화면(1-6)이 똑같은 규칙이 필요해서 공유 유틸로 뽑았다. TextureRect를 직접
# 만지지 않는다 - 그건 호출부와 TextureFit의 몫이다.

const PLACEHOLDER_PORTRAIT_PATH := "res://assets/placeholder_portrait.png"

static var _placeholder_texture: Texture2D


static func placeholder() -> Texture2D:
	if _placeholder_texture == null:
		_placeholder_texture = load(PLACEHOLDER_PORTRAIT_PATH)
	return _placeholder_texture


static func load_character_file_texture(profile: CharacterProfile, filename: String) -> Texture2D:
	return CharacterLibrary.load_profile_texture(profile, filename)


## 큰 초상화가 없거나(portrait_file 비어 있음) 로딩에 실패하면 실루엣
## 플레이스홀더로 대체한다. 어떤 경우에도 빈 화면이 나오면 안 된다.
static func resolve_display_texture(profile: CharacterProfile) -> Texture2D:
	var texture := load_character_file_texture(profile, profile.portrait_file if profile != null else "")
	return texture if texture != null else placeholder()


## 작은 초상(이름표 썸네일)에 쓸 텍스처를 고른다. thumbnail_file이 있고
## 로딩에 성공하면 그것을, 아니면 큰 초상/실루엣 폴백(resolve_display_texture)을 쓴다.
static func resolve_thumbnail_texture(profile: CharacterProfile) -> Texture2D:
	if profile != null:
		var dedicated := load_character_file_texture(profile, profile.thumbnail_file)
		if dedicated != null:
			return dedicated
	return resolve_display_texture(profile)


## 작은 초상에 전용 thumbnail_file 이미지를 쓰는 경우에만 true(가운데 기준 크롭).
## portrait_file로 폴백한 경우나 실루엣인 경우는 false(위쪽 기준 크롭 - 전신
## 일러스트를 정사각형에 채울 때 얼굴이 있을 위쪽을 기준으로 잘라낸다).
static func thumbnail_should_center_crop(profile: CharacterProfile) -> bool:
	if profile == null:
		return false
	return load_character_file_texture(profile, profile.thumbnail_file) != null
