extends TestCase

## 낮은 풀(LOW): 높이 ≤ 0.16, 폭 ≥ 0.3.
func test_grass_low():
	var bb := GrassGen.build(GrassGen.Kind.LOW).get_aabb()
	assert_true(bb.size.y <= 0.16, "LOW 높이 %.3f > 0.16" % bb.size.y)
	assert_true(maxf(bb.size.x, bb.size.z) >= 0.3, "LOW 폭 %.3f < 0.3" % maxf(bb.size.x, bb.size.z))


func _tri_count(m: ArrayMesh) -> int:
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## B2 풀 덩어리(PATCH): 삼각형 ≤ 120, 폭 1.4~3.2 m, 높이 0.5~1.3 m, 결정적.
func test_patch_budget_and_size():
	for v in 6:
		var m := GrassGen.build(GrassGen.Kind.PATCH, v)
		assert_true(_tri_count(m) <= 120, "PATCH 변형 %d 삼각형 %d > 120" % [v, _tri_count(m)])
		var bb := m.get_aabb()
		assert_true(bb.size.x >= 1.4 and bb.size.x <= 3.2, "PATCH x 폭 %.2f" % bb.size.x)
		assert_true(bb.size.z >= 1.4 and bb.size.z <= 3.2, "PATCH z 폭 %.2f" % bb.size.z)
		assert_true(bb.size.y >= 0.5 and bb.size.y <= 1.3, "PATCH 높이 %.2f" % bb.size.y)


func test_patch_deterministic_and_variants():
	for kind in [GrassGen.Kind.PATCH, GrassGen.Kind.FLOWER_PATCH]:
		var a: PackedVector3Array = GrassGen.build(kind, 2).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = GrassGen.build(kind, 2).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var c: PackedVector3Array = GrassGen.build(kind, 3).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq(a, b, "같은 인자 = 같은 메시")
		assert_true(a != c, "변형마다 다른 배치")


## 꽃무리(FLOWER_PATCH): 삼각형 ≤ 200, 지름 2~4 m, 꽃 정점(B=1) 있음.
func test_flower_patch_budget_and_flowers():
	for v in 6:
		var m := GrassGen.build(GrassGen.Kind.FLOWER_PATCH, v)
		assert_true(_tri_count(m) <= 200, "FLOWER_PATCH 삼각형 %d > 200" % _tri_count(m))
		var bb := m.get_aabb()
		var dia := maxf(bb.size.x, bb.size.z)
		assert_true(dia >= 2.0 and dia <= 4.0, "FLOWER_PATCH 지름 %.2f" % dia)
		var cols: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var flowers := 0
		for c in cols:
			if c.b > 0.5:
				flowers += 1
		# 꽃 한 송이 = 삼각형 4개 = 정점 12개, 8~15송이
		assert_true(flowers >= 8 * 12 and flowers <= 15 * 12, "꽃 정점 %d" % flowers)
