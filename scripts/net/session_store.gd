class_name SessionStore
extends RefCounted

# 재접속 토큰을 user://에 저장한다(docs/multiplayer.md §6 "클라이언트 쪽
# 재접속 정보 저장"). 메모리에만 있으면 웹에서 가장 흔한 복구 동작인
# 새로고침(F5)이 토큰을 지워버리므로, 1-1에서 확립한 방식 그대로
# FileAccess로 user:// 파일을 직접 읽고 쓴다.
#
# 이번 단계(2-3)는 발급과 저장까지만 한다 - 실제 재접속 매칭(join_room에
# 이 토큰을 실어 보내 기존 슬롯을 되찾는 처리)은 서버에 아직 없다(2-6).

const SESSION_PATH := "user://session.json"


## 저장이 막힌 환경(시크릿 모드 등)에서도 게임 자체는 평소대로 진행되어야
## 한다(1-6/1-7과 같은 원칙) - 실패해도 push_warning만 남기고 조용히
## 넘어간다. 사용자가 만든 콘텐츠가 아니라 편의 기능이라 경고 다이얼로그도
## 띄우지 않는다.
static func save(code: String, reconnect_token: String, player_index: int) -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SessionStore.save: %s를 열 수 없음 - %s" % [SESSION_PATH, error_string(FileAccess.get_open_error())])
		return

	file.store_string(JSON.stringify({
		"code": code,
		"reconnect_token": reconnect_token,
		"player_index": player_index,
		"saved_at": Time.get_datetime_string_from_system(),
	}))
	file.close()


## 저장된 세션이 없거나 형식이 깨졌으면 null. 있으면
## {code, reconnect_token, player_index, saved_at} Dictionary.
static func load() -> Variant:
	if not FileAccess.file_exists(SESSION_PATH):
		return null

	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if file == null:
		return null

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	if not (parsed.has("code") and parsed.has("reconnect_token") and parsed.has("player_index")):
		return null
	return parsed


static func clear() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
