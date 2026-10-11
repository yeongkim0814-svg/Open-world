extends TestCase

## 잎 한 장(사각형 = 정점 6개) 단위로 뿌리 폭·끝 폭을 잰다. 꽃 부분(정점색 B > 0.5)은 건너뛴다.
func _leaf_ratios(mesh: ArrayMesh) -> Array:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var out := []
	var i := 0
	while i + 6 <= v.size():
		if c[i].b > 0.5:
			i += 3
			continue
		var pts := []
		for j in 6:
			var p: Vector3 = v[i + j]
			var dup := false
			for q in pts:
				if (q as Vector3).distance_to(p) < 0.0001:
					dup = true
			if not dup:
				pts.append(p)
		pts.sort_custom(func(a: Vector3, b: Vector3): return a.y < b.y)
		var root_w: float = (pts[0] as Vector3).distance_to(pts[1])
		var tip_w: float = (pts[pts.size() - 1] as Vector3).distance_to(pts[pts.size() - 2])
		out.append(tip_w / root_w)
		i += 6
	return out

func test_grass_budget_and_no_spikes():
	for kind in [GrassGen.Kind.TUFT, GrassGen.Kind.BROAD, GrassGen.Kind.FLOWER]:
		var mesh := GrassGen.build(kind)
		var tris: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
		var max_tris: int = 14 if kind == GrassGen.Kind.FLOWER else 10
		assert_true(tris >= 6 and tris <= max_tris, "종류 %d 삼각형 %d" % [kind, tris])
		var ratios: Array = _leaf_ratios(mesh)
		assert_true(ratios.size() >= 3, "잎 3장 이상")
		for r in ratios:
			assert_true(r >= 0.6, "끝/뿌리 폭 %.2f < 0.6 (뾰족함)" % r)

func test_grass_wind_weight_root_zero():
	for kind in [GrassGen.Kind.TUFT, GrassGen.Kind.BROAD, GrassGen.Kind.FLOWER]:
		var arr := GrassGen.build(kind).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var lo := 0
		var hi := 0
		for i in v.size():
			if v[i].y < v[lo].y: lo = i
			if v[i].y > v[hi].y: hi = i
		assert_almost(c[lo].g, 0.0, 0.001, "뿌리 바람 가중 0")
		assert_true(c[hi].g >= 0.9, "꼭대기 바람 가중 %.2f" % c[hi].g)

func test_grass_flower_marked():
	var c: PackedColorArray = GrassGen.build(GrassGen.Kind.FLOWER).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var n := 0
	for col in c:
		if col.b > 0.5:
			n += 1
	assert_true(n >= 3, "꽃 정점(B=1) 존재")
	var c2: PackedColorArray = GrassGen.build(GrassGen.Kind.TUFT).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for col in c2:
		assert_true(col.b < 0.5, "TUFT에 꽃 표시 없음")

func test_tree_budget_and_surfaces():
	for kind in [TreeGen.Kind.ROUND, TreeGen.Kind.COLUMN, TreeGen.Kind.SHRUB]:
		var mesh: ArrayMesh = TreeGen.build(7, kind)
		assert_eq(mesh.get_surface_count(), 2)
		var tris: int = 0
		for s in 2:
			tris += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
		assert_true(tris >= 150 and tris <= 400, "종류 %d 삼각형 %d" % [kind, tris])

func test_tree_deterministic_and_varied():
	var a := TreeGen.build(1, TreeGen.Kind.ROUND)
	var b := TreeGen.build(1, TreeGen.Kind.ROUND)
	assert_eq(a.surface_get_arrays(1)[Mesh.ARRAY_VERTEX], b.surface_get_arrays(1)[Mesh.ARRAY_VERTEX])
	assert_eq(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var h1: float = a.get_aabb().size.y
	var h2: float = TreeGen.build(2, TreeGen.Kind.ROUND).get_aabb().size.y
	assert_true(absf(h1 - h2) / maxf(h1, h2) > 0.05, "높이 차 %.2f vs %.2f" % [h1, h2])
