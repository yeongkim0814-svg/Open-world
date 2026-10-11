extends TestCase
## 바위·구름 생성기 테스트.


func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _tris(m: ArrayMesh) -> int:
	return _verts(m).size() / 3


func test_rock_deterministic() -> void:
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB, RockGen.Kind.PILLAR]:
		assert_eq(_verts(RockGen.build(7, kind)), _verts(RockGen.build(7, kind)), "같은 인자 = 같은 메시")
		assert_true(_verts(RockGen.build(7, kind)) != _verts(RockGen.build(8, kind)), "다른 seed = 다른 메시")


func test_rock_budget() -> void:
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB, RockGen.Kind.PILLAR]:
		for s in 5:
			var n := _tris(RockGen.build(s, kind))
			assert_true(n >= 40 and n <= 200, "kind %d seed %d: %d 삼각형" % [kind, s, n])


func test_rock_normals_outward() -> void:
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB, RockGen.Kind.PILLAR]:
		for s in 3:
			var arrays := RockGen.build(s, kind).surface_get_arrays(0)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var center := Vector3.ZERO
			for p in v:
				center += p
			center /= v.size()
			for i in range(0, v.size(), 3):
				var fc := (v[i] + v[i + 1] + v[i + 2]) / 3.0
				assert_true(nrm[i].dot(fc - center) > 0.0, "kind %d seed %d 면 %d 법선이 안쪽" % [kind, s, i / 3])


func test_rock_colors_in_range() -> void:
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB, RockGen.Kind.PILLAR]:
		var cols: PackedColorArray = RockGen.build(3, kind).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		assert_true(cols.size() > 0)
		for c in cols:
			assert_true(c.r >= 0.8 and c.r <= 1.1 and c.g >= 0.8 and c.g <= 1.1 and c.b >= 0.8 and c.b <= 1.1, "명도 범위 밖 %s" % str(c))
			assert_true(c.a >= 0.4 and c.a <= 1.0, "AO 범위 밖 %f" % c.a)


func test_cloud_budget_and_flat_bottom() -> void:
	for s in 6:
		var v := _verts(CloudGen.build(s))
		var n := v.size() / 3
		assert_true(n >= 100 and n <= 300, "seed %d: %d 삼각형" % [s, n])
		var lo := INF
		var hi := -INF
		for p in v:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var dev := 0.0
		# 최저 정점들: 바닥에서 높이의 5% 이내인 정점은 모두 편차 < 15% (바닥 평면)
		var bottom: Array[float] = []
		for p in v:
			if p.y < lo + 0.05 * (hi - lo):
				bottom.append(p.y)
		assert_true(bottom.size() >= 6, "바닥 정점이 너무 적음")
		for y in bottom:
			dev = maxf(dev, y - lo)
		assert_true(dev < 0.15 * (hi - lo), "바닥이 평평하지 않음")
		assert_eq(v, _verts(CloudGen.build(s)), "결정적")
		var cols: PackedColorArray = CloudGen.build(s).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var gmax := 0.0
		for i in v.size():
			if v[i].y <= lo + 0.001:
				assert_almost(cols[i].g, 0.0, 0.001, "바닥 가중 0")
			gmax = maxf(gmax, cols[i].g)
		assert_true(gmax >= 0.9, "윗면 가중 ≥ 0.9")
