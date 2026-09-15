extends Control

# 게임 시작 전 "인원수만큼 캐릭터 고르기" 화면. Main.gd가 인원수 버튼을 누르면
# configure(player_count)를 부르고, 이 화면이 확정되면 selection_confirmed로
# 결과를 돌려준다. 목록은 CharacterLibrary.get_selectable_profiles()(내장
# 기본 캐릭터 포함)를 쓰고, 여러 플레이어가 같은 캐릭터를 골라도 제한하지 않는다.

signal selection_confirmed(profiles: Array[CharacterProfile])
signal back_requested()

const SLOT_BOX_SIZE := Vector2(96, 96)

@onready var _slots_row: HBoxContainer = $CenterContainer/VBox/SlotsRow
@onready var _back_button: Button = $CenterContainer/VBox/ButtonsRow/BackButton
@onready var _confirm_button: Button = $CenterContainer/VBox/ButtonsRow/ConfirmButton

var _available: Array[CharacterProfile] = []
var _selected_indices: Array[int] = []
var _slot_widgets: Array[Dictionary] = []


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_confirm_button.pressed.connect(_on_confirm_pressed)


## Main.gd가 인원수 버튼을 누른 직후 부른다. 매번 새로 호출되므로(재시작 등)
## 슬롯을 통째로 다시 만든다 - 인원수가 매번 바뀔 수 있어서 재사용보다 단순하다.
func configure(player_count: int) -> void:
	_available = CharacterLibrary.get_selectable_profiles()
	_confirm_button.disabled = _available.is_empty()

	_selected_indices.clear()
	_slot_widgets.clear()
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()

	for p in player_count:
		var default_index := (p % _available.size()) if not _available.is_empty() else 0
		_selected_indices.append(default_index)
		_slot_widgets.append(_build_slot(p))

	_refresh_all_slots()


func _build_slot(player_index: int) -> Dictionary:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var player_label := Label.new()
	player_label.text = "플레이어 %d" % (player_index + 1)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(player_label)

	var box := Control.new()
	box.custom_minimum_size = SLOT_BOX_SIZE
	box.clip_contents = true
	box.resized.connect(_on_slot_box_resized.bind(player_index))
	var texture_rect := TextureRect.new()
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(texture_rect)
	vbox.add_child(box)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var nav_row := HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prev_button := Button.new()
	prev_button.text = "◀"
	prev_button.pressed.connect(_on_prev_pressed.bind(player_index))
	nav_row.add_child(prev_button)

	var position_label := Label.new()
	position_label.custom_minimum_size = Vector2(56, 0)
	position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_row.add_child(position_label)

	var next_button := Button.new()
	next_button.text = "▶"
	next_button.pressed.connect(_on_next_pressed.bind(player_index))
	nav_row.add_child(next_button)
	vbox.add_child(nav_row)

	_slots_row.add_child(vbox)

	return {
		"texture_rect": texture_rect,
		"box": box,
		"name_label": name_label,
		"position_label": position_label,
	}


func _on_prev_pressed(player_index: int) -> void:
	if _available.is_empty():
		return
	_selected_indices[player_index] = (_selected_indices[player_index] - 1 + _available.size()) % _available.size()
	_refresh_slot(player_index)


func _on_next_pressed(player_index: int) -> void:
	if _available.is_empty():
		return
	_selected_indices[player_index] = (_selected_indices[player_index] + 1) % _available.size()
	_refresh_slot(player_index)


func _on_slot_box_resized(player_index: int) -> void:
	if player_index < _slot_widgets.size() and not _available.is_empty():
		_refresh_slot(player_index)


func _refresh_all_slots() -> void:
	for i in _slot_widgets.size():
		_refresh_slot(i)


func _refresh_slot(player_index: int) -> void:
	var widget: Dictionary = _slot_widgets[player_index]
	if _available.is_empty():
		widget.name_label.text = "캐릭터 없음"
		widget.position_label.text = "0 / 0"
		return

	var profile := _available[_selected_indices[player_index]]
	widget.name_label.text = profile.display_name
	widget.position_label.text = "%d / %d" % [_selected_indices[player_index] + 1, _available.size()]

	var center_crop := CharacterPortrait.thumbnail_should_center_crop(profile)
	TextureFit.fit(widget.texture_rect, CharacterPortrait.resolve_thumbnail_texture(profile), widget.box.size, true, 0.5 if center_crop else 0.0)


func _on_confirm_pressed() -> void:
	if _available.is_empty():
		return
	var profiles: Array[CharacterProfile] = []
	for index in _selected_indices:
		profiles.append(_available[index])
	selection_confirmed.emit(profiles)
