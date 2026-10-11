extends TestCase

func test_depleted_and_restored_match_spec():
	assert_eq(StylePalette.DEPLETED.sky_horizon, Color("#AABAC5"))
	assert_eq(StylePalette.DEPLETED.grass, Color("#A5AC91"))
	assert_eq(StylePalette.DEPLETED.rock, Color("#8C918F"))
	assert_eq(StylePalette.DEPLETED.ground, Color("#C8C2AC"))
	assert_eq(StylePalette.RESTORED.grass, Color("#6FA35A"))
	assert_eq(StylePalette.RESTORED.sky_zenith, Color("#4F86C0"))
	assert_eq(StylePalette.LIFE, Color("#76C9C3"))

func test_color_interpolates():
	assert_eq(StylePalette.color("grass", 0.0), StylePalette.DEPLETED.grass)
	assert_eq(StylePalette.color("grass", 1.0), StylePalette.RESTORED.grass)
	var mid := StylePalette.color("grass", 0.5)
	var want: Color = StylePalette.DEPLETED.grass.lerp(StylePalette.RESTORED.grass, 0.5)
	for i in 3:
		assert_true(absf(mid[i] - want[i]) < 0.01, "채널 %d" % i)

func test_restored_is_more_saturated():
	for k in StylePalette.DEPLETED:
		assert_true(StylePalette.RESTORED[k].s >= StylePalette.DEPLETED[k].s, "채도: %s" % k)
