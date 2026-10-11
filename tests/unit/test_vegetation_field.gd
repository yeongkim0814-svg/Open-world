extends TestCase
## VegetationField — 블록 스트리밍·해제·근처 충돌 (합성 fixture, 테스트 트리에 붙여 실행)

const L := VegContext.Layer
static var _cat: VegCatalog


func _catalog() -> VegCatalog:
	if _cat == null:
		_cat = VegCatalog.new()
	return _cat


func _make(reach := {}) -> VegetationField:
	var f := VegetationField.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(f)
	f.setup(VegFixture.bare_context(), _catalog())
	for k in reach:
		f.set_reach(k, reach[k])
	return f


func _run(f: VegetationField, max_steps := 400) -> void:
	var n := 0
	while f.busy() and n < max_steps:
		f.step(50.0)
		n += 1


func _block_center(layer: int, k: Vector2i) -> Vector2:
	var s: float = VegPlacement.BLOCK[layer]
	return Vector2((k.x + 0.5) * s, (k.y + 0.5) * s)


func test_streams_around_center():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	f.update_center(Vector3(10, 0, 5))
	_run(f)
	var keys := f.block_keys(L.GRASS)
	assert_true(keys.size() > 10, "풀 블록이 만들어져야 함: %d" % keys.size())
	var lim := 55.0 + 16.0 * 0.7072
	for k in keys:
		assert_true(_block_center(L.GRASS, k).distance_to(Vector2(10, 5)) <= lim + 0.01, "범위 밖 풀 블록 %s" % str(k))
	assert_true(f.stats()["instances"] > 0, "인스턴스가 있어야 함")
	f.free()


func test_releases_far_blocks():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	assert_true(f.block_keys(L.GRASS).size() > 0)
	f.update_center(Vector3(500, 0, 0))
	for k in f.block_keys(L.GRASS):
		assert_true(_block_center(L.GRASS, k).x > 400.0, "먼 블록이 남음 %s" % str(k))
	# 새 블록은 가까운 것부터: 첫 step 뒤 만들어진 블록이 가장 가까운 후보
	f.step(0.0)
	var keys := f.block_keys(L.GRASS)
	assert_eq(keys.size(), 1, "예산 0 이어도 한 블록은 만든다")
	var d0 := _block_center(L.GRASS, keys[0]).distance_to(Vector2(500, 0))
	assert_true(d0 < 16.0, "가장 가까운 블록부터: %f" % d0)
	f.free()


func test_step_budget_stops_new_blocks():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	f.update_center(Vector3(0, 0, 0))
	var before: int = f.stats()["pending"]
	f.step(0.0)
	assert_eq(f.stats()["pending"], before - 1, "예산 소진 뒤에는 새 블록을 시작하지 않는다")
	f.free()


func test_collision_only_near():
	var f := _make({L.GRASS: 0.0, L.SHRUB: 0.0, L.TREE: 130.0, L.ROCK: 130.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	assert_true(f.stats()["collision_blocks"] > 0, "근처 충돌 블록이 있어야 함")
	for e in f.collision_block_keys():
		var layer: int = e[0]
		var k: Vector2i = e[1]
		var lim := 48.0 + 128.0 * 0.7072
		assert_true(_block_center(layer, k).length() <= lim + 0.01, "먼 충돌 블록 %s" % str(k))
	f.update_center(Vector3(400, 0, 0))
	assert_eq(f.stats()["collision_blocks"], 0, "멀어지면 충돌 해제")
	f.free()


func test_no_climb_group():
	var f := _make({L.GRASS: 0.0, L.SHRUB: 0.0, L.TREE: 130.0, L.ROCK: 0.0})
	f.update_center(Vector3(20, 0, 0))
	_run(f)
	var n := 0
	for b in f.find_children("*", "StaticBody3D", true, false):
		n += 1
		assert_true(b.is_in_group("no_climb"), "나무 충돌체 그룹")
	assert_true(n > 0, "나무 충돌체가 no_climb 그룹이어야 함")
	f.free()


func test_multimesh_setup():
	var f := _make({L.TREE: 130.0, L.ROCK: 0.0, L.SHRUB: 0.0, L.GRASS: 0.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	var found_lod0 := false
	var found_lod1 := false
	for mmi in f.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		assert_true(mm.use_colors and mm.use_custom_data)
		assert_true(mm.instance_count > 0)
		# 헤드리스(dummy 렌더러)는 인스턴스 색·AABB 를 저장하지 않아 읽어 검증할 수 없다
		if mmi.visibility_range_end == 260.0:
			found_lod0 = true
			assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		if mmi.visibility_range_begin == 240.0 and mmi.visibility_range_end == 700.0:
			found_lod1 = true
			assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_true(found_lod0 and found_lod1, "나무 LOD0/LOD1 인스턴스")
	f.free()


func test_water_nodes_reread():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	var w := Water.new()
	w.size = Vector3(400, 200, 400)   # 수면 y = 100 → 지형(10 안팎)이 전부 잠긴다
	var reads := [0]
	f.water_source = func():
		reads[0] += 1
		return [w]
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	assert_eq(f.stats()["instances"], 0, "물에 잠긴 곳엔 풀이 없어야 함")
	assert_eq(reads[0], f.stats()["blocks"], "블록마다 물 노드를 다시 읽는다")
	w.free()
	f.free()
