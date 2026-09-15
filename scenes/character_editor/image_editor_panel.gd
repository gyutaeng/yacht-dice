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

# CharacterLimits는 이 파일 작성 시점에 막 추가된 class_name이라, 전역 스크립트
# 클래스 캐시가 아직 못 봤을 수 있는 배포 환경을 대비해 preload로 직접 참조한다.
const CharacterLimitsScript = preload("res://scripts/characters/character_limits.gd")

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
@onready var _limit_dialog: AcceptDialog = $LimitDialog
@onready var _resize_confirm_dialog: ConfirmationDialog = $ResizeConfirmDialog

var _profile: CharacterProfile
var _picker: FilePicker
var _picker_busy: bool = false
var _pending_slot: String = ""  # "portrait" 또는 "thumbnail"

# 픽셀 한도 초과로 거부된 이미지를 자동으로 줄여서 다시 넣을지 물어보는 동안
# 들고 있는 데이터. ResizeConfirmDialog가 확인될 때만 쓰인다.
var _pending_resize: Dictionary = {}


func _ready() -> void:
	_picker = FilePicker.create()
	add_child(_picker)
	_picker.files_picked.connect(_on_files_picked)
	_picker.pick_cancelled.connect(_on_pick_cancelled)

	_resize_confirm_dialog.confirmed.connect(_on_resize_confirmed)

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
	var file_name: String = entry.name

	# AssetLoader의 8MB는 "이보다 크면 디코딩도 시도 안 하는" 최후 방어선이다.
	# CharacterLimits의 권장 상한(스탠딩 4MB/썸네일 1MB)은 항상 이보다 작으므로
	# 정상적으로는 아래 CharacterLimits 검사에서 먼저 걸리지만, 방어적으로 이
	# 최후 방어선도 그대로 유지한다.
	if bytes.size() > AssetLoader.MAX_IMAGE_BYTES:
		_show_limit_message("이 파일은 %s로 너무 커서 열어볼 수조차 없습니다(최대 %s)." % [
			CharacterLimitsScript.format_bytes(bytes.size()), CharacterLimitsScript.format_bytes(AssetLoader.MAX_IMAGE_BYTES)
		])
		return

	var texture := AssetLoader.load_texture_from_bytes(bytes)
	if texture == null:
		_show_limit_message("이미지를 열 수 없습니다 - 지원하지 않는 형식이거나 파일이 손상되었을 수 있습니다.")
		return

	var check := CharacterLimitsScript.check_image(texture.get_width(), texture.get_height(), bytes.size(), _pending_slot)
	if not check["ok"]:
		if check.get("can_auto_resize", false):
			_pending_resize = {"texture": texture, "file_name": file_name, "slot": _pending_slot}
			_resize_confirm_dialog.dialog_text = check["message"] + "\n\n자동으로 줄여서 넣을까요?"
			_resize_confirm_dialog.popup_centered()
		else:
			_show_limit_message(check["message"])
		return

	_finish_image_upload(bytes, file_name, _pending_slot)


func _finish_image_upload(bytes: PackedByteArray, file_name: String, slot: String) -> void:
	var saved_name := CharacterLibrary.save_asset_bytes(_profile.id, "", file_name, bytes)
	if saved_name.is_empty():
		storage_write_failed.emit()
		return

	if slot == "portrait":
		_profile.portrait_file = saved_name
	else:
		_profile.thumbnail_file = saved_name

	_refresh_previews()
	changed.emit()


## 픽셀 한도 초과로 거부됐던 이미지를 한도에 맞게 줄여서 다시 검사한다.
## Image.resize()는 원본 비율을 유지한 채 긴 변을 한도에 맞춘다(짧은 변은
## 비율대로 같이 줄어듦 - 찌그러지지 않음). 원본 확장자를 그대로 유지해서
## 다시 인코딩한다 - PNG는 무손실, JPG/WebP는 품질 0.9로 손실 압축.
##
## resize()/인코딩은 동기 호출이라 큰 이미지에서는 잠깐 멈춘 것처럼 보일 수
## 있다(특히 스레드를 못 쓰는 웹). 그래서 버튼 문구를 "처리 중..."으로 바꾸고
## 한 프레임을 기다린 뒤에 실제 작업을 한다 - await 없이 바로 무거운 작업을
## 하면 문구가 바뀌었다는 사실 자체가 화면에 그려지기 전에 멈춰버린다.
func _on_resize_confirmed() -> void:
	if _pending_resize.is_empty() or _profile == null:
		return

	var data := _pending_resize
	_pending_resize = {}

	var texture: Texture2D = data["texture"]
	var file_name: String = data["file_name"]
	var slot: String = data["slot"]

	var portrait_original := _portrait_load_button.text
	var thumbnail_original := _thumbnail_load_button.text
	_set_load_buttons_disabled(true)
	_portrait_load_button.text = "처리 중..."
	_thumbnail_load_button.text = "처리 중..."
	await get_tree().process_frame

	var max_dimension: int = CharacterLimitsScript.PORTRAIT_MAX_DIMENSION if slot == "portrait" else CharacterLimitsScript.THUMBNAIL_MAX_DIMENSION
	var image := texture.get_image()
	var long_side := maxi(image.get_width(), image.get_height())
	var scale := float(max_dimension) / float(long_side)
	var new_width := maxi(1, roundi(image.get_width() * scale))
	var new_height := maxi(1, roundi(image.get_height() * scale))
	image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)

	var new_bytes: PackedByteArray
	match file_name.get_extension().to_lower():
		"jpg", "jpeg":
			new_bytes = image.save_jpg_to_buffer(0.9)
		"webp":
			new_bytes = image.save_webp_to_buffer(false, 0.9)
		_:
			new_bytes = image.save_png_to_buffer()

	_portrait_load_button.text = portrait_original
	_thumbnail_load_button.text = thumbnail_original
	_set_load_buttons_disabled(false)

	var recheck := CharacterLimitsScript.check_image(new_width, new_height, new_bytes.size(), slot)
	if not recheck["ok"]:
		_show_limit_message("자동으로 줄였는데도 용량 제한을 넘습니다.\n\n" + recheck["message"])
		return

	_finish_image_upload(new_bytes, file_name, slot)


func _show_limit_message(message: String) -> void:
	_limit_dialog.dialog_text = message
	_limit_dialog.popup_centered()


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
