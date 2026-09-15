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
- WebSocket 메시지 크기와 수신 버퍼 크기의 관계를 항상 확인할 것. 큰
  메시지를 연달아 보내면 버퍼가 넘쳐 조용히 사라진다(2-5 후속, 실제로
  겪음 - `docs/multiplayer.md` §8.5-6).

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
- 1-7: 캐릭터 팩(.ydchar.zip 내보내기/가져오기) — **데스크톱은 실제 클릭까지 확인 완료. 웹은 export만 했고 사용자의 브라우저 확인이 아직 안 됨.**
- 2-1: 멀티플레이 설계 문서(`docs/multiplayer.md`) + GameState headless 검증(`server_main.gd`) — **완료.**
- 2-3: WebSocket 연결 + 방 관리(게임 동기화 제외) — **완료.** 실제 소켓으로
  수동 검증(아래 요약)까지 마침, 사용자의 에디터 다중 인스턴스 확인은 아직.
- 2-4: 실제 게임 동기화(서버 권위 + "리모컨" UI) — **완료.** 실제 소켓으로
  한 판 끝까지(굴리기/고정/확정/턴 전환/게임 종료) 수동 검증함.
- 2-4B: 온라인 로비에 내 캐릭터 연결 — **완료(배선까지). 실제 보이스가
  들리는지는 사용자의 수동 확인이 아직.**
- 2-4C: GameEvents 릴레이 전수 조사 + `die_held_changed` 등 5개 추가 —
  **완료.** 온라인 홀드 효과음 안 나던 버그의 원인이었음.
- 2-5: 캐릭터 팩 실시간 전송(`transferring` 단계 실제 구현) — **완료.**
  실제 소켓(서버+클라이언트 2개)으로 정상 전송/오버사이즈 거부 두 경로
  모두 수동 검증함(아래 요약).

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

### 2-3(WebSocket 연결 + 방 관리) 완료 요약
`docs/multiplayer.md`의 메시지 규약을 그대로 따랐다 - 게임 진행 동기화
(주사위/점수, request_roll 등)는 이번 범위 밖이고 연결·로비·방 관리까지만.

- **문서와 다르게 구현한 부분(사전에 확인받음)**: 문서 §9 결정 1("방 인원은
  생성 시점에 고정")과 달리, 로비 중 방장이 인원수를 낮출 수 있어야 한다는
  요구사항이 있어 `set_player_count`(C→S)/`room_player_count_changed`(S→C)
  메시지를 새로 추가했다(사용자가 미리 승인).
- **문서에 없어서 이번에 채운 것들**: 에러 코드 `NOT_HOST`/`GAME_ALREADY_STARTED`.
  방장 판정 규칙(별도 필드 없이 "현재 채워진 슬롯 중 가장 낮은 인덱스").
  `room_joined` 응답에 문서에 없던 `player_count` 필드를 추가(클라이언트가
  "인원 N/M"을 그리려면 목표 인원을 알아야 하는데 `players` 배열만으로는
  알 수 없어서 - §2.0의 "기본값 있는 선택적 필드 추가는 버전을 안 올려도
  된다"는 규칙 안에서의 추가).
- **새 파일**: `scripts/net/protocol.gd`(NetProtocol - 메시지 상수 +
  JSON 인코드/디코드), `scripts/net/secure_random.gd`(SecureRandom -
  2-1의 `_generate_secure_seed()`를 여기로 옮김), `scripts/net/room.gd`(Room -
  방 하나의 상태: 슬롯 배열/로비 상태 기계/GameState+RNG), `scripts/net/room_manager.gd`(RoomManager -
  방 코드 발급/라우팅, 네트워크를 전혀 모르는 순수 로직), `scripts/net/game_client.gd`(GameClient -
  클라이언트 쪽 WebSocketMultiplayerPeer + 프로토콜 상태 기계, GameEvents와
  같은 패턴으로 시그널만 emit), `scripts/net/session_store.gd`(SessionStore -
  재접속 토큰을 `user://session.json`에 저장 - **이번 단계는 발급/저장까지만,
  실제 재접속 매칭은 2-6**), `scenes/online/online_screen.tscn`+`.gd`(온라인
  화면 - 서버 접속/방 만들기·참가/로비).
- **방마다 독립된 RNG**: `Room._init()`이 `SecureRandom.generate_seed()`로
  방 전용 시드를 새로 뽑는다(서버 전체가 RNG를 공유하면 한 방에서 본
  주사위로 다른 방 결과를 추론할 여지가 생기므로 절대 공유하지 않음).
  로비 중 `set_player_count`로 인원이 바뀌면 **같은 RNG 인스턴스를
  재사용**해 `GameState`만 다시 만든다(`GameState._init()`은 생성 시점에
  주사위를 안 굴리므로 안전 - `roll()`을 실제로 부르기 전까지 RNG를
  소모하지 않음).
- **`server_main.gd`를 REPL에서 실제 서버로 완전히 교체**: 2-1에서 만든
  `roll`/`hold`/`score`/`state`/`auto`/`quit` 콘솔 명령은 전부 없앴다 -
  `OS.read_string_from_stdin()`은 블로킹이라 `_process()`로 소켓을
  폴링해야 하는 서버 루프와 같이 못 쓴다(2-1에서 실측 확인한 사실 그대로
  재확인됨). 이제 서버 종료는 프로세스를 직접 끊는 방식(Ctrl+C)이다. 포트는
  CLI 인자 → `YACHT_DICE_PORT` 환경변수 → 기본값 8910 순.
- **시작 화면을 로컬/온라인으로 분기**: `Main.tscn`의 StartScreen에
  `ModeChoiceRow`([로컬 게임]/[온라인 게임])를 추가하고, 기존
  인원수 선택 UI는 `LocalGamePanel`로 묶어서 숨김 처리했다. 기존 로컬
  플레이 흐름(2/3/4인 버튼 → 캐릭터 선택 → 게임)은 코드/시그널을 전혀
  안 건드렸다 - `test_game_start_builtin_only.gd`가 여전히 통과하는 것으로
  구조적 회귀는 없음을 확인했지만, **버튼을 실제로 눌러보는 화면 확인은
  아직 사용자 몫**(에디터에서 직접).
- **수동으로 실제 소켓 검증까지 마침**(자동 회귀 테스트에는 안 넣음 - 실제
  TCP 연결이 필요해서 헤드리스 테스트 스위트의 성격과 안 맞음): 서버를
  실제로 띄우고 클라이언트 역할을 하는 임시 스크립트로 다음을 전부
  확인했다 - hello 핸드셰이크, 방 생성/참가, 캐릭터 메타 브로드캐스트,
  방장의 `set_player_count`(3→2)와 그 순간 바로 반영되는 정원, 전원 준비
  시 자동 시작(game_started), 방 없음/방장 아닌 사람의 인원수 변경 시도
  에러 응답, 프로토콜 버전 불일치 시 연결 종료, 메시지 크기 초과 시 연결
  종료.
  - **수동 검증 중 실제 버그 하나 발견하고 수정**: 방의 두 참가자가 거의
    동시에 나가면(연결이 이미 닫힌 상대에게) `player_left` 알림을
    보내려다 엔진이 "ready_state != STATE_OPEN" ERROR를 콘솔에 남겼다
    (크래시는 아니고 계속 진행되지만 로그가 지저분함). `server_main.gd`의
    `_send()`가 보내기 전에 `WebSocketPeer.get_ready_state() == STATE_OPEN`을
    먼저 확인하도록 고쳤다.
- 새 테스트 33개(`test_protocol.gd`/`test_session_store.gd`/`test_room_manager.gd`) -
  전체 522개 통과. `GameClient`/`server_main.gd`의 실제 소켓 동작 자체는
  이 테스트들이 다루지 않는다(위 수동 검증으로 커버).
- **남은 것**: 사용자가 직접 Godot 에디터의 "Run Multiple Instances"로
  클라이언트 여러 개를 띄워 실제 화면으로 확인(수동 소켓 검증은 화면 없이
  스크립트로만 했음), 로컬 모드 화면 확인.

### 2-3 후속 — 닉네임(display_name) 검증 보강
2-3 검토 중 사용자가 지적: 닉네임은 남의 화면에 그대로 뜨는 값인데 검사가
없었다. `NetProtocol`(클라이언트/서버 공유)에 `MAX_DISPLAY_NAME_LENGTH`(20 →
**12자**로 조정)와 `sanitize_display_name()`(제어문자 제거 + 양끝 공백
제거 + 길이 제한)을 추가하고, 온라인 화면의 `NicknameEdit.max_length`도
이 값으로 맞춰 입력 자체를 막는다. **서버(`server_main.gd`)가 받은 뒤
다시 한번 같은 함수로 정리한다** - 클라이언트가 보낸 값을 그대로 믿지
않는다(원칙 6). 정리 후 빈 문자열이면(제어문자/공백뿐이었으면) 서버가
슬롯 번호로 "플레이어 N" 기본값을 채운다. 새 테스트 4개, 실제 소켓으로
"제어문자+30자 닉네임 → 12자로 정리됨"/"빈 닉네임 → 플레이어 N"까지
수동 확인함. 전체 526개 테스트 통과.

### 2-4(실제 게임 동기화) 완료 요약
`docs/multiplayer.md` §1/§2/§4/§5를 실제로 구현했다 - 서버가 주사위를
굴리고, 클라이언트는 화면을 그리기만 한다.

- **"리모컨" 구조(사용자가 확정)**: 게임 화면(`scenes/Main.gd`)은 버튼이
  눌리면 `active_controller.request_roll()/request_hold()/request_score()`만
  부른다. `if 온라인` 분기가 화면 코드 안에 전혀 없다 - 로컬/온라인
  어느 쪽을 붙일지는 게임 진입 지점(`_enter_game()`) 한 곳에서만 정해진다.
  단, **읽기(화면 렌더링)는 지금처럼 `game_state` 필드를 직접 읽는다** -
  사용자가 "쓰기만 금지"로 범위를 명확히 확정해줘서, 기존 `_refresh_*_ui()`
  코드는 거의 안 바뀌었다.
- **`GameState`에 `read_only` 추가**: `roll()`/`toggle_lock()`/
  `confirm_category()`/`start_turn()`/`auto_confirm_least_damaging()`은
  read_only 인스턴스에서 부르면 `push_error`로 시끄럽게 실패하고 아무
  것도 안 바꾼다 - "에러 없이 조용히 틀리는" 사고(초기 야추 50점,
  queue_free, 특수 족보 연출)를 다시 겪지 않기 위한 설계. 유일한 갱신
  경로는 `apply_snapshot()`(서버 스냅샷을 그대로 반영, JSON 왕복으로
  정수가 float가 되는 문제를 원소별 `int()`/`bool()`로 방어).
- **컨트롤러 2개**(`scripts/game/`): `LocalGameController`(진짜
  `GameState.roll()` 등을 직접 부름), `OnlineGameController`(read_only
  `GameState` 사본을 들고 있고, `GameClient.request_*()`를 보낸 뒤
  응답이 올 때까지 `is_request_pending()`으로 연타를 막는다). 둘 다
  추상 클래스 없이 같은 이름의 메서드만 맞춘 덕타이핑 계약.
- **서버**: `Room`에 `validate_roll/hold/score()`(순수 로직, 헤드리스
  테스트 가능)를 추가하고 `server_main.gd`는 이 결과만 보고 배선한다.
  GameEvents 릴레이는 서버 프로세스 전체에 하나뿐인 `GameEvents`
  인스턴스를 "지금 처리 중인 방"(`_active_room`) 표시로 공유해서, 방마다
  새로 구독하지 않는다. **스냅샷을 먼저 보내고 이벤트를 그 다음에
  보낸다**(사용자가 지적한 순서 요구사항) - 안 그러면 보이스 핸들러가
  낡은 상태를 읽는다.
- **문서에 이름 없어 새로 정한 에러 코드 2개**: `NOT_YOUR_TURN`(문서
  §7에 이름만 언급됨), `NOT_IN_GAME`(문서에 이름조차 없음). 리롤 소진/
  이미 확정된 칸/범위 밖 인덱스는 전부 `INVALID_ARGUMENT` 재사용.
- **온라인 v1은 캐릭터 보이스가 안 난다(버그 아님, 2-3이 정한 범위)**:
  온라인 로비는 닉네임만 받으므로, 게임 화면엔 `display_name`만 채운
  빈 `CharacterProfile`을 넘긴다 - "매핑 없는 캐릭터" 경로(기존 로컬
  코드가 이미 처리하던 경로)를 그대로 타서 특수 족보 텍스트 팝업과
  효과음(SfxBank)은 온라인에서도 완전히 정상 동작하지만, 캐릭터
  보이스만 voice_map이 비어 있어 소리가 안 난다. 2-5에서 실제 캐릭터
  데이터가 오가면 그 즉시 채워진다.
- **디버그 단축키/버튼을 온라인에서 숨김**: `debug_hotkeys.gd`에
  `set_panel_visible()`을 추가하고 `_show_screen()` 한 곳에서
  온라인 로비/온라인 게임 양쪽 다 가린다. `debug_hotkeys.game_state`는
  온라인 사본에 절대 안 물린다(`_enter_game()`에서 `my_index == -1`일
  때만 연결).
- **Phase 1 연출 코드는 실제로 0줄 바뀜**: `autoload/voice_bank.gd`,
  `autoload/sfx_bank.gd` 전체와 `Main.gd`의 `_transition_portrait`/
  `_play_special_hand_effect`/`_start_greeting_sequence`/
  `_on_greeting_step_started`/`_on_greeting_sequence_finished`/
  `_build_character_area`/`_build_scoreboard` 함수 본문을 diff로
  확인함 - 전부 변경 없음. 서버가 보낸 이벤트를 클라이언트가 로컬
  `GameEvents`로 재방출하기만 하면 됐다는 뜻.
- **온라인 재대전은 이번 범위 밖**: 게임 종료 후 [다시 하기] 버튼은
  로컬에서만 보이고 온라인은 [타이틀로]만 제공한다.
- 새 테스트 30개(`test_game_state_snapshot.gd`/`test_room_gameplay.gd`/
  `test_online_game_controller.gd`) - 전체 582개 통과. 실제 소켓
  동작(요청→스냅샷→화면 갱신, 남의 턴 요청 거부, 인원수 변경, 게임 종료
  까지)은 서버를 실제로 띄우고 스크립트 클라이언트 2개로 한 판 끝까지
  수동 검증했다 - 이 과정에서 실제 버그 하나 더 발견: 방의 두 참가자가
  거의 동시에 나갈 때(2-3에서 이미 고친 `_send()` 가드) 외에 새로 발견된
  건 없음, 2-3의 수정이 여전히 유효함을 재확인.
- **에디터 GUI 다중 인스턴스로 화면까지 보는 확인은 아직 사용자 몫**
  (텍스트 팝업/초상화 전환/점수판 갱신이 실제로 눈에 보이는지).

### 2-4B(온라인 로비에 내 캐릭터 연결) 완료 요약
2-4에서 온라인 보이스 경로가 한 번도 실행된 적이 없어서(닉네임만 다뤄서)
"조용한 게 정상인지 연결이 없는지" 구분이 안 되는 문제를 먼저 해소했다 -
2-5(캐릭터 팩 전송) 전에 내 캐릭터로 먼저 검증.

- **인사 연출(1-4C)은 코드를 전혀 안 건드렸다.** `autoload/voice_bank.gd`의
  `_advance_greeting()`을 다시 읽어 확인: 매핑 없는 플레이어는 재생 시도
  자체를 안 해서 대기 시간이 0이고 화면 전환도 없다 - "여러 명이 서 있는데
  침묵" 같은 어색함이 원래 없는 구조였다. 로컬에서 "일부만 보이스를 설정한
  다인 게임"과 완전히 같은 코드 경로라 온라인 전용 처리가 필요 없었다.
- **1-6의 `CharacterSelectScreen`을 그대로 재사용**(새 화면 안 만듦) -
  `configure(1)`로 1인분만 빌려서 온라인 로비의 "내 캐릭터" 선택에 쓴다.
  `Main.gd`의 `_character_select_for_online` 플래그 하나가 결과를 로컬
  새 게임(`_start_new_game`)과 온라인(`online_screen.set_my_profile()`)
  중 어디로 돌려줄지 정하는 유일한 분기점. 기본값 false라 로컬 흐름은
  코드 경로가 전혀 안 바뀐다.
- **온라인 로비의 닉네임 입력(LineEdit)을 캐릭터 선택으로 완전히
  대체**했다 - `select_character`로 보내는 `display_name`은 이제 내가
  고른 `CharacterProfile.display_name`이고, `meta.id`도 처음으로 실제
  값을 채워 보낸다(문서가 이미 정의해둔 필드를 채우는 것뿐이라 프로토콜
  변경 아님 - 2-5에서 캐릭터 팩 요청에 쓸 수 있게 미리 채워둠).
  `CharacterLibrary.get_selectable_profiles()[0]`(내장 기본 포함이라 항상
  1개 이상)을 화면이 뜨자마자 기본값으로 잡아둬서, 아무것도 안 눌러도
  항상 유효한 캐릭터가 붙어 있다.
- **게임 시작 시 내 슬롯에만 실제 프로필을 연결**한다
  (`online_screen.gd`의 `_on_game_started()`) - 남의 슬롯은 여전히
  닉네임만 채운 빈 프로필(실루엣 폴백, 2-5 전까지). 이 배열이 그대로
  `VoiceBank.configure()`/`_build_character_area()`/`_build_scoreboard()`로
  넘어가므로(2-4에서 이미 뚫어놓은 경로) 그 함수들은 이번에도 한 줄도
  안 바뀌었다.
- **헤드리스로 배선 로직을 확인**(임시 씬으로 `online_screen.tscn`을
  실제로 인스턴스화 - 저장소엔 안 남김): 기본 프로필 자동 선택, 썸네일/
  이름 표시 갱신, 게임 시작 시 "내 슬롯=내 진짜 프로필 객체, 남의
  슬롯=별도 플레이스홀더 객체"가 정확히 조립되는 것까지 확인함.
- **실제 오디오가 들리는지는 자동화할 수 없다** - 실제
  `user://characters/`의 진짜 보이스 파일이 있어야 의미가 있어서, 이번
  스텝의 핵심 확인(내 턴에 내 보이스가 실제로 재생되는지)은 **사용자가
  직접 듣고 확인해야 한다.** 안 들리면 `VoiceBank.configure()`에 실제로
  뭐가 들어가는지부터 짚어나가면 된다.
- 새 자동 테스트는 추가하지 않음(계획 단계에서 이미 정함 - 순수 클라이언트
  로컬 배선이라 오디오/화면을 직접 봐야 의미가 있음). 전체 582개 그대로
  통과(회귀 없음).

### 2-4C(GameEvents 릴레이 전수 조사) 완료 요약
사용자가 온라인에서 주사위 홀드 효과음이 안 난다고 보고 → 원인은
`die_held_changed`가 2-1 문서의 릴레이 목록에 처음부터 빠져 있었던 것.
"이런 게 또 있을 수 있다"며 `GameEvents`의 시그널 12개 전부를 판정표로
훑었다.

- **판정 결과**: `dice_rolled`/`special_hand_rolled`/`bonus_achieved`/
  `zero_scored`/`turn_started`/`game_ended`는 이미 전달되고 있었음.
  `die_held_changed`는 [누락](SfxBank가 실제로 구독 중인데 서버가 안
  보냄). `score_committed`/`yacht_scored`/`turn_ended`/`game_started`
  (GameState 자체 시그널)는 처음엔 "지금 구독자가 없다"는 이유로 제외
  후보였다.
- **사용자가 그 판정 기준 자체를 기각함**: "구독자가 없어서 제외"는
  오늘 참인 사실이지 규칙이 아니고, 나중에 연출을 추가하는 사람은 자기
  코드를 의심하지 릴레이 목록을 의심하지 않는다(`die_held_changed`가
  정확히 그 꼴). 그래서 **규칙을 "게임에서 일어난 사건은 전부 전달한다,
  예외는 `score_previewed` 하나(빈도 + 클라이언트 재계산 가능)"로
  단순화**하고, 나머지 5개를 전부 릴레이에 추가했다.
- **이름 충돌을 하나 발견해서 피함**: `GameState.start_turn()`이 내는
  `GameEvents.game_started`를 그대로 릴레이하려 했더니, 로비가 다 찼을
  때 이미 보내는 네트워크 메시지 `game_started`(§2.2, `player_count`만
  담는 별개의 메시지)와 이름이 겹쳐서 클라이언트가 게임 시작을 두 번
  받을 뻔했다(인사 연출이 두 번 시작될 위험). 새 메시지 이름
  `game_state_started`를 따로 만들어서 피했다 - 로컬로 재방출할 때는
  원래 이름(`GameEvents.game_started`)으로 되돌아간다.
- **프로토콜 버전은 안 올림** - 올리기 전에 전제("모르는 메시지 타입을
  받아도 크래시 안 함")를 코드로 직접 확인했다: 클라이언트(`game_client.gd`)는
  `match`에 해당 분기가 없으면 조용히 무시, 서버(`server_main.gd`)는
  기본 분기에서 `error`만 보내고 연결을 안 끊는다. 둘 다 안전함을
  실제 소켓으로도 재확인(모르는 타입의 메시지를 보내도 연결 유지됨).
- **재발 방지**: `scripts/net/game_event_relay.gd`에 `RELAYED_EVENTS`/
  `EXCLUDED_EVENTS` 두 목록을 만들고,
  `test_game_event_relay_classification.gd`가
  `GameEvents.get_script().get_script_signal_list()`(상속 시그널 제외,
  스크립트가 직접 선언한 것만)로 실제 시그널 목록을 읽어와 둘 중
  하나로 분류돼 있는지 대조한다 - 새 시그널을 추가하고 분류를 빠뜨리면
  이 테스트가 바로 실패한다("나중에 사람이 기억해서 확인"에 안 기댐).
- **문서 동기화**: `docs/multiplayer.md` §2.2에 새 이벤트 5개 + 위 규칙
  한 줄을 추가하면서, 이번에 발견한 기존 누락(2-3의 `set_player_count`/
  `room_player_count_changed`가 문서에 아예 없었음)도 같이 채웠다.
- 실제 소켓으로 `die_held_changed`가 전달되는지, `game_state_started`가
  `GameEvents.game_started`를 중복 없이 정확히 한 번만 재방출하는지
  확인함. 새 테스트 12개 추가, 전체 610개 통과.

### 2-5(캐릭터 팩 실시간 전송) 완료 요약
로비의 `transferring` 단계(2-3에서 자리만 만들어두고 v1은 즉시 통과시키던
그 단계)에서 실제로 서로의 캐릭터 팩을 주고받게 했다. 자세한 프로토콜/
설계 결정은 `docs/multiplayer.md` §8, 팩 검증 공유 구조는
`docs/character_pack.md`에 정리했다 — 여기는 요약만.

- **1단계(메타데이터+해시 캐시)**: `select_character`/`player_character`의
  `meta`에 `pack_hash`(sha256 hex) 필드를 추가했다(기본값 있는 선택
  필드라 프로토콜 버전은 안 올림, 2-4C와 같은 근거). 캐릭터를 고르면
  그 자리에서 `export_pack_bytes()`로 압축+해시를 미리 끝내둔다(업로드
  요청이 와도 재압축 안 함). `ReceivedPackCache.has_cached()`로 이미
  받은 해시면 요청 자체를 안 보낸다 - 같은 캐릭터를 고른 사람끼리, 그리고
  재접속 시에도 다시 안 받는다.
- **2단계(실제 전송)**: 서버(`Room.TransferState` - `COLLECTING` →
  `TRANSFERRING_PACK` × N → `DONE`)가 **한 번에 해시 하나씩만** 순서대로
  처리한다 - 이 스케줄러 설계 덕분에 "한 클라이언트가 동시에 두 개를
  안 받는다"는 요구사항이 클라이언트 쪽 로직 없이 저절로 만족된다. 청크는
  `NetProtocol.CHUNK_PAYLOAD_BYTES`(32KB, 이번에 문서 상수에서 실제 코드
  상수로 승격)로 나눠 Base64로 보낸다. 전송 상한은 `CharacterLimits.TOTAL_WARNING_BYTES`
  (15MB)를 그대로 재사용해서, 1-7B 편집 화면의 안내 문구("15MB를 넘으면
  전송 안 될 수 있다")와 실제 상한이 같은 상수에서 나오게 했다.
- **막혔을 때**: 60초(`PACK_TRANSFER_TIMEOUT_MSEC`) 타임아웃, 소유자가
  보낸 `total_bytes`가 상한을 넘으면 첫 청크에서 즉시 포기 - 둘 다
  `pack_transfer_failed`를 방 전체에 방송하고 다음 해시로 넘어가며, 큐가
  다 처리되면(실패 포함) 항상 `game_started`가 나간다. 실제 소켓으로
  정상 전송과 오버사이즈 거부(가짜 `total_bytes`) 두 경로 모두 확인함 -
  둘 다 로비가 멈추지 않고 게임이 시작됨.
- **받은 팩 처리(예외 없음)**: 1-7의 검증 로직을 `CharacterLibrary.validate_and_extract_pack()`
  으로 뽑아 로컬 가져오기/네트워크 수신이 공유하게 리팩터링했다(신뢰
  검증이 두 곳에서 갈라지지 않게). 이 함수는 파일 하나 풀 때마다 선택적
  `yield_node`를 통해 한 프레임씩 쉬어서(2-5의 새 요구사항), 최대 3명분을
  받을 때 압축 해제가 한 프레임에 몰려 웹이 얼어붙는 걸 막는다 - 이
  함수가 `await`를 포함하는 코루틴이 되면서 `import_pack()`과 그 호출부
  (`character_editor.gd`, 테스트 3개)도 전부 `await`를 타도록 같이
  바꿨다. 재조립한 바이트의 sha256을 받는 쪽이 직접 검증(서버는 버퍼링
  없이 릴레이만 함)하고, 검증/해시 대조 실패는 상대를 탓하지 않고
  로그만 남긴 뒤 조용히 기본 캐릭터로 대체한다. 저장 위치는
  `user://cache/received/<해시>/`로 `user://characters/`(내 캐릭터
  목록)와 완전히 분리했고, 60MB(`ReceivedPackCache.MAX_CACHE_BYTES`)
  상한을 넘으면 오래된 것부터 지운다.
- **저장이 막힌 환경**: `AssetLoader.load_texture_from_bytes()`/
  `load_audio_from_bytes()`가 이미 경로 없이 순수 바이트만 받는 구조라는
  걸 구현 전에 코드로 직접 확인했고, 그 덕분에 디스크 쓰기 실패 시
  `CharacterProfile.asset_bytes`(새 런타임 전용 필드)에 바이트를 담아
  그 판 한정 메모리 전용으로 쓰는 경로가 새 디코딩 코드 없이 거의
  공짜로 만들어졌다. `CharacterProfile`의 또 다른 새 런타임 전용 필드
  `asset_base_dir`은 디스크 캐시 경로를 가리킨다 - 두 필드 모두
  `is_builtin`과 같은 패턴(직렬화 안 됨)이라 `VoiceBank`/`CharacterPortrait`/
  `voice_mapping_panel.gd` 세 호출부는 한 줄도 안 고쳤다
  (`CharacterLibrary.load_profile_texture()`/`load_profile_audio()`의
  분기만 확장).
- **신규 파일**: `scripts/net/received_pack_cache.gd`(`ReceivedPackCache`),
  `scripts/net/pack_transfer_client.gd`(`PackTransferClient` - 클라이언트
  쪽 상태 기계, 슬롯별 `NONE`/`WAITING`/`RECEIVING`/`DONE`/`FAILED`).
  새 테스트 17개(`test_pack_transfer_metadata.gd` - `Room.compute_needed_hashes()`
  중복 제거, 서버 스케줄러의 수집/타임아웃/큐 소진을 순수 로직으로
  검증) + 기존 3개 테스트를 `await` 대응으로 수정, 전체 638개 통과.
- **검증 방법(주의 - 재현 시 참고)**: 실제 서버(`server_main.gd`) +
  클라이언트 2개(`GameClient`)를 한 프로세스 안에서 붙여 검증했다. 이
  과정에서 이번 세션에 이미 한 번 겪었던 "GDScript 람다가 바깥 지역
  변수를 값으로 캡처해서, 람다 안에서 대입해도 바깥에 반영 안 됨" 함정을
  검증 스크립트 자체에서 또 밟았다(멤버 필드로 바꿔서 해결) - 로컬 변수를
  `connect()`하는 람다 안에서 바꿀 계획이면 항상 멤버 필드나 Dictionary로
  박싱할 것. 검증 스크립트는 확인 후 삭제해서 저장소에 안 남았다.
- **후속 버그 수정 - 전송이 2%(청크 1개)에서 멈춤**: 사용자가 실제 브라우저
  (에디터의 "브라우저에서 실행"과 내보낸 웹 빌드 둘 다)로 재현. 원인은
  `WebSocketMultiplayerPeer`의 `outbound_buffer_size` 기본값이 65535바이트
  뿐인데, 업로더가 32KB(Base64 후 약 43KB) 청크를 한 프레임 안에서 연달아
  `put_packet()`으로 내보내다 대기열이 금방 넘쳤기 때문 - `put_packet()`은
  이때 크래시 없이 `ERR_OUT_OF_MEMORY`만 조용히 돌려주는데 그 반환값을
  안 보고 있어서 두 번째 청크부터 사라졌다(직접 400KB 무작위 팩으로
  재현 - 엔진이 실제로 `ERR_OUT_OF_MEMORY`를 여러 번 반환하는 것까지
  확인함). `GameClient`/`server_main.gd` 양쪽 `_send()`를 보내기
  큐(실패한 메시지는 버리지 않고 다음 프레임에 재시도) 구조로 바꿔서
  해결 - 자세한 경위와 진단 로그 위치는 `docs/multiplayer.md` §8.5-1.
  같은 방식으로 수정 전/후 재현·해결을 각각 실제 소켓으로 재확인했고
  (13청크 팩이 끝까지 도착, 캐시 파일 크기가 원본과 정확히 일치), 전체
  638개 테스트 그대로 통과.
- **후속 버그 수정 2 - 전송은 100%인데 상대 초상/보이스가 안 뜸**: 위
  버그를 고친 뒤에도 사용자가 재현. 프레임 타임라인을 찍어 확정한 원인:
  `server_main.gd`는 마지막 청크를 릴레이 큐에 넣자마자 `game_started`를
  보내는데, 클라이언트는 그 청크를 검증·캐시 저장·프로필 확정하는 데
  (웹 프리징 방지용 프레임 분할 때문에) 몇 프레임 더 걸린다 - "보냈다"를
  "받는 쪽이 다 처리해서 쓸 수 있다"로 착각한 것으로, 바로 위 WebSocket
  버그와 같은 패턴이 한 단계 위(메시지 단위)에서 반복된 것이었다.
  사용자가 "클라이언트만 기다리게 하면 검증 속도 차이 때문에 재현 안
  되는 버그가 된다"고 지적해서, 클라이언트 쪽 대기 대신 **서버가 전원의
  `pack_ready`(새 메시지, 영수증) 를 받은 뒤에만 `game_started`를
  보내도록** 바꿨다(`Room.TransferState`에 `AWAITING_READY` 단계 추가,
  `NetProtocol.PACK_READY_TIMEOUT_MSEC` 별도 상수 - 자세한 경위·설계
  근거는 `docs/multiplayer.md` §8.5-2). 클라이언트 쪽에도 이중 방어로
  `wait_until_all_resolved()`를 남겨뒀다. 실제 소켓으로 4가지(파일 많은
  팩의 레이스 재현 여부, 한쪽만 커스텀, 양쪽 다 기본 캐릭터, 검증 실패
  팩) 전부 확인, 새 테스트 13개 추가로 전체 649개 통과.
- **후속 버그 수정 3 - 카운트다운 정지 + 큰 팩 전송이 중간에 멈춤**:
  (a) "타임아웃까지 N초" 카운트다운이 60에서 안 내려가던 건 진짜 타임아웃이
  멈춘 게 아니라(그건 `Time.get_ticks_msec()` 기반이라 안 멈췄음), 화면
  갱신이 청크 이벤트에만 걸려 있어서 전송이 멈추면 화면도 같이 멈춘
  것이었다 - `PackTransferClient._process()`가 매 프레임 직접 갱신하도록
  고침. (b) 보내는 쪽/서버/받는 쪽 3자 모두에 5초 무진전 시 경고를 남기는
  멈춤 감지를 추가함(`NetProtocol.TRANSFER_STALL_WARNING_SEC`). (c) 진짜
  원인 조사 중 순수 엔진 실험으로 "엔진이 패킷을 유실한다"는 가설을
  세웠으나, 사용자가 "실제 로그엔 유실이 없다(42/42 다 도착)"고 반박 -
  재검토 결과 가설이 틀렸음을 인정하고 폐기함. 코드를 다시 읽어 진짜
  원인을 확정: `PackTransferClient`의 완료 판정(`for c in chunks: if c ==
  null: return`)이 몇 번째 청크가 빠졌는지 안 보고 "전부 찼는지"만 보는데,
  청크 단위 재전송/결측 확인이 아예 없어서 **중간 청크 하나만 빠져도
  `_finalize_received_pack()`이 영원히 안 불린다.** 청크 하나를 일부러
  안 보내는 재현으로 직접 확인함. 이때 `wait_until_all_resolved()`에
  상한이 없어서 게임 화면으로 절대 못 넘어가는 **확실한 버그**를 그
  자리에서 고쳤다(`NetProtocol.LOCAL_PACK_RESOLVE_TIMEOUT_MSEC`, 10초 -
  서버의 60초보다 짧게). 진단도 강화해서 "청크 X/Y 수신, 결측 인덱스
  [...]"처럼 무엇이 왜 남았는지 보여주고, 진행률 문구도 전송 100% 이후엔
  "저장 처리 중..."으로 구분함. 청크가 애초에 왜 빠졌는지의 근본 원인은
  아직 못 찾음(다음 조사 대상, `docs/multiplayer.md` §8.5-3). 이 과정에서
  검증 스크립트 자체의 람다 캡처 버그(이 세션에서 반복된 함정)를 세 번 더
  잡아 고침. 새 테스트 4개 추가, 전체 665개 통과.
- **후속 버그 수정 4 - 로그 자체가 "보냈다"를 거짓말하고 있었다**: 위
  조사 중 사용자가 "청크 42/42 수신함"을 근거로 유실 없음을 주장했다가
  스스로 "그 로그는 마지막 순번 도착만 본다"고 정정했고, "같은 착각이
  세 번째"라고 지적함(①put_packet 실패를 성공으로 착각 ②"보냈다"를
  "받아서 쓸 수 있다"로 착각 ③이번엔 로그가 "큐에 넣음"을 "보냄"이라고
  찍음). 실제로 서버의 "청크 수신...릴레이" 로그와 클라이언트의 "전송
  요청함" 로그 둘 다 `put_packet()` 성공 여부와 무관하게 큐에 넣는
  시점에 찍히고 있었고, 서버의 "전송 완료" 판정도 수신자에게 실제로
  다 나갔는지와 무관하게 소유자로부터 마지막 순번을 받은 시점에 찍히고
  있었다. `GameClient`/`server_main.gd`의 `_send()`에 `on_sent: Callable`
  을 추가해서 `put_packet()`이 **실제로** 성공하는 순간(즉시든 큐에서
  나중에 빠질 때든)에만 "실제 전송 완료"를 찍게 하고, 서버는 청크×수신자
  개수만큼 실제 송신이 확인된 뒤에만 "전송 완료 확인"을 찍고 다음
  해시로 넘어가도록 고쳤다(`_relay_confirm_state`). 실제 소켓으로 세
  로그(보내는 쪽/서버/받는 쪽)가 청크 번호별로 정확히 맞물려 찍히는 것을
  확인함. 청크 단위 재전송(결측 순번만 다시 요청)은 계획만 세우고 아직
  구현 안 함 - 사용자가 실제 웹 빌드로 재현한 세 로그를 가져오면 이
  로그들로 원인(보내는 쪽/서버/네트워크 중 어디)을 먼저 가린 뒤 설계하기로 함.
- **후속 버그 수정 5 - 결측 청크 단위 재전송(청크 하나가 사라져도 팩
  전체를 포기하지 않게)**: 원인 규명(위 4번)과는 별개로 필요한 개선 -
  받는 쪽이 멈춤을 감지하면(기존 5초 감지 재사용) 빠진 순번만 지정해서
  다시 요청한다(`request_pack_chunks`/`pack_chunks_requested`, 프로토콜
  버전 안 올림). 서버는 바이트를 버퍼링하지 않는 기존 설계를 유지하고
  소유자에게 전달만 하며, `Room.transfer_hash_owners`/`recipients_for_hash()`
  (지나간 해시도 조회 가능)로 "지금 진행 중인 해시"와 "이미 지나간
  해시의 재전송"을 구분해 후자는 진행 판정(`_relay_confirm_state`)에
  관여하지 않는다. 요청 횟수 상한(3회, 클라이언트/서버 양쪽에서 독립
  강제)을 넘기면 기존 타임아웃이 그대로 이어받아 기본 캐릭터로 대체한다.
  멈춤 감지 자체도 `current_waiting_hash` 하나가 아니라 대기 중인 해시
  전부를 매 프레임 독립적으로 검사하도록 바꿨다 - 서버가 청크를 성공적으로
  내보내면 바로 다음 해시로 넘어가므로, 받는 쪽이 결측을 알아챌 때쯤엔
  이미 다음 해시가 current인 경우가 흔해서다. 실제 소켓으로 청크 하나를
  일부러 빼고 전송한 뒤, 재전송 요청 → 소유자가 그 순번만 재전송 →
  최종적으로 기본 캐릭터가 아니라 실제 프로필로 resolve되는 것까지
  확인함. 자세한 설계는 `docs/multiplayer.md` §8.5-5. `Room`의
  `recipients_for_hash()`/`mark_chunk_resend_requested()`를 검증하는
  새 테스트 4개(개별 확인 10건) 추가, 전체 675개 통과.
- **후속 버그 수정 6 - 결측의 진짜 원인 확정: 받는 쪽 WebSocket 버퍼
  초과**: 사용자가 웹 빌드로 재현한 로그(42개 중 16개 결측, 대부분 홀수
  인덱스, 서버→클라이언트 방향만)를 분석해 원인을 확정했다.
  `WebSocketPeer`의 받는 쪽 버퍼(`inbound_buffer_size`) 기본값이
  65,535바이트인데, 청크 32KB를 Base64로 감싸면 약 43.8KB라 한 번에
  하나 반밖에 못 담는다 - 두 개가 연달아 오면 두 번째가 조용히 버려진다
  (예상 손실률 32%가 실제 38%와 비슷했고, "하나 걸러 하나" 무늬도 이걸로
  설명됨). 이 세션의 모든 실제 소켓 검증이 서버·클라이언트 둘 다
  네이티브였다는 게 맹점이었다 - 서버는 항상 네이티브지만 문제를 겪는
  클라이언트는 웹(HTML5) 빌드라, 브라우저의 `WebSocketPeer`(네이티브와
  완전히 다른 구현)에서만 나는 문제를 원래부터 볼 수 없는 구조였다.
  `GameClient.connect_to_server()`가 `create_client()` 전에
  `set_inbound_buffer_size(1MB)`를 설정하고(순서가 중요 - 연결 후 설정은
  적용 안 될 수 있음), 서버도 `_start_server()`에서 같은 값으로 설정했다.
  **사용자가 1MB 빌드로 재전송 요청 0건(결측 자체가 안 생김)으로 성공을
  확인함** - 웹 export에서도 이 설정이 실제로 반영된다는 뜻이다.
  이 조사 과정에서 붙인 계측 셋(대기/꺼냄 개수, decode 실패, 해시별 최대
  대기 개수 요약 - "버퍼 한계 약 23개" 대비)은 전부 `DEBUG_MODE`에 묶여
  릴리스에 영향 없이 그대로 남겨뒀다(2-6 연결 끊김 처리에서 재사용 예정).
  4인 게임 최악의 `state_snapshot`도 실측(693바이트)해서 이 버그가 지금
  당장 게임 진행 메시지에는 영향이 없음을 확인했다. `docs/multiplayer.md`
  §5(TCP라 유실 걱정 없다는 설명이 부정확했음)와 §8.5-3/§8.5-6을 정정함.
- **사용자 확인이 핵심인 것(아직 안 됨)**: 실제 게임 시작 인사가
  P1→P2→... 순서로 양쪽 화면 모두에서 들리는지, 다른 사람의 실제
  초상/보이스가 내 화면에도 보이고 들리는지는 자동 검증으로 확인할 수
  없는 부분이라 **사용자가 직접 실제 클라이언트 2개로 확인해야 한다.**

### 현재 전체 테스트 개수
675개 (`scripts/tests/test_runner.tscn`, 전부 통과).

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

### 디버그 버튼 패널이 화면 밖으로 잘리던 버그(수정)
버튼을 72x22 -> 104x34로 키운 직후, 화면 우하단에 떠야 할 디버그 버튼
패널이 실제로는 화면 밖으로 밀려나 야추 버튼의 좌측 상단 끄트머리만 겨우
보이는 상태였다. 원인: `set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT,
PRESET_MODE_MINSIZE)`를 버튼을 넣기 **전**(크기가 아직 (0,0)일 때) 호출해서,
앵커 사각형 자체가 그 시점의 크기(0,0)로 고정돼버렸다.

고친 방법(`scripts/dev/debug_hotkeys.gd`의 `_build_debug_button_panel()`):
anchor를 전부 1(우하단 모서리)로 두고 `offset_left`와 `offset_right`를
같은 값으로 둬서 앵커 사각형 자체를 폭 0인 점으로 만든 뒤,
`grow_horizontal`/`grow_vertical`을 `GROW_DIRECTION_BEGIN`으로 줘서 나중에
버튼이 늘어나 최소 크기가 커져도 항상 그 점을 기준으로 화면 안쪽(왼쪽/위)으로만
자라게 했다. 이러면 버튼을 넣는 시점이나 창 크기 변화와 무관하게 항상 화면
안에 들어온다 — 데스크톱에서 스크린샷으로 확인함(6개 버튼 전부 여백을 두고
완전히 보임).

### 1-7 완료 요약 — 캐릭터 팩(.ydchar.zip)
- 포맷 문서: `docs/character_pack.md`(manifest.json 스키마, 폴더 구조, 검증
  규칙, 크기 제한을 전부 적어뒀다 — Phase 2에서 이 zip을 네트워크로 그대로
  보낼 예정이라 미리 문서화해야 한다고 판단했다).
- **내보내기**(`CharacterLibrary.export_pack_bytes()`): `ZIPPacker`로
  manifest.json(디스크 파일이 아니라 `profile.to_dict()`로 새로 씀 - 항상
  메모리 상 최신 상태와 일치)과, manifest가 가리키는 파일만(1-6의
  `_referenced_files()`를 export/정리 양쪽이 공유하도록 리팩터링) 담는다.
  데스크톱은 `FileDialog`(저장 모드), 웹은
  `JavaScriptBridge.download_buffer()`로 분기(`character_editor.gd`).
  내보내기 전 저장 안 한 변경사항이 있으면 저장할지부터 물어본다.
- **가져오기**(`CharacterLibrary.import_pack()`): 1-5의 `FilePicker`로 zip을
  고른 뒤 `ZIPReader`로 읽는다. **남이 만든 파일이라 전혀 신뢰하지 않는다** —
  디스크에 한 바이트도 쓰기 전에 다음을 전부 통과해야 한다: manifest.json
  존재 + `CharacterProfile.from_dict()` 스키마 통과, 모든 zip 항목 경로에
  `..`/절대경로/백슬래시 없음(zip slip 방지), 모든 항목 확장자가
  `png/jpg/jpeg/webp/wav/ogg/mp3/json` 화이트리스트 안에 있음, 압축 해제
  누적 크기가 50MB 이하(항목을 하나 읽을 때마다 즉시 검사 - `ZIPReader`에
  압축 해제 전 크기 미리보기 API가 없어서 항목 하나가 거대한 경우까지는 못
  막지만 흔한 "여러 항목의 합" 폭탄은 막는다). 전부 통과하면 id가 겹쳐도
  덮어쓰지 않고 항상 새 id를 발급한다(`_generate_unique_id()` 재사용).
- 편집 화면에 [가져오기]/[내보내기] 버튼 추가. 가져오기 직후 목록을
  새로고침하고 새 캐릭터를 선택 상태로 만든다. `test_character_pack.gd`(13개 -
  왕복 성공/새 id 발급/manifest 없음 거부/스키마 오류 거부/경로 탈출 3종
  거부/확장자 거부)와 `test_character_editor_scene.gd`(씬 로딩 스모크
  테스트)를 추가했다.
- **검증 상태**: 데스크톱에서 실제 클릭으로 내보내기(FileDialog 저장 확인) ->
  가져오기(같은 zip을 다시 열어 새 id로 들어오는 것) -> 정리(삭제)까지
  전부 확인했다. **웹은 아직 실제 브라우저에서 확인 안 됨 - 사용자가 직접
  내보내기(브라우저 다운로드가 실제로 뜨는지)/가져오기를 확인해야 한다.**

### 1-7 후속 — 업로드 용량/크기 제한 (CharacterLimits)
2-5에서 캐릭터 팩을 온라인으로 전송할 때 쓸 크기 제한을 편집 화면 업로드
시점에 미리 반영했다. 상수와 검사 로직은 `scripts/characters/character_limits.gd`
하나에 모았다: 스탠딩 긴 변 2048px/4MB, 썸네일 1024px/1MB, 보이스 1MB,
전체 합계 권장 10MB/경고 15MB. `autoload/asset_loader.gd`의 최후 방어선
(이미지 8MB/오디오 2MB)은 그대로 두고, 이 값들은 항상 그보다 작거나 같아야
한다는 관계를 `test_character_limits.gd`가 회귀 검증한다.

- **픽셀 초과는 거부, 자동 축소 제안**: `image_editor_panel.gd`에서 픽셀
  한도를 넘으면 `Image.resize()`(Lanczos, 원본 비율 유지)로 줄여서 다시
  넣을지 확인 다이얼로그를 띄운다. 원본 확장자 그대로 재인코딩(PNG 무손실,
  JPG/WebP 품질 0.9). 용량만 넘고 픽셀은 정상이면 자동 축소를 제안하지
  않는다(화질만 나빠지고 원인이 해결 안 됨) - WebP 변환 등을 안내만 한다.
- **안내 문구는 항상 3단 구성**: 지금 얼마인지 -> 한도가 얼마인지 -> 어떻게
  줄이는지. "용량이 큽니다" 한 줄짜리 메시지는 쓰지 않는다.
- **보이스는 여러 개를 한 번에 고를 수 있어서** 결과가 파일마다 다를 수
  있다(`voice_mapping_panel.gd`) - 거부/권고 메시지를 모아뒀다가 한 번에
  다이얼로그로 보여준다. WAV는 한도 안에 들어와도 OGG/MP3 변환을 가볍게
  권고한다(거부 아님).
- **캐릭터 전체 합계**를 편집 화면 상단에 항상 표시(`CharacterLibrary.compute_pack_size()`).
  10MB 초과 노랑, 15MB 초과 빨강. 15MB를 넘어도 저장 자체는 막지 않고,
  저장할 때마다 "온라인에서 전송되지 않을 수 있다"고 알려준다.
- **팩 가져오기에도 같은 기준 적용, 단 경고만**: `import_pack()`이 반환하는
  `warning` 필드에 초과 항목을 담아 편집 화면이 안내 다이얼로그로 보여준다 -
  이미 신뢰 검증(경로/확장자/스키마/50MB)을 통과한 팩이라 이제 와서 거부하지
  않는다.
- `format_bytes()`가 원래 항상 MB 단위였는데, 데스크톱에서 실제로 작은
  테스트 이미지(수십 KB)를 올려보니 "0.0MB"로 뭉개져 보이는 걸 발견해서
  1MB 미만은 KB로 표기하도록 고쳤다 - 실제 클릭 테스트로만 잡을 수 있었던
  버그라 기록해둔다.
- 새 테스트 20개(`test_character_limits.gd`) 추가, 전체 423개 통과.
- **데스크톱에서 실제 클릭으로 확인**: 픽셀 초과 이미지 -> 자동 축소 다이얼로그
  -> 축소 후 정상 저장까지, 용량만 초과한 이미지 -> 자동 축소 제안 없이
  거부까지 전부 확인했다. **웹은 아직 확인 안 됨.**

### 1-8 웹 전체 점검 전 사전 정비 (테스트를 방해하는 문제 3가지)
Phase 1을 닫기 전 웹 전체 훑기(`docs/web_verification_checklist.md`)를
시작하기 직전에, 테스트 자체를 방해할 만한 문제 둘을 먼저 고쳤고 하나는
보류했다.

1. **AssetLoader LRU 캐시에 메모리 기준 상한 추가(고침)**: 캐릭터를 여러 개
   바꿔가며 보는 게 이번 테스트의 핵심 시나리오라 정확히 이 캐시를 채우는
   상황이었다. 개수 상한(64개)만으로는 실제 메모리와 안 맞아서(디코딩된
   Texture2D는 2048x2048 RGBA 한 장에 16MB) 브라우저 탭이 죽을 위험이
   있었다. `AssetLoader.CacheState`(내부 클래스)를 새로 만들어 텍스처
   캐시 150MB/오디오 캐시 50MB 상한을 개수 상한과 병행 적용한다(둘 중
   하나라도 넘으면 오래된 것부터 지움). 이미지는 `width*height*4`로,
   오디오는 원본 바이트 크기로 추정한다(OGG/MP3는 재생 시점에 스트리밍
   디코딩해서 상주 메모리가 압축 크기에 가깝고, WAV는 애초에 압축이
   거의 없어 원본 크기가 곧 데이터 크기에 가까움 - 코드 주석에 이유 남김).
   `get_cache_stats()`로 현재 사용량을 조회할 수 있고, `DEBUG_MODE`일 때
   화면 우하단 디버그 버튼 위에 "캐시: 이미지 N개/XMB, 오디오 N개/XMB"로
   1초마다 갱신 표시한다(`debug_hotkeys.gd`) - 데스크톱에서 실제로 캐릭터를
   선택해보며 텍스처 3개/39.2MB로 정상 집계되는 것까지 확인함. 새 테스트
   `test_asset_loader.gd` 추가.
2. **DebugInitLog가 무한히 자라던 문제(고침)**: `Main.gd`의 화면 좌상단
   진단 로그가 게임을 새로 시작할 때마다 계속 append만 하고 안 지웠다.
   최근 `DEBUG_LOG_MAX_LINES`(30)줄만 배열로 들고 있다가 매번 통째로
   다시 그리는 방식으로 바꾸고, `_start_new_game()` 맨 앞에서
   `_clear_debug_log()`로 이전 판 로그를 비운다. 새 테스트
   `test_debug_log.gd` 추가.
3. **메인 스레드 동기 처리(이미지 리사이즈, 팩 압축/해제)는 일단 보류**:
   실제로 몇 초나 멈추는지 이번 웹 테스트에서 체감해보고 판단하기로 함.
   대신 "아무 반응 없이 멈추면 고장난 줄 안다"는 우려에 대응해, 버튼
   문구를 "처리 중..."/"내보내는 중..."/"가져오는 중..."으로 바꾸고
   `await get_tree().process_frame`로 한 프레임 기다린 뒤에 실제 무거운
   작업을 시작하도록 `image_editor_panel.gd`/`character_editor.gd`를
   고쳤다 - await 없이 바로 무거운 작업을 하면 문구가 바뀌었다는 사실
   자체가 화면에 그려지기 전에 멈춰서 사용자에게는 버튼이 안 눌린 것처럼
   보인다.

전체 테스트 446개 통과.

### 1-4C: 게임 시작 인사를 플레이어 순서대로 순차 재생 + 소개 연출
예전엔 게임이 시작되자마자 플레이어 1의 인사만 재생되고(우선순위 때문에
`turn_started`("내 차례") 보이스가 조용히 씹혔다) 바로 플레이 가능한
상태였다. 이제는: 게임 시작 → 입력 전체 차단 → 플레이어 1부터 순서대로
인사 보이스를 하나씩(절대 안 겹침, 끝나면 0.3초 쉬고 다음) 재생하면서 그
플레이어로 큰 슬롯을 전환(1-3 크로스페이드 재사용) → 전부 끝나면 첫 턴
플레이어(0번)로 복귀하고 입력 해제. 두 차례 반복해서 다듬은 최종 구조는
다음과 같다.

**보이스는 전역으로 한 번에 하나만 재생된다** - 원래는 슬롯(플레이어)별로
우선순위를 비교해서, 서로 다른 플레이어의 보이스끼리는 비교 자체가 없어
동시에 났다(예: 야추 포기 보이스와 다음 플레이어의 "내 차례"가 겹침).
`VoiceBank`에 `_global_active_player`/`_global_active_priority`(전역 상태)와
`_pending_request`(대기 하나)를 두고, 모든 재생 요청이 `_request_voice()`
하나만 거치도록 통일했다:
- 아무것도 안 나고 있으면 즉시 재생.
- 재생 중인 것보다 우선순위가 높으면 즉시 교체(0.1초 페이드아웃 후 전환 -
  기존 방식 그대로, 다만 이제 슬롯이 달라도 적용됨). 페이드 도중 또
  교체되면 진행 중이던 트윈을 먼저 kill한다(안 그러면 볼륨이 튐).
- 같거나 낮으면 대기열에 하나만 넣는다(기존 대기와 우선순위 비교해서 높은
  쪽만 남김).
- 대기가 `VOICE_WAIT_TIMEOUT_MSEC`(1.5초, 상수)를 넘기면 재생 안 하고
  버린다 - 때를 놓친 대사("이미 주사위를 굴린 뒤에 나오는 내 차례!")는
  안 하는 게 낫다. `DEBUG_MODE`일 때 버려질 때마다 `[VoiceBank] xxx 대기
  N초 초과로 버림` 로그를 남긴다 - 1.5초 값을 실측으로 조정할 때 쓴다.

**인사/승패 시퀀스도 이 경로 하나만 탄다.** 원래 인사·승패·일반 요청이 각자
`AudioStreamPlayer.finished`를 따로 구독해서, 게임이 끝나는 순간(직전
보이스를 WIN이 교체하고, WIN이 끝나는 시점에 "대기열 확인"과 "LOSE 재생"이
동시에 반응할 수 있는 상황)처럼 여러 경로가 겹칠 위험이 있었다. 이제
`finished`를 구독하는 곳은 `configure()`가 연결하는 `_on_slot_finished`
하나뿐이다 - 인사(`_greeting_step_index`)와 승패(`_ending_step_player`)는
"지금 몇 번째 단계인지"만 들고 있다가, 자기 단계가 끝났다는 통보를 받으면
`_request_voice()`로 다음 단계를 요청할 뿐이다. 게임 로직(game_state)은
전혀 안 건드리므로 턴 진행이 오디오를 기다리는 일은 없다 - Phase 2에서
서버가 턴을 관리해도 문제없다.

**건너뛰기는 버튼으로만.** 처음엔 화면 클릭/아무 키로도 건너뛰게 했다가,
연출을 보고 싶은 사람이 실수로 건너뛸 수 있어서 [인사 건너뛰기]
버튼(`InputBlocker`의 자식, 화면 상단 중앙 - 디버그 버튼과도 초상화와도
안 겹침) 전용으로 바꿨다. 연출 중엔 `_unhandled_input()`이 키보드 입력을
전부 삼킨다(ESC 포함 - 연출이 끝나면 원래대로 종료 확인으로 돌아옴).

- **매핑 없는 플레이어는 대기/화면전환 없이 바로 다음**으로 건너뛴다.
  **전원이 매핑 없으면**(내장 기본 캐릭터만 있는 경우 등) `play_greeting_sequence()`가
  재귀 호출로 그 자리에서 끝까지 돌아 `greeting_sequence_finished`까지
  동기적으로 emit하므로, `Main.gd`가 그 직전에 켠 입력 차단이 같은 프레임
  안에서 도로 꺼져 화면엔 전혀 안 보인다 - 별도 분기 없이 자연히 성립.
- **까다로웠던 버그(사전에 잡음)**: `AudioStreamPlayer.stop()`은 `finished`를
  emit하지 않는다. 건너뛰기가 그냥 `.stop()`만 부르면 전역 상태가 정리 안 돼
  영원히 "재생 중"으로 남는다 - `request_skip_greeting()`이 `_on_slot_finished`가
  했을 일을 직접 해준다.
- **DEBUG_MODE 디버그 버튼과의 충돌 방지**: 인사 연출 중엔
  `debug_hotkeys.greeting_active`를 true로 세팅해서 디버그 버튼/단축키가
  전부 무시된다.
- **덤으로 고친 잠복 버그**: `debug_hotkeys.gd`가 `DEBUG_MODE=false`일 때
  자기 자신을 `queue_free()`했는데, `Main.gd`가 들고 있는 `@onready var
  debug_hotkeys` 참조가 나중에 유효하지 않게 될 수 있었다(이번 세션 내내
  `DEBUG_MODE=true`라 한 번도 실제로 안 걸렸던 버그). 이제는 노드를 지우지
  않고 `_ready()`/`_input()`이 그냥 아무 것도 안 하게만 만들어서 참조가
  항상 유효하다.
- 새 테스트 14개(`test_voice_bank.gd` - 전역 재생 조정을 화이트박스로 검증:
  즉시 재생/교체/대기/대기 우선순위 비교/타임아웃 폐기) 추가, 전체
  465개 통과. 실제 음성 타이밍/순서는 자동 테스트로 검증 못 하므로(이
  파일의 기존 방침) 데스크톱에서 직접 듣고 보는 확인이 필요하다 -
  **아직 확인 못 함**(자동화 시도 중 공유 데스크톱의 다른 창과 충돌
  위험이 있어 중단함). 포트레이트 전환(0.3초 페이드)과 보이스 시작이
  동시에 걸리는 타이밍은 사용자 요청대로 조정 없이 그대로 뒀다 - 어색하면
  다음에 조정.

### 참고: export_presets.cfg가 세션 중 자동으로 바뀜
1-8 사전 작업에서 `CharacterLimits` class_name 등록을 위해 에디터를 헤드리스로
한 번 띄운 적이 있는데(`godot --headless --editor --quit-after 3`), 그때
Godot이 `export_presets.cfg`를 최신 스키마로 자동 정리한 것으로 보인다
(`export_path`가 절대경로에서 상대경로로 바뀌는 등 - 다행히 같은 위치
`F:/Godot/web_build/`를 가리켜서 실제 export 결과는 안 바뀌었다. CLI로
export할 때 항상 출력 경로를 명시적으로 넘겨서(`--export-release "Web"
"F:/Godot/web_build/index.html"`) 이 파일의 값과 무관하게 동작한다).
`variant/thread_support=false`는 그대로 유지됨을 확인함. 의도한 변경이
아니라 여기 기록만 해둔다 - 문제 되면 알려주기 바람.

### 2-1(GameState headless 검증) 완료 요약
- **`GameState.auto_confirm_least_damaging(player_index) -> int`** (`scripts/game_state.gd`)를
  신설해서, `docs/multiplayer.md` §6에서 정한 대로 "반응 없는 플레이어 대신
  안전하게 한 수 두기" 판단 로직을 GameState 정식 함수로 승격했다. 화면도
  네트워크도 필요 없는 순수 규칙 로직이라 여기 있어야 디버그 빌드 플래그와
  무관하게 항상 동작한다(디버그 전용 파일에 있으면 배포 빌드에서 죽는다).
  - 판단 기준: 아직 안 굴렸으면 정확히 한 번만 굴리고(리롤 없음) → 미확정
    칸 중 지금 다이스로 최고점 칸을 고름 → 전부 0점이면 **카테고리 인덱스가
    가장 낮은 칸**을 포기(비교를 `>`로만 해서 동점이면 먼저 본 것이 유지되게
    구현 — 재현 가능한 결정적 동작을 위한 명시적 타이브레이크 규칙).
  - `debug_hotkeys.gd`의 `_auto_confirm_one()`/`_auto_finish_game()`은 이제
    이 함수를 부르기만 하는 얇은 껍데기고, 옛 판단 로직(`_ensure_rolled()`/
    `_find_open_category()`)은 삭제했다.
  - 새 테스트 6개(`scripts/tests/suites/test_auto_confirm.gd`): 안 굴린
    상태면 정확히 한 번만 굴리는지, 같은 시드·같은 상황에서 결정적인지,
    전부 0점이면 가장 낮은 인덱스를 포기하는지, 남은 칸이 하나뿐이면 그걸
    고르는지, 최고점 칸을 고르는지, `game_state.gd` 소스 자체가
    `DEBUG_MODE`/`BuildInfo`를 참조하지 않는지(코드 수준 회귀 테스트).
- **`server_main.gd` + `server_main.tscn`**: GameState를 화면 없이 콘솔에서
  끝까지 돌려보는 headless 진입점. 실행 명령:
  `godot --headless --path . res://server_main.tscn -- <인원수>`
  (인원수 생략 시 기본 2). 명령: `roll` / `hold <번호...>` / `score <족보키>`
  / `state` / `auto` / `quit`. 규칙 위반(안 굴린 상태에서 확정 시도, 이미
  확정된 칸, 리롤 초과, 범위 밖 주사위 번호, 알 수 없는 족보/명령 등)은
  전부 크래시 없이 한국어 에러 메시지를 찍고 계속 진행하도록 만들었고,
  자동 진행 명령(`auto`) 24회로 2인 게임을 끝까지 돌려 승자 출력까지
  실제로 확인했다(공동 우승은 `get_winners()`가 동점자를 전부 모아주는
  기존 구현을 그대로 재사용해서 별도 분기가 필요 없었다).
  - **주의(다음에 비슷한 걸 만들 때 참고)**: `OS.read_string_from_stdin()`은
    줄 단위가 아니라 그 순간 버퍼에 들어와 있는 만큼을 통째로 돌려준다.
    명령을 빠르게 이어 보내면(테스트용 파이프 입력 등) 한 번의 호출에
    여러 줄이 개행 문자와 함께 섞여 들어와서, 이를 한 줄짜리 명령으로
    착각하면 "알 수 없는 명령"으로 통째로 실패한다 - 읽은 덩어리를 직접
    `\n`으로 잘라 큐에 쌓아두고 하나씩 처리하도록 고쳐서 해결했다.
  - **서버 RNG 시드를 `Crypto.generate_random_bytes()`로 교체**(후속 수정):
    처음엔 "`randomize()`가 이 환경에서 멈춘다"고 오판해서
    `Time.get_ticks_usec()` 기반 시드로 피해갔는데, 사용자가 지적한 대로
    이건 서버에서 쓰면 안 되는 방식이었다 - 서버가 언제 켜졌는지 대충
    알면 시드 범위가 좁혀지고, 시드를 알면 앞으로 나올 주사위를 전부
    계산할 수 있어서 "서버가 굴리니까 치팅 불가능"이라는 Phase 2의
    전제(`docs/multiplayer.md` §0) 자체가 무너진다. `Crypto` 클래스와
    `generate_random_bytes()`가 이 Godot 4.7 빌드에 실제로 존재/동작하는
    것을 `--headless --script`로 직접 확인한 뒤(2회 호출로 서로 다른
    바이트가 나오는 것까지 확인), `server_main.gd`에 8바이트를 받아
    64비트 정수로 접어 `RandomNumberGenerator.seed`에 넣는
    `_generate_secure_seed()`를 추가했다. **웹 export 호환 여부는 따로
    검증하지 않았다** - `docs/multiplayer.md` §0에 서버는 항상 네이티브
    headless 바이너리로만 돌고 Web export는 클라이언트 전용이라고 이미
    못박혀 있어서, 이 함수는 `server_main.gd`(서버 전용 진입점)에만 있고
    클라이언트가 쓰는 `Main.gd`의 로컬 싱글 모드는 손대지 않았다(거긴
    `GameState._init()`이 여전히 자체 `randomize()`를 쓴다 - 겨룰 상대가
    없는 로컬 플레이라 시드 예측 가능성이 문제되지 않는다).
  - **정정: `randomize()`는 안 멈춘다.** 같은 방식(`--headless --script`)으로
    `randomize()`만 따로 다시 불러보니 즉시 리턴했다 - 처음에 겪은 "멈춤"은
    `randomize()`가 아니라 `OS.read_string_from_stdin()`이 파이프로 빠르게
    이어 보낸 여러 줄을 한 번에 통째로 읽어버려서, 그 한 번의 읽기를 처리한
    뒤 stdin이 이미 바닥났는데 다음 읽기를 무한정 기다리며 멈춘 것이었다
    (바로 위에서 이미 고친 버그와 같은 원인). 다음에 비슷한 멈춤을 만나면
    `randomize()`부터 의심하지 말고 입출력 버퍼링을 먼저 볼 것.
- **보고: GameState의 UI 의존 여부** — `scripts/game_state.gd` 전체를
  다시 읽어 확인한 결과 **UI/Node 의존 없음**. `RefCounted`이고 상태
  갱신은 전부 공개 필드·메서드로, 외부 통지는 전부 `GameEvents` 시그널
  방출로만 한다. Phase 0에서 이미 제대로 분리되어 있었고, 이번 headless
  검증으로 실제 동작까지 확인됨 - 서버로 옮겨도 터질 UI 참조가 없다.

### 남은 단계
- 1-4C 실제 확인: 인사 보이스가 매핑된 캐릭터로 2인 이상 게임을 시작해서
  순서/간격/전환/건너뛰기(버튼)/디버그 버튼 무시/보이스 안 겹침(야추 포기
  직후 다음 플레이어 턴 시작 등)을 직접 듣고 보고 확인.
- 1-8: `docs/web_verification_checklist.md`대로 웹 전체 점검(사용자가 직접
  브라우저에서 진행 중) - 캐릭터 편집 화면, 캐릭터 팩, 업로드 제한, 시크릿
  모드, 오디오 자동재생 정책, 메모리, 창 크기 변경까지.
- 2-4B/2-4C 실제 확인: 실제 보이스가 있는 캐릭터로 온라인 방을 만들어서
  내 턴에 "내 차례" 보이스가 들리는지, 주사위를 고정할 때 홀드
  효과음이 나는지(2-4C가 고친 것), 초상화가 뜨는지 직접 확인.
- 2-5 실제 확인(핵심 성공 신호): 서로 다른 커스텀 캐릭터를 고른 2~4인이
  실제로 온라인 방에서 만나, 게임 시작 인사가 P1→P2→... 순서로 **양쪽
  화면 모두**에서 들리는지, 다른 사람의 실제 초상/보이스가 보이고
  들리는지 사용자가 직접 확인.
- Phase 2: 온라인 멀티플레이 (2-1·2-3·2-4·2-4B·2-4C·2-5 완료 - 실제
  주사위 진행이 서버 권위로 동작하고, 내 캐릭터도 온라인에 연결됐고,
  GameEvents 릴레이가 전수 조사를 거쳐 빠짐없이 나가고, 캐릭터 팩까지
  실제로 전송된다). 다음은 2-6(연결 끊김 처리 - 재접속 토큰 실제 매칭,
  AFK 자동 진행, 턴 제한 시간).
