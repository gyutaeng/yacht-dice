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
- 1-5: FilePicker(데스크톱/웹 파일 선택 추상화) — **완료. 데스크톱·웹 양쪽 실제 브라우저/앱에서 검증됨.**

### 1-5(파일 선택) 완료 요약
- 데스크톱: `FilePickerDesktop`(Godot `FileDialog` + 백그라운드 스레드 읽기)으로 검증 완료.
- 웹: 자체 JS 브릿지(JavaScriptBridge.create_callback)로 여러 번 시도했지만 "선택창은 뜨는데 콜백이 Godot으로 안 돌아옴" 문제를 못 잡아서(콜백 GC 수정, try/catch, 네이티브 cancel 이벤트 등 다 시도했지만 실패), 검증된 애드온 [`godot-file-access-web`](https://github.com/Scrawach/godot-file-access-web)(Scrawach, MIT License)로 교체해서 해결했다. `addons/FileAccessWeb/core/file_access_web.gd`에 수정 없이 벤더링, `scripts/io/file_picker_web.gd`는 이를 부르는 얇은 껍데기. **사용자가 실제 브라우저에서 파일 선택 정상 동작 확인함.**
- `FilePicker` 공개 인터페이스(`create()`/`pick_files()`/`files_picked`/`pick_cancelled`/`debug_log`)와 `_finalize_pick()`, 데스크톱 구현은 이 과정에서 전혀 안 바뀜.
- **알려진 제약**: 웹에서는 한 번에 파일 1개만 선택 가능(애드온 자체 한계). 데스크톱은 다중 선택 그대로 지원. 1-6 UI 설계 시 감안할 것.
- 웹 export 관련 문제(한글 폰트 깨짐, 빌드 캐시 구분, 콘솔 로그 안 보임 등)와 해결·절차는 전부 `docs/web_export.md`에 정리했다 — 다음에 웹 export를 다시 만질 때는 여기부터 읽을 것.
- 부수적으로 만든 것: `addons/build_stamp`(export할 때마다 빌드 시각 자동 기록) + `BuildInfo` autoload(게임 시작 시 콘솔/브라우저 배너에 빌드 시각 표시) — 자세한 내용은 `docs/web_export.md`.
- Pretendard 폰트(OFL-1.1, `assets/fonts/`)를 프로젝트 기본 폰트로 지정해서 한글 렌더링 문제도 이때 같이 해결(데스크톱·웹 둘 다 확인 완료).

### user:// 웹 영구 저장 검증 (1-6 준비)
- 1-6에서 캐릭터를 `user://`에 저장할 예정이라, 웹에서 `user://`가 새로고침 후에도 실제로 유지되는지(Godot 웹은 IndexedDB 기반 영구 저장소를 씀) `file_picker_test.tscn`에 검증 UI를 추가했다: `[저장 테스트]`(현재 시각을 `user://web_persistence_test.txt`에 기록) / `[불러오기 테스트]`(읽어서 화면 로그에 표시) 버튼, 그리고 화면이 뜰 때 자동으로 한 번 읽어서 이전 값이 있으면 보여준다(새로고침 전/후 값을 비교하면 유지 여부가 바로 확인됨).
- **이 세션에서는 코드만 추가하고 export까지 했다 - 사용자가 브라우저에서 직접 새로고침해가며 확인하기로 함(아직 결과 모름).** 결과에 따라 1-6 설계가 갈린다: 안 되면 캐릭터 저장 방식 자체를 다시 생각해야 함.

### 다음 할 일 (순서대로)
1. **아직 하지 않음**: 메인 씬을 `file_picker_test.tscn`에서 원래 게임 화면(`res://scenes/Main.tscn`)으로 되돌리기 — user:// 검증 결과를 확인한 뒤에 할 것(사용자 요청으로 보류 중). **테스트 씬 자체는 지우지 말 것** — 1-8(웹 빌드 최종 검증)에서 다시 쓴다.
2. 그다음 1-6부터(아래 "남은 단계" 참고).

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
