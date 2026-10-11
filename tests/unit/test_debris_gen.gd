extends TestCase
## 쓰러진 통나무·그루터기 생성기 (B2 9.1): 삼각형 ≤ 60, 결정적, 바닥이 y=0.


func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_debris_budget_and_determinism():
	for kind in [DebrisGen.Kind.LOG, DebrisGen.Kind.STUMP]:
		for s in 6:
			var m := DebrisGen.build(s, kind)
			assert_true(_verts(m).size() / 3 <= 60, "kind %d seed %d: %d 삼각형" % [kind, s, _verts(m).size() / 3])
			assert_true(_verts(m).size() > 0)
			assert_eq(_verts(m), _verts(DebrisGen.build(s, kind)), "같은 인자 = 같은 메시")
		assert_true(_verts(DebrisGen.build(1, kind)) != _verts(DebrisGen.build(2, kind)), "다른 seed = 다른 메시")


## 통나무: 길이 4~7 m, 지름 0.6~0.9 m, 바닥 y=0. 그루터기: 바닥 y=0, 높이 0.4~0.9 m.
func test_debris_dimensions():
	for s in 6:
		var bb := DebrisGen.build(s, DebrisGen.Kind.LOG).get_aabb()
		var length := maxf(bb.size.x, bb.size.z)
		assert_true(length >= 4.0 and length <= 7.0, "통나무 길이 %.2f" % length)
		assert_true(bb.size.y >= 0.6 and bb.size.y <= 0.95, "통나무 지름(높이) %.2f" % bb.size.y)
		assert_true(absf(bb.position.y) < 0.01, "통나무 바닥 y=0")
		var sb := DebrisGen.build(s, DebrisGen.Kind.STUMP).get_aabb()
		assert_true(sb.size.y >= 0.4 and sb.size.y <= 0.9, "그루터기 높이 %.2f" % sb.size.y)
		assert_true(absf(sb.position.y) < 0.01, "그루터기 바닥 y=0")
