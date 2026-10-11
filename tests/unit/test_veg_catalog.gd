extends TestCase
## VegCatalog — 모든 mesh id 빌드·나무 LOD1 삼각형·바위 충돌 모양·줄기 치수

var _cat := VegCatalog.new()


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return n


func test_all_ids_build():
	var have := _cat.ids()
	for id in VegPlacement.mesh_ids():
		assert_true(have.has(id), "ids() 에 없음: %s" % id)
		assert_true(_cat.mesh(id) != null, "메시 없음: %s" % id)


func test_tree_lod():
	for id in VegPlacement.mesh_ids():
		if id.begins_with("tree_"):
			var m := _cat.mesh(id, 1)
			assert_true(m != null and _tris(m) <= 40, "%s LOD1 삼각형 %d > 40" % [id, _tris(m)])


func test_grass_variants_differ():
	var a = GrassGen.build(GrassGen.Kind.TUFT, 0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b = GrassGen.build(GrassGen.Kind.TUFT, 1).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(a != b, "풀 변형 1 이 변형 0 과 같은 정점")


func test_rock_shape():
	for id in VegPlacement.mesh_ids():
		if id.begins_with("rock_"):
			var s := _cat.rock_shape(id)
			assert_true(s.points.size() >= 8, "%s 점 %d < 8" % [id, s.points.size()])
			assert_true(s == _cat.rock_shape(id), "%s 같은 객체가 아님" % id)


func test_trunk():
	for id in VegPlacement.mesh_ids():
		if id.begins_with("tree_"):
			var t := _cat.trunk(id)
			assert_true(t.x > 0.1, "%s 줄기 반경 %.3f" % [id, t.x])
			assert_true(t.y > 0.8, "%s 줄기 높이 %.3f" % [id, t.y])


func test_tree_leaves_use_instance_tint():
	var m := _cat.mesh("tree_round_0")
	var leaves := m.surface_get_material(1) as ShaderMaterial
	assert_true(leaves.get_shader_parameter("instance_tint") == true, "나무 잎은 개체별 색조를 써야 함")
