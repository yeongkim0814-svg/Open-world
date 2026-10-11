extends TestCase

## 평관형(SPREAD): 결정적이고 폭/키 ≥ 0.9. LOD1: 삼각형 ≤ 40, LOD0 과 키 차 < 15 %.
func test_tree_spread_and_lod1():
	var a := TreeGen.build(3, TreeGen.Kind.SPREAD)
	var b := TreeGen.build(3, TreeGen.Kind.SPREAD)
	assert_eq(a.get_faces().size(), b.get_faces().size(), "같은 seed 는 같은 정점 수")
	for s in 6:
		var bb := TreeGen.build(s, TreeGen.Kind.SPREAD).get_aabb()
		var ratio := minf(bb.size.x, bb.size.z) / bb.size.y
		assert_true(ratio >= 0.9, "평관형 seed %d 폭/키 %.2f < 0.9" % [s, ratio])
	for kind in [TreeGen.Kind.ROUND, TreeGen.Kind.COLUMN, TreeGen.Kind.SPREAD]:
		for s in 6:
			var lo := TreeGen.build(s, kind, 0)
			var hi := TreeGen.build(s, kind, 1)
			var tris: int = hi.get_faces().size() / 3
			assert_true(tris <= 40, "LOD1 종류 %d seed %d 삼각형 %d > 40" % [kind, s, tris])
			assert_eq(hi.get_surface_count(), 2, "LOD1 서피스 2개 (줄기·잎)")
			var h0 := lo.get_aabb().size.y
			var h1 := hi.get_aabb().size.y
			assert_true(absf(h0 - h1) / h0 < 0.15, "LOD 키 차 종류 %d seed %d: %.2f vs %.2f" % [kind, s, h0, h1])
