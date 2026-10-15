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


## BotW 비율: 카탈로그 변형(시드 11·18·25)마다 활엽수 평균 키 10~14 m, 가장 낮은 잎 ≥ 3 m (숲 안 시야), LOD1 도 같다.
## 덤불은 그대로 (키 < 2 m).
func test_broadleaf_botw_scale():
	for kind in [TreeGen.Kind.ROUND, TreeGen.Kind.COLUMN, TreeGen.Kind.SPREAD]:
		var sum := 0.0
		for v in 3:
			var sd := VegCatalog.TREE_SEED_BASE + v * 7
			for lod in 2:
				var m := TreeGen.build(sd, kind, lod)
				var leaf: PackedVector3Array = m.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
				var lo := INF
				for p in leaf:
					lo = minf(lo, p.y)
				assert_true(lo >= 3.0, "종류 %d 시드 %d lod%d 가장 낮은 잎 %.2f m < 3" % [kind, sd, lod, lo])
			sum += TreeGen.build(sd, kind, 0).get_aabb().size.y
		var avg := sum / 3.0
		assert_true(avg >= 10.0 and avg <= 14.0, "종류 %d 평균 키 %.2f m (10~14)" % [kind, avg])
	for v in 4:
		var h := TreeGen.build(VegCatalog.SHRUB_SEED_BASE + v * 7, TreeGen.Kind.SHRUB).get_aabb().size.y
		assert_true(h < 2.0, "덤불 키 %.2f m" % h)
