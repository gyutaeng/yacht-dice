extends VBoxContainer

# 좌측 패널: 캐릭터 목록 렌더링과 새로 만들기/복제/삭제 "의도"만 emit한다.
# 실제 CharacterLibrary 호출과 "저장 안 한 변경사항이 있는데 다른 캐릭터로
# 넘어가도 되는지" 판단은 전부 character_editor.gd(오케스트레이터)가 한다 -
# 이 패널은 그 판단에 필요한 정보(dirty 여부)를 아예 모른다.

signal selected(profile: CharacterProfile)
signal new_requested()
signal duplicate_requested(profile_id: String)
signal delete_requested(profile_id: String)

@onready var _list_container: VBoxContainer = $Scroll/ListContainer
@onready var _new_button: Button = $ActionsRow/NewButton
@onready var _duplicate_button: Button = $ActionsRow/DuplicateButton
@onready var _delete_button: Button = $ActionsRow/DeleteButton
@onready var _delete_confirm_dialog: ConfirmationDialog = $DeleteConfirmDialog

var _profiles: Array[CharacterProfile] = []
var _selected_id: String = ""
var _button_group := ButtonGroup.new()


func _ready() -> void:
	_new_button.pressed.connect(func() -> void: new_requested.emit())
	_duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit(_selected_id))
	_delete_button.pressed.connect(_on_delete_pressed)
	_delete_confirm_dialog.confirmed.connect(func() -> void: delete_requested.emit(_selected_id))

	refresh()


## CharacterLibrary가 바뀔 만한 일(생성/복제/삭제)이 있고 난 뒤 오케스트레이터가 부른다.
func refresh() -> void:
	_profiles = CharacterLibrary.scan()

	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()

	for profile in _profiles:
		_list_container.add_child(_build_row(profile))

	_update_action_buttons()


## 지금 선택된 캐릭터가 바뀌었을 때(다른 걸 골랐거나, 새로 만들었거나, 선택이
## 취소됐을 때) 오케스트레이터가 부른다. 여기서 직접 selected를 emit하지
## 않는다 - 이건 "이미 확정된 결과"를 표시만 하는 것이다.
func set_selected(profile_id: String) -> void:
	_selected_id = profile_id
	for row in _list_container.get_children():
		row.button_pressed = (row.get_meta("profile_id") == profile_id)
	_update_action_buttons()


func _build_row(profile: CharacterProfile) -> Button:
	var button := Button.new()
	button.text = profile.display_name
	button.icon = CharacterPortrait.resolve_thumbnail_texture(profile)
	button.expand_icon = true
	button.custom_minimum_size = Vector2(0, 44)
	button.toggle_mode = true
	button.button_group = _button_group
	button.button_pressed = (profile.id == _selected_id)
	button.set_meta("profile_id", profile.id)
	button.pressed.connect(func() -> void: selected.emit(profile))
	return button


func _on_delete_pressed() -> void:
	var profile := _find_profile(_selected_id)
	if profile == null:
		return
	_delete_confirm_dialog.dialog_text = "'%s'을(를) 삭제하시겠습니까? 되돌릴 수 없습니다." % profile.display_name
	_delete_confirm_dialog.popup_centered()


func _find_profile(id: String) -> CharacterProfile:
	for profile in _profiles:
		if profile.id == id:
			return profile
	return null


func _update_action_buttons() -> void:
	var has_selection := _selected_id != ""
	_duplicate_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
