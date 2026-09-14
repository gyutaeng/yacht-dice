extends RefCounted

# FilePicker의 실제 OS 파일 다이얼로그/브라우저 상호작용은 이 스위트가 아니라
# windowed 실행(데스크톱)이나 export 후 브라우저(웹)로 확인한다(VoiceBank 등과
# 같은 관례). 여기서는 두 구현이 공유하는 순수 로직만 검증한다: 받은 파일을
# 확장자로 다시 거르는 FilePicker._finalize_pick()과, FileDialog.filters 문자열을
# 만드는 FilePickerDesktop._build_filters().


func run(r) -> void:
	r.begin_suite("FilePicker 판정 로직")

	_test_finalize_pick_filters_by_extension(r)
	_test_finalize_pick_case_insensitive(r)
	_test_finalize_pick_all_rejected(r)
	_test_finalize_pick_empty_input(r)
	_test_build_filters(r)


# GDScript 람다는 바깥 지역 변수를 "값으로" 캡처한다 — 람다 안에서
# `received = files`처럼 변수 자체를 재대입하면 람다 자신의 복사본만 바뀌고
# 바깥 스코프엔 반영되지 않는다. 그래서 한 칸짜리 배열에 담아 "내용물"을
# 바꾸는 식으로 우회한다(이 프로젝트의 다른 테스트 스위트와 같은 관례).

func _test_finalize_pick_filters_by_extension(r) -> void:
	var picker := FilePicker.new()
	var received := [[]]
	picker.files_picked.connect(func(files): received[0] = files)

	var raw: Array = [
		{"name": "portrait.png", "bytes": PackedByteArray([1, 2, 3])},
		{"name": "malware.exe", "bytes": PackedByteArray([4, 5, 6])},
		{"name": "voice.wav", "bytes": PackedByteArray([7, 8, 9])},
	]
	var allowed: Array[String] = ["png", "jpg", "jpeg", "webp"]
	picker._finalize_pick(raw, allowed)

	r.expect_eq("허용 확장자만 통과(3개 중 1개)", received[0].size(), 1)
	if received[0].size() == 1:
		r.expect_eq("통과한 건 portrait.png", received[0][0].name, "portrait.png")
	picker.free()


func _test_finalize_pick_case_insensitive(r) -> void:
	var picker := FilePicker.new()
	var received := [[]]
	picker.files_picked.connect(func(files): received[0] = files)

	var raw: Array = [{"name": "PHOTO.PNG", "bytes": PackedByteArray([1])}]
	var allowed: Array[String] = ["png"]
	picker._finalize_pick(raw, allowed)

	r.expect_eq("대문자 확장자도 소문자 허용 목록과 매칭됨", received[0].size(), 1)
	picker.free()


func _test_finalize_pick_all_rejected(r) -> void:
	var picker := FilePicker.new()
	var received := [[]]
	var emitted := [false]
	picker.files_picked.connect(func(files):
		received[0] = files
		emitted[0] = true)

	var raw: Array = [{"name": "song.mp3", "bytes": PackedByteArray([1])}]
	var allowed: Array[String] = ["wav", "ogg"]
	picker._finalize_pick(raw, allowed)

	r.expect_true("전부 탈락해도 files_picked는 emit됨(빈 배열로)", emitted[0])
	r.expect_eq("전부 탈락하면 빈 배열", received[0].size(), 0)
	picker.free()


func _test_finalize_pick_empty_input(r) -> void:
	var picker := FilePicker.new()
	var received := [["dummy"]]  # 초기값을 일부러 비지 않게 해서, emit이 실제로 안 일어나면 테스트가 실패하도록.
	picker.files_picked.connect(func(files): received[0] = files)

	picker._finalize_pick([], ["png"])

	r.expect_eq("애초에 받은 게 없으면 빈 배열로 emit", received[0].size(), 0)
	picker.free()


func _test_build_filters(r) -> void:
	var picker := FilePickerDesktop.new()

	var filters := picker._build_filters(["png", "jpg"])
	r.expect_eq("filters 배열은 항목 1개", filters.size(), 1)
	r.expect_eq("filters 포맷", filters[0], "*.png,*.jpg ; 허용된 파일")

	var empty_filters := picker._build_filters([])
	r.expect_eq("확장자가 없으면 빈 filters", empty_filters.size(), 0)
	picker.free()
