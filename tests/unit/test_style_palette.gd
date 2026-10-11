extends TestCase

func test_depleted_and_restored_match_spec():
	assert_eq(StylePalette.DEPLETED.sky_horizon, Color("#AABAC5"))
	assert_eq(StylePalette.DEPLETED.grass, Color("#A5AC91"))
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

## B2 9.2: 잎(황갈색)·바위(청회색)는 회복 0 에서 일부러 색조를 줘 구분하므로 채도 규칙에서 제외한다.
func test_restored_is_more_saturated():
	for k in StylePalette.DEPLETED:
		if k == "foliage" or k == "rock":
			continue
		assert_true(StylePalette.RESTORED[k].s >= StylePalette.DEPLETED[k].s, "채도: %s" % k)

## 첫 섬 교체 A: 구역·길 땅 색 키 (회복 시 채도 규칙은 test_restored_is_more_saturated가 함께 검사)
func test_zone_and_path_keys_exist():
	for k in ["zone_broadleaf", "zone_conifer", "zone_wetland", "zone_highland", "zone_wasteland", "path_dirt", "path_paved"]:
		assert_true(StylePalette.DEPLETED.has(k) and StylePalette.RESTORED.has(k), "키 없음: " + k)
	# 황무지는 회복하면 초원 쪽 초록이 된다 (구역 전환)
	assert_true(StylePalette.RESTORED.zone_wasteland.g > StylePalette.RESTORED.zone_wasteland.r, "회복된 황무지 = 초록 계열")


## B2 9.2 색표 HEX
func test_b2_recovery_zero_colors():
	assert_eq(StylePalette.DEPLETED.foliage, Color("#A89270"))
	assert_eq(StylePalette.DEPLETED.trunk, Color("#5E5045"))
	assert_eq(StylePalette.RESTORED.trunk, Color("#6B5640"))
	assert_eq(StylePalette.DEPLETED.rock, Color("#7E858C"))
	assert_eq(StylePalette.RESTORED.rock, Color("#8E8A82"))
	assert_eq(StylePalette.DEPLETED.moss, Color("#9E9A86"))
	assert_eq(StylePalette.RESTORED.moss, Color("#6F8F55"))
	assert_eq(StylePalette.DEPLETED.ground, Color("#B5B19E"))


func _luma(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## 회복 0 과 0.5 에서 잎·바위 선형 휘도 차 ≥ 12 % (밝은 쪽 기준), 잎 따뜻함(R > B), 바위 차가움(B ≥ R)
func test_leaf_rock_separation():
	for r in [0.0, 0.5]:
		var leaf := _luma(StylePalette.color("foliage", r))
		var rock := _luma(StylePalette.color("rock", r))
		var diff := absf(leaf - rock) / maxf(leaf, rock)
		assert_true(diff >= 0.12, "회복 %.1f 잎·바위 밝기 차 %.3f < 0.12" % [r, diff])
	var leaf0: Color = StylePalette.color("foliage", 0.0)
	var rock0: Color = StylePalette.color("rock", 0.0)
	assert_true(leaf0.r > leaf0.b, "회복 0 잎 R > B")
	assert_true(rock0.b >= rock0.r, "회복 0 바위 B >= R")
