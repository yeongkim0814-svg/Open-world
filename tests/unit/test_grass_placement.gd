extends TestCase

## 평지(높이 10m) 8×8m 필드. world_size 8 → x,z ∈ [-4,4].
func _flat(h01 := 0.5) -> HeightField:
	var img := Image.create(9, 9, false, Image.FORMAT_L8)
	img.fill(Color(h01, h01, h01))
	return HeightField.new(img, 8.0, 0.0, 20.0)

## 16m 필드, x>0 쪽이 45° 경사(1m당 1m 상승).
func _half_steep() -> HeightField:
	var img := Image.create(17, 17, false, Image.FORMAT_L8)
	for y in 17:
		for x in 17:
			var wx := float(x) - 8.0
			var h := 6.0 + (maxf(wx, 0.0) * 1.0)
			var v := h / 20.0
			img.set_pixel(x, y, Color(v, v, v))
	return HeightField.new(img, 16.0, 0.0, 20.0)

func test_points_skip_steep_and_water():
	var f := _half_steep()
	var pts := GrassPlacement.points(f, Vector2(-4, -4), 8.0, 6.0, 1)
	assert_true(pts.size() > 0, "평평한 쪽엔 풀이 있어야 함")
	for p in pts:
		assert_true(p.x < 0.6, "경사 칸(x>0.6)에는 점이 없어야 함: %s" % p)
	var flat := _flat()
	var wet := GrassPlacement.points(flat, Vector2(-4, -4), 8.0, 6.0, 1, func(_x, _z): return 15.0)
	assert_eq(wet.size(), 0, "물 아래 칸에는 점 0개")
	var dry := GrassPlacement.points(flat, Vector2(-4, -4), 8.0, 6.0, 1, func(_x, _z): return -INF)
	assert_true(dry.size() > 0)

func test_skips_sand_below_2m():
	var low := _flat(0.05)  # 1 m
	assert_eq(GrassPlacement.points(low, Vector2(-4, -4), 8.0, 6.0, 1).size(), 0)

func test_density_matches():
	var pts := GrassPlacement.points(_flat(), Vector2(-4, -4), 8.0, 6.0, 7)
	assert_true(absf(pts.size() - 384.0) <= 38.4, "384±10%% (실제 %d)" % pts.size())

func test_deterministic_with_seed():
	var f := _flat()
	var a := GrassPlacement.points(f, Vector2(-4, -4), 8.0, 6.0, 42)
	var b := GrassPlacement.points(f, Vector2(-4, -4), 8.0, 6.0, 42)
	var c := GrassPlacement.points(f, Vector2(-4, -4), 8.0, 6.0, 43)
	assert_true(a == b)
	assert_true(a != c)
