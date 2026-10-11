class_name MapBaker
extends RefCounted
## 색칠 지도 이미지들 → 구운 데이터. 노드 비의존, 결정적 (같은 입력 = 같은 출력).
## 파이프라인: 띠 → 높이 (HeightBands) → 표식 도장 (MapStamps) → 길 효과.

const H_MIN := -16.0
const H_MAX := 90.0
const PREVIEW_SIZE := 512
const PATH_FLATTEN_HALF_M := 2.0     ## 길 가로 평균 반폭 (m)
const PATH_FLATTEN_MAX := 0.5        ## 흙길·포장길이 지형을 바꾸는 최대 높이 (m)
const AQUEDUCT_DIG := 1.5            ## 수로가 파내는 깊이 (m)
const DIR_WINDOW := 3                ## 길 방향 추정 창 반경 (px)
const SMOOTH_RADIUS := 12.0
const DETAIL := 1.5
const SEED := 1

const REQUIRED_LAYERS := ["height", "markers"]


## layers: {"height": Image, "zones": Image, "paths": Image, "markers": Image} (zones·paths 는 없어도 됨).
## 반환: {height: PackedFloat32Array(m), zones: PackedByteArray, paths: PackedByteArray,
##        markers: Array[Dictionary], errors: PackedStringArray, warnings: PackedStringArray, world: float}
## errors 가 비어 있지 않으면 굽기 실패 (다른 값은 믿지 말 것).
static func bake(layers: Dictionary, size := 1024, world := 1024.0) -> Dictionary:
	var result := {
		"height": PackedFloat32Array(), "zones": PackedByteArray(), "paths": PackedByteArray(),
		"markers": [], "errors": PackedStringArray(), "warnings": PackedStringArray(),
		"world": world,
	}
	var errors: PackedStringArray = result["errors"]
	for name in REQUIRED_LAYERS:
		if not layers.has(name) or layers[name] == null:
			errors.append("필수 지도 없음: %s.png" % name)
	for name in layers:
		var img: Image = layers[name]
		if img != null and img.get_width() != img.get_height():
			errors.append("%s.png 는 정사각형이어야 합니다 (현재 %d×%d)" % [name, img.get_width(), img.get_height()])
	if not errors.is_empty():
		return result

	# 표식
	var markers: Array = MarkerReader.read(layers["markers"], size, world)
	for msg in MarkerReader.validate(markers):
		if msg.begins_with(MarkerReader.WARNING_PREFIX):
			result["warnings"].append(msg)
		else:
			errors.append(msg)
	markers = MarkerReader.limit_sluices(markers)
	result["markers"] = markers

	# 높이
	var bands := MapLegend.load_layer(layers["height"], MapLegend.height_palette(), size)
	var cliff := PackedByteArray()
	cliff.resize(size * size)
	for i in size * size:
		if bands[i] == MapLegend.CLIFF_INDEX:
			cliff[i] = 1
	var h := HeightBands.build(bands, size, cliff, SMOOTH_RADIUS, DETAIL, SEED)
	MapStamps.apply(h, size, world, markers)

	# 구역 (비어 있음 = 초원 0)
	var zones := PackedByteArray()
	zones.resize(size * size)
	if layers.get("zones") != null:
		var zl := MapLegend.load_layer(layers["zones"], MapLegend.zone_palette(), size)
		for i in size * size:
			zones[i] = maxi(zl[i], 0)

	# 길 (구운 값 = 인덱스 + 1, 0 = 없음)
	var paths := PackedByteArray()
	paths.resize(size * size)
	if layers.get("paths") != null:
		var pl := MapLegend.load_layer(layers["paths"], MapLegend.path_palette(), size)
		for i in size * size:
			paths[i] = pl[i] + 1       # −1 → 0
		_apply_paths(h, paths, size, world)

	for i in size * size:
		h[i] = clampf(h[i], H_MIN, H_MAX)
	result["height"] = h
	result["zones"] = zones
	result["paths"] = paths
	return result


## 흙길·포장길(1, 2): 길 방향의 수직으로 ±2m 평균에 다가감 (변화 ≤ 0.5m). 수로(3): 1.5m 파냄.
static func _apply_paths(h: PackedFloat32Array, paths: PackedByteArray, size: int, world: float) -> void:
	var src := h.duplicate()
	var k := float(size - 1) / world          # px / m
	var half_steps := int(ceil(PATH_FLATTEN_HALF_M * k))
	var step_px := PATH_FLATTEN_HALF_M * k / maxf(half_steps, 1)
	for y in size:
		for x in size:
			var i := y * size + x
			var p := paths[i]
			if p == 0:
				continue
			if p == 3:
				h[i] = src[i] - AQUEDUCT_DIG
				continue
			# 길 방향 = 같은 종류(흙길·포장길) 칸들의 주축
			var n := 0
			var sx := 0.0
			var sy := 0.0
			var sxx := 0.0
			var syy := 0.0
			var sxy := 0.0
			for dy in range(maxi(-DIR_WINDOW, -y), mini(DIR_WINDOW, size - 1 - y) + 1):
				for dx in range(maxi(-DIR_WINDOW, -x), mini(DIR_WINDOW, size - 1 - x) + 1):
					var q := paths[i + dy * size + dx]
					if q == 1 or q == 2:
						n += 1
						sx += dx; sy += dy
						sxx += dx * dx; syy += dy * dy; sxy += dx * dy
			var ax := 0.0
			var ay := 1.0          # 방향이 불분명하면 아무 쪽이나 (결정적)
			if n >= 3:
				var cxx := sxx / n - (sx / n) * (sx / n)
				var cyy := syy / n - (sy / n) * (sy / n)
				var cxy := sxy / n - (sx / n) * (sy / n)
				var theta := 0.5 * atan2(2.0 * cxy, cxx - cyy)       # 주축 각
				ax = -sin(theta)     # 가로 방향 = 주축에 수직
				ay = cos(theta)
			var total := 0.0
			var cnt := 0
			for s in range(-half_steps, half_steps + 1):
				var sxp := clampi(int(round(x + ax * s * step_px)), 0, size - 1)
				var syp := clampi(int(round(y + ay * s * step_px)), 0, size - 1)
				total += src[syp * size + sxp]
				cnt += 1
			h[i] = src[i] + clampf(total / cnt - src[i], -PATH_FLATTEN_MAX, PATH_FLATTEN_MAX)


## 높이 (m) → RGB8 16비트 (R 상위·G 하위). HeightField(img, world, −16, 90) 가 그대로 읽는다.
static func encode_height(h: PackedFloat32Array, size: int) -> Image:
	var data := PackedByteArray()
	data.resize(size * size * 3)
	var scale := 255.0 / (H_MAX - H_MIN)
	for i in size * size:
		var t := clampf((h[i] - H_MIN) * scale, 0.0, 255.0)
		var r := int(t)
		var g := clampi(int(round((t - r) * 256.0)), 0, 255)
		if r == 255:
			g = 0
		data[i * 3] = r
		data[i * 3 + 1] = g
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)


## 확인용 위에서 본 지도 (512px): 구역 색 × 높이 음영, 바다, 길, 표식 점.
static func preview(baked: Dictionary, size: int) -> Image:
	var h: PackedFloat32Array = baked["height"]
	var zones: PackedByteArray = baked["zones"]
	var paths: PackedByteArray = baked["paths"]
	var out_n := PREVIEW_SIZE
	var stride := float(size) / out_n
	var data := PackedByteArray()
	data.resize(out_n * out_n * 3)
	var zone_cols: Array[Color] = MapLegend.zone_palette()
	var path_cols: Array[Color] = MapLegend.path_palette()
	var light := Vector3(-0.5, 0.7, -0.5).normalized()
	var world: float = float(baked.get("world", float(size)))
	var cell_m := world / maxf(size - 1, 1)     # 음영 계산용 칸 크기 (m)
	for oy in out_n:
		var sy := mini(int(oy * stride), size - 1)
		for ox in out_n:
			var sx := mini(int(ox * stride), size - 1)
			var i := sy * size + sx
			var hh := h[i]
			var xl := h[i - 1] if sx > 0 else hh
			var xr := h[i + 1] if sx < size - 1 else hh
			var zu := h[i - size] if sy > 0 else hh
			var zd := h[i + size] if sy < size - 1 else hh
			var nrm := Vector3(-(xr - xl) / (2.0 * cell_m), 1.0, -(zd - zu) / (2.0 * cell_m)).normalized()
			var shade := clampf(nrm.dot(light), 0.0, 1.0)
			var base: Color
			if hh < 0.0:
				base = Color8(0x4F, 0x81, 0xBD).lerp(Color8(0x1F, 0x3A, 0x5F), clampf(-hh / 12.0, 0.0, 1.0))
				shade = 0.85 + 0.15 * shade
			else:
				base = zone_cols[zones[i]]
			var c := base * (0.45 + 0.7 * shade)
			var pv := paths[i]
			if pv > 0:
				c = path_cols[pv - 1]
			var o := (oy * out_n + ox) * 3
			data[o] = clampi(int(c.r * 255.0), 0, 255)
			data[o + 1] = clampi(int(c.g * 255.0), 0, 255)
			data[o + 2] = clampi(int(c.b * 255.0), 0, 255)
	var img := Image.create_from_data(out_n, out_n, false, Image.FORMAT_RGB8, data)
	for m in baked["markers"]:
		var px := int(round((m["x"] / world + 0.5) * (out_n - 1)))
		var py := int(round((m["z"] / world + 0.5) * (out_n - 1)))
		img.fill_rect(Rect2i(px - 4, py - 4, 9, 9), Color.BLACK)
		img.fill_rect(Rect2i(px - 3, py - 3, 7, 7), MapLegend.MARKERS[m["kind"]])
	return img
