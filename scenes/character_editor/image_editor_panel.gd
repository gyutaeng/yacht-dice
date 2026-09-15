extends VBoxContainer

# 중앙 패널: 이름, 스탠딩 초상, 썸네일, 보이스 볼륨. 이미지 두 장은 FilePicker
# 인스턴스 하나를 공유하고("어느 슬롯을 위해 열었는지"만 _pending_slot으로
# 기억), 고른 바이트는 검증 통과 즉시 CharacterLibrary.save_asset_bytes()로
# 디스크에 쓴다. manifest.json 갱신(진짜 "저장")은 오케스트레이터의 몫이다.

signal changed()
signal volume_changed(value: float)
signal storage_write_failed()

const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const VOLUME_MIN := -24.0
const VOLUME_MAX := 12.0

@onready var _name_edit: LineEdit = $NameRow/NameEdit
@onready var _portrait_preview: TextureRect = $PortraitSection/PortraitBox/PortraitPreview
@onready var _portrait_box: Control = $PortraitSection/PortraitBox
@onready var _portrait_load_button: Button = $PortraitSection/PortraitButtonsRow/LoadButton
@onready var _portrait_remove_button: Button = $PortraitSection/PortraitButtonsRow/RemoveButton
@onready var _thumbnail_preview: TextureRect = $ThumbnailSection/ThumbnailBox/ThumbnailPreview
@onready var _thumbnail_box: Control = $ThumbnailSection/ThumbnailBox
@onready var _thumbnail_load_button: Button = $ThumbnailSection/ThumbnailButtonsRow/LoadButton
@onready var _thumbnail_remove_button: Button = $ThumbnailSection/ThumbnailButtonsRow/RemoveButton
@onready var _volume_slider: HSlider = $VolumeRow/VolumeSlider
@onready var _volume_value_label: Label = $VolumeRow/VolumeValueLabel

var _profile: CharacterProfile
var _picker: FilePicker
var _picker_busy: bool = false
var _pending_slot: String = ""  # "portrait" 또는 "thumbnail"


func _ready() -> void:
	_picker = FilePicker.create()
	add_child(_picker)
	_picker.files_picked.connect(_on_files_picked)
	_picker.pick_cancelled.connect(_on_pick_cancelled)

	_name_edit.text_changed.connect(_on_name_changed)
	_portrait_load_button.pressed.connect(_on_portrait_load_pressed)
	_portrait_remove_button.pressed.connect(_on_portrait_remove_pressed)
	_thumbnail_load_button.pressed.connect(_on_thumbnail_load_pressed)
	_thumbnail_remove_button.pressed.connect(_on_thumbnail_remove_pressed)

	_volume_slider.min_value = VOLUME_MIN
	_volume_slider.max_value = VOLUME_MAX
	_volume_slider.step = 0.5
	_volume_slider.value_changed.connect(_on_volume_changed)

	# 박스 크기가 레이아웃 계산 전(0,0)일 수 있어서, 실제 크기가 잡히는 시점에
	# 다시 맞춘다(Main.gd의 portrait_stack.resized와 같은 이유).
	_portrait_box.resized.connect(_on_preview_box_resized)
	_thumbnail_box.resized.connect(_on_preview_box_resized)

	load_profile(null)


func _on_preview_box_resized() -> void:
	if _profile != null:
		_refresh_previews()


## 오케스트레이터가 "지금 편집 대상"이 바뀔 때마다 부른다. null이면 선택된
## 캐릭터가 없다는 뜻 - 전부 비우고 입력을 막는다.
func load_profile(profile: CharacterProfile) -> void:
	_profile = profile
	var enabled := profile != null

	_name_edit.editable = enabled
	_portrait_load_button.disabled = not enabled
	_thumbnail_load_button.disabled = not enabled
	_volume_slider.editable = enabled

	if not enabled:
		_name_edit.text = ""
		_portrait_preview.texture = null
		_thumbnail_preview.texture = null
		_portrait_remove_button.disabled = true
		_thumbnail_remove_button.disabled = true
		return

	_name_edit.text = profile.display_name
	_volume_slider.set_value_no_signal(profile.volume_db)
	_volume_value_label.text = "%.1f dB" % profile.volume_db
	_refresh_previews()


func _refresh_previews() -> void:
	_portrait_remove_button.disabled = _profile.portrait_file.is_empty()
	_thumbnail_remove_button.disabled = _profile.thumbnail_file.is_empty()

	TextureFit.fit(_portrait_preview, CharacterPortrait.resolve_display_texture(_profile), _portrait_box.size, false, 0.0)

	var center_crop := CharacterPortrait.thumbnail_should_center_crop(_profile)
	TextureFit.fit(_thumbnail_preview, CharacterPortrait.resolve_thumbnail_texture(_profile), _thumbnail_box.size, true, 0.5 if center_crop else 0.0)


func _on_name_changed(new_text: String) -> void:
	if _profile == null:
		return
	_profile.display_name = new_text
	changed.emit()


func _on_portrait_load_pressed() -> void:
	_start_pick("portrait")


func _on_thumbnail_load_pressed() -> void:
	_start_pick("thumbnail")


func _start_pick(slot: String) -> void:
	if _picker_busy or _profile == null:
		return
	_picker_busy = true
	_pending_slot = slot
	_set_load_buttons_disabled(true)
	_picker.pick_files(IMAGE_EXTENSIONS, false)


func _set_load_buttons_disabled(disabled: bool) -> void:
	_portrait_load_button.disabled = disabled
	_thumbnail_load_button.disabled = disabled


func _on_pick_cancelled() -> void:
	_picker_busy = false
	_set_load_buttons_disabled(false)


func _on_files_picked(files: Array) -> void:
	_picker_busy = false
	_set_load_buttons_disabled(false)

	if files.is_empty() or _profile == null:
		return

	var entry = files[0]
	var bytes: PackedByteArray = entry.bytes

	if bytes.size() > AssetLoader.MAX_IMAGE_BYTES:
		push_warning("ImageEditorPanel: 이미지가 크기 상한을 초과함(%d바이트) - %s" % [bytes.size(), entry.name])
		return
	if AssetLoader.load_texture_from_bytes(bytes) == null:
		push_warning("ImageEditorPanel: 이미지 디코딩 실패 - %s" % entry.name)
		return

	var saved_name := CharacterLibrary.save_asset_bytes(_profile.id, "", entry.name, bytes)
	if saved_name.is_empty():
		storage_write_failed.emit()
		return

	if _pending_slot == "portrait":
		_profile.portrait_file = saved_name
	else:
		_profile.thumbnail_file = saved_name

	_refresh_previews()
	changed.emit()


func _on_portrait_remove_pressed() -> void:
	if _profile == null:
		return
	_profile.portrait_file = ""
	_refresh_previews()
	changed.emit()


func _on_thumbnail_remove_pressed() -> void:
	if _profile == null:
		return
	_profile.thumbnail_file = ""
	_refresh_previews()
	changed.emit()


func _on_volume_changed(value: float) -> void:
	if _profile == null:
		return
	_profile.volume_db = value
	_volume_value_label.text = "%.1f dB" % value
	volume_changed.emit(value)
	changed.emit()
