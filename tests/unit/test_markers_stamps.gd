extends TestCase
## 표식 읽기 · 도장. 크기 256, 세계 256m (1px ≈ 1m).

const S := 256
const W := 256.0

func _img() -> Image:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return img

func _blob(img: Image, kind: String, x: int, y: int, w := 8, h := 8) -> void:
	img.fill_rect(Rect2i(x, y, w, h), MapLegend.MARKERS[kind])

func _px_to_world(px: float) -> float:
	return (px / float(S - 1) - 0.5) * W

func _first(markers: Array, kind: String) -> Dictionary:
	for m in markers:
		if m["kind"] == kind:
			return m
	return {}

func _flat(v: float) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(S * S)
	h.fill(v)
	return h

func _at(h: PackedFloat32Array, x: float, z: float) -> float:
	var px := int(round((x / W + 0.5) * (S - 1)))
	var pz := int(round((z / W + 0.5) * (S - 1)))
	return h[pz * S + px]

func test_blob_centroid():
	var img := _img()
	_blob(img, "tower", 100, 50, 10, 6)       # 중심 px (104.5, 52.5)
	_blob(img, "ruin", 30, 200)
	_blob(img, "ruin", 200, 30)               # 같은 색 떨어진 두 덩어리 = 두 표식
	var ms := MarkerReader.read(img, S, W)
	var t := _first(ms, "tower")
	assert_almost(t["x"], _px_to_world(104.5), 0.01)
	assert_almost(t["z"], _px_to_world(52.5), 0.01)
	var ruins := 0
	for m in ms:
		if m["kind"] == "ruin":
			ruins += 1
	assert_eq(ruins, 2)

func test_yaw_faces_village():
	var img := _img()
	_blob(img, "tower", 60, 120)
	_blob(img, "village", 200, 120)           # 탑에서 동쪽(+x)
	var ms := MarkerReader.read(img, S, W)
	var t := _first(ms, "tower")
	var v := _first(ms, "village")
	var fwd := Basis(Vector3.UP, t["yaw"]) * Vector3.FORWARD
	var want := Vector3(v["x"] - t["x"], 0, v["z"] - t["z"]).normalized()
	assert_true(fwd.dot(want) > 0.999, "탑이 마을을 바라봄 %s vs %s" % [fwd, want])
	var alone := _img()
	_blob(alone, "tower", 60, 120)
	assert_almost(_first(MarkerReader.read(alone, S, W), "tower")["yaw"], 0.0, 0.0001, "마을·저수호 없으면 0")

func test_required_markers():
	var ms: Array = []
	var errs := MarkerReader.validate(ms)
	assert_true(errs.size() >= 3, "시작·탑·저수호 없음 → 오류 3: %s" % str(errs))
	ms = [{"kind": "start", "x": 0.0, "z": 0.0, "yaw": 0.0}, {"kind": "tower", "x": 1.0, "z": 0.0, "yaw": 0.0}, {"kind": "lake", "x": 2.0, "z": 0.0, "yaw": 0.0}]
	assert_eq(MarkerReader.validate(ms).size(), 0)
	for i in 4:
		ms.append({"kind": "sluice", "x": float(i), "z": 5.0, "yaw": 0.0})
	var warn := MarkerReader.validate(ms)
	assert_eq(warn.size(), 1, "수문 4개 = 경고 1: %s" % str(warn))
	assert_true(warn[0].begins_with(MarkerReader.WARNING_PREFIX))
	assert_eq(MarkerReader.limit_sluices(ms, 3).size(), 6)

func test_lake_stamp_numbers():
	var h := _flat(5.0)
	var lake := {"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}
	MapStamps.apply(h, S, W, [lake])
	assert_almost(_at(h, 0, 0), -13.0, 0.05, "중심 = 꼭대기 − 22")
	assert_almost(_at(h, 30, 0), -13.0, 0.05, "반경 30")
	assert_almost(_at(h, 53, 0), 9.0, 0.05, "둑 꼭대기 = 지면 + 4")
	assert_almost(_at(h, 0, -53), 9.0, 0.05)
	assert_almost(_at(h, 100, 0), 5.0, 0.05, "바깥 원지형")
	assert_true(_at(h, 67, 0) > 5.0 and _at(h, 67, 0) < 9.0, "바깥 비탈 중간")
	assert_almost(lake["crest"], 9.0, 0.01, "마커에 crest 기록")

## 설계서 P12: 높은 산 위에서도 "둑 + 깊은 분지" (꼭대기 > 주변, 바닥 = 꼭대기 − 22).
func test_lake_stamp_relative_on_high_ground():
	var h := _flat(100.0)
	var lake := {"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}
	MapStamps.apply(h, S, W, [lake])
	assert_almost(lake["crest"], 104.0, 0.01)
	assert_almost(_at(h, 0, 0), 82.0, 0.05, "바닥 = 꼭대기 − 22")
	assert_almost(_at(h, 53, 0), 104.0, 0.05, "둑 꼭대기")
	assert_almost(_at(h, 110, 0), 100.0, 0.05, "바깥 원지형")
	assert_true(_at(h, 53, 0) > _at(h, 100, 0), "꼭대기 > 주변")
	# 비탈진 지면: 반경 60~80m 고리의 원지형 중앙값 (대칭 경사 → 중심 높이)
	var g := _flat(0.0)
	for y in S:
		for x in S:
			g[y * S + x] = 100.0 + 0.1 * _px_to_world(x)
	var lake2 := {"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}
	MapStamps.apply(g, S, W, [lake2])
	assert_almost(lake2["crest"], 104.0, 0.3, "비탈 고리 중앙값")

func test_tower_island_top():
	var h := _flat(5.0)
	var ms := [{"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}, {"kind": "tower", "x": 10.0, "z": 0.0, "yaw": 0.0}]
	MapStamps.apply(h, S, W, ms)
	assert_almost(_at(h, 10, 0), 11.0, 0.05, "탑 윗면 = 꼭대기 + 2")
	assert_almost(_at(h, 18, 0), 11.0, 0.05, "반경 8 안 윗면")
	assert_almost(_at(h, -30, 0), -13.0, 0.05, "섬 밖은 분지 바닥")
	assert_almost(ms[1]["top"], 11.0, 0.01, "마커에 top 기록")

func test_village_flattened():
	var h := _flat(0.0)
	for y in S:
		for x in S:
			h[y * S + x] = 3.0 + 0.05 * (x - 128) + 0.03 * (y - 128) + sin(x * 0.3) * 0.5   # 기울고 울퉁불퉁
	MapStamps.apply(h, S, W, [{"kind": "village", "x": 0.0, "z": 0.0, "yaw": 0.0}])
	var lo := 1e9
	var hi := -1e9
	for y in S:
		for x in S:
			var wx := _px_to_world(x)
			var wz := _px_to_world(y)
			if Vector2(wx, wz).length() <= 30.0:
				lo = minf(lo, h[y * S + x])
				hi = maxf(hi, h[y * S + x])
	assert_true(hi - lo < 0.3, "마을 편차 %.3f" % (hi - lo))

## 1km 등반 스윕: 안쪽 벽 윗부분이 둥글게 누우면 등반 유지(경사)와 꼭대기 판정 사이에 끼어 깜빡인다 → 직선 벽 + 날카로운 테두리.
func test_lake_inner_wall_has_sharp_lip():
	var top := MapStamps.lake_profile(MapStamps.LAKE_WALL_R, 5.0, 9.0, -13.0)
	var below := MapStamps.lake_profile(MapStamps.LAKE_WALL_R - 0.5, 5.0, 9.0, -13.0)
	assert_true(top - below >= 5.0, "테두리 바로 아래 0.5m 구간도 가팔라야 함 (차 %.2f)" % (top - below))
	assert_almost(MapStamps.lake_profile(50.0, 5.0, 9.0, -13.0), 9.0, 0.01, "테두리 너머는 평평한 둑 꼭대기")
	assert_almost(MapStamps.lake_profile(10.0, 5.0, 104.0, 82.0), 82.0, 0.01, "바닥은 floor 인자")

## 최종 리뷰: 시작·탑·저수호가 두 개 이상이면 경고 (앞의 것을 쓴다)
func test_duplicate_required_markers_warn():
	var ms := [{"kind": "start", "x": 0.0, "z": 0.0, "yaw": 0.0}, {"kind": "start", "x": 9.0, "z": 0.0, "yaw": 0.0},
		{"kind": "tower", "x": 0.0, "z": 0.0, "yaw": 0.0}, {"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}]
	var out := MarkerReader.validate(ms)
	assert_eq(out.size(), 1)
	assert_true(out[0].begins_with(MarkerReader.WARNING_PREFIX), "오류가 아니라 경고")

## 설계서 P14: 산마을은 도장 없음 (평탄화하지 않음)
func test_hill_village_not_flattened():
	var h := _flat(0.0)
	for y in S:
		for x in S:
			h[y * S + x] = 3.0 + 0.05 * (x - 128) + 0.03 * (y - 128) + sin(x * 0.3) * 0.5
	var before := h.duplicate()
	MapStamps.apply(h, S, W, [{"kind": "hill_village", "x": 0.0, "z": 0.0, "yaw": 0.0}])
	assert_eq(h, before, "산마을 = 높이 그대로")
	var img := _img()
	_blob(img, "hill_village", 100, 100)
	assert_eq(_first(MarkerReader.read(img, S, W), "hill_village")["kind"], "hill_village")
