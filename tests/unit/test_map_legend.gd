extends TestCase

func _hpal() -> Array[Color]:
	return MapLegend.height_palette()

func test_exact_colors_classify():
	var pal := _hpal()
	for i in pal.size():
		assert_eq(MapLegend.classify(pal[i], pal), i)

func test_white_and_transparent_are_empty():
	var pal := _hpal()
	assert_eq(MapLegend.classify(Color.WHITE, pal), -1)
	assert_eq(MapLegend.classify(Color(0.6, 0.73, 0.35, 0.2), pal), -1)

func test_blended_edge_pixels():
	var pal := _hpal()
	var a := pal[3]   # 평지
	var b := pal[4]   # 언덕
	var mid := a.lerp(b, 0.5)
	var k := MapLegend.classify(mid, pal)
	assert_true(k == 3 or k == 4, "중간색은 둘 중 하나: %d" % k)
	assert_eq(MapLegend.classify(Color8(200, 60, 60), pal), -1, "문턱 밖 색 = 비어 있음")

func test_resize_and_reject_non_square():
	var pal := _hpal()
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(pal[3])
	var out := MapLegend.load_layer(img, pal)
	assert_eq(out.size(), 1024 * 1024)
	assert_eq(out[0], 3)
	var bad := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	assert_eq(MapLegend.load_layer(bad, pal).size(), 0, "정사각형 아님 = 빈 배열")

func test_band_heights_a2():
	var want := [-14.0, -4.0, 1.0, 6.0, 20.0, 45.0, 90.0, 160.0]
	for i in want.size():
		assert_almost(MapLegend.HEIGHT[i]["h"], want[i], 0.0001, "띠 %d" % i)

func test_stream_path_and_hill_village_marker():
	var pp := MapLegend.path_palette()
	assert_eq(pp.size(), 4)
	assert_eq(pp[3].to_html(false).to_upper(), "6FA8DC")
	assert_eq(MapLegend.classify(Color8(0x6F, 0xA8, 0xDC), pp), 3, "개천 = 인덱스 3 (구운 값 4)")
	assert_eq(MapLegend.classify(Color8(0x2E, 0x75, 0xB6), pp), 2, "수로는 그대로")
	assert_eq(MapLegend.MARKERS["hill_village"].to_html(false).to_upper(), "FFC000")
	var mp := MapLegend.marker_palette()
	assert_eq(MapLegend.classify(Color8(0xFF, 0xC0, 0x00), mp), MapLegend.marker_kinds().find("hill_village"))
	assert_eq(MapLegend.classify(Color8(0xFF, 0xFF, 0x00), mp), MapLegend.marker_kinds().find("village"))
