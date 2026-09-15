extends Control

# 캐릭터 편집 화면의 오케스트레이터. "지금 편집 중인 프로필이 뭔지"와
# "저장 안 한 변경사항이 있는지"를 여기서만 들고 있고, 3개 패널은 그 상태를
# 모른 채 emit/받기만 한다. 목록 패널의 새로 만들기/복제/선택 전환처럼
# "지금 편집 중인 걸 바꾸는" 모든 동작은 _guard_unsaved()를 거친다.

signal closed()

@onready var _list_panel = $Margin/Root/HBox/LeftPanel
@onready var _image_panel = $Margin/Root/HBox/CenterPanel
@onready var _voice_panel = $Margin/Root/HBox/RightPanel
@onready var _save_button: Button = $Margin/Root/TopBar/SaveButton
@onready var _close_button: Button = $Margin/Root/TopBar/CloseButton
@onready var _export_button: Button = $Margin/Root/TopBar/ExportButton
@onready var _import_button: Button = $Margin/Root/TopBar/ImportButton
@onready var _unsaved_changes_dialog: ConfirmationDialog = $UnsavedChangesDialog
@onready var _storage_warning_dialog: AcceptDialog = $StorageWarningDialog
@onready var _export_unsaved_dialog: ConfirmationDialog = $ExportUnsavedDialog
@onready var _export_save_dialog: FileDialog = $ExportSaveDialog
@onready var _import_error_dialog: AcceptDialog = $ImportErrorDialog
@onready var _import_warning_dialog: AcceptDialog = $ImportWarningDialog
@onready var _pack_size_warning_dialog: AcceptDialog = $PackSizeWarningDialog
@onready var _pack_size_label: Label = $Margin/Root/TopBar/PackSizeLabel

var _current_profile: CharacterProfile
var _dirty: bool = false
var _pending_after_discard: Callable

# 1-7 캐릭터 팩. 내보내기는 데스크톱(FileDialog 저장)과 웹
# (JavaScriptBridge.download_buffer, 다이얼로그 없이 바로 브라우저 다운로드가
# 뜸)이 갈라지므로, zip 바이트를 만든 뒤 플랫폼별로 분기한다. 가져오기는
# FilePicker(1-5)를 그대로 재사용한다 - 이미지/보이스 피커와 마찬가지로
# "확장자를 하나 더 골라 여는 것"일 뿐이라 새 추상화가 필요 없다.
const PACK_FILE_SUFFIX := ".ydchar.zip"
var _import_picker: FilePicker
var _pending_export_bytes: PackedByteArray

# CharacterLimits는 이 파일 작성 시점에 막 추가된 class_name이라, 전역 스크립트
# 클래스 캐시가 아직 못 봤을 수 있는 배포 환경을 대비해 preload로 직접 참조한다.
const CharacterLimitsScript = preload("res://scripts/characters/character_limits.gd")


func _ready() -> void:
	_list_panel.selected.connect(_on_list_selected)
	_list_panel.new_requested.connect(_on_new_requested)
	_list_panel.duplicate_requested.connect(_on_duplicate_requested)
	_list_panel.delete_requested.connect(_on_delete_requested)

	_image_panel.changed.connect(_on_child_changed)
	_image_panel.volume_changed.connect(_voice_panel.update_preview_volume)
	_image_panel.storage_write_failed.connect(_show_storage_warning)

	_voice_panel.changed.connect(_on_child_changed)
	_voice_panel.storage_write_failed.connect(_show_storage_warning)

	_save_button.pressed.connect(_on_save_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_unsaved_changes_dialog.confirmed.connect(_on_discard_confirmed)

	_export_button.pressed.connect(_on_export_pressed)
	_import_button.pressed.connect(_on_import_pressed)
	_export_unsaved_dialog.confirmed.connect(_on_export_unsaved_confirmed)
	_export_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_save_dialog.file_selected.connect(_on_export_save_path_selected)

	_load_profile(null)


func _on_list_selected(profile: CharacterProfile) -> void:
	if _current_profile != null and profile.id == _current_profile.id:
		return
	_guard_unsaved(func() -> void: _load_profile(profile))


func _on_new_requested() -> void:
	_guard_unsaved(func() -> void:
		var profile := CharacterLibrary.create_new("새 캐릭터")
		if profile == null:
			_show_storage_warning()
			return
		_list_panel.refresh()
		_load_profile(profile)
	)


func _on_duplicate_requested(profile_id: String) -> void:
	if profile_id.is_empty():
		return
	_guard_unsaved(func() -> void:
		var profile := CharacterLibrary.duplicate_profile(profile_id)
		if profile == null:
			_show_storage_warning()
			return
		_list_panel.refresh()
		_load_profile(profile)
	)


## 삭제는 "지금 열려 있는 캐릭터"가 아니어도 목록에서 바로 할 수 있다 -
## 편집 중인 내용과 무관하니 dirty 여부와 상관없이 즉시 실행한다. 단, 지금
## 편집 중이던 캐릭터를 지운 거라면 그 편집 내용은 더 이상 의미가 없으므로
## 확인 없이 비운다(어차피 폴더가 없어져서 저장할 곳도 없다).
func _on_delete_requested(profile_id: String) -> void:
	if profile_id.is_empty():
		return
	CharacterLibrary.delete(profile_id)
	if _current_profile != null and _current_profile.id == profile_id:
		_dirty = false
		_load_profile(null)
	_list_panel.refresh()


func _guard_unsaved(action: Callable) -> void:
	if _dirty:
		_pending_after_discard = action
		_unsaved_changes_dialog.popup_centered()
	else:
		action.call()


func _on_discard_confirmed() -> void:
	_dirty = false
	if _pending_after_discard.is_valid():
		_pending_after_discard.call()


func _load_profile(profile: CharacterProfile) -> void:
	_current_profile = profile
	_dirty = false
	_list_panel.set_selected(profile.id if profile != null else "")
	_image_panel.load_profile(profile)
	_voice_panel.load_profile(profile)
	_save_button.disabled = profile == null
	_export_button.disabled = profile == null
	_update_save_button_text()
	_update_pack_size_label()


func _on_child_changed() -> void:
	_dirty = true
	_update_save_button_text()
	_update_pack_size_label()  # 파일을 추가/제거할 때마다 즉시 반영(디스크에는 이미 써졌으므로).


func _update_save_button_text() -> void:
	_save_button.text = "저장 *" if _dirty else "저장"


## "현재 캐릭터 용량: 3.2 / 15 MB" 표시. 10MB를 넘으면 노랑, 15MB를 넘으면
## 빨강으로 바뀐다(CharacterLimits.total_size_color) - 저장을 막지는 않고
## 그냥 알려주기만 하는 것이라 색으로 계속 눈에 띄게 해둔다.
func _update_pack_size_label() -> void:
	if _current_profile == null:
		_pack_size_label.text = ""
		return
	var total := CharacterLibrary.compute_pack_size(_current_profile)
	_pack_size_label.text = "현재 캐릭터 용량: %s / %s" % [
		CharacterLimitsScript.format_bytes(total), CharacterLimitsScript.format_bytes(CharacterLimitsScript.TOTAL_WARNING_BYTES)
	]
	_pack_size_label.modulate = CharacterLimitsScript.total_size_color(total)


func _on_save_pressed() -> void:
	if _current_profile == null:
		return
	if not _save_current_profile():
		_show_storage_warning()


## _on_save_pressed()와 내보내기 전 자동 저장(_on_export_unsaved_confirmed)이
## 공유하는 실제 저장 동작. 성공 여부만 돌려주고 실패 시 다이얼로그를 띄우는
## 건 호출부가 각자 알아서 한다 - 내보내기 쪽은 실패하면 내보내기 자체를
## 이어가면 안 되기 때문에 이 함수 안에서 다이얼로그까지 처리하지 않는다.
func _save_current_profile() -> bool:
	if not CharacterLibrary.save_profile(_current_profile):
		return false
	_dirty = false
	_update_save_button_text()
	_list_panel.refresh()
	_list_panel.set_selected(_current_profile.id)
	_maybe_warn_pack_size()
	return true


## 15MB(권장 상한)를 넘어도 저장 자체는 막지 않는다 - 다만 온라인 전송(2-5)
## 에서 문제가 될 수 있다는 걸 저장할 때마다 분명히 알려준다.
func _maybe_warn_pack_size() -> void:
	var total := CharacterLibrary.compute_pack_size(_current_profile)
	if total <= CharacterLimitsScript.TOTAL_WARNING_BYTES:
		return
	_pack_size_warning_dialog.dialog_text = "이 캐릭터의 전체 용량이 %s로 권장 상한(%s)을 넘었습니다.\n온라인에서 상대에게 전송되지 않을 수 있습니다." % [
		CharacterLimitsScript.format_bytes(total), CharacterLimitsScript.format_bytes(CharacterLimitsScript.TOTAL_WARNING_BYTES)
	]
	_pack_size_warning_dialog.popup_centered()


func _on_close_pressed() -> void:
	_guard_unsaved(func() -> void: closed.emit())


func _show_storage_warning() -> void:
	_storage_warning_dialog.popup_centered()


func _on_export_pressed() -> void:
	if _current_profile == null:
		return
	if _dirty:
		_export_unsaved_dialog.popup_centered()
		return
	_export_current_profile()


func _on_export_unsaved_confirmed() -> void:
	if not _save_current_profile():
		_show_storage_warning()
		return
	_export_current_profile()


## zip 바이트를 만든 뒤 플랫폼에 맞게 내보낸다 - 웹은 다이얼로그 없이 바로
## 브라우저 다운로드를 띄우고(사용자가 이미 [내보내기]를 눌렀으므로 추가
## 확인 없이 바로 진행해도 됨), 데스크톱은 저장 위치를 물어야 하므로
## FileDialog를 띄운다(실제 쓰기는 _on_export_save_path_selected에서).
func _export_current_profile() -> void:
	var zip_bytes := CharacterLibrary.export_pack_bytes(_current_profile)
	if zip_bytes.is_empty():
		_show_storage_warning()
		return

	var file_name := "%s%s" % [_current_profile.id, PACK_FILE_SUFFIX]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(zip_bytes, file_name)
	else:
		_pending_export_bytes = zip_bytes
		_export_save_dialog.current_file = file_name
		_export_save_dialog.popup_centered_ratio(0.7)


func _on_export_save_path_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("CharacterEditor: 캐릭터 팩을 저장할 수 없음 - %s" % path)
		_show_storage_warning()
	else:
		file.store_buffer(_pending_export_bytes)
		file.close()
	_pending_export_bytes = PackedByteArray()


## 지금 편집 중인 내용을 버리고 다른 캐릭터(새로 가져온 것)로 넘어가는
## 동작이라 _guard_unsaved()를 거친다 - 새로 만들기/복제/목록에서 다른 캐릭터
## 선택과 정확히 같은 이유다.
func _on_import_pressed() -> void:
	_guard_unsaved(_start_import)


func _start_import() -> void:
	if _import_picker == null:
		_import_picker = FilePicker.create()
		add_child(_import_picker)
		_import_picker.files_picked.connect(_on_import_files_picked)
	_import_picker.pick_files(["zip"], false)


func _on_import_files_picked(files: Array) -> void:
	if files.is_empty():
		return  # 확장자 재검사(FilePicker._finalize_pick)에서 전부 걸러진 경우.

	var result := CharacterLibrary.import_pack(files[0]["bytes"])
	if not result["ok"]:
		_import_error_dialog.dialog_text = result["error"]
		_import_error_dialog.popup_centered()
		return

	_list_panel.refresh()
	_load_profile(result["profile"])

	# 남이 만든 팩이 CharacterLimits 권장 상한을 넘어도 가져오기 자체는 막지
	# 않는다(이미 신뢰 검증은 통과했으므로) - 다만 알아두라고 알려준다.
	var warning: String = result.get("warning", "")
	if warning != "":
		_import_warning_dialog.dialog_text = warning
		_import_warning_dialog.popup_centered()
