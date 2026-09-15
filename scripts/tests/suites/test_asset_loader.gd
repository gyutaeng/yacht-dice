extends RefCounted

# AssetLoader의 디코딩 캐시(CacheState)를 검증한다. 원래는 항목 개수(64개)만
# 상한이었는데, 캐시가 들고 있는 게 원본 압축 바이트가 아니라 디코딩된
# Texture2D/AudioStream이라(2048x2048 RGBA 한 장만 16MB) 실제 메모리와 안
# 맞았다 - 그래서 추정 메모리 총합 상한을 추가했다. 이 스위트는 그 관계를
# 회귀 검증한다.


func run(r) -> void:
	r.begin_suite("AssetLoader 디코딩 캐시")

	_test_cache_state_evicts_by_entry_count(r)
	_test_cache_state_evicts_by_byte_total(r)
	_test_cache_state_lru_order(r)
	_test_real_image_cache_hit_returns_same_instance(r)
	_test_get_cache_stats_reflects_loaded_image(r)


## CacheState는 AssetLoader 안에 정의된 내부 클래스라 AssetLoader.CacheState로
## 바로 접근할 수 있다 - 실제 상수(150MB 등)와 무관하게 작은 상한으로 로직만
## 따로 검증하기 위해 여기서 직접 인스턴스를 만든다.
func _test_cache_state_evicts_by_entry_count(r) -> void:
	var state = AssetLoader.CacheState.new(2, 1000000)
	state.put("a", "value_a", 10)
	state.put("b", "value_b", 10)
	r.expect_eq("상한 안에서는 전부 유지됨", state.count(), 2)

	state.put("c", "value_c", 10)
	r.expect_eq("개수 상한을 넘으면 가장 오래된 것부터 지움", state.count(), 2)
	r.expect_true("가장 오래된 항목(a)이 지워짐", state.get_cached("a") == null)
	r.expect_true("최근 항목(c)은 남아있음", state.get_cached("c") != null)


func _test_cache_state_evicts_by_byte_total(r) -> void:
	# 개수는 넉넉하지만(상한 10개) 바이트 총합 상한(100)을 넘기는 경우.
	var state = AssetLoader.CacheState.new(10, 100)
	state.put("a", "value_a", 60)
	state.put("b", "value_b", 60)
	r.expect_eq("바이트 총합이 상한을 넘으면 개수와 무관하게 지움", state.count(), 1)
	r.expect_true("먼저 넣은 게(a) 지워짐", state.get_cached("a") == null)
	r.expect_eq("총합이 최신 항목 크기로 줄어듦", state.total_bytes(), 60)


func _test_cache_state_lru_order(r) -> void:
	var state = AssetLoader.CacheState.new(2, 1000000)
	state.put("a", "value_a", 10)
	state.put("b", "value_b", 10)
	state.get_cached("a")  # a를 조회해서 "최근 사용"으로 만든다.
	state.put("c", "value_c", 10)  # 상한 초과 - 가장 오래된 걸 지워야 하는데, 이제는 b여야 한다.
	r.expect_true("조회해서 최근으로 옮겨진 항목(a)은 안 지워짐", state.get_cached("a") != null)
	r.expect_true("조회 안 한 항목(b)이 지워짐", state.get_cached("b") == null)


func _test_real_image_cache_hit_returns_same_instance(r) -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var bytes := image.save_png_to_buffer()

	var first := AssetLoader.load_texture_from_bytes(bytes)
	var second := AssetLoader.load_texture_from_bytes(bytes)
	r.expect_true("같은 바이트를 다시 불러오면 캐시에서 같은 인스턴스를 돌려줌", first == second)


func _test_get_cache_stats_reflects_loaded_image(r) -> void:
	var image := Image.create(10, 10, false, Image.FORMAT_RGB8)
	var bytes := image.save_png_to_buffer()
	AssetLoader.load_texture_from_bytes(bytes)

	var stats := AssetLoader.get_cache_stats()
	r.expect_true("이미지를 하나 이상 불러오면 텍스처 캐시 항목 수가 0보다 큼", stats["texture_count"] > 0)
	r.expect_true("텍스처 캐시 바이트 총합도 0보다 큼", stats["texture_bytes"] > 0)
