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
- **원칙 1 관련 미검증 사항**: `project.godot`에 `3d/physics_engine="Jolt Physics"`가 설정되어 있는데, 이 프로젝트가 실제로 3D 물리를 쓰는지, Jolt Physics가 HTML5 export에서 정상 동작하는지 아직 한 번도 확인된 적이 없다. HTML5 export 프리셋도 아직 구성되어 있지 않다(`export_presets.cfg` 없음).
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

### 한글 폰트(Pretendard) 관련 참고
- 파일: `assets/fonts/Pretendard-Regular.otf`, `Pretendard-Bold.otf`, `LICENSE.txt`(SIL OFL 1.1 원문 — 배포 시 저작권 표기에 씀). Pretendard 1.3.9, npm 패키지의 정적 otf 빌드(jsdelivr CDN에서 받음). OFL이라 상업적 재배포·번들 전부 허용.
- 적용 위치: `project.godot`의 `[gui] theme/custom_font="res://assets/fonts/Pretendard-Regular.otf"` — 프로젝트 전체 기본 폰트라 개별 라벨에 지정할 필요 없음.
- Bold가 실제로 필요한 곳은 확정된 점수 라벨(`Main.gd`의 `_refresh_scoreboard_ui`, `bold_font` 사용) 한 곳뿐이었다. `bold_font`는 원래 `ThemeDB.fallback_font`에 `variation_embolden`을 걸어 합성한 가짜 볼드였는데(한글 폰트가 없던 시절의 임시방편), 이제 `Pretendard-Bold.otf`를 직접 로드하도록 바꿨다(`Main.gd`의 `BOLD_FONT_PATH` 상수). 특수 족보 연출 라벨(`special_hand_label`)은 font_size만 키운 것이라 애초에 볼드가 아니었다.
- 웹 빌드 전체 용량(릴리스, Thread Support 끈 상태): `index.wasm` 39.5MB + `index.pck` 2.55MB(폰트 포함 게임 리소스) + 나머지(js/아이콘) ~0.3MB = **총 약 41MB(42,398,023바이트)**. 96%가 Godot 엔진 wasm 자체라 폰트가 차지하는 비중은 크지 않다. 용량 최적화는 나중에 별도로 할 일.
- `export_presets.cfg`는 `.gitignore` 대상이라 저장소에 없다. 다음 세션에서 다시 필요하면: 플랫폼 Web, `variant/thread_support=false`(이유는 위 1-5 절 참고), 나머지는 에디터 `프로젝트 > 내보내기`의 기본값 그대로 두면 된다.

### 1-5(파일 선택) 상태 — 다음에 이어서 할 일
- 데스크톱 구현(FilePickerDesktop)은 검증 완료: FileDialog 시그널을 시뮬레이션해서 실제 파일을 백그라운드 스레드로 읽고, 확장자 필터링, 취소까지 전부 windowed 실행으로 확인했다.
- **웹 구현(FilePickerWeb)은 아직 실제 브라우저에서 테스트하지 못했다 — 다음 세션에서 가장 먼저 할 일이다.** JavaScriptBridge API 존재 여부는 ClassDB로 확인했지만, 실제 브라우저에서 파일 선택창이 뜨는지·취소 감지가 동작하는지는 검증되지 않았다.
- 브라우저 검증용으로 `scenes/dev/file_picker_test.tscn`(+`.gd`)을 만들어 뒀다. 이미지/오디오 고르기 버튼, 결과 목록(파일명·크기·AssetLoader 디코딩 성공 여부, 이미지 미리보기, 오디오 재생 버튼), 화면 하단 로그(웹 콘솔 대신 화면에 직접 찍음)까지 이 씬 하나로 "선택 → 바이트 → 텍스처/오디오" 전체 경로를 확인할 수 있다. `godot --headless ... file_picker_test.tscn --quit-after 1`로 에러 없이 로드되는 것까지만 확인했고, 실제 브라우저 동작은 미검증.
- Web export의 **Thread Support는 꺼도 된다**: 저장소에서 `Thread`를 쓰는 곳은 `FilePickerDesktop` 하나뿐이고 `FilePicker.create()`가 웹에서는 `FilePickerWeb`을 골라 그 코드 자체가 실행되지 않는다(AssetLoader/VoiceBank/SfxBank도 전부 동기 코드). 켜면 COOP/COEP 헤더가 필요해 서버 설정만 복잡해진다.
- `scripts/io/`, `scripts/tests/suites/test_file_picker.gd`, `scenes/dev/`는 이 섹션을 쓰는 시점 기준 아직 커밋되지 않았다(`git status`로 확인할 것).

### 웹 테스트 절차
1. `project.godot`의 `run/main_scene`을 잠시 `res://scenes/dev/file_picker_test.tscn`으로 바꾼다(에디터 `프로젝트 > 프로젝트 설정 > Application > Run > Main Scene`에서 바꾸거나, `project.godot` 파일을 직접 편집). **테스트 끝나면 `res://scenes/Main.tscn`으로 반드시 되돌릴 것.**
2. Godot 에디터 `프로젝트 > 내보내기`에서 Web export 프리셋을 추가한다(export template 설치 필요). Thread Support는 위 이유로 꺼둔다.
3. export한 폴더를 정적 파일 서버로 서빙한다 — `file://`로 직접 열면 브라우저가 막는다: `python -m http.server 8060` 후 `http://localhost:8060/`로 접속.
4. `file_picker_test.tscn`의 버튼을 **실제로 마우스로 클릭**해서 테스트한다 — 자동화 스크립트로 흉내 낸 클릭은 브라우저가 파일 선택창을 막을 수 있어서 의미가 없다(이번 구현이 지키려는 바로 그 제약).
5. 확인 포인트: 파일 선택창이 뜨는지 / 여러 개 골랐을 때 다 들어오는지 / 취소 시 로그에 "취소됨"만 남고 에러가 없는지(개발자 도구 콘솔도 같이 확인) / 허용 안 한 확장자를 억지로 골라도 걸러지는지 / 이미지 미리보기와 오디오 재생이 실제로 되는지.

### 현재 전체 테스트 개수
373개 (`scripts/tests/test_runner.tscn`, 전부 통과 — 이 중 FilePicker 쪽 12개는 위에서 말했듯 아직 미커밋 상태일 수 있다).

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
