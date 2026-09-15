# 배포 준비 체크리스트 (3-3)

정식으로 배포할 빌드를 만들기 직전에 이 목록을 확인한다. 개발 중에는 웹
export 빌드를 계속 확인해야 해서 디버그 기능을 켜둔 채로 지내는 게 정상이고,
그래서 실수로 켠 채 배포하는 사고가 나기 쉽다 — 이 문서는 그걸 막기 위한
마지막 관문이다.

## 1. `DEBUG_MODE`가 `false`인지 확인

`build_info.gd`의 `const DEBUG_MODE`를 연다. `true`로 되어 있으면 아래가
전부 정식 빌드에 그대로 남는다:

- `scripts/dev/debug_hotkeys.gd`의 Ctrl+Shift+숫자/S/A 키보드 단축키
  (주사위를 원하는 족보로 강제 지정, 게임 자동 진행)
- 화면 우하단의 디버그 버튼 6개([야추][라지][풀하우스][포카드][한 칸 확정][끝까지 진행])
- 화면 좌상단의 진단 로그(초기화 단계, `special_hand_rolled` 구독자 목록 등)

`false`로 바꾼 뒤 `git diff build_info.gd`로 다른 값(특히 `BUILD_TIME`)이
같이 바뀌지 않았는지도 확인하고 커밋한다.

## 2. 전체 테스트 통과 확인

```
godot --headless res://scripts/tests/test_runner.tscn
```

387개(작업이 늘면 숫자도 늘어난다) 전부 통과해야 한다.

## 3. 실제 export 빌드로 확인

에디터의 "브라우저에서 실행"은 쓰지 않는다(`docs/web_export.md` 참고 — 실제
export와 다르게 동작해서 재현 안 되는 버그가 있었다). 반드시:

1. `godot --headless --path . --export-release "Web" "F:/Godot/web_build/index.html"`
2. `F:/Godot/web_build`를 정적 서버로 서빙(`python -m http.server`)해서 브라우저로 직접 확인
3. 위 디버그 버튼/로그가 화면에 전혀 안 보이는지 확인 — DEBUG_MODE를
   false로 내렸는데도 뭔가 보이면 배포하면 안 된다.

## 4. `git status`로 남은 변경사항 확인

의도치 않게 커밋에 딸려 들어가는 파일이 없는지 마지막으로 확인한다.
