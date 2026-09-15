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
#
# 중요(GC 함정 - 콜백 객체): JavaScriptBridge.create_callback()이 돌려주는
# JavaScriptObject를 지역 변수/임시값으로만 쓰면, GDScript 쪽에서 아무도
# 참조를 안 들고 있으니 다음 GC 사이클에 회수된다. 그러면 JS의
# window[콜백이름]은 죽은 참조가 되어 change/onload가 와도 Godot으로
# 아무것도 안 돌아온다. 그래서 반드시 멤버 변수에 담아 pick_files() 호출이
# 끝난 뒤에도(콜백이 실제로 불릴 때까지) 살려둔다.
#
# 중요(GC 함정 - FilePicker 인스턴스 자체): 콜백 객체를 멤버 변수에 담아도,
# 그 멤버를 들고 있는 이 노드 자체가 씬 트리에서 빠지거나 해제되면 똑같이
# 죽는다. 그래서 이 클래스는 반드시 호출하는 쪽(예: file_picker_test.gd)이
# 멤버 변수에 담고 add_child()로 씬 트리에 붙여서, 선택이 끝날 때까지(정확히는
# _finalize_pick/pick_cancelled가 emit될 때까지) 살아있게 해야 한다 - 이
# 클래스 자신은 스스로를 씬 트리에 붙이지 않으므로 호출부 책임이다.
var _select_callback: JavaScriptObject
var _file_callback: JavaScriptObject
var _error_callback: JavaScriptObject
var _cancel_callback: JavaScriptObject
var _js_error_callback: JavaScriptObject

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

	var select_cb_name := "__godot_file_picker_selected_%d" % _call_token
	var file_cb_name := "__godot_file_picker_file_%d" % _call_token
	var error_cb_name := "__godot_file_picker_error_%d" % _call_token
	var cancel_cb_name := "__godot_file_picker_cancelled_%d" % _call_token
	var js_error_cb_name := "__godot_file_picker_jserror_%d" % _call_token

	_select_callback = JavaScriptBridge.create_callback(_on_js_selected)
	_file_callback = JavaScriptBridge.create_callback(_on_js_file_data)
	_error_callback = JavaScriptBridge.create_callback(_on_js_file_error)
	_cancel_callback = JavaScriptBridge.create_callback(_on_js_cancelled)
	_js_error_callback = JavaScriptBridge.create_callback(_on_js_error)

	var window_obj := JavaScriptBridge.get_interface("window")
	window_obj.set(select_cb_name, _select_callback)
	window_obj.set(file_cb_name, _file_callback)
	window_obj.set(error_cb_name, _error_callback)
	window_obj.set(cancel_cb_name, _cancel_callback)
	window_obj.set(js_error_cb_name, _js_error_callback)

	var accept := ""
	for i in extensions.size():
		if i > 0:
			accept += ","
		accept += "." + extensions[i]

	_debug("파일 선택창을 여는 중 (허용 확장자: %s, 다중 선택: %s)" % [accept, multiple])

	# 아래 각 이벤트 핸들러 본문을 개별 try/catch로 감싼 이유: change/cancel/
	# onFocus 콜백은 IIFE가 끝난 뒤 "나중에" 브라우저 이벤트 루프에서 실행되므로,
	# IIFE 바깥을 한 번 감싸는 것만으로는 이 안에서 던져진 예외를 못 잡는다.
	# 여기서 잡아 reportError로 콘솔+Godot 양쪽에 남기지 않으면, 이벤트가
	# 왔는데도 예외 때문에 마지막 한 줄(Godot 콜백 호출)까지 못 가는 경우를
	# "아예 조용히 죽음"으로만 보게 된다.
	var js := """
(function() {
	function reportError(context, err) {
		console.error('[FilePicker] ' + context + ' 중 예외 발생:', err);
		try {
			window.%s(context + ': ' + (err && err.message ? err.message : String(err)));
		} catch (e2) {
			console.error('[FilePicker] 에러 콜백 자체도 실패:', e2);
		}
	}

	try {
		console.log('[FilePicker] input 생성 및 클릭 시도');
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
				try {
					console.log('[FilePicker] window focus 복귀 감지, 파일 선택 상태 확인 중...');
					if (handled) { return; }
					if (!input.files || input.files.length === 0) {
						handled = true;
						console.log('[FilePicker] focus 복귀 후에도 선택된 파일 없음 -> 취소로 간주');
						window.%s();
						cleanup();
					}
				} catch (err) {
					reportError('onFocus 타임아웃 콜백', err);
				}
			}, 300);
		};
		window.addEventListener('focus', onFocus);

		// 최신 브라우저(Chrome 113+ 등)는 파일 선택창을 취소하면 change 없이
		// 이 네이티브 cancel 이벤트가 곧바로 온다 - 있으면 이걸로 즉시 처리하고,
		// 없는 브라우저는 위 onFocus 타임아웃이 대신 잡는다.
		input.addEventListener('cancel', function() {
			try {
				console.log('[FilePicker] cancel 이벤트(네이티브) 수신');
				if (handled) { return; }
				handled = true;
				window.%s();
				cleanup();
			} catch (err) {
				reportError('cancel 이벤트 핸들러', err);
			}
		});

		input.addEventListener('change', function() {
			console.log('[FilePicker] change 이벤트 수신(원본) - files.length=' + (input.files ? input.files.length : 'null'));
			try {
				handled = true;
				var files = input.files;
				if (!files || files.length === 0) {
					console.log('[FilePicker] change 이벤트는 왔지만 파일 0개 -> 취소로 간주');
					window.%s();
					cleanup();
					return;
				}
				var total = files.length;
				var names = [];
				for (var n = 0; n < total; n++) { names.push(files[n].name); }
				console.log('[FilePicker] change 이벤트 수신: ' + total + '개 - ' + names.join(', '));
				window.%s(total, names.join(','));

				for (var i = 0; i < total; i++) {
					(function(idx) {
						var file = files[idx];
						var reader = new FileReader();
						reader.onload = function() {
							try {
								var buf = reader.result;
								console.log('[FilePicker] FileReader.onload: ' + file.name + ' (' + buf.byteLength + '바이트)');
								window.%s(file.name, buf, idx, total);
							} catch (err) {
								reportError('FileReader.onload(' + file.name + ')', err);
							}
						};
						reader.onerror = function() {
							console.error('[FilePicker] FileReader 읽기 실패: ' + file.name, reader.error);
							try {
								window.%s(file.name, idx, total);
							} catch (err) {
								reportError('FileReader.onerror(' + file.name + ')', err);
							}
						};
						reader.readAsArrayBuffer(file);
					})(i);
				}
				cleanup();
			} catch (err) {
				reportError('change 이벤트 핸들러', err);
			}
		});

		input.click();
		console.log('[FilePicker] input.click() 호출 완료 - 브라우저 파일 선택창 대기 중');
	} catch (err) {
		reportError('pick_files 초기 설정', err);
	}
})();
""" % [
		js_error_cb_name,
		accept, str(multiple),
		cancel_cb_name,
		cancel_cb_name,
		cancel_cb_name,
		select_cb_name,
		file_cb_name,
		error_cb_name,
	]

	JavaScriptBridge.eval(js, true)


func _on_js_selected(count, names) -> void:
	_debug("change 이벤트가 Godot에 도착함 - 파일 %s개 (%s)" % [str(count), str(names)])


func _on_js_file_data(name, buffer, index, total) -> void:
	_debug("FileReader.onload 도착 - '%s' (index %s/%s)" % [str(name), str(int(index) + 1), str(total)])

	if not JavaScriptBridge.is_js_buffer(buffer):
		_debug("경고: '%s'의 buffer 인자가 JS ArrayBuffer가 아님(%s) - 빈 바이트로 처리" % [str(name), typeof(buffer)])
		_received_files.append({"name": String(name), "bytes": PackedByteArray()})
	else:
		var bytes: PackedByteArray = JavaScriptBridge.js_buffer_to_packed_byte_array(buffer)
		_debug("PackedByteArray 변환 완료 - '%s' %d바이트" % [String(name), bytes.size()])
		_received_files.append({"name": String(name), "bytes": bytes})

	_expected_total = int(total)
	_maybe_finish()


func _on_js_file_error(name, index, total) -> void:
	_debug("FileReader 읽기 실패 - '%s' (index %s/%s), 빈 바이트로 처리" % [str(name), str(int(index) + 1), str(total)])
	_received_files.append({"name": String(name), "bytes": PackedByteArray()})
	_expected_total = int(total)
	_maybe_finish()


func _maybe_finish() -> void:
	if _expected_total >= 0 and _received_files.size() >= _expected_total:
		_cleanup_js_callbacks()
		_finalize_pick(_received_files, _pending_extensions)


func _on_js_cancelled() -> void:
	_debug("선택 취소됨(브라우저 쪽 취소 감지)")
	_cleanup_js_callbacks()
	pick_cancelled.emit()


## JS 쪽에서 잡힌 예외를 여기로 받는다. 이게 찍힌다면 "콜백이 조용히 안
## 불림"이 아니라 "JS 실행 중 뭔가 던져서 못 갔음"이라는 뜻이라 원인이 완전히
## 달라진다 - 그래서 그 자체로 중요한 진단 정보다. 여기서 픽업을 강제로
## 끝내지는 않는다(어느 단계에서 났는지에 따라 이후 콜백이 여전히 올 수도
## 있어서).
func _on_js_error(message) -> void:
	_debug("JS 쪽에서 예외 발생 - %s" % str(message))


func _cleanup_js_callbacks() -> void:
	var select_cb_name := "__godot_file_picker_selected_%d" % _call_token
	var file_cb_name := "__godot_file_picker_file_%d" % _call_token
	var error_cb_name := "__godot_file_picker_error_%d" % _call_token
	var cancel_cb_name := "__godot_file_picker_cancelled_%d" % _call_token
	var js_error_cb_name := "__godot_file_picker_jserror_%d" % _call_token
	JavaScriptBridge.eval(
		"delete window.%s; delete window.%s; delete window.%s; delete window.%s; delete window.%s;" % [
			select_cb_name, file_cb_name, error_cb_name, cancel_cb_name, js_error_cb_name
		],
		true
	)
