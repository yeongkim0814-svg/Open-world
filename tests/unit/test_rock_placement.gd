extends TestCase

# 합성 지형: 300 m, 가운데 원뿔 산(경사 큼) + 바깥 평지.
func _field() -> HeightField:
	var n := 150
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	for y in n:
		for x in n:
			var wx := (float(x) / (n - 1) - 0.5) * 300.0
			var wz := (float(y) / (n - 1) - 0.5) * 300.0
			var d := Vector2(wx, wz).distance_to(Vector2(30, 20))
			var h := clampf(1.0 - d / 60.0, 0.0, 1.0)   # 60 m 반경 원뿔, 70 m 높이 → 약 49°
			img.set_pixel(x, y, Color(h, h, h))
	return HeightField.new(img, 300.0, -10.0, 60.0)

func _excl() -> Array:
	return [Vector3(30, 20, 15), Rect2(-3, -2, 6, 38)]

func test_rocks_avoid_exclusions():
	var pts := RockPlacement.points(_field(), 7, 70, _excl())
	assert_true(pts.size() > 40, "충분히 배치: %d" % pts.size())
	for t in pts:
		var p: Vector3 = t.origin
		assert_true(Vector2(p.x, p.z).distance_to(Vector2(30, 20)) >= 15.0, "원 밖")
		assert_false(Rect2(-3, -2, 6, 38).has_point(Vector2(p.x, p.z)), "사각형 밖")

func test_rocks_prefer_slopes():
	var f := _field()
	var pts := RockPlacement.points(f, 7, 70, _excl())
	var steep := 0
	for t in pts:
		var n := f.normal_at(t.origin.x, t.origin.z)
		if rad_to_deg(acos(n.y)) >= 35.0:
			steep += 1
	assert_true(float(steep) / pts.size() >= 0.7, "경사 칸 비율 %d/%d" % [steep, pts.size()])

func test_deterministic():
	var f := _field()
	var a := RockPlacement.points(f, 7, 70, _excl())
	var b := RockPlacement.points(f, 7, 70, _excl())
	var c := RockPlacement.points(f, 8, 70, _excl())
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_true(a[i].is_equal_approx(b[i]), "같은 시드 = 같은 결과")
	assert_false(a.size() == c.size() and a[0].is_equal_approx(c[0]), "다른 시드 = 다른 결과")

func test_scale_and_sink():
	var f := _field()
	for t in RockPlacement.points(f, 7, 70, _excl()):
		var s: float = t.basis.get_scale().x
		assert_true(s >= 0.99 and s <= 6.01, "크기 1~6m: %f" % s)
		var ground := f.height_at(t.origin.x, t.origin.z)
		assert_true(t.origin.y < ground, "땅에 묻힘")
