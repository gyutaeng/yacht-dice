extends Control

# 1-5(FilePicker) 웹 검증용 임시 화면. 게임 본편과 완전히 분리되어 있다.
#
# 목적은 FilePicker 단독이 아니라 "파일 선택 -> 바이트 -> 텍스처/오디오"
# 전체 경로를 눈으로 확인하는 것이라, 받은 바이트를 실제로 AssetLoader에
# 넣어 디코딩 성공/실패까지 화면에 찍는다.
#
# 웹에서는 개발자 도구 콘솔을 열기 번거로우므로, push_warning 대신
# 화면 하단 로그 영역에 직접 찍는다.

const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

# 1-6에서 캐릭터를 user://에 저장할 예정인데, 웹에서 user://가 새로고침 후에도
# 실제로 유지되는지(IndexedDB 기반 영구 저장소로 잡히는지) 미리 확인해두려고
# 넣었다. 여기서 안 되면 캐릭터 편집 화면 자체가 무용지물이라 먼저 검증한다.
const PERSISTENCE_TEST_PATH := "user://web_persistence_test.txt"

@onready var _pick_image_button: Button = $Margin/Root/ButtonRow/PickImageButton
@onready var _pick_audio_button: Button = $Margin/Root/ButtonRow/PickAudioButton
@onready var _save_test_button: Button = $Margin/Root/PersistenceRow/SaveTestButton
@onready var _load_test_button: Button = $Margin/Root/PersistenceRow/LoadTestButton
@onready var _results_list: VBoxContainer = $Margin/Root/ResultsScroll/ResultsList
@onready var _log_text: RichTextLabel = $Margin/Root/LogText

var _file_picker_image: FilePicker
var _file_picker_audio: FilePicker


func _ready() -> void:
	_log("빌드: %s" % BuildInfo.BUILD_TIME)

	_file_picker_image = FilePicker.create()
	add_child(_file_picker_image)
	_file_picker_image.files_picked.connect(_on_image_files_picked)
	_file_picker_image.pick_cancelled.connect(_on_image_cancelled)
	_file_picker_image.debug_log.connect(_on_picker_debug_log.bind("이미지"))

	_file_picker_audio = FilePicker.create()
	add_child(_file_picker_audio)
	_file_picker_audio.files_picked.connect(_on_audio_files_picked)
	_file_picker_audio.pick_cancelled.connect(_on_audio_cancelled)
	_file_picker_audio.debug_log.connect(_on_picker_debug_log.bind("오디오"))

	_pick_image_button.pressed.connect(_on_pick_image_button_pressed)
	_pick_audio_button.pressed.connect(_on_pick_audio_button_pressed)
	_save_test_button.pressed.connect(_on_save_test_button_pressed)
	_load_test_button.pressed.connect(_on_load_test_button_pressed)

	_log("준비 완료. 플랫폼: %s" % ("web" if OS.has_feature("web") else "desktop"))

	# 새로고침 후에도 이전에 저장한 값이 남아있는지는 시작할 때 한 번
	# 자동으로 읽어봐야 확인된다(버튼을 누르는 시점엔 이미 이번 세션에서
	# 저장한 값과 뒤섞여서 구분이 안 됨).
	_load_persistence_test("시작 시 자동 확인")


# 웹에서는 브라우저가 "실제 클릭의 콜스택 안"에서만 파일창을 허용하므로,
# 이 핸들러에서 await 없이 곧바로 pick_files()를 불러야 한다
# (file_picker_web.gd 주석 참고).
func _on_pick_image_button_pressed() -> void:
	_log("이미지 선택 창을 여는 중...")
	_file_picker_image.pick_files(IMAGE_EXTENSIONS, true)


func _on_pick_audio_button_pressed() -> void:
	_log("오디오 선택 창을 여는 중...")
	_file_picker_audio.pick_files(AUDIO_EXTENSIONS, true)


func _on_image_files_picked(files: Array) -> void:
	if files.is_empty():
		_log("이미지 선택: 통과한 파일이 없음(확장자 필터에서 전부 걸러짐)")
		return
	_log("이미지 %d개 선택됨" % files.size())
	for entry in files:
		_add_image_row(entry.name, entry.bytes)


func _on_audio_files_picked(files: Array) -> void:
	if files.is_empty():
		_log("오디오 선택: 통과한 파일이 없음(확장자 필터에서 전부 걸러짐)")
		return
	_log("오디오 %d개 선택됨" % files.size())
	for entry in files:
		_add_audio_row(entry.name, entry.bytes)


func _on_save_test_button_pressed() -> void:
	var timestamp := Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open(PERSISTENCE_TEST_PATH, FileAccess.WRITE)
	if file == null:
		_log("user:// 저장 실패 - %s (%s)" % [PERSISTENCE_TEST_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(timestamp)
	file.close()
	_log("user:// 저장 성공 - '%s'를 %s에 기록함" % [timestamp, PERSISTENCE_TEST_PATH])


func _on_load_test_button_pressed() -> void:
	_load_persistence_test("불러오기 테스트")


## context: 로그에 어느 상황에서 읽은 건지 남기려는 접두사("시작 시 자동 확인"
## vs "불러오기 테스트") - 새로고침 직후 자동 확인 결과와 버튼을 눌러 확인한
## 결과가 로그에서 섞이지 않게 구분한다.
func _load_persistence_test(context: String) -> void:
	if not FileAccess.file_exists(PERSISTENCE_TEST_PATH):
		_log("%s: user://에 저장된 값이 없음(%s)" % [context, PERSISTENCE_TEST_PATH])
		return

	var file := FileAccess.open(PERSISTENCE_TEST_PATH, FileAccess.READ)
	if file == null:
		_log("%s: user:// 읽기 실패 - %s (%s)" % [context, PERSISTENCE_TEST_PATH, error_string(FileAccess.get_open_error())])
		return
	var content := file.get_as_text()
	file.close()
	_log("%s: user:// 읽기 성공 - 저장된 값 '%s'" % [context, content])


func _on_image_cancelled() -> void:
	_log("이미지 선택 취소됨")


func _on_audio_cancelled() -> void:
	_log("오디오 선택 취소됨")


## FilePicker 내부 단계별 진행 상황(선택창 열림/change 이벤트/FileReader 완료 등).
## 어디서 멈췄는지 화면에서 바로 보려고 붙였다 - 웹에서는 개발자 도구를 열기
## 번거로우니 이 화면 로그가 사실상 유일한 확인 수단이다.
func _on_picker_debug_log(message: String, picker_label: String) -> void:
	_log("[%s] %s" % [picker_label, message])


func _add_image_row(file_name: String, bytes: PackedByteArray) -> void:
	var texture := AssetLoader.load_texture_from_bytes(bytes)
	var success := texture != null
	var row := _build_row(file_name, bytes.size(), success)

	if success:
		var preview := TextureRect.new()
		preview.texture = texture
		preview.custom_minimum_size = Vector2(64, 64)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(preview)

	_results_list.add_child(row)
	_log("이미지 디코딩 %s: %s (%s)" % [
		"성공" if success else "실패", file_name, _format_size(bytes.size())
	])


func _add_audio_row(file_name: String, bytes: PackedByteArray) -> void:
	var stream := AssetLoader.load_audio_from_bytes(bytes)
	var success := stream != null
	var row := _build_row(file_name, bytes.size(), success)

	if success:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		row.add_child(player)

		var play_button := Button.new()
		play_button.text = "재생"
		play_button.pressed.connect(func() -> void: player.play())
		row.add_child(play_button)

	_results_list.add_child(row)
	_log("오디오 디코딩 %s: %s (%s)" % [
		"성공" if success else "실패", file_name, _format_size(bytes.size())
	])


func _build_row(file_name: String, byte_size: int, success: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = file_name
	name_label.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_label)

	var size_label := Label.new()
	size_label.text = _format_size(byte_size)
	size_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(size_label)

	var status_label := Label.new()
	status_label.text = "성공" if success else "실패"
	status_label.modulate = Color(0.4, 0.9, 0.4) if success else Color(0.9, 0.4, 0.4)
	status_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(status_label)

	return row


func _format_size(byte_count: int) -> String:
	if byte_count < 1024:
		return "%d B" % byte_count
	if byte_count < 1024 * 1024:
		return "%.1f KB" % (byte_count / 1024.0)
	return "%.1f MB" % (byte_count / (1024.0 * 1024.0))


func _log(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_log_text.append_text("[%s] %s\n" % [timestamp, message])
