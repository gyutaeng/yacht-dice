extends VBoxContainer

# 우측 패널: GameEvents.VOICE_EVENTS 테이블을 읽어 행을 자동 생성한다(하드코딩
# 금지 - 테이블에 항목이 늘면 이 화면도 저절로 늘어난다). 오디오 FilePicker
# 하나를 모든 행이 공유하고, "지금 어느 이벤트를 위해 열었는지"만 기억한다.
# 미리듣기도 AudioStreamPlayer 하나를 공유한다(동시에 여러 개가 울릴 필요가 없음).

signal changed()
signal storage_write_failed()

const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

@onready var _rows_container: VBoxContainer = $Scroll/RowsContainer

var _profile: CharacterProfile
var _picker: FilePicker
var _picker_busy: bool = false
var _pending_event_key: String = ""
var _preview_player: AudioStreamPlayer
var _add_buttons: Array[Button] = []


func _ready() -> void:
	_picker = FilePicker.create()
	add_child(_picker)
	_picker.files_picked.connect(_on_files_picked)
	_picker.pick_cancelled.connect(_on_pick_cancelled)

	_preview_player = AudioStreamPlayer.new()
	add_child(_preview_player)

	load_profile(null)


func load_profile(profile: CharacterProfile) -> void:
	_profile = profile
	_preview_player.stop()
	_rebuild_rows()


## 이미지 패널의 볼륨 슬라이더가 움직일 때, "지금 재생 중인" 미리듣기가 있으면
## 그 자리에서 바로 반영한다(다음에 다시 누를 때가 아니라). 재생 중이 아니면
## 아무 일도 안 한다 - 다음 재생부터는 프로필의 volume_db를 다시 읽으니 이미 반영됨.
func update_preview_volume(value: float) -> void:
	if _preview_player.playing:
		_preview_player.volume_db = value


func _rebuild_rows() -> void:
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	_add_buttons.clear()

	for event in GameEvents.VOICE_EVENTS:
		_rows_container.add_child(_build_event_row(event))


func _build_event_row(event: Dictionary) -> Control:
	var files: Array = _profile.voice_map.get(event.key, []) if _profile != null else []
	var is_once: bool = event.frequency == "once"

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	if files.is_empty():
		panel.modulate.a = 0.55  # 보이스가 하나도 없는 이벤트는 흐리게.

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = event.label
	label.add_theme_font_size_override("font_size", 16)
	header.add_child(label)

	var freq_tag := Label.new()
	freq_tag.text = "한 판에 한 번" if is_once else "자주 반복"
	freq_tag.add_theme_font_size_override("font_size", 12)
	freq_tag.modulate = Color(0.6, 0.8, 1.0) if is_once else Color(1.0, 0.8, 0.4)
	header.add_child(freq_tag)
	vbox.add_child(header)

	var desc := Label.new()
	desc.text = event.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate.a = 0.7
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	if not is_once:
		var hint := Label.new()
		hint.text = "여러 개 넣으면 재생 때마다 무작위로 골라줍니다 - 짧은 대사를 여러 개 넣어보세요."
		hint.add_theme_font_size_override("font_size", 11)
		hint.modulate = Color(1.0, 0.8, 0.4, 0.9)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(hint)

	for filename in files:
		vbox.add_child(_build_file_row(event.key, filename))

	var add_button := Button.new()
	add_button.text = "파일 추가"
	add_button.disabled = _profile == null
	add_button.pressed.connect(_on_add_pressed.bind(event.key))
	_add_buttons.append(add_button)
	vbox.add_child(add_button)

	return panel


func _build_file_row(event_key: String, filename: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = filename.get_file()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)

	var play_button := Button.new()
	play_button.text = "▶ 미리듣기"
	play_button.pressed.connect(_on_preview_pressed.bind(filename))
	row.add_child(play_button)

	var remove_button := Button.new()
	remove_button.text = "제거"
	remove_button.pressed.connect(_on_remove_file_pressed.bind(event_key, filename))
	row.add_child(remove_button)

	return row


func _on_preview_pressed(filename: String) -> void:
	if _profile == null:
		return
	var stream := CharacterLibrary.load_profile_audio(_profile, filename)
	if stream == null:
		push_warning("VoiceMappingPanel: 미리듣기 실패 - %s" % filename)
		return
	_preview_player.stop()
	_preview_player.stream = stream
	_preview_player.volume_db = _profile.volume_db
	_preview_player.play()


func _on_remove_file_pressed(event_key: String, filename: String) -> void:
	if _profile == null:
		return
	var files: Array = _profile.voice_map.get(event_key, [])
	files.erase(filename)
	if files.is_empty():
		_profile.voice_map.erase(event_key)
	else:
		_profile.voice_map[event_key] = files
	_rebuild_rows()
	changed.emit()


func _on_add_pressed(event_key: String) -> void:
	if _picker_busy or _profile == null:
		return
	_picker_busy = true
	_pending_event_key = event_key
	_set_add_buttons_disabled(true)
	_picker.pick_files(AUDIO_EXTENSIONS, true)


func _set_add_buttons_disabled(disabled: bool) -> void:
	for button in _add_buttons:
		if is_instance_valid(button):
			button.disabled = disabled or _profile == null


func _on_pick_cancelled() -> void:
	_picker_busy = false
	_set_add_buttons_disabled(false)


func _on_files_picked(files: Array) -> void:
	_picker_busy = false

	if files.is_empty() or _profile == null:
		_set_add_buttons_disabled(false)
		return

	var any_saved := false
	for entry in files:
		var bytes: PackedByteArray = entry.bytes

		if bytes.size() > AssetLoader.MAX_AUDIO_BYTES:
			push_warning("VoiceMappingPanel: 오디오가 크기 상한을 초과함(%d바이트) - %s" % [bytes.size(), entry.name])
			continue
		if AssetLoader.load_audio_from_bytes(bytes) == null:
			push_warning("VoiceMappingPanel: 오디오 디코딩 실패 - %s" % entry.name)
			continue

		var saved_name := CharacterLibrary.save_asset_bytes(_profile.id, "voices", entry.name, bytes)
		if saved_name.is_empty():
			storage_write_failed.emit()
			continue

		var files_for_key: Array = _profile.voice_map.get(_pending_event_key, [])
		files_for_key.append(saved_name)
		_profile.voice_map[_pending_event_key] = files_for_key
		any_saved = true

	_rebuild_rows()  # 버튼 재활성화까지 포함해서 다시 그린다.
	if any_saved:
		changed.emit()
