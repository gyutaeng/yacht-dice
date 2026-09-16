extends Node

# 이 파일은 addons/build_stamp(EditorExportPlugin)가 export할 때마다 자동으로
# 덮어쓴다 - 직접 값을 고쳐도 다음 export에서 사라지니 의미가 없다.
#
# 왜 필요한가: 웹 빌드를 여러 번 내보내면서 "지금 브라우저에 뜬 게 방금 만든
# 새 빌드인지 예전 빌드인지" 구분이 안 돼 테스트가 제자리를 맴돌았다. 그래서
# 게임이 시작될 때 이 값을 화면(브라우저 상단 배너)과 콘솔 양쪽에 찍는다.
const BUILD_TIME := "2026-09-16 14:21"

# 이 상수는 addons/build_stamp가 건드리지 않는다(정규식이 BUILD_TIME 줄만 골라
# 바꾼다) - export를 다시 해도 아래 값이 그대로 유지된다.
#
# ============================================================
# 개발/테스트용 디버그 기능을 전부 묶는 하나의 스위치.
#
# **베타 배포 후(사용자 지적) - 더 이상 손으로 켜고 끄는 상수가 아니다.**
# 예전엔 여기 값을 true/false로 직접 고쳐서 배포했는데, "다시 켜는 걸
# 잊거나 켠 채로 내보내는 사고"가 반복될 위험이 있었다. 지금은 export
# 프리셋 자체(export_presets.cfg)의 Custom Features 태그로 자동 결정된다 -
# "Web (release)" 프리셋에만 붙어 있는 "yd_release" 태그가 있으면 꺼지고,
# 없으면(에디터에서 그냥 실행할 때 포함) 켜진 채로 남는다. 이 판정은
# `OS.has_feature()`로 실제 빌드에 구운 값을 읽는 것이라, 상수를 깜빡
# 안 고친 실수가 애초에 발생할 수 없다. 이 태그는 실제 export에서만
# 구워지고 에디터의 "실행" 버튼/`godot` 직접 실행에는 절대 안 붙는다는
# 것을 임시 빌드로 직접 확인했다(`docs/web_export.md` "DEBUG_MODE 자동
# 전환" 참고) - 그래서 "에디터에서는 항상 켜져 있어야 한다"는 요구사항이
# 코드를 안 갈라도 저절로 만족된다.
#
# 묶여 있는 것:
#   - scripts/dev/debug_hotkeys.gd의 Ctrl+Shift+숫자/S/A 키보드 단축키
#   - 같은 파일의 화면 우하단 디버그 버튼 6개(웹은 브라우저가 Ctrl+숫자를
#     가로채서 키가 안 먹을 수 있어 버튼으로 이중화함)
#   - Main.gd의 화면 좌상단 진단 로그(초기화 단계, special_hand_rolled
#     구독자 수 등 - _debug_init_log() 참고)
#
# **서버(server_main.gd) 콘솔 로그는 이 스위치와 무관하다.** 서버 콘솔은
# 친구들이 보는 화면이 아니라 운영자가 문제를 진단하는 유일한 창이라서,
# 서버 쪽 print()는 처음부터 거의 전부 이 스위치 없이 무조건 찍히도록
# 짜여 있었다(2-1부터의 관례) - 이번에 재대전 버그 조사용으로 추가했던
# 로그 3곳만 실수로 이 스위치에 묶여 있어서 무조건 출력으로 되돌렸다.
# ============================================================
static var DEBUG_MODE: bool = not OS.has_feature("yd_release")


func _ready() -> void:
	print("[YachtDice] 빌드: %s (디버그 기능: %s)" % [BUILD_TIME, "켜짐" if DEBUG_MODE else "꺼짐"])
	if OS.has_feature("web"):
		_stamp_browser()


## HTML 셸의 head_include가 심어둔 배너(#yd-build-banner)를 실제 빌드 시각으로
## 갱신한다. 이 함수가 실행됐다는 것 자체가 "엔진이 실제로 부팅해서 이
## GDScript까지 실행됐다"는 증거라, 배너 텍스트가 "HTML 셸 로드됨"에서 안
## 바뀌면 엔진/WASM 초기화 단계에서 멈췄다는 뜻이다.
func _stamp_browser() -> void:
	var debug_label := "디버그 켜짐" if DEBUG_MODE else "디버그 꺼짐"
	var js := """
(function() {
	var b = document.getElementById('yd-build-banner');
	if (!b) {
		b = document.createElement('div');
		b.id = 'yd-build-banner';
		b.style.cssText = 'position:fixed;top:0;left:0;z-index:99999;background:#000;color:#0f0;font:12px monospace;padding:2px 6px;pointer-events:none;';
		document.body.appendChild(b);
	}
	b.textContent = '빌드: %s (엔진 시작됨, %s)';
	console.log('[YachtDice] 빌드: %s (엔진이 실제로 시작되어 이 GDScript가 실행됨, %s)');
})();
""" % [BUILD_TIME, debug_label, BUILD_TIME, debug_label]
	JavaScriptBridge.eval(js, true)
