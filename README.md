# 요트다이스

플레이어가 직접 만든 캐릭터(스탠딩 이미지 + 보이스)로 즐기는 온라인
요트다이스 보드게임입니다. Godot 4.7 / GDScript로 만들었습니다.

## 시작하기

**[게임하러 가기](https://gyutaeng.github.io/Custom-YatchDice-game/)**

- PC 브라우저 전용입니다. 모바일은 지원하지 않습니다.
- 서버가 무료 플랜이라 한동안 접속이 없으면 잠듭니다. 접속을 시도하면
  최대 1분 정도 걸려 깨어날 수 있습니다 - "서버를 깨우는 중입니다"
  문구가 뜨면 정상 동작 중이니 기다리면 됩니다.
- 방을 만들거나 참가한 뒤, 각자 캐릭터를 고르고 로비에서 [준비 완료]를
  눌러야 합니다. 인원이 다 모여도 저절로 시작되지 않습니다 - 전원이
  준비를 마쳐야 게임이 시작됩니다.

## 캐릭터 만들기

게임 시작 화면의 [캐릭터 관리]에서 이미지(전신 스탠딩 + 선택적으로
정사각형 썸네일)와 보이스(상황별 대사, 최대 9가지)를 올려 내 캐릭터를
만들 수 있습니다. 만든 캐릭터는 파일 하나(`.ydchar.zip`)로 내보내고
가져올 수 있어서 다른 사람과 공유하기도 쉽습니다.

이미지/보이스 권장 크기와 용량 한도, 만드는 순서는
[docs/character_guide.md](docs/character_guide.md)에 정리했습니다.

## 이 저장소에 대해

이 프로젝트는 저장소 두 개로 나뉘어 있습니다.

- **이 저장소(`yacht-dice`)**: 클라이언트/서버 전체 소스코드. Render에
  배포되는 서버(Docker)도 여기서 빌드됩니다.
- **[`Custom-YatchDice-game`](https://github.com/gyutaeng/Custom-YatchDice-game)**:
  실제로 플레이하는 웹 클라이언트가 빌드되어 GitHub Pages로 배포되는
  저장소입니다. 빌드 산출물만 들어 있고 소스는 없습니다.

## 개발자용

- **엔진/언어**: Godot 4.7 (GDScript). 웹(HTML5) export를 항상 지원하는
  것을 전제로 만들었습니다.
- **아키텍처 원칙** 몇 가지(전체 목록은 [CLAUDE.md](CLAUDE.md) 참고):
  - 게임 규칙(`GameState`)은 UI 노드를 직접 참조하지 않습니다 -
    `GameState` → 시그널 → UI 단방향입니다.
  - 게임 이벤트는 `GameEvents` autoload 시그널로만 주고받습니다 -
    방출자는 구독자를 모릅니다.
  - 주사위는 주입된 `RandomNumberGenerator`로 굴립니다(`randi()` 직접
    호출 없음) - 온라인 대전에서 서버가 권한을 갖기 위한 전제입니다.
  - 사용자가 올린 파일(이미지/보이스)은 확장자 화이트리스트와 크기
    상한을 거쳐야만 쓰입니다.
- **로컬에서 돌려보기**: Godot 4.7.2 에디터로 프로젝트를 열면 됩니다.
  테스트 스위트는 씬으로 실행합니다(`--script` 방식은 autoload가
  등록되지 않아 동작하지 않습니다):
  ```
  godot --headless --path . res://scripts/tests/test_runner.tscn
  ```
  효과음 파일은 라이선스 문제로 저장소에 포함하지 않았습니다(아래
  "라이선스" 참고). 클론한 상태 그대로 실행해도 게임은 정상 진행되고,
  다만 소리는 나지 않습니다 - 실행 시 콘솔에 안내 로그가 한 번
  출력됩니다. 직접 채워 넣는 방법은
  [docs/sfx_guide.md](docs/sfx_guide.md)에 정리했습니다.
- **서버만 따로 띄우기**:
  ```
  godot --headless --path . res://server_main.tscn -- <포트> [바인드 주소]
  ```
  포트를 생략하면 `8910`, 바인드 주소를 생략하면 모든 인터페이스(`*`)가
  기본값입니다.
- **로컬 서버로 온라인 대전 붙어보기**: 클라이언트는 빌드 종류에 따라
  접속 주소가 자동으로 갈립니다 - 배포용(`Web (release)`) 빌드는 Render
  주소로, 그 외(에디터 실행/`Web (dev)`)는 로컬(`ws://127.0.0.1:8910`)로
  붙습니다. 온라인 접속 화면에서 서버 주소를 직접 입력하는 것도
  가능합니다.
- **문서(`docs/`)**: 캐릭터 팩 포맷, 멀티플레이 프로토콜, 배포 절차,
  웹 export 주의사항 등을 정리해 뒀습니다. 그중
  [docs/multiplayer.md](docs/multiplayer.md)에는 온라인 대전을 만들면서
  실제로 겪은 버그와 그 원인을 조사 과정 그대로 기록해 뒀습니다 -
  "이렇게 판단했는데 틀렸다"는 정정이 여러 번 나옵니다.
- **CLAUDE.md**: 이 프로젝트는 대부분 Claude Code로 작업했습니다.
  저장소 루트의 [CLAUDE.md](CLAUDE.md)는 그 Claude Code에게 주는 작업
  규칙 문서입니다(코딩 스타일, 지켜야 할 아키텍처 원칙, 세션 간
  인수인계 기록). 사람이 읽으라고 쓴 문서는 아니지만 공개 저장소에
  그대로 있는 파일이라 여기 밝혀 둡니다.

## 문의

- **코드/소스 관련 질문·제보**: [GitHub Issues](https://github.com/gyutaeng/yacht-dice/issues)
- **플레이 중 문제·버그 제보**: 트위터 [@GYU_VS](https://x.com/GYU_VS)

취미로 만든 프로젝트라 답이 늦을 수 있습니다.

## 라이선스

이 저장소의 코드는 [MIT License](LICENSE)입니다(저작권자 gyutaeng).
이 라이선스는 제가 작성한 코드에만 적용되고, 아래 구성요소는 각자의
라이선스를 따릅니다 - 이들을 MIT로 재라이선스할 권한은 없습니다.

- **폰트**: [Pretendard](https://github.com/orioncactus/pretendard)
  (Copyright (c) Kil Hyung-jin, SIL Open Font License 1.1 -
  [전문](assets/fonts/LICENSE.txt))
- **파일 업로드 애드온**: [godot-file-access-web](https://github.com/Scrawach/godot-file-access-web)
  (Copyright (c) Scrawach, MIT License -
  [전문](addons/FileAccessWeb/LICENSE.txt))
- **게임 엔진**: [Godot Engine](https://godotengine.org/) (MIT License -
  [godotengine.org/license](https://godotengine.org/license/))
- **효과음**: Pixabay의 로열티프리 음원을 씁니다. 출처 표기 의무는
  없는 라이선스지만, 원본을 가공 없이 단독으로 재배포하는 것은
  금지되어 있어 이 저장소에는 파일을 올리지 않았습니다. 어떤 효과음이
  어디서 쓰이는지는 [docs/sfx_guide.md](docs/sfx_guide.md)에
  정리했습니다.
