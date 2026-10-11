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


## 표식 없는 맥락 (정상·마을 제외가 배치 시험을 가리지 않게). 아주 먼 표식 하나만 둔다.
static func bare_context() -> VegContext:
	return context(Callable(), [{"kind": "start", "x": -5000.0, "z": -5000.0}])


## 경사 지도: h = clamp(40 + 0.9x, 2, 85) → x ≈ -42..50 가 normal.y ≈ 0.74 비탈, 양쪽은 평지
static func steep_context() -> VegContext:
	var h := PackedFloat32Array()
	h.resize(N * N)
	for j in N:
		for i in N:
			h[j * N + i] = clampf(40.0 + 0.9 * (float(i) - 64.0), 2.0, 85.0)
	var f := HeightField.new(MapBaker.encode_height(h, N), WORLD, MapBaker.H_MIN, MapBaker.H_MAX)
	return VegContext.new(f, zones(), paths(), [{"kind": "start", "x": -5000.0, "z": -5000.0}], cfg())
