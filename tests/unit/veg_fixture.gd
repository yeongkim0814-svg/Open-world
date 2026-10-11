class_name VegFixture
extends RefCounted
## 식생 시험용 합성 지도 (128 m). 테스트 파일 아님 — 러너는 test_*.gd 만 읽는다.
## 높이: 10 + 0.1x (z > 56 인 남쪽 띠는 0 m = 바다·해변). 구역: x < 0 초원(0) / x >= 0 활엽수림(1).
## 길: x = -2..1 세로 흙길(4 px). 표식: 마을 (-40,-40), 탑 (40,-40), 산마을 (-45,45), 정상 (55,55).

const WORLD := 128.0
const N := 129   # 1 m / 픽셀

static func markers() -> Array:
	return [
		{"kind": "village", "x": -40.0, "z": -40.0},
		{"kind": "tower", "x": 40.0, "z": -40.0},
		{"kind": "hill_village", "x": -45.0, "z": 45.0},
		{"kind": "peak", "x": 55.0, "z": 55.0},
	]

static func cfg() -> Dictionary:
	return {"tower_radius": 10.0, "lake_radius": 20.0, "summit_radius": 120.0}

static func field() -> HeightField:
	var h := PackedFloat32Array()
	h.resize(N * N)
	for j in N:
		for i in N:
			var x := float(i) - 64.0
			var z := float(j) - 64.0
			h[j * N + i] = 0.0 if z > 56.0 else 10.0 + 0.1 * x
	return HeightField.new(MapBaker.encode_height(h, N), WORLD, MapBaker.H_MIN, MapBaker.H_MAX)

static func zones() -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_R8)
	for j in N:
		for i in N:
			img.set_pixel(i, j, Color8(1 if i >= 64 else 0, 0, 0))
	return img

static func paths() -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_R8)
	for j in N:
		for i in range(62, 66):
			img.set_pixel(i, j, Color8(1, 0, 0))
	return img

static func context(water := Callable(), mk: Array = []) -> VegContext:
	return VegContext.new(field(), zones(), paths(), mk if not mk.is_empty() else markers(), cfg(), water)
