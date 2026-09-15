extends Node

# 이 파일은 addons/build_stamp(EditorExportPlugin)가 export할 때마다 자동으로
# 덮어쓴다 - 직접 값을 고쳐도 다음 export에서 사라지니 의미가 없다.
#
# 왜 필요한가: 웹 빌드를 여러 번 내보내면서 "지금 브라우저에 뜬 게 방금 만든
# 새 빌드인지 예전 빌드인지" 구분이 안 돼 테스트가 제자리를 맴돌았다. 그래서
# 게임이 시작될 때 이 값을 화면(브라우저 상단 배너)과 콘솔 양쪽에 찍는다.
const BUILD_TIME := "2026-09-15 18:44"


func _ready() -> void:
	print("[YachtDice] 빌드: %s" % BUILD_TIME)
	if OS.has_feature("web"):
		_stamp_browser()


## HTML 셸의 head_include가 심어둔 배너(#yd-build-banner)를 실제 빌드 시각으로
## 갱신한다. 이 함수가 실행됐다는 것 자체가 "엔진이 실제로 부팅해서 이
## GDScript까지 실행됐다"는 증거라, 배너 텍스트가 "HTML 셸 로드됨"에서 안
## 바뀌면 엔진/WASM 초기화 단계에서 멈췄다는 뜻이다.
func _stamp_browser() -> void:
	var js := """
(function() {
	var b = document.getElementById('yd-build-banner');
	if (!b) {
		b = document.createElement('div');
		b.id = 'yd-build-banner';
		b.style.cssText = 'position:fixed;top:0;left:0;z-index:99999;background:#000;color:#0f0;font:12px monospace;padding:2px 6px;pointer-events:none;';
		document.body.appendChild(b);
	}
	b.textContent = '빌드: %s (엔진 시작됨)';
	console.log('[YachtDice] 빌드: %s (엔진이 실제로 시작되어 이 GDScript가 실행됨)');
})();
""" % [BUILD_TIME, BUILD_TIME]
	JavaScriptBridge.eval(js, true)
