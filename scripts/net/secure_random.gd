class_name SecureRandom
extends RefCounted

# server_main.gd(2-1)에 있던 것을 방 관리 쪽(RoomManager)에서 쓰기 좋은
# 자리로 옮겼다.
#
# 서버 주사위 시드는 예측 가능하면 안 된다 - 이 값을 미리 알면 앞으로 나올
# 주사위를 전부 계산할 수 있어서, "서버가 굴리니까 치팅이 불가능하다"는
# Phase 2의 전제(docs/multiplayer.md §0)가 조작 없이도 무너진다. 그래서
# RandomNumberGenerator.randomize()(시각 기반) 대신, OS 엔트로피를 쓰는
# Crypto.generate_random_bytes()로 시드를 만든다.
#
# 방마다(RoomManager.create_room()이 방을 만들 때마다) 이 함수를 새로
# 호출해서 그 방 전용 RNG를 만든다 - 서버 전체가 RNG 하나를 공유하면 한
# 방에서 본 주사위로 난수 진행 상태를 추론해 다른 방의 결과를 예측할
# 여지가 생기므로, 절대 공유하지 않는다.
#
# 이 클래스는 서버(headless 네이티브 바이너리) 전용이다 -
# docs/multiplayer.md §0에 따라 서버는 절대 Web export로 돌지 않으므로,
# Crypto의 웹 export 동작 여부는 이 경로에서는 따질 필요가 없다. 클라이언트
# 로컬(싱글) 모드는 GameState._init()이 자체적으로 randomize()를 쓰는 기존
# 경로를 그대로 유지한다 - 다른 사람과 겨루는 게 아니라서 시드를 예측당해도
# 치팅 상대가 없다.
static func generate_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(8)
	var seed_value := 0
	for b in bytes:
		seed_value = (seed_value << 8) | b
	return seed_value
