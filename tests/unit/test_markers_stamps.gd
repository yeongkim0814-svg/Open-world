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
	MapStamps.apply(h, S, W, [{"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}])
	assert_almost(_at(h, 0, 0), -6.0, 0.05, "중심")
	assert_almost(_at(h, 30, 0), -6.0, 0.05, "반경 30")
	assert_almost(_at(h, 53, 0), 16.0, 0.05, "둑 꼭대기")
	assert_almost(_at(h, 0, -53), 16.0, 0.05)
	assert_almost(_at(h, 100, 0), 5.0, 0.05, "바깥 원지형")
	assert_true(_at(h, 67, 0) > 5.0 and _at(h, 67, 0) < 16.0, "바깥 비탈 중간")

func test_tower_island_top():
	var h := _flat(5.0)
	var ms := [{"kind": "lake", "x": 0.0, "z": 0.0, "yaw": 0.0}, {"kind": "tower", "x": 10.0, "z": 0.0, "yaw": 0.0}]
	MapStamps.apply(h, S, W, ms)
	assert_almost(_at(h, 10, 0), 18.0, 0.05)
	assert_almost(_at(h, 18, 0), 18.0, 0.05, "반경 8 안 윗면")
	assert_almost(_at(h, -30, 0), -6.0, 0.05, "섬 밖은 분지 바닥")

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
