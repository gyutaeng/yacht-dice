# 배포 준비 체크리스트 (3-3)

정식으로(또는 베타로) 배포할 빌드를 만들기 직전에 이 목록을 확인한다.

**베타 배포 후 바뀐 것(사용자 지적)**: 예전엔 `build_info.gd`의
`DEBUG_MODE` 상수를 손으로 `true`/`false`로 고쳐서 배포했는데, "다시
켜는 걸 잊거나 켠 채로 내보내는 사고"가 반복될 위험이 있었다(사람이
기억하는 방식은 이 프로젝트에서 여러 번 실패했다). 지금은 **어느
export 프리셋을 선택하느냐가 DEBUG_MODE를 자동으로 결정한다** - 손으로
상수를 고칠 필요 자체가 없어졌다. 자세한 메커니즘은 `build_info.gd`의
주석과 `docs/web_export.md`의 "DEBUG_MODE 자동 전환" 참고.

## 1. 올바른 export 프리셋을 골랐는지 확인

`export_presets.cfg`에 웹 프리셋이 두 개 있다:

- **`Web (개발)`** - `custom_features=""`. DEBUG_MODE가 켜진 채로
  나온다(디버그 단축키/버튼/화면 로그 전부 보임). 평소 개발 중 확인용.
- **`Web (배포)`** - `custom_features="yd_release"`. 이 태그가 있으면
  `build_info.gd`의 `DEBUG_MODE`가 자동으로 `false`가 된다. **베타/정식
  배포는 반드시 이 프리셋으로 export한다.** export_path는
  `F:/Godot/web_build/index.html`로 고정되어 있다 - **이 폴더가 곧
  GitHub Pages 저장소**(이 프로젝트 git과는 무관한 별도 저장소)이므로,
  여기 들어있는 건 항상 배포 빌드뿐이다(개발용은 아래처럼 완전히 다른
  폴더 `F:/Godot/web_dev`를 쓴다 - 섞일 경로 자체가 없음).

가장 간단한 방법은 `F:\Godot\build_release.bat`을 더블클릭하는 것이다
(아래 참고). 직접 CLI로 하려면:

```
"F:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "F:\Godot\Project\yacht-dice" --export-release "Web (배포)" "F:/Godot/web_build/index.html"
```

export가 끝나면 콘솔에 `BuildStamp: 배포용 빌드(yd_release 태그 있음) -
DEBUG_MODE 꺼짐`이 찍힌다(`addons/build_stamp`가 export 시점에 바로
알려준다) - **이 줄이 "개발용 빌드"로 찍히면 프리셋을 잘못 골랐다는
뜻이니 그 자리에서 바로 알 수 있다.**

**⚠️ 반드시 CLI로 export한다 - 에디터 GUI의 "내보내기" 버튼은 쓰지
않는다.** 실제로 겪은 문제: `export_presets.cfg`를 이미 올바르게
고쳐뒀는데도(디스크 파일 자체는 정상 - `custom_features="yd_release"`가
그대로 있었음), 에디터를 열어 GUI로 export하니 `yd_release` 태그가 안
먹힌 빌드가 나온 적이 있다. 에디터가 파일을 열 때 시점에 따라 메모리에
든 프리셋 상태가 디스크와 어긋날 수 있고(이 세션에서 이미 프리셋
전체가 통째로 덮어써진 사고를 한 번 겪음 - 그보다 작은 규모로 필드
하나만 어긋나는 것도 같은 원인 계열이다), GUI로 export하면 그 어긋난
상태 그대로 빌드가 나온다. CLI(`--headless --export-release`)는 그
순간 파일을 새로 읽어서 export하므로 이런 어긋남 자체가 생기지 않는다 -
**베타/정식 배포처럼 정확성이 중요한 export는 항상 CLI만 쓴다.**
개발 중 화면을 눈으로 보는 `Web (개발)` export는 GUI로 해도 상관없다
(디버그가 켜진 채로 나오는 게 기본값이라 위험이 없음).

## 2. 전체 테스트 통과 확인

```
godot --headless res://scripts/tests/test_runner.tscn
```

844개(작업이 늘면 숫자도 늘어난다) 전부 통과해야 한다.

## 3. 실제 export 빌드로 "정말 꺼졌는지" 화면에서 직접 확인

에디터의 "브라우저에서 실행"은 쓰지 않는다(`docs/web_export.md` 참고 —
실제 export와 다르게 동작해서 재현 안 되는 버그가 있었다). 상수 값을
읽는 게 아니라 **실제로 빌드에 구워진 값을 화면에서 직접 본다** -
1. `F:/Godot/web_build`를 정적 서버로 서빙(`python -m http.server`)해서
   브라우저로 직접 연다.
2. 화면 좌상단(또는 콘솔)의 빌드 배너에 `디버그 꺼짐`이 찍히는지 확인한다
   (`디버그 켜짐`이면 잘못된 프리셋으로 export된 것 - 1번부터 다시).
3. 아래 "DEBUG_MODE가 꺼지면 사라지는 것 목록"이 화면에 전혀 안 보이는지
   확인한다 - 디버그 버튼/단축키/화면 좌상단 진단 로그가 하나라도 보이면
   배포하면 안 된다.

## 4. `git status`로 남은 변경사항 확인

의도치 않게 커밋에 딸려 들어가는 파일이 없는지 마지막으로 확인한다.
`build_info.gd`의 `BUILD_TIME`은 export할 때마다 자동으로 바뀌는 값이라
커밋해도 무방하다(`DEBUG_MODE`는 이제 상수가 아니라 계산되는 값이라 이
파일에 diff가 남지 않는다). 이건 이 프로젝트(`F:\Godot\Project\yacht-dice`)의
git 상태다 - 아래 5번의 `F:/Godot/web_build`는 완전히 별도의 git 저장소다.

## 5. `F:/Godot/web_build`를 GitHub Pages 저장소에 커밋/푸시

`F:/Godot/web_build`는 이 프로젝트 git과 무관한 **별도의 git 저장소**다.
1~3번으로 만든 배포 빌드가 실제로 GitHub Pages에 올라가려면 그 저장소
안에서 따로 커밋하고 푸시해야 한다(이 프로젝트의 git 작업과는 다른
저장소이므로 여기서 자동으로 처리해주지 않는다).

## 참고 - DEBUG_MODE가 꺼지면(`Web (배포)`로 export하면) 사라지는 것

베타 테스터에게 "이게 왜 안 보이지"라는 질문을 받지 않으려면 미리
알아둘 것 - 아래는 전부 `Web (개발)`에는 있고 `Web (배포)`에는 없다.

- `scripts/dev/debug_hotkeys.gd`의 Ctrl+Shift+숫자/S/A 키보드 단축키
  (주사위를 원하는 족보로 강제 지정, 한 칸 확정, 게임 자동 진행)
- 화면 우하단의 디버그 버튼 6개([야추][라지][풀하우스][포카드][한 칸 확정][끝까지 진행])
  와 그 위의 캐시 사용량 표시(이미지/오디오 캐시 개수·용량)
- `Main.gd`의 화면 좌상단 진단 로그(게임 시작 초기화 단계,
  `special_hand_rolled` 구독자 목록 등)
- 온라인 로비 화면의 전송 진단 로그 패널(`online_screen.gd`의
  `_transfer_debug_log`)
- 온라인 전용 `[빠른 진행]` 버튼(한 턴만 자동 처리)

**베타 중에도 항상 켜져 있는 것(DEBUG_MODE와 무관)**:

- **서버(`server_main.gd`) 콘솔의 모든 `[서버]`/`[서버][전송]` 로그.**
  서버는 이 체크리스트가 다루는 클라이언트 웹 빌드와 별개로 항상
  headless 바이너리로 직접 돌리는 것이라 이 프리셋 전환의 영향을 받지
  않는다 - 애초에 서버 쪽 로그는 처음부터 DEBUG_MODE에 안 묶여 있다
  (베타 운영자가 문제를 진단하는 유일한 창이므로 의도한 설계).
