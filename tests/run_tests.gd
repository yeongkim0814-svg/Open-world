extends SceneTree
## 헤드리스 테스트 러너: godot --headless --path . -s tests/run_tests.gd
## tests/unit/test_*.gd 의 test_* 메서드를 메서드마다 새 인스턴스로 실행한다.

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(UNIT_DIR))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load("%s/%s" % [UNIT_DIR, file])
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			var case: TestCase = script.new()
			case.call(name)
			for failure in case._failures:
				failed += 1
				print("FAILED: %s::%s — %s" % [file, name, failure])
	if failed == 0:
		print("ALL PASSED (%d tests)" % total)
		quit(0)
	else:
		print("%d FAILURE(S) in %d tests" % [failed, total])
		quit(1)
