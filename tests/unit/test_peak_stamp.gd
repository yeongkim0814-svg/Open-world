extends TestCase
## 봉우리 도장 (설계서 P18). 크기 701, 세계 1400m (1칸 = 2m). 높이는 칠한 띠 위에 "더한다".

const S := 701
const W := 1400.0

func _flat(v: float) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(S * S)
	h.fill(v)
	return h

func _at(h: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x / W + 0.5) * (S - 1), 0.0, S - 1.001)
	var fz := clampf((z / W + 0.5) * (S - 1), 0.0, S - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var top := lerpf(h[iz * S + ix], h[iz * S + ix + 1], tx)
	var bot := lerpf(h[(iz + 1) * S + ix], h[(iz + 1) * S + ix + 1], tx)
	return lerpf(top, bot, tz)

func _peak() -> Dictionary:
	return {"kind": "peak", "x": 0.0, "z": 0.0, "yaw": 0.0}

## 중심에서 거리 d, 각도 a(rad) 방향 반지름 경사각 (도). 4m 폭으로 잰다.
func _slope_deg(h: PackedFloat32Array, d: float, a: float) -> float:
	var hi := _at(h, (d - 2.0) * cos(a), (d - 2.0) * sin(a))
	var lo := _at(h, (d + 2.0) * cos(a), (d + 2.0) * sin(a))
	return rad_to_deg(atan2(hi - lo, 4.0))

## 정상 평탄지(반경 180m) 안은 기울어진 원지형 위에서도 정확히 peak_height.
func test_peak_summit_height():
	var h := _flat(0.0)
	for z in S:
		for x in S:
			h[z * S + x] = 45.0 + 0.01 * ((float(x) / (S - 1) - 0.5) * W)      # 기울어진 고원
	MapStamps.apply(h, S, W, [_peak()], {"peak_height": 350.0})
	var worst := 0.0
	for z in S:
		for x in S:
			var wx := (float(x) / (S - 1) - 0.5) * W
			var wz := (float(z) / (S - 1) - 0.5) * W
			if Vector2(wx, wz).length() <= 178.0:
				worst = maxf(worst, absf(h[z * S + x] - 350.0))
	assert_true(worst <= 1.0, "정상 평탄지 높이 오차 %.3f m" % worst)
	assert_almost(_at(h, -690, -690), 45.0 - 6.9, 0.05, "peak_radius 밖은 원지형")
	assert_true(_at(h, 500, 0) > 45.0 + 5.0 + 0.01 * 500.0, "비탈은 원지형보다 높음")
	var h2 := _flat(10.0)
	MapStamps.apply(h2, S, W, [_peak()])
	assert_almost(_at(h2, 0, 0), 350.0, 1.0, "기본 정상 350m")

## 정상 테두리 아래 절벽대(60도 이상) + 시드로 정한 오르는 틈 3곳(35도 이하).
func test_peak_has_gaps_and_cliffs():
	var h := _flat(5.0)
	var m := _peak()
	MapStamps.apply(h, S, W, [m], {})
	var gaps: Array = m["gaps"]
	assert_eq(gaps.size(), 3, "틈 3곳")
	var again := _peak()
	MapStamps.apply(_flat(5.0), S, W, [again], {})
	assert_eq(again["gaps"], gaps, "같은 입력 = 같은 틈 (결정적)")
	for g in gaps:
		for off in [-4.0, 0.0, 4.0]:
			var a: float = g + deg_to_rad(off)
			for d in [190.0, 205.0, 220.0]:
				var s := _slope_deg(h, d, a)
				assert_true(s <= 35.0 and s >= 0.0, "틈 경사 d=%.0f 각 %.0f%+.0f: %.1f도" % [d, rad_to_deg(g), off, s])
	var steep := 0
	var total := 0
	for deg in range(0, 360, 4):
		var a := deg_to_rad(float(deg))
		var near_gap := false
		for g in gaps:
			if absf(wrapf(a - g + PI, 0.0, TAU) - PI) < deg_to_rad(14.0):
				near_gap = true
		if near_gap:
			continue
		total += 1
		if _slope_deg(h, 205.0, a) >= 60.0:
			steep += 1
	assert_true(total > 50 and float(steep) / total >= 0.95, "절벽대 60도 이상 비율 %d/%d" % [steep, total])

## 칠한 단차(절벽)는 더해진 비탈 위에도 그대로 남는다 (봉우리는 "더하기").
func test_peak_adds_to_painted_steps():
	var flat := _flat(45.0)
	var step := _flat(45.0)
	for z in S:
		for x in S:
			if (float(x) / (S - 1) - 0.5) * W > 380.0:
				step[z * S + x] = 65.0          # 칠한 20m 절벽 단차 (동쪽)
	MapStamps.apply(flat, S, W, [_peak()], {})
	MapStamps.apply(step, S, W, [_peak()], {})
	assert_almost(_at(step, 420, 0) - _at(flat, 420, 0), 20.0, 0.01, "단차 20m 그대로 (봉우리 위)")
	assert_almost(_at(step, 400, 100) - _at(flat, 400, 100), 20.0, 0.01)
	assert_almost(_at(step, -420, 0) - _at(flat, -420, 0), 0.0, 0.01, "단차 없는 쪽은 같음")
	assert_true(_at(flat, 420, 0) > 45.0 + 5.0, "비탈이 원지형에 더해짐")

## 틈 지맥은 절벽대 아래 SPUR_LEN 안에서 원래 비탈로 녹아든다 (반경 전체를 가르는 직선 경사로 = 판자 금지).
func test_peak_gap_spur_fades():
	var h := _flat(5.0)
	var m := _peak()
	MapStamps.apply(h, S, W, [m], {})
	var d := MapStamps.SUMMIT_RADIUS + MapStamps.CLIFF_WIDTH + MapStamps.SPUR_LEN + 40.0
	for g in m["gaps"]:
		var side := (_at(h, d * cos(g - 0.35), d * sin(g - 0.35)) + _at(h, d * cos(g + 0.35), d * sin(g + 0.35))) * 0.5
		var mid := _at(h, d * cos(g), d * sin(g))
		assert_true(absf(mid - side) < 15.0, "틈 %.0f도 d=%.0f: 지맥 %.1f vs 옆 %.1f" % [rad_to_deg(g), d, mid, side])

## 틈 지맥 등은 절벽대 아래에서도 걸을 만하다 (칠한 고원 45m 위, 42도 이하).
func test_peak_gap_spur_walkable():
	var h := _flat(45.0)
	var m := _peak()
	MapStamps.apply(h, S, W, [m], {})
	var d0 := MapStamps.SUMMIT_RADIUS + MapStamps.CLIFF_WIDTH
	var worst := 0.0
	for g in m["gaps"]:
		var d := d0
		while d < d0 + MapStamps.SPUR_LEN:
			worst = maxf(worst, _slope_deg(h, d, g))
			d += 10.0
	assert_true(worst <= 42.0, "지맥 등 최대 경사 %.1f도" % worst)
