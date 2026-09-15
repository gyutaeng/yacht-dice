## 프로젝트

Godot 4.7 / GDScript로 만드는 요트다이스 보드게임. 플레이어가 직접 올린 PNG 스탠딩 일러스트와 WAV 보이스로 캐릭터를 커스텀하는 것이 핵심 기능. 추후 리치마작으로 확장 예정.

## 반드시 지킬 아키텍처 원칙

1. 웹(HTML5) export를 반드시 지원한다. 데스크톱 전용 API를 쓰기 전에 웹에서 동작하는지 먼저 확인할 것.
2. 게임 규칙 로직(GameState)은 UI 노드를 절대 참조하지 않는다. 단방향: GameState -> 시그널 -> UI.
3. 런타임 에셋 로딩은 파일 경로가 아니라 PackedByteArray를 기준으로 짠다. 경로를 받는 함수는 바이트 함수를 부르는 얇은 래퍼일 뿐이다. **단, 이건 user:// (사용자 업로드, 임포트 안 거침) 전용이다. res:// 안의 게임 내장 리소스는 반드시 load()/preload()로 읽는다 — export 시 원본이 임포트된 리소스로 바뀌어 pck에 들어가고 원본 바이트는 안 들어가므로, AssetLoader/FileAccess로 res:// 원본을 읽으려 하면 에디터에서만 되고 export된 빌드에서는 조용히 실패한다(SfxBank가 실제로 겪음).**
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
- 1-5: FilePicker(데스크톱/웹 파일 선택 추상화) — **완료. 데스크톱·웹 양쪽 실제 브라우저/앱에서 검증됨.**
- 1-6: 캐릭터 편집 UI(CharacterEditor) + 게임 시작 전 캐릭터 선택 화면 — **완료. 데스크톱·웹 양쪽에서 전체 흐름 실제 확인(특수 족보 연출 포함).**

### 1-5(파일 선택) 완료 요약
- 데스크톱: `FilePickerDesktop`(Godot `FileDialog` + 백그라운드 스레드 읽기)으로 검증 완료.
- 웹: 자체 JS 브릿지(JavaScriptBridge.create_callback)로 여러 번 시도했지만 "선택창은 뜨는데 콜백이 Godot으로 안 돌아옴" 문제를 못 잡아서(콜백 GC 수정, try/catch, 네이티브 cancel 이벤트 등 다 시도했지만 실패), 검증된 애드온 [`godot-file-access-web`](https://github.com/Scrawach/godot-file-access-web)(Scrawach, MIT License)로 교체해서 해결했다. `addons/FileAccessWeb/core/file_access_web.gd`에 수정 없이 벤더링, `scripts/io/file_picker_web.gd`는 이를 부르는 얇은 껍데기. **사용자가 실제 브라우저에서 파일 선택 정상 동작 확인함.**
- `FilePicker` 공개 인터페이스(`create()`/`pick_files()`/`files_picked`/`pick_cancelled`/`debug_log`)와 `_finalize_pick()`, 데스크톱 구현은 이 과정에서 전혀 안 바뀜.
- **알려진 제약**: 웹에서는 한 번에 파일 1개만 선택 가능(애드온 자체 한계). 데스크톱은 다중 선택 그대로 지원. 1-6 UI 설계 시 감안할 것.
- 웹 export 관련 문제(한글 폰트 깨짐, 빌드 캐시 구분, 콘솔 로그 안 보임 등)와 해결·절차는 전부 `docs/web_export.md`에 정리했다 — 다음에 웹 export를 다시 만질 때는 여기부터 읽을 것.
- 부수적으로 만든 것: `addons/build_stamp`(export할 때마다 빌드 시각 자동 기록) + `BuildInfo` autoload(게임 시작 시 콘솔/브라우저 배너에 빌드 시각 표시) — 자세한 내용은 `docs/web_export.md`.
- Pretendard 폰트(OFL-1.1, `assets/fonts/`)를 프로젝트 기본 폰트로 지정해서 한글 렌더링 문제도 이때 같이 해결(데스크톱·웹 둘 다 확인 완료).

### user:// 웹 영구 저장 검증 (1-6 준비) — 완료, 통과
1-6에서 캐릭터를 `user://`에 저장할 예정이라, 웹에서 `user://`가 새로고침 후에도 실제로 유지되는지(Godot 웹은 IndexedDB 기반 영구 저장소를 씀) `file_picker_test.tscn`에 검증 UI를 추가해서 확인했다: `[저장 테스트]`/`[불러오기 테스트]` 버튼, 화면이 뜰 때 자동으로 한 번 읽어서 이전 값이 있으면 보여줌. **사용자가 브라우저에서 저장 → 새로고침 → 자동 확인 로그에 값이 그대로 남아있는 것까지 확인함.** → 웹에서 캐릭터를 만들고 저장하는 전체 경로가 살아있다는 뜻이라 1-6이 웹에서도 의미 있게 동작한다는 게 보장됐다.

**미확인 사항**: 시크릿(프라이빗) 모드에서의 동작은 아직 안 봤다 — 브라우저에 따라 시크릿 모드는 IndexedDB를 세션이 끝나면 지우거나 아예 막을 수 있어서, 정상 모드와 다를 수 있다. **1-8(웹 빌드 최종 검증)에서 확인할 것.**

### 웹 재검증이 다시 필요해지면
`project.godot`의 `run/main_scene`을 `res://scenes/dev/file_picker_test.tscn`으로 잠시 바꿔서 export하면 된다(자세한 절차는 `docs/web_export.md`) — 테스트 끝나면 반드시 `res://scenes/Main.tscn`으로 되돌릴 것.

### 1-6(캐릭터 편집 UI) 완료 요약
- **`scenes/character_editor/character_editor.tscn`**: 3단 레이아웃(좌 목록/중앙 이미지+이름+볼륨/우 보이스 매핑). `character_editor.gd`가 오케스트레이터로 "지금 편집 중인 프로필"과 dirty 플래그만 들고 있고, 3개 패널(`character_list_panel.gd`/`image_editor_panel.gd`/`voice_mapping_panel.gd`)은 상태를 모른 채 emit/받기만 한다. Main.tscn이 아니라 별도 씬으로 만들어서 Main.gd가 `[캐릭터 관리]` 버튼을 누르면 `instantiate()`해서 오버레이로 띄우고 닫으면 `queue_free()`한다.
- **저장 모델(대화 중 사용자가 직접 고친 부분)**: 이미지/보이스 파일은 고르는 즉시 `CharacterLibrary.save_asset_bytes()`로 디스크에 쓰지만(미리보기도 즉시 갱신), `[제거]`는 profile 필드만 지우고 실제 파일 삭제는 안 한다. `[저장]` = `manifest.json` 갱신 + **그 manifest가 안 가리키는 파일을 전부 정리**(`CharacterLibrary.save_profile()` 안에 통합, 별도의 "삭제 예정" 상태 없음). 저장 실패 시 아무것도 안 지워진다. 이미지를 여러 번 바꿔보고 저장 안 하고 나가도 고아 파일이 안 쌓인다(1-7 캐릭터 팩 zip에 안 딸려 들어가고 2-5의 20MB 전송 상한도 안 갉아먹음).
- **보이스 매핑**: `GameEvents.VOICE_EVENTS` 테이블을 그대로 읽어 10행을 자동 생성(하드코딩 없음 - 테이블에 항목이 늘면 화면도 저절로 늘어남). 테이블에 `"frequency": "once"/"frequent"` 필드를 추가해서 "한 판에 한 번"(게임 시작/승리/패배/보너스/야추 포기)과 "자주 반복"(내 차례/야추/라지 스트레이트/풀 하우스/포카드)을 시각적으로 구분한다. 보이스가 없는 이벤트는 흐리게. 볼륨 슬라이더(`profile.volume_db`)를 조절하면 재생 중인 미리듣기에 바로 반영됨.
- **FilePicker는 패널당 1개만 공유**(이미지 패널 1개, 보이스 패널 1개) — "지금 어느 슬롯/이벤트를 위해 열었는지"만 기억하고, 선택 진행 중엔 그 패널의 다른 추가 버튼을 비활성화해서 웹의 비동기 콜백이 꼬이지 않게 함.
- **알려진 제약**: 웹에서는 이미지/보이스 모두 한 번에 1개만 선택됨(1-5의 FileAccessWeb 애드온 한계, 그대로 이어받음).
- **공유 유틸 2개를 새로 뽑음**: `scripts/ui/texture_fit.gd`(TextureRect 비율 유지 배치, contain/cover), `scripts/characters/character_portrait.gd`(프로필의 어느 파일을 읽을지 + 실루엣 폴백 결정) — 원래 `Main.gd`에 있던 로직을 그대로 옮긴 것이라 게임 화면 동작은 안 바뀌었고, 캐릭터 선택 화면도 같은 로직을 재사용한다.
- **게임 시작 전 캐릭터 선택**(`scenes/character_select_panel.gd`, `Main.tscn`의 `CharacterSelectScreen`): 인원수 버튼을 누르면 그 인원수만큼 슬롯이 생기고, 슬롯마다 ◀▶로 `CharacterLibrary.get_selectable_profiles()`(내장 기본 포함)를 순환하며 "N / M" 위치 표시. 기본값은 예전 임시 코드와 같은 라운드로빈이라 아무것도 안 건드려도 합리적으로 채워진다. 여러 플레이어가 같은 캐릭터를 골라도 제한 없음(실제로 확인함). `Main.gd`의 `TODO(1-6)` 임시 배정 함수(`_assign_player_characters`)는 삭제했다. "다시 하기"는 새로 고르지 않고 직전 선택을 재사용한다.
- **`scripts/dev/character_seed.gd` 삭제**: 자기 자신의 주석에 "1-6에서 진짜 캐릭터 생성 UI가 생기면 통째로 지운다"고 적혀 있던 개발용 임시 스크립트라 이번에 지웠다(Main.tscn의 참조도 같이 제거). 기존에 이 스크립트가 만들어둔 테스트 캐릭터(테스트A/테스트B/가로이미지)는 `user://characters/`에 그대로 남아있고 정상적인 사용자 캐릭터로 취급된다.
- 새 유닛 테스트 6개(`scripts/tests/suites/test_character_library.gd`) 추가 — `save_asset_bytes()`의 이름 충돌 처리, `save_profile()`의 고아 파일 정리(빈 `voices/` 폴더 정리 포함)를 검증.
- 데스크톱에서 windowed 실행으로 전체 흐름(목록 선택/새로 만들기/이미지 업로드→미리보기/볼륨 슬라이더→미리듣기 실시간 반영/저장→manifest 반영/삭제/저장 안 한 변경사항 확인 다이얼로그/게임 시작 전 캐릭터 선택→같은 캐릭터 중복 배정→실제 게임 화면 반영)을 직접 확인 완료.

### 1-6 이후 버그 수정 (화면 전환 정리, 웹 게임 시작 안 되던 문제)
- **버그 1(캐릭터 편집 화면 뒤로 시작 화면이 비쳐 보임, 데스크톱·웹 둘 다)**: 원인 두 가지 다 있었다 — ①오버레이를 띄우면서 시작 화면을 안 숨김 ②편집 화면 루트에 불투명 배경이 없음. 둘 다 고침: `_on_manage_characters_pressed()`가 열 때 `start_screen.visible = false`로 확실히 숨기고 닫힐 때 되돌리며, `character_editor.tscn` 루트에 화면 전체를 덮는 `ColorRect`(불투명, `mouse_filter=STOP`)를 깔았다. **데스크톱에서 스크린샷으로 수정 확인함.**
- **화면 전환을 `_show_screen(Screen)` 함수 하나로 통일**: `Main.gd`에 `enum Screen { START, CHARACTER_SELECT, GAME }`을 두고, 이 셋 중 지금 보여야 할 화면만 `visible=true`, 나머지는 전부 `visible=false`가 되도록 한 함수로 묶었다. 예전엔 버튼 핸들러마다 개별적으로 `.visible`을 켜고 꺼서 하나를 빠뜨리기 쉬운 구조였다. `GameOverOverlay`는 GAME 위에 뜨는 모달이라 이 enum에는 안 넣고 그대로 별도 관리.
- **버그 2(웹에서 게임 시작 후 진행 불가 — 데스크톱은 정상)**: 사용자가 준 증상(주사위가 "?" 대신 씬 기본값 표시, 점수판 없음, 초상화 없음, 버튼 무반응)은 초기화 함수가 중간에 멈췄을 때의 모습과 정확히 일치했다. 유력 원인은 "사용자 캐릭터가 0개라 내장 기본 캐릭터(이미지 전혀 없음)만 배정되는 경로"였다 - 데스크톱은 이전 세션에서 만든 테스트 캐릭터가 항상 남아있어서 이 경로를 한 번도 안 타봤을 수 있다는 게 사용자의 추론이었다.
  - 사용자가 제안한 방법대로 **데스크톱에서 `user://characters/`를 통째로 비우고 재현을 시도했지만 재현되지 않았다** — 빈 사용자 캐릭터 + 내장 기본 캐릭터만 있는 조건에서도 데스크톱은 정상 동작했다(스크린샷 확인). `_build_character_area()`/`_build_scoreboard()`/`CharacterPortrait`/`TextureFit`을 처음부터 끝까지 코드로도 다시 훑었지만 이 조건에서 죽을 만한 null/빈 배열 접근을 못 찾았다.
  - 버그 1의 두 수정(화면 전환 통일 + 편집 화면 불투명 배경)을 적용한 뒤 **실제로 웹 export해서 브라우저에서 직접 재생해봤다**: 화면 구석 진단 로그에 "캐릭터 배정 완료 → 보이스뱅크 설정 완료 → 초상화 영역 생성 완료 → 점수판 생성 완료 → 시그널 연결 완료 → 첫 턴 시작 완료"가 전부 순서대로 찍혔고, 점수판·초상화·주사위 굴리기·점수 확정까지 전부 정상 동작했다. **정확한 원래 원인(왜 데스크톱에서 재현이 안 됐는지)은 못 짚었지만, 수정 후 웹에서 실제로 끝까지 도는 것까지 확인함.**
  - **사용자가 브라우저에서 직접 최종 확인할 것.**
- **회귀 테스트 추가**: `scripts/tests/suites/test_game_start_builtin_only.gd` — 내장 기본 캐릭터(이미지 없음)만으로 `Main.tscn`을 실제로 `add_child`해서 `_start_new_game()`을 끝까지 돌려보고 점수판/초상화 영역/게임 상태가 전부 만들어지는지 검증한다. `Engine.get_main_loop().root`가 아직 자식 설정 중일 수 있어서 프레임을 기다려야 했고, 그래서 `test_runner.gd`의 스위트 실행 루프에 `await`를 추가했다(기존 스위트는 전부 동기라 영향 없음).
- **TEMP 진단 로그(`Main.tscn`의 `DebugInitLog` 노드, `Main.gd`의 `_debug_init_log()`)**: 게임 시작 초기화 단계마다 화면 좌상단에 한 줄씩 찍는다. **사용자가 웹에서 최종 확인 끝나면 제거 요청할 것 — 아직 지우지 않았다.**

### 1-6 이후 버그 수정 2라운드 (res:// 내장 리소스를 AssetLoader로 읽던 문제)
- **에디터의 "브라우저에서 실행"은 쓰지 않는다.** 임시 폴더에 디버그 빌드를 내보내는 별도 경로라 실제 export 설정과 다르게 동작한다(게임 진행 자체가 막힘 - 정식 export로는 정상). 원인은 안 파고들기로 했다. **웹 테스트는 항상 export → `F:/Godot/web_build` → `python -m http.server` 경로만 쓴다.** `docs/web_export.md`에 굵게 명시함.
- **`SfxBank`가 게임 내장 효과음을 못 읽던 버그**: `res://assets/sfx/*.wav`를 `AssetLoader.load_audio_from_path()`(내부적으로 원본 바이트를 `FileAccess`로 읽음)로 불러오고 있었다. res:// 안의 오디오/이미지는 export 시 Godot 임포터가 변환한 리소스로 pck에 들어가고 **원본 바이트는 pck에 안 들어가서**, 에디터 실행(원본이 프로젝트 폴더에 그대로 있음)에서는 되고 export된 빌드에서는 조용히 실패했다(에러도 안 뜨고 그냥 소리가 안 남) — **에디터 실행으로는 재현이 안 되고 실제 export에서만 나타나는 버그**였다. `load()`/`ResourceLoader.exists()`로 교체해서 해결.
- **같은 함정이 있던 곳 추가로 발견해서 미리 고침**: `CharacterPortrait`/`VoiceBank`가 내장 기본 캐릭터(`res://characters/default`)의 파일을 읽을 때도 `is_builtin`이면 `AssetLoader`를 쓰고 있었다 — 지금은 내장 기본 캐릭터에 이미지/보이스가 아예 없어서 잠재적(latent) 버그였지만, 나중에 실루엣 이미지 등을 res://characters/default/에 넣는 순간 똑같이 터졌을 것. `CharacterLibrary`에 `load_profile_texture()`/`load_profile_audio()`를 새로 만들어 "내장(res://)이면 load(), 사용자(user://)면 AssetLoader"를 한 곳에서 분기하도록 정리하고, 이 두 곳과 `voice_mapping_panel.gd`의 미리듣기까지 전부 이걸 쓰도록 바꿨다.
- **원칙 3에 한 줄 추가**: PackedByteArray 기반 로딩은 user:// 전용이고, res:// 내장 리소스는 반드시 load()/preload()로 읽는다는 구분을 명시했다.
- **검증 방법**: 임시로 Windows 데스크톱 export 프리셋을 만들어 실제로 export한 뒤(export하면 원본이 아니라 pck 안의 임포트된 리소스만 남으므로 웹과 같은 조건을 훨씬 빠르게 재현 가능) standalone .exe를 직접 실행해서 콘솔에 4개 효과음이 전부 `true`로 로딩되는 것을 확인했다. 검증용 프리셋/코드는 확인 후 전부 제거함(저장소에 안 남음).

### 1-6 이후 버그 수정 3라운드 (특수 족보 연출 - 웹 미확인 상태로 남음)
- **증상**: export한 웹 빌드에서 특수 족보(야추 등) 문장 연출이 안 뜬다는 보고. 데스크톱은 정상. 효과음(SfxBank)과 문장 연출(`Main.gd`)이 `GameEvents.special_hand_rolled`를 각각 독립적으로 구독하는 구조는 맞다(하나가 안 되면 둘 다 안 되는 게 아니라 따로 문제 날 수 있는 구조 - 의도한 설계).
- **진단 로그 추가(TEMP, 아직 안 뺌)**: `_play_special_hand_effect()` 시작 시 `special_hand_label`의 `visible`/`size`/`get_global_rect()`를 찍고, 페이드인 끝(`modulate.a`)과 연출 종료 시점도 찍는다. 기존 `_debug_init_log()`(화면 좌상단 로그)를 그대로 재사용했다.
- **실제로 export한 웹 빌드를 서빙해서 확인**했다(에디터의 "브라우저에서 실행"은 안 씀). 임시로 `debug_hotkeys.gd`의 에디터 전용 guard를 잠깐 풀어서 Ctrl+Shift+1로 야추를 강제 지정해가며 테스트했고(확인 후 원래대로 되돌림, 저장소에 안 남음), 진단 로그에 `rect=(1.0, 42.0)`, `modulate.a=1.0`, "연출 종료"까지 전부 정상적으로 찍히는 걸 확인했다 — **데스크톱에서 찍히는 값과 완전히 동일**했다. 다만 애니메이션 지속 시간이 짧고(페이드 0.15초+유지 1.2초) 자동화로 정확한 순간에 스크린샷을 못 잡아서, 화면에 실제로 그려지는 걸 눈으로 직접 보지는 못했다.
- **결론을 못 냈다.** 진단값이 데스크톱과 동일해서 로직상 문제를 못 찾았고, 그렇다고 "고쳤다"고 단정할 수도 없다. **사용자가 브라우저에서 직접 다시 확인이 필요함.** 안 보이면 진단 로그(화면 좌상단)에 "특수족보 연출 시작"이 실제로 찍히는지부터 확인해달라고 요청할 것 - 그것조차 안 찍히면 시그널 전달 자체가 문제고, 찍히는데 안 보이면 렌더링/z-order 쪽을 더 파야 한다.
- **볼드체 적용**: `special_hand_label`에 `Pretendard-Bold.otf`(이미 있던 파일)를 `add_theme_font_override("font", bold_font)`로 적용했다. ExtraBold(OFL, jsdelivr에서 받아봄, 1.5MB)도 비교해보려 했으나 위 재현 문제로 나란히 비교할 시간을 못 냈고, 우선 Bold로 반영 후 제거했다(저장소에 안 남음) — 사용자가 실제로 보고 부족하다고 판단하면 그때 ExtraBold/Black을 다시 받아 비교하기로 함(둘 다 같은 OFL 라이선스, 파일 크기도 비슷해서 웹 빌드 용량에 미치는 영향은 미미함 - Bold를 ExtraBold로 "교체"하면 순증가는 없고, "추가"하면 약 1.5MB 늘어남).

### 현재 전체 테스트 개수
387개 (`scripts/tests/test_runner.tscn`, 전부 통과).

### 🚨 배포 전 필수 확인: `build_info.gd`의 `DEBUG_MODE`를 `false`로
`DEBUG_MODE`는 개발/테스트용 디버그 기능을 전부 묶는 하나의 스위치다. **지금은
1-7·1-8에서 웹 export 빌드를 계속 확인해야 해서 의도적으로 `true`로 켜져
있다. 정식 배포 전에는 반드시 `false`로 되돌릴 것** — 이 값은
`addons/build_stamp`가 건드리지 않는 상수라(정규식이 `BUILD_TIME` 줄만
바꾼다) export를 다시 해도 그대로 남는다. `git status`/`git diff`로 이 값이
`false`인지 커밋 전에 항상 확인한다. 3-3(배포 준비) 체크리스트에도 있다.

이 스위치 하나에 아래 세 가지가 전부 묶여 있다(`false`면 셋 다 안 보이고
안 켜짐, `true`면 셋 다 켜짐):
- `scripts/dev/debug_hotkeys.gd`의 Ctrl+Shift+숫자/S/A 키보드 단축키
- 같은 파일의 화면 우하단 디버그 버튼 6개 — **웹에서는 키보드 단축키를 믿을
  수 없다는 게 실제로 확인됐다.** 브라우저가 Ctrl+숫자 조합을 자체 단축키로
  먼저 가로채기 때문(크롬은 Ctrl+1~8을 탭 전환에 쓴다). 그래서 버튼을
  이중화해뒀고, 버튼과 키보드는 `_perform_action()`이라는 같은 함수를
  호출하므로 동작이 완전히 같다 — 데스크톱 에디터에서는 키가 빠르니 그대로
  쓰고, 웹에서는 버튼을 쓴다.
- `Main.gd`의 화면 좌상단 진단 로그(`_debug_init_log()`) — 게임 시작 초기화
  단계, `special_hand_rolled` 구독자 수/이름 등을 찍는다. 웹에서만 재현되고
  에디터에서는 안 되는 버그를 잡을 때 브라우저 콘솔보다 이게 더 믿을 만하다
  (1-5에서 겪은 문제).

원래 이름은 `DEBUG_KEYS_IN_EXPORT`(단축키만 export에서 켜는 용도)였는데,
진단 로그까지 이 스위치 하나로 묶으면서 `DEBUG_MODE`로 이름을 바꿨다. 예전엔
`OS.has_feature("editor")`가 참이면 이 값과 무관하게 단축키가 항상 켜졌지만,
지금은 그 특별 취급을 없애고 `DEBUG_MODE` 하나로 통일했다 — 에디터에서 계속
개발하는 동안은 `true`로 켜두면 되고, 그 자체가 배포 전 `false` 전환을
잊지 않게 하는 유일한 안전장치가 된다.

### 디버그 단축키/버튼 (`scripts/dev/debug_hotkeys.gd`, `DEBUG_MODE`가 `true`일 때만 동작)
- Ctrl+Shift+1 / [야추] 버튼 : 야추로 강제 지정
- Ctrl+Shift+2 / [라지] 버튼 : 라지 스트레이트로 강제 지정
- Ctrl+Shift+3 / [풀하우스] 버튼 : 풀 하우스로 강제 지정
- Ctrl+Shift+4 / [포카드] 버튼 : 포카드로 강제 지정
- Ctrl+Shift+S / [한 칸 확정] 버튼 : 현재 플레이어의 빈 칸 하나 자동 확정
- Ctrl+Shift+A / [끝까지 진행] 버튼 : 게임이 끝날 때까지 자동 진행
(키보드 단축키는 텍스트 입력 위젯에 포커스가 있으면 전부 무시된다.)

### 1-6 완료 — 웹에서도 최종 확인됨
캐릭터 편집 UI, 게임 시작 전 캐릭터 선택 화면, 화면 전환 정리(버그 1),
res:// 리소스 로딩 버그(2라운드) 수정에 이어, 특수 족보(야추 등) 연출이
웹에서 안 뜬다던 마지막 의심(3라운드)까지 실제로는 버그가 아니었던 것으로
결론났다 — 웹에서는 디버그 키가 export 빌드에서 안 먹어서 애초에 야추가 발생한
적이 없었을 뿐이고, 위 디버그 버튼으로 실제 야추를 띄워본 결과 데스크톱과
동일하게 정상 동작했다(사용자가 웹 브라우저에서 직접 확인함). **1-6을 최종
완료로 닫는다.**

### 남은 단계
- 1-7: 캐릭터 팩(내보내기/불러오기) — zip으로 묶을 때 1-6의 "저장 시 고아 파일 정리" 덕분에 manifest가 안 가리키는 파일은 이미 없는 상태라는 걸 전제로 설계 가능.
- 1-8: 웹 빌드 최종 검증(캐릭터 편집 화면의 실제 브라우저 동작, 시크릿 모드에서의 user:// 동작 포함)
- Phase 2: 온라인 멀티플레이
