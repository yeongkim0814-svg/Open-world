extends TestCase
## 굽기. 크기 256, 세계 256m.

const S := 256
const W := 256.0

func _blank() -> Image:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return img

func _height_img(top: int, bottom: int) -> Image:
	var img := _blank()
	var pal := MapLegend.height_palette()
	img.fill_rect(Rect2i(0, 0, S, S / 2), pal[top])
	img.fill_rect(Rect2i(0, S / 2, S, S / 2), pal[bottom])
	return img

func _markers_img() -> Image:
	var img := _blank()
	img.fill_rect(Rect2i(30, 30, 6, 6), MapLegend.MARKERS["lake"])      # 세계 약 (−95, −95)
	img.fill_rect(Rect2i(230, 40, 6, 6), MapLegend.MARKERS["tower"])
	img.fill_rect(Rect2i(200, 200, 6, 6), MapLegend.MARKERS["start"])
	return img

func _layers(height: Image, paths = null) -> Dictionary:
	var l := {"height": height, "markers": _markers_img()}
	if paths != null:
		l["paths"] = paths
	return l

func test_bake_deterministic():
	var a := MapBaker.bake(_layers(_height_img(3, 4)), S, W)
	var b := MapBaker.bake(_layers(_height_img(3, 4)), S, W)
	assert_eq(a["errors"].size(), 0, str(a["errors"]))
	assert_eq(a["height"], b["height"])
	assert_eq(a["zones"], b["zones"])
	assert_eq(a["paths"], b["paths"])
	assert_eq(a["height"].size(), S * S)
	assert_eq(a["zones"].size(), S * S)
	assert_eq(a["zones"][5 * S + 5], 0, "구역 비어 있음 = 초원")

func test_encode_roundtrip():
	var h := PackedFloat32Array()
	h.resize(S * S)
	for i in S * S:
		h[i] = -16.0 + 106.0 * fmod(i * 0.6180339, 1.0)      # 범위 전체
	h[0] = -16.0
	h[1] = 90.0
	var img := MapBaker.encode_height(h, S)
	assert_eq(img.get_width(), S)
	assert_eq(img.get_format(), Image.FORMAT_RGB8)
	var f := HeightField.new(img, W, -16.0, 90.0)
	var worst := 0.0
	for j in range(0, S, 5):
		for i in range(0, S, 7):
			var x := (float(i) / (S - 1) - 0.5) * W
			var z := (float(j) / (S - 1) - 0.5) * W
			worst = maxf(worst, absf(f.height_at(x, z) - h[j * S + i]))
	assert_true(worst < 0.01, "왕복 오차 %.4f m" % worst)

func test_path_dig_and_flatten():
	var base := MapBaker.bake(_layers(_height_img(3, 4)), S, W)["height"] as PackedFloat32Array
	# 흙길: 가로로 난 길, 남북 비탈 한가운데 (z ≈ 0), 폭 5
	var paths := _blank()
	paths.fill_rect(Rect2i(150, S / 2 - 2, 60, 5), MapLegend.path_palette()[0])
	# 수로: 평지 위 세로 줄 (x ≈ 100.., z ≈ 200 근처가 아닌 곳), 폭 3
	paths.fill_rect(Rect2i(100, 175, 3, 40), MapLegend.path_palette()[2])
	var baked := MapBaker.bake(_layers(_height_img(3, 4), paths), S, W)
	var h := baked["height"] as PackedFloat32Array
	var p := baked["paths"] as PackedByteArray
	assert_eq(p[(S / 2) * S + 170], 1, "흙길 = 1")
	assert_eq(p[190 * S + 101], 3, "수로 = 3")
	var x := 180
	var base_range := absf(base[(S / 2 - 2) * S + x] - base[(S / 2 + 2) * S + x])
	var new_range := absf(h[(S / 2 - 2) * S + x] - h[(S / 2 + 2) * S + x])
	assert_true(base_range > 0.3, "비탈 확인 %.3f" % base_range)
	assert_true(new_range < base_range, "길 가로 편차 줄어듦 %.3f < %.3f" % [new_range, base_range])
	var worst := 0.0
	for j in range(S / 2 - 2, S / 2 + 3):
		for i in range(150, 210):
			worst = maxf(worst, absf(h[j * S + i] - base[j * S + i]))
	assert_true(worst <= 0.5 + 0.001, "흙길 변화 ≤ 0.5m: %.3f" % worst)
	assert_almost(base[190 * S + 101] - h[190 * S + 101], 1.5, 0.001, "수로 1.5m 파냄")
	assert_almost(h[190 * S + 110], base[190 * S + 110], 0.001, "수로 밖은 그대로")

func test_missing_required_layer_errors():
	var no_markers := MapBaker.bake({"height": _height_img(3, 3)}, S, W)
	assert_true(no_markers["errors"].size() > 0)
	var no_height := MapBaker.bake({"markers": _markers_img()}, S, W)
	assert_true(no_height["errors"].size() > 0)
	var empty_markers := MapBaker.bake({"height": _height_img(3, 3), "markers": _blank()}, S, W)
	assert_true(empty_markers["errors"].size() >= 3, "필수 표식 없음 오류: %s" % str(empty_markers["errors"]))
	var rect := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	var bad := MapBaker.bake({"height": rect, "markers": _markers_img()}, S, W)
	assert_true(bad["errors"].size() > 0 and "300" in bad["errors"][0], "크기가 오류에 나옴: %s" % str(bad["errors"]))

func test_preview_size():
	var baked := MapBaker.bake(_layers(_height_img(3, 4)), S, W)
	var img := MapBaker.preview(baked, S)
	assert_eq(img.get_width(), 512)
	assert_eq(img.get_height(), 512)

func _stream_paths(x0: int, x1: int, z0: int, z1: int) -> Image:
	var p := _blank()
	p.fill_rect(Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1), MapLegend.path_palette()[3])
	return p

## 개천: V자 — 중앙 −2.5m, 칠한 가장자리 0 (평지, 7px 폭)
func test_stream_profile():
	var base := MapBaker.bake(_layers(_height_img(3, 3)), S, W)["height"] as PackedFloat32Array
	var baked := MapBaker.bake(_layers(_height_img(3, 3), _stream_paths(100, 106, 150, 200)), S, W)
	var h := baked["height"] as PackedFloat32Array
	var p := baked["paths"] as PackedByteArray
	assert_eq(p[175 * S + 103], 4, "개천 = 4")
	var z := 175
	assert_almost(h[z * S + 103] - base[z * S + 103], -2.5, 0.01, "중앙")
	assert_almost(h[z * S + 100] - base[z * S + 100], 0.0, 0.01, "왼쪽 가장자리")
	assert_almost(h[z * S + 106] - base[z * S + 106], 0.0, 0.01, "오른쪽 가장자리")
	assert_almost(h[z * S + 102] - base[z * S + 102], -2.5 * 2.0 / 3.0, 0.05, "중간")
	assert_almost(h[z * S + 99] - base[z * S + 99], 0.0, 0.0001, "개천 밖은 그대로")

## 순서: 도장 → 길 → 개천. 저수호 둑(도장)을 지나는 개천은 도장된 높이에서 2.5m 파인다.
func test_stream_dug_after_stamps():
	var base := MapBaker.bake(_layers(_height_img(3, 3)), S, W)["height"] as PackedFloat32Array
	# 저수호 중심 px ~32.5 -> 둑 꼭대기 (반경 ~53m) 는 px ~85~86 근처
	var with_stream := MapBaker.bake(_layers(_height_img(3, 3), _stream_paths(83, 89, 20, 45)), S, W)
	var h := with_stream["height"] as PackedFloat32Array
	var z := 32
	assert_true(base[z * S + 86] > 8.0, "그 자리는 도장된 둑 (%.2f)" % base[z * S + 86])
	assert_almost(base[z * S + 86] - h[z * S + 86], 2.5, 0.01, "도장이 만든 둑 위에서 파임")

func test_stream_not_flattened_by_path_pass():
	var paths := _stream_paths(100, 106, 150, 200)
	paths.fill_rect(Rect2i(150, 170, 40, 4), MapLegend.path_palette()[0])
	var baked := MapBaker.bake(_layers(_height_img(3, 3), paths), S, W)
	assert_eq(baked["errors"].size(), 0, str(baked["errors"]))
	assert_eq(baked["paths"][172 * S + 103], 4)

func test_edge_sea_cfg():
	var on := MapBaker.bake(_layers(_height_img(3, 3)), S, W)["height"] as PackedFloat32Array
	assert_almost(on[150 * S + 0], -14.0, 0.01, "기본 = 가장자리 바다")
	var off := MapBaker.bake(_layers(_height_img(3, 3)), S, W, {"edge_sea": false})["height"] as PackedFloat32Array
	assert_true(off[150 * S + 0] > 4.0, "edge_sea=false -> 육지 유지 (%.2f)" % off[150 * S + 0])
	assert_true(off[S * S - 1] > 4.0 and off[255 * S] > 4.0)

func test_cfg_range_and_smooth():
	var mountain := MapBaker.bake(_layers(_height_img(7, 7)), S, W)["height"] as PackedFloat32Array
	assert_true(mountain[128 * S + 128] <= 90.001, "기본 상한 90")
	var cfg := {"min_h": -20.0, "max_h": 200.0, "smooth_radius": 40.0, "edge_sea": false}
	var hi := MapBaker.bake(_layers(_height_img(7, 7)), S, W, cfg)["height"] as PackedFloat32Array
	assert_true(hi[128 * S + 128] > 120.0, "상한 200 -> 고산 160 유지 (%.1f)" % hi[128 * S + 128])
	assert_true(hi[128 * S + 128] <= 200.001)

func test_encode_roundtrip_custom_range():
	var h := PackedFloat32Array()
	h.resize(S * S)
	for i in S * S:
		h[i] = -20.0 + 220.0 * fmod(i * 0.6180339, 1.0)
	var img := MapBaker.encode_height(h, S, -20.0, 200.0)
	var f := HeightField.new(img, W, -20.0, 200.0)
	var worst := 0.0
	for j in range(0, S, 5):
		for i in range(0, S, 7):
			var x := (float(i) / (S - 1) - 0.5) * W
			var z := (float(j) / (S - 1) - 0.5) * W
			worst = maxf(worst, absf(f.height_at(x, z) - h[j * S + i]))
	assert_true(worst < 0.02, "왕복 오차 %.4f m" % worst)

func test_meta_written():
	var d := MapBaker.meta({}, 1024, 1024.0)
	assert_eq(d["world"], 1024.0)
	assert_eq(d["size"], 1024)
	assert_eq(d["min_h"], -16.0)
	assert_eq(d["max_h"], 90.0)
	var m := MapBaker.meta({"min_h": -20, "max_h": 200, "world": 999, "edge_sea": false}, 2048, 2048.0)
	assert_eq(m["world"], 2048.0, "world 인자가 우선")
	assert_eq(m["size"], 2048)
	assert_eq(m["min_h"], -20.0)
	assert_eq(m["max_h"], 200.0)
	assert_eq(m.size(), 4)
	var baked := MapBaker.bake(_layers(_height_img(3, 3)), S, W)
	assert_eq(baked["meta"], MapBaker.meta({}, S, W))

func test_bake_markers_carry_crest_and_top():
	var baked := MapBaker.bake(_layers(_height_img(3, 3)), S, W)
	for m in baked["markers"]:
		if m["kind"] == "lake":
			assert_true(m.has("crest"), "저수호 crest")
		if m["kind"] == "tower":
			assert_true(m.has("top"), "탑 top")
