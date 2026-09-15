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
# 항목 수(64개)만 세던 예전 상한은 실제 메모리 사용량과 안 맞았다 - 캐시가
# 들고 있는 건 원본 압축 바이트가 아니라 **디코딩된** Texture2D/AudioStream이라,
# 2048x2048 RGBA 텍스처 한 장만 해도 16MB(width*height*4)다. 64개가 전부
# 그 정도 해상도면 캐시 하나로 1GB 가까이 커질 수 있어서, 실제로 캐릭터를
# 여러 개 바꿔가며 보는 시나리오(1-8 웹 테스트)에서 브라우저 탭이 죽을 수
# 있었다. 그래서 개수 상한과 별개로 "추정 메모리 총합" 상한을 두고, 둘 중
# 하나라도 넘으면 오래된 것부터 지운다(CacheState 참고).
const MAX_CACHE_ENTRIES := 64

# 이미지 캐시 150MB, 오디오 캐시 50MB - 브라우저 탭 하나가 각종 오버헤드
# (WASM 힙, 오디오 버퍼, 렌더링 등) 없이도 편하게 감당할 수 있는 수준을
# 넉넉히 보수적으로 잡았다. 150MB는 2048x2048(스탠딩 상한, CharacterLimits
# 참고) 텍스처를 약 9장 동시에 들고 있을 수 있는 양이라, 실제로는 대부분
# 그보다 작은 이미지를 쓰므로 훨씬 여유가 있다. 둘 다 별도의 script 상수라
# 나중에 실측 후 조정하기 쉽다.
const MAX_TEXTURE_CACHE_BYTES := 150 * 1024 * 1024
const MAX_AUDIO_CACHE_BYTES := 50 * 1024 * 1024

const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const JPEG_SIGNATURE: PackedByteArray = [0xFF, 0xD8, 0xFF]
const RIFF_SIGNATURE: PackedByteArray = [0x52, 0x49, 0x46, 0x46]  # "RIFF"
const WEBP_SIGNATURE: PackedByteArray = [0x57, 0x45, 0x42, 0x50]  # "WEBP" (RIFF 8바이트 뒤)
const WAVE_SIGNATURE: PackedByteArray = [0x57, 0x41, 0x56, 0x45]  # "WAVE" (RIFF 8바이트 뒤)
const OGG_SIGNATURE: PackedByteArray = [0x4F, 0x67, 0x67, 0x53]  # "OggS"
const ID3_SIGNATURE: PackedByteArray = [0x49, 0x44, 0x33]  # "ID3" (ID3v2 태그가 붙은 mp3)

var _texture_cache := CacheState.new(MAX_CACHE_ENTRIES, MAX_TEXTURE_CACHE_BYTES)
var _audio_cache := CacheState.new(MAX_CACHE_ENTRIES, MAX_AUDIO_CACHE_BYTES)


func load_texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null

	var key := _hash_bytes(bytes)
	var cached: Texture2D = _texture_cache.get_cached(key)
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
	# 디코딩된 텍스처의 실제 메모리는 압축 전 원본 파일 크기와 무관하다 -
	# 원본이 잘 압축된 PNG/WebP라도 픽셀 데이터는 항상 width*height*채널수만큼
	# 풀린다. 채널 수를 이미지마다 따지는 대신 RGBA(4바이트/픽셀) 기준으로
	# 넉넉하게 추정한다 - 과소평가보다 과대평가가 안전하다.
	var estimated_bytes := image.get_width() * image.get_height() * 4
	_texture_cache.put(key, texture, estimated_bytes)
	return texture


func load_audio_from_bytes(bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null

	var key := _hash_bytes(bytes)
	var cached: AudioStream = _audio_cache.get_cached(key)
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

	# 오디오는 이미지와 달리 원본 압축 바이트 크기를 그대로 메모리 추정치로
	# 써도 된다 - WAV는 애초에 압축이 거의 없어 파일 크기가 곧 데이터 크기에
	# 가깝고, OGG/MP3는 Godot이 재생 시점에 그때그때 스트리밍 디코딩하지
	# 전체를 한꺼번에 PCM으로 풀어서 들고 있지 않으므로, 상주 메모리도 파일
	# 크기에 훨씬 가깝다(이미지처럼 "압축 해제 후 크기"가 따로 없음).
	_audio_cache.put(key, stream, bytes.size())
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


## 지금 캐시가 실제로 얼마나 차 있는지. DEBUG_MODE 화면 표시(debug_hotkeys.gd)가
## 쓴다 - 개수 상한/메모리 상한을 실측으로 조정하려면 이 수치를 봐야 한다.
func get_cache_stats() -> Dictionary:
	return {
		"texture_count": _texture_cache.count(),
		"texture_bytes": _texture_cache.total_bytes(),
		"audio_count": _audio_cache.count(),
		"audio_bytes": _audio_cache.total_bytes(),
	}


## LRU 캐시 하나의 상태(항목/추정 메모리 총합)를 들고 있는다. 텍스처 캐시와
## 오디오 캐시가 상한만 다르고 동작은 완전히 같아서(둘 다 "개수 또는 총
## 바이트 중 하나라도 넘으면 가장 오래된 것부터 지운다") 로직을 한 곳에
## 모았다 - 두 캐시가 서로 다르게 동작하는 사고를 막기 위함.
class CacheState:
	extends RefCounted

	var _values: Dictionary = {}  # key -> 캐싱된 값(Texture2D/AudioStream)
	var _sizes: Dictionary = {}  # key -> 추정 바이트(값과 별도로 들고 있어야 지울 때 총합에서 뺄 수 있음)
	var _total_bytes: int = 0
	var _max_entries: int
	var _max_bytes: int


	func _init(max_entries: int, max_bytes: int) -> void:
		_max_entries = max_entries
		_max_bytes = max_bytes


	func get_cached(key: String):
		if not _values.has(key):
			return null
		var value = _values[key]
		var size: int = _sizes[key]
		# 맨 뒤로 옮겨서 "가장 최근 사용됨"으로 표시(Dictionary는 삽입 순서 유지).
		_values.erase(key)
		_sizes.erase(key)
		_values[key] = value
		_sizes[key] = size
		return value


	func put(key: String, value, estimated_bytes: int) -> void:
		if _values.has(key):
			_total_bytes -= _sizes[key]
			_values.erase(key)
			_sizes.erase(key)

		_values[key] = value
		_sizes[key] = estimated_bytes
		_total_bytes += estimated_bytes

		while not _values.is_empty() and (_values.size() > _max_entries or _total_bytes > _max_bytes):
			var oldest_key = _values.keys()[0]
			_total_bytes -= _sizes[oldest_key]
			_values.erase(oldest_key)
			_sizes.erase(oldest_key)


	func count() -> int:
		return _values.size()


	func total_bytes() -> int:
		return _total_bytes
