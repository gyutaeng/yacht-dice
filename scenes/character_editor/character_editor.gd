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
@onready var _unsaved_changes_dialog: ConfirmationDialog = $UnsavedChangesDialog
@onready var _storage_warning_dialog: AcceptDialog = $StorageWarningDialog

var _current_profile: CharacterProfile
var _dirty: bool = false
var _pending_after_discard: Callable


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
	_update_save_button_text()


func _on_child_changed() -> void:
	_dirty = true
	_update_save_button_text()


func _update_save_button_text() -> void:
	_save_button.text = "저장 *" if _dirty else "저장"


func _on_save_pressed() -> void:
	if _current_profile == null:
		return
	if CharacterLibrary.save_profile(_current_profile):
		_dirty = false
		_update_save_button_text()
		_list_panel.refresh()
		_list_panel.set_selected(_current_profile.id)
	else:
		_show_storage_warning()


func _on_close_pressed() -> void:
	_guard_unsaved(func() -> void: closed.emit())


func _show_storage_warning() -> void:
	_storage_warning_dialog.popup_centered()
