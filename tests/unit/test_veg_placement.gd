extends TestCase
## VegPlacement — 결정성·제외·밀도·간격·다양성·바위 묻힘·가장자리 (합성 지도는 veg_fixture.gd)

const L := VegContext.Layer
const ALL_LAYERS := [L.GRASS, L.SHRUB, L.TREE, L.ROCK]


func _keys_around(layer: int) -> Array:
	# 지도(128 m)를 덮는 블록 키들
	var b: float = VegPlacement.BLOCK[layer]
	var lo := int(floor(-64.0 / b)); var hi := int(floor(64.0 / b))
	var out := []
	for kz in range(lo, hi + 1):
		for kx in range(lo, hi + 1):
			out.append(Vector2i(kx, kz))
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["mesh"] != b[i]["mesh"] or not a[i]["xform"].is_equal_approx(b[i]["xform"]) \
				or a[i]["custom"] != b[i]["custom"] or a[i]["size"] != b[i]["size"]:
			return false
	return true


func test_deterministic():
	var c := VegFixture.bare_context()
	for layer in ALL_LAYERS:
		var k := Vector2i(-1, -1)
		var a := VegPlacement.block(c, layer, k, 1337)
		var b := VegPlacement.block(c, layer, k, 1337)
		assert_true(a.size() > 0, "층 %d 블록이 비었음" % layer)
		assert_true(_same(a, b), "층 %d 같은 키 두 번" % layer)
		var d := VegPlacement.block(c, layer, k, 99)
		assert_false(_same(a, d), "층 %d world_seed 가 다르면 달라야" % layer)


func test_exclusions_respected():
	var c := VegFixture.context()   # 기본 표식·길 포함
	var total := 0
	for layer in ALL_LAYERS:
		for k in _keys_around(layer):
			for it in VegPlacement.block(c, layer, k):
				var p: Vector3 = it["xform"].origin
				total += 1
				assert_false(c.excluded(layer, p.x, p.z), "층 %d (%.1f, %.1f) 제외 지역" % [layer, p.x, p.z])
	assert_true(total > 100, "개체가 너무 적음 %d" % total)


func test_tree_density_forest_vs_meadow():
	var c := VegFixture.bare_context()
	var forest := 0; var meadow := 0
	for s in range(1, 6):
		forest += VegPlacement.block(c, L.TREE, Vector2i(0, -1), s).size()
		meadow += VegPlacement.block(c, L.TREE, Vector2i(-1, -1), s).size()
	print("  나무 5시드 합: 숲 %d / 초원 %d" % [forest, meadow])
	assert_true(forest > 0 and forest > meadow * 5, "숲 %d vs 초원 %d" % [forest, meadow])


func test_tree_slope_and_spacing():
	var c := VegFixture.steep_context()
	var n := 0
	for k in [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
		var items := VegPlacement.block(c, L.TREE, k)
		for i in items.size():
			var p: Vector3 = items[i]["xform"].origin
			n += 1
			assert_true(c.slope_ny(p.x, p.z) >= 0.77, "나무 경사 ny %.3f" % c.slope_ny(p.x, p.z))
			for j in range(i + 1, items.size()):
				var q: Vector3 = items[j]["xform"].origin
				assert_true(Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) >= 4.0 - 0.001, "나무 간격")
	assert_true(n > 10, "나무 수 %d" % n)


func test_variety():
	var c := VegFixture.bare_context()
	var pairs := 0; var dup := 0
	for s in range(1, 4):
		for k in [Vector2i(0, -1), Vector2i(-1, -1)]:
			var items := VegPlacement.block(c, L.TREE, k, s)
			for i in items.size():
				var best := -1; var bd := 1e18
				var pi: Vector3 = items[i]["xform"].origin
				for j in items.size():
					if j == i:
						continue
					var d: float = pi.distance_squared_to(items[j]["xform"].origin)
					if d < bd:
						bd = d; best = j
				if best < 0:
					continue
				pairs += 1
				if items[i]["mesh"] == items[best]["mesh"] and absf(items[i]["size"] - items[best]["size"]) < 0.05:
					dup += 1
	assert_true(pairs > 20, "나무 쌍 %d" % pairs)
	assert_true(float(dup) / maxf(pairs, 1) < 0.1, "나무 중복 %d/%d" % [dup, pairs])
	# 풀: 블록마다 서로 다른 종(GrassGen 종류) 수
	var multi := 0; var blocks := 0
	for kz in range(-4, 0):
		for kx in range(-4, 4):
			var items := VegPlacement.block(c, L.GRASS, Vector2i(kx, kz))
			if items.size() < 20:
				continue
			var kinds := {}
			for it in items:
				kinds[String(it["mesh"]).get_slice("_", 1)] = true
			blocks += 1
			if kinds.size() >= 2:
				multi += 1
	assert_true(blocks > 10, "풀 블록 %d" % blocks)
	assert_true(float(multi) / maxf(blocks, 1) > 0.6, "풀 종 다양 %d/%d" % [multi, blocks])


func test_rock_not_floating():
	var c := VegFixture.steep_context()
	var n := 0
	for k in [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
		for it in VegPlacement.block(c, L.ROCK, k):
			var p: Vector3 = it["xform"].origin
			var foot: float = it["size"] * 0.4
			var low := c.ground_y(p.x, p.z, foot)
			n += 1
			assert_true(p.y <= low + 0.01, "바위 뜸 y %.2f > %.2f" % [p.y, low])
	assert_true(n > 10, "바위 수 %d" % n)


func test_edge_block():
	var c := VegFixture.context()
	for layer in ALL_LAYERS:
		for k in [Vector2i(-50, -50), Vector2i(50, 50), Vector2i(-1, 40), Vector2i(0, 0)]:
			var items := VegPlacement.block(c, layer, k)
			assert_true(items is Array)


func test_block_timing():
	# 블록 하나 계산 시간 (캐시가 데워진 뒤, 서로 다른 블록·시드 평균/최대). 경사 지도 = 바위 포함 최악 쪽
	for ctx_name in ["평탄", "경사"]:
		var c := VegFixture.bare_context() if ctx_name == "평탄" else VegFixture.steep_context()
		for layer in ALL_LAYERS:
			var keys := []
			var b: float = VegPlacement.BLOCK[layer]
			for kz in range(-4, 0):
				for kx in range(-4, 4):
					keys.append(Vector2i(kx, kz) if layer == L.GRASS else Vector2i(kx % 2, kz % 2 - 1))
			for k in keys:
				VegPlacement.block(c, layer, k, 7)   # 데우기
			var sum := 0.0; var worst := 0.0; var cnt := 0; var items := 0
			for k in keys:
				var t0 := Time.get_ticks_usec()
				var r := VegPlacement.block(c, layer, k, 8)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				sum += ms; worst = maxf(worst, ms); cnt += 1; items += r.size()
			print("  블록 시간 [%s] %s: 평균 %.2f ms, 최대 %.2f ms, 평균 개체 %.0f" % [ctx_name, ["풀", "덤불", "나무", "바위"][layer], sum / cnt, worst, float(items) / cnt])


func test_rock_tilt_within_25_degrees():
	var c := VegFixture.steep_context()
	var n := 0
	var worst := 0.0
	for s in [1, 2, 3]:
		for k in [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
			for it in VegPlacement.block(c, L.ROCK, k, s):
				var up: Vector3 = (it["xform"] as Transform3D).basis.y.normalized()
				var ang := rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))
				worst = maxf(worst, ang)
				n += 1
				assert_true(ang <= 25.0 + 0.05, "바위 기울기 %.2f° > 25°" % ang)
	print("  바위 %d 개 최대 기울기 %.2f°" % [n, worst])
	assert_true(n > 30, "바위 수 %d" % n)


## 빈터/맨땅 문턱: 2048 m 지도 200x200 표본(world_seed 1337)에서 빈터 35 %, 맨땅 25 % 안팎
func _frac_below(kind: String, thr: float) -> float:
	var nz := VegPlacement.noise(kind, 1337)
	var below := 0
	for j in 200:
		for i in 200:
			if nz.get_noise_2d(-1024.0 + (i + 0.5) * 10.24, -1024.0 + (j + 0.5) * 10.24) < thr:
				below += 1
	return below / 40000.0


func test_clearing_fractions():
	var tf := _frac_below("clump_tree", VegPlacement.TREE_CLUMP_BELOW)
	var gf := _frac_below("clump_grass", VegPlacement.GRASS_BARE_BELOW)
	print("  빈터 %.1f %% / 맨땅 %.1f %%" % [tf * 100.0, gf * 100.0])
	assert_true(absf(tf - 0.35) <= 0.04, "숲 빈터 비율 %.3f (목표 0.35±0.04)" % tf)
	assert_true(absf(gf - 0.25) <= 0.04, "맨땅 비율 %.3f (목표 0.25±0.04)" % gf)
