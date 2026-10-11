extends TestCase
## 바위 윗면 표시 (B2 9.2): 법선 y > 0.6 인 면의 정점색 B 채널 = 1 (그 밖은 B < 0.95).

const TOP_B := 0.95


func test_top_marked_exactly_on_up_faces():
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB, RockGen.Kind.PILLAR]:
		for s in 4:
			var arrays := RockGen.build(s, kind).surface_get_arrays(0)
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i in nrm.size():
				var up: bool = nrm[i].y > 0.6
				assert_eq(cols[i].b >= TOP_B, up, "kind %d seed %d 정점 %d: 법선 y %.2f B %.2f" % [kind, s, i, nrm[i].y, cols[i].b])


## 윗면 정점 비율 15~60 % (이끼가 점이 아니라 덩어리로 읽히되 몸체를 덮지 않게). 기둥은 옆면이 많아 제외.
func test_top_ratio():
	for kind in [RockGen.Kind.ROUND, RockGen.Kind.SLAB]:
		for s in 8:
			var cols: PackedColorArray = RockGen.build(s, kind).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var n := 0
			for c in cols:
				if c.b >= TOP_B:
					n += 1
			var ratio := float(n) / float(cols.size())
			assert_true(ratio >= 0.15 and ratio <= 0.60, "kind %d seed %d 윗면 비율 %.2f" % [kind, s, ratio])
