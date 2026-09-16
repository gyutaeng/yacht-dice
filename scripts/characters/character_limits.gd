class_name CharacterLimits
extends RefCounted

# 캐릭터 편집 화면에서 사용자에게 "이 정도까지만 넣어주세요"라고 안내하는
# 권장 상한이다. 2-5에서 캐릭터 팩을 온라인으로 전송할 때 쓸 크기 제한을
# 미리 반영한 값이라, 편집 화면에서 바로 걸러두면 나중에 로비에서 거부당해
# 편집 화면으로 되돌아오는 왕복을 없앨 수 있다.
#
# autoload/asset_loader.gd의 상한(이미지 8MB, 오디오 2MB)은 이것과 다른
# 목적이다 - 그건 "이보다 크면 디코딩 자체를 시도하지 않는" 기술적 최후
# 방어선이고, 여기 값은 항상 그보다 작거나 같아야 한다(안 그러면 최후
# 방어선보다 사용자 안내 상한이 더 관대해지는 모순이 생긴다).
#
# 픽셀 치수 제한은 경고가 아니라 거부다 - 4096x8192 같은 이미지는 텍스처
# 메모리를 수백 MB 잡아먹어서 특히 웹에서 치명적이다.

const PORTRAIT_MAX_DIMENSION := 2048  # 긴 변 기준, px
const PORTRAIT_MAX_BYTES := 4 * 1024 * 1024

const THUMBNAIL_MAX_DIMENSION := 1024
const THUMBNAIL_MAX_BYTES := 1 * 1024 * 1024

const VOICE_MAX_BYTES := 1 * 1024 * 1024

# 용량과 별개인 제한이다(사용자 지적) - WAV는 1MB면 대략 11초라 용량
# 제한이 우연히 길이도 같이 막아주지만, 우리가 권장하는 OGG는 1MB에
# 1~2분이 들어가서 용량만으로는 긴 대사를 못 막는다. 길이 자체가
# 문제인 이유는 1-4C의 보이스 대기열(VOICE_WAIT_TIMEOUT_MSEC, 1.5초) -
# 대사 하나가 길게 재생되는 동안 그 사이에 일어난 다른 이벤트(야추,
# 보너스, 상대 차례 등)의 보이스 요청이 대기열에서 조용히 밀려나거나
# 버려진다. 런타임에 오디오를 잘라낼 수는 없으므로(1-7B와 같은 원칙 -
# 자동 변환이 불가능한 제약은 거부하고 안내만 한다) 업로드 시점에
# 거부한다.
const VOICE_MAX_DURATION_SEC := 7.0

# 캐릭터 전체(초상+썸네일+보이스 전부 합계) 상한. RECOMMENDED를 넘으면 노란색
# 경고, WARNING을 넘으면 빨간색 경고 - 다만 이 둘은 저장 자체를 막지 않는다
# (개별 파일 상한과 달리 "권장"일 뿐이다).
const TOTAL_RECOMMENDED_BYTES := 10 * 1024 * 1024
const TOTAL_WARNING_BYTES := 15 * 1024 * 1024


## 사람이 읽기 좋은 용량 표기. 1MB 미만은 "512KB"처럼 KB로(안 그러면 작은
## 파일이 죄다 "0.0MB"로 뭉개져 보인다). 1MB 이상은 정확히 나눠떨어지면
## "4MB", 아니면 "12.4MB"처럼 소수점 한 자리까지("4.0MB" 같은 어색한 표기를 피함).
static func format_bytes(byte_count: int) -> String:
	if byte_count < 1024 * 1024:
		return "%dKB" % int(round(byte_count / 1024.0))
	var mb := byte_count / 1024.0 / 1024.0
	if is_equal_approx(mb, roundf(mb)):
		return "%dMB" % int(round(mb))
	return "%.1fMB" % mb


## 스탠딩/썸네일 이미지 하나를 검사한다. kind는 "portrait" 또는 "thumbnail".
## 반환: {"ok": bool, "message": String(ok=false일 때만 의미 있음),
## "can_auto_resize": bool(픽셀 초과가 원인일 때만 true - Image.resize()로
## 해결 가능하다는 뜻)}.
##
## 메시지는 항상 같은 형식이다(어떤 한도를 넘었든): 지금 몇 px/MB인지 -> 한도가
## 얼마인지 -> 어떻게 줄이는지. 사용자가 "용량이 큽니다" 한 줄만 보고 뭘 해야
## 할지 몰라 헤매는 걸 막기 위해 셋을 항상 같이 준다.
static func check_image(width: int, height: int, byte_size: int, kind: String) -> Dictionary:
	var max_dimension: int = PORTRAIT_MAX_DIMENSION if kind == "portrait" else THUMBNAIL_MAX_DIMENSION
	var max_bytes: int = PORTRAIT_MAX_BYTES if kind == "portrait" else THUMBNAIL_MAX_BYTES
	var kind_label: String = "스탠딩" if kind == "portrait" else "썸네일"

	var long_side := maxi(width, height)
	var dimension_exceeded := long_side > max_dimension
	var bytes_exceeded := byte_size > max_bytes

	if not dimension_exceeded and not bytes_exceeded:
		return {"ok": true}

	var message := (
		"이 이미지는 %dx%d, %s입니다. %s는 긴 변 %dpx, %s까지 넣을 수 있어요. "
		+ "크기를 줄이거나 WebP로 저장하면 훨씬 작아집니다.\n"
		+ "(투명 배경이 필요하면 PNG 대신 WebP를 쓰세요. 보통 1/3~1/5로 줄어듭니다)"
	) % [width, height, format_bytes(byte_size), kind_label, max_dimension, format_bytes(max_bytes)]

	return {"ok": false, "message": message, "can_auto_resize": dimension_exceeded}


## 보이스 파일 하나를 검사한다. duration_sec은 AudioStream.get_length()로 잰
## 실제 재생 길이(초) - wav/ogg/mp3 전부에서 정확히 동작함을 실측 확인함.
## 반환: {"ok": bool, "message": String(ok=false일 때만), "advisory": String(한도
## 안에 들어와도 WAV라서 권고할 게 있으면 채워짐, 없으면 "")}. advisory는
## 거부가 아니라 "그냥 알려주는 것"이라 ok=true여도 같이 온다.
static func check_voice(byte_size: int, file_name: String, duration_sec: float) -> Dictionary:
	if byte_size > VOICE_MAX_BYTES:
		var message := (
			"이 파일은 %s입니다. 보이스 하나는 %s까지 넣을 수 있어요. "
			+ "WAV는 압축이 없어서 큽니다. OGG나 MP3로 변환하면 보통 10배 작아집니다."
		) % [format_bytes(byte_size), format_bytes(VOICE_MAX_BYTES)]
		return {"ok": false, "message": message, "advisory": ""}

	if duration_sec > VOICE_MAX_DURATION_SEC:
		var message := (
			"이 파일은 %.1f초입니다. 보이스 하나는 %.0f초까지 넣을 수 있어요. "
			+ "오디오 편집 프로그램에서 잘라서 다시 올려주세요."
		) % [duration_sec, VOICE_MAX_DURATION_SEC]
		return {"ok": false, "message": message, "advisory": ""}

	return {"ok": true, "message": "", "advisory": _wav_advisory(file_name)}


static func _wav_advisory(file_name: String) -> String:
	if file_name.get_extension().to_lower() == "wav":
		return "WAV 파일이에요. OGG나 MP3로 바꾸면 훨씬 작아져서 나중에 온라인에서 캐릭터를 주고받을 때 유리합니다."
	return ""


## 캐릭터 전체 용량이 권장 상한을 넘었는지에 따라 표시 색을 고른다. UI가
## "노랑/빨강" 색상값을 직접 들고 있지 않고 여기서 한 곳에서만 기준을 정한다.
static func total_size_color(total_bytes: int) -> Color:
	if total_bytes > TOTAL_WARNING_BYTES:
		return Color(1.0, 0.4, 0.4)
	if total_bytes > TOTAL_RECOMMENDED_BYTES:
		return Color(1.0, 0.85, 0.3)
	return Color(1, 1, 1, 0.8)
