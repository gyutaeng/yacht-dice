extends RefCounted

# 여러 테스트 스위트가 공유하는 아주 단순한 assert/집계 도구.
# GUT 같은 애드온이 없어서, 씬 하나로 전체 결과를 콘솔에 찍는 용도로 직접 만들었다.

var total := 0
var passed := 0
var failures: Array[String] = []

var _current_suite := ""


func begin_suite(suite_name: String) -> void:
	_current_suite = suite_name
	print("\n== %s ==" % suite_name)


func expect_eq(description: String, actual, expected) -> void:
	total += 1
	if actual == expected:
		passed += 1
		print("  [PASS] %s" % description)
	else:
		print("  [FAIL] %s (기대값=%s, 실제값=%s)" % [description, str(expected), str(actual)])
		failures.append("[%s] %s (기대값=%s, 실제값=%s)" % [_current_suite, description, str(expected), str(actual)])


func expect_true(description: String, condition: bool) -> void:
	expect_eq(description, condition, true)


func print_summary() -> bool:
	print("\n========================================")
	print("%d개 중 %d개 통과" % [total, passed])
	if failures.is_empty():
		print("모든 테스트 통과.")
	else:
		print("실패한 테스트 %d개:" % failures.size())
		for failure in failures:
			print("  - %s" % failure)
	print("========================================")
	return failures.is_empty()
