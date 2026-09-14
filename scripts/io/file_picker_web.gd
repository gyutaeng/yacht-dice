class_name FilePickerWeb
extends FilePicker

# 웹 구현: 숨긴 <input type=file>을 만들어 클릭시키고, FileReader로 읽은
# ArrayBuffer를 JavaScriptBridge로 PackedByteArray로 바꿔 받는다.
#
# 중요: 브라우저는 실제 사용자 클릭(버튼 pressed 등)의 콜스택 "안에서"만
# 파일 선택창을 허용한다. 그래서 pick_files()는 처음부터 끝까지(콜백 등록 ->
# JS eval -> input.click()) 전부 동기적으로 실행된다 — await도, call_deferred도,
# 한 프레임 미루는 것도 없다. 호출하는 쪽도 버튼의 pressed 핸들러 안에서
# 곧바로(다른 await를 거치지 않고) pick_files()를 불러야 한다.
#
# 참고: Scrawach/godot-file-access-web과 같은 방식(hidden input + FileReader +
# JavaScriptBridge.create_callback)을 쓰되, 이 기능에 필요한 만큼만 직접 짰다.

var _pending_extensions: Array[String] = []
var _received_files: Array = []
var _expected_total: int = -1
var _call_token: int = -1

static var _next_token: int = 0


func pick_files(extensions: Array[String], multiple: bool) -> void:
	_pending_extensions = extensions
	_received_files = []
	_expected_total = -1
	_call_token = FilePickerWeb._next_token
	FilePickerWeb._next_token += 1

	var file_cb_name := "__godot_file_picker_file_%d" % _call_token
	var cancel_cb_name := "__godot_file_picker_cancelled_%d" % _call_token

	var window_obj := JavaScriptBridge.get_interface("window")
	window_obj.set(file_cb_name, JavaScriptBridge.create_callback(_on_js_file_data))
	window_obj.set(cancel_cb_name, JavaScriptBridge.create_callback(_on_js_cancelled))

	var accept := ""
	for i in extensions.size():
		if i > 0:
			accept += ","
		accept += "." + extensions[i]

	var js := """
(function() {
	var input = document.createElement('input');
	input.type = 'file';
	input.accept = '%s';
	input.multiple = %s;
	input.style.display = 'none';
	document.body.appendChild(input);

	var handled = false;
	var cleanup = function() {
		window.removeEventListener('focus', onFocus);
		if (input.parentNode) { input.parentNode.removeChild(input); }
	};

	// change 이벤트가 브라우저마다 취소 시에도/안에도 오지 않을 수 있어서,
	// 창이 다시 포커스를 받았는데도 파일이 하나도 없으면 취소로 간주한다.
	var onFocus = function() {
		setTimeout(function() {
			if (handled) { return; }
			if (!input.files || input.files.length === 0) {
				handled = true;
				window.%s();
				cleanup();
			}
		}, 300);
	};
	window.addEventListener('focus', onFocus);

	input.addEventListener('change', function() {
		handled = true;
		var files = input.files;
		if (!files || files.length === 0) {
			window.%s();
			cleanup();
			return;
		}
		var total = files.length;
		for (var i = 0; i < total; i++) {
			(function(idx) {
				var file = files[idx];
				var reader = new FileReader();
				reader.onload = function() {
					window.%s(file.name, reader.result, idx, total);
				};
				reader.readAsArrayBuffer(file);
			})(i);
		}
		cleanup();
	});

	input.click();
})();
""" % [accept, str(multiple), cancel_cb_name, cancel_cb_name, file_cb_name]

	JavaScriptBridge.eval(js, true)


func _on_js_file_data(name, buffer, index, total) -> void:
	if not JavaScriptBridge.is_js_buffer(buffer):
		push_warning("FilePickerWeb: 콜백 인자가 JS 버퍼가 아님 - %s" % str(name))
		return

	var bytes: PackedByteArray = JavaScriptBridge.js_buffer_to_packed_byte_array(buffer)
	_received_files.append({"name": String(name), "bytes": bytes})
	_expected_total = int(total)

	if _received_files.size() >= _expected_total:
		_cleanup_js_callbacks()
		_finalize_pick(_received_files, _pending_extensions)


func _on_js_cancelled() -> void:
	_cleanup_js_callbacks()
	pick_cancelled.emit()


func _cleanup_js_callbacks() -> void:
	var file_cb_name := "__godot_file_picker_file_%d" % _call_token
	var cancel_cb_name := "__godot_file_picker_cancelled_%d" % _call_token
	JavaScriptBridge.eval("delete window.%s; delete window.%s;" % [file_cb_name, cancel_cb_name], true)
