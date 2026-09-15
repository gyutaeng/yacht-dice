extends Node

# 사용자가 자기 컴퓨터 아무 데서나 고른 이미지/오디오를 안전하게 불러오는 곳.
# 캐릭터 초상화/보이스 업로드, 그리고 나중에 남이 만든 캐릭터 팩(1-7)을 열 때 쓴다.
#
# 원칙 3: 실제 디코딩은 전부 PackedByteArray 기반 함수
# (load_texture_from_bytes/load_audio_from_bytes)로 하고, 경로를 받는 함수는
# 파일을 읽어 바이트로 바꾼 다음 그 함수를 부르는 얇은 래퍼일 뿐이다. bytes 쪽
# 함수는 확장자를 아예 모르므로 내용(시그니처)만 보고 형식을 스스로 판별한다 —
# 그래서 드래그&드롭이나 네트워크로 받은 바이트도 같은 경로를 탄다.
#
# 원칙 6: 외부에서 들어온 파일은 신뢰하지 않는다.
# - 확장자 화이트리스트: 허용 안 된 확장자는 열어보지도 않는다.
# - 크기 상한: FileAccess.get_length()로 파일 전체를 메모리에 올리기 전에 먼저 확인한다.
# - 시그니처(매직 바이트) 검사: 확장자 검사는 "PNG를 .txt로 바꾼 파일"은 막아도
#   "아무 파일이나 .png로 이름만 바꾼 파일"은 못 막는다(한 방향만 막음). 그래서
#   파일 내용의 매직 바이트가 주장하는 확장자와 실제로 일치하는지 추가로 검사한다.
#   둘 중 어느 쪽이 안 맞는지 경고 로그에 남긴다.
#
# 중요: 이 파일의 *_from_path() 함수들은 user:// 파일 전용이다. res:// 안의
# 게임 내장 리소스(효과음 등)에는 절대 쓰지 말 것 — res://의 이미지/오디오는
# export 시 Godot 임포터가 변환한 리소스로 pck에 들어가고 원본 바이트는 안
# 들어가므로, 여기서 FileAccess로 원본을 읽으려 하면 에디터에서는(원본이
# 프로젝트 폴더에 그대로 있어서) 되지만 export된 빌드에서는 조용히 실패한다
# (SfxBank가 실제로 이 버그를 겪었다 - 이제 고쳐서 load()를 쓴다).
# res:// 내장 리소스는 반드시 load()/preload()로 읽는다.

const MAX_IMAGE_BYTES := 8 * 1024 * 1024  # 8MB
const MAX_AUDIO_BYTES := 2 * 1024 * 1024  # 2MB (파일 1개당)
const ALLOWED_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const ALLOWED_AUDIO_EXTENSIONS := ["wav", "ogg", "mp3"]

# sha256 해시 기반 디코딩 캐시. 같은 바이트를 여러 번 디코딩하지 않기 위함이다
# (예: 1-3에서 턴이 바뀔 때마다 같은 캐릭터 텍스처를 다시 만드는 낭비를 막음).
# 항목 수가 상한을 넘으면 가장 오래전에 "쓰인"(생성 또는 마지막 조회) 항목부터
# 버린다(LRU). Dictionary는 삽입 순서를 유지하므로, 조회할 때 항목을 지웠다가
# 다시 넣는 방식으로 "최근 사용"을 맨 뒤로 옮긴다.
const MAX_CACHE_ENTRIES := 64

const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const JPEG_SIGNATURE: PackedByteArray = [0xFF, 0xD8, 0xFF]
const RIFF_SIGNATURE: PackedByteArray = [0x52, 0x49, 0x46, 0x46]  # "RIFF"
const WEBP_SIGNATURE: PackedByteArray = [0x57, 0x45, 0x42, 0x50]  # "WEBP" (RIFF 8바이트 뒤)
const WAVE_SIGNATURE: PackedByteArray = [0x57, 0x41, 0x56, 0x45]  # "WAVE" (RIFF 8바이트 뒤)
const OGG_SIGNATURE: PackedByteArray = [0x4F, 0x67, 0x67, 0x53]  # "OggS"
const ID3_SIGNATURE: PackedByteArray = [0x49, 0x44, 0x33]  # "ID3" (ID3v2 태그가 붙은 mp3)

var _texture_cache: Dictionary = {}  # sha256 hex -> Texture2D
var _audio_cache: Dictionary = {}  # sha256 hex -> AudioStream


func load_texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null

	var key := _hash_bytes(bytes)
	var cached: Texture2D = _cache_get(_texture_cache, key)
	if cached != null:
		return cached

	var image := Image.new()
	var err: Error

	if _has_prefix(bytes, PNG_SIGNATURE):
		err = image.load_png_from_buffer(bytes)
	elif _has_prefix(bytes, JPEG_SIGNATURE):
		err = image.load_jpg_from_buffer(bytes)
	elif _has_prefix(bytes, RIFF_SIGNATURE) and _has_prefix_at(bytes, 8, WEBP_SIGNATURE):
		err = image.load_webp_from_buffer(bytes)
	else:
		push_warning("AssetLoader: 알 수 없는 이미지 형식(시그니처가 PNG/JPEG/WEBP 중 어디에도 안 맞음)")
		return null

	if err != OK:
		push_warning("AssetLoader: 이미지 디코딩 실패 (%s)" % error_string(err))
		return null

	var texture := ImageTexture.create_from_image(image)
	_cache_put(_texture_cache, key, texture)
	return texture


func load_audio_from_bytes(bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null

	var key := _hash_bytes(bytes)
	var cached: AudioStream = _cache_get(_audio_cache, key)
	if cached != null:
		return cached

	var stream: AudioStream = null

	if _has_prefix(bytes, RIFF_SIGNATURE) and _has_prefix_at(bytes, 8, WAVE_SIGNATURE):
		stream = AudioStreamWAV.load_from_buffer(bytes)
	elif _has_prefix(bytes, OGG_SIGNATURE):
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	elif _looks_like_mp3(bytes):
		stream = AudioStreamMP3.load_from_buffer(bytes)
	else:
		push_warning("AssetLoader: 알 수 없는 오디오 형식(시그니처가 WAV/OGG/MP3 중 어디에도 안 맞음)")
		return null

	if stream == null:
		push_warning("AssetLoader: 오디오 디코딩 실패")
		return null

	_cache_put(_audio_cache, key, stream)
	return stream


func load_texture_from_path(path: String, max_bytes: int = MAX_IMAGE_BYTES) -> Texture2D:
	var bytes := _read_file_bytes(path, ALLOWED_IMAGE_EXTENSIONS, max_bytes)
	if bytes.is_empty():
		return null
	return load_texture_from_bytes(bytes)


func load_audio_from_path(path: String, max_bytes: int = MAX_AUDIO_BYTES) -> AudioStream:
	var bytes := _read_file_bytes(path, ALLOWED_AUDIO_EXTENSIONS, max_bytes)
	if bytes.is_empty():
		return null
	return load_audio_from_bytes(bytes)


## 검증(확장자+크기+시그니처)만 통과시키고 디코딩은 하지 않은 원본 바이트를 돌려준다.
## 디코딩 결과가 아니라 원본 바이트 자체가 필요할 때 쓴다(예: 프로필 폴더 안에
## 파일을 그대로 복사해 넣는 경우). 검증에 실패하면 빈 배열을 반환한다.
func read_validated_image_bytes(path: String, max_bytes: int = MAX_IMAGE_BYTES) -> PackedByteArray:
	return _read_file_bytes(path, ALLOWED_IMAGE_EXTENSIONS, max_bytes)


func read_validated_audio_bytes(path: String, max_bytes: int = MAX_AUDIO_BYTES) -> PackedByteArray:
	return _read_file_bytes(path, ALLOWED_AUDIO_EXTENSIONS, max_bytes)


func _read_file_bytes(path: String, allowed_extensions: Array, max_bytes: int) -> PackedByteArray:
	var extension := path.get_extension().to_lower()
	if not allowed_extensions.has(extension):
		push_warning("AssetLoader: 허용되지 않는 확장자(.%s) - %s" % [extension, path])
		return PackedByteArray()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AssetLoader: 파일을 열 수 없음 - %s" % path)
		return PackedByteArray()

	var size := file.get_length()
	if size > max_bytes:
		push_warning("AssetLoader: 파일이 크기 상한을 초과함(%d > %d바이트) - %s" % [size, max_bytes, path])
		file.close()
		return PackedByteArray()

	var bytes := file.get_buffer(size)
	file.close()

	if not _matches_signature(bytes, extension):
		push_warning("AssetLoader: 확장자(.%s)와 실제 파일 내용이 일치하지 않음(위장된 파일일 수 있음) - %s" % [extension, path])
		return PackedByteArray()

	return bytes


func _matches_signature(bytes: PackedByteArray, extension: String) -> bool:
	match extension:
		"png":
			return _has_prefix(bytes, PNG_SIGNATURE)
		"jpg", "jpeg":
			return _has_prefix(bytes, JPEG_SIGNATURE)
		"webp":
			return _has_prefix(bytes, RIFF_SIGNATURE) and _has_prefix_at(bytes, 8, WEBP_SIGNATURE)
		"wav":
			return _has_prefix(bytes, RIFF_SIGNATURE) and _has_prefix_at(bytes, 8, WAVE_SIGNATURE)
		"ogg":
			return _has_prefix(bytes, OGG_SIGNATURE)
		"mp3":
			return _looks_like_mp3(bytes)
	return false


func _looks_like_mp3(bytes: PackedByteArray) -> bool:
	if _has_prefix(bytes, ID3_SIGNATURE):
		return true
	# ID3 태그가 없는 raw mp3: MPEG 프레임 동기 워드(0xFF + 상위 3비트가 전부 1)로 시작한다.
	return bytes.size() >= 2 and bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0


func _has_prefix(bytes: PackedByteArray, expected: PackedByteArray) -> bool:
	return _has_prefix_at(bytes, 0, expected)


func _has_prefix_at(bytes: PackedByteArray, offset: int, expected: PackedByteArray) -> bool:
	if bytes.size() < offset + expected.size():
		return false
	for i in expected.size():
		if bytes[offset + i] != expected[i]:
			return false
	return true


func _hash_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _cache_get(cache: Dictionary, key: String):
	if not cache.has(key):
		return null
	var value = cache[key]
	cache.erase(key)
	cache[key] = value  # 맨 뒤로 옮겨서 "가장 최근 사용됨"으로 표시
	return value


func _cache_put(cache: Dictionary, key: String, value) -> void:
	if cache.has(key):
		cache.erase(key)
	cache[key] = value
	while cache.size() > MAX_CACHE_ENTRIES:
		var oldest_key = cache.keys()[0]
		cache.erase(oldest_key)
