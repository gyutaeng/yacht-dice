@tool
extends EditorExportPlugin

# _export_begin()은 파일을 실제로 패킹하기 전, 프로젝트 파일시스템을 스캔하는
# 시점보다 먼저 호출된다. 그래서 여기서 res://build_info.gd의 BUILD_TIME 줄만
# 새 시각으로 바꿔두면, 이번 export의 pck에 방금 쓴 새 시각이 그대로 들어간다.
# 에디터 GUI로 내보내든 `godot --headless --export-release`로 내보내든 똑같이
# 동작한다 - 사람이 매번 시각을 손으로 갱신할 필요가 없게 하려고 export
# 파이프라인 자체에 걸었다.
#
# 전체 파일을 다시 만들지 않고 BUILD_TIME 한 줄만 정규식으로 치환하는 이유:
# build_info.gd의 _ready()/_stamp_browser() 로직을 여기 문자열로 또 베껴두면
# 나중에 그 로직을 고칠 때마다 두 군데를 같이 고쳐야 해서 어긋나기 쉽다.

const BUILD_INFO_PATH := "res://build_info.gd"
const BUILD_TIME_PATTERN := "(?m)^const BUILD_TIME := \".*\"$"


func _get_name() -> String:
	return "BuildStamp"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var timestamp: String = Time.get_datetime_string_from_system(false, true).substr(0, 16)

	# 베타 배포 후(사용자 요청) - DEBUG_MODE가 이제 build_info.gd의 상수가
	# 아니라 export 프리셋의 Custom Features 태그("yd_release")로 결정되므로
	# (build_info.gd 주석 참고), 사람이 export 버튼을 누르는 그 순간에
	# "이번 빌드가 개발용/배포용 중 뭔지" 콘솔에 바로 보여준다 - 실행 결과를
	# 기다리지 않고 export 시점에 바로 확인할 수 있게(런타임 확인은 게임
	# 시작 시 빌드 배너의 "디버그 켜짐/꺼짐" 표시가 따로 해준다).
	if features.has("yd_release"):
		print("BuildStamp: 배포용 빌드(yd_release 태그 있음) - DEBUG_MODE 꺼짐")
	else:
		print("BuildStamp: 개발용 빌드(yd_release 태그 없음) - DEBUG_MODE 켜짐")

	var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.READ)
	if file == null:
		push_error("BuildStamp: %s를 읽을 수 없음 (%s)" % [BUILD_INFO_PATH, error_string(FileAccess.get_open_error())])
		return
	var content := file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile(BUILD_TIME_PATTERN)
	if regex.search(content) == null:
		push_error("BuildStamp: %s에서 BUILD_TIME 줄을 못 찾음 - 형식이 바뀌었을 수 있음" % BUILD_INFO_PATH)
		return
	var new_content := regex.sub(content, "const BUILD_TIME := \"%s\"" % timestamp, true)

	var out := FileAccess.open(BUILD_INFO_PATH, FileAccess.WRITE)
	if out == null:
		push_error("BuildStamp: %s에 쓸 수 없음 (%s)" % [BUILD_INFO_PATH, error_string(FileAccess.get_open_error())])
		return
	out.store_string(new_content)
	out.close()
	print("BuildStamp: 빌드 시각을 %s로 찍음" % timestamp)
