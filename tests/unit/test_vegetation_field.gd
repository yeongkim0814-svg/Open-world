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
	# 새 블록은 가까운 것부터: 예산 0 이어도 step 마다 한 단위(격자 한 줄)씩 진행해 첫 블록이 완성된다
	var n := 0
	while f.block_keys(L.GRASS).is_empty() and n < 100:
		f.step(0.0)
		n += 1
	var keys := f.block_keys(L.GRASS)
	assert_eq(keys.size(), 1, "예산 0 이어도 진행해 한 블록씩 만든다")
	assert_true(n > 1, "블록 계산은 여러 step 에 나눠진다: %d" % n)
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
	var f := _make({L.TREE: 400.0, L.ROCK: 0.0, L.SHRUB: 0.0, L.GRASS: 0.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	var lod0 := 0
	var lod1 := 0
	var shadow := 0
	var cat := _catalog()
	for mmi in f.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		assert_true(mm.use_colors and mm.use_custom_data)
		assert_true(mm.instance_count > 0)
		# 헤드리스(dummy 렌더러)는 인스턴스 색·AABB 를 저장하지 않아 읽어 검증할 수 없다
		if mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			shadow += 1
		elif mm.mesh == cat.mesh("tree_round_0", 1) or mm.mesh == cat.mesh("tree_column_0", 1) or mm.mesh == cat.mesh("tree_spread_0", 1):
			lod1 += 1
		else:
			lod0 += 1
			assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_true(lod0 > 0 and lod1 > 0, "나무 LOD0/LOD1 인스턴스 %d/%d" % [lod0, lod1])
	assert_true(shadow > 0, "근처 나무 그림자 전용 인스턴스")
	f.free()


## 블록 여러 개가 칸 하나로 모인다: 같은 묶음 MultiMesh 수 ≤ 칸 수 × 메시 종류
func test_cells_merge_blocks():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	var st := f.stats()
	assert_true(st["blocks"] > 16, "풀 블록 %d" % st["blocks"])
	# 풀 칸 64 m → 반경 55 m 안 블록이 걸치는 칸은 최대 3×3 = 9, 메시 종류 8
	assert_true(st["multimeshes"] <= 9 * 8, "MultiMesh %d" % st["multimeshes"])
	assert_true(st["multimeshes"] < st["blocks"], "칸으로 모아야 함: mm %d, 블록 %d" % [st["multimeshes"], st["blocks"]])
	f.free()


## 반경 가장자리에서 조금 흔들려도 블록을 지웠다 다시 만들지 않는다
func test_free_hysteresis():
	var f := _make({L.TREE: 0.0, L.ROCK: 0.0, L.SHRUB: 0.0})
	f.update_center(Vector3(0, 0, 0))
	_run(f)
	var before := f.block_keys(L.GRASS).size()
	f.update_center(Vector3(5, 0, 0))
	_run(f)
	f.update_center(Vector3(0, 0, 0))
	var kept := f.block_keys(L.GRASS).size()
	assert_true(kept >= before, "되돌아왔을 때 블록이 지워져 있음: %d < %d" % [kept, before])
	assert_eq(f.stats()["pending"], 0, "다시 만들 블록이 없어야 함")
	f.free()


## setup 두 번: 물 판정이 자기 자신을 감싸 무한 재귀하지 않는다
func test_setup_twice_no_recursive_water():
	var f := VegetationField.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(f)
	var ctx := VegFixture.bare_context()
	f.setup(ctx, _catalog())
	f.setup(ctx, _catalog())
	f.water_source = func(): return []
	var lvl := float(ctx.get_water().call(0.0, 0.0))
	assert_eq(lvl, -INF, "물 없음")
	f.free()


func test_trunk_shapes_shared():
	var f := _make({L.GRASS: 0.0, L.SHRUB: 0.0, L.TREE: 130.0, L.ROCK: 0.0})
	f.update_center(Vector3(20, 0, 0))
	_run(f)
	var shapes := {}
	var n := 0
	for cs in f.find_children("*", "CollisionShape3D", true, false):
		n += 1
		shapes[cs.shape] = true
	assert_true(n > 0)
	assert_true(shapes.size() <= n, "모양 %d / 충돌 %d" % [shapes.size(), n])
	# 같은 (id, 크기 구간) = 같은 모양 객체
	assert_true(f._trunk_shape("tree_round_0", 1.0) == f._trunk_shape("tree_round_0", 1.01), "크기 구간 안에서 공유")
	assert_true(f._trunk_shape("tree_round_0", 1.0) != f._trunk_shape("tree_round_0", 1.2), "다른 구간은 다른 모양")
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
