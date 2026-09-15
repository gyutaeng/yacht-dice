## 프로젝트

Godot 4.7 / GDScript로 만드는 요트다이스 보드게임. 플레이어가 직접 올린 PNG 스탠딩 일러스트와 WAV 보이스로 캐릭터를 커스텀하는 것이 핵심 기능. 추후 리치마작으로 확장 예정.

## 반드시 지킬 아키텍처 원칙

1. 웹(HTML5) export를 반드시 지원한다. 데스크톱 전용 API를 쓰기 전에 웹에서 동작하는지 먼저 확인할 것.
2. 게임 규칙 로직(GameState)은 UI 노드를 절대 참조하지 않는다. 단방향: GameState -> 시그널 -> UI.
3. 런타임 에셋 로딩은 파일 경로가 아니라 PackedByteArray를 기준으로 짠다. 경로를 받는 함수는 바이트 함수를 부르는 얇은 래퍼일 뿐이다.
4. 주사위 난수는 randi()를 직접 부르지 않고 주입받은 RandomNumberGenerator를 쓴다. 멀티플레이에서 서버가 권한을 갖기 위한 준비다.
5. 게임 이벤트는 GameEvents autoload 싱글톤의 시그널로만 주고받는다. 방출자는 구독자를 몰라야 한다.
6. 외부에서 들어온 파일(사용자 업로드, 네트워크 수신)은 신뢰하지 않는다. 확장자 화이트리스트와 크기 상한을 반드시 검사한다.
7. GameEvents의 score_previewed는 UI 갱신 전용이다. 한 번 굴릴 때마다 미확정 항목 수만큼 방출되므로, 캐릭터 보이스 트리거로는 절대 쓰지 않는다.
8. 테스트는 반드시 씬으로 실행한다(godot --headless res://...tscn). --script 방식은 오토로드를 등록하지 않아 GameEvents 참조 코드가 컴파일되지 않는다.

## 코드 스타일

- 응답은 한국어로.
- 주석은 "왜"를 적는다. "무엇"은 코드가 이미 말한다.
- 파일을 여러 개 고치는 작업은 구현 전에 계획을 먼저 보여주고 확인을 받는다.

## 현재 어긋나 있는 부분

`scenes/Main.gd`(현재 유일한 스크립트)를 기준으로 확인한 목록. 아직 고치지 않았다.

- **원칙 2 위반 (GameState/UI 미분리)**: `Main.gd` 하나가 주사위 값·리롤 횟수·플레이어별 확정 점수 같은 게임 상태와, `Label`/`Button` 노드 조작을 모두 함께 가지고 있다. 예를 들어 `_roll_dice()`(117~123행)는 `dice_results` 배열을 갱신하면서 동시에 `dice_labels[i].text`를 직접 쓰고, `_on_confirm_pressed()`(173~190행)도 `player_confirmed_scores`를 갱신하면서 `score_labels[index].text`와 `confirm_buttons[index].disabled`를 같은 함수 안에서 직접 건드린다. GameState 역할과 UI 역할이 분리된 별도 노드/클래스가 없고, 시그널을 거치지 않고 서로 직접 참조한다.
- **원칙 4 위반 (RNG 미주입)**: `_roll_dice()`(121행)에서 전역 함수 `randi_range(1, 6)`을 직접 호출한다. 주입받은 `RandomNumberGenerator` 인스턴스가 어디에도 없다.
- **원칙 5 위반 (GameEvents 싱글톤 부재)**: 프로젝트에 autoload 싱글톤 자체가 하나도 없다(`project.godot`에 `[autoload]` 섹션 없음). 버튼 클릭은 `Main.gd` 내부 핸들러에 바로 연결되어 있고(예: 55~56행, 166행), 턴 전환·점수 갱신도 전부 `Main.gd`가 자기 자신의 함수를 직접 호출하는 방식(`_switch_to_player()`, `_update_score_previews()` 등)이라 방출자/구독자 구분이 없다.
- **원칙 1 관련 미검증 사항**: `project.godot`에 `3d/physics_engine="Jolt Physics"`가 설정되어 있지만, 프로젝트 전체에 `Node3D` 계열 노드가 하나도 없어(주사위도 2D `Label`) 실제로 3D 물리를 쓰지 않는 죽은 설정이다 — 그래서 Jolt가 HTML5에서 되는지 자체가 지금은 의미 없는 질문이다. HTML5 export 프리셋은 1-5B(폰트) 작업 때 만들어서 저장소에 커밋되어 있다(`export_presets.cfg`).
- **원칙 3·6은 현재 해당 사항 없음**: 파일 업로드/에셋 로딩 기능 자체가 아직 구현되지 않아 위반 여부를 판단할 코드가 없다. 해당 기능을 만들 때부터 원칙 3(PackedByteArray 기준)·6(화이트리스트/크기 검사)을 지켜야 한다.

## 현재 진행 상황

*큰 작업이 끝날 때마다 이 섹션을 갱신한다. 새 세션에서 이어갈 때는 여기부터 읽는다.*

### 완료한 단계
- 0-1, 0-2: GameState/UI 분리, RNG 주입
- 0-3: GameEvents 이벤트 버스 도입
- 상단 보너스 규칙(63점 이상 +35점)
- 0-4: 족보 회귀 테스트 + 통합 테스트 러너(scripts/tests/)
- 0.5-1: GameState 2~4인 확장
- 0.5-2: UI 레이아웃 재구성, 종료 오버레이, 점수 확정 2단계
- 0.5-3: 다인수 테스트 + 1-1 캐릭터 데이터 모델(CharacterProfile/CharacterLibrary)
- 1-2: 바이트 기반 에셋 로더(AssetLoader) — 포맷 확장, 매직바이트 검사, LRU 캐시
- 1-3: 캐릭터 스테이지 — 초상 크로스페이드, 실루엣 폴백
- 1-3B: 턴 시작 시 자동 굴리기 제거(수동 굴리기로 변경), 작은/큰 초상 파일 분리(thumbnail_file)
- 1-3C: 특수 족보(야추 등) 연출 — 팝업 라벨, 입력 차단
- 1-4: VoiceBank(캐릭터 보이스 재생) 도입
- 1-4B: 보이스 이벤트 테이블 10개로 확정, game_started 시그널 추가, SfxBank(게임 내장 효과음) 도입, 디버그 단축키를 Ctrl+Shift 조합으로 전환(F8/F9/F10이 Godot 에디터 자체 단축키와 충돌해서)
- 1-5: FilePicker(데스크톱/웹 파일 선택 추상화)
- 웹 빌드 한글 깨짐(네모) 수정: Pretendard(OFL-1.1) 폰트를 프로젝트 기본 폰트로 지정, `bold_font`를 합성 볼드에서 실제 Bold 파일로 교체. 데스크톱 windowed 실행과 실제 web export 양쪽에서 한글 렌더링 확인 완료.
- 웹에서 파일 선택 후 아무 반응 없던 버그 수정 + 빌드 식별/진단 체계 도입(아래 참고). 웹 export 관련 세부 절차는 전부 `docs/web_export.md`로 옮겼다.

### 한글 폰트(Pretendard) 관련 참고
- 파일: `assets/fonts/Pretendard-Regular.otf`, `Pretendard-Bold.otf`, `LICENSE.txt`(SIL OFL 1.1 원문 — 배포 시 저작권 표기에 씀). Pretendard 1.3.9, npm 패키지의 정적 otf 빌드(jsdelivr CDN에서 받음). OFL이라 상업적 재배포·번들 전부 허용.
- 적용 위치: `project.godot`의 `[gui] theme/custom_font="res://assets/fonts/Pretendard-Regular.otf"` — 프로젝트 전체 기본 폰트라 개별 라벨에 지정할 필요 없음.
- Bold가 실제로 필요한 곳은 확정된 점수 라벨(`Main.gd`의 `_refresh_scoreboard_ui`, `bold_font` 사용) 한 곳뿐이었다. `bold_font`는 원래 `ThemeDB.fallback_font`에 `variation_embolden`을 걸어 합성한 가짜 볼드였는데(한글 폰트가 없던 시절의 임시방편), 이제 `Pretendard-Bold.otf`를 직접 로드하도록 바꿨다(`Main.gd`의 `BOLD_FONT_PATH` 상수). 특수 족보 연출 라벨(`special_hand_label`)은 font_size만 키운 것이라 애초에 볼드가 아니었다.

### 1-5(파일 선택) 상태
- 데스크톱 구현은 검증 완료: FileDialog로 실제 파일(placeholder_portrait.png)을 골라 백그라운드 스레드 읽기 → `_finalize_pick` → `AssetLoader.load_texture_from_bytes()` 디코딩 성공까지 `file_picker_test.tscn`에서 실제로 확인했다(로그: "이미지 디코딩 성공: ... (1.8 MB)").
- **웹에서 "선택창은 뜨는데 고른 뒤 아무 일도 안 일어나는" 버그를 찾아 고쳤다.** 원인은 `FilePickerWeb.pick_files()`에서 `JavaScriptBridge.create_callback()`이 돌려주는 `JavaScriptObject`를 지역 변수/임시값으로만 넘기고 아무 데도 저장하지 않은 것이었다 — GDScript 쪽에서 참조를 안 들고 있으니 GC되고, JS의 `window[콜백이름]`은 죽은 참조가 되어 `change`/`FileReader.onload`가 와도 Godot으로 돌아오지 못했다. `_select_callback`/`_file_callback`/`_error_callback`/`_cancel_callback` 멤버 변수에 담아 살려두도록 고쳤다.
- 겸사겸사 고친 것: ①`_on_js_file_data`에서 `is_js_buffer` 검사에 실패하면 카운트를 안 올리고 그냥 리턴해서 전체 선택이 영원히 멈추던 버그(실패도 카운트에 포함시키도록 수정) ②`FileReader.onerror` 핸들러가 아예 없어서 읽기 실패 시 조용히 멈추던 부분(에러 콜백 추가) ③`change` 이벤트 시점에 파일 개수/이름을 Godot에 바로 알리는 체크포인트(`_on_js_selected`) 추가.
- 로그를 촘촘하게 넣었다: `FilePicker` 기반 클래스에 `debug_log` 시그널을 추가해 선택창 열림/change 수신/FileReader 완료/PackedByteArray 변환/files_picked 방출 직전 등 각 단계를 `print()`(브라우저 콘솔로 감)와 화면 로그(`file_picker_test.gd`가 `debug_log`를 구독해 `[이미지]`/`[오디오]` 접두사로 찍음) 양쪽에 남긴다. 주입한 JS 안에도 각 단계 `console.log`/`console.error`를 넣어서, 혹시 Godot 콜백이 또 안 불려도 브라우저 콘솔만으로 어디까지 갔는지 알 수 있다.
- **콜백 GC 수정 후에도 여전히 웹에서 막힘 — 파일 선택창은 뜨지만 고른 뒤/취소해도 `_on_js_selected`조차 안 찍히는 증상이 나왔다(2라운드).** 코드 재확인 결과 `FilePickerWeb` 인스턴스 자체는 `file_picker_test.gd`가 멤버 변수 + `add_child()`로 이미 정상 보관 중이었고, `<input>`도 이미 `document.body.appendChild()`로 붙어 있었다 — 그 두 가지는 원인이 아니었다. 대신 진단력을 더 끌어올렸다: ①`change`/`onFocus`/네이티브 `cancel` 이벤트 핸들러 본문 전체를 각각 try/catch로 감싸고, 예외가 나면 `__godot_file_picker_jserror_N` 콜백으로 Godot에 보고 + `console.error`도 남기게 함(IIFE 바깥만 감싸면 나중에 비동기로 실행되는 이 핸들러들 안에서 던져진 예외는 못 잡음) ②`change` 핸들러 맨 첫 줄에 무조건 `console.log`를 넣어 "JS까지는 왔는데 Godot 콜백만 실패"와 "JS 이벤트 자체가 안 옴"을 구분 가능하게 함 ③최신 Chrome(113+) 등이 지원하는 네이티브 `input` `cancel` 이벤트 리스너를 추가 — 이 이벤트를 지원하는 브라우저는 `change`가 아예 안 오고 이걸로만 취소가 감지되므로, 안 듣고 있으면 "취소해도 로그가 없음" 증상과 정확히 들어맞는다.
- **이 라운드의 수정이 실제 브라우저에서 되는지, 그리고 새로 추가한 JS 에러 콜백/네이티브 cancel 로그에 뭐가 찍히는지는 아직 확인 못 함 — 사용자가 이번엔 브라우저 콘솔까지 같이 확인하기로 함.**

### 빌드 식별 / 웹 진단 (addons/build_stamp, BuildInfo)
- "지금 뜬 게 새 빌드인지 옛 빌드인지 구분이 안 된다"는 문제 때문에 만들었다. `addons/build_stamp`(EditorExportPlugin)가 export 시작 시점마다 `res://build_info.gd`의 `BUILD_TIME`을 자동으로 현재 시각으로 고쳐 쓴다 — 에디터 GUI export든 CLI export든 동일하게 동작(헤드리스 CLI export로 직접 검증 완료: "BuildStamp: 빌드 시각을 2026-09-15 18:11로 찍음" 로그 확인).
- `BuildInfo` autoload가 게임 시작 시 콘솔에 `[YachtDice] 빌드: <시각>`을 찍고, 웹에서는 브라우저 페이지 좌상단에 고정 배너를 띄운다.
- `export_presets.cfg`의 `html/head_include`에 엔진이 뜨기도 전에 실행되는 순수 JS를 심어서, 페이지 로드 직후엔 같은 배너 자리에 "HTML 셸 로드됨..."을 먼저 찍는다. 그래서 배너가 그 문구에서 "빌드: ... (엔진 시작됨)"으로 안 바뀌면 엔진(wasm) 자체가 못 뜬 것이고, 바뀌면 그 시각이 방금 export한 시각과 같은지만 보면 캐시 문제인지 바로 구분된다. **개발자 도구를 안 열어도** 화면만으로 판단 가능하게 만든 것이 핵심 — 실제로 새로 export한 빌드를 브라우저에서 열어 배너가 "빌드: 2026-09-15 18:11 (엔진 시작됨)"으로 정상 갱신되는 것까지 이 세션에서 직접 확인했다.
- 자세한 내용과 export 절차 전체는 `docs/web_export.md` 참고.

### 웹 export 폴더 위치 변경
- `export_path`를 프로젝트 안(`build/web/`)에서 **프로젝트 바깥 `F:/Godot/web_build/`**로 옮겼다. 프로젝트 안에 두면 Godot 에디터가 export된 PNG를 리소스로 다시 임포트해서 `.import` 파일을 만들고, 그게 다음 export의 pck에 또 들어가는 악순환이 있었다(실제로 `build/web/index.png.import` 등이 생겨 있던 것을 발견하고 정리함). `.gitignore`의 `build/` 항목은 더 이상 필요 없어 제거했다.
- `export_presets.cfg`는 계속 저장소에 커밋 대상이다(민감한 값이 없는 동안은 — 안드로이드 키스토어 등이 생기면 그때 다시 논의).

### 현재 전체 테스트 개수
373개 (`scripts/tests/test_runner.tscn`, 전부 통과).

### 디버그 단축키 (`scripts/dev/debug_hotkeys.gd`, 에디터에서만 동작)
- Ctrl+Shift+1 : 야추로 강제 지정
- Ctrl+Shift+2 : 라지 스트레이트로 강제 지정
- Ctrl+Shift+3 : 풀 하우스로 강제 지정
- Ctrl+Shift+4 : 포카드로 강제 지정
- Ctrl+Shift+S : 현재 플레이어의 빈 칸 하나 자동 확정
- Ctrl+Shift+A : 게임이 끝날 때까지 자동 진행
(텍스트 입력 위젯에 포커스가 있으면 전부 무시된다.)

### 남은 단계
- 1-6: 캐릭터 편집 UI(이름/초상/보이스 업로드 — 여기서 FilePicker와 VoiceBank를 실제로 연결한다)
- 1-7: 캐릭터 팩(내보내기/불러오기)
- 1-8: 웹 빌드 최종 검증
- Phase 2: 온라인 멀티플레이
