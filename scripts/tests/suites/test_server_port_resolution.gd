extends RefCounted

# 2-7(Render 상시 배포) 사전 작업 - `_resolve_port()`의 우선순위를
# "CLI 인자 -> PORT(Render 표준) -> YACHT_DICE_PORT(로컬 개발용) -> 기본값"
# 순으로 바꿨다. Render는 자기가 정한 포트를 PORT 환경변수로 주입하고
# 그 포트를 실제로 듣고 있는지 감시하므로, 이 우선순위가 틀리면 배포가
# 죽은 것으로 처리된다(`docs/deployment_checklist.md` "2-7 사전 조사" §2).
# port_override(테스트 전용 필드)가 항상 최우선이라는 기존 계약은 그대로다.

const YACHT_ENV := "YACHT_DICE_PORT"
const RENDER_ENV := "PORT"


func run(r) -> void:
	r.begin_suite("서버 포트 우선순위(2-7 - PORT 환경변수 추가)")
	_test_defaults_to_8910_with_no_env(r)
	_test_yacht_dice_port_env_used_when_set(r)
	_test_render_port_env_takes_priority_over_yacht_dice_port(r)
	_test_port_override_wins_over_everything(r)
	_test_bind_address_defaults_to_wildcard(r)
	_test_bind_address_override_wins(r)


func _make_server() -> Node:
	var server_script: GDScript = load("res://server_main.gd")
	return server_script.new()


## 테스트가 실제 프로세스 환경변수를 건드리므로, 각 테스트 전후로 반드시
## 원래 값으로 되돌린다 - 안 그러면 이후 테스트나 실제 실행에 영향을 줄 수 있다.
func _clear_env() -> void:
	OS.set_environment(YACHT_ENV, "")
	OS.set_environment(RENDER_ENV, "")


func _test_defaults_to_8910_with_no_env(r) -> void:
	_clear_env()
	var server := _make_server()
	r.expect_eq("아무 환경변수도 없으면 기본값 8910", server._resolve_port(), 8910)
	_clear_env()


func _test_yacht_dice_port_env_used_when_set(r) -> void:
	_clear_env()
	OS.set_environment(YACHT_ENV, "9999")
	var server := _make_server()
	r.expect_eq("YACHT_DICE_PORT만 있으면 그 값을 씀(로컬 개발 경로 유지)", server._resolve_port(), 9999)
	_clear_env()


func _test_render_port_env_takes_priority_over_yacht_dice_port(r) -> void:
	_clear_env()
	OS.set_environment(YACHT_ENV, "9999")
	OS.set_environment(RENDER_ENV, "7777")
	var server := _make_server()
	r.expect_eq("PORT(Render 표준)가 있으면 YACHT_DICE_PORT보다 우선함", server._resolve_port(), 7777)
	_clear_env()


func _test_port_override_wins_over_everything(r) -> void:
	_clear_env()
	OS.set_environment(YACHT_ENV, "9999")
	OS.set_environment(RENDER_ENV, "7777")
	var server := _make_server()
	server.port_override = 12345
	r.expect_eq("port_override(테스트 전용)는 환경변수보다도 항상 우선함", server._resolve_port(), 12345)
	_clear_env()


## 헬스체크 후보 C 후속(실제 배포 사고 - Render 스캐너가 Godot의 내부
## 전용 포트까지 찾아내 찔러봄) - 바인드 주소 기본값은 기존 로컬 개발
## 동작을 그대로 유지해야 하므로 "*"(모든 인터페이스)다. CLI 인자로만
## 바뀌므로(포트처럼 환경변수 경로가 없음) 여기서는 기본값/override만
## 확인한다 - CLI 인자 자체는 test_server_port_resolution.gd의 나머지
## 테스트들과 같은 이유로 이 테스트 스위트의 실제 실행 인자를 못 바꾸므로
## 검증 범위 밖이다.
func _test_bind_address_defaults_to_wildcard(r) -> void:
	var server := _make_server()
	r.expect_eq("CLI 인자/override가 없으면 기본값 \"*\"(로컬 개발 기존 동작 유지)", server._resolve_bind_address(), "*")


func _test_bind_address_override_wins(r) -> void:
	var server := _make_server()
	server.bind_address_override = "127.0.0.1"
	r.expect_eq("bind_address_override(테스트 전용)가 우선함", server._resolve_bind_address(), "127.0.0.1")
