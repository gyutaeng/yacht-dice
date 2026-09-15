# 웹(HTML5) export 절차

## 왜 이 문서가 있는가

웹 빌드를 여러 번 내보내면서 겪은 문제 두 가지 때문에 절차를 문서로 고정해둔다.

1. **내보내기 폴더를 프로젝트 안에 두면 안 된다.** `res://build/` 같은 프로젝트 내부 경로로 export하면, 열려 있는 Godot 에디터가 export된 PNG(`index.png`, `index.icon.png` 등)를 새 리소스로 인식해서 다시 임포트하고 `.import` 파일을 만든다. 그러면 *다음* export의 pck에 그 리소스가 또 들어가는 악순환이 생긴다. 그래서 `export_path`는 항상 프로젝트 바깥이어야 한다.
2. **"지금 보고 있는 게 새 빌드인지 옛날 빌드인지" 구분이 안 되면 테스트가 제자리를 맴돈다.** 그래서 export할 때마다 빌드 시각이 자동으로 화면과 콘솔에 찍히도록 만들어뒀다(아래 "빌드 식별" 참고).

## 내보내기 위치

`export_presets.cfg`의 `export_path`는 **`F:/Godot/web_build/index.html`** — 프로젝트 폴더(`F:/Godot/Project/yacht-dice/`) 바깥이다. 절대 프로젝트 안의 경로로 바꾸지 말 것(위 1번 이유).

## Thread Support는 끈다

`variant/thread_support=false`로 되어 있다. 저장소에서 실제 `Thread`를 쓰는 곳은 `FilePickerDesktop` 하나뿐이고, `FilePicker.create()`는 웹에서 `FilePickerWeb`을 골라 그 코드 자체가 실행되지 않는다(`AssetLoader`/`VoiceBank`/`SfxBank`도 전부 동기 코드). Thread Support를 켜면 COOP/COEP 헤더가 필요해져 정적 파일 서버 설정만 복잡해지므로 끈 채로 둔다.

## 빌드 식별 (addons/build_stamp)

`addons/build_stamp`는 export가 시작될 때(`_export_begin`) `res://build_info.gd`의 `BUILD_TIME` 상수를 현재 시각으로 자동으로 고쳐 쓰는 EditorExportPlugin이다. 에디터 GUI로 내보내든 `godot --headless --export-release ...`로 내보내든 똑같이 동작한다 — 사람이 매번 손으로 시각을 갱신할 필요가 없다.

`BuildInfo`(autoload, `res://build_info.gd`)는 게임이 시작되면:
- 콘솔에 `[YachtDice] 빌드: <시각>`을 `print()`로 찍는다.
- 웹에서는 `JavaScriptBridge.eval()`로 브라우저 페이지 좌상단에 고정된 배너(`#yd-build-banner`)를 만들어 `빌드: <시각> (엔진 시작됨)`을 표시하고 `console.log`도 같이 호출한다.

여기에 더해 `export_presets.cfg`의 `html/head_include`에 **엔진이 뜨기 전에** 실행되는 순수 JS를 심어뒀다 — 페이지가 로드되자마자 같은 배너 자리에 `HTML 셸 로드됨 - 엔진 시작 대기 중...`을 먼저 찍고 `console.log`도 호출한다. 그래서 배너 문구가:
- **"HTML 셸 로드됨..."에서 안 바뀜** → 브라우저는 페이지를 열었지만 Godot 엔진(wasm)이 못 떴다는 뜻. 서버 MIME 타입, 파일 누락, 브라우저 호환성 등을 의심할 것.
- **"빌드: ... (엔진 시작됨)"으로 바뀜** → 엔진이 정상적으로 부팅해서 `BuildInfo` 스크립트까지 실행됐다는 뜻. 이때 시각이 방금 export한 시각과 같은지만 보면 새 빌드인지 옛 빌드(캐시)인지 바로 구분된다.

즉 **개발자 도구를 아예 안 열어도** 브라우저 화면만 보고 두 가지(페이지가 뜨는지 / 엔진이 뜨는지)를 구분할 수 있다. 콘솔을 열면 같은 정보가 `console.log`로도 남아 있다.

`build_info.gd`는 export할 때마다 자동으로 덮어써지는 파일이라, git에는 마지막으로 export한 시각이 커밋될 수 있다 — 신경 쓰지 않아도 된다(직접 값을 고쳐봐야 다음 export에서 사라진다).

## 절차

1. `scenes/dev/file_picker_test.tscn` 등 확인하려는 씬이 `project.godot`의 `run/main_scene`으로 지정돼 있는지 확인한다(임시로 바꿨다면 테스트 후 `res://scenes/Main.tscn`으로 되돌릴 것).
2. 내보내기:
   - 에디터 GUI: `프로젝트 > 내보내기` → Web 프리셋 → 내보내기(Export Project).
   - CLI: `godot --headless --export-release "Web" "F:/Godot/web_build/index.html"` (godot 실행 파일 경로는 환경에 맞게).
   - 어느 쪽이든 `addons/build_stamp`가 자동으로 `build_info.gd`를 갱신한다.
3. `F:/Godot/web_build/`를 정적 파일 서버로 서빙한다 — `file://`로 직접 열면 브라우저가 막는다.
   ```
   cd F:/Godot/web_build
   python -m http.server 8060
   ```
   `http://localhost:8060/index.html`로 접속.
4. 페이지 좌상단 배너로 새 빌드가 떴는지부터 확인한다(위 "빌드 식별" 참고).
5. 파일 선택 버튼처럼 사용자 제스처가 필요한 UI는 **실제로 마우스로 클릭**해서 테스트한다 — 자동화 스크립트로 흉내 낸 클릭은 브라우저가 막을 수 있다.
6. 확인 포인트: 파일 선택창이 뜨는지 / 여러 개 골랐을 때 다 들어오는지 / 취소 시 로그에 "취소됨"만 남고 에러가 없는지(개발자 도구 콘솔도 같이 확인) / 허용 안 한 확장자를 억지로 골라도 걸러지는지 / 이미지 미리보기와 오디오 재생이 실제로 되는지.

## 빌드 용량 참고

릴리스 빌드(Thread Support 끔) 기준 `index.wasm` 39.5MB + `index.pck` ~2.55MB(폰트 포함 게임 리소스) + 나머지(js/아이콘) ~0.3MB = 총 약 41MB. 96%가 Godot 엔진 wasm 자체라 리소스(폰트 등)가 차지하는 비중은 크지 않다. 용량 최적화는 필요해지면 별도로 다룬다.
