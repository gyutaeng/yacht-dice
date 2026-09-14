class_name FilePicker
extends Node

# 사용자 컴퓨터의 파일을 골라 바이트로 가져오는 공통 인터페이스. 데스크톱과
# 웹은 파일 선택 방식이 완전히 다르므로(OS 파일 다이얼로그 vs 브라우저
# <input type=file>) 실제 구현은 FilePickerDesktop/FilePickerWeb 두 개로
# 나뉘고, 이 클래스는 그 둘이 공유하는 시그널과 "받은 뒤 한 번 더 확장자를
# 검사하는" 로직만 갖는다.
#
# 사용법: FilePicker.create()로 현재 플랫폼에 맞는 구현을 받아 씬에
# add_child()한 뒤 files_picked/pick_cancelled를 구독하고 pick_files()를 부른다.

signal files_picked(files: Array)  # 각 원소: { "name": String, "bytes": PackedByteArray }
signal pick_cancelled()


static func create() -> FilePicker:
	if OS.has_feature("web"):
		return FilePickerWeb.new()
	return FilePickerDesktop.new()


func pick_files(_extensions: Array[String], _multiple: bool) -> void:
	push_error("FilePicker.pick_files()는 추상 메서드다 — FilePicker.create()로 만든 구현체를 써야 한다.")


## OS/브라우저의 파일 필터는 참고용일 뿐 강제가 아니다(사용자가 "모든 파일"로
## 바꿔서 엉뚱한 확장자를 고를 수 있음) — 그래서 실제로 받은 뒤 여기서 다시
## 확인한다. 안 맞는 파일은 조용히 빠지고(개별 경고만 남김), 통과한 것만
## files_picked로 나간다. 두 구현이 이 검사를 각자 다시 짜지 않도록 공통으로 둔다.
func _finalize_pick(raw_files: Array, allowed_extensions: Array[String]) -> void:
	var lowered_allowed: Array[String] = []
	for ext in allowed_extensions:
		lowered_allowed.append(ext.to_lower())

	var accepted: Array = []
	for entry in raw_files:
		var file_name: String = entry.name
		var ext := file_name.get_extension().to_lower()
		if lowered_allowed.has(ext):
			accepted.append(entry)
		else:
			push_warning("FilePicker: 확장자가 허용 목록에 없어 건너뜀 - %s" % file_name)

	files_picked.emit(accepted)
