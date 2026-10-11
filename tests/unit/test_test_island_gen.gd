extends TestCase

func _field(img: Image) -> HeightField:
	return HeightField.new(img, TestIslandGen.WORLD, TestIslandGen.MIN_H, TestIslandGen.MAX_H)

func test_size_and_deterministic():
	var a := TestIslandGen.image(129, 3)
	assert_eq(a.get_width(), 129)
	assert_eq(a.get_height(), 129)
	assert_eq(a.get_data(), TestIslandGen.image(129, 3).get_data())

func test_has_cliff_and_pond():
	var f := _field(TestIslandGen.image(129, 3))
	var steep := 0
	for z in range(-60, 61, 2):
		for x in range(-60, 61, 2):
			if f.normal_at(x, z).y < 0.5:
				steep += 1
	assert_true(steep > 0, "60° 넘는 절벽 칸이 있어야 함")
	var p := TestIslandGen.POND_CENTER
	assert_true(f.height_at(p.x, p.y) < 2.0, "연못 중심 < 2.0 (실제 %s)" % f.height_at(p.x, p.y))
	assert_true(f.height_at(63.0, 0.0) < 0.5, "가장자리 = 바다")
	assert_true(f.height_at(0.0, 20.0) > TestIslandGen.POND_LEVEL, "섬 중앙은 물 위")
