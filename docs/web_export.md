# 웹(HTML5) export 절차

## 왜 이 문서가 있는가

웹 파일 선택 기능(1-5)을 실제로 브라우저에서 되게 만드는 데 여러 세션이 걸렸다. 겪은 문제와 해결을 다 여기 적어둔다 — 다음에 웹 export를 다시 만지게 되면(1-8 최종 검증, 이후 캐릭터 팩 등) 같은 함정에 또 빠지지 않기 위해서다.

## 절대 쓰지 말 것: 에디터의 "브라우저에서 실행"

Godot 에디터 상단의 "브라우저에서 실행"(웹 플랫폼을 실행 대상으로 골랐을 때 나오는 재생 버튼)은 **쓰지 않는다.** 이건 임시 폴더에 디버그 빌드를 내보내고 에디터 내장 서버로 서빙하는 완전히 별도의 경로라서, 이 문서에 정리된 export 설정(`export_presets.cfg`의 `html/head_include`, `addons/build_stamp` 플러그인 등)이 똑같이 적용되는지 보장이 안 되고, 실제로 정식 export와 다르게 동작하는 게 확인됐다(게임 진행 자체가 막힘 — 정식 export로는 똑같은 상황에서 정상 동작). 왜 다르게 동작하는지는 파고들지 않기로 했다.

**웹 테스트는 항상 아래 절차(export → `F:/Godot/web_build` → `python -m http.server`)만 쓴다.**

## 사전 준비: export template 설치

Godot 에디터 `에디터 > 관리자 내보내기 템플릿`(또는 `Editor > Manage Export Templates`)에서 현재 에디터 버전(4.7.2)과 정확히 일치하는 템플릿을 설치해야 한다. 버전이 안 맞으면 export 자체가 실패한다. 이 프로젝트에서 쓰는 Web 템플릿은 `web_nothreads_release.zip`/`web_nothreads_debug.zip`(아래 "Thread Support" 참고).

## Web 프리셋 설정

`export_presets.cfg`에 이미 구성돼 있고 저장소에 커밋되어 있다(민감한 값이 생기기 전까지는 커밋 대상 — 안드로이드 키스토어 등이 생기면 그때 다시 논의). 핵심 값:

- **`export_path`는 반드시 프로젝트 폴더 바깥**: `F:/Godot/web_build/index.html`. 프로젝트 안(`res://build/` 등)에 두면 열려 있는 Godot 에디터가 export된 PNG(`index.png`, `index.icon.png` 등)를 새 리소스로 인식해서 다시 임포트하고 `.import` 파일을 만든다. 그러면 *다음* export의 pck에 그 리소스가 또 들어가는 악순환이 생긴다 — 실제로 한 번 겪고 `build/` 폴더를 통째로 지운 적 있다. 절대 프로젝트 안의 경로로 바꾸지 말 것.
- **`variant/thread_support=false`**: 저장소에서 실제 `Thread`를 쓰는 곳은 `FilePickerDesktop` 하나뿐이고, `FilePicker.create()`는 웹에서 `FilePickerWeb`을 골라 그 코드 자체가 실행되지 않는다(`AssetLoader`/`VoiceBank`/`SfxBank`도 전부 동기 코드). Thread Support를 켜면 COOP/COEP 헤더가 필요해져 정적 파일 서버 설정만 복잡해지므로 끈 채로 둔다.
- `html/head_include`: 엔진이 뜨기 전에 실행되는 진단용 스크립트(아래 "빌드 식별" 참고).

## DEBUG_MODE 자동 전환 (베타 배포 후 추가)

`export_presets.cfg`에 웹 프리셋이 **두 개** 있다 - `Web (개발)`
(`custom_features=""`)과 `Web (배포)`(`custom_features="yd_release"`).
`build_info.gd`의 `DEBUG_MODE`는 더 이상 손으로 켜고 끄는 상수가 아니라
`not OS.has_feature("yd_release")`로 계산되는 값이라, **어느 프리셋으로
export했는지가 DEBUG_MODE를 자동으로 정한다** - "고치는 걸 잊고 배포"
사고 자체가 구조적으로 안 생긴다.

- **왜 가능한지 실제로 확인한 방법**: 임시 Windows Desktop 프리셋에
  `custom_features="yd_test_tag"`를 달아 export한 뒤, 그 실행 파일이
  `OS.has_feature("yd_test_tag")`를 `true`로 돌려주는지, 반대로 에디터에서
  같은 씬을 그냥 실행했을 때는 `false`인지 직접 실행해서 확인했다
  (`godot --headless res://...tscn`으로 직접 실행 vs
  `--export-release`로 내보낸 뒤 그 바이너리를 실행 - 전자는 시종일관
  `false`, 후자만 `true`). Custom Features 태그는 **실제 export에서만
  바이너리에 구워지고, 에디터의 "실행" 버튼에는 절대 안 붙는다**는 게
  이걸로 확정됐다 - 그래서 "에디터에서는 항상 디버그가 켜져 있어야
  한다"는 요구사항이 코드를 안 갈라도 저절로 만족된다. 검증용 프리셋/
  씬은 확인 후 전부 지워서 저장소에 안 남는다.
- **export 시점 확인**: `addons/build_stamp`가 export가 시작되는 순간
  콘솔에 `BuildStamp: 배포용 빌드(yd_release 태그 있음) - DEBUG_MODE
  꺼짐` 또는 `개발용 빌드(...) - DEBUG_MODE 켜짐`을 바로 찍어준다 -
  실행 결과를 기다릴 필요 없이 export 버튼을 누른 그 자리에서 프리셋을
  잘못 고르지 않았는지 알 수 있다.
- **런타임 확인**: 게임이 시작될 때 찍히는 빌드 배너(아래 "빌드 식별")
  자체에 `디버그 켜짐`/`디버그 꺼짐`이 같이 찍힌다 - 상수 값을 눈으로
  믿는 대신 실제로 그 빌드에 구워진 값을 화면에서 바로 확인한다.
- **서버(`server_main.gd`) 콘솔 로그는 이 전환과 무관하다** - 서버는 이
  Web 프리셋들과 별개의 headless 바이너리로 항상 따로 돌리고, 서버 쪽
  `print()`는 처음부터 DEBUG_MODE에 안 묶여 있다(운영자가 보는 유일한
  진단 창이라 항상 켜둬야 하므로 - `docs/deployment_checklist.md` 참고).

## 로컬 서버로 서빙 — `file://`로 직접 열면 안 되는 이유

브라우저는 `file://` 프로토콜에서 `fetch()`(Godot의 `.pck`/`.wasm` 로딩이 이걸 씀)를 CORS 정책으로 막는다. 그래서 export한 `index.html`을 더블클릭해서 열면 리소스를 하나도 못 불러오고 조용히 실패하거나 에러만 뜬다. 반드시 정적 파일 서버를 거쳐야 한다:

```
cd F:/Godot/web_build
python -m http.server 8060
```

`http://localhost:8060/index.html`로 접속.

## 절차 요약

1. 확인하려는 씬이 `project.godot`의 `run/main_scene`으로 지정돼 있는지 확인한다.
2. 내보내기:
   - 에디터 GUI: `프로젝트 > 내보내기` → Web 프리셋 → 내보내기(Export Project).
   - CLI: `godot --headless --export-release "Web (개발)" "F:/Godot/web_build/index.html"`.
     베타/정식 배포용 빌드는 `"Web (배포)"` 프리셋을 쓴다(아래 "DEBUG_MODE
     자동 전환" 참고, `docs/deployment_checklist.md`에 절차 있음).
   - 어느 쪽이든 `addons/build_stamp`가 자동으로 `build_info.gd`에 빌드 시각을 찍는다.
3. 위 방법으로 로컬 서버를 띄우고 접속한다.
4. **가장 먼저, 페이지 좌상단 빌드 배너부터 확인한다**(아래 "빌드 식별" 참고) — 이거 없이 테스트를 시작하면 옛날 빌드를 붙잡고 왜 안 되냐며 헤매게 된다. 실제로 여러 세션에 걸쳐 이걸로 시간을 많이 썼다.
5. 사용자 제스처가 필요한 UI(파일 선택 등)는 **실제로 마우스로 클릭**해서 테스트한다 — 자동화 스크립트로 흉내 낸 클릭은 브라우저가 막을 수 있다.

## 오늘(그리고 지난 세션들) 막혔던 지점과 해결

### 1. 한글이 전부 네모(□)로 깨짐
Godot 기본 폰트에 한글 글리프가 없다. 데스크톱은 OS 시스템 폰트로 대체돼서 몰랐는데, 웹은 대체할 시스템 폰트가 없어서 그대로 깨진다. → Pretendard(OFL-1.1, `assets/fonts/`)를 `project.godot`의 `[gui] theme/custom_font`로 프로젝트 기본 폰트로 지정해서 해결.

### 2. 직접 짠 JavaScriptBridge 콜백이 Godot으로 안 돌아옴
`JavaScriptBridge.create_callback()`이 돌려주는 `JavaScriptObject`를 지역 변수로만 쓰면 GC되어 JS의 `window[콜백이름]`이 죽은 참조가 된다 — 멤버 변수에 담아 살려두는 것까지 고쳤는데도, 여전히 파일 선택창은 뜨지만 `change`/`cancel` 콜백이 전혀 안 돌아오는 증상이 계속됐다(원인을 끝내 못 찾음). → 여러 라운드 자체 디버깅 후, 검증된 애드온 [`godot-file-access-web`](https://github.com/Scrawach/godot-file-access-web)(Scrawach, MIT License)의 핵심 스크립트로 교체해서 해결. `addons/FileAccessWeb/core/file_access_web.gd`에 수정 없이 그대로 벤더링했고, `scripts/io/file_picker_web.gd`가 이걸 부르는 얇은 껍데기다. `FilePicker` 공개 인터페이스(`create()`/`pick_files()`/`files_picked`/`pick_cancelled`/`debug_log`)와 `_finalize_pick()`, 데스크톱 구현은 전혀 안 건드렸다.
- 라이선스: `addons/FileAccessWeb/LICENSE.txt`(MIT 전문 + 원본 링크). **배포 시 이 파일을 그대로 유지해서 같이 배포할 것.**
- **알려진 제약**: 이 애드온은 **한 번에 파일 1개만** 지원한다(`<input>`에 `multiple` 속성이 없음). 그래서 웹에서 `pick_files(..., multiple=true)`를 호출해도 1개만 받고 경고 로그를 남긴다. 데스크톱은 `FileDialog`가 이미 다중 선택을 지원하므로 영향 없음 — 웹/데스크톱 동작이 이 부분만 다르다는 걸 캐릭터 편집 UI(1-6) 설계할 때 감안할 것.

### 3. GDScript `print()`가 브라우저 콘솔에 안 나옴
실제로 DevTools를 열어 확인한 결과, `html/head_include`로 심어둔 순수 HTML `<script>`의 `console.log`는 정상적으로 보이는데 Godot 엔진 자체의 시작 배너나 `JavaScriptBridge.eval()`로 찍는 로그는 전혀 안 보였다. DevTools 콘솔의 실행 컨텍스트 필터가 관련 있을 것으로 추정되지만 정확한 원인은 못 밝혔다. → **화면 로그(테스트 화면 하단의 `RichTextLabel`)를 유일하게 신뢰할 수 있는 채널로 쓴다.** `FilePicker` 기반 클래스의 `debug_log` 시그널이 각 단계(선택창 열림/로딩 시작/진행률/데이터 도착/변환 완료/에러)를 이 화면 로그에 전부 남긴다.

### 4. "지금 보는 게 새 빌드인지 옛 빌드인지" 구분이 안 됨
웹 빌드를 여러 번 다시 내보내면서 캐시된 옛날 빌드를 붙잡고 테스트하는 바람에 제자리를 맴돈 적이 있다. → 아래 "빌드 식별" 체계를 만들어서 **테스트 시작 전에 항상 먼저 확인하는 습관**으로 굳혔다.

### 5. res:// 내장 리소스를 AssetLoader/FileAccess로 읽어서 export된 빌드에서만 조용히 실패
`SfxBank`가 게임 내장 효과음(`res://assets/sfx/*.wav`)을 `AssetLoader.load_audio_from_path()`(내부적으로 `FileAccess`로 원본 바이트를 읽음)로 불러오고 있었다. 에디터에서 실행하면 원본 `.wav`가 프로젝트 폴더에 그대로 있어서 잘 됐지만, export하면 Godot 임포터가 원본을 변환된 리소스로 바꿔 pck에 넣고 **원본 바이트는 pck에 안 들어가서** `FileAccess.open()`이 조용히 실패했다(효과음이 안 남 — 에러도 안 뜸). → `load()`/`ResourceLoader.exists()`로 교체해서 해결(CLAUDE.md 원칙 3에도 반영). `CharacterPortrait`/`VoiceBank`가 내장 기본 캐릭터(`res://characters/default`)의 파일을 읽는 경로도 같은 함정이 있어서(지금은 내장 기본 캐릭터에 이미지/보이스가 없어 잠재적 버그였음) `CharacterLibrary.load_profile_texture()`/`load_profile_audio()`로 미리 고쳐뒀다 — 나중에 내장 기본 캐릭터에 실루엣 이미지 등을 추가할 때 또 겪지 않도록.
- **교훈**: `res://` 안의 게임 내장 이미지/오디오는 반드시 `load()`/`preload()`로 읽는다. `AssetLoader`(바이트 기반)는 `user://`의 사용자 업로드 파일 전용이다. 이 버그는 **에디터 실행으로는 재현이 안 되고 실제 export된 빌드에서만** 나타나므로, 리소스 로딩 관련 변경은 반드시 export한 빌드로 확인할 것.

## 빌드 식별 (addons/build_stamp)

`addons/build_stamp`는 export가 시작될 때(`_export_begin`) `res://build_info.gd`의 `BUILD_TIME` 상수를 현재 시각으로 자동으로 고쳐 쓰는 EditorExportPlugin이다. 에디터 GUI로 내보내든 `godot --headless --export-release ...`로 내보내든 똑같이 동작한다 — 사람이 매번 손으로 시각을 갱신할 필요가 없다.

`BuildInfo`(autoload, `res://build_info.gd`)는 게임이 시작되면:
- 콘솔에 `[YachtDice] 빌드: <시각>`을 `print()`로 찍는다(단, 위 3번 문제로 브라우저 콘솔에선 안 보일 수 있음).
- 웹에서는 `JavaScriptBridge.eval()`로 브라우저 페이지 좌상단에 고정된 배너(`#yd-build-banner`)를 만들어 `빌드: <시각> (엔진 시작됨)`을 표시한다.

여기에 더해 `export_presets.cfg`의 `html/head_include`에 **엔진이 뜨기 전에** 실행되는 순수 JS를 심어뒀다 — 페이지가 로드되자마자 같은 배너 자리에 `HTML 셸 로드됨 - 엔진 시작 대기 중...`을 먼저 찍는다. 그래서 배너 문구가:
- **"HTML 셸 로드됨..."에서 안 바뀜** → 브라우저는 페이지를 열었지만 Godot 엔진(wasm)이 못 떴다는 뜻. 서버 MIME 타입, 파일 누락, 브라우저 호환성 등을 의심할 것.
- **"빌드: ... (엔진 시작됨)"으로 바뀜** → 엔진이 정상적으로 부팅해서 `BuildInfo` 스크립트까지 실행됐다는 뜻. 이때 시각이 방금 export한 시각과 같은지만 보면 새 빌드인지 옛 빌드(캐시)인지 바로 구분된다.

**개발자 도구를 아예 안 열어도** 브라우저 화면만 보고 판단 가능하다는 게 핵심이다.

`build_info.gd`는 export할 때마다 자동으로 덮어써지는 파일이라, git에는 마지막으로 export한 시각이 커밋될 수 있다 — 신경 쓰지 않아도 된다(직접 값을 고쳐봐야 다음 export에서 사라진다).

## 확인 체크리스트

- 페이지 좌상단 배너가 방금 export한 시각으로 뜨는가.
- 파일 선택창이 뜨는가(웹은 한 번에 1개만 — 위 "알려진 제약" 참고).
- 취소 시 화면 로그에 "취소됨"만 남고 에러가 없는가.
- 허용 안 한 확장자를 억지로 골라도 걸러지는가.
- 이미지 미리보기와 오디오 재생이 실제로 되는가.

## 빌드 용량 참고

릴리스 빌드(Thread Support 끔) 기준 `index.wasm` 39.5MB + `index.pck` ~2.55MB(폰트 포함 게임 리소스) + 나머지(js/아이콘) ~0.3MB = 총 약 41MB. 96%가 Godot 엔진 wasm 자체라 리소스(폰트 등)가 차지하는 비중은 크지 않다. 용량 최적화는 필요해지면 별도로 다룬다.
