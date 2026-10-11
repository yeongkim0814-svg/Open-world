extends TestCase
## 청크 지형: LOD 선택, 청크 메시, 치마, 충돌 (256m 합성 높이 지도 — 빠르게).
## 256m 지도의 구역은 4×4, 구역 (ix,iz) 원점 = (-128 + 64·ix, -128 + 64·iz).

const SIZE := 256.0
const MIN_H := -16.0
const MAX_H := 90.0


## 부드러운 언덕 합성 지도 (257² RGB8, 16비트 인코딩 R 상위·G 하위).
func _field() -> HeightField:
	var n := 257
	var data := PackedByteArray()
	data.resize(n * n * 3)
	for pz in n:
		for px in n:
			var h := 20.0 + 8.0 * sin(px * 0.08) + 6.0 * cos(pz * 0.06) + 0.02 * px
			var t := (h - MIN_H) / (MAX_H - MIN_H) * 255.0
			var r := int(floor(t))
			var g := int(floor((t - r) * 256.0))
			var i := (pz * n + px) * 3
			data[i] = r
			data[i + 1] = mini(g, 255)
			data[i + 2] = 0
	return HeightField.new(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data), SIZE, MIN_H, MAX_H)


func _terrain(field: HeightField) -> ChunkedTerrain:
	var t := ChunkedTerrain.new()
	t.use_field(field)
	return t


func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func test_step_for_distances():
	assert_eq(TerrainLod.step_for(0.0), 1.0)
	assert_eq(TerrainLod.step_for(95.9), 1.0)
	assert_eq(TerrainLod.step_for(96.0), 2.0)
	assert_eq(TerrainLod.step_for(223.9), 2.0)
	assert_eq(TerrainLod.step_for(224.0), 4.0)
	assert_eq(TerrainLod.step_for(479.9), 4.0)
	assert_eq(TerrainLod.step_for(480.0), 16.0)
	assert_eq(TerrainLod.step_for(5000.0), 16.0)


func test_wanted_covers_world():
	var w := TerrainLod.wanted(Vector2.ZERO, 1024.0)
	assert_eq(w.size(), 256, "16x16 구역")
	assert_true(w.has(Vector2i(0, 0)) and w.has(Vector2i(15, 15)))
	# 원점은 구역 (8,8) 모서리: 인접 4구역 모두 1m
	assert_eq(w[Vector2i(8, 8)], 1.0)
	assert_eq(w[Vector2i(7, 7)], 1.0)
	assert_eq(w[Vector2i(0, 0)], 16.0, "먼 모서리는 16m")


func test_chunk_vertex_count():
	var f := _field()
	var arr := _arrays(ChunkMesh.build(f, Vector2(0, 0), 64.0, 4.0, 8.0))
	var n := 17
	assert_eq(arr[Mesh.ARRAY_VERTEX].size(), n * n + 4 * (n - 1), "17² + 치마 64")
	assert_eq(arr[Mesh.ARRAY_INDEX].size() / 3, 2 * 16 * 16 + 4 * 16 * 2)


func test_chunk_matches_field():
	var f := _field()
	var arr := _arrays(ChunkMesh.build(f, Vector2(-64, 0), 64.0, 4.0, 8.0))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var n := 17
	for i in n * n:
		assert_almost(v[i].y, f.height_at(v[i].x, v[i].z), 0.0001)
		assert_true(nr[i].distance_to(f.normal_at(v[i].x, v[i].z)) < 0.0001)
	assert_almost(v[0].x, -64.0, 0.0001)
	assert_almost(v[0].z, 0.0, 0.0001)
	assert_almost(v[n * n - 1].x, 0.0, 0.0001)
	assert_almost(v[n * n - 1].z, 64.0, 0.0001)


func test_skirt_covers_lod_seam():
	var f := _field()
	var skirt_a := 2.0
	var skirt_b := 8.0
	var a := _arrays(ChunkMesh.build(f, Vector2(-64, 0), 64.0, 1.0, skirt_a))  # 1m, 동쪽 테두리 x=0
	var b := _arrays(ChunkMesh.build(f, Vector2(0, 0), 64.0, 4.0, skirt_b))     # 4m, 서쪽 테두리 x=0
	var va: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var vb: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
	var na := 65
	var nb := 17
	var worst := 0.0
	for iz in na:
		var ha := va[iz * na + (na - 1)].y
		var zb := iz / 4.0
		var j := mini(int(floor(zb)), nb - 2)
		var hb := lerpf(vb[j * nb].y, vb[(j + 1) * nb].y, zb - j)
		var diff := ha - hb
		worst = maxf(worst, absf(diff))
		if diff > 0.0:
			assert_true(diff <= skirt_a, "A가 높음: 치마 %.2f ≥ 차 %.2f" % [skirt_a, diff])
		else:
			assert_true(-diff <= skirt_b, "B가 높음: 치마 %.2f ≥ 차 %.2f" % [skirt_b, -diff])
	# 치마 정점이 실제로 skirt 만큼 내려가 있다 (테두리 순서 0번 = 북서 모서리)
	assert_almost(va[na * na].y, va[0].y - skirt_a, 0.0001)
	assert_almost(vb[nb * nb].y, vb[0].y - skirt_b, 0.0001)
	assert_true(worst > 0.0, "합성 지도에 높이 차가 있어야 의미 있음")


func test_skirt_faces_outward():
	var f := _field()
	var arr := _arrays(ChunkMesh.build(f, Vector2(0, 0), 64.0, 16.0, 32.0))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var c := Vector3(32, 0, 32)
	var grid_tris := 2 * 4 * 4
	for t in range(grid_tris, idx.size() / 3):
		var p0 := v[idx[t * 3]]
		var p1 := v[idx[t * 3 + 1]]
		var p2 := v[idx[t * 3 + 2]]
		var cross := (p1 - p0).cross(p2 - p0)       # Godot 앞면 = 시계 → 바깥 법선의 반대 방향
		var mid := (p0 + p1 + p2) / 3.0
		var out := Vector3(mid.x - c.x, 0, mid.z - c.z)
		assert_true(cross.dot(out) < 0.0, "치마 삼각형 %d 은 바깥을 향함" % t)
	for t in grid_tris:
		var cr := (v[idx[t * 3 + 1]] - v[idx[t * 3]]).cross(v[idx[t * 3 + 2]] - v[idx[t * 3]])
		assert_true(cr.y < 0.0, "격자는 위가 앞면")


func test_nearest_3x3_built_first():
	var t := _terrain(_field())
	var cam := Vector3(10, 0, 10)           # 구역 (2,2)
	var guard := 0
	while t.stats()["chunks"] < 1 and guard < 5000:
		t.step(cam, 0.0)                    # 예산 0 = 프레임당 조각 하나
		guard += 1
	assert_true(t.has_chunk(Vector2i(2, 2)), "카메라 구역 먼저")
	while t.stats()["chunks"] < 9 and guard < 5000:
		t.step(cam, 0.0)
		guard += 1
	assert_eq(t.stats()["chunks"], 9, "3×3 이 끝나기 전엔 다른 구역 없음")
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := Vector2i(2 + dx, 2 + dz)
			assert_true(t.has_chunk(k), "3×3 %s" % k)
			assert_eq(t.chunk_step(k), TerrainLod.step_for(Vector2(cam.x, cam.z).distance_to(TerrainLod.chunk_center(k, SIZE))))
	t.free()


func test_converges_and_budget_slices():
	var t := _terrain(_field())
	var frames := 0
	while frames == 0 or t.stats()["pending"] > 0:
		t.step(Vector3.ZERO, 0.0)
		frames += 1
		if frames > 5000:
			break
	assert_eq(t.stats()["chunks"], 16, "256m = 4×4 구역")
	assert_eq(t.stats()["pending"], 0)
	assert_true(frames >= 16, "예산 0이면 프레임당 최소 조각 하나: %d" % frames)
	assert_true(t.stats()["triangles"] > 0)
	t.free()


func test_sliced_job_equals_build():
	var f := _field()
	var whole := _arrays(ChunkMesh.build(f, Vector2(-64, -64), 64.0, 1.0, 2.0))
	var job := ChunkMesh.Job.new(f, Vector2(-64, -64), 64.0, 1.0, 2.0)
	var slices := 0
	while not job.run(0):                   # 마감 0 = 호출마다 한 행
		slices += 1
	assert_true(slices > 100, "여러 조각으로 나뉨: %d" % slices)
	var sliced := _arrays(job.mesh)
	assert_true(sliced[Mesh.ARRAY_VERTEX] == whole[Mesh.ARRAY_VERTEX])
	assert_true(sliced[Mesh.ARRAY_INDEX] == whole[Mesh.ARRAY_INDEX])


func test_fine_chunk_normals_match_field():
	var f := _field()
	var arr := _arrays(ChunkMesh.build(f, Vector2(0, 0), 64.0, 1.0, 2.0))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var worst := 0.0
	for i in 65 * 65:
		assert_almost(v[i].y, f.height_at(v[i].x, v[i].z), 0.0001)
		worst = maxf(worst, nr[i].distance_to(f.normal_at(v[i].x, v[i].z)))
	assert_true(worst < 0.01, "1m 법선 ≈ normal_at: %f" % worst)


func test_replace_only_when_step_changes():
	var t := _terrain(_field())
	var cam := Vector3(-120, 0, -120)       # 구역 (0,0)
	for i in 200:
		t.step(cam, 50.0)
	assert_eq(t.stats()["pending"], 0)
	var key := Vector2i(0, 0)
	var mesh_before: Mesh = t.chunk_node(key).mesh
	t.step(Vector3(-118, 0, -118), 50.0)
	assert_eq(t.stats()["pending"], 0, "단계 불변이면 대기 없음")
	assert_true(t.chunk_node(key).mesh == mesh_before, "단계가 같으면 메시 유지")
	t.step(Vector3(120, 0, 120), 0.0)       # 반대편으로 이동: (0,0) 은 멀어져 4m
	assert_true(t.stats()["pending"] > 0)
	for i in 300:
		t.step(Vector3(120, 0, 120), 50.0)
	assert_eq(t.chunk_step(key), 4.0)
	assert_true(t.chunk_node(key).mesh != mesh_before)
	assert_eq(t.stats()["chunks"], 16, "교체해도 구역 수 그대로")
	t.free()


func test_far_chunks_no_shadow_and_material():
	var t := ChunkedTerrain.new()
	var mat := StandardMaterial3D.new()
	t.material = mat
	t.use_field(_field())
	for i in 200:
		t.step(Vector3(-120, 0, -120), 50.0)
	var near: MeshInstance3D = t.chunk_node(Vector2i(0, 0))
	var far: MeshInstance3D = t.chunk_node(Vector2i(3, 3))
	assert_eq(t.chunk_step(Vector2i(0, 0)), 1.0)
	assert_eq(t.chunk_step(Vector2i(3, 3)), 4.0)
	assert_eq(near.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(far.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_true(near.material_override == mat and far.material_override == mat)
	t.free()


func test_collision_matches_field():
	var f := _field()
	var t := _terrain(f)
	for i in 200:
		t.step(Vector3(-30, 0, -30), 50.0)    # 구역 (1,1) → 3×3 = (0..2, 0..2)
	var shapes: Dictionary = t.collision_shapes()
	assert_eq(shapes.size(), 9)
	var col: CollisionShape3D = shapes[Vector2i(1, 1)]
	var hm := col.shape as HeightMapShape3D
	assert_eq(hm.map_width, 65)
	assert_eq(hm.map_depth, 65)
	# 노드 중심 = 구역 중심, 표본 간격 1m (스케일 1)
	assert_almost(col.position.x, -32.0, 0.0001)
	assert_almost(col.position.z, -32.0, 0.0001)
	assert_almost(col.scale.x, 1.0)
	for iz in [0, 7, 32, 64]:
		for ix in [0, 13, 32, 64]:
			var wx: float = col.position.x - 32.0 + ix
			var wz: float = col.position.z - 32.0 + iz
			assert_almost(hm.map_data[iz * 65 + ix], f.height_at(wx, wz), 0.001, "표본 (%d,%d)" % [ix, iz])
	t.free()


func test_collision_swaps_on_crossing():
	var t := _terrain(_field())
	for i in 200:
		t.step(Vector3(-30, 0, -30), 50.0)
	assert_true(t.collision_shapes().has(Vector2i(0, 0)))
	for i in 200:
		t.step(Vector3(100, 0, -30), 50.0)    # 구역 (3,1)
	var s: Dictionary = t.collision_shapes()
	assert_false(s.has(Vector2i(0, 0)), "멀어진 구역 충돌 제거")
	assert_true(s.has(Vector2i(3, 1)) and s.has(Vector2i(3, 0)) and s.has(Vector2i(2, 2)))
	assert_eq(s.size(), 6, "월드 가장자리에서 3×2")
	t.free()


## 1km 측정: 깊은 바다 아래 구역(불투명 바다에 가려짐)은 메시를 만들지 않는다 — 그리기 호출 절약.
func test_underwater_chunks_skipped():
	var n := 257
	var data := PackedByteArray()
	data.resize(n * n * 3)
	for pz in n:
		for px in n:
			var h := 10.0 if px < 64 and pz < 64 else -10.0   # 왼쪽 위 구역만 땅
			var tv := (h - MIN_H) / (MAX_H - MIN_H) * 255.0
			var i := (pz * n + px) * 3
			data[i] = int(floor(tv))
			data[i + 1] = mini(int(floor((tv - floor(tv)) * 256.0)), 255)
	var f := HeightField.new(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data), SIZE, MIN_H, MAX_H)
	var t := _terrain(f)
	var frames := 0
	while frames == 0 or t.stats()["pending"] > 0:
		t.step(Vector3.ZERO, 50.0)
		frames += 1
		if frames > 5000:
			break
	assert_true(t.has_chunk(Vector2i(0, 0)), "땅 구역은 만든다")
	assert_false(t.has_chunk(Vector2i(3, 3)), "깊은 바다 구역은 건너뛴다")
	assert_true(t.stats()["chunks"] < 16)
	t.free()

## 최종 리뷰: 실제 구운 지도에서 LOD 이웃 경계 높이 차가 치마 깊이를 넘음(최대 16.7m) → 구역마다 측정한 치마.
## 모든 구역 가장자리에서 1m 높이와 가장 거친(16m) 보간의 차 ≤ 그 구역 치마여야 어떤 이웃 조합에도 틈이 없다.
func test_measured_skirt_covers_baked_map():
	var img := load("res://maps/first_island/baked/height.png") as Image
	var f := HeightField.new(img, 1024.0, -16.0, 90.0)
	var n := TerrainLod.chunks_per_side(1024.0)
	for iz in range(0, n, 3):
		for ix in range(0, n, 3):
			var o := Vector2(-512.0 + ix * 64.0, -512.0 + iz * 64.0)
			var skirt := ChunkMesh.skirt_for(f, o, 64.0)
			for e in 4:
				for k in 65:
					var p := _edge_point(o, e, float(k))
					var a := _edge_point(o, e, floor(k / 16.0) * 16.0)
					var b := _edge_point(o, e, minf(floor(k / 16.0) * 16.0 + 16.0, 64.0))
					var t := fposmod(float(k), 16.0) / 16.0 if k < 64 else 1.0
					var coarse := lerpf(f.height_at(a.x, a.y), f.height_at(b.x, b.y), t)
					assert_true(absf(f.height_at(p.x, p.y) - coarse) <= skirt, "구역 %s 가장자리 %d 틈" % [Vector2i(ix, iz), e])


func _edge_point(o: Vector2, e: int, s: float) -> Vector2:
	match e:
		0: return o + Vector2(s, 0)
		1: return o + Vector2(s, 64)
		2: return o + Vector2(0, s)
		_: return o + Vector2(64, s)


# --- A2: 2km 지도 · 먼 256m 묶음 -----------------------------------------------

const BIG := 2048.0


## 2048m 합성 언덕 지도 (513² 이미지 = 4m 칸). 서쪽 가장자리 띠는 깊은 바다.
func _field_2k() -> HeightField:
	var n := 513
	var data := PackedByteArray()
	data.resize(n * n * 3)
	for pz in n:
		for px in n:
			var h := 25.0 + 14.0 * sin(px * 0.05) + 11.0 * cos(pz * 0.04) + 6.0 * sin((px + pz) * 0.13)
			if px < 100:
				h = -12.0
			var t := (h - MIN_H) / (MAX_H - MIN_H) * 255.0
			var r := int(floor(t))
			var i := (pz * n + px) * 3
			data[i] = r
			data[i + 1] = mini(int((t - r) * 256.0), 255)
	return HeightField.new(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data), BIG, MIN_H, MAX_H)


func _converge(t: ChunkedTerrain, cam: Vector3, limit := 20000) -> int:
	var frames := 0
	while frames == 0 or t.stats()["pending"] > 0:
		t.step(cam, 50.0)
		frames += 1
		if frames > limit:
			break
	return frames


func _mesh_nodes(t: ChunkedTerrain) -> int:
	var c := 0
	for ch in t.get_children():
		if ch is MeshInstance3D:
			c += 1
	return c


func test_far_blocks_reduce_nodes():
	var t := _terrain(_field_2k())
	_converge(t, Vector3(1000, 0, 1000))
	var st := t.stats()
	assert_true(st["blocks"] > 30, "먼 묶음이 많다: %d" % st["blocks"])
	assert_true(_mesh_nodes(t) < 300, "메시 노드 %d < 300" % _mesh_nodes(t))
	assert_eq(_mesh_nodes(t), st["chunks"] + st["blocks"])
	t.free()


## 묶음이 다 덮은 구역엔 개별 구역 노드가 없고, 카메라 주변은 개별로 남는다.
func test_block_replaces_its_chunks():
	var t := _terrain(_field_2k())
	_converge(t, Vector3(1000, 0, 1000))
	assert_true(t.block_keys().size() > 0)
	for b: Vector2i in t.block_keys():
		for dz in 4:
			for dx in 4:
				assert_false(t.has_chunk(Vector2i(b.x * 4 + dx, b.y * 4 + dz)), "묶음 %s 안 구역은 없음" % b)
	assert_true(t.has_chunk(Vector2i(31, 31)), "카메라 구역은 개별")
	assert_false(t.has_block(Vector2i(7, 7)), "카메라 옆 묶음 없음")
	t.free()


## 모든 육지 구역은 개별 노드 또는 묶음 노드로 덮여 있다 (묶음 ↔ 구역 전환 중에도 구멍 없음).
func _holes(t: ChunkedTerrain, n: int, skip: Dictionary) -> int:
	var holes := 0
	for iz in n:
		for ix in n:
			var k := Vector2i(ix, iz)
			if skip.has(k):
				continue
			var inst := t.chunk_node(k)
			var covered := inst != null and inst.visible
			var b := t.block_node(Vector2i(ix / 4, iz / 4))
			if b != null and b.visible:
				covered = true
			if not covered:
				holes += 1
	return holes


func test_block_transitions_leave_no_holes():
	var f := _field_2k()
	var t := _terrain(f)
	var skip := ChunkedTerrain._underwater_chunks(f)
	_converge(t, Vector3(1000, 0, 1000))
	assert_eq(_holes(t, 32, skip), 0, "수렴 후")
	# 카메라를 멀리 옮겨 묶음 ↔ 구역 전환을 프레임 단위(예산 0)로 지켜본다
	var worst := 0
	for path in [Vector3(-200, 0, -200), Vector3(700, 0, 300)]:
		var guard := 0
		t.step(path, 0.0)
		while t.stats()["pending"] > 0 and guard < 20000:
			worst = maxi(worst, _holes(t, 32, skip))
			t.step(path, 0.0)
			guard += 1
		assert_eq(_holes(t, 32, skip), 0, "수렴 후 %s" % path)
	assert_eq(worst, 0, "전환 중 구멍 수")
	t.free()


## 묶음(16m)과 이웃 64m 구역(4m) 경계: 두 메시 테두리의 높이 차를 양쪽 치마 중 낮은 쪽이 덮는다.
func test_block_and_chunk_seam_covered():
	var f := _field_2k()
	var bo := Vector2(0, 0)                                  # 묶음 원점 (256m)
	var b_skirt := ChunkMesh.skirt_for(f, bo, 256.0)
	var c_skirt := ChunkMesh.skirt_for(f, Vector2(-64, 0), 64.0)
	var blk := _arrays(ChunkMesh.build(f, bo, 256.0, 16.0, b_skirt))
	var chk := _arrays(ChunkMesh.build(f, Vector2(-64, 0), 64.0, 4.0, c_skirt))   # 묶음 서쪽 이웃
	var vb: PackedVector3Array = blk[Mesh.ARRAY_VERTEX]
	var vc: PackedVector3Array = chk[Mesh.ARRAY_VERTEX]
	var nb := 17
	var nc := 17
	assert_true(b_skirt >= 6.0 and c_skirt >= 6.0)
	var worst := 0.0
	for iz in range(0, 17):                                  # 이웃 구역 동쪽 테두리 x=0 (z 0..64)
		var zc := vc[iz * nc + (nc - 1)].z
		var hc := vc[iz * nc + (nc - 1)].y
		var zb := zc / 16.0
		var j := mini(int(floor(zb)), nb - 2)
		var hb := lerpf(vb[j * nb].y, vb[(j + 1) * nb].y, zb - j)   # 묶음 서쪽 테두리 (열 0)
		var diff := hc - hb
		worst = maxf(worst, absf(diff))
		if diff > 0.0:
			assert_true(diff <= b_skirt, "구역이 높음: 묶음 치마 %.2f ≥ 차 %.2f" % [b_skirt, diff])
		else:
			assert_true(-diff <= c_skirt, "묶음이 높음: 구역 치마 %.2f ≥ 차 %.2f" % [c_skirt, -diff])
	assert_true(worst > 0.0, "높이 차가 있어야 의미 있음")
	assert_eq(vb.size(), 17 * 17 + 4 * 16)


## 바다만 있는 묶음은 만들지 않는다.
func test_underwater_block_skipped():
	var t := _terrain(_field_2k())
	_converge(t, Vector3(1000, 0, 1000))
	assert_false(t.has_block(Vector2i(0, 3)), "서쪽 가장자리(깊은 바다) 묶음 생략")
	assert_false(t.has_chunk(Vector2i(0, 12)))
	t.free()


func test_meta_json_honoured():
	var dir := "user://_test_meta_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 129
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color8(128, 0, 0))
	img.save_png(dir.path_join("height.png"))
	var fa := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify({"world": 512, "size": 129, "min_h": -20.0, "max_h": 200.0}))
	fa.close()
	var t := ChunkedTerrain.new()
	t.baked_dir = dir
	t.load_map()
	assert_true(t.field != null)
	assert_eq(t.field.world_size, 512.0)
	assert_almost(t.field.height_at(0, 0), -20.0 + 128.0 / 255.0 * 220.0, 0.5)
	_converge(t, Vector3.ZERO)
	assert_eq(t.stats()["chunks"], 64, "512m = 8×8 구역 (카메라 중앙 → 전부 개별)")
	t.step(Vector3(0, 0, 0), 50.0)
	assert_eq(t.collision_shapes().size(), 9)
	t.free()
	# meta 없음 → 1024 / −16 / 90
	var dir2 := "user://_test_nometa_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir2)
	img.save_png(dir2.path_join("height.png"))
	var t2 := ChunkedTerrain.new()
	t2.baked_dir = dir2
	t2.load_map()
	assert_eq(t2.field.world_size, 1024.0)
	assert_almost(t2.field.height_at(0, 0), -16.0 + 128.0 / 255.0 * 106.0, 0.5)
	t2.free()
