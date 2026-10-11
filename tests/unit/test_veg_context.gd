extends TestCase
## VegContext — 구역·길·표식·물 제외 (합성 지도는 veg_fixture.gd)

func test_zone_and_edge():
	var c := VegFixture.context()
	assert_eq(c.zone_at(-30.0, 10.0), 0)
	assert_eq(c.zone_at(30.0, 10.0), 1)
	assert_true(c.edge_dist_zone(-2.0, 10.0) <= 4.0, "경계 옆 %.1f" % c.edge_dist_zone(-2.0, 10.0))
	assert_almost(c.edge_dist_zone(-30.0, 10.0), 20.0, 0.001, "멀면 max_m")

func test_path_exclusion():
	var c := VegFixture.context()
	assert_true(c.excluded(VegContext.Layer.GRASS, 0.5, 0.0), "길 1 m 옆")
	assert_false(c.excluded(VegContext.Layer.GRASS, 6.0, 0.0), "길 6 m 옆")
	assert_eq(c.path_near(0.5, 0.0, 1.5), 1)
	assert_eq(c.path_near(10.0, 0.0, 1.5), 0)

func test_path_priority_and_radii():
	var p := VegFixture.paths()
	p.set_pixel(100, 30, Color8(4, 0, 0))   # 개천 1 px: x=36, z=-34
	var c := VegContext.new(VegFixture.field(), VegFixture.zones(), p, [], VegFixture.cfg())
	assert_true(c.excluded(VegContext.Layer.GRASS, 36.0, -31.5), "개천 3 m 안")
	assert_false(c.excluded(VegContext.Layer.GRASS, 36.0, -29.0), "개천 3 m 밖")
	p.set_pixel(36, 30, Color8(3, 0, 0))    # 수로 x=-28, z=-34
	c = VegContext.new(VegFixture.field(), VegFixture.zones(), p, [], VegFixture.cfg())
	assert_true(c.excluded(VegContext.Layer.GRASS, -28.0, -32.5), "수로 2 m 안")
	assert_false(c.excluded(VegContext.Layer.GRASS, -28.0, -31.0), "수로 2 m 밖")
	p.set_pixel(65, 30, Color8(4, 0, 0))    # 흙길 옆 개천 → 개천 우선
	c = VegContext.new(VegFixture.field(), VegFixture.zones(), p, [], VegFixture.cfg())
	assert_eq(c.path_near(0.0, -34.0, 1.0), 4)

func test_thin_stream_inner_ring():
	var p := VegFixture.paths()
	p.set_pixel(100, 30, Color8(4, 0, 0))   # 개천 1 px: x=36, z=-34
	var c := VegContext.new(VegFixture.field(), VegFixture.zones(), p, [], VegFixture.cfg())
	assert_true(c.excluded(VegContext.Layer.GRASS, 36.0, -31.0), "1 px 개천 3 m 옆")
	assert_true(c.excluded(VegContext.Layer.GRASS, 34.0, -34.0), "1 px 개천 2 m 옆")

func test_marker_exclusion():
	var c := VegFixture.context()
	for layer in [VegContext.Layer.GRASS, VegContext.Layer.SHRUB, VegContext.Layer.TREE, VegContext.Layer.ROCK]:
		assert_true(c.excluded(layer, -40.0, 0.0), "마을 40 m 안 층 %d" % layer)
		assert_true(c.excluded(layer, 40.0, -40.0 + 14.0), "탑 14 m 안 층 %d" % layer)
	assert_true(c.excluded(VegContext.Layer.TREE, -15.0, 45.0), "산마을 30 m 나무")
	assert_true(c.excluded(VegContext.Layer.ROCK, -15.0, 45.0), "산마을 30 m 바위")
	assert_false(c.excluded(VegContext.Layer.GRASS, -15.0, 45.0), "산마을 30 m 풀 허용")
	assert_false(c.excluded(VegContext.Layer.SHRUB, -15.0, 45.0), "산마을 30 m 덤불 허용")

func test_lake_marker():
	var mk := [{"kind": "lake", "x": 20.0, "z": 0.0, "radius": 10.0, "crest": 12.0}]
	var c := VegContext.new(VegFixture.field(), VegFixture.zones(), VegFixture.paths(), mk, VegFixture.cfg())
	assert_true(c.excluded(VegContext.Layer.TREE, 20.0 + 20.0, 0.0), "반경 10 + 둑 12 안 나무")
	assert_false(c.excluded(VegContext.Layer.TREE, 20.0 + 25.0, 0.0), "밖")
	assert_true(c.excluded(VegContext.Layer.SHRUB, 20.0 + 15.0, 0.0), "둑 위 덤불 제외")
	assert_false(c.excluded(VegContext.Layer.GRASS, 20.0 + 15.0, 0.0), "둑 위 풀 허용")

func test_water_and_sea():
	var c := VegFixture.context()
	assert_true(c.excluded(VegContext.Layer.GRASS, -20.0, 60.0), "높이 < 0.8")
	assert_false(c.excluded(VegContext.Layer.GRASS, 20.0, 10.0), "육지")
	var water := func(x: float, z: float) -> float: return 100.0 if x > 20.0 and x < 30.0 else -INF
	var w := VegFixture.context(water)
	assert_true(w.excluded(VegContext.Layer.GRASS, 25.0, 20.0), "수면 아래")
	assert_false(w.excluded(VegContext.Layer.GRASS, 35.0, 20.0), "수면 밖")

func test_summit_no_trees():
	var c := VegFixture.context()
	assert_true(c.excluded(VegContext.Layer.TREE, -40.0, 10.0), "정상 100 m 나무")
	assert_false(c.excluded(VegContext.Layer.ROCK, -40.0, 10.0), "정상 100 m 바위 허용")
	assert_false(c.excluded(VegContext.Layer.GRASS, -40.0, 10.0), "정상 100 m 풀 허용")

func test_out_of_map_clamped():
	var c := VegFixture.context()
	assert_eq(c.zone_at(VegFixture.WORLD / 2.0 + 50.0, 0.0), 1)
	assert_eq(c.zone_at(-VegFixture.WORLD / 2.0 - 50.0, 0.0), 0)
	assert_eq(c.path_near(500.0, 500.0, 1.5), 0)

func test_ground_y_foot():
	var c := VegFixture.context()
	assert_almost(c.ground_y(20.0, 10.0), 12.0, 0.1)
	assert_almost(c.ground_y(20.0, 10.0, 3.0), 11.7, 0.1, "발 모서리 최솟값")
	assert_true(c.slope_ny(20.0, 10.0) > 0.99)
