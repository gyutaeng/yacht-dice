## 프로젝트

Godot 4.7 / GDScript로 만드는 요트다이스 보드게임. 플레이어가 직접 올린 PNG 스탠딩 일러스트와 WAV 보이스로 캐릭터를 커스텀하는 것이 핵심 기능. 추후 리치마작으로 확장 예정.

## 🚨 저장소 2개 - 절대 섞으면 안 됨

- **`F:\Godot\web_build`** → `gyutaeng/Custom-YatchDice-game`(공개, GitHub Pages 배포용 - **빌드된 클라이언트만** 들어있음)
- **이 디렉터리(프로젝트 루트, `F:\Godot\Project\yacht-dice`)** → `gyutaeng/yacht-dice`(비공개, Render 서버 배포용 - **소스 전체 + Dockerfile**)

**이유**: 소스와 Dockerfile을 공개 저장소(`Custom-YatchDice-game`)에 올리면 서버 소스 전체가 공개된다 - 두 저장소는 반드시 이 매핑 그대로 유지할 것.

**정정(원래 "과거 사고 기록"이었던 내용, 취소됨)**: `spr_betako_icon.png`을
죽은 파일로 오판해서 한 번 삭제했다가 되돌렸다 - **실제로는
`project.godot`의 `config/icon`(앱/창 아이콘)이 `uid://6hpay5ra0c7b`로
이 파일을 가리키고 있는, 살아있는 필수 에셋이다.** 삭제한 채로 export를
시도해보고서야("Unrecognized UID" 에러로 export 자체가 깨짐) 발견했다 -
처음 감사할 때 `.gd`/`.tscn` 안의 문자열만 grep해서 "코드 어디서도
참조 안 됨"이라고 판단한 게 잘못이었다(project.godot은 파일을 경로
문자열이 아니라 UID로 참조하고, `.import` 사이드카 파일이 트래킹돼
있다는 것 자체가 "정식으로 쓰이는 리소스"라는 신호였는데 놓쳤다). 앞으로
어떤 파일이 진짜 안 쓰이는지 판단하려면 문자열 grep만으로 부족하고,
`project.godot`/`.tscn`의 UID 참조까지 같이 확인해야 한다. **재발 방지로
추가한 `.gitignore`의 저장소 루트 한정 이미지/오디오 확장자 규칙은
그대로 유지한다** - 하위 폴더(`assets/`, `characters/` 등)의 정상 에셋에는
영향 없고, 새 아이콘/에셋을 루트가 아니라 `assets/` 아래 두는 게 앞으로도
맞는 방향이다.

## 🌿 브랜치 워크플로우

`main`이 이 저장소(`gyutaeng/yacht-dice`)의 유일한 배포 기준이고 Render는
`main`만 본다. 예전엔 `step/1-N-이름` 브랜치 하나에서 계속 커밋을 이어가다가
가끔 `main`으로 fast-forward하는 식이었는데, 세션이 여러 번 지나며 브랜치
이름이 실제 작업 내용과 완전히 무관해지고(`step/1-5-file-picker`라는 이름의
브랜치에 2-1부터 2-7까지, 즉 캐릭터 팩·온라인 멀티플레이·Render 배포 준비까지
전부 쌓여 있었다) `main`이 여러 세션 동안 뒤처진 채로 방치된 적이 있다(2026-09-17,
10개 커밋 차이). **앞으로는 작업을 `main`에 직접 하거나, 그 작업 단계의 이름에
맞는 새 브랜치를 그때그때 파서 끝나면 바로 `main`으로 fast-forward + push한다** -
이름이 안 맞는 옛 브랜치를 계속 이어 쓰지 않는다. 완전히 선형이고 `main`이 뒤처진
쪽뿐이면(분기 없음) fast-forward는 히스토리를 안 건드리는 안전한 작업이다.

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
- **커밋 시 `git add .`/`git add -A` 같은 포괄 추가를 쓰지 않는다 -
  변경한 파일을 항상 이름으로 명시해서 스테이징한다.** 저장소 루트에
  실수로 떨어진 파일(예: 수동 검증 중 만든 캐릭터 아이콘)이 포괄
  추가에 쓸려 들어가 비공개 저장소에 커밋된 적이 있다(아래 "저장소
  2개" 절 참고) - `.gitignore`로 흔한 확장자는 막아뒀지만, 그것과
  무관하게 애초에 포괄 추가 자체를 안 쓰는 게 근본 대책이다.
- **Godot 프로젝트에서 "이 파일이 안 쓰인다"는 grep만으로 판단하면 안
  된다.** `project.godot`은 리소스를 경로 문자열이 아니라 UID
  (`uid://...`)로 가리키므로 파일명으로 아무리 grep해도 안 걸린다 -
  `.import`/`.tscn`의 참조도 마찬가지로 UID 기반이라 같은 함정이 있다.
  그래서 삭제 판단의 기준은 "코드에서 참조가 안 보인다"가 아니라
  **"삭제한 뒤 실제로 export가 통과하는지"**여야 한다 - grep은 후보를
  좁히는 용도로만 쓰고, 최종 확인은 항상 실제 export(또는 최소한
  프로젝트를 다시 여는 것)로 한다. 실제 사례: `spr_betako_icon.png`을
  "코드 어디서도 참조 안 되는 죽은 파일"로 grep만으로 판단해 삭제했다가,
  실제로는 `project.godot`의 `config/icon`(앱/창 아이콘)이 UID로 이
  파일을 가리키고 있어서 export가 "Unrecognized UID" 에러로 깨졌다 -
  삭제 후 export를 실제로 돌려보고서야(사용자 지적: "어떻게
  확인했는지"를 먼저 되물었어야 했다) 발견했다.

## 현재 어긋나 있는 부분

`scenes/Main.gd`(현재 유일한 스크립트)를 기준으로 확인한 목록. 아직 고치지 않았다.

- **원칙 2 위반 (GameState/UI 미분리)**: `Main.gd` 하나가 주사위 값·리롤 횟수·플레이어별 확정 점수 같은 게임 상태와, `Label`/`Button` 노드 조작을 모두 함께 가지고 있다. 예를 들어 `_roll_dice()`(117~123행)는 `dice_results` 배열을 갱신하면서 동시에 `dice_labels[i].text`를 직접 쓰고, `_on_confirm_pressed()`(173~190행)도 `player_confirmed_scores`를 갱신하면서 `score_labels[index].text`와 `confirm_buttons[index].disabled`를 같은 함수 안에서 직접 건드린다. GameState 역할과 UI 역할이 분리된 별도 노드/클래스가 없고, 시그널을 거치지 않고 서로 직접 참조한다.
- **원칙 4 위반 (RNG 미주입)**: `_roll_dice()`(121행)에서 전역 함수 `randi_range(1, 6)`을 직접 호출한다. 주입받은 `RandomNumberGenerator` 인스턴스가 어디에도 없다.
- **원칙 5 위반 (GameEvents 싱글톤 부재)**: 프로젝트에 autoload 싱글톤 자체가 하나도 없다(`project.godot`에 `[autoload]` 섹션 없음). 버튼 클릭은 `Main.gd` 내부 핸들러에 바로 연결되어 있고(예: 55~56행, 166행), 턴 전환·점수 갱신도 전부 `Main.gd`가 자기 자신의 함수를 직접 호출하는 방식(`_switch_to_player()`, `_update_score_previews()` 등)이라 방출자/구독자 구분이 없다.
- **원칙 1 관련 미검증 사항**: `project.godot`에 `3d/physics_engine="Jolt Physics"`가 설정되어 있지만, 프로젝트 전체에 `Node3D` 계열 노드가 하나도 없어(주사위도 2D `Label`) 실제로 3D 물리를 쓰지 않는 죽은 설정이다 — 그래서 Jolt가 HTML5에서 되는지 자체가 지금은 의미 없는 질문이다. HTML5 export 프리셋은 1-5B(폰트) 작업 때 만들어서 저장소에 커밋되어 있다(`export_presets.cfg`).
- **원칙 3·6은 현재 해당 사항 없음**: 파일 업로드/에셋 로딩 기능 자체가 아직 구현되지 않아 위반 여부를 판단할 코드가 없다. 해당 기능을 만들 때부터 원칙 3(PackedByteArray 기준)·6(화이트리스트/크기 검사)을 지켜야 한다.

## 현재 진행 상황

*큰 작업이 끝날 때마다 이 섹션을 갱신한다. 새 세션에서 이어갈 때는 여기부터 읽는다.*

### 📍 지금 상태 요약 (2026-09-16 기준 - 새 세션은 여기부터 읽을 것)

- **`v0.3-online` 태그까지 완료.** 로컬 2~4인, 캐릭터 커스텀(스탠딩
  이미지/썸네일/보이스, 팩 내보내기·가져오기), 온라인 대전(서버 권위
  진행, 연결 끊김/재접속, 게임 종료 후 같은 방에서 재대전)까지 전부
  실제로 동작한다. 태그 이후 커밋 3개(`v0.3-online..HEAD`)가 더 있는데
  전부 인프라/버그 수정이라 기능 자체는 안 바뀜 - DEBUG_MODE를 export
  프리셋으로 자동 전환, 재접속 유예 60초 단축, `build_release.bat`
  인코딩 수정.
- **GitHub Pages에 배포됨**: <https://gyutaeng.github.io/Custom-YatchDice-game/>
  - 저장소는 `F:/Godot/web_build`다. **이 프로젝트(`F:/Godot/Project/yacht-dice`)의
    git과 완전히 별개인 독립 저장소**이고, 실제로 커밋된 파일이 들어있는
    라이브 저장소다 - 스크래치 폴더처럼 다루면 안 된다(아래 교훈 참고).
  - 배포용 빌드는 `F:\Godot\build_release.bat`을 더블클릭하면
    `Web (release)` 프리셋으로 export해서 이 폴더를 갱신한다. 커밋/푸시는
    이 저장소 안에서 따로 해야 한다(자동으로 안 됨) - 자세한 절차는
    `docs/deployment_checklist.md`.
- **다음 계획**: 서버를 아직 상시 배포하지 않은 상태라, 지인 대상
  비공개 베타는 로컬 서버를 **Cloudflare 터널**로 잠깐 노출해서 진행할
  예정이다.
- **재대전 2판째 크래시는 계측 완비, 미재현 상태로 2-7과 병행 진행
  중이다.** 청크 유실(엔진 자체의 결함)은 이미 수정·검증 완료:
  `WebSocketMultiplayerPeer.put_packet()`이 보내는 쪽 버퍼가 찼을 때도
  항상 `OK`를 반환하는 것을 실제로 재현해서 확인 - 반환값 대신
  `get_current_outbound_buffered_amount()`로 사전에 확인하도록 고쳤다
  (`docs/multiplayer.md` §8.5-7). 실제 크래시 재현 시도(단방향 팩 전송)는
  재현되지 않았다 - 상태는 "미재현/원인 미확정/계측 완비"(§8.5-8). 원래
  크래시는 **양방향** 팩 전송이었는데 이 경로가 아직 미검증이라, 2-7
  착수 전에 이 경로로 한 번 더(한 세션 한도) 재현을 시도하기로
  확정했다 - `docs/deployment_checklist.md` "2-7 사전 조사 §6" 참고.
  **아직 사용자가 이 재현을 진행하지 않은 상태로 2-7 인프라 작업을
  먼저 시작했다** - 정식 순서는 재현이 먼저지만, 인프라 준비(계정/도구
  설치, 저장소, Dockerfile)는 크래시 여부와 무관하게 필요한 작업이라
  병행했다. **Render에 실제로 서비스를 만들어 띄우기 전에는 반드시
  이 재현을 마칠 것.**

### 🔵 2-7(Render 배포) 진행 상황 - 다음 세션은 여기서 이어서 시작
확정된 순서는 `docs/deployment_checklist.md` "2-7 사전 조사 §6"에 있다.
2026-09-17 새벽 세션에서 단계 0/1/3까지 진행하고 멈췄다(사용자 요청 -
다음날 이어감). 같은 날 낮 세션에서 사용자가 단계 0/1/3 진행을
승인하고, 두 저장소(공개 `Custom-YatchDice-game`/비공개 `yacht-dice`)
구분을 명시하라고 지시(위 "🚨 저장소 2개" 절 참고)한 뒤, 단계 2(양방향
크래시 재현)와 Render 계정 생성은 자기가 직접 하기로 하고 단계 3.5/6
준비를 맡겼다 - 아래 체크리스트와 "2-7 후속" 절이 그 결과다.

- ✅ **단계 0(비공개 저장소)**: `https://github.com/gyutaeng/yacht-dice`
  (private) 생성 완료, `origin`으로 연결, `main`을 Render 배포 기준으로
  확정하고 push 완료. `gh` CLI 설치·인증도 완료(계정 gyutaeng).
- ✅ **단계 1(PORT 환경변수)**: `server_main.gd::_resolve_port()`
  우선순위를 "CLI 인자 → `PORT` → `YACHT_DICE_PORT` → 8910"으로 완료,
  회귀 테스트 4개 통과.
- ⬜ **단계 2(양방향 크래시 재현)**: **아직 사용자가 안 함.** 다음
  세션에서 이걸 먼저 할지, 인프라를 계속 준비할지 확인할 것.
- ✅ **단계 3(Dockerfile)**: 로컬 `docker build`+`docker run`까지 확인
  완료. Docker Desktop 자체가 이 컴퓨터에 없어서 WSL2 설치(`wsl --install`
  + 재부팅) → Docker Desktop 재실행까지 거쳤다(둘 다 완료됨 - 다음
  세션엔 이 설치가 그대로 남아있을 것이므로 재설치 불필요).
- 🟡 **단계 4(바인딩/헬스체크)**: 바인딩은 확인 완료(`"*"` 기본값이
  이미 0.0.0.0 요구사항 충족 - `netstat`으로 재실측도 완료). **헬스
  체크는 여전히 실제 배포에서만 100% 확정되지만, Render 공식 문서상
  "Health Check Path를 비워두면 기본이 TCP 확인"이라 후보 A(경로를
  비워둔다, 코드 변경 없음)로 될 가능성이 높다고 판단** - 후보
  A/B/C 비교와 판단 근거는 아래 "2-7 후속 - 저장소 분리 감사 + 연결
  유지 시간 계측 로그 + 단계 3.5" 절 참고.
- ⬜ **단계 5(Render 서비스 생성) - 사용자의 크래시 재현 결과가 나온
  뒤에 시작.** Render 계정은 오늘 사용자가 직접 만든다. 계정이 있으면:
  New → Web Service → 저장소(`gyutaeng/yacht-dice`, private라
  Render의 GitHub 앱 권한 부여 필요) → Environment: Docker → Free 플랜.
  **아직 실제로 만들지는 않았다.** 화면에 보이는 Health Check Path
  설정 항목을 캡처/전달받아서 위 후보 판단을 최종 확정할 것.
- 🟡 **단계 6(연결 유지 시간 실측, go/no-go 분기점) - 로그 계측은
  준비 완료, 실측 자체는 아직.** `server_main.gd`에 30초 주기 연결
  유지 로그 + 해제 시 총 유지 시간 로그를 추가하고 로컬 소켓으로
  동작을 확인했다(아래 절 참고) - Render에 실제로 배포된 뒤 이 로그로
  무료 플랜의 실제 유지 시간을 잴 준비가 됐다는 뜻이지, 아직 Render
  환경에서 재본 것은 아니다.
- ⬜ 단계 7(재시작 안내 문구), 8(접속 주소 자동 분기), 9(재빌드+Pages
  재배포), 10(전체 재검증)은 아직 손 안 댐.
- **남은 것**: 위 2-7 이어서 진행 → **Phase 3**(웹 퍼블리싱 마감 -
  `docs/deployment_checklist.md`/`docs/web_verification_checklist.md`
  체크리스트 완주).

### ⚠️ 진행 중/보류/제약 - 다음 세션이 바로 알아야 할 것

- **스몰 스트레이트 보이스/연출은 보류.** 사용자 피드백을 받은 뒤 넣을지
  판단하기로 함 - 아직 구현 안 됨(다른 특수 족보처럼 넣을지, 아니면
  스몰은 너무 자주 나와서 뺄지 아직 결정 안 됨).
- **게임 결과 화면의 "(나감)" 표시를 실제로 본 적이 없다.** 게임 도중
  이탈한 사람을 순위 목록에 "(나감)"으로 표시하는 코드
  (`_departed_player_indices`, "B. 게임 결과 화면에 캐릭터 얼굴 추가"
  항목, 아래)는 이미 있고 헤드리스 테스트로도 확인했지만, **실제 온라인
  플레이 중 이 경로(게임 도중 이탈 → 게임이 끝까지 진행됨 → 결과
  화면에 그 사람이 "(나감)"으로 뜸)를 사용자가 직접 지나가본 적이
  없다.** 베타 중 확인이 필요한 항목.
- **`export_presets.cfg`를 고칠 땐 Godot 에디터를 반드시 완전히 닫은
  뒤에 고칠 것.** 열려 있으면 에디터가 메모리 상태로 파일을 덮어써서
  방금 한 수정이 통째로 사라진다 - 이번 세션에 실제로 프리셋 2개가
  전부 날아간 적이 있다(아래 교훈 참고).
- **배포용 export는 반드시 CLI로만 한다.** `F:\Godot\build_release.bat`
  더블클릭이 가장 쉽다. 에디터 GUI의 "내보내기" 버튼은 쓰지 않는다 -
  디스크 파일이 정상이어도 에디터 세션의 오래된 메모리 상태로 export될
  수 있다는 게 실제로 확인됐다(아래 교훈 참고).

### 🎓 이번 세션에서 얻은 교훈 (다음 세션도 읽을 것)

*이미 자세히 적어둔 건 중복하지 않고 위치만 가리킨다.*

- **웹 WebSocket 수신 버퍼 65,535바이트 한계**(43.8KB짜리 청크가 하나
  걸러 하나씩 사라짐) → `connect_to_server()`/서버 시작 시
  `set_inbound_buffer_size()`를 **연결/서버 생성 전에** 키워야 반영됨.
  자세한 조사 경위: `docs/multiplayer.md` §8.5-6.
- **"보냈다"를 "도착했다"로 착각하는 실수가 이 프로젝트에서 여러 번
  반복됐다**(①`put_packet()` 실패를 성공으로 착각 ②"발송"과 "받아서
  쓸 수 있음"을 혼동 ③"큐에 넣음"을 로그가 "보냄"이라고 찍음 - `docs/multiplayer.md`
  §8.5-4가 "세 번째"라고 적어둔 시점의 목록. 사용자 기억으로는 이후
  한 번 더 있었다고 함). 뭔가 "보냈다/받았다"를 로그로 확인할 때는 항상
  **실제로 상대에게 도달한 시점**인지 다시 물을 것. 경위:
  `docs/multiplayer.md` §8.5-1~4.
- **네이티브끼리만 검증하면 웹(WASM/브라우저)에서만 나는 버그를
  구조적으로 못 본다.** 이번 세션에도 같은 함정을 한 번 더 밟았다 -
  DEBUG_MODE export 태그 메커니즘을 처음엔 네이티브 Windows 빌드로만
  검증하고 "될 것"이라 보고했는데, 실제 웹 export에서는(원인은 메커니즘이
  아니라 에디터 GUI의 스테일 상태였지만) 다른 결과가 나왔다. 서버가
  아니라 **클라이언트가 관련된 검증은 반드시 실제 웹 export로 재확인**
  할 것 - 네이티브 검증은 첫 단계일 뿐 마지막이 아니다. 자세한 경위:
  `docs/web_export.md` "DEBUG_MODE 자동 전환"(2차 검증 항목).
- **소켓/네트워크 테스트만으로는 "버튼이 안 먹는다" 같은 UI 버그를 못
  잡는다.** 3번째 재대전 버그(`GameOverOverlay`가 `_show_screen()`
  관리 밖에 있어서 화면 전환이 막힘)는 서버-클라이언트 메시지 교환은
  전부 정상이었고, 실제로 `Main.tscn`을 인스턴스화해서 화면 상태
  (`.visible`)까지 확인하는 테스트를 만들고 나서야 잡혔다. 경위:
  `docs/multiplayer.md` §6 "재대전 UI가 안 뜨던 버그".
- **"화면이 떠 있는지"로 상태를 판단하면 안 된다.** 화면 구성이 나중에
  바뀌면 그 판단이 조용히 틀린다 - 대신 서버가 보내는 실제 데이터
  (예: `game_state.game_over`)로 판단한다. 바로 위와 같은 경위,
  `docs/multiplayer.md` §6.
- **로그가 거짓말하면 없는 버그를 쫓게 된다.** "청크 42/42 수신함"이
  마지막 순번 도착만 보고 있었는데 "전부 도착함"으로 오해해서 엉뚱한
  가설(엔진이 패킷을 유실한다)을 세웠다가 폐기한 적이 있다. 로그 문구가
  실제로 무엇을 확인하는지 항상 의심할 것. 경위: `docs/multiplayer.md`
  §8.5-4.
- **GDScript에서 타입 붙인 변수에 `null`을 대입하면 그 줄에서 바로
  런타임 에러가 나서, 바로 다음 줄의 null 검사에 절대 도달하지 못한다**
  (`var slot: Dictionary = arr[i]`처럼 - `arr[i]`가 `null`이면 그 대입
  자체가 죽는다. null 검사가 필요하면 **타입 없이 받아서** 검사부터
  해야 한다). 경위: CLAUDE.md "2-6B 후속 — 사용자 실제 확인 중 발견한
  서버 크래시" 항목.
- **`_process()` 안에서 에러가 나도 프로그램 전체는 안 죽고, 그 프레임의
  나머지 처리와 그 기능만 조용히 마비된다.** 그래서 "서버가 살아있으니
  괜찮다"가 아니라 "그 기능이 실제로 진행되는지"를 따로 확인해야 한다.
  같은 경위(바로 위).
- **(새로 추가) Godot 에디터가 열려 있으면 `export_presets.cfg`
  외부 수정이 통째로 덮어써질 수 있고, 심지어 파일이 멀쩡해도 에디터
  GUI로 export하면 그 세션의 오래된 메모리 상태로 나갈 수 있다.** 둘 다
  이번 세션에 실제로 겪었다 - 전자는 프리셋 2개가 통째로 날아간 사고,
  후자는 `custom_features` 태그가 디스크엔 있는데 GUI export 결과물엔
  안 먹힌 사고. **그래서 export_presets.cfg를 고칠 땐 에디터를 완전히
  닫고, 배포용 export는 항상 CLI로 한다** - 위 "진행 중/보류/제약" 항목
  참고. `web_build` 폴더 자체가 이제 라이브 git 저장소라는 것도 이 참에
  다시 확인했다(실수로 `rm`했다가 `git restore`로 복구한 적 있음 -
  이제부터 그 폴더엔 삭제 명령을 쓰지 않는다).
- **(새로 추가) 배치 파일(.bat)에 한글 문구나, 한글이 포함된 값(예:
  export 프리셋 이름)을 넘기면 콘솔 코드페이지가 안 맞을 때 명령줄
  구조 자체가 깨질 수 있다.** 안내 문구는 ASCII로만 쓰고, 프리셋
  이름도 영문(`Web (dev)`/`Web (release)`)으로 바꿔서 해결했다. 줄바꿈도
  LF만 있으면 cmd.exe의 `if (...) else (...)` 괄호 블록이 깨질 수 있어서
  CRLF로 저장하고, `goto` 방식으로 바꿨다.
- **(새로 추가, 도구 사용 관련) PowerShell의 `Select-Object -Last N`은
  입력 스트림이 끝나야 뭔가를 출력한다** - 그 앞에 매달린 프로세스가
  오래 걸리면(또는 안 끝나면) 관찰자 입장에선 "출력이 하나도 없다"로
  보여서 진짜 멈춘 것과 구분이 안 된다. 배경 실행 중인 프로세스의
  진행 상황을 보려면 파일로 리다이렉트해서 그 파일을 직접 읽을 것
  (`-Last`/`-Tail` 계열로 파이프하지 말 것).
- **(새로 추가, 도구 사용 관련) 백그라운드로 띄운 `godot --headless`
  프로세스를 도구의 "작업 중지"로 멈춰도 실제 자식 프로세스가 안 죽고
  남을 수 있다.** 이번 세션에 이렇게 쌓인 좀비 프로세스가 8개까지
  늘어난 적이 있다(포트 점유로 다음 테스트가 이유 없이 멈추는 것처럼
  보였다). 확실하게 정리하려면 `Get-Process`로 프로세스 이름/명령줄을
  직접 확인하고 필요하면 `Stop-Process -Force`로 끝낼 것.

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
- 2-6: 연결 끊김/재접속/턴 타임아웃 처리 — **완료.** 실제 소켓으로
  ping 무응답 종료/그레이스 재접속/확정 이탈 후 즉시 자동 처리/늦은
  재접속/명시적 나가기/연결된 채 턴 시간 초과 6가지 시나리오 전부
  수동 검증함(아래 요약).
- 2-6B: 게임 종료 후 같은 방에서 재대전 — **완료.** 실제 소켓으로
  재대전 기본 흐름/대기 중 끊김-재접속/대기 시간 초과-강제 퇴장 3가지
  시나리오 전부 수동 검증함(아래 요약, 이 검증 중 실제 버그 하나 발견해
  고침).

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
- **보이스 매핑**: `GameEvents.VOICE_EVENTS` 테이블을 그대로 읽어 행을 자동 생성(하드코딩 없음 - 테이블에 항목이 늘거나 줄면 화면도 저절로 따라감). 처음엔 10행이었으나 야추 포기(yacht.zero)를 뺀 뒤로 9행이다(아래 "1-4B 후속" 참고). 테이블에 `"frequency": "once"/"frequent"` 필드를 추가해서 "한 판에 한 번"(게임 시작/승리/패배/보너스)과 "자주 반복"(내 차례/야추/라지 스트레이트/풀 하우스/포카드)을 시각적으로 구분한다. 보이스가 없는 이벤트는 흐리게. 볼륨 슬라이더(`profile.volume_db`)를 조절하면 재생 중인 미리듣기에 바로 반영됨.
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
- **에디터의 "브라우저에서 실행"은 쓰지 않는다.** 임시 폴더에 디버그 빌드를 내보내는 별도 경로라 실제 export 설정과 다르게 동작한다(게임 진행 자체가 막힘 - 정식 export로는 정상). 원인은 안 파고들기로 했다. **웹 테스트는 항상 export → `F:/Godot/web_dev` → `python -m http.server` 경로만 쓴다.**(베타 배포 준비 이후 경로 - `F:/Godot/web_build`는 GitHub Pages 배포 전용으로 분리됨, 아래 "베타 배포 준비" 항목 참고) `docs/web_export.md`에 굵게 명시함.
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
  **정정(친구 대상 베타 테스트 후속, 확정 2 조사)**: 위 "그 반환값을 안
  보고 있어서 사라졌다"는 틀렸다 - `put_packet()`은 버퍼가 찬 상태에서도
  항상 `OK`를 반환한다는 게 나중에 최소 재현 스크립트로 확인됐다(엔진
  콘솔의 `ERR_OUT_OF_MEMORY`는 내부 C++ 함수의 로그일 뿐 반환값에는
  안 실림). 그러니 이때 실제로 증상이 사라진 건 이 큐 수정이 아니라
  나중에 §8.5-6에서 밝혀진 받는 쪽 버퍼 1MB 상향 덕분이었을 가능성이
  높다 - 자세한 경위는 `docs/multiplayer.md` §8.5-1 정정/§8.5-7 참고.
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

### 2-6(연결 끊김/재접속/턴 타임아웃) 완료 요약
`docs/multiplayer.md` §6 정책을 실제로 구현했다 - 이미 있던
`SessionStore`(2-3, 토큰 저장)와 `GameState.auto_confirm_least_damaging()`
(2-2, 대신 진행 판단)는 그대로 재사용하고 새로 안 만들었다.

- **문서와 다르게 구현한 부분(사전 확인받음)**: §6 원문은 끊김 감지를
  "WebSocket 레벨 ping/pong"으로 적었지만, 2-5 후속에서 얻은 교훈(엔진의
  WebSocket 동작을 웹/네이티브 양쪽에서 검증 없이 믿지 않는다 - §8.5-6)을
  그대로 적용해 애플리케이션 레벨 `ping`/`pong` 메시지로 직접 만들었다.
  서버가 각 접속의 마지막 통신 시각을 직접 추적해서 5초마다 `ping`을
  보내고 15초 무응답이면 직접 끊는다.
- **문서에 없어서 이번에 정한 것**: 재접속 유예(2분)가 끝나 "확정
  이탈"로 넘어간 뒤에도 같은 토큰이면 재접속을 계속 허용한다(사용자
  확인 완료 - 그레이스가 끝났다고 재접속 자체를 영구히 막을 필요는
  없다는 판단). 새 메시지 `player_timer(player_index, kind, seconds_left)`
  (턴 제한/재접속 유예 카운트다운 표시용, §6에 없던 요구사항)도 이번에
  추가했다. 둘 다 프로토콜 버전은 안 올림(작은 필드만 추가/새 메시지
  타입 - 기존 클라이언트/서버 양쪽에 안전하다는 2-4C 이후 확립된 전제).
- **`Room`(순수 로직)**: 슬롯마다 연결 상태(`ConnectionState` - `CONNECTED`/
  `GRACE_PERIOD`/`PAST_GRACE`)와 턴 데드라인을 추가했다. 연결이 끊기면
  (`mark_slot_disconnected`) 슬롯을 비우지 않고 `peer_id`만 -1로 만들어
  `meta`/재접속 토큰을 살려둔다 - 이게 있어야 재접속(`find_slot_by_reconnect_token`,
  CONNECTED인 슬롯은 매칭 대상에서 제외해 이미 연결된 자리를 못 뺏게
  막음)이 가능하다. `RoomManager.remove_peer()`는 `voluntary`(명시적
  `leave()`인지) 인자로 분기한다 - 명시적으로 나가면 게임 도중이라도
  그레이스 없이 즉시 완전히 비운다(토큰 파기).
- **`server_main.gd`**: `_service_in_game_rooms()`(`_service_transferring_rooms()`
  와 같은 패턴)가 매 프레임 IN_GAME 방을 돈다 - 그레이스 만료 감지,
  턴 타임아웃(연결 여부와 무관하게 60초) 처리, 1초 주기
  `player_timer` 방송을 전부 여기서 한다. **확정 이탈된 플레이어의
  턴은 60초를 안 기다리고 즉시 처리된다** - `turn_started` 시점에
  데드라인을 이미 지난 값으로 세팅해두고 다음 프레임에 서비스 루프가
  자연스럽게 집어서 처리하게 해서, 같은 `_mutate_and_broadcast()` 호출
  스택 안에서 재귀적으로 auto_confirm이 또 불리는 상황을 피했다(실제
  라이브 검증에서 0ms - 진짜 즉시 처리됨을 확인).
- **재접속 성공 시**: 방 전원에게 `player_reconnected` 방송 + 게임이
  이미 IN_GAME이면 그 사람에게만 즉시 최신 `state_snapshot`을 추가로
  보낸다(§5 "매번 전체 스냅샷" 원칙을 재접속에도 그대로 적용).
- **클라이언트**: 새 `scripts/net/reconnect_backoff.gd`(`ReconnectBackoff`
  - 1,2,4,8,16초... 지수 백오프, 상한 `NetProtocol.MAX_RECONNECT_ATTEMPTS`)
  하나를 **첫 접속(배포가 Render 무료 플랜이라 유휴 시 서버가 잠들고
  깨어나는 데 최대 1분 걸림)과 게임 도중 재접속 양쪽에서 재사용**한다
  (`online_screen.gd`). 게임 화면에 한 번이라도 들어간 뒤의 `disconnected`
  는 로비로 안 튕기고(`_show_screen()`을 안 부름) 조용히 재접속을
  시도한다 - 성공하면 `game_reconnected`, 상한 소진/서버 쪽 거부(방이
  이미 정리됨 등)면 `reconnect_exhausted`를 emit해서 Main.gd가 배너
  문구만 바꾼다.
- **새로고침(F5) 복귀**: `Main.gd`가 시작 시 `SessionStore`에 저장된
  세션이 있으면 다이얼로그로 물어보고(`SessionResumeDialog`), 수락하면
  `online_screen.attempt_session_resume()`이 재접속 후 캐릭터 팩을
  다시 확인(캐시에 있으면 즉시, 없으면 재요청)한 뒤 정상적인 게임
  진입 경로(`game_play_started`)를 그대로 탄다 - 로비 종료 시(`_on_game_started`)
  와 코드를 공유한다(`_resolve_profiles_and_enter_game()`).
- **화면 표시**: 다른 플레이어의 연결 상태를 그 사람 점수판 칸 밑에
  지속 표시(`connection_status_labels`), 확정 이탈이 하나라도 있으면
  턴 라벨 옆에 `[로비로 나가기]` 버튼 노출, 내 턴 카운트다운은 별도
  라벨. 내 연결이 끊겼을 땐 화면 상단 배너(`ReconnectOverlay`)만
  뜨고 화면 전환은 절대 안 한다(로비로 안 튕기는 게 핵심 요구사항).
- **검증**: `Room`/`RoomManager`/`ReconnectBackoff`의 순수 로직은 새
  테스트 24개(`test_room_connection.gd`, `test_reconnect_backoff.gd`,
  `test_room_manager.gd` 추가분)로 헤드리스 검증. 실제 소켓으로는
  임시 상수(턴 제한/그레이스를 초 단위로 임시로 줄여서 검증 후 원복)를
  써서 6가지 시나리오를 전부 직접 확인함: ping 15초 무응답 연결 종료,
  그레이스 안 재접속(`player_reconnected` 수신), 그레이스 만료 →
  확정 이탈(`player_left(reason=timeout)`) → 그 사람 턴이 되자마자
  0ms만에 자동 처리, 확정 이탈 후에도 같은 토큰으로 재접속 성공, 연결은
  멀쩡한데 응답 없을 때 turn timeout으로 자동 처리, 명시적 `leave()`
  후 같은 토큰 재접속 시도가 `ROOM_FULL`로 거부됨. `player_timer`
  메시지도 "turn"/"reconnect" 두 종류 다 정상 카운트다운 확인.
- **아직 실제로 못 겪은 것**: 이번 시나리오들은 전부 인위적으로
  소켓을 끊어서 재현했다 - 실제 브라우저 탭 닫기/새로고침/서버 재시작
  세 가지는 사용자가 직접 확인해야 한다(브라우저 새로고침 시 캐릭터가
  실루엣으로 잠깐 보일 수 있음, 서버 재시작은 방 데이터 자체가
  사라지므로 재접속이 아니라 `ROOM_NOT_FOUND`로 조용히 끝나는 게
  정상임을 미리 알아둘 것).

### 2-6B(게임 종료 후 같은 방에서 재대전) 완료 요약
`Room.State.ENDED`(아무 데서도 직접 검사되지 않던, 사실상 죽은 이름)를
`REMATCHING`으로 대체해서 "게임 종료 → 재대전 대기 → 캐릭터 재선택
(선택) → 재전송 → 새 게임"을 한 방에서 반복할 수 있게 했다. 자세한
상태 전이/설계 결정은 `docs/multiplayer.md` §3(로비 상태 기계)와
§6(재대전 대기 중 끊김)에 정리했다 - 여기는 요약만.

- **핵심 발견(계획 단계에서 미리 확인)**: 2-5의 캐릭터 팩 전송
  파이프라인(`Room.begin_transfer()`/`PackTransferClient.begin()`/
  `ReceivedPackCache` 해시 캐시)이 처음부터 완전히 재진입 가능하게
  짜여 있어서, "판 사이에 캐릭터를 바꿀 수 있게"가 사실상 공짜로
  해결됐다 - 캐릭터가 안 바뀌었으면 해시가 같아 전송 자체가 없고,
  바뀐 사람 것만 다시 전송된다. 이번에 새로 만든 것은 전송 로직이
  아니라 "재대전 상태로 들어가고 나가는 다리"뿐이다.
- **새 상태/헬퍼(`scripts/net/room.gd`)**: `Room.accepts_lobby_actions()`
  (`LOBBY` 또는 `REMATCHING`이면 true - `select_character`/`ready`/
  `set_player_count`/신규 `join_room`이 전부 이 하나만 확인하도록
  통일), `begin_rematch_wait(now)`(전원 `ready`를 되돌리고 방 전체
  대기 마감을 잡음), `is_rematch_wait_timed_out()`, `start_new_game()`
  (`change_capacity()`와 같은 패턴으로 **같은 rng 인스턴스를 재사용**해
  완전히 새 `GameState`를 만듦 - "지난 판 상태가 조금이라도 남으면
  안 된다"를 예외 없이 만족).
- **재대전 대기 시간은 슬롯별이 아니라 방 전체에 하나**
  (`NetProtocol.REMATCH_READY_TIMEOUT_MSEC`, 2분 - 2-6의 재접속 유예와
  같은 값으로 통일)(추천안, 사용자 승인). "버튼을 안 누른 사람"과
  "끊긴 채 안 돌아온 사람"을 같은 기준으로 다루기 위한 단순화 -
  2-6의 슬롯별 그레이스 타이머를 또 만들지 않는다. 시간이 다 되면
  그때까지 준비 안 한 슬롯을 전부(연결 여부 무관) `RoomManager.force_vacate_slot()`
  으로 강제 퇴장시키고(`player_left(reason=timeout)`), 그 방은 다시
  사람을 기다리는 `REMATCHING`으로 남는다 - 완전히 나간 것과 같은
  취급이라 토큰도 파기된다(재접속 유예의 "이탈 후에도 토큰 유효"는
  여기 적용 안 함 - 이미 2분을 줬으므로).
- **`_handle_join_room()`의 `is_reconnect` 판정 버그를 구현 전에
  미리 잡음**: `room.state != LOBBY`면 재접속이라는 예전 가정이
  `REMATCHING`도 신규 참가를 받는 지금은 안 맞는다(빈 슬롯을 채우는
  새 사람이 `REMATCHING`에서도 생길 수 있음) - 토큰이 실제로 어느
  슬롯과 일치하는지 직접 조회해서 판정하도록 코드를 짜기 전에 고쳤다.
- **실제 소켓 검증 중 발견하고 고친 진짜 버그**: 두 슬롯이 같은 순간에
  재대전 대기 시간을 초과하면, 먼저 처리된 슬롯을 비우고 나서 두 번째
  슬롯의 퇴장을 방송하는 순서였다 - `_broadcast_room()`이 그 순간의
  `room.slots`를 그대로 훑기 때문에, 이미 비워진 첫 번째 슬롯의
  주인은(소켓은 아직 열려 있는데도) 두 번째 사람의 `player_left`를 못
  받는 상태였다. `_service_rematch_rooms()`를 "방송을 전부 먼저 끝내고
  나서 비우기" 순서로 고쳤다. 실제 2인 동시 타임아웃을 소켓으로
  재현해서 고치기 전/후 차이를 직접 확인함.
- **클라이언트(`scenes/Main.gd`/`scenes/online/online_screen.gd`)**:
  게임 종료 화면에 온라인 전용 `[한 판 더]` 버튼 추가(로컬 `[다시 하기]`는
  그대로 유지, `[나가기]`는 기존 `leave()` 경로 재사용). `[한 판 더]`는
  1-6/2-4B의 `CharacterSelectScreen`을 1인분만 그대로 재사용해서
  캐릭터를 다시 고르게 하고(2-4B에서 만든 그 화면, 새 화면 없음),
  확정되면 `select_character` 전송 직후 자동으로 `set_ready(true)`까지
  같이 보낸다(따로 준비 버튼을 또 안 누르게). 안 바꾸고 그대로
  확정해도 동작은 같다(해시가 같아 전송 없음). 재대전 대기 카운트다운은
  `player_timer(kind="rematch")`를 받아 로비 상태 문구에 표시한다(시간
  기준 계산 - 2-5에서 겪은 "멈춘 카운트다운" 재발 방지). `_on_online_game_play_started()`
  맨 앞에서 2-6의 idempotent 시그널 해제(`_disconnect_online_client_signals()`)를
  먼저 호출해서, 같은 `GameClient`로 재대전이 반복돼도 시그널이 중복
  연결되지 않게 했다.
- **세션 저장(`SessionStore`) 정책이 바뀜**: 예전엔 "게임이 정상 종료되면
  세션을 지운다"고 문서에 적혀 있었지만(실제로 그렇게 구현되지도
  않았었음), 2-6B로 게임 종료가 더 이상 방의 끝이 아니게 되면서 이
  가정 자체를 폐기했다 - 세션은 명시적으로 나갈 때만 지운다. `docs/multiplayer.md`
  §6에 반영.
- **메모리/상태 오염 없음 - 새로 만들 필요가 없었다**: `Room`/`GameState`/
  `OnlineGameController`가 전부 `RefCounted`라서, `start_new_game()`이
  매번 새 `GameState`를 만들면 이전 객체는 참조가 끊기는 즉시 가비지
  컬렉션 대상이 된다 - 명시적 해제 코드가 필요 없다. 클라이언트 쪽
  `_enter_game()`/`VoiceBank.configure()`/점수판·초상화 영역 재구성도
  이미 매번 완전히 새로 만드는 구조라 손을 안 댔다(로컬 "다시 하기"가
  이미 오래전부터 검증해온 경로와 동일).
- **새 테스트 12개**(`scripts/tests/suites/test_room_rematch.gd` 8개 +
  `test_room_manager.gd`의 `REMATCHING` 관련 신규 참가/재접속/그레이스
  3개) - `accepts_lobby_actions()`, `begin_rematch_wait()`의 ready 리셋과
  마감 시각, `is_rematch_wait_timed_out()`, `start_new_game()`의 완전
  초기화(플레이어 0 총점 0, 모든 칸 미확정, 새 `GameState` 인스턴스,
  같은 rng 재사용), 그리고 **사용자가 명시적으로 요청한 "같은 방에서
  연속 3판을 돌려도 상태가 오염되지 않는지"** 검증(3라운드 반복하며
  매번 총점 0/플레이어 0부터 시작/`transfer_resend_request_counts` 등
  2-5 필드가 라운드마다 안 쌓이는지 확인). 전체 787개 통과.
- **실제 소켓으로 3가지 시나리오 확인**: ① 재대전 기본 흐름(1판 끝 →
  `REMATCHING` → 재확정 → `TRANSFERRING` 재진입 → 2판째가
  `current_player=0`/총점 0/`game_over=false`로 시작) ② 재대전 대기
  중 끊김 → 그레이스 내 재접속(같은 슬롯 복귀, `CONNECTED`로 정상화)
  ③ 재대전 대기 시간 초과 → 전원 강제 퇴장(`player_left(reason=timeout)`
  2건, 방은 빈 채로 남음). 검증 스크립트는 확인 후 삭제해서 저장소에
  안 남았다.
- **테스트 편의(사용자가 물어본 것) - 디버그 자동 진행(Ctrl+Shift+A)은
  온라인 화면에서 못 쓴다.** 2-4에서 이미 온라인 로비/게임 화면에서
  디버그 버튼/단축키를 숨기도록 정해뒀기 때문이다(`debug_hotkeys.set_panel_visible()`).
  연속 재대전을 손으로 빠르게 확인하려면, 디버그 자동 진행 대신 **양쪽
  클라이언트에서 그냥 빈 칸을 아무거나 계속 확정해서** 한 판을 빠르게
  끝내는 방법을 쓸 것 - 12칸이라 오래 안 걸린다. 자동화된 검증(위 실제
  소켓 확인)에서는 `room.game_state.auto_confirm_least_damaging()`을
  서버 쪽 `Room` 객체에 직접 반복 호출해서 한 판을 즉시 끝냈다(실제
  요청 왕복 없이 - "게임이 끝나는 걸 서버가 감지하는지" 자체는 2-4/2-5가
  이미 검증했으므로 이번 검증의 대상이 아니었음).
- **온라인 로비 UI(참가자 목록/준비 상태 표시)는 이미 있는 것을 그대로
  재사용** - `REMATCHING`도 `player_joined`/`player_character`/
  `player_ready_changed`/`room_player_count_changed`를 로비 때와
  똑같이 받으므로 새 핸들러가 필요 없었다.

### 2-6B 후속 — 사용자 실제 확인 중 발견한 서버 크래시(재대전이 안 되던 진짜 원인)
사용자가 실제 브라우저로 재대전을 시도하다가 서버 콘솔에서
`SCRIPT ERROR: Trying to assign value of type 'Nil' to a variable of type
'Dictionary'. at: _service_rematch_rooms (server_main.gd:653)`를
`_process()` 안에서 매 프레임 반복해서 봤다고 보고 - `[한 판 더]` 안내창이
안 닫히는 증상의 원인이었다.

- **근본 원인**: `REMATCHING` 중 한 명이 `[나가기]`(자발적 `leave()`)로
  나가면 그 슬롯이 `null`이 된다(2-6B가 의도한 정상 상태 - "인원이
  모자란 재대전 로비"). 그런데 `_service_rematch_rooms()`의 두 반복문이
  `var slot: Dictionary = room.slots[i]`처럼 배열 원소를 **null 검사보다
  먼저** 타입 있는 `Dictionary` 변수에 대입하고 있었다 - GDScript는
  `null`을 `Dictionary` 타입 변수에 대입하는 순간 그 자리에서 런타임
  에러를 내므로, 바로 다음 줄의 `if slot != null` 검사는 이미 늦다.
  이 함수는 `_process()`에서 매 프레임 불리므로, 슬롯 하나가 비워진
  방이 존재하는 한 서버가 **매 프레임** 같은 자리에서 죽었다 - 크래시
  자체가 서버 프로세스를 끝내지는 않지만, 그 프레임의 나머지 처리(패킷
  큐 소비 등)를 막아서 겉보기엔 "버튼이 안 먹는다"로만 보였다.
- **같은 모양이 2-5(캐릭터 팩 전송)에도 이미 두 곳 있었다**: 재대전이
  전송 단계를 재사용하면서 이 함정을 밟을 조건(전송 도중 수신자가
  나감)도 같이 노출됐다 - `_warn_if_transfer_stalled()`와
  `_handle_upload_pack_chunk()`의 청크 릴레이 루프, 그리고
  `RoomManager.force_vacate_slot()`도 전부 같은 패턴이었다. 넷 다
  null 검사를 원본 배열 원소에 먼저 하도록 고쳤다.
- **근본 수정**: 중복되던 "점유+미준비 슬롯 찾기" 판단을
  `Room.not_ready_occupied_slots()` 하나로 합쳐서(`players_summary()`가
  이미 쓰던 안전한 패턴 - 타입 없이 받아서 null 검사 먼저) 같은 실수를
  두 곳에 반복할 여지 자체를 없앴다. `_service_rematch_rooms()`의 타임아웃
  처리 루프와 매초 카운트다운 방송 루프 둘 다 이 함수 하나만 쓴다.
- **재현 조건**: 게임 종료 → `REMATCHING` → 한 명이 `[나가기]`(자발적
  이탈, 그레이스 없이 즉시 슬롯이 `null`이 됨) → 남은 한 명이 아직
  `[한 판 더]`를 안 누른 상태. 이 조건이면 그 다음 1초 주기 카운트다운
  방송 때(또는 2분 대기 초과 처리 때) 100% 재현됐다 - "두 번째 시도부터
  안 뜬다"는 보고는 버그가 사라진 게 아니라, 재시도할 때 두 명 다
  `[한 판 더]`만 누르고 아무도 `[나가기]`를 안 눌러 이 조건(슬롯이 null이
  되는 상황)을 다시 안 밟은 것이었다.
- **새 테스트 6개**: `test_room_rematch.gd`에 `not_ready_occupied_slots()`
  기본 동작 2개 + **버그 재현 조건을 그대로 박은 회귀 테스트**(재대전
  대기 중 한 슬롯을 `vacate_by_peer()`로 비운 채 호출해도 크래시 없이
  남은 슬롯만 반환하는지). `test_room_manager.gd`에 `force_vacate_slot()`을
  이미 빈 슬롯/범위 밖 인덱스에 또 불러도 크래시 없는지 2개.
- **실제 소켓으로 크래시 조건을 그대로 재현해 수정 전/후 확인**: 2인
  게임 종료 → REMATCHING → 남은 한 명(A)이 아직 미준비인 채로 다른 한
  명(B)이 `leave()` → 서버가 `SCRIPT ERROR` 없이 살아있는지, A가 여전히
  `player_timer(kind=rematch)` 카운트다운을 정상 수신하는지(3.2초간 3회
  수신 확인), 새 참가자가 빈 슬롯에 들어와 실제로 2판째가 시작되는지
  (`current_player=0`)까지 전부 확인함. 검증 스크립트는 확인 후 삭제.
- 전체 793개 통과(+6).

### 1-4B 후속 — 야추 포기(yacht.zero) 보이스를 목록에서 제거
사용자 요청: 야추 포기(yacht.zero)를 캐릭터 편집 화면의 보이스 매핑
대상에서 뺀다. 1-4B에서 `yacht.roll`/`hold` 등을 뺐을 때와 같은 방식 -
`GameEvents.zero_scored` 시그널과 이벤트 릴레이는 그대로 남기고(나중에
다시 쓸 수도 있음), 캐릭터 보이스로만 더 이상 반응하지 않게 했다.

- **`autoload/game_events.gd`**: `VOICE_EVENTS`에서 `Yacht.ZERO` 행을
  제거(10개 → 9개). `Yacht.ZERO = "yacht.zero"` 상수 자체는 남겨뒀다 -
  `zero_scored` 시그널의 카테고리 판정 등에서 여전히 의미 있는 값이고,
  제거 대상은 어디까지나 "보이스로 반응하는 목록"이지 이 개념 자체가
  아니다.
- **`autoload/voice_bank.gd`**: `zero_scored` 구독과 `_on_zero_scored()`
  핸들러, `_event_priority`의 ZERO 등록, `PRIORITY_ZERO` 상수를 전부
  제거했다 - 테이블에서만 빼고 재생 로직은 살려두면 "1-4B와 같은 방식"이
  아니게 된다(yacht.roll/hold는 애초에 VoiceBank 재생 로직 자체가 없다).
- **1-6 편집 화면은 확인만 하고 코드를 안 고쳤다** - `voice_mapping_panel.gd`가
  `GameEvents.VOICE_EVENTS`를 그대로 순회해서 행을 그리므로 9행으로
  저절로 줄어든다.
- **기존 캐릭터 팩과의 호환(원칙 6)**: `CharacterProfile._sanitize_voice_map()`이
  애초에 키 이름을 `VOICE_EVENTS`와 대조하지 않고 문자열 키 + 배열 값이면
  그대로 통과시키므로, manifest에 `yacht.zero` 매핑이 남아있는 옛날 팩도
  에러 없이 그대로 가져와진다 - 그 매핑은 단지 아무도 안 읽는 죽은
  데이터로 조용히 남을 뿐이다. 실제로 그런 팩(zip)을 직접 만들어
  가져오기가 성공하는지, `save_profile()`의 고아 파일 정리가 이 매핑이
  가리키는 파일을 잘못 지우지 않는지까지 새 테스트로 확인했다
  (`test_character_pack.gd::_test_orphaned_voice_event_key_is_imported_without_error`).
- `docs/character_pack.md`는 확인해봤지만 보이스 이벤트를 개수로 나열한
  부분이 원래 없어서(단일 예시 `voice_map` 키 하나만 보여줌) 고칠 곳이
  없었다.
- 전체 799개 통과(+6).

### 2-6 후속 — 사용자 실제 확인 중 발견한 버그 2건 (새로고침 캐릭터 초기화 / 인사 재생)
사용자가 실제 브라우저로 재대전 크래시(위 후속 항목)를 고친 뒤 다시
테스트하다가 보고한 두 가지. 하나는 고쳤고, 하나는 실제 소켓으로 100회
가까이 재현을 시도했지만 재현하지 못했다 - 정직하게 그 과정과 결론을
남긴다.

- **버그: 새로고침(F5) 복귀 후 내 캐릭터가 기본 캐릭터로 보임(고침)**.
  원인과 수정은 `docs/multiplayer.md`("클라이언트 쪽 재접속 정보 저장"
  섹션의 "버그 수정(2-6 후속)" 항목 두 개)에 자세히 적었다 - 요약하면
  ① `online_screen.gd`가 새로고침 뒤 항상 기본 캐릭터로 리셋되는데
  서버가 이미 보내주는 `room_joined`의 `meta.id`로 복원을 안 하고
  있었던 것(→ `_find_profile_by_id()` 추가), ② 복귀도 `_enter_game()`을
  똑같이 타서 이미 지나간 인사 연출을 다시 틀던 것(→
  `game_play_started`에 `is_resume` 플래그 추가). 실제 소켓으로 캐릭터
  생성 → 게임 시작 → 새 `online_screen` 인스턴스로 복귀(진짜 새로고침과
  가장 가까운 시뮬레이션 - 페이지 전체가 다시 뜨면 메모리가 통째로
  사라지므로) → 캐릭터 id/보이스 매핑이 정확히 복원되는 것까지 확인함.
- **의심 사례: 가끔 첫 턴 대사가 두 번 재생됨(재현 못 함, 관련 버그 하나는
  발견해 고침)**. `turn_started`가 실제로 몇 번 방출되는지부터 실측했다 -
  방출 지점은 딱 두 곳뿐이다: `game_state.gd`의 `_begin_turn()`(온라인
  클라이언트의 read_only 사본에서는 read_only 가드에 막혀 절대 안 불림)과
  `online_game_controller.gd`의 서버 릴레이 한 곳(`_client.turn_started.connect(func(p):
  GameEvents.turn_started.emit(p))`). 실제 소켓으로 첫 턴 포함 총 105회의
  턴 전환(20회 실행 × 첫 턴 하나, 15회 실행 × 턴 6개)을 실제 요청
  왕복(roll → score)으로 진행시키며 셌지만 **전부 정확히 1번씩**이었다 -
  네트워크/서버 계층에서 중복이나 누락은 못 찾았다. 코드를 훑다가
  **관련은 있지만 다른 진짜 버그**를 하나 발견해 고쳤다:
  `VoiceBank._on_slot_finished()`가 인사 연출 중에는 조건 분기에서 곧장
  `return`해버려서 `_try_play_pending()`을 절대 안 불렀다 - 인사 재생
  중(우선순위 30)에 낮은 우선순위(20)로 도착한 요청(전형적으로 온라인
  첫 턴의 `turn_started`)은 대기열에 들어간 채로 **인사가 끝나도 아무도
  다시 꺼내 재생/폐기해주지 않고 영원히 방치**됐다 - 게다가 그 자리를
  비우지 않으니 그 뒤로 같거나 낮은 우선순위 요청은(`priority >`
  비교라 동률이면 안 바뀜) 계속 밀려날 수 있었다. `_advance_greeting()`이
  인사를 완전히 끝낼 때 `_try_play_pending()`을 마저 불러 대기 슬롯을
  확실히 비우도록 고쳤다(1.5초를 이미 넘겼으면 그냥 버려지지만, 최소한
  다음 요청을 막지는 않음). 사용자가 요청한 대로 실제로 재생/요청/대기/
  버림되는 이벤트마다 `player`/`key`/`file`/우선순위를 찍는 로그를
  `DEBUG_MODE`에 묶어 `voice_bank.gd`에 영구히 남겨뒀다 - **재현되면
  이 로그로 같은 파일이 두 번인지, 아니면 인사(`common.game_start`)
  다음에 내 차례(`common.turn_start`)가 이어진 정상 설계 동작인지
  바로 구분할 수 있다.**

### A. 보이스 파일 길이 제한
용량(1MB) 제한만으로는 길이를 못 막는다는 사용자 지적 - WAV는 1MB가
대략 11초라 우연히 막히지만, 우리가 권장하는 OGG는 1MB에 1~2분이
들어간다. 길이가 긴 대사가 `VoiceBank`의 `VOICE_WAIT_TIMEOUT_MSEC`(1.5초)
대기열을 오래 막아서 그 사이 다른 이벤트(야추/보너스/상대 차례)의
보이스가 조용히 버려지는 게 진짜 문제였다.

- **`AudioStream.get_length()` 사전 확인**: wav/ogg/mp3 전부에서 실제로
  정확히 동작함을 실측했다 - ffmpeg로 정확히 3.7초짜리 테스트 파일
  세 개를 만들어 `AssetLoader.load_audio_from_bytes()`로 디코드 후
  확인, 오차 0. 미리듣기 때 이미 디코드하는 걸 재사용하므로 추가 비용도
  거의 없다.
- **하드 상한 7초**(`CharacterLimits.VOICE_MAX_DURATION_SEC`) - 넘으면
  편집 화면 업로드는 거부(런타임에 오디오를 자를 수 없으므로 1-7B
  방식대로 안내만 하고 막음), **팩 가져오기(1-7)는 거부하지 않고 경고만**
  (이미 신뢰 검증을 통과한 팩이라는 기존 원칙과 동일). 안내 문구는
  "지금 몇 초 -> 한도 몇 초 -> 어떻게 줄이는지" 3단 구성을 그대로 따름.
- **이벤트별 권장 길이**(7초는 거부선일 뿐, 적정 길이는 이벤트마다 다름 -
  `GameEvents.VOICE_EVENTS`에 `recommended_label`/`recommended_max_sec`
  추가): 내 차례 1~2초, 포카드/풀하우스 2~3초, 라지 스트레이트/야추/
  보너스 3~4초, 게임 시작 인사 5초 이내, 승리/패배 7초 이내. 편집
  화면(1-6) 각 행에 "한 판에 한 번"/"자주 반복" 태그 옆에 표시하고,
  저장된 파일이 권장을 넘으면(거부 아님) 용량 경고와 같은 노란색으로
  표시한다.
- `docs/character_pack.md`에 길이 제한/권장 길이 표 추가. 새 테스트
  포함 전체 804개 통과.

### B. 게임 결과 화면에 캐릭터 얼굴 추가
사람들이 캡처해서 공유할 가능성이 높은 화면이라는 사용자 지적 - 이름/
점수만 있던 텍스트 요약을 캐릭터 썸네일이 들어간 순위 목록으로 완전히
바꿨다.

- **썸네일은 1-3의 `CharacterPortrait`/`TextureFit`을 그대로 재사용**
  (새 컴포넌트 없음) - 썸네일 없으면 스탠딩 위쪽 크롭, 그것도 없으면
  실루엣(1-3B) 폴백이 손 안 대고 그대로 동작한다. 크기는 처음 96px로
  했다가 4인 기준 결과 패널 전체 높이를 실측하니 653px가 나와서(작은
  창에서 여유 부족) 사용자가 미리 승인해둔 대로 80px로 낮춰
  589px로 줄였다 - `RESULT_THUMBNAIL_SIZE` 상수 하나로 관리.
- **순위는 "1224" 방식**(동점은 같은 순위, 다음 순위는 인원수만큼
  건너뜀 - `get_winners()`로 승자 판정, 별도 순위 계산은 점수 내림차순
  정렬로 직접 계산). 승자는 노란 테두리로만 강조(사용자 지적 - 캡처했을
  때 지저분해 보이면 안 되므로 과하게 안 함).
- **리모컨 구조 유지(사용자 지적)** - 게임 결과 화면이 로컬/온라인을
  직접 구분하던 기존 코드(`my_player_index == -1`로 분기)를 없앴다.
  `LocalGameController`/`OnlineGameController` 양쪽에
  `get_game_over_actions() -> Array[{"id", "label"}]`를 추가해서 "이
  화면에서 가능한 행동"을 컨트롤러가 정하고, `Main.gd`는 받은 목록
  그대로 버튼을 동적으로 만들어 눌리면 `_on_game_over_action_pressed(id)`
  하나로만 처리한다. 로컬은 `[다시 하기]`/`[처음으로]`(기존 그대로 유지 -
  사용자가 명시적으로 확인), 온라인은 `[한 판 더]`/`[나가기]`. 기존
  `RestartButton`/`RematchButton`/`ToTitleButton` 정적 노드 3개를
  `GameOverButtonsRow`(빈 컨테이너) 하나로 대체했다.
- **2-6으로 도중에 나간 사람도 표시**(사용자 지적) - 기존
  `_departed_player_indices`(연결 상태 표시에 이미 쓰던 것)를 그대로
  재사용해서 이름 옆에 "(나감)"만 붙인다. 이 김에 이 딕셔너리를 채우는
  `_on_online_player_left()`가 `reason="timeout"`만 처리하고
  `reason="left"`(명시적 나가기)는 놓치고 있던 기존 빈틈도 같이
  고쳤다(둘 다 그 순간부터 서버가 즉시 자동 진행하는 건 똑같으므로
  같은 취급이 맞음).
- **온라인에서 남의 썸네일**: 별도 검증 코드를 새로 안 만들었다 - 결과
  화면이 읽는 `player_character_assignments`는 게임 중 초상화/보이스가
  이미 쓰고 있는 바로 그 배열이라(2-5에서 이미 온라인 정상 동작 확인
  완료), 결과 화면에서 새로 뚫어야 할 온라인 전용 경로가 없다.
- **새 테스트**(`test_game_over_ui.gd`) - `test_game_start_builtin_only.gd`와
  같은 방식으로 `Main.tscn`을 실제 인스턴스화해서 확인: 4인 공동 1위(→
  3위로 순위 건너뜀) 순위 계산, 도중에 나간 사람 "(나감)" 표시, 썸네일
  박스 크기, 로컬/온라인 각각의 버튼 라벨, 4인 기준 결과 패널 높이
  실측(589px). `_refresh_game_over_ui()`는 그대로 동기 함수 유지 -
  보이스 재생을 기다리는 코드를 추가하지 않았다.
- 전체 826개 통과.

### 2-6B 후속 - 재대전 버튼이 안 먹던 버그 수정 (서버 크래시를 고친 뒤 증상이 바뀐 3번째 라운드)
2-6B 배포 후 실제로 두 라운드에 걸쳐 겪은 버그. 1라운드(서버 크래시 -
`_service_rematch_rooms()` 등에서 배열 원소가 `null`인데 타입 있는
`Dictionary` 변수에 대입해서 남 - `Room.not_ready_occupied_slots()`로
뽑아 null 검사를 먼저 하도록 고침)를 고치자 서버는 안 죽는데 양쪽 다
`[한 판 더]`를 눌러도 반응이 없고 `[나가기]`를 누른 사람만 로비로
가는 증상으로 바뀌었다. 자세한 조사 과정/코드 위치는
`docs/multiplayer.md` §6 "재대전 UI가 안 뜨던 버그" 참고, 여기는 요약만.

- **원인 1**: `GameOverOverlay`가 4개 화면(START/CHARACTER_SELECT/GAME/
  ONLINE)을 관리하는 `_show_screen()`의 관리 밖에서 개별적으로만
  닫히고 있었다 - `[한 판 더]`가 실제로 `_show_screen(CHARACTER_SELECT)`
  까지는 정확히 불렀지만(리모컨 구조 자체는 정상 - 사용자의 "액션 id
  불일치" 의심은 코드 대조로 기각), 오버레이가 그 위에 계속 떠서
  "아무 반응 없음"으로 보였다. `_show_screen()`이 호출될 때마다
  `GameOverOverlay`/`ReconnectOverlay`(같은 구멍이 있어서 같이 발견)를
  무조건 닫도록 통합해서 해결 - `_return_to_title()`/`_enter_game()`에
  있던 개별 `.visible = false` 줄은 제거(단일 통로로 통일).
- **사용자 요청으로 같은 종류의 구멍이 더 있는지 루트 레벨 오버레이를
  전부 훑음**: `QuitConfirmDialog`/`SessionResumeDialog`/`DebugInitLog`/
  `DebugHotkeys`는 각자 맥락 안에서 스스로 닫혀서 안전, `InputBlocker`/
  `GreetingSkipButton`/`SpecialHandLabel`(1-3C/1-4C)은 `GameScreen`
  아래 중첩되어 있어 부모가 안 보이면 자동으로 같이 가려짐(Godot
  Control 트리 규칙), 캐릭터 편집 화면 다이얼로그들은 편집 화면 자체가
  `_show_screen()`과 무관한 별도 씬이라 안전 - 실제로 고칠 게 있던 건
  `GameOverOverlay`/`ReconnectOverlay` 둘뿐이었다.
- **원인 2**: 재대전 대기 중 한 명이 나가면 남은 사람의
  `_on_online_player_left()`가 "게임 진행 중 이탈"(2-6, 상태 라벨만
  갱신) 분기만 알고 있어서 로비로 안 돌아갔다. **사용자 지적 - "화면이
  떠 있는지"가 아니라 "방 상태"로 판단하라**: `GameOverOverlay.visible`
  로 재대전 대기 여부를 판단하면 원인 1과 똑같은 함정(화면 구성이
  바뀌면 조용히 틀림)이라, 대신 서버 스냅샷을 그대로 미러링한 실제
  게임 데이터 `game_state.game_over`로 판단하도록 고쳤다(재대전 대기
  중이면 아직 새 `game_state`로 안 바뀐 상태) - 서버에 새 필드/메시지를
  추가하지 않고 클라이언트가 이미 가진 데이터를 재사용했다.
- **테스트에 불변식을 박음**(사용자 요청) - `test_game_over_ui.gd`에
  "`_show_screen()`을 4가지 화면 중 어느 것으로 부르든, 호출 후엔
  `GameOverOverlay`/`ReconnectOverlay`가 항상 닫혀 있다"를 추가해서,
  나중에 새 루트 레벨 오버레이가 생겨도 같은 구멍이 조용히 재발하면
  자동으로 잡히게 했다. `_on_game_over_action_pressed()`를 실제
  `Main.tscn` 인스턴스에 직접 먹여 화면 전환/오버레이 정리를 확인하는
  테스트, `_on_online_player_left()`의 방 상태 판단(재대전 대기 중
  이탈 vs 게임 진행 중 이탈)을 확인하는 테스트도 추가했다.
- **서버 로그 보강**(사용자 요청, `BuildInfo.DEBUG_MODE`에 묶음) -
  `[한 판 더]` 확정 시 클라이언트(`select_character`+`ready` 전송)와
  서버(재대전 준비 수신/전원 준비 완료) 양쪽에 진단 로그를 추가해서,
  다음에 비슷한 증상이 나면 어디서 끊기는지 바로 보이게 했다.
- 새 테스트 다수 추가, 전체 844개 통과.

### 현재 전체 테스트 개수
905개 (`scripts/tests/test_runner.tscn`, 전부 통과) - 최신 수치는 파일
맨 아래쪽 최근 항목을 확인할 것(이 숫자는 그때그때 갱신이 늦을 수 있음).

### 베타 배포 준비 - DEBUG_MODE를 export 프리셋으로 자동 전환
베타 배포를 앞두고 사용자가 지적: `DEBUG_MODE` 상수를 손으로 껐다 켰다
하는 방식은 "다시 켜는 걸 잊거나 켠 채로 내보내는 사고"가 나기 쉽고,
이 프로젝트는 실제로 사람이 기억하는 방식에 여러 번 실패했다(체크리스트에
적어두는 것만으로는 부족했다). 두 가지를 정리했다.

- **서버 콘솔 로그는 DEBUG_MODE와 무관한지 먼저 확인** - `server_main.gd`의
  `print()`를 전수 조사한 결과 처음부터(2-1) 거의 전부 무조건 출력이었다.
  예외는 딱 3곳, 이번 세션(3번째 재대전 버그 조사) 때 실수로
  `BuildInfo.DEBUG_MODE`에 묶어 넣은 진단 로그들뿐이었다 - 정작 베타 중에
  가장 필요할 로그가 배포하면서 꺼지는 셈이었다. 셋 다 무조건 출력으로
  되돌렸다.
- **export 프리셋을 `Web (dev)`/`Web (release)` 둘로 분리**
  (`export_presets.cfg`) - 후자에만 `custom_features="yd_release"` 태그를
  달았다. `build_info.gd`의 `DEBUG_MODE`를 `const := true`에서
  `static var DEBUG_MODE: bool = not OS.has_feature("yd_release")`로
  바꿔서, 상수를 손으로 안 고쳐도 어느 프리셋으로 export했는지가 자동으로
  값을 정한다. **Custom Features 태그가 실제 export에서만 바이너리에
  구워지고 에디터의 "실행"에는 절대 안 붙는다는 것을 임시 Windows
  프리셋으로 직접 실행해서 확인했다**(에디터 직접 실행은 항상 `false`,
  export한 바이너리만 `true`) - 그래서 "에디터에서는 항상 켜져 있어야
  한다"는 요구사항이 코드를 안 갈라도 저절로 만족된다. 자세한 검증
  방법/export 시점(`addons/build_stamp` 확장)·런타임(빌드 배너에 "디버그
  켜짐/꺼짐" 표시) 확인 방법은 `docs/web_export.md`("DEBUG_MODE 자동
  전환")와 `docs/deployment_checklist.md`(전면 개정)에 정리했다.
- 전체 844개 테스트 그대로 통과(로직 변경 없음 - 컴파일 타임 상수를
  런타임 계산 값으로 바꾼 것뿐).

### 베타 배포 준비 후속 - 실제 웹 빌드로 재검증 + export 경로 완전 분리
위 항목 배포 직후 사용자가 실제로 `Web (release)`를 export했는데 빌드
배너에 "디버그 켜짐"이 떴다고 보고 - "네이티브(Windows)로만 검증하고
웹에서만 나는 문제를 놓쳤을 수 있다"는 지적을 받아 다시 조사했다.

- **실제 웹/WASM 런타임으로 재검증**: 처음 시도한
  `--virtual-time-budget` 방식(헤드리스 브라우저에 가짜 시간을 흘려보내
  즉시 dump-dom)은 fetch/WASM 컴파일 같은 비동기 작업을 못 기다려서
  신뢰할 수 없었다 - **CDP(Chrome DevTools Protocol)로 헤드리스
  Edge를 직접 띄워 진짜 wall-clock 시간을 기다리는 방식**으로 바꿔서
  `Web (dev)`/`Web (release)`(release/debug 두 export 템플릿 다) 전부
  재확인했다. 결과: 메커니즘 자체는 웹에서도 정확히 동작함을 확인
  (`Web (dev)` → "디버그 켜짐", `Web (release)` → "디버그 꺼짐").
- **진짜 원인은 다른 데 있었다 - 에디터 GUI export는 메모리 상태가
  디스크와 어긋날 수 있다.** `export_presets.cfg` 자체는 (당시에도)
  정상이었다(`custom_features="yd_release"`가 그대로 있었음). 그런데도
  GUI로 export한 빌드에서 태그가 안 먹혔다 - 위에서 이미 한 번 겪은
  "에디터가 파일 전체를 덮어쓰는" 사고와 같은 원인 계열이 더 작은
  단위(필드 하나)로 재발한 것으로 보인다. **결론: 정확성이 중요한
  export(특히 배포용)는 항상 CLI(`--headless --export-release`)로 한다
  - CLI는 실행할 때마다 파일을 새로 읽으므로 에디터 세션 상태와 무관하다.**
  `docs/deployment_checklist.md`/`docs/web_export.md`에 굵게 경고로 남김.
- **export 경로를 완전히 분리**(사용자 요청 - GitHub Pages 저장소가
  `F:/Godot/web_build`인데 개발 중 테스트도 같은 폴더에 export하고 있어서,
  실수로 개발 빌드를 그 저장소에 커밋해 배포해버릴 경로가 있었다):
  `Web (dev)` → `F:/Godot/web_dev`(git과 무관, 평소 개발 테스트용),
  `Web (release)` → `F:/Godot/web_build`(GitHub Pages 저장소 - **여기 안에는
  항상 배포 빌드만 있다는 게 폴더가 다르다는 사실만으로 구조적으로
  보장됨**). `F:/Godot/web_open`(이전에 쓰던 임시 경로)은 이제 안 씀 -
  정리 대상.
- **`F:\Godot\build_release.bat` 추가**(`run_server.bat`과 같은 자리,
  같은 스타일) - Godot exe 전체 경로 + `--path`로 프로젝트 지정 +
  `--export-release "Web (release)"` + 끝에 `pause`. 매번 긴 CLI 명령을 손으로
  치는 대신 더블클릭 한 번으로 배포 빌드를 만든다.

### 2-6 후속 - 재접속 유예를 2분 → 60초로 단축(턴 제한과 같은 값)
친구와 실제로 플레이해보니 재접속 유예 2분이 너무 길다는 사용자 지적으로
`NetProtocol.RECONNECT_GRACE_MSEC`를 60초(`TURN_TIMEOUT_MSEC`과 같은 값)로
낮췄다. 자세한 내용은 `docs/multiplayer.md` §6 "턴 제한 시간" 항목에 정리,
여기는 요약만.

- **두 값이 같아지면서 생기는 경계(사용자가 먼저 확인 요청)** - 자기
  턴이 막 시작된 직후 끊기면 "유예 만료(확정 이탈)"와 "턴 시간 초과"가
  같은 시점에 겹칠 수 있다. 코드를 다시 읽어보니 `server_main.gd`의
  `_service_in_game_rooms()`가 원래부터 이 둘을 하나의 `if(OR)`로 묶어서
  `auto_confirm_least_damaging()`을 부르므로(별도의 두 분기가 아님),
  두 조건이 동시에 참이어도 호출은 항상 정확히 한 번뿐이었다 - **새로
  생긴 버그가 아니라 기존 설계가 이미 안전했음을 확인**한 것.
- **경계값 테스트 추가**(`test_room_connection.gd`,
  `_test_grace_expiry_and_turn_timeout_coincide_processes_turn_once`) -
  `server_main.gd`가 실제로 하는 순서(그레이스 만료 처리 → 이탈/타임아웃
  OR 판정 → 자동 확정)를 그대로 재현해서, 두 조건이 겹쳐도 턴 처리가
  정확히 한 번, current_player가 정확히 한 칸만 넘어가는지 확인한다.
- **실제 소켓으로도 확인**(임시로 두 값을 3초로 줄여서 검증 후 원복,
  스크립트는 삭제) - 2인 방에서 0번 플레이어를 턴 시작 직후 응답 없이
  바로 끊어서 재현: `player_left`가 `reason=timeout`으로 정확히 1번만
  오고, 최종 스냅샷에서 `current_player`가 정확히 1로(0에서 한 칸만)
  넘어갔고, 0번 플레이어의 확정 칸도 정확히 1개만 생겼다 - 중복 처리나
  턴 건너뜀 없음을 실제 코드로 재확인.
- **값은 상수 하나(`NetProtocol.RECONNECT_GRACE_MSEC`)만 바꾸면 된다** -
  전체 코드베이스를 훑어 이 값을 리터럴로 하드코딩한 곳이 없음을
  확인했다(전부 상수를 그대로 참조). 화면 카운트다운도 서버가 매초
  `player_timer(kind="reconnect")`로 계산해서 보내주는 값을 그대로
  표시할 뿐이라 클라이언트 쪽 코드 변경도 필요 없었다.
- **`REMATCH_READY_TIMEOUT_MSEC`(재대전 대기)은 이번 변경 범위 밖 -
  그대로 2분.** 원래 "재접속 유예와 같은 값"이라고 문서/주석에 적혀
  있었는데 이제 서로 달라졌으므로, 그 설명을 전부 고쳐서 "재대전 대기는
  게임이 이미 끝난 뒤라 게임 도중 끊김만큼 급하지 않다"는 별도 근거로
  바꿨다(`scripts/net/protocol.gd`/`docs/multiplayer.md` 양쪽).
- 새 테스트 포함 전체 849개 통과.

### 베타 배포 준비 후속 2 - build_release.bat 인코딩 깨짐 수정 + 프리셋 이름 영문화
사용자가 `build_release.bat`을 실제로 실행하니 콘솔이 한글 대신
`諛고룷 鍮뚮뱶 ?ㅽ뙣` 같은 깨진 글자를 찍고, 심하면 `'--headless'은(는)
내부 또는 외부 명령...이 아닙니다`처럼 명령줄 구조 자체가 깨졌다.

- **원인 두 가지를 같이 없앴다** - ① `export_presets.cfg`의 프리셋
  이름 `"Web (개발)"`/`"Web (배포)"`에 한글이 들어있어서, cmd.exe의
  콘솔 코드페이지가 안 맞으면 `--export-release`에 넘기는 그 이름 자체가
  깨져 Godot이 프리셋을 못 찾을 수 있었다. ② 배치 파일 자체도 파일을
  쓴 도구가 LF만 남긴 상태였는데(cmd.exe는 CRLF를 기대), `if (...) else
  (...)` 괄호 블록은 특히 줄바꿈에 약해서 인코딩/개행 문제가 겹치면
  블록 파싱 자체가 깨질 수 있었다.
- **프리셋 이름을 영문으로 변경**: `"Web (개발)"` → `"Web (dev)"`,
  `"Web (배포)"` → `"Web (release)"`(`export_presets.cfg`, 에디터
  닫힌 상태에서 수정). 코드/문서의 모든 참조(`CLAUDE.md`,
  `build_info.gd`, `docs/deployment_checklist.md`, `docs/web_export.md`,
  `.gitignore`)를 새 이름으로 맞췄다.
- **`build_release.bat`을 다시 씀**: 안내 문구를 전부 ASCII 영문으로
  바꾸고(`unix2dos`로 CRLF 강제), `if errorlevel 1 goto FAIL` +
  `:FAIL`/`:END` 레이블 방식으로 바꿔서 괄호 블록을 없앴다.
- **실제로 두 경로 다 실행해서 확인함**(파일만 쓰고 넘기지 않음,
  사용자 요청) - 성공 경로(`cmd /c "echo. | build_release.bat"`로
  끝의 `pause`에 자동으로 엔터를 흘려보냄)는 `Release build done ->
  F:/Godot/web_build/`가 안 깨지고 찍히는 것까지 확인. 실패 경로는
  존재하지 않는 프리셋 이름으로 임시 배치 파일을 하나 더 만들어(확인
  후 삭제) 돌려봤고, `Release build FAILED - check the error messages
  above.`가 마찬가지로 안 깨지고 찍히는 것과 Godot 에러 메시지가 실제
  프리셋 이름(`"Web (dev)"`/`"Web (release)"`)을 정확히 나열해주는 것도
  확인했다.
- **실제로 겪은 사고와 복구**: 확인 과정에서 `F:/Godot/web_build`(사용자가
  이미 만들어둔 실제 GitHub Pages git 저장소)의 `index.html`/`index.pck`를
  실수로 `rm`으로 지웠다 - 둘 다 커밋된 파일이라 `git restore`로 즉시
  복구했고 데이터 손실은 없었다. 이 폴더가 이제 진짜 git 저장소라는 걸
  스크린샷 대신 명령 결과로 마주친 뒤로는 그 안에서 삭제성 명령을 다시
  쓰지 않기로 했다 - export(덮어쓰기)만 쓴다.

### 친구 대상 실제 베타 테스트에서 발견된 버그 4건 - 3번(팩 재전송) 수정 완료, 나머지는 로그 확인 중
사용자가 친구들과 실제로 온라인 대전을 해보고 보고한 문제 4가지:
① 재대전 시 [한 판 더]를 둘 다 눌러도 바로 시작이 안 됨(준비 취소 후
재준비하면 됨), ② 그 상태로 시작하면 2번 플레이어 차례 대사가 두 번
재생됨, ③ 같은 캐릭터인데 판마다 다시 전송됨, ④ 서버를 껐다 켰더니
접속이 안 됨. 사용자 요청대로 로그를 기다리지 않고 코드만 먼저 훑어
원인 후보를 정리했고, 그 중 ③은 실제로 헤드리스 테스트로 재현·원인
확정까지 마쳐 바로 수정했다.

- **③ 확정 원인 + 수정 완료**: `CharacterLibrary.export_pack_bytes()`가
  쓰는 `ZIPPacker.start_file()`의 `modified_time` 기본값(0)이 "시각
  없음"이 아니라 **호출 시점의 실제 시각**으로 해석된다(DOS 타임스탬프,
  2초 단위) - 실제로 같은 프로필을 시간 간격을 두고 두 번 내보내
  바이트 단위로 비교해보니 257바이트 중 딱 2바이트만 달랐고, 그 위치가
  정확히 zip 로컬/중앙 헤더의 시각 필드였다(1.2~1.5초 간격으로는 재현이
  안 됐다가 - DOS 타임스탬프가 2초 단위라 우연히 같은 구간에 걸림 - 2.5초
  이상 벌리자 100% 재현됨). 이 때문에 `pack_hash`(=zip 바이트 전체의
  sha256)가 캐릭터를 안 바꿔도 판마다 달라져서, `Room.compute_needed_hashes()`가
  매번 "새 캐릭터"로 오판해 재전송을 걸었다. `_zip_write_entry()`가
  `start_file()`에 고정값(1)을 `modified_time`으로 넘기도록 고쳐서
  해결 - 시각 필드를 완전히 지워서 내용이 같으면 항상 같은 바이트가
  나오게 했다. 회귀 테스트 추가(`test_character_pack.gd::_test_export_pack_bytes_is_deterministic_across_time`,
  2.5초 간격을 실제로 기다려 확인). 전체 851개 통과.
- **① 재대전 시작 안 됨**: `server_main.gd`의 `_handle_ready()` →
  `_maybe_start_game()` → `Room.all_ready()` 경로를 끝까지 읽었지만
  막힐 지점을 코드로는 못 찾았다. 서버가 이미 DEBUG_MODE와 무관하게
  "재대전 준비 수신 - 슬롯 N ready=... (준비 X/Y)"와 "전원 준비 완료 -
  전송 단계로 진입" 두 로그를 찍고 있으므로(`server_main.gd:452`,
  `:512`), **재현 시 이 두 로그가 실제로 몇 번/어떤 순서로 찍히는지가
  결정적 단서** - "준비 2/2"까지만 찍히면 서버 쪽, 그것조차 안 찍히면
  클라이언트의 select_character/ready 전송 문제로 좁혀진다.
- **② 차례 대사 중복 - 확정 원인 + 수정 완료**: 처음엔 "재대전 경로만의
  문제"로 진단했는데, 사용자가 "게임 종료 후 로비로 나갔다가 새 방을
  만들어 시작해도 똑같이 두 번 난다"고 정정해줬다 - 재대전과 로비 재개설은
  서로 다른 코드를 타므로, 범인은 그 둘 중 하나가 아니라 **"브라우저를
  새로고침하지 않은 채 한 세션에서 게임에 두 번째로 들어가는 것" 자체였다.
  진입/이탈 경로 전체를 다시 훑어 원인을 확정했다: `_client`(GameClient)는
  세션 내내(재대전이든 로비 재개설이든 몇 번을 거치든) 단 하나의 인스턴스로
  살아있는데, `OnlineGameController`는 게임에 진입할 때마다(`Main.gd`의
  `_enter_game()`) 새로 만들어지면서 그 `_client`의 `turn_started` 등 12개
  시그널에 매번 새 리스너를 추가만 하고 이전 것을 안 끊었다 - 두 진입
  경로(재대전은 `_return_to_title()`을 안 거치고 곧장 재진입, 로비
  재개설은 거침) 둘 다 결국 같은 `Main.gd._on_online_game_play_started()`
  → `OnlineGameController.new()` 호출로 수렴하므로 증상이 똑같았던 것.
  `_disconnect_online_client_signals()`(`Main.gd`)는 `Main.gd` 자신이
  건 3개(`player_left`/`player_reconnected`/`player_timer`)만 끊을 뿐이라
  이 12개는 원래도 대상이 아니었다.
  **로컬(오프라인) 경로는 이 버그와 무관하다** - `LocalGameController`는
  `GameClient` 같은 영속 객체에 아무것도 connect하지 않고 매번 새
  `GameState`를 직접 조작할 뿐이고, `VoiceBank`/`SfxBank`의 `GameEvents`
  구독도 오토로드 `_ready()`에서 앱 생애주기 동안 딱 한 번만 연결되므로
  재진입해도 안 쌓인다.
  **수정**: `OnlineGameController`가 connect할 때 쓴 `Signal`/`Callable`
  쌍을 `_relay_connections`에 저장해뒀다가 `dispose()`에서 정확히 그
  쌍으로 disconnect하도록 바꿨다(`scripts/game/online_game_controller.gd`) -
  익명 람다라도 connect 시점에 만든 그 Callable 객체를 그대로 들고 있으면
  나중에 정확히 지목해서 끊을 수 있다. `LocalGameController`에도 대칭을
  위해 아무 것도 안 하는 `dispose()`를 추가했다(덕타이핑 계약 유지).
  `Main.gd`가 이 `dispose()`를 **두 지점 모두**에서 부르도록 배선했다 -
  `_return_to_title()`(로비 재개설 등 "타이틀로 완전히 복귀"를 거치는
  모든 경로가 여기로 수렴)과 `_enter_game()` 맨 앞(재대전처럼
  `_return_to_title()`을 안 거치고 곧장 다음 판으로 들어가는 경로 대비 -
  이미 `_return_to_title()`에서 dispose된 경우는 `active_controller`가
  이미 null이라 아무 일도 안 함). 두 지점 다 필요하다는 걸 실제로
  확인했다 - 회귀 테스트를 추가하기 전에 `dispose()` 호출을 일부러
  지워보고 실패하는 것까지 본 뒤 복구했다.
  회귀 테스트(`test_online_reentry_relay.gd`) - "재대전 경로"와
  "로비 재개설 경로"를 각각 별도 테스트로 만들어(사용자 요청 - 한쪽만
  고치고 다른 쪽을 놓치는 사고를 잡기 위함) `Main.tscn`을 실제
  인스턴스화하고 `_on_online_game_play_started()`를 3회 반복 호출,
  같은 `GameClient`의 `turn_started.get_connections().size()`가 항상
  1회차와 같은지 확인한다. 전체 857개 통과.
- **④ 서버 재시작 후 접속 안 됨 - 사용자 착오로 취소됨.** 로컬 재현 결과
  (포트 충돌 시 명확히 실패, 재시작 시 포트 즉시 반환)는 여전히 유효한
  기록으로 남기지만, 실제로 겪은 문제는 이게 아니었다 - 아래 "친구 대상
  실제 베타 테스트 후속" 항목의 ④'(정정)/⑤(신규) 참고.

### 친구 대상 실제 베타 테스트 후속 - 후속 1~4(dispose 안전성/구조화/전수
검사/영속 객체 감사) + 1번 조사 + ④'정정/⑤신규 버그
위 ②(대사 중복) 수정 보고 후 사용자가 요청한 후속 확인 4가지, "1번이
이미 고쳐졌을 가능성" 조사, 그리고 버그 목록 정정(④ 취소, ⑤ 신규)까지
한 번에 처리했다.

**후속 1 - dispose() 이중 호출 안전성**: 코드 검토 결과 이미 안전했다 -
`dispose()`는 끝에 `_relay_connections.clear()`를 무조건 실행하므로,
두 번째 호출은 빈 배열을 순회해 아무 일도 안 한다(`is_connected()` 확인도
이미 있어 설령 배열이 안 비었어도 에러 없이 스킵됨). `Main.gd`가 컨트롤러
참조를 어떻게 다루는지도 확인 - `_return_to_title()`은 `dispose()` 직후
`active_controller = null`, `_enter_game()`은 `dispose()` 직후 곧장 새
컨트롤러로 덮어쓰므로 실제로 같은 인스턴스에 두 번 불릴 경로는 없다.
그래도 방어적 보장이 되는지 직접 확인하기 위해 새 테스트 2개를
추가했다(`test_online_game_controller.gd`) - `dispose()`가 실제로
`_client` 쪽 연결을 지우는지(GameEvents 재방출이 아니라 연결 자체를
확인, 더 근본적인 검증), 연속 3회 호출해도 에러 없이 0개로 유지되는지.

**후속 2 - 장부를 구조로 강제**: "connect할 때 쌍을 저장한다"는 규약이
아니라 구조로 막고 싶다는 요청 - `_connect_relay()`를 `_connect_tracked()`로
이름을 바꾸고(더 명확한 의도 표현), `OnlineGameController` 안에서
`_client` 시그널에 연결하는 통로를 이 함수 하나로 통일했다. 새 테스트
`_test_every_client_signal_connection_is_tracked()` - `GameClient.get_script().get_script_signal_list()`로
스스로 선언한 시그널 전부를 리플렉션으로 순회해서, 실제 연결 개수가
`_relay_connections` 장부의 개수와 정확히 일치하는지 확인한다. **검증**:
일부러 `_client.hello_acknowledged.connect(func(): pass)`를 `_connect_tracked()`를
안 거치고 직접 추가해봤더니 이 테스트가 정확히 `"hello_acknowledged(실제
1개, 장부 0개)"`를 짚어내며 실패했다 - 확인 후 제거.

**후속 3 - 회귀 테스트 범위를 12개 전부로**: `test_online_reentry_relay.gd`가
`turn_started` 하나만 세던 것을, `GameClient`가 선언한 시그널 전부를
매 라운드 딕셔너리로 비교하도록 확장했다(`_all_connection_counts()`/
`_diff_counts()`) - 새 시그널이 추가돼도 손으로 목록을 안 늘려도 된다.
실패하면 어느 시그널이 새는지 이름까지 정확히 보여준다.

**후속 4 - 다른 영속 객체 전수 조사**: `signal ` 선언을 리포지토리 전체에서
훑어 표로 정리했다.

| 영속 객체 | 무엇이 연결하는가 | 연결 시점 | 해제 시점 |
|---|---|---|---|
| `GameClient`(온라인 세션 내내 하나) | `online_screen.gd`(14개) | `_ready()`, 세션당 1회 | 세션 자체가 끝날 때까지 불필요(1회성) |
| `GameClient` | `PackTransferClient`(4개) | `online_screen._ready()`의 `configure(_client)`, 1회 | 위와 동일 |
| `GameClient` | `Main.gd`(3개: player_left/reconnected/timer) | `_on_online_game_play_started()`, 게임 진입마다 | `_disconnect_online_client_signals()` - 이미 `is_connected()` 가드로 idempotent, 문제 없음 |
| `GameClient` | `OnlineGameController`(12개) | `_init()`, 게임 진입마다 **새 인스턴스 생성** | **예전엔 없었음(이번에 고친 버그의 본체)** → 지금은 `dispose()` |
| `GameEvents`(앱 전체 1개) | `VoiceBank`/`SfxBank`(오토로드) | 각자 `_ready()`, 앱 생애주기 1회 | 불필요(1회성, 앱 종료까지 삶) |
| `GameEvents` | `Main.gd` | `_ready()`, 1회 | 불필요 |
| `GameEvents` | `OnlineGameController`(12개 중 관련분) | 위와 같음 | 위와 같음(`dispose()`로 커버됨 - `GameEvents` 쪽에서 보면 `_client`를 통해 재방출되는 것뿐이라 실제 연결은 `_client`에 걸림) |
| `VoiceBank`(오토로드) 자체 시그널(`greeting_step_started`/`greeting_sequence_finished`) | `Main.gd` | `_ready()`, 1회 | 불필요 |
| `CharacterLibrary`/`AssetLoader`(오토로드) | 없음(시그널 자체가 없음) | 해당 없음 | 해당 없음 |
| `character_select_screen`(Main.tscn에 상주하는 단일 노드) | `Main.gd`(2개: selection_confirmed/back_requested) | `_ready()`, 1회 | 불필요 |
| `character_select_screen` 내부(슬롯 버튼 등) | 자기 자신의 `configure()` | 매 `configure()` 호출마다 | 매번 `queue_free()`로 슬롯 통째 재생성 - 발신자 자체가 죽으므로 안전(누수 아님) |

**결론**: `GameEvents`/`VoiceBank`/`CharacterLibrary`/`AssetLoader`처럼
앱 전체에서 하나뿐인 자원에 연결하는 코드는 전부 그 자원과 함께 앱
생애주기 동안 딱 한 번만 연결되는 구조였다 - 이번에 고친
`OnlineGameController`→`GameClient`가 **유일하게 "영속 객체 + 게임마다
새로 생기는 객체"였던 지점**이다. 캐릭터 편집 화면(`character_editor.tscn`)도
확인했지만 내부 패널들은 영속 오토로드에 아무것도 connect하지 않고
편집 화면 자기 자신의 버튼/필드에만 연결하므로, 편집 화면이 통째로
`queue_free()`될 때 같이 정리되어 이 패턴에 안 걸린다.

**1번(재대전 시작 안 됨)이 이번 수정으로 고쳐졌을 가능성 - 조사 결과
낮다고 판단**: 이번에 끊은 12개 시그널(`state_snapshot_received`/
`server_error`/`dice_rolled`/`die_held_changed`/`special_hand_rolled`/
`score_committed`/`yacht_scored`/`zero_scored`/`bonus_achieved`/
`turn_ended`/`turn_started`/`game_ended`/`game_state_started`)에는
ready/캐릭터 선택 확정 관련 핸들러가 하나도 없다 - `[한 판 더]` 확정
시 실제로 나가는 `_client.select_character()`/`_client.set_ready(true)`
호출은 버튼 클릭 → 함수 호출의 직접 경로이고, 그 앞단의 연결
(`character_select_screen.selection_confirmed` 등)은 전부 `Main.gd`/
`character_select_panel.gd`의 `_ready()`에서 한 번만 연결되는 것들이라
이번 버그의 영향권 밖이었다. 그리고 `_refresh_game_over_ui()`에
`_game_over_ui_built` 가드가 있어 `state_changed`가 중복으로 와도
버튼이 두 개 생기지 않는다는 것도 확인했다 - "버튼이 두 개 생겨서
한 번 눌러도 두 번 처리됐다"는 경로도 아니다.
**ready 처리 방식 확인**: 두 경로가 서로 다르다 - 로비의 수동 [준비
완료] 버튼(`online_screen.gd::_on_ready_button_pressed()`)은 로컬에
저장된 `_players[my_index]["ready"]`를 뒤집어 보내는 **토글**이라
네트워크 중복에 원칙적으로 약하지만, `[한 판 더]` 확정이 실제로 쓰는
`confirm_rematch_character()`의 `_client.set_ready(true)`는 **절대값**
이라 중복 전송에 강하다(같은 값이 두 번 가도 결과가 같음) - 그리고
1번 버그는 정확히 후자(재대전 확정) 경로에서 난 것이므로, 토글이
문제라는 가설은 이 경로엔 해당하지 않는다. 토글 방식 자체를 절대값으로
바꾸는 건 이번엔 보류(문제가 재현된 경로가 애초에 토글을 안 씀).
**서버 로그 추가**: `_handle_ready()`가 같은 슬롯에서 직전과 동일한
ready 값이 연속으로 오면 `[서버][경고] 방 %s: 슬롯 %d에서 동일한
ready 값(%s)이 연속으로 수신됨 - 메시지 중복 의심`을 찍도록 했다
(`server_main.gd`) - 재현되면 이 로그로 중복 전송 여부 자체는 바로
확인할 수 있다. **사용자의 수정본 재테스트 결과를 기다린다.**

**④'(정정) + 4번은 로그만**: "서버 재시작 후 접속 안 됨"은 사용자
착오로 취소됐고, 실제로 있었던 일은 "두 번째 게임 도중 서버 접속이
끊김"(재현 조건 미상)이다. 지금 고치라는 요청이 아니라 다음 재현 때
바로 잡히게 로그만 보강했다(`server_main.gd`):
- `_on_peer_disconnected()`가 이제 "사유"(우리가 먼저 끊었으면
  hello 타임아웃/핑 무응답 중 어느 쪽인지, 아니면 "상대가 스스로 닫음
  - 엔진이 구체적 사유를 안 줌")와 "마지막 수신 후 경과 시간"을 항상
  찍는다. `WebSocketMultiplayerPeer.peer_disconnected(id)`는 원래
  종료 사유/코드를 안 주므로, 서버가 스스로 끊은 경우만 미리
  `_disconnect_reason`에 적어두고 나머지는 "엔진이 안 준다"고 정직하게
  표시하는 방식으로 한계 안에서 최대한 정보를 남겼다.
- 포트 충돌 메시지를 `ERR_ALREADY_IN_USE`일 때 전용 문구("포트 %d이(가)
  이미 사용 중입니다 - 다른 서버 프로세스가 이미 떠 있는지 확인하세요")로
  더 명확하게 갈랐다(그 외 에러는 기존 `error_string()` 그대로).
  로컬 재현으로는 이미 조용히 실패하지 않는다는 게 확인된 상태였지만
  (위 ④ 기록 참고), 사용자가 콘솔을 훑어볼 때 더 바로 눈에 띄도록
  문구 자체를 개선했다.

**⑤(신규) - 게임 종료 후 새로고침(F5)하면 방으로 복귀 못 함, "서버를
깨우는 중"에서 멈춤**: `room.gd`/`RoomManager.join_room()`을 다시 읽어
재접속 수락 조건을 확인한 결과, **토큰 매칭이 방 상태와 완전히 무관하게
항상 먼저 확인되도록 이미 짜여 있었다**(`RoomManager.join_room()`의
주석에도 "방 상태와 무관하게 항상 그 슬롯으로 복귀시킨다"고 명시돼
있음) - `REMATCHING`도 `TRANSFERRING`/`IN_GAME`과 완전히 같은 방식으로
`mark_slot_disconnected()`/재접속을 받아주고, 오히려 재대전 대기 시간
(`REMATCH_READY_TIMEOUT_MSEC`, 2분)이 게임 도중 그레이스(60초)보다
넉넉하다(`_service_rematch_rooms()`는 슬롯별 60초 그레이스를 아예 안
보고 방 전체 2분 마감만 본다). 즉 **room.gd의 상태 머신 자체에는 게임
종료 후 재접속을 거부하는 코드가 없다.**

그래서 "서버를 깨우는 중"이 뜬다는 것 자체가 `join_room` 요청이 서버에
도달하기도 전에 `connect_to_server()`(WebSocket 연결 자체)가 실패하고
있다는 뜻으로 해석했다 - 이 문구는 `online_screen.gd::_on_connection_failed()`
에서 뜨는데, 이 함수는 `room.gd`를 전혀 모른다(그보다 훨씬 아래
계층). **이건 위 4번(두 번째 게임 도중 서버 접속이 끊김)과 같은 근본
원인일 가능성이 있다** - 서버가 그 시점에 실제로 응답 불능이었다면,
이후의 F5 재연결 시도가 전부 `connect_to_server()` 단계에서 실패하는
게 당연하다.

그와 별개로 문구 자체에 실제 버그 두 개를 찾아 고쳤다:
1. `attempt_session_resume()`(F5 세션 복귀)은 `_reconnecting_after_disconnect`를
   안 켜므로 `_on_connection_failed()`가 항상 "서버를 깨우는 중입니다"
   (Render 콜드스타트 대비 문구)로 빠졌다 - 로컬 서버는 깨울 대상이
   없는데도 이 문구가 나가 진짜 원인(연결 실패)을 가렸다. 판단 로직을
   `_connection_retry_label()`로 분리하고 `_resuming_session` 분기
   ("이전 게임에 다시 연결하는 중")를 추가해 세 상황(게임 도중 재접속/
   세션 복귀/진짜 첫 접속)을 구분했다.
2. **더 심각한 버그**: 세션 복귀 시도가 재시도를 다 쓰고도 연결에
   실패하면(`_reconnecting_after_disconnect`와 달리) `_resuming_session`이
   계속 `true`로 남고 `reconnect_exhausted`도 안 나가서, 화면이 온라인
   화면(연결 패널)에 마지막 메시지만 찍힌 채 조용히 멈췄다 - **사용자가
   본 증상과 정확히 일치한다.** `_on_server_error()`의 세션 복귀 실패
   처리(`SessionStore.clear()` + `_show_connect_panel()`)와 같은 방식으로
   맞췄다.

새 테스트(`test_online_reconnect_messages.gd`) - `_connection_retry_label()`이
세 상황을 정확히 구분하는지(우선순위 포함), 재시도 소진 시 실제로
연결 패널로 돌아오고 `_resuming_session`이 풀리는지 확인한다(`ReconnectBackoff.attempt`를
상한으로 미리 맞춰 실제 1초+ 타이머를 안 기다리고 헤드리스로 즉시
검증). 전체 869개 통과.

**남은 것**: 1번 재테스트 결과(사용자), 4번의 실제 재현(로그가 준비됐으니
다음에 걸리면 사유/경과시간이 남을 것).

### 확인 1~4 (사용자가 위 후속 1~4 보고 받은 뒤 요청한 추가 확인/구현)
2번을 종결로 확정받은 뒤, 남은 항목(1번/4번/5번)에 대해 사용자가 요청한
네 가지 확인을 처리했다 - 그 중 1번(유예 시간 분리)과 3번(조용히
버려지는 메시지)은 코드 수정까지 포함한다.

**확인 1 - 유예 시간 두 개(REMATCH_READY_TIMEOUT_MSEC vs
RECONNECT_GRACE_MSEC)를 혼동한 것 아닌가, 수정 완료**: 사용자가 정확히
짚었다 - "재대전 대기는 오히려 2분으로 더 넉넉하다"는 이전 보고는
결론은 맞았지만 이유가 틀렸었다. 다시 조사해보니 `RECONNECT_GRACE_MSEC`
(60초)는 `REMATCHING` 중에도 슬롯마다 마감 시각이 설정은 됐지만, 그
마감을 실제로 확인해서 슬롯을 내보내는 코드(`is_grace_expired()`를
부르는 `_service_in_game_rooms()`)가 `room.state == IN_GAME`인 방만
처리하도록 필터링돼 있어서 **REMATCHING 중엔 60초 시계가 설정만 되고
한 번도 확인되지 않는 죽은 값**이었다 - 그래서 실제 상한은
`REMATCH_READY_TIMEOUT_MSEC`(2분) 하나뿐이었다. "우연히 60초보다
넉넉하다"에 기대는 구조라 다음에 누가 `_service_in_game_rooms()`의
상태 필터를 무심코 넓히면 조용히 60초로 줄어드는 사고를 만들 수 있었다.
사용자가 요청한 대로 명시적으로 분리했다:
- `NetProtocol.RECONNECT_GRACE_MSEC` → `IN_GAME_RECONNECT_GRACE_MSEC`로
  이름 변경(값 60초 그대로, `TRANSFERRING`/`IN_GAME` 전용).
- `NetProtocol.POST_GAME_RECONNECT_GRACE_MSEC`(3분, 신규) - `REMATCHING`
  전용. 단순 상수 추가로 끝나지 않았다 - **실제로 3분을 보장하려면
  세 곳을 같이 고쳐야 했다**: ① `RoomManager.remove_peer()`가
  `room.state`를 보고 두 유예 중 맞는 걸 골라 `mark_slot_disconnected()`
  (이제 `grace_msec` 매개변수를 받음)에 넘김. ② `Room.begin_rematch_wait()`가
  게임 종료 순간 이미 GRACE_PERIOD인 슬롯의 마감 시각을 3분 기준으로
  다시 계산(안 그러면 게임 도중 확보한 60초의 나머지만 남은 채로 결과
  화면에 들어감). ③ 새 `Room.grace_expired_disconnected_slots()`를
  `server_main.gd::_service_rematch_rooms()`가 매 프레임 확인해서, 방
  전체 2분 타이머와 **독립적으로** 그 슬롯 하나만 내보냄 - 그리고 방
  전체 2분 타이머 쪽은 새 `Room.not_ready_connected_slots()`(연결된
  슬롯만)를 쓰도록 바꿔서, 끊긴 사람이 방 전체 타이머에 이중으로 안
  걸리게 했다(IN_GAME의 `is_grace_expired()`/`is_turn_timed_out()`을
  독립된 OR 조건으로 처리하는 기존 패턴과 같은 구조). `docs/multiplayer.md`
  §6 "재대전 대기 중 끊김"을 이 정정 경위와 함께 다시 썼다. 새 테스트
  8개(`test_room_manager.gd`/`test_room_rematch.gd`) 추가.
- **일부러 남긴 단순화**: `player_timer(kind="rematch")` 카운트다운
  표시는 여전히 방 전체 2분 기준이다 - 끊긴 사람의 개별 3분 유예는
  화면에 따로 안 보여준다(그 사람은 화면을 안 보고 있고, 연결된
  다른 플레이어에겐 "방이 언제 포기하는지"인 2분 쪽이 더 의미 있는
  정보라고 판단). 필요해지면 나중에 분리 가능.

**확인 2 - 5번은 원인 미상으로 남겨둠, 종결 아님**: 지난 보고에서 고친
두 가지(잘못된 "서버를 깨우는 중" 문구, 재시도 소진 후 화면이 조용히
멈추는 것)는 "실패했을 때 어떻게 보이는가"의 수정이지 "왜 실패했는가"의
해결이 아니라는 지적에 동의한다 - **5번은 계측 완료, 원인 미상 상태로
남긴다.** 추가 확인한 것:
- 재시도 소진 후 실제로 쓸 수 있는 행동이 있는가 - 있다.
  `_show_connect_panel()`로 돌아가면 [방 만들기]/[방 참가]/[뒤로]가
  전부 눌리는 상태다(막힌 화면이 아님) - 다만 "원래 그 방으로 자동
  재시도"라는 의미의 전용 [다시 시도] 버튼은 없다(세션이 이미
  `SessionStore.clear()`로 지워진 뒤라 "그 방"이라는 개념 자체가
  없어짐 - 재시도하려면 새로 방을 만들거나 참가해야 함).
- 실패 사유가 화면 문구로 구분되는가 - 부분적으로만. "서버에 도달 못함"
  (`_on_connection_failed`)과 "도달했으나 거부됨"(`_on_server_error`,
  구체적 `message` 포함)은 서로 다른 경로/문구로 이미 구분된다. "데이터
  수신 중"(예: 캐릭터 팩 전송 단계)은 `PackTransferClient.get_status_text()`가
  이미 별도 문구를 낸다. 셋을 한 화면에서 나란히 비교하며 보여주는
  통합 뷰는 없지만, 최소한 서로 다른 세 실패 유형이 서로 다른 라벨에
  써지긴 한다.

**확인 3 - 새 가설(상태 전이 중 도착한 메시지가 조용히 버려짐), 실제로
발견해서 고침**: `server_main.gd`의 모든 `_handle_*` 함수를 전수
조사했다. 결과: `_handle_ready()`/`_handle_select_character()`(1번과
가장 관련 있는 두 핸들러)는 이미 `_send_error()`를 호출하고 있어
완전히 조용한 드롭은 아니었다 - 다만 `_send_error()` 자체가 서버 콘솔에
아무것도 안 남기고 클라이언트에게만 보냈어서, 서버 로그만 보면 마치
아무 일도 없었던 것처럼 보였다. 반면 2-5(캐릭터 팩 전송) 핸들러
4개(`_handle_pack_ready`/`_handle_request_character_pack`/
`_handle_upload_pack_chunk`/`_handle_request_pack_chunks`)에는 **진짜
완전히 조용한 드롭이 다수** 있었다 - 코드 주석에 "조용히 무시한다"고
명시적으로 적혀 있던 것들("어차피 방어적 검사라 평소엔 안 걸릴
것"이라는 가정 하에). 사용자 지적대로 이 가정 자체가 위험하다(정확히
이런 "평소엔 안 걸릴" 경로에서 실제 버그가 난 전례가 이미 있음 -
2-6B 후속 서버 크래시).
- `_send_error()`가 이제 보내기 전에 항상
  `[서버][에러 응답] peer=%d code=%s message=%s`를 콘솔에 남긴다.
- 새 `_log_ignored(message_type, reason, sender_id, room)` 헬퍼를
  만들어 완전히 조용했던 드롭 지점 전부(위 4개 핸들러의 모든 검증
  실패 경로, 약 15곳)에 심었다 - 형식은 사용자가 요청한 그대로
  `[서버][무시됨] 메시지=X 사유=... peer=N 방=YYYY 상태=Z`.
- **실제 소켓으로 검증**: 정상 흐름(방 생성→참가)에서는 이 로그가
  전혀 안 찍히는 것과, 일부러 상태가 안 맞는 시점에 `pack_ready`를
  보내면 정확히
  `[서버][무시됨] 메시지=pack_ready 사유=TRANSFERRING 상태가 아님 peer=... 방=... 상태=LOBBY`
  가 찍히는 것 둘 다 확인했다.
- **"보류했다가 상태 진입 후 처리" 제안은 검토 후 보류**: `_handle_ready()`/
  `_handle_select_character()`가 거부하는 유일한 경우는 room.state가
  `TRANSFERRING`/`IN_GAME`일 때뿐인데, `[한 판 더]` 확정은
  `select_character`+`ready(true)` 딱 2개만 순서대로 보내고 둘 다
  같은 프레임 처리 사이클 안에서 처리되므로(서버가 매 프레임 서비스
  루프를 먼저 돌리고 그 다음에 그 프레임에 도착한 메시지를 처리),
  "정상적으로 보낸 단일 메시지 쌍이 우연히 상태 전환 사이에 낀다"는
  자연스러운 레이스를 코드상 찾지 못했다 - 이런 레이스가 있으려면
  애초에 **중복 전송**이 먼저 있어야 하는데, 그건 확인 3의 나머지
  계측(위 `_log_ignored`, 그리고 아래 "1번 새 가설 확인"의 ready 중복
  경고)으로 이미 잡을 수 있다. 그래서 검증되지 않은 복잡도(보류 큐)를
  미리 넣기보다, 재현 로그를 먼저 보고 실제로 필요한지 판단하기로
  했다.

**확인 4 - 터널 가능성 + 클라이언트 계측, 완료**: `GameClient`
(`scripts/net/game_client.gd`)에 서버와 대칭되는 계측을 추가했다:
- 마지막 서버 메시지 수신 후 경과 시간(`_last_received_msec`, 서버의
  `_last_seen_msec`와 같은 개념).
- 핑 간격(`_last_ping_received_msec`) - **진짜 RTT는 아니다**(현재
  프로토콜은 서버→클라이언트 ping에 클라이언트가 pong만 돌려줄 뿐,
  그 pong이 서버에 언제 도착하는지 클라이언트는 알 방법이 없다 - RTT는
  서버 쪽에서만 잴 수 있음). 대신 "직전 ping으로부터 몇 ms 만에 다음
  ping이 왔는가"를 재서, 정상(5000ms 근처)에서 벗어나면 연결이 이미
  흔들리고 있다는 신호로 쓴다.
- 연결 종료 시 close_code/close_reason(`WebSocketPeer.get_close_code()`/
  `get_close_reason()`) - **구현 중 실제 함정을 하나 잡았다**: 처음엔
  `_process()`가 `CONNECTION_DISCONNECTED`를 감지한 시점에 바로
  `_peer.get_peer(1)`을 불렀는데, 그땐 이미 엔진이 내부 peer 목록에서
  지워버린 뒤라 `Condition "!peers_map.has(p_id)" is true` 콘솔 ERROR가
  났다(실제 소켓으로 kill -9 재현해서 직접 목격함). `peer_disconnected`
  **시그널** 시점에 미리 캡처해뒀다가 `_process()`는 캡처된 값만 읽도록
  고쳐서 해결 - 이 시점엔 에러 없이 값을 읽을 수 있음을 실제로
  확인했다(다만 kill -9처럼 정상 종료 프레임이 아예 없는 경우
  close_code는 -1로 남는 게 맞는 동작임도 확인함 - "코드 없음"과
  "코드=1006(비정상 종료)"을 구분하려면 상대가 최소한의 TCP FIN이라도
  보내야 하는데, 완전한 프로세스 강제 종료는 그것조차 없다).
- `PING_INTERVAL_MSEC`/`PING_TIMEOUT_MSEC` 상수를 `server_main.gd`
  전용에서 `NetProtocol`(공유 파일)로 옮겼다 - 클라이언트도 같은 간격
  값을 참조해야 해서.
- **판단 기준을 문서에 명시**(사용자 요청) - 다음 베타에서 4번/5번이
  재현되면 서버 콘솔/클라이언트 화면 로그/cloudflared 창을 같은 시각
  으로 대조해서, cloudflared 창에 같은 시각 기록이 있으면 원인은
  터널로 보고 **더 파지 않고 2-7(Render 배포)로 직행**한다는 기준을
  `docs/multiplayer.md`("베타 트러블슈팅" 새 절)에 적어뒀다.

전체 881개 테스트 통과. `_send_error()`/`_log_ignored()`/클라이언트
계측 모두 실제 소켓으로 동작을 확인했다(정상 흐름에서 노이즈 없음,
비정상 상황에서 정확한 로그 확인).

### 확정 1~3 - 서버 크래시 계측 + 청크 유실의 진짜 원인(엔진 버그) 확정 + 수정
사용자가 실제 베타 세션의 서버 콘솔/cloudflared 로그를 대조해서 세 가지를
확정해줬다: (1) 4번·5번의 원인은 터널이 아니라 서버 프로세스가 재대전
2판째 시작 순간 죽는 것, (2) 청크 유실은 "에러 난 청크 N"과 "실제로
없어진 청크"가 항상 N-1로 정확히 어긋난다(18개 전부 일치), (3) 서버의
`outbound_buffer_size`가 아직 기본값(65535)이었다. 지시받은 순서(확정
2 → 확정 3 → 확정 1 계측 → 여기서 보고)대로 처리했다.

**확정 2 - 청크 유실, 원인이 처음 추정과 달랐다(더 근본적인 엔진 버그를
실제로 재현해서 확정함)**: 처음엔 "확인된 개수만 세는" 완료 판정이
재전송 중복 확인으로 인해 실제보다 빨리 채워지는 버그라고 판단하고
고쳤다(아래 참고 - 이것도 실제 버그였다). 그런데 그 수정을 넣은 뒤에도
회귀 테스트(작은 버퍼로 강제 재현)가 여전히 실패했다 - "청크 X/30 실제
송신 완료"가 매번 찍히는데 수신 측은 0개를 받았다. 최소 재현 스크립트로
직접 확인한 결과, **`WebSocketMultiplayerPeer.put_packet()`은 보내는
쪽 버퍼가 이미 찬 상태에서 불려도 항상 `OK`(0)를 반환한다** - 엔진
콘솔에는 `Condition "... > outbound_buffer_size" is true. Returning:
ERR_OUT_OF_MEMORY`가 찍히지만, 이건 내부 C++ 함수(`wsl_peer.cpp`의
`_send`, 이 프로젝트의 GDScript `_send()`와 이름만 같은 별개 함수)의
로그일 뿐 `put_packet()`의 반환값에는 반영되지 않는다(Godot 4.7.2,
32768바이트 버퍼에 32768바이트 패킷을 연속 10번 넣는 최소 재현으로
확인 - 5번째부터 버퍼가 찼는데도 10번 전부 `OK`를 반환했고 실제로
도착한 건 5번째 것 하나뿐이었다). **이 프로젝트의 "보냈다"를
"도착했다"로 착각한 사고 목록에 여섯 번째가 추가된 셈인데, 이번엔
GDScript 코드가 아니라 엔진 자체가 그렇게 착각하게 만들었다는 점이
다르다.** 그래서 반환값 확인은 그대로 두되(다른 이유로 진짜 에러가
날 수도 있으니 방어적으로 유지), **`WebSocketPeer.get_current_outbound_buffered_amount()`로
"지금 이미 못 나간 데이터가 있는지"를 put_packet() 호출 전에 미리
확인**하는 방식으로 바꿨다(`server_main.gd`의 `_send()`/`_flush_outgoing_queues()`,
`game_client.gd`의 `_send()`/`_flush_outgoing_queue()` 네 곳 전부). 이
값이 0보다 크면 아예 put_packet()을 시도하지 않고 큐에 넣는다 - 이게
이제 진짜 방어선이고, 반환값 확인은 보조 수단으로 격하됐다.
- 완료 판정 자체도 별도로 고쳤다(요청받은 그대로): "확인된 개수"
  (`confirmed: int`)가 아니라 (순번,수신자) 쌍마다 성공 플래그를 정확히
  기록하는 Dictionary(`confirmed: {recipient_index: {sequence: true}}`)로
  바꿔서, 재전송으로 같은 쌍이 두 번 확인돼도 개수가 안 부풀도록 했다
  (`_mark_relay_confirmed()`/`_all_relay_pairs_confirmed()`). 두 수정
  (buffered_amount 사전 확인 + 정확한 완료 판정)은 서로 다른 층의
  문제라 둘 다 필요했다 - 전자가 없으면 애초에 데이터가 유실되고,
  후자가 없으면 유실이 있어도 "완료"로 오판할 수 있었다.
- **회귀 테스트**(`test_pack_relay_buffer_overflow.gd`, 사용자 요청) -
  보내는 쪽 버퍼를 일부러 작게(패킷 하나(약 43.8KB)는 들어가지만 두
  개는 못 들어가는 크기) 설정하고 30개 청크를 한 프레임 안에 몰아서
  보낸 뒤, 실제 로컬 소켓으로 붙은 수신자가 30개를 빠짐없이(내용까지
  정확히) 받는지 확인한다. 이 수정을 빼고 돌리면 실제로 실패하는 것도
  확인했다(0개 수신). 테스트 작성 중 겪은 함정: `hello_ok`/`room_code`
  같은 스칼라를 람다 안에서 대입하려다 또 이 프로젝트의 고질병(GDScript
  람다가 바깥 지역 변수를 값으로 캡처)을 밟았다 - Dictionary로 박싱해서
  해결(§8.5에 이미 여러 번 기록된 패턴, 검증 스크립트 자체에서 또
  반복됨).

**확정 3 - 보내는 쪽 버퍼 1MB로, 실제 적용값 로그 출력**: 서버
(`server_main.gd::_start_server()`)와 클라이언트(`game_client.gd::connect_to_server()`)
양쪽에 `set_outbound_buffer_size(1MB)`를 추가하고, 받는 쪽과 똑같이
"요청 X바이트 → 실제 X바이트" 형식으로 되읽어 로그를 남긴다. 상수는
`NetProtocol.SERVER_OUTBOUND_BUFFER_BYTES`/`CLIENT_OUTBOUND_BUFFER_BYTES`로
공유 파일에 추가(받는 쪽 상수와 같은 패턴). **버퍼를 키워도 확정 2의
사전 확인 수정을 생략하면 안 된다** - 버퍼는 압력을 줄일 뿐이고,
`put_packet()`의 반환값이 못 믿을 신호라는 사실 자체는 버퍼 크기와
무관하게 여전히 참이라 더 큰 캐릭터 팩에서는 1MB 버퍼로도 같은 패턴이
재발할 수 있다.

**확정 1 계측(원인 규명 자체는 다음 크래시 재현 이후) - `F:\Godot\run_server.bat`**:
- Godot 실행 직후 `%ERRORLEVEL%`을 저장해 종료 코드를 화면에 크게
  표시한다 - 0이면 "정상 종료", 그 외엔 "UNEXPECTEDLY... 프로세스가
  죽었다"로 명확히 구분(전에는 창이 그대로 떠 있어서 서버가 살아있다고
  착각할 수 있었다).
- `--log-file "F:\Godot\logs\server.log"`를 추가해 콘솔 출력을 파일에도
  그대로 남긴다(콘솔이 스크롤로 밀려나거나 창이 닫혀도 파일은 남음) -
  한글 `print()` 내용까지 정확히 그대로 파일에 남는 것을 실제로 확인했다.
- 서버 코드 자체의 `quit()` 호출은 원래 딱 한 곳(포트 충돌)뿐이었고
  이미 이유를 출력한 뒤 종료하고 있었다 - "조용히 끝나는 경로"는 이
  스크립트 안에는 없었다. 즉 미스터리 크래시는 `quit()`을 거치지 않는
  진짜 엔진 크래시(또는 OS 강제 종료)라는 뜻이고, 그건 GDScript 쪽
  에러 처리로는 못 잡는다 - 그래서 종료 코드 자체가 유일한 단서다.
- **실제로 두 경로 다 검증함**(PowerShell로 프로세스를 강제 종료해
  크래시를 흉내내고, 포트 충돌도 재현) - 둘 다 "UNEXPECTEDLY(exit
  code -1 / 1)"로 정확히 표시되고 로그 파일도 정확한 한글 인코딩으로
  남는 것까지 확인했다.

### 확정 2/3 후속 - 정정 2건 + 확인 2건 (사용자 지적 - 재현은 별도 진행)

**정정 1(사용자) - "에러 난 청크 N ↔ 유실된 청크 N-1" 진단은 오프셋
착시였다.** Godot의 `ERROR`는 stderr, `print()`는 stdout으로 나가서
콘솔에서 줄 순서가 뒤바뀔 수 있다 - 에러 줄이 한 줄 늦게 보였을
뿐이고, 실제 법칙은 "에러 하나 = 청크 하나 유실"이다(개수 18:18만
맞았고 오프셋은 표시 순서 아티팩트). 최소 재현 결과(반환값이 항상
`OK`)가 맞다 - 코드 수정 없음, 이해만 정정.

**정정 2(사용자) - `docs/multiplayer.md` §8.5-1의 과거 기록을 고쳤다.**
"`put_packet()`이 `ERR_OUT_OF_MEMORY`를 반환하는데 확인 안 해서
유실됐다 → 큐+재시도로 해결했다"는 결론이 지금 확인된 사실(반환값은
항상 `OK`)과 모순된다 - `docs/multiplayer.md` §8.5-1에 정정 각주를
추가하고, 진짜 메커니즘(반환값 자체가 항상 성공을 거짓말함)과 "그
시점 증상이 사라진 진짜 이유는 나중의 받는 쪽 버퍼 상향(§8.5-6)이었을
가능성이 높다"는 재해석을 새 §8.5-7로 정리했다. 이 세션 위쪽의 같은
착오("전송이 2%에서 멈춤" 항목)에도 같은 취지의 정정 각주를 남겼다.

**확인 1(사용자) - 사전 확인 조건이 너무 보수적이었다, 수정 완료.**
처음 짠 조건은 `get_current_outbound_buffered_amount() > 0`이면 무조건
대기 - 이러면 프레임당 패킷 하나만 나가서 1MB 버퍼가 사실상 무의미해진다.
사용자가 제안한 `buffered + 이번 크기 + 여유 <= 한도` 형태로 바꿨다
(`NetProtocol.has_room_to_send_now()`, 여유는 청크 하나 크기
`estimate_encoded_chunk_bytes()`를 재사용 - 이 프로토콜에서 가장 큰
메시지 종류이므로 "한 번 더 최대 크기 메시지가 와도 여유가 있다"는
뜻이 된다). 서버·클라이언트 `_send()`/`_flush_outgoing_queue(s)` 네
곳 전부 반영. 회귀 테스트(`test_pack_relay_buffer_overflow.gd`)의
버퍼 상수도 이 새 조건(현재+메시지+여유)에 맞춰 100000바이트로
재조정(예전 50000바이트로는 여유 계산 때문에 아무것도 못 보내는
데드락이 남을 뻔했다 - 테스트 자체를 돌려보고 잡음).
**59청크(약 1.9MB) 실측**: 로컬 소켓·1MB 버퍼 기준 새 방식 약
1.26~1.29초, "조금이라도 남으면 무조건 대기"로 되돌려 측정하면 약
1.38초 - 이 크기/환경(로컬 루프백)에서는 차이가 크지 않지만(버퍼가
워낙 빨리 드레인됨), 지연이 큰 실제 네트워크에서는 차이가 더 클
것으로 예상된다. 자세한 수치는 `docs/multiplayer.md` §8.5-7.

**확인 2(사용자) - 같은 함정이 다른 곳에도 있는지 전수 조사, 완료.**
`server_main.gd`/`scripts/net/`에서 반환값으로 성공을 판정하는 지점을
전부 찾았다:
| 위치 | 판정 대상 | 신뢰 가능? |
|---|---|---|
| `server_main.gd` `_start_server()` `peer.create_server(port)` | 포트 바인딩 성공 | **예** - 포트 충돌을 실제로 만들어 `ERR_ALREADY_IN_USE`가 정확히 반환되는 것을 이미 직접 확인함(베타 버그 목록 4번 조사 때) |
| `server_main.gd`/`game_client.gd`의 `put_packet() != OK` (4곳) | 패킷 전송 성공 | **아니오(확정)** - 이번에 확인한 대로 버퍼 초과 시 거짓 `OK`. 반환값 확인은 방어적으로 유지하되 주된 판정은 `get_current_outbound_buffered_amount()` 사전 확인으로 교체함 |
| `game_client.gd` `connect_to_server()`의 `_peer.create_client(url)` | 클라이언트 소켓 생성 성공 | **부분적으로 신뢰, 이미 안전하게 설계됨** - 이 반환값은 "URL 형식이 유효한지"만 확인하는 것으로 보이고, 실제 "연결이 됐는지"는 이 반환값이 아니라 이후 `get_connection_status()`를 매 프레임 폴링해서 판단한다(반환값에만 의존하지 않는 기존 설계가 이미 안전함) |
| `received_pack_cache.gd`의 `DirAccess.make_dir_recursive_absolute()`/`remove_absolute()` (3곳) | 디스크 폴더 생성/삭제 성공 | **다른 위험군이라 별도 확인 안 함** - `put_packet()`처럼 "버퍼에 쌓아뒀다가 나중에 실패할 수 있는" 비동기/버퍼링 API가 아니라 즉시 완료되는 동기 파일시스템 호출이라, 같은 종류의 "성공을 거짓으로 반환" 위험이 성립하지 않는다고 판단 - 다만 이건 추론이지 이번에 직접 재현해서 검증한 건 아니다 |

새로 뭔가를 더 고치지는 않았다 - `put_packet()` 외엔 전부 신뢰
가능하거나(포트 바인딩, connect_to_server의 실질 판정 경로) 다른
위험군(파일시스템)이라는 결론.

전체 884개 테스트 통과, 위 변경 모두 실제 소켓/실측으로 재확인함.

**여기서 다시 멈춘다(사용자 지시)** - 다음은 사용자가 브라우저 두 개로 직접
재현한다(1판 정상 종료 → 한쪽이 나가기 → 새로고침 → 같은 방 재입장 →
2판 시작 순간 서버가 죽었던 그 시나리오). 크래시 로그를 받은 뒤 확정
1의 실제 원인(사용자가 준 단서 - 슬롯의 peer가 교체된 뒤 방/전송 상태
어딘가 예전 peer_id를 참조하는 곳이 있는지, 게임 시작 시 슬롯을
순회하며 송신하는 경로 우선 의심)을 규명한다. 그 다음에 2-7(Render
배포)로 넘어간다.

전체 884개 테스트 통과.

### 확정 2/3 후속 2 - 데드락 방지 장치 + 크래시 재현 테스트 결과 + 전원 이탈 방 즉시 해제 + 소소한 것 2건

사용자가 브라우저 두 개로 크래시 재현을 진행한 결과를 가지고 온 큰 묶음.
순서대로 처리했다.

**막혔던 문제 - 전체 테스트 스위트가 걸려서 멈춤(이번 세션 자체 버그,
사용자 지적 아님).** 새 테스트 파일(`test_abandoned_room_cleanup.gd`)에
`server: Node` 타입 매개변수에서 `.room_manager`를 거친 값을 `:=`로
받으려 한 타입 추론 파싱 에러가 남아있었다 - `preload()`가 이 깨진
스크립트를 조용히 무효 리소스로 로드해서, 바로 다음 스위트를 `.new()`할
때 "Nonexistent function 'new' in base 'GDScript'"로 죽었다(정확히 그
직전 스위트인 `test_pack_relay_buffer_overflow.gd`가 방금 성공적으로
끝난 것처럼 보여서 원인 추적이 오래 걸렸다 - 실제로는 그다음 항목이
문제였다). `var room: Room = ...`로 타입을 명시해서 해결. **교훈**:
"A가 성공하고 B에서 죽었다"는 로그를 볼 때, preload 기반 배열에서는
B 자체가 아니라 B의 preload가 실패해서 null이 들어간 경우까지 의심할
것 - 특히 직전에 같은 패턴(`:=`로 untyped 멤버 접근 결과 받기)의
버그를 이미 한 번 겪었다면 그 패턴이 새 파일에도 반복됐는지부터 본다.

**[후속] 데드락 방지 장치 3가지(사용자 지적) - `has_room_to_send_now()`의
margin 계산 자체가 오설정에서 영원히 거짓이 될 수 있다는 지적, 전부 반영.**
1. `NetProtocol.can_chunk_ever_be_sent(buffer_limit)` 추가(순수 판정 -
   빈 버퍼에도 청크 하나+여유가 못 들어가면 false). 서버 `_start_server()`/
   클라이언트 `connect_to_server()`가 버퍼 설정 직후, 소켓을 실제로 열기
   전에 이걸로 확인해서 거짓이면 그 자리에서 명확한 에러를 내고 중단한다
   (서버는 `get_tree().quit(1)`, 클라이언트는 `connection_failed` emit).
2. 송신 대기열 정체 감시(`_check_outgoing_stall()`, 서버/클라이언트 양쪽) -
   기존 `TRANSFER_STALL_WARNING_SEC` 기반 받는 쪽 감시(`pack_transfer_client.gd`,
   팩 전송 전용)와 같은 판단 기준(5초 동안 안 줄면 경고, 줄어드는 방향만
   진전으로 인정)을 소켓 큐 자체(전송 계층)에 붙였다 - 팩 전송이 아닌
   다른 메시지가 막혀도 잡을 수 있는 더 아래 계층의 안전망. 경고에
   대기열 길이/버퍼 사용량/한도/맨 앞 메시지 크기를 전부 남긴다.
3. 회귀 테스트(`test_outbound_buffer_safety.gd`, 8건) - `can_chunk_ever_be_sent()`가
   실제로 문제됐던 값(50000바이트 - 이 세션의 테스트 작성 중 실제로
   영원히 멈추는 사고를 낸 값)을 false로, 실제 배포 값(1MB)을 true로
   판정하는지, 그리고 서버/클라이언트가 실제로 쓰는 `peer.get_outbound_buffer_size()`
   경로(엔진이 요청값을 그대로 안 받아들일 가능성까지 포함)로 걸어도
   같은 결과가 나오는지 확인. `get_tree().quit()`/실제 소켓 연결은
   여기서 직접 안 건드림(공유 테스트 러너를 죽이거나 범위 밖).

**재현 테스트 결과 문서화(docs/multiplayer.md §8.5-8 신설)** - 청크 유실
해결 확인(3.88MB/119청크, 에러 0/재전송 0 - §8.5-7 당시 1.9MB/18유실과
대비), 양쪽 버퍼 1MB 정상 적용 확인, **크래시 자체는 미재현**(게임1 →
나가기 → 새로고침 → 재입장 → 게임2 시작까지 전부 성공, 서버 생존).
상태를 "미재현 / 원인 미확정 / 계측 완비"로 명시하고, "버퍼 고갈이
원래 크래시의 원인이었고 §8.5-7이 부수적으로 고쳤을 수 있다"는 가설을
증명 안 됨으로 명확히 구분했다. **한계**: 이번 재현은 단방향 전송(슬롯0→
슬롯1, 119청크)만 검증했고, 원래 크래시는 양방향 전송(양쪽 다 커스텀
캐릭터)이었다 - 이 경로는 아직 한 번도 검증 안 됨(다음 재현 시 반드시
양쪽 다 커스텀 캐릭터로 양방향을 강제할 것).

**[새로 발견된 문제] 점유 슬롯 전원 확정 이탈 시 방 즉시 해제 - 완료.**
`Room.all_occupied_slots_past_grace()`(점유 슬롯이 하나라도 있고 전부
`PAST_GRACE`인지) + `server_main.gd::_tear_down_abandoned_room()`(방 전체를
로그(`방 XXXX 해제: 점유 슬롯 전원 확정 이탈`) 남기고 즉시 해제 -
`room_manager.force_vacate_slot()`으로 슬롯을 비우고 `_relay_confirm_state`/
`_next_timer_broadcast_msec`까지 정리)를 `_service_in_game_rooms()`에
추가해서, 게임을 끝까지 자동 진행한 뒤 재대전 대기까지 기다리던 예전
동작을 없앴다. **사용자 질문에 답**: 턴 자동 처리(이탈)는 60초를 안
기다리고 **즉시**(0ms) 처리된다(2-6에서 이미 확정·실측된 사실 - `turn_started()`가
확정 이탈 플레이어의 턴이면 데드라인을 이미 지난 값으로 세팅해둠).
즉 예전에 새던 자원은 "턴마다 60초"가 아니라 "게임이 빠르게 끝난 뒤의
재대전 대기 2분"이었고, 이번 수정이 그 2분 자체를 없앤다. 회귀 테스트
6건(`test_room_connection.gd` 5건 + `test_abandoned_room_cleanup.gd` 3건).

**[남은 소소한 것] 2건, 둘 다 완료.**
1. **ready 메시지 중복 경고의 근본 원인** - `online_screen.gd`의
   `_on_ready_button_pressed()`가 로컬 캐시(`_players`, 서버 echo로만
   갱신됨)만 읽고 보내기 전엔 안 바꿨다 - 왕복 시간 안에 이 핸들러가
   두 번 불리면(웹 브라우저가 탭 하나를 터치+마우스 클릭 두 이벤트로
   겹쳐 보내는 경우가 실제 있음) 둘 다 같은 값을 보낸다. 지금은 ready가
   절대값이라 무해했지만, 진짜 토글 의도(빠르게 두 번 눌러 켰다 끄기)로
   두 번 불렸다면 두 번째 토글이 조용히 사라지는 실질적 버그이기도
   했다. 보내는 즉시 로컬 캐시도 낙관적으로 갱신하도록 고침(`_players[my_index]["ready"] = next`).
   회귀 테스트(`test_online_ready_toggle.gd`) - 연달아 두 번 호출해도
   같은 값이 아니라 매번 토글된 값이 나가는지 확인.
2. **팩 전송 완료 로그에 소요 시간 추가** - 기존 실측(§8.5-7의 59청크
   비교)은 전부 같은 프로세스 안 루프백 소켓 기준이라 실제 네트워크
   수치가 필요하다는 지적. `_relay_confirm_state`에 그 해시의 첫 청크가
   도착한 시각(`started_msec`)과 `total_bytes`를 같이 기록해서,
   `_maybe_finish_relay()`의 완료 로그를 "해시 XXXX 전송 완료 (N청크,
   M바이트, T초)" 형식으로 바꿨다.

전체 905개 테스트 통과.

**다음 단계(사용자 지시) - 2-7(Render 상시 배포) 착수 전에 구현 계획을
먼저 제안하고 승인받을 것.** 아직 제안 전.

### 2-7 계획 확정 + 착수 (PORT 환경변수 완료, Docker/gh 설치 대기)
제안한 2-7 계획에 사용자가 결정 2건 + 순서 재배열 + 신규 단계 3개를
반영해 확정해줬다. 자세한 최종 순서/결정 근거는 `docs/deployment_checklist.md`
"6. 확정된 구현 계획" 절에 정리(요약만 여기 남김).

- **결정 1**: 2-7 착수 전 크래시 게이트를 그대로 유지하되, 양방향 팩
  전송(원래 크래시 조건) 재현을 한 세션 한도로 한 번 더 시도한 뒤
  진행하기로 확정(무한정 안 붙잡음).
- **결정 2**: 접속 주소는 `yd_release` 기능 태그로 자동 분기(배포
  빌드→Render URL, 개발 빌드→localhost) - 불특정 다수 공개라 수동
  입력을 기본으로 둘 수 없음. 수동 입력은 눈에 덜 띄게 남김.
- **순서 재배열**: "연결 유지 시간 실측"(Render 무료 플랜에서 WebSocket이
  실제로 몇 분 만에 끊기는지 - 문서마다 다르게 적혀 있어 실측 필요,
  이 계획 전체의 go/no-go 분기점)을 클라이언트 작업 전 앞쪽으로 당김.
- **신규 단계 3개**: (0) 서버 소스용 비공개 Git 저장소 준비(지금은
  `web_build`만 있고 서버 저장소가 없음), (3.5) 바인딩 주소/헬스 체크
  확인, (6.5) 접속 주소 변경 후 클라이언트 재빌드+Pages 재배포.
- **단계 1(PORT 환경변수) 완료**: `_resolve_port()` 우선순위를 "CLI
  인자 → `PORT`(Render 표준) → `YACHT_DICE_PORT`(로컬) → 8910"으로
  조정(`server_main.gd`). 회귀 테스트 4개(`test_server_port_resolution.gd`) -
  `OS.set_environment()`로 실제 프로세스 환경변수를 조작해 4단계
  우선순위 전부 확인. 덤으로 바인딩 주소(`create_server()`가 `"*"`
  기본값 사용 - Render의 0.0.0.0 요구사항 이미 충족)도 확인 완료.
- **단계 0(비공개 저장소 준비) 완료**: `gh` CLI를 winget으로 설치하고
  사용자가 직접 `gh auth login`을 완료한 뒤(브라우저 인증이 필요해
  대화형으로 진행), `https://github.com/gyutaeng/yacht-dice`(private)를
  만들어 `origin`으로 연결했다. 이 로컬 저장소엔 원격이 아예 없던
  상태였다(`main`은 오래된 커밋에 멈춰 있었음). 사용자 결정으로
  `step/1-5-file-picker`(v0.3-online + 이번 세션 전부 포함, 최신 상태)를
  `main`으로 fast-forward 병합해서 push - **Render는 앞으로 `main`을
  배포 기준으로 본다.** 위 "확정 2/3 후속 2" 절까지의 변경사항을 커밋
  하나(`친구 대상 실제 베타 테스트 후속 일괄 반영 + 2-7 착수 준비`)로
  묶었다.
- **Docker Desktop 설치 완료**: winget 자동 설치는 관리자 권한 승인(UAC)에
  막혀 실패했지만(2026-09-16), 이 컴퓨터에 WSL2 자체가 없던 게 더 근본
  원인이었다(`wsl --status`가 "설치 안 됨") - 사용자가 직접 `wsl --install`
  + 재부팅으로 WSL2를 설치한 뒤 Docker Desktop이 정상적으로 뜸(`docker run
  hello-world` 확인).
- **단계 3(Dockerfile) 완료**: `Dockerfile`/`.dockerignore` 작성 후 실제
  `docker build`+`docker run`으로 로컬 검증까지 마쳤다. 막혔다가 고친
  문제 하나 - 로컬 에디터가 오래 쌓아둔 `.godot/imported/` 캐시 덕에
  안 보이던 문제인데, 깨끗한 컨테이너는 이 캐시가 없어서 순수
  `--headless` 실행이 폰트/스크립트 파싱 에러로 죽었다(1-8 사전 작업
  때 이미 겪은 것과 같은 원인). `RUN godot --headless --editor
  --quit-after 60 --path /app`로 이미지 빌드 시점에 임포트를 강제해서
  해결. 컨테이너가 정상적으로 뜨는 것(로컬과 동일한 로그), PORT
  환경변수가 실제 컨테이너에서도 반영되는 것(`-e PORT=9999` → 로그에
  "포트 9999"), TCP 연결은 되지만 평범한 HTTP엔 응답 안 하는 것
  (WebSocket 전용 서버라 정상 - 다음 단계 헬스체크 확인의 배경)까지
  전부 확인했다. 자세한 내용은 `docs/deployment_checklist.md` "2-7 사전
  조사 §3/§3.5" 참고.

전체 909개 테스트 통과.

### 2-7 후속 - 저장소 분리 감사 + 연결 유지 시간 계측 로그 + 단계 3.5(바인딩/헬스체크) 확인
사용자가 단계 0/1/3 진행을 승인하고, 오늘 자기가 직접 단계 2(양방향
크래시 재현)와 Render 계정 생성을 맡는 동안, 단계 5(Render 서비스 생성)
전에 필요한 준비 두 가지를 처리했다.

- **비공개 저장소(`gyutaeng/yacht-dice`)에 실수로 올라간 게 있는지 감사 -
  빌드 산출물/로그/인증정보는 깨끗함, 아이콘 파일은 오판 후 정정**:
  `git ls-files`로 194개 트래킹 파일 전부를 확인한 결과, 빌드 산출물
  (`.godot/`는 `.gitignore`로 제외, `web_build`/`web_dev`는 애초에 이
  저장소 바깥 경로라 구조적으로 섞일 수 없음)/서버 로그(`F:\Godot\logs\`도
  저장소 바깥)/Render·GitHub 인증정보(Dockerfile/.dockerignore/docs
  전체 grep, `.claude/settings.json` 확인 - 전부 없음)는 전부 깨끗했다.
  **저장소 루트의 `spr_betako_icon.png`(595바이트)를 처음엔 "코드
  어디서도 참조 안 되는 죽은 파일"로 잘못 판단해 삭제했다가 되돌렸다** -
  `project.godot`의 `config/icon`(앱/창 아이콘)이 UID로 이 파일을
  가리키고 있는 살아있는 필수 에셋이었다(정정 경위는 위 "저장소 2개"
  절의 "정정" 항목 참고). **결론: 감사 결과 비공개 저장소에 실제로
  잘못 올라간 파일은 없었다** - 오히려 감사 과정에서 정상 에셋을 죽은
  파일로 오판해 삭제할 뻔한 게 이번 세션의 진짜 실수다. 그래도 재발
  방지 조치 자체는 여전히 유효하다고 판단해 유지한다: `.gitignore`에
  저장소 루트 한정 이미지/오디오 확장자 규칙(`/*.png` 등, 하위 폴더는
  영향 없음)을 추가했고 기존 에셋(assets/, characters/ 등)이 여전히
  정상 트래킹되는지 `git check-ignore`로 확인했다. `git add .`/
  `git add -A` 금지 원칙도 CLAUDE.md 코드 스타일에 명시했다(위 참고) -
  다만 이번 케이스에서 그 규칙이 막아줬을 문제는 실은 없었다는 점도
  같이 남긴다.
- **연결 유지 시간 계측 로그 추가(`server_main.gd`) - 단계 6 실측 준비**:
  `_connected_since_msec`(접속 시각)/`_last_sent_msec`(마지막으로 실제
  `put_packet()`이 성공한 시각 - `_last_seen_msec`이 이미 "마지막 수신"
  이므로 새로 안 만들고 그대로 재사용)를 추가하고, 30초마다(아무 일이
  없어도) 지금 붙어있는 접속 전부에 대해
  `[서버][연결계측] 유지: peer N, M초 경과, 현재 접속 수 K, 마지막 수신=A초 전, 마지막 송신=B초 전`을
  찍는 `_service_connection_heartbeat()`를 추가했다. 연결 해제 로그
  (`_on_peer_disconnected`)에도 `총 유지 M초`를 추가했다 - 이제
  "얼마나 버티다 끊겼는지"(해제 시점)와 "지금 몇 초째 살아있는지"(주기
  로그) 둘 다 남는다. 마지막 수신/송신을 같이 남기는 이유는 유휴
  때문에 끊기는 것과 시간 자체가 다 돼서 끊기는 것을 구분하기 위함 -
  ping을 5초마다 계속 보내는데도(마지막 송신이 항상 5초 이내) 특정
  시점에 끊기면 유휴 타임아웃이 아니라 하드 타임 리밋이라는 뜻이 된다.
  로컬 소켓(scene 기반 `GameClient` 임시 테스트 - `--script` 모드는
  오토로드 미등록으로 컴파일이 안 된다는 이 프로젝트의 기존 교훈을
  또 확인함, 결국 임시 `.tscn`으로 검증 후 삭제)으로 heartbeat 로그와
  "총 유지 39.9초" 형태의 해제 로그 둘 다 실제로 찍히는 것을 확인했다.
  전체 909개 테스트 그대로 통과(회귀 없음).
- **단계 3.5(바인딩) - 코드 확인 + 실측 둘 다 완료, 수정 불필요**:
  `server_main.gd`의 `peer.create_server(port)`가 `bind_address`
  인자를 안 넘겨 엔진 기본값(`"*"`)을 쓴다는 건 지난 세션에 이미
  코드로 확인된 사실이었고, 이번에 로컬로 서버를 띄워
  `netstat -an`으로 직접 실측해서 재확인했다 - `0.0.0.0:PORT`와
  `[::]:PORT` 양쪽 다 LISTENING으로 뜬다. Render의 "0.0.0.0에 바인딩"
  요구사항을 코드 변경 없이 이미 만족한다.
- **단계 3.5(컨테이너 밖 접속) - 재확인 완료**: Docker Desktop이 꺼져
  있어서 다시 켜고(WSL2 기반, 지난 세션에 설치된 그대로 정상 기동),
  오늘 바뀐 `server_main.gd`를 반영해 이미지를 재빌드한 뒤
  `docker run -p 18910:8910`으로 띄워 호스트(컨테이너 밖)에서
  `Test-NetConnection`으로 TCP 연결이 되는 것(`TcpTestSucceeded: True`)과,
  평범한 HTTP GET은 응답 없이 실패하는 것(WebSocket 전용 서버라 정상 -
  지난 세션 기록과 일치) 둘 다 재확인했다. 확인 후 컨테이너는 삭제함.
- **단계 3.5(헬스 체크) - 구현은 보류, 후보만 정리(사용자 지시)**:
  Render 문서 확인 결과, **Health Check Path를 비워두면 기본값이
  HTTP가 아니라 TCP 소켓 확인**이다("5초 안에 TCP 연결을 받아들이면
  성공" - Render 공식 문서 인용, 아래 출처). 이게 사실이면 지금 서버
  코드를 전혀 안 고쳐도 될 가능성이 높다 - 위에서 재확인한 대로 TCP
  연결 자체는 이미 되기 때문. 다만 이 동작이 Docker 환경 서비스에도
  똑같이 적용되는지는 문서에 명시적으로 안 나와 있어서(Private
  Service는 TCP 전용이라고 못박혀 있지만, Docker Web Service가 그와
  같은지는 확인 안 됨) 실제 배포(단계 5) 때 화면의 Health Check Path
  설정 항목을 캡처해서 최종 확인이 필요하다. 후보:
  - **후보 A(추천) - Health Check Path를 비워둔다.** 장점: 코드 변경
    0줄, 지금 구조(WebSocket 전용 서버)와 완벽히 맞음. 단점: Render가
    문서와 다르게 동작하거나, 나중에 정책이 바뀌어 HTTP 응답을
    요구하게 되면 그 시점에야 드러남(배포 실패로 알게 됨).
  - **후보 B - Godot 서버 자체가 HTTP도 같이 답하게 만든다(기각).**
    Python `websockets` 라이브러리의 Render 배포 가이드가 이 방식(같은
    포트에서 WS 업그레이드가 아닌 요청만 골라 200을 돌려줌)을 쓰지만,
    이건 그 라이브러리가 HTTP 파싱을 이미 갖고 있어서 가능한 것 -
    Godot의 `WebSocketMultiplayerPeer`/`WebSocketPeer`는 이미 CLAUDE.md에
    적혀 있듯("Godot의 WebSocket 서버는 평범한 HTTP 요청에 응답하지
    못한다") 그런 훅이 없고, 이번에 컨테이너로 직접 재확인한 대로 실제
    HTTP GET에 응답 자체를 안 한다. 이 경로를 만들려면 로우레벨
    TCP+수동 HTTP 파싱을 GDScript로 새로 짜야 해서(사실상 미니 HTTP
    서버 재구현) 비용 대비 얻는 게 적다 - 후보 A로 충분하면 이건 필요
    없다.
  - **후보 C - 컨테이너 안에 작은 프록시 프로세스를 하나 더 둔다.**
    (예: nginx) 공개 포트(Render가 주입하는 `PORT`)를 이 프록시가 받아서,
    헬스 체크 경로만 자기가 200으로 답하고 나머지(WS 업그레이드 요청)는
    내부 전용 포트의 Godot 서버로 그대로 넘겨준다(WebSocket은 raw TCP
    패스스루로 프록시 가능 - nginx가 지원). 장점: Render가 실제로
    무엇을 요구하든 대응 가능, 헬스 체크 자체를 우리가 완전히 통제.
    단점: Dockerfile에 프록시 설치/설정이 추가되고, 움직이는 부품이
    하나 늘어 그 자체가 새 실패 지점이 될 수 있음(설정 드리프트,
    지연 한 홉 추가).
  - **판단(사용자 확정) - 후보 A로 확정.** Health Check Path를 비워두고
    배포한다 - Render 문서상 헬스 체크는 선택 사항이고 지정하지 않으면
    포트 개방(TCP)으로 판정한다. 후보 C(내부 프록시)는 A가 실제
    배포에서 실패하는 게 확인될 때만 꺼내되, 그 판단은 실제 배포 로그를
    보고 한다 - **지금은 구현하지 않는다.** 후보 B는 사실상 후보 C를
    GDScript로 재발명하는 셈이라 처음부터 기각.
  - 출처: [Health Checks – Render Docs](https://render.com/docs/health-checks),
    [Deploy to Render - websockets docs](https://websockets.readthedocs.io/en/14.1/howto/render.html)

### 2-7 후속 2 - 빌드 배너에 커밋 해시 추가 (베타 로그로 코드 특정)
사용자 요청: 빌드 배너가 지금은 시각/디버그 여부만 보여주는데, 짧은 git
커밋 해시를 추가해서 친구들이 보내는 로그 한 줄만으로 어느 코드였는지
바로 특정할 수 있게 한다. 형식: `[YachtDice] 빌드: 2026-09-17 09:12
(a3f9c21) (디버그 기능: 켜짐)`.

- **`build_info.gd`에 `BUILD_COMMIT` 상수 추가**(기본값 `"unknown"` -
  git을 못 읽는 환경에서도 빌드/export 자체는 절대 안 막히게). 콘솔
  로그(`_ready()`)와 웹 브라우저 배너/콘솔(`_stamp_browser()`) 양쪽
  포맷 문자열에 `(%s)`로 끼워 넣었다 - 서버(`server_main.tscn`)도
  클라이언트(`Main.tscn`)도 같은 `BuildInfo` 오토로드를 쓰므로 이
  한 곳만 고치면 양쪽 다 반영된다.
- **채우는 경로는 두 곳, 서로 독립적**(BUILD_TIME과 똑같은 이유 - 서버는
  export 파이프라인을 안 거치므로 클라이언트 쪽 메커니즘이 안 닿는다):
  - **클라이언트(Web/Desktop export)**: `addons/build_stamp/build_stamp_export_plugin.gd`가
    BUILD_TIME과 같은 방식(export 시작 시 정규식 한 줄 치환)으로 채운다.
    새 `_current_git_commit()` 함수가 `OS.execute("git", ["-C", 프로젝트_경로,
    "rev-parse", "--short", "HEAD"], ...)`로 해시를 얻고, `git status
    --porcelain`이 비어있지 않으면(커밋 안 된 변경사항 있음) 해시 뒤에
    `-dirty`를 붙인다. git이 없거나 실패해도 `"unknown"`을 돌려줄 뿐
    export 자체를 막지 않는다.
  - **서버(Docker 이미지)**: `Dockerfile`이 `COPY . .` 직후 `RUN` 한
    단계로 같은 걸 한다(`git rev-parse --short HEAD 2>/dev/null || echo
    unknown`, dirty 판정도 동일) - `sed`로 `build_info.gd`의
    `BUILD_COMMIT` 줄을 치환한다. 이걸 위해 `.dockerignore`에서
    `.git/` 제외를 뺐고(이미지 크기가 조금 늘지만 이 프로젝트 규모에서는
    미미함 - 멀티스테이지 빌드까지는 안 감), `git` 패키지를 apt 설치
    목록에 추가했다.
- **검증**: 전체 909개 테스트 그대로 통과(회귀 없음 - 이 기능을 직접
  검증하는 자동 테스트는 없음, git 실행 결과에 의존하는 export/빌드
  시점 동작이라 헤드리스 테스트 스위트의 성격과 안 맞아서 2-5의 실제
  소켓 검증들과 같은 이유로 자동화하지 않음). **오늘 뽑는 Web (dev)
  빌드가 이 기능이 실제로 export 파이프라인에서 동작하는 첫 실제
  검증이다** - 브라우저 콘솔/배너에 커밋 해시가 실제로 찍히는지 확인할
  것. Docker 쪽(서버) 스탬핑은 아직 실제 이미지로 재현 확인 전(다음에
  이미지를 다시 빌드할 때 `docker logs`의 "커밋 스탬프: ..." 줄과
  서버 시작 배너를 대조해서 확인할 것 - 오늘은 단계 5 보류로 서버
  재배포 자체가 없어 우선순위 밖).

### 단계 2 종결(양방향 크래시 미재현) + ready 중복의 진짜 원인 수정 + 브랜치 정리
사용자가 로컬 dev 빌드(커밋 `dabe2ad` 이전 버전)로 양방향 팩 전송
크래시 재현을 진행한 결과와, 그 로그에서 발견한 새 단서 두 가지를
한 번에 처리했다.

- **단계 2(양방향 크래시 재현) 종결 - 크래시 미재현**: 2.13MB/66청크 ↔
  3.88MB/119청크 양방향 전송, 3판 연속, 이탈/새로고침/재입장 포함
  조건으로 서버가 223초간 정상 동작(`ERR_OUT_OF_MEMORY` 0건, 재전송
  요청 0건, 대사 중복 없음). `docs/multiplayer.md` §8.5-9에 재현
  조건/결과를 기록하고 "양방향 검증 완료/크래시 미재현/원인 미확정"으로
  정리 - 이 경로에서의 재현은 여기서 종결하고 단계 5로 넘어간다.
- **빌드 배너가 소스 직접 실행 시 거짓말하던 문제 수정**: `run_server.bat`
  등으로 서버를 소스에서 직접 실행하면 `BUILD_TIME`/`BUILD_COMMIT`이
  마지막 export/Docker 빌드 시점에 멈춰 있어, 오늘 코드로 돌고 있는데도
  어제 날짜가 찍히는 걸 사용자가 실제 로그로 발견했다. `OS.has_feature("template")`로
  "지금 export된 빌드가 아니다"를 실측 확인한 뒤에만 런타임에 git을
  직접 읽어 다시 계산하도록 고쳤다(export된 빌드는 res://가 git 저장소를
  안 가리켜 이 시도가 자연히 실패하므로 안전). git도 못 읽고 baked
  값도 없으면 "unknown(소스 직접 실행 - 스탬프 없음)"으로 명시한다 -
  틀린 값보다 모른다는 게 낫다는 사용자 지적. 로컬 소스 실행/Docker
  컨테이너 재빌드 양쪽에서 정확한 커밋(dirty 여부 포함)이 찍히는 것을
  실제로 확인했다.
- **ready 중복 경고의 진짜 원인 발견 - 1번 버그(재대전 시작 안 됨)의
  유력한 원인으로 추정**: 사용자의 가설("인원 변동 시 클라이언트가
  자동으로 ready를 해제한다")은 클라이언트 전체에서 `set_ready()` 호출
  지점이 딱 2곳(준비 버튼 토글, `[한 판 더]` 확정)뿐임을 grep으로
  확인해 기각했다. 진짜 원인: 서버의 `Room.begin_rematch_wait()`가
  게임 종료 순간 전원의 ready를 false로 되돌리는데, 그 사실을
  클라이언트에 알리는 메시지가 없다 - 클라이언트의 로컬 `_players` 캐시는
  그 판을 시작할 때 값(항상 true)을 그대로 들고 있다가, 재대전 대기
  화면에서 준비 버튼을 처음 누르면 "true→false" 토글값이 나가는데
  서버는 이미 false라 중복이 된다. 로그 노이즈만이 아니라 실제 버그다 -
  버튼 라벨이 "준비 취소"로 잘못 떠서 유저가 이미 준비된 줄 알고
  기다리면 재대전 대기 타임아웃(2분)에 강제 퇴장될 수 있다.
  `game_ended`(서버가 `begin_rematch_wait()`를 부르는 바로 그 순간
  함께 오는 신호) 수신 시 클라이언트도 로컬 캐시를 전부 false로
  리셋하도록 고쳤다 - 새 네트워크 메시지 없이 이미 오는 신호로 해결.
  **증상과 사용자가 베타 후 보고했던 1번 버그 원문("한 판 더 둘 다
  눌렀음에도 바로 시작이 안 됨. 준비 취소하고 다시 준비해야 게임이
  재시작됨")의 순서까지 정확히 일치한다** - 다만 **"1번 버그 해결"이
  아니라 "1번 버그의 유력한 원인 수정 완료, 실사용 확인 대기"로 남긴다.**
  이 수정 이후에야 검증 로그를 추가했으므로 "고치기 전엔 실제로 이
  경로에서 문제가 났었다"는 것 자체는 이 테스트로 직접 재현/확인할
  방법이 없다(사용자 지적) - **이 테스트로 확인되는 것은 "지금 동작이
  올바른가"뿐이고, "이것이 1번 버그의 원인이었는가"는 다음 친구 테스트에서
  해당 증상이 실제로 사라졌는지로만 최종 확인된다.**
  - **검증 준비**: `online_screen.gd`에 로컬 ready 캐시가 바뀔 때마다
    (게임 종료 리셋, 버튼 클릭) 버튼 라벨/캐시값/전송값을 시각과 함께
    화면(`TransferDebugLog`)에 남기는 진단 로그 3곳 추가 - 서버의
    "재대전 준비 수신 - 슬롯 N ready=..." 로그와 시각을 대조할 수
    있다. 회귀 테스트 추가(`test_online_ready_toggle.gd`), 전체 911개
    테스트 통과.
  - **검증 결과(사용자, 커밋 `dabe2ad` 로컬 dev 빌드, 브라우저 2개(일반/
    시크릿))**: 게임 한 판 종료 후 `[한 판 더]`를 누르면 자동으로 준비
    완료(버튼 라벨 "준비 취소")로 표시되고, 상대도 같은 과정을 거치면
    양쪽 다 준비 완료가 되어 게임이 정상 시작됐다 - "준비 취소 후 다시
    준비"가 필요 없었다. 판정 근거: 클라이언트 표시와 서버 상태가
    어긋나 있었다면(수정 전 상태) 눌러도 서버가 이미 같은 값이라 무시해서
    게임이 시작될 수 없었을 것 - 정상 시작됐다는 것 자체가 둘이 일치함을
    보여준다.
    **범위를 정확히 남긴다(사용자 지적, 반드시 이 표현 유지)**:
    - 확인된 것: **지금 동작이 올바르다**(클라이언트 표시=서버 상태 일치,
      한 번만 눌러도 시작됨).
    - 확인되지 않은 것: **이것이 원래 1번 버그(베타 중 "한 판 더 둘 다
      눌렀는데 시작 안 됨, 준비 취소하고 다시 준비해야 시작됨")의 진짜
      원인이었는가** - 검증 로그를 수정 이후에 넣었으므로 "고치기 전
      동작"은 이 테스트로 직접 재현/확인할 방법이 없었다.
    - 최종 확인 방법: **다음 친구 테스트에서 해당 증상이 실제로 사라져
      있는지.**
    - **현재 상태: "1번 버그의 유력한 원인 수정 완료, 실사용 확인 대기"
      (해결로 종결하지 않음).**
  - **후속 과제로 남긴 것(지금 구현 안 함)**: 이번 수정은 서버와
    클라이언트가 같은 값(ready 리셋 시점)을 각자 계산하는 구조라, 같은
    종류의 버그가 재발할 수 있는 근본 형태는 그대로다. "거울을 두 개
    두지 않는다"는 원칙(2-4의 `GameState.read_only` 패턴과 같은 방향) -
    서버가 ready를 권위 있게 알리고 클라이언트는 표시만 하는 구조로
    바꾸는 방안을 `docs/multiplayer.md` §11에 후속 과제로 정리했다 -
    Render 배포가 더 급해서 지금 당장은 안 함.
- **브랜치 정리**: `step/1-5-file-picker`(2-1부터 오늘 작업까지 전부
  쌓여 있던, 이름이 무관해진 브랜치)를 `main`으로 fast-forward(완전히
  선형이라 히스토리 안 건드림) 후 push, 동일함을 확인하고 옛 브랜치
  삭제. `origin/main` 최신 해시는 이 절 작성 시점 기준 `7da0e5c`(이후
  이 절 자체도 `main`에 커밋됨). CLAUDE.md에 "🌿 브랜치 워크플로우"
  원칙 추가 - 앞으로 `main`에 직접 작업하거나 단계 이름에 맞는 새
  브랜치를 그때그때 판다.

### (구) 🚨 배포 전 필수 확인: `build_info.gd`의 `DEBUG_MODE`를 `false`로
**위 항목으로 대체됨 - 더 이상 이 상수를 손으로 고치지 않는다.** 아래는
DEBUG_MODE가 묶고 있던 것들의 목록이라 여전히 유효하므로 남겨둔다.

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

### 온라인 전용 [빠른 진행] 버튼(`scenes/Main.gd`, `DEBUG_MODE` + 온라인일 때만)
2-4에서 "온라인엔 디버그 UI를 숨긴다"고 정한 원칙의 명시적 예외(사용자
요청) - 위 디버그 단축키/버튼은 로컬 전용 `GameState`를 직접 조작하는
방식이라 온라인(read_only 사본)에는 애초에 안 먹는다. 2-6/2-6B를 실제
브라우저 2개로 반복 확인할 때 한 턴을 넘기려고 클릭을 여러 번 하는
수고를 덜기 위한 것으로, 새 네트워크 메시지는 하나도 안 만들고 기존
`request_roll`/`request_score`만 그대로 순서대로 보낸다(서버 입장에서는
사람이 빠르게 클릭한 것과 구별되지 않고, 턴 권한 검사도 그대로 통과해야
함). 내 턴에 누르면 안 굴렸으면 굴리고 → 빈 칸 중 아무거나(가장 낮은
인덱스) 하나 확정 → **딱 한 턴만 처리하고 멈춘다**(연속 자동 아님 -
상대 턴까지 자동으로 넘기면 재대전/연결 끊김처럼 눈으로 확인하려던
동작 자체를 가리게 됨). `DEBUG_MODE=false`면(배포 체크리스트 항목)
당연히 안 보인다.

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
- 2-6 실제 확인: 브라우저 탭을 그냥 닫기(상대 화면에 연결 끊김 →
  나갔습니다가 순서대로 뜨는지), 새로고침(F5)으로 복귀 다이얼로그가
  뜨고 실제로 게임 화면에 돌아오는지, 서버 프로세스를 잠깐 껐다 켰을 때
  재시도 UI가 정상적으로 포기하는지(방 데이터가 사라지므로 재접속이
  아니라 ROOM_NOT_FOUND로 끝나는 게 정상).
- 2-6B 실제 확인: 실제 브라우저 2개로 한 판을 끝까지 하고 양쪽 다
  `[한 판 더]`를 눌러 캐릭터 재선택 화면이 뜨는지, 캐릭터를 그대로
  두면 전송 없이 바로 시작되고 바꾸면 그 사람 것만 전송되는지, 게임
  시작 인사가 2판째도 다시 나오는지, 한 명이 `[나가기]`를 누르면
  남은 사람 화면에 알림이 뜨고 로비로 돌아가 사람을 기다리는지.
- Phase 2: 온라인 멀티플레이 (2-1·2-3·2-4·2-4B·2-4C·2-5·2-6·2-6B 완료 -
  실제 주사위 진행이 서버 권위로 동작하고, 내 캐릭터도 온라인에
  연결됐고, GameEvents 릴레이가 전수 조사를 거쳐 빠짐없이 나가고,
  캐릭터 팩까지 실제로 전송되고, 연결 끊김/재접속/턴 타임아웃까지
  처리되고, 게임 종료 후 같은 방에서 재대전까지 가능하다). Phase 2
  범위에서 남은 것은 §9(문서 범위 밖으로 명시)에 없는 추가 요구가
  생기기 전까지는 위 사용자 확인들뿐이다 - 다음 코드 작업은 Phase 3
  (배포 준비, `docs/deployment_checklist.md`)로 넘어갈 차례.
