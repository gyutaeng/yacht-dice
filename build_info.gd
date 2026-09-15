extends Node

# 이 파일은 addons/build_stamp(EditorExportPlugin)가 export할 때마다 자동으로
# 덮어쓴다 - 직접 값을 고쳐도 다음 export에서 사라지니 의미가 없다.
#
# 왜 필요한가: 웹 빌드를 여러 번 내보내면서 "지금 브라우저에 뜬 게 방금 만든
# 새 빌드인지 예전 빌드인지" 구분이 안 돼 테스트가 제자리를 맴돌았다. 그래서
# 게임이 시작될 때 이 값을 화면(브라우저 상단 배너)과 콘솔 양쪽에 찍는다.
const BUILD_TIME := "2026-09-15 22:28"

# 이 상수는 addons/build_stamp가 건드리지 않는다(정규식이 BUILD_TIME 줄만 골라
# 바꾼다) - export를 다시 해도 아래 값이 그대로 유지된다.
#
# ============================================================
# 개발/테스트용 디버그 기능을 전부 묶는 하나의 스위치.
#
# false면 자동으로 사라지는 게 원칙(OS.has_feature("editor")가 아니라 export
# 여부와 무관하게 이 값 하나로 통일)이지만, 1-6~1-8처럼 웹 export 빌드에서
# 직접 확인해야 하는 작업이 이어지는 동안은 true로 켜둔 채로 개발한다.
#
# 묶여 있는 것:
#   - scripts/dev/debug_hotkeys.gd의 Ctrl+Shift+숫자/S/A 키보드 단축키
#   - 같은 파일의 화면 우하단 디버그 버튼 6개(웹은 브라우저가 Ctrl+숫자를
#     가로채서 키가 안 먹을 수 있어 버튼으로 이중화함)
#   - Main.gd의 화면 좌상단 진단 로그(초기화 단계, special_hand_rolled
#     구독자 수 등 - _debug_init_log() 참고)
#
# **정식 배포 전에는 반드시 false로 되돌릴 것.** 정식 배포판에 디버그 단축키/
# 버튼/진단 로그가 남아있으면 안 된다 - docs/deployment_checklist.md(3-3
# 배포 준비)에서 반드시 확인한다.
# ============================================================
const DEBUG_MODE := true


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
