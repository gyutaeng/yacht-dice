# 리치마작 확장 여지 조사 (요트다이스 저장소 기준)

이 문서는 **`yacht-dice` 저장소를 전혀 모르는 사람**이 커스텀 리치마작
프로젝트를 새로 시작할 때 첫 입력 자료로 쓰기 위해 작성됐다. 요트다이스는
"플레이어가 직접 만든 캐릭터(이미지+보이스)로 즐기는 온라인 보드게임"이고,
Godot 4.7 / GDScript, 서버 권위 구조(WebSocket, Render에 Docker로 배포),
클라이언트는 웹(HTML5)이다. 다음 프로젝트(리치마작)도 같은 방식(캐릭터
커스텀 + 온라인 대전)이라는 전제 하에, 이 저장소에서 무엇을 그대로/거의
그대로 가져다 쓸 수 있고, 무엇을 구조만 빌려 내용을 새로 짜야 하고, 무엇을
아예 새로 설계해야 하는지 조사한 결과다.

**코드는 조사 과정에서 전혀 수정하지 않았다.** 아래 모든 판단은 실제
파일을 읽고 확인한 내용이다.

## 분류 기준

- **(A) 거의 그대로 재사용 가능** — 요트다이스 규칙(주사위/점수판)에
  의존하지 않는 순수 인프라. 파일명이나 주석의 "요트다이스"/"야추" 언급
  정도만 바꾸면 그대로 쓸 수 있다.
- **(B) 구조는 재사용, 내용은 교체** — 설계 패턴(클래스 구조, 책임 분리,
  이벤트 흐름)은 그대로 베낄 가치가 있지만, 그 안의 구체적 내용(상수 값,
  메서드 이름, 데이터 필드)은 마작에 맞게 다시 써야 한다.
- **(C) 재사용 불가** — 요트다이스 규칙(주사위 5개, 12개 점수 카테고리,
  리롤 3회 등)에 완전히 종속돼서 마작에 옮길 게 거의 없다.

---

## 조사 1 — 재사용 가능성 분류

### 네트워크 계층

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `scripts/net/protocol.gd` — 메시지 봉투(`encode`/`decode`), 프로토콜 버전, 에러 코드 상수, `sanitize_display_name()` | **A** | JSON 봉투 형식(`{"type":..., "payload":...}`)과 디코드 실패 시 연결을 신뢰하지 않는 원칙은 게임 종류와 무관하다. |
| `protocol.gd` — 송신 대기열 안전장치: `has_room_to_send_now()`/`can_chunk_ever_be_sent()`/`estimate_encoded_chunk_bytes()` | **A** | `WebSocketPeer` 버퍼 오버플로우 문제(2-5~확정2/3에서 실제로 겪은 버그)를 해결한 범용 로직. 상수(`CHUNK_PAYLOAD_BYTES` 등) 값만 마작 캐릭터 팩 크기에 맞게 재조정하면 된다. |
| `protocol.gd` — 핑/타임아웃 상수(`PING_INTERVAL_MSEC`/`PING_TIMEOUT_MSEC`), 재접속 유예(`IN_GAME_RECONNECT_GRACE_MSEC`/`POST_GAME_RECONNECT_GRACE_MSEC`), 재대전 대기(`REMATCH_READY_TIMEOUT_MSEC`) | **A** | 연결 끊김 감지·재접속 유예는 순수 네트워크 관심사. 값 자체(60초/3분/2분)도 그대로 쓸 만하다 — 이 값들은 전부 실제 베타 테스트로 조정된 실측치라 마작에서도 출발점으로 유효하다. |
| `protocol.gd` — 메시지 이름 상수(`MSG_REQUEST_ROLL`/`MSG_DICE_ROLLED`/`MSG_SCORE_COMMITTED` 등 게임 진행 메시지) | **C** | 이름 자체가 요트다이스 행동(굴리기/고정/점수 확정)이다. 로비/팩 전송 메시지(`MSG_HELLO`/`MSG_CREATE_ROOM`/`MSG_SELECT_CHARACTER`/`MSG_READY`/`MSG_UPLOAD_PACK_CHUNK` 등)는 A, 게임 진행 메시지만 C로 갈린다. |
| `scripts/net/room_manager.gd` — 방 코드 발급, `join_room()`(토큰 기반 재접속/신규 참가 분기), `remove_peer()`(자발적 이탈 vs 그레이스) | **A** | 순수 로직(`RefCounted`, 네트워크 모름), 게임 종류와 완전히 무관. `MIN/MAX_PLAYER_COUNT`만 `GameState`(요트다이스 전용 클래스)를 참조하므로 이 한 줄만 마작 쪽 상수로 바꾸면 된다. |
| `scripts/net/room.gd` — `State`/`ConnectionState`/`TransferState` enum, 슬롯 배열, 재접속 토큰, 팩 전송 상태 기계(`begin_transfer`~`mark_transfer_done`) | **B** | 로비→(캐릭터 팩 전송)→게임 중→재대전 대기라는 **상태 기계 자체**는 그대로 베낄 가치가 있다. 다만 `game_state: GameState` 필드와 `validate_roll/hold/score()`(요트다이스 행동 검증)는 완전히 새로 써야 한다. **가장 중요한 한계**: `Room`은 "슬롯당 GameState 인스턴스 하나 = 게임 하나"라는 1:1 모델이라, 마작의 "한 방에서 여러 국(局)을 도는 하나의 판(반장전)"을 표현할 개념이 없다(조사 2 참고). |
| `scripts/net/game_client.gd` — 연결/로비/팩 전송 부분(`connect_to_server`/`create_room`/`join_room`/`select_character`/`set_ready`/`request_character_pack`/`upload_pack_chunk`, 송신 큐 `_flush_outgoing_queue`/`_check_outgoing_stall`, `State` enum) | **A** | 이 파일의 앞쪽 60~70%가 여기 해당한다. |
| `game_client.gd` — 게임 진행 시그널·메서드(`request_roll/hold/score`, `dice_rolled`/`score_committed`/`yacht_scored`/`turn_started` 등 시그널, `_handle_packet()`의 그 부분 분기) | **C** | 요트다이스 행동 그대로. 마작은 `request_discard`/`request_call_pon`/`riichi_declared` 같은 완전히 다른 어휘가 필요하다. |
| `scripts/net/reconnect_backoff.gd` | **A** | 지수 백오프(1,2,4,8,16...) 순수 계산. 게임과 무관. |
| `scripts/net/session_store.gd` | **A** | `user://session.json`에 재접속 토큰 저장/삭제. 게임과 무관. |
| `scripts/net/secure_random.gd` | **A** | `Crypto.generate_random_bytes()` 기반 시드 생성. 마작 패산(牌山) 셔플에도 그대로 필요한 암호학적으로 안전한 RNG 시드다. |
| `scripts/net/received_pack_cache.gd`, `pack_transfer_client.gd` | **B** | 해시 기반 캐시/청크 재전송 요청 구조는 그대로 쓸 만하지만, 캐시 폴더 이름(`user://cache/received/`)이나 상한 값 등은 마작 캐릭터 팩 크기 정책에 맞게 재조정 대상. |
| `scripts/net/game_event_relay.gd`(RELAYED_EVENTS/EXCLUDED_EVENTS 분류 + 리플렉션 검증) | **B** | "새 시그널을 추가하면 분류를 빠뜨릴 수 없게 자동 검증한다"는 **기법**은 매우 유용하지만, 목록 내용 자체는 `GameEvents`(요트다이스 시그널)를 그대로 가리킨다. |
| `server_main.gd` — 서버 부팅(`_resolve_port`/`_resolve_bind_address`), 버퍼 설정, `_broadcast_room`/`_send`/`_send_error`/`_log_ignored`, 핑/하트비트/그레이스 서비스 루프(`_service_ping_timeouts`/`_service_connection_heartbeat`) | **A** | 게임 종류와 무관한 서버 골격. |
| `server_main.gd` — `_handle_request_roll/hold/score`, `_on_ge_*`(GameEvents 릴레이), `_mutate_and_broadcast()` | **B/C 경계** | `_mutate_and_broadcast()`(상태 변경 → 스냅샷 전체 브로드캐스트 → 대기 이벤트 전송)라는 **흐름 자체**는 재사용 가치가 있다(B). 하지만 그 안에서 부르는 `room.game_state.roll()` 등은 완전히 새로 짜야 하고(C), 무엇보다 **`_broadcast_room()`이 방 전원에게 항상 "완전히 같은 payload"를 보낸다는 전제 자체가 마작에서는 깨진다** — 조사 2 참고. |

### 캐릭터 팩(생성·검증·저장·전송·캐시)

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `scripts/characters/character_profile.gd` — 스키마(`id`/`display_name`/`portrait_file`/`thumbnail_file`/`voice_map`/`volume_db`), `FORMAT_VERSION`, `from_dict()`/`to_dict()`, `_sanitize_voice_map()` | **A** | 게임 종류를 어디에도 가정하지 않는다. `voice_map`의 키(이벤트 이름)는 완전히 임의의 문자열이라 마작 이벤트 키를 그대로 넣을 수 있다. |
| `autoload/character_library.gd` — 스캔/저장/삭제/복제, `export_pack_bytes()`/`import_pack()`/`validate_and_extract_pack()`(경로 탈출 방지, 확장자 화이트리스트, 50MB 압축해제 상한), `_referenced_files()`(고아 파일 정리) | **A** | 전부 게임 무관. 유일하게 게임 이름이 박힌 상수는 `PACK_FILE_SUFFIX := ".ydchar.zip"` 하나뿐이다(조사 3에서 다룸). |
| `autoload/asset_loader.gd` | **A** | grep으로 확인 — "요트"/"야추"/"Yacht"/"dice" 등 게임 관련 문자열이 전혀 없다. 순수 바이트 기반 이미지/오디오 로더(PNG/JPG/WebP/WAV/OGG/MP3 매직바이트 검사, LRU 캐시). 이 저장소에서 가장 완성도 높게 게임과 분리된 파일이다. |
| `scripts/characters/character_limits.gd` | **A** | 크기/길이 상한 표. 값(픽셀/용량/초)은 게임 무관 — 마작도 같은 종류의 이미지/보이스를 쓰므로 숫자까지 그대로 출발점으로 쓸 만하다. |
| `scripts/characters/character_portrait.gd` | **A** | 어느 파일을 읽을지 + 실루엣 폴백 결정. 게임 화면 레이아웃과 무관한 순수 판단 로직. |
| `docs/character_pack.md` | **B** | 문서 구조(스키마 설명 + 크기 제한 + 검증 규칙)는 그대로 베낄 틀이지만, 내용 중 "요트다이스" 언급과 보이스 이벤트 예시는 교체 대상. |

### 보이스뱅크 / SFX뱅크 / 이벤트 버스(GameEvents)

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `autoload/game_events.gd` — 시그널 선언(`dice_rolled`/`score_committed`/`yacht_scored` 등) | **C** | 요트다이스 규칙 그 자체. |
| `game_events.gd` — `Common := {GAME_START, TURN_START, WIN, LOSE}` 네임스페이스 관례, `VOICE_EVENTS` 테이블 스키마(`key`/`label`/`description`/`frequency`/`recommended_label`/`recommended_max_sec`) | **A(패턴)** | **이 파일 자체에 이미 "리치마작을 붙일 때 여기에 Mahjong := { RIICHI = ..., ... } 를 추가한다"는 주석이 있다** — 즉 게임별 네임스페이스로 캐릭터 보이스 이벤트를 나누는 설계가 처음부터 여러 게임을 염두에 두고 만들어졌다. 다만 마작 프로젝트는 별도 저장소이므로 이 파일을 "확장"하는 게 아니라, **같은 패턴(Common 네임스페이스 + 테이블 스키마)을 그대로 베껴 자기 자신의 `GameEvents`를 새로 만드는 것**이 맞다. |
| `autoload/voice_bank.gd` — 전역 재생 조정(`_request_voice`/`_preempt_and_play`/`_start_playing_stream`/`_try_play_pending`, 우선순위 선점, 대기 타임아웃), 인사/승패 시퀀스 재생(`play_greeting_sequence`/`_advance_greeting`/`_play_game_end_sequence`), `configure(profiles)`, 크로스페이드 | **B** | "한 번에 한 명만 말한다, 우선순위 높은 요청이 오면 페이드아웃 후 교체, 대기 큐는 하나만 유지하고 타임아웃 지나면 버린다"는 **조정 엔진**은 매우 정교하게 다듬어진 부분(친구 대상 실사용 테스트로 검증됨)이라 그대로 가져갈 가치가 크다. 다만 `_event_priority`(우선순위 표)와 `_on_special_hand_rolled`/`_on_bonus_achieved`/`event_key_for_category()`는 요트다이스 카테고리에 종속되어 있어 새로 써야 한다. |
| `voice_bank.gd` — `PRIORITY_ENDING`/`PRIORITY_YACHT`/`PRIORITY_SPECIAL_HAND`/`PRIORITY_GAME_START`/`PRIORITY_TURN_START` | **B** | "승패 > 하이라이트 > 게임시작 > 내차례" 같은 **우선순위 단계 개념**은 재사용, 이름과 개수(마작은 리치/쯔모/론/역만 등으로 하이라이트 종류가 훨씬 많음)는 다시 설계. |
| `autoload/sfx_bank.gd` | **B** | `AudioStreamPlayer` 풀 + `GameEvents` 구독 + `_load_optional()`(파일 없으면 조용히 스킵) **패턴**은 재사용. 내용(주사위 굴림/고정/야추/특수족보 4개 사운드)은 전부 C. |

### 화면 전환(Main.gd)과 "리모컨" 컨트롤러 구조

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `scenes/Main.gd` — `enum Screen`/`_show_screen()`(화면 전환을 한 함수로 통일, 오버레이를 매번 확실히 닫음) | **A** | 이 프로젝트가 실제로 겪은 버그(오버레이가 안 닫혀 화면이 안 넘어가는 것처럼 보임)를 고친 결과물이라, 처음부터 이 패턴으로 시작하면 같은 실수를 반복하지 않는다. |
| `LocalGameController`/`OnlineGameController`(`scripts/game/`) — 덕타이핑 계약(`request_*`/`is_request_pending`/`leave_game`/`dispose`/`get_game_over_actions`), Main.gd가 로컬/온라인을 몰라도 되게 하는 구조 | **A(패턴) / C(메서드 내용)** | "화면은 컨트롤러가 로컬인지 온라인인지 몰라야 한다"는 **원칙과 뼈대**는 그대로 베낄 가치가 최고로 높다(이 프로젝트가 실제로 겪은 버그 - `OnlineGameController`의 리스너 누수 - 를 고친 `_connect_tracked()`/`dispose()` 장부 패턴까지 포함). 다만 메서드 이름 자체(`request_roll`/`request_hold`/`request_score`)는 마작 행동(`request_discard`/`request_call_*`/`declare_riichi` 등)으로 전부 바뀐다. |
| `Main.gd` — `_build_character_area()`/`_transition_portrait()`/`_player_label_text()`(초상화 크로스페이드), `_start_greeting_sequence()`(인사 순차 재생 + 입력 차단) | **A** | 캐릭터 초상/보이스 연출은 어떤 보드게임에도 그대로 붙는다. |
| `Main.gd` — `_build_scoreboard()`/`_refresh_scoreboard_ui()`/`score_labels[player][category]`/`dice_labels`/`_on_dice_gui_input` | **C** | 12칸 점수판 그리드, 주사위 5개 UI. 마작은 손패/버림패/콜 표시 등 전혀 다른 화면이 필요해서 여기는 **완전히 새로 그려야 한다.** |
| `Main.gd` — `_play_special_hand_effect()`(팝업 라벨 페이드), `_compute_game_over_rankings()`/`_build_game_over_results_list()`(공동순위 계산 + 캐릭터 썸네일 + "(나감)" 표시) | **B** | 팝업 연출 메커니즘과 "동점자를 순위표에서 어떻게 묶어 보여줄지"는 마작 최종 결과 화면에도 유용한 패턴이지만, 트리거 조건(카테고리 이름)과 순위 계산 세부(마작은 단순 합계가 아니라 판마다 순위점을 매기는 경우가 흔함)는 다시 설계. |
| **구조적 조언** | — | `Main.gd`는 1385줄짜리 파일 하나에 화면 전환/컨트롤러 연결/캐릭터 연출/점수판 렌더링이 전부 섞여 있다. 마작 프로젝트에서는 **이 파일을 통째로 복사하지 말고**, 화면 전환·컨트롤러 연결·캐릭터 연출 부분만 뽑아 새 파일로 시작하고 점수판/입력 부분은 처음부터 새로 짜는 걸 권한다. |

### 배포 일체

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `Dockerfile`, `docker-entrypoint.sh`, `nginx.conf.template`, `docker-log-filter.sh` | **A** | grep으로 전수 확인 — 게임 이름이 박힌 곳은 헬스체크 응답 문자열(`"yacht-dice server: ok"`) 하나와 로그 접두어 주석뿐이다. Godot 헤드리스 서버를 내부 포트에 띄우고 nginx가 Render의 공개 포트를 받아 WebSocket만 패스스루하는 구조, 헬스체크 후보 A/B/C 검토 결과(TCP 확인만으론 부족해서 nginx 프록시가 필요했던 이유)까지 통째로 재사용 가치가 있다. |
| `addons/build_stamp/`(빌드 시각/커밋 해시 자동 스탬핑) | **A** | 완전히 범용. `custom_features="yd_release"` 태그 이름만 바꾸면 된다. |
| `export_presets.cfg`의 `Web (dev)`/`Web (release)` 이원화 + `DEBUG_MODE` 자동 전환 구조 | **A** | 패턴 자체가 범용. 프리셋 이름/경로만 새 프로젝트 것으로. |
| `build_release.bat`/`run_server.bat` | **A** | 경로 상수만 바꾸면 그대로. |
| `.gitignore`/`.dockerignore`의 "저장소 루트 이미지/오디오 확장자 차단" 규칙, "효과음 원본 제외" 패턴 | **A** | 재발 방지 규칙 자체가 범용 교훈. |

### 테스트 러너와 테스트 구조

| 영역/파일 | 분류 | 근거 |
|---|---|---|
| `scripts/tests/test_runner.gd`/`test_runner.tscn`/`test_reporter.gd` | **A** | `func run(r) -> void:`를 갖는 스크립트를 `SUITES` 배열에 preload로 등록하는 방식일 뿐, 게임 내용과 무관. "테스트는 반드시 씬으로 실행한다(`--script`는 autoload 미등록)"는 이 프로젝트의 교훈도 그대로 유효하다. |
| 캐릭터/네트워크 계열 테스트 스위트(`test_character_library.gd`/`test_character_pack.gd`/`test_character_limits.gd`/`test_asset_loader.gd`/`test_protocol.gd`/`test_session_store.gd`/`test_room_manager.gd`/`test_room_connection.gd`/`test_reconnect_backoff.gd`/`test_pack_transfer_metadata.gd`/`test_outbound_buffer_safety.gd`/`test_server_port_resolution.gd`/`test_game_client_connect_timeout.gd` 등) | **A/B** | 이들이 검증하는 대상(A로 분류된 파일들)이 그대로 재사용되므로 테스트도 거의 그대로(경로/상수만 조정) 가져갈 수 있다. |
| 규칙/점수 계열 테스트(`test_initial_state.gd`/`test_scoring.gd`/`test_bonus.gd`/`test_special_hands.gd`/`test_auto_confirm.gd`/`test_game_start_builtin_only.gd`), 게임 상태 동기화 테스트(`test_game_state_snapshot.gd`/`test_room_gameplay.gd`/`test_online_game_controller.gd`) | **C** | 요트다이스 규칙을 직접 검증하는 테스트라 내용은 못 쓰지만, **"화이트박스로 우선순위/타임아웃/결정성을 검증한다"는 테스트 작성 스타일**은 마작 쪽에서도 그대로 따라할 가치가 있다. |
| `test_game_event_relay_classification.gd`(리플렉션으로 시그널 전수 분류 검증) | **B** | "새 시그널을 추가하면 분류를 빠뜨릴 수 없다"는 이 검증 **기법**은 마작에도 그대로 이식할 가치가 크다. |

### GameState와 점수 계산 — B/C 경계

`scripts/game_state.gd`(543줄) 전체를 확인했다. 대부분 C지만, 몇 가지는 **개념만** 가져갈 수 있다.

**C(재사용 불가) — 파일의 대부분**:
- `CATEGORY_NAMES`/`SPECIAL_HAND_PRIORITY`/`UPPER_BONUS_*`/`YACHT_CATEGORY_INDEX` 등 전부.
- `calc_aces()`~`calc_yacht()`(12개 점수 계산 함수) 전부.
- `dice_results`/`dice_locked`/`MAX_ROLLS_PER_TURN`/`_roll_unlocked_dice()` — 주사위 5개, 리롤 3회라는 요트다이스 고유 개념.
- `get_state_snapshot()`/`apply_snapshot()`의 **필드 목록**(dice_results, rolls_left, player_confirmed_scores 등) — 마작은 완전히 다른 필드(손패, 버림패, 도라 표시패, 리치 상태 등)가 필요하다.
- "한 게임 = `GameState` 인스턴스 하나가 시작부터 `game_over`까지 전부 담당한다"는 **모델 자체** — 마작은 이 경계 자체가 다르다(아래 조사 2 "판 수" 참고).

**B(구조만 재사용)**:
- `read_only` 가드 패턴 — "온라인 클라이언트가 들고 있는 사본은 절대 스스로 진행하면 안 되고, 어긋나면 `push_error`로 시끄럽게 실패해야 한다"는 원칙(이 프로젝트가 과거 "에러 없이 조용히 틀리는" 사고를 여러 번 겪고 도입한 방어) — 마작의 손패 동기화에도 그대로 필요한 개념이다.
- `apply_snapshot()`이 JSON 왕복 후 정수/불리언 타입을 명시적으로 강제하는 습관(`int()`/`bool()`) — JSON은 정수도 float로 돌려준다는 함정은 마작 스냅샷에도 똑같이 적용된다.
- `state_changed` 시그널 하나로 UI 전체 갱신을 트리거하는 방식.
- `get_winners()`(동점자를 배열로 전부 반환) — "합산 점수로 순위를 매기고 동점을 허용한다"는 아이디어 자체는 마작 최종 결과에도 쓰이지만, 마작은 보통 매 국(局)마다도 순위/점수 변동이 있어 이 함수 하나로는 부족하다.
- `RefCounted` 기반이라 컨트롤러가 버려지면 자동으로 가비지 컬렉션되는 생명주기 — 새 게임마다 인스턴스를 새로 만들고 예전 것은 그냥 참조를 끊으면 되는 방식은 그대로 유효하다.

---

## 조사 2 — 마작에서 새로 생기는 요구사항과의 충돌

### 인원(3인 vs 4인)

현재 구조: `RoomManager.is_valid_player_count()`가 `GameState.MIN_PLAYER_COUNT`(2)~`MAX_PLAYER_COUNT`(4) 범위를 검사하고, `Room.change_capacity()`가 **같은 규칙의 GameState를 인원수만 다르게 새로 만든다** — 요트다이스는 2/3/4인이 전부 "같은 규칙, 참가자 수만 다름"이기 때문에 이 모델이 성립한다.

마작은 다르다. 3인 마작과 4인 마작은 패산 구성(3인은 보통 2~8만 패를 빼고 침)과 일부 역(役) 성립 조건이 달라서, **"인원수 슬라이더"가 아니라 "규칙 세트 선택"에 가깝다.** 지금 구조를 그대로 가져가면 안 되는 지점:
- `change_capacity()`처럼 로비 중에 인원을 유동적으로 바꾸는 기능은, 마작에서는 "3인 마작 방"과 "4인 마작 방"을 아예 다른 규칙 엔진으로 취급해야 하므로 **게임 시작 전 "3인/4인" 모드 선택으로 대체**해야 한다(단순 인원수 검증이 아니라 규칙 클래스 자체를 고르는 개념).
- 방/슬롯 배열 구조 자체(`Room.slots`, 재접속 토큰, 연결 상태 관리)는 인원수와 무관하게 그대로 재사용 가능(A) — 바뀌는 건 "capacity를 바꿀 수 있다"는 가정 하나뿐이다.

**결론**: 슬롯/재접속 인프라는 그대로, "규칙은 인원수와 무관하게 하나"라는 전제만 버리면 된다.

### 판 수(동풍전/반장전 — 한 게임 안에 여러 국)

이게 조사 1에서 이미 짚었듯 **구조가 아예 없는 영역**이다. 지금 모델:

```
Room.State: LOBBY → TRANSFERRING → IN_GAME → REMATCHING → (새 IN_GAME)
                                     └─ GameState 인스턴스 1개, 시작~game_over까지
```

재대전(`Room.start_new_game()`)은 "이전 게임과 완전히 무관한 새 게임"을 만드는 것이 목적이라 점수도 0부터, 캐릭터도 다시 고를 수 있게 설계돼 있다(2-6B). 이건 마작의 "국(局)"과 정반대다 — 마작은 한 국이 끝나도 **누적 점수, 국 순서(동1국→동2국→...), 장풍(동/남/서/북), 연장(같은 장을 반복하는 본장 수)이 다음 국으로 이어져야 한다.**

지금 코드에는 이 "이어지는 여러 국을 감싸는 상위 개념"이 전혀 없다 — `Room`은 `GameState` 하나만 들고 있고, 그 하나가 끝나면 방은 로비류 상태(REMATCHING)로 돌아갈 뿐이다. **새로 설계해야 할 계층**:
- `Match`(또는 `Hanchan`) 같은 새 객체: 현재 장풍/국수/연장, 참가자별 누적 점수, 매치 종료 조건(예: 하코텐/톱 플레이어 확정, 특정 점수 이하 파산)을 들고 있다.
- `Room.state`에 `IN_GAME`(한 국 진행 중)과 그 국들을 감싸는 `Match` 개념을 별도 레이어로 추가 — `Room`이 `GameState` 하나 대신 `Match`(여러 개의 "국" 인스턴스를 순서대로 만들어내는 것) 하나를 들게 하는 구조가 필요하다.
- 참고할 수 있는 유일한 기존 패턴: `change_capacity()`/`start_new_game()`이 "같은 `rng` 인스턴스는 재사용하되 상태 객체는 새로 만든다"는 방식 — 국이 바뀔 때 "새 국(局) 객체를 만들되 매치 전체의 RNG나 누적 점수는 유지"하는 것과 결이 비슷해서, 이 패턴 자체는 참고가 된다. 다만 "무엇을 초기화하고 무엇을 이어받는지"의 목록(장풍/연장/누적점수는 유지, 손패/버림패/도라는 초기화)은 전부 새로 정의해야 한다.

### 비공개 정보(★ 가장 큰 차이 — 실제로 확인해보니 맞았다)

`server_main.gd`를 직접 읽어 확정했다: **`_broadcast_room()`은 방의 모든 슬롯에게 정확히 같은 `payload` 객체를 그대로 보낸다**(`server_main.gd:1527` — 반복문 안에서 슬롯마다 다른 내용을 만드는 코드가 전혀 없다). `_mutate_and_broadcast()`도 `room.game_state.get_state_snapshot()` **하나**를 만들어서 그 하나를 전원에게 뿌린다(`server_main.gd:1288-1296`). 재접속 시 특정 peer 한 명에게만 스냅샷을 보내는 경로(`_handle_join_room`, 506행)도 있지만, 그마저 "누구에게 보낼지"만 다를 뿐 **보내는 내용은 여전히 같은 전체 스냅샷**이다.

즉 이 저장소의 동기화 모델은 "서버가 정답을 하나 계산하면, 그 정답을 아무 필터링 없이 방 전체에 복사해서 뿌린다"는 것을 전제로 처음부터 끝까지 설계돼 있다 — 요트다이스는 주사위가 전부 공개 정보라 이 전제가 성립했다. 이걸 뒷받침하는 증거를 더 들면:
- `GameState.get_state_snapshot()`이 반환하는 Dictionary에는 "이 필드는 이 플레이어에게만 보여준다" 같은 개념 자체가 없다 — 단일 평면 Dictionary.
- `Room`도 "이 슬롯 전용 뷰"를 계산하는 메서드가 전혀 없다(`players_summary()`도 전원에게 같은 배열을 준다).

마작은 정확히 이 지점이 깨진다 — 각자 손패(13~14장)는 자신에게만 보여야 하고, 남의 손패는 안 보여야(가려야) 한다(단, 리치 선언 여부·버림패·콜한 패처럼 공개돼야 하는 부분정보도 있다 — "전부 비공개"가 아니라 "필드마다 공개 범위가 다르다"는 게 진짜 어려운 지점이다).

**필요한 재설계(새로 만들어야 함, 기존에 유사 개념 없음)**:
1. `get_state_snapshot()`을 "전체 상태를 하나 만드는" 함수에서 **"보는 사람의 player_index를 받아서, 그 사람 기준으로 필터링된 스냅샷을 만드는" 함수**(예: `get_state_snapshot_for(viewer_index: int)`)로 바꿔야 한다. 손패 필드는 `viewer_index == 그 손패 주인`일 때만 실제 패 목록을, 아니면 "장수만"(또는 아예 생략) 넣는 식.
2. `_broadcast_room()`처럼 "같은 payload를 슬롯 배열에 반복해서 보내는" 함수를 그대로 재사용할 수 없다 — **슬롯마다 다른 payload를 만들어서 각자에게 개별 전송하는 함수**가 새로 필요하다(`_send()` 자체는 peer 하나에게 보내는 함수라 그대로 재사용 가능하지만, "전원에게 같은 것"이라는 `_broadcast_room()`의 전제가 깨지므로 이 함수를 감싸는 새 헬퍼가 필요하다).
3. 클라이언트 쪽 `GameState`(온라인 사본, `read_only`)도 "내 손패는 실제 값, 남의 손패는 안 보이거나 장수만" 같은 **부분적으로 비어있는 상태**를 정상적으로 표현할 수 있어야 한다 — 지금 `apply_snapshot()`은 "완전한 스냅샷이 온다"는 전제로 짜여 있어서, 필드가 일부만 채워진 스냅샷을 받는 경우를 아예 상정하지 않는다.
4. 보안 관점도 새로 생긴다 — 원칙 6("외부 입력을 신뢰하지 않는다")이 지금까지는 "클라이언트가 보낸 값을 서버가 안 믿는다" 방향으로만 적용됐는데, 마작에서는 반대 방향("서버가 클라이언트에게 남의 손패를 실수로 보내면 안 된다")도 똑같이 중요해진다 — 이건 순수히 서버 쪽 스냅샷 필터링 코드의 정확성 문제라 자동화된 회귀 테스트(예: "특정 플레이어에게 간 payload에 남의 손패 필드가 절대 없어야 한다"를 검증하는 테스트)를 처음부터 넣는 걸 권한다.

### 턴 구조(반응/콜 — 론·폰·치, 동시에 여러 명이 반응 가능)

지금 서버의 턴 검증은 전부 "지금 `current_player`가 나인가"라는 단일 기준이다(`Room._validate_turn()` → `find_slot_by_peer(peer_id) != game_state.current_player`면 거부, `OnlineGameController._request_pending` 하나로 연타 방지). 마작은:
- 내 차례가 아니어도(남이 버린 패에 대해) 론/폰/치/깡을 선언할 수 있다.
- 여러 명이 동시에 반응할 수 있고(예: 두 명이 동시에 론 선언), 우선순위(론 > 퐁/깡 > 치, 그리고 방향 규칙)로 하나를 골라야 한다.
- 콜이 성립하면 정상적인 "다음 차례로 자동 진행"이 아니라 **턴이 그 자리로 점프**한다.

이건 "지금 차례인 사람 한 명만 유효한 요청을 보낼 수 있다"는 지금 서버 모델의 근본 전제와 충돌한다. `TURN_TIMEOUT_MSEC`(내 턴에 응답 없으면 서버가 자동 진행) 같은 **"마감 시각을 두고 지나면 서버가 판단한다"는 타이머 인프라 자체는 재사용 가능(B)**하지만, "그 마감 시각 동안 유효한 응답자가 여러 명"이라는 것과 "먼저 온 응답이 아니라 우선순위가 높은 응답이 이긴다"는 조정 로직은 완전히 새로 설계해야 한다(반응 수집 → 짧은 시간 대기 → 우선순위 판정 → 승자 반영, 이런 흐름 자체가 새로운 서버 상태).

### 연출 시간(마작은 판정·연출이 훨씬 많다)

`VoiceBank`의 전역 조정 엔진(한 번에 하나만 재생, 우선순위로 선점, 대기 타임아웃 1.5초 지나면 버림)은 구조적으로는 이벤트 빈도가 늘어나도 버틴다(B) — 다만 튜닝된 상수들(`VOICE_WAIT_TIMEOUT_MSEC=1500`, `GREETING_GAP_DURATION=0.3`)은 요트다이스의 이벤트 빈도(한 턴에 한 번 정도)에 맞춰 잡힌 값이라, 마작처럼 매 버림패·매 콜 기회마다 이벤트가 날 수 있는 환경에서는 재튜닝이 필요할 가능성이 높다. 우선순위 단계도 5단계(`PRIORITY_ENDING`~`PRIORITY_TURN_START`)에서 리치/쯔모/론/역만/유국 등으로 훨씬 세분화해야 할 것이다.

---

## 조사 3 — 캐릭터 팩

### 게임 독립적인 부분 vs 요트다이스 전용 부분

`autoload/character_library.gd`와 `scripts/characters/character_profile.gd`를 다시 확인한 결과, **게임 이름이 박힌 지점은 딱 하나**다:

```gdscript
const PACK_FILE_SUFFIX := ".ydchar.zip"
```

그 외 manifest 스키마(`format_version`/`id`/`display_name`/`portrait_file`/`thumbnail_file`/`voice_map`/`volume_db`), zip 압축/해제, 경로 탈출 방지, 확장자 화이트리스트(`png/jpg/jpeg/webp/wav/ogg/mp3/json`), 50MB 압축해제 상한, 파일 참조 정리 로직은 전부 게임과 무관하다. `voice_map`은 애초에 "문자열 키 → 파일명 배열"일 뿐이라 마작 이벤트 키를 넣어도 스키마 검증을 그대로 통과한다.

### 호환 안 되게 만드는 방법 + 오류 안내

1. **확장자를 바꾼다**: `.ydchar.zip` → 예를 들어 `.rmjchar.zip`(리치마작 가정) 같은 새 확장자로 정한다. `character_library.gd`의 `PACK_FILE_SUFFIX` 상수 하나만 바꾸면 파일 선택 다이얼로그 필터/내보내기 파일명이 자동으로 따라간다.
2. **포맷 식별자를 명시적으로 넣는다**: manifest.json에 `"format_version"`은 이미 있지만 이건 "같은 게임의 스키마 버전"을 뜻하는 필드다. 여기에 **게임 식별자 필드를 하나 추가**하는 걸 권한다(예: `"game": "yacht-dice"` vs `"game": "riichi-mahjong"`). `CharacterProfile.from_dict()`가 이 필드를 확인해서, 값이 다르면(또는 필드 자체가 없으면 - 확장자만 다르고 내용은 같은 실수 방지) 스키마 검증을 실패시킨다.
3. **잘못된 팩을 넣었을 때 분명하게 알려주기**: 지금 `character_library.gd`의 `_extract_error()`/`_import_error()` 패턴(에러 사유를 문자열로 만들어 UI가 그대로 보여주는 구조)이 이미 있다 — 여기에 사유 하나를 추가하면 된다. 예: "이 파일은 요트다이스용 캐릭터 팩입니다 - 리치마작에서는 쓸 수 없습니다" 처럼, 단순히 "manifest.json이 없습니다"보다 **어느 게임 파일인지까지 구체적으로 말해주는 것**을 권한다(이 저장소가 이미 "확장자만 보고 죽은 파일로 오판하지 말라"는 교훈을 가지고 있는 것과 같은 맥락 — 사용자에게도 애매한 에러보다 원인을 정확히 짚어주는 메시지가 낫다).

### VOICE_EVENTS 구조가 게임별로 교체 가능한가

**그렇다.** `game_events.gd`의 `VOICE_EVENTS`는 배열 안에 `{"key", "label", "description", "frequency", "recommended_label", "recommended_max_sec"}` Dictionary를 나열하는 것뿐이고, 이 배열을 읽어서 UI 행을 만드는 쪽(`voice_mapping_panel.gd`, 확인 결과 조사 1에서 다루지 않았지만 기존 CLAUDE.md 기록상 "테이블을 그대로 순회해 행을 자동 생성"한다고 명시돼 있음)도 테이블 내용에 전혀 의존하지 않는다. 즉 **새 프로젝트에서 이 파일의 구조(스키마 + `Common` 네임스페이스 관례)를 그대로 베끼고, 내용만 마작 이벤트(`Mahjong := {RIICHI, TSUMO, RON, YAKUMAN, ...}`)로 채우면 캐릭터 편집 화면 코드를 한 줄도 안 고쳐도 새 이벤트 목록이 자동으로 반영된다.** 이게 이 저장소에서 "게임을 갈아끼워도 되는 지점"이 가장 깨끗하게 분리된 사례다.

---

## 조사 4 — 저장소 구성 제안

혼자 만드는 취미 프로젝트이고, 요트다이스가 이미 Render(서버)+GitHub Pages(클라이언트)로 실제 배포되어 지인들이 쓰고 있다는 점을 전제로 판단했다.

### (a) 이 저장소 안에 추가

- **장점**: 파일 이동/복사가 필요 없다. 두 게임이 정말 코드를 대량 공유하게 되면(예: 캐릭터 팩 포맷을 억지로 통일) 한 곳만 고치면 된다.
- **단점**: `project.godot`이 하나뿐이라 두 게임이 같은 Godot 프로젝트/같은 export 설정/같은 Docker 이미지를 억지로 공유해야 한다. 이미 실제 서비스 중인 요트다이스를 건드리다 실수로 배포를 망가뜨릴 위험이 항상 같이 따라다닌다(예: 마작 작업 중 `project.godot`의 autoload를 잘못 건드리면 요트다이스 서버도 같이 죽는다). CLAUDE.md/문서도 두 게임 얘기가 뒤섞여서 나중에 "이 규칙이 어느 게임 얘기였는지" 헷갈리기 쉽다. **가장 권하지 않는 안.**

### (b) 별도 저장소로 시작하고, 공통 부분은 복사

- **장점**: 요트다이스 서비스와 완전히 격리된다 — 마작 개발 중 무슨 실수를 해도 이미 돌아가는 서비스에 영향이 없다. 조사 1에서 A로 분류한 파일들(약 15~20개 — asset_loader/character_library/character_profile/character_limits/character_portrait/reconnect_backoff/session_store/secure_random/room_manager 골격/protocol.gd 골격/game_client.gd 골격/Dockerfile 계열/build_stamp/export 프리셋 구조/test_runner)을 그대로 복사해서 시작점으로 삼을 수 있다. Godot 프로젝트 자체가 완전히 독립적이라 마작 전용 `project.godot`/autoload 구성을 자유롭게 바꿀 수 있다.
- **단점**: 나중에 한쪽에서 발견한 버그(예: WebSocket 버퍼 크기 교훈)를 다른 쪽에도 반영하려면 손으로 다시 옮겨야 한다.
- **판단**: 이 단점은 이 프로젝트 규모에서는 크지 않다 — 지금까지 발견된 굵직한 네트워크 버그들(버퍼 오버플로우, 청크 유실, ready 중복 등)은 전부 "상수 값 하나 또는 함수 하나"짜리 교훈이라, 발견 시점에 한 번 수동으로 옮기는 비용이 "공유 라이브러리를 만들고 버전을 관리하는" 비용보다 훨씬 싸다.

### (c) 공통 부분을 별도 라이브러리로 분리하고 양쪽에서 참조

- **장점**: 이론적으로 가장 "깨끗한" 구조 — 버그 수정이 자동으로 양쪽에 반영된다.
- **단점**: Godot에는 성숙한 패키지 매니저가 없다(addons/를 git submodule이나 수동 복사로 공유하는 정도) - 결국 "라이브러리를 갱신할 때마다 양쪽 프로젝트에서 다시 받아서 테스트한다"는 절차가 필요한데, 이건 사실상 (b)의 "발견 시 수동으로 옮긴다"와 실질적인 노력 차이가 크지 않으면서 **버전 관리라는 새로운 관리 부담**(어느 버전을 쓰는지, 라이브러리 쪽 변경이 다른 프로젝트를 깨뜨리지 않는지)만 추가된다. 혼자 만드는 프로젝트 두 개 사이에 이 정도 인프라를 유지하는 건 과한 투자로 보인다.
- **판단**: 두 프로젝트가 장기간 병행 개발되며 공유 코드가 계속 늘어난다면 그때 가서 재검토할 수 있지만, **지금 시점에는 권하지 않는다.**

### 확정: **(b)**

새 저장소를 만들고, 조사 1에서 A로 분류한 파일들을 복사해서 시작점으로 삼는다. B로 분류한 파일들은 복사한 뒤 적극적으로 고쳐 쓴다(빈 파일에서 시작하는 것보다 훨씬 빠르다). C로 분류한 파일(GameState, Main.gd의 점수판 부분, 요트다이스 전용 시그널 등)은 참고만 하고 새로 짠다.

**결정 이유(확정)**: 요트다이스는 이미 Render+GitHub Pages로 실제 운영 중이다. (c)처럼 공통 부분을 별도 라이브러리로 묶어 양쪽이 참조하게 하면, 마작 쪽 작업(버그가 있을 수 있는 새 코드) 중의 실수가 라이브러리를 통해 이미 살아 있는 요트다이스 서비스에 그대로 번질 위험이 생긴다. (b)처럼 완전히 분리된 별도 저장소로 시작하면 이 위험 자체가 구조적으로 없어진다 - 마작 저장소에서 무슨 실수를 해도 요트다이스는 전혀 영향받지 않는다.

---

## 요약 — 다음 프로젝트를 시작할 때 순서 제안

1. **먼저 설계할 것(코드보다 문서가 먼저 필요한 부분)**: 조사 2의 세 가지(비공개 정보 필터링 구조, 국/판을 감싸는 Match 계층, 반응/콜 턴 구조)는 전부 이 저장소에 유사 사례가 없는 새 설계다 — 파일을 복사하기 전에 이 세 가지를 문서로 먼저 확정하는 걸 권한다.
2. **그대로 복사해서 바로 쓸 것(A)**: 배포 인프라 전체(Dockerfile/nginx/entrypoint/build_stamp/export 프리셋), `asset_loader.gd`, 캐릭터 팩 저장소(`character_library.gd`/`character_profile.gd`/`character_limits.gd`/`character_portrait.gd`), 네트워크 기반(`reconnect_backoff.gd`/`session_store.gd`/`secure_random.gd`/`room_manager.gd` 골격/protocol.gd의 버퍼·핑·재접속 상수), 테스트 러너.
3. **복사 후 적극적으로 고쳐 쓸 것(B)**: `room.gd`의 상태 기계, `game_client.gd`/`server_main.gd`의 로비·팩 전송 부분, `VoiceBank`의 조정 엔진, `LocalGameController`/`OnlineGameController`의 덕타이핑 뼈대, `Main.gd`의 화면 전환·캐릭터 연출 부분(점수판/입력 부분은 제외).
4. **참고만 하고 새로 짤 것(C)**: `GameState`(마작 규칙 엔진 전체), `Main.gd`의 점수판/주사위 UI, `GameEvents`의 시그널 목록(단, `Common` 네임스페이스 관례와 `VOICE_EVENTS` 테이블 스키마는 그대로 베낀다).
5. 캐릭터 팩은 호환 안 되게(확장자 + `game` 식별자 필드), 하지만 스키마/검증 로직은 그대로.
