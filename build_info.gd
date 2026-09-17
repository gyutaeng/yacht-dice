extends Node

# 이 파일은 addons/build_stamp(EditorExportPlugin)가 export할 때마다 자동으로
# 덮어쓴다 - 직접 값을 고쳐도 다음 export에서 사라지니 의미가 없다.
#
# 왜 필요한가: 웹 빌드를 여러 번 내보내면서 "지금 브라우저에 뜬 게 방금 만든
# 새 빌드인지 예전 빌드인지" 구분이 안 돼 테스트가 제자리를 맴돌았다. 그래서
# 게임이 시작될 때 이 값을 화면(브라우저 상단 배너)과 콘솔 양쪽에 찍는다.
const BUILD_TIME := "2026-09-16 18:02"

# 2-7 후속(사용자 요청) - 친구가 보내주는 로그 한 줄만으로 어느 커밋의
# 코드인지 특정하기 위한 짧은 git 커밋 해시. 기본값 "unknown"은 git을 못
# 읽는 환경(예: .git이 없는 빌드 컨텍스트)에서 그대로 남는 값이다 - 이
# 상수를 못 채웠다고 빌드/export 자체가 실패해서는 안 된다.
#
# 두 곳에서 각자 독립적으로 이 값을 채운다(경로가 다르다):
#   - 클라이언트(Web/Desktop export): addons/build_stamp/build_stamp_export_plugin.gd가
#     BUILD_TIME과 같은 방식(export 시작 시 정규식 치환)으로 채운다.
#   - 서버(Docker 이미지): 이 파일이 export 파이프라인을 안 거치고 그대로
#     이미지에 들어가므로, Dockerfile이 이미지 빌드 중 같은 방식(sed)으로
#     따로 채운다 - 둘 중 하나가 안 됐다고 다른 하나까지 막히지 않는다.
# 작업 트리에 커밋 안 된 변경사항이 있으면 해시 뒤에 "-dirty"가 붙는다 -
# 커밋 안 된 코드로 뽑은 빌드를 나중에 커밋된 것으로 착각하면 안 되므로.
const BUILD_COMMIT := "unknown"

# 이 두 상수는 addons/build_stamp가 건드리지 않는다(정규식이 BUILD_TIME/
# BUILD_COMMIT 줄만 골라 바꾼다) - export를 다시 해도 아래 값이 그대로 유지된다.
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
	var stamp := _resolve_display_stamp()
	print("[YachtDice] 빌드: %s (%s) (디버그 기능: %s)" % [stamp["time"], stamp["commit"], "켜짐" if DEBUG_MODE else "꺼짐"])
	if OS.has_feature("web"):
		_stamp_browser(stamp)


## 2-7 후속(사용자 지적) - 서버는 export를 안 거치고 소스에서 직접 실행되는
## 경우가 있는데(로컬 테스트, `run_server.bat` 등), 그럴 땐 BUILD_TIME/
## BUILD_COMMIT이 "마지막으로 export/Docker 빌드했던 시점"에 멈춰 있어서
## 오늘 고친 코드로 실행 중인데도 어제 날짜가 찍히는 거짓말을 한다(실제로
## 겪음 - 연결계측 로그는 오늘 코드가 맞는데 배너만 어제를 가리켰다).
##
## `OS.has_feature("template")`는 실제 export된 바이너리(웹/데스크톱, debug/
## release 전부)에서만 참이고, 에디터 바이너리로 소스를 직접 돌리는 모든
## 경우(`--headless`로 씬을 돌리는 것 포함, 실측으로 확인함)에는 거짓이다 -
## 그래서 이 값으로 "지금 export된 빌드를 실행 중인가"를 정확히 가른다.
## export된 빌드는 원본 대신 pck 안 리소스로 도니 res://가 git 저장소를
## 가리키지 않아 아래 git 시도가 자연히 실패해서 baked 값을 그대로 쓴다 -
## 이 함수가 export 결과를 잘못 덮어쓸 걱정은 구조적으로 없다.
func _resolve_display_stamp() -> Dictionary:
	if not OS.has_feature("template"):
		var live_commit := _resolve_runtime_commit()
		if not live_commit.is_empty():
			return {
				"time": Time.get_datetime_string_from_system(false, true).substr(0, 16),
				"commit": live_commit,
			}
		if BUILD_COMMIT == "unknown":
			# git도 못 읽고 export/Docker 스탬프도 없다 - 틀린 값을 보여주는
			# 것보다 모른다고 하는 게 낫다(사용자 지적).
			return {"time": BUILD_TIME, "commit": "unknown(소스 직접 실행 - 스탬프 없음)"}
	return {"time": BUILD_TIME, "commit": BUILD_COMMIT}


## git으로 짧은 커밋 해시를 읽는다(addons/build_stamp의 같은 이름 함수와
## 판정 기준이 동일 - 코드가 다른 이유는 여기는 EditorPlugin이 아니라 게임
## 런타임 코드라 상속/공유가 자연스럽지 않아서다). git이 없거나 이 폴더가
## 저장소가 아니면 빈 문자열을 돌려준다 - 실패를 절대 밖으로 전파하지
## 않는다(서버가 못 켜지는 일은 없어야 함).
func _resolve_runtime_commit() -> String:
	var project_dir := ProjectSettings.globalize_path("res://")

	var hash_output := []
	var hash_exit := OS.execute("git", ["-C", project_dir, "rev-parse", "--short", "HEAD"], hash_output, true)
	if hash_exit != 0 or hash_output.is_empty():
		return ""
	var commit_hash: String = String(hash_output[0]).strip_edges()
	if commit_hash.is_empty():
		return ""

	var status_output := []
	var status_exit := OS.execute("git", ["-C", project_dir, "status", "--porcelain"], status_output, true)
	var is_dirty := status_exit == 0 and not status_output.is_empty() and not String(status_output[0]).strip_edges().is_empty()

	return "%s-dirty" % commit_hash if is_dirty else commit_hash


## HTML 셸의 head_include가 심어둔 배너(#yd-build-banner)를 실제 빌드 시각으로
## 갱신한다. 이 함수가 실행됐다는 것 자체가 "엔진이 실제로 부팅해서 이
## GDScript까지 실행됐다"는 증거라, 배너 텍스트가 "HTML 셸 로드됨"에서 안
## 바뀌면 엔진/WASM 초기화 단계에서 멈췄다는 뜻이다.
func _stamp_browser(stamp: Dictionary) -> void:
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
	b.textContent = '빌드: %s (%s) (엔진 시작됨, %s)';
	console.log('[YachtDice] 빌드: %s (%s) (엔진이 실제로 시작되어 이 GDScript가 실행됨, %s)');
})();
""" % [stamp["time"], stamp["commit"], debug_label, stamp["time"], stamp["commit"], debug_label]
	JavaScriptBridge.eval(js, true)
