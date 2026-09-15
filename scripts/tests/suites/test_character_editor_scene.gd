extends RefCounted

# character_editor.tscn이 실제로 인스턴스화되어 _ready()를 오류 없이
# 통과하는지만 확인하는 스모크 테스트. 1-7에서 내보내기/가져오기 버튼과
# 다이얼로그를 추가하면서 @onready 경로를 잘못 적으면(노드 이름 오타 등)
# 이 테스트가 즉시 걸린다 - 실제 클릭까지는 확인 못 하지만 "씬이 아예
# 안 열림" 사고는 막는다.


func run(r) -> void:
	r.begin_suite("CharacterEditor 씬 로딩 스모크 테스트")

	# test_runner가 아직 자기 자신의 _ready() 안에 있어서 get_tree().root가
	# "자식 설정 중"으로 잡혀있다 - 한 프레임 기다려야 add_child()가 통과한다.
	await Engine.get_main_loop().process_frame

	var scene: PackedScene = load("res://scenes/character_editor/character_editor.tscn")
	var instance: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(instance)
	await Engine.get_main_loop().process_frame  # _ready()가 실행되어 @onready 노드들이 채워지도록 기다린다.

	r.expect_true("씬이 오류 없이 인스턴스화되고 트리에 들어감", is_instance_valid(instance))
	r.expect_true("현재 캐릭터가 없을 땐 내보내기 버튼이 비활성화됨", instance._export_button.disabled)

	instance.get_parent().remove_child(instance)
	instance.free()
