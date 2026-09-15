class_name FilePickerWeb
extends FilePicker

# 웹 구현: 직접 짠 JS 브릿지(create_callback + 커스텀 <input>)로 여러 번
# 고쳐봤지만 "선택창은 뜨는데 change/cancel 콜백이 Godot으로 전혀 안 돌아옴"
# 증상을 못 잡아서, 검증된 애드온(godot-file-access-web)의 콜백 처리 코드를
# 그대로 가져다 쓰기로 했다.
#
# 원본: https://github.com/Scrawach/godot-file-access-web (MIT License,
# Copyright (c) 2023 Scrawach) - 라이선스 전문은 addons/FileAccessWeb/LICENSE.txt.
# 벤더링한 파일: addons/FileAccessWeb/core/file_access_web.gd (수정 없이 그대로).
#
# 원본과 우리 FilePicker 인터페이스의 차이를 이 얇은 껍데기에서 흡수한다:
# - 원본은 결과를 base64 문자열로 준다(loaded 시그널의 세 번째 인자) ->
#   Marshalls.base64_to_raw()로 PackedByteArray로 바꿔서 _finalize_pick()에
#   넘긴다(확장자 재검사는 그쪽 로직을 그대로 재사용).
# - 원본은 한 번에 파일 1개만 지원한다(<input>에 multiple 속성이 없고 JS
#   onchange가 files[0]만 읽음). 그래서 pick_files(extensions, multiple)의
#   multiple=true는 웹에서는 무시되고 로그로 경고만 남긴다 - 데스크톱은
#   FileDialog가 이미 다중 선택을 지원하므로 영향 없다.

# class_name 전역 등록에 기대지 않고 preload로 직접 참조한다 - .godot의
# 전역 스크립트 클래스 캐시가 아직 새로 추가된 애드온을 못 봤을 때
# "FileAccessWeb 타입을 찾을 수 없음" 컴파일 에러가 나는 걸 피하기 위함.
const FileAccessWebScript := preload("res://addons/FileAccessWeb/core/file_access_web.gd")

var _uploader: RefCounted
var _pending_extensions: Array[String] = []


func pick_files(extensions: Array[String], multiple: bool) -> void:
	_pending_extensions = extensions

	if _uploader == null:
		_uploader = FileAccessWebScript.new()
		_uploader.load_started.connect(_on_load_started)
		_uploader.loaded.connect(_on_loaded)
		_uploader.progress.connect(_on_progress)
		_uploader.error.connect(_on_error)
		_uploader.upload_cancelled.connect(_on_upload_cancelled)

	if multiple:
		_debug("웹 구현(FileAccessWeb 애드온)은 다중 선택을 지원하지 않음 - 1개만 받는다")

	var accept := ""
	for i in extensions.size():
		if i > 0:
			accept += ","
		accept += "." + extensions[i]

	_debug("파일 선택창을 여는 중 (허용 확장자: %s)" % accept)
	_uploader.open(accept)


func _on_load_started(file_name: String) -> void:
	_debug("파일 로딩 시작 - %s" % file_name)


func _on_progress(current_bytes: int, total_bytes: int) -> void:
	_debug("읽는 중 - %d / %d바이트" % [current_bytes, total_bytes])


func _on_loaded(file_name: String, file_type: String, base64_data: String) -> void:
	_debug("데이터 도착 - %s (%s, base64 문자열 길이 %d)" % [file_name, file_type, base64_data.length()])
	var bytes := Marshalls.base64_to_raw(base64_data)
	_debug("PackedByteArray 변환 완료 - %d바이트" % bytes.size())
	_finalize_pick([{"name": file_name, "bytes": bytes}], _pending_extensions)


func _on_error() -> void:
	_debug("파일 읽기 오류(브라우저 error 이벤트) - 선택 취소로 처리")
	pick_cancelled.emit()


func _on_upload_cancelled() -> void:
	_debug("선택 취소됨(브라우저 cancel 이벤트)")
	pick_cancelled.emit()
