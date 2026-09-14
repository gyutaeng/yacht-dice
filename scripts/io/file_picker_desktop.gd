class_name FilePickerDesktop
extends FilePicker

# 데스크톱 구현: Godot의 FileDialog를 실제 파일시스템 모드로 띄우고, 고른
# 경로를 FileAccess로 읽어 바이트로 바꿔 넘긴다. 큰 파일을 읽을 때 메인
# 스레드(=UI)가 멈추지 않도록 백그라운드 Thread에서 읽는다.

var _file_dialog: FileDialog
var _pending_extensions: Array[String] = []
var _read_thread: Thread


func _ready() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.title = "파일 선택"
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.files_selected.connect(_on_files_selected)
	_file_dialog.canceled.connect(_on_canceled)
	add_child(_file_dialog)


func _exit_tree() -> void:
	if _read_thread != null and _read_thread.is_started():
		_read_thread.wait_to_finish()


func pick_files(extensions: Array[String], multiple: bool) -> void:
	_pending_extensions = extensions
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES if multiple else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = _build_filters(extensions)
	_file_dialog.popup_centered_ratio(0.7)


## FileDialog.filters 형식("*.png,*.jpg ; 설명")으로 변환한다. 이 형식이라는 걸
## 눈으로 확인하기 쉽게 테스트에서 직접 검증한다.
func _build_filters(extensions: Array[String]) -> PackedStringArray:
	if extensions.is_empty():
		return PackedStringArray()

	var patterns: Array[String] = []
	for ext in extensions:
		patterns.append("*.%s" % ext)

	return PackedStringArray(["%s ; 허용된 파일" % ",".join(patterns)])


func _on_file_selected(path: String) -> void:
	_read_paths([path])


func _on_files_selected(paths: PackedStringArray) -> void:
	_read_paths(Array(paths))


func _on_canceled() -> void:
	pick_cancelled.emit()


func _read_paths(paths: Array) -> void:
	if _read_thread != null and _read_thread.is_started():
		_read_thread.wait_to_finish()  # 이론상 겹칠 일 없지만 방어적으로.

	_read_thread = Thread.new()
	_read_thread.start(_read_paths_threaded.bind(paths))


# 백그라운드 스레드에서 실행된다 — 여기서 시그널을 직접 emit하거나 씬 트리를
# 건드리면 안 되므로, 결과를 call_deferred로 메인 스레드에 넘긴다.
func _read_paths_threaded(paths: Array) -> void:
	var results: Array = []
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("FilePickerDesktop: 파일을 열 수 없음 - %s" % path)
			continue
		var bytes := file.get_buffer(file.get_length())
		file.close()
		results.append({"name": path.get_file(), "bytes": bytes})

	call_deferred("_on_read_complete", results)


func _on_read_complete(results: Array) -> void:
	_finalize_pick(results, _pending_extensions)
