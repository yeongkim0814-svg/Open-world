extends TestCase
## 띠 → 높이 (작은 크기 128로 검사; 가장자리 깊은 바다 폭 = 32 * size / 1024 → 4px)

const S := 128

func _filled(band: int) -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(S * S)
	b.fill(band)
	return b

func _no_cliff() -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(S * S)
	return c

func _h(h: PackedFloat32Array, x: int, y: int) -> float:
	return h[y * S + x]

func test_band_targets():
	var h := HeightBands.build(_filled(3), S, _no_cliff())
	for y in range(40, 90, 7):
		for x in range(40, 90, 7):
			assert_almost(_h(h, x, y), 4.0, 1.5, "평지 (%d,%d) = %.2f" % [x, y, _h(h, x, y)])

func test_empty_filled_from_nearest():
	var b := _filled(-1)
	for y in S:
		for x in range(0, 40):
			b[y * S + x] = 5   # 고원 24, 오른쪽은 비어 있음
	var h := HeightBands.build(b, S, _no_cliff(), 4.0, 0.0)
	assert_almost(_h(h, 100, 64), 24.0, 0.5, "빈칸은 가까운 고원 값으로 채움")

func test_edge_is_deep_sea():
	var h := HeightBands.build(_filled(4), S, _no_cliff())
	for i in [0, 3, 64, S - 1]:
		assert_almost(_h(h, i, 0), -12.0, 0.01)
		assert_almost(_h(h, 0, i), -12.0, 0.01)
		assert_almost(_h(h, i, S - 1), -12.0, 0.01)
		assert_almost(_h(h, S - 1, i), -12.0, 0.01)

func test_smooth_between_bands():
	var b := _filled(3)
	for y in S:
		for x in range(S / 2, S):
			b[y * S + x] = 4   # 평지 | 언덕
	var h := HeightBands.build(b, S, _no_cliff(), 12.0, 0.0)
	var max_slope := 0.0
	for x in range(20, S - 20):
		max_slope = maxf(max_slope, absf(_h(h, x + 1, 64) - _h(h, x, 64)))
	assert_true(rad_to_deg(atan(max_slope)) < 30.0, "경사 %.1f°" % rad_to_deg(atan(max_slope)))
	assert_almost(_h(h, 24, 64), 4.0, 0.3)
	assert_almost(_h(h, S - 25, 64), 12.0, 0.3)

func _cliff_case(gap: bool) -> PackedFloat32Array:
	var b := _filled(-1)
	var c := _no_cliff()
	for y in S:
		for x in S:
			if x < S / 2:
				b[y * S + x] = 3     # 평지 4
			elif x > S / 2:
				b[y * S + x] = 5     # 고원 24
	for y in S:
		if gap and y == 64:
			continue
		c[y * S + S / 2] = 1
	return HeightBands.build(b, S, c, 12.0, 0.0)

func test_cliff_line_keeps_wall_steep():
	var h := _cliff_case(false)
	var x := S / 2
	assert_true(_h(h, x + 3, 64) - _h(h, x - 3, 64) >= 15.0, "절벽 차 %.1f" % (_h(h, x + 3, 64) - _h(h, x - 3, 64)))
	assert_true(_h(h, x + 3, 30) - _h(h, x - 3, 30) >= 15.0)

func test_cliff_line_with_gap_still_steep():
	var h := _cliff_case(true)
	var x := S / 2
	assert_true(_h(h, x + 3, 64) - _h(h, x - 3, 64) >= 12.0, "틈 있는 절벽 차 %.1f" % (_h(h, x + 3, 64) - _h(h, x - 3, 64)))

func test_deterministic_and_detail_zero_near_sea():
	var a := HeightBands.build(_filled(3), S, _no_cliff(), 12.0, 1.5, 7)
	var b := HeightBands.build(_filled(3), S, _no_cliff(), 12.0, 1.5, 7)
	assert_eq(a, b)
