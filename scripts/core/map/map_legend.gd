class_name MapLegend
extends RefCounted
## 색칠 지도 범례 (설계서 2026-10-12-painted-map-terrain-design.md 3장).
## 픽셀 = 가장 가까운 범례색. RGB 거리(0~255) > THRESHOLD, 흰색, 투명(α < 0.5) = 비어 있음(−1).

const THRESHOLD := 60.0
const WHITE_MIN := 235   ## 세 채널 모두 이 이상이면 흰 종이(비어 있음)

## 높이 띠 (순서 = 인덱스). 마지막 CLIFF_INDEX = 절벽 선 (높이 없음).
const HEIGHT := [
	{"color": Color8(0x1F, 0x3A, 0x5F), "name": "deep_sea", "h": -14.0},
	{"color": Color8(0x4F, 0x81, 0xBD), "name": "shallow_sea", "h": -4.0},
	{"color": Color8(0xF2, 0xE6, 0xB8), "name": "beach", "h": 1.0},
	{"color": Color8(0x9B, 0xBB, 0x59), "name": "plain", "h": 6.0},
	{"color": Color8(0xC4, 0xD7, 0x9B), "name": "hill", "h": 20.0},
	{"color": Color8(0xE3, 0xB4, 0x6A), "name": "plateau", "h": 45.0},
	{"color": Color8(0xB0, 0x7A, 0x4A), "name": "mountain", "h": 90.0},
	{"color": Color8(0x7F, 0x6A, 0x93), "name": "high_mountain", "h": 160.0},
]
const CLIFF := Color8(0xE0, 0x21, 0x8A)
const CLIFF_INDEX := 8

## 식생 구역 (인덱스 0 = 초원 = 비어 있을 때 기본값)
const ZONES := [
	{"color": Color8(0xA9, 0xD1, 0x8E), "name": "meadow"},
	{"color": Color8(0x54, 0x82, 0x35), "name": "broadleaf"},
	{"color": Color8(0x37, 0x56, 0x23), "name": "conifer"},
	{"color": Color8(0x5F, 0xB3, 0xB3), "name": "wetland"},
	{"color": Color8(0xA6, 0xA6, 0xA6), "name": "highland"},
	{"color": Color8(0xFF, 0xE6, 0x99), "name": "coast"},
	{"color": Color8(0xC5, 0x5A, 0x11), "name": "wasteland"},
]

## 길 (구운 값 = 인덱스 + 1, 0 = 길 없음)
const PATHS := [
	{"color": Color8(0x8B, 0x5A, 0x2B), "name": "dirt"},
	{"color": Color8(0x40, 0x40, 0x40), "name": "paved"},
	{"color": Color8(0x2E, 0x75, 0xB6), "name": "aqueduct"},
	{"color": Color8(0x6F, 0xA8, 0xDC), "name": "stream"},      ## 개천 (마른 물길, 구운 값 4)
]

const MARKERS := {
	"start": Color8(0x00, 0x00, 0x00),
	"tower": Color8(0xFF, 0x00, 0x00),
	"lake": Color8(0x00, 0xB0, 0xF0),
	"sluice": Color8(0xFF, 0x8C, 0x00),
	"village": Color8(0xFF, 0xFF, 0x00),        ## 해안 마을 (평탄화)
	"hill_village": Color8(0xFF, 0xC0, 0x00),   ## 산마을 (도장 없음)
	"ruin": Color8(0x70, 0x30, 0xA0),
	"lookout": Color8(0xFF, 0x66, 0xCC),
	"bridge": Color8(0x00, 0xFF, 0x00),
}


static func _colors(table: Array) -> Array[Color]:
	var out: Array[Color] = []
	for e in table:
		out.append(e["color"])
	return out


## 높이 띠 8색 + 절벽 선 (인덱스 8)
static func height_palette() -> Array[Color]:
	var p := _colors(HEIGHT)
	p.append(CLIFF)
	return p


static func zone_palette() -> Array[Color]:
	return _colors(ZONES)


static func path_palette() -> Array[Color]:
	return _colors(PATHS)


static func marker_kinds() -> Array:
	return MARKERS.keys()


static func marker_palette() -> Array[Color]:
	var out: Array[Color] = []
	for k in MARKERS:
		out.append(MARKERS[k])
	return out


static func classify(c: Color, palette: Array[Color]) -> int:
	if c.a < 0.5 or (c.r8 >= WHITE_MIN and c.g8 >= WHITE_MIN and c.b8 >= WHITE_MIN):
		return -1
	var best := -1
	var best_d := THRESHOLD * THRESHOLD
	for i in palette.size():
		var p := palette[i]
		var dr := float(c.r8 - p.r8)
		var dg := float(c.g8 - p.g8)
		var db := float(c.b8 - p.b8)
		var d := dr * dr + dg * dg + db * db
		if d <= best_d:
			best_d = d
			best = i
	return best


## 이미지 → size×size 인덱스 배열(행 우선). 정사각형이 아니면 오류 후 빈 배열.
static func load_layer(img: Image, palette: Array[Color], size := 1024) -> PackedInt32Array:
	var out := PackedInt32Array()
	if img == null or img.get_width() != img.get_height():
		push_error("색칠 지도는 정사각형이어야 합니다: %s" % (str(img.get_size()) if img else "null"))
		return out
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != size:
		im.resize(size, size, Image.INTERPOLATE_NEAREST)
	out.resize(size * size)
	# 같은 색이 넓게 칠해지므로 색 → 인덱스 캐시로 판정 횟수를 줄인다.
	var cache := {}
	var data := im.get_data()
	for i in size * size:
		var key := (data[i * 4] << 24) | (data[i * 4 + 1] << 16) | (data[i * 4 + 2] << 8) | data[i * 4 + 3]
		var k = cache.get(key)
		if k == null:
			k = classify(Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]), palette)
			cache[key] = k
		out[i] = k
	return out
