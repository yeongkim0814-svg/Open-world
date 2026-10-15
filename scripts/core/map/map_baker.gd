class_name MapBaker
extends RefCounted
## 색칠 지도 이미지들 → 구운 데이터. 노드 비의존, 결정적 (같은 입력 = 같은 출력).
## 파이프라인: 띠 → 평활화 (HeightBands) → 봉우리 → 저수호·탑·마을 (MapStamps) → 길 효과 (흙길·포장길 평탄화, 수로 파기) → 개천 파기 → 지느러미 제거.

const H_MIN := -16.0                 ## 구운 높이 범위 기본값 (cfg min_h·max_h 로 바꿈)
const H_MAX := 90.0
const PREVIEW_SIZE := 512
const PATH_CROSS_M := 4.0           ## 길 가로 단면을 재는 반폭 (m): 이 안의 길 칸 평균 = 길바닥 높이
const PATH_CUT_MAX := 3.0            ## 길바닥이 깎거나 메우는 최대 높이 (m) — 넘으면 그만큼만 (아주 가파른 곳)
const PATH_SHOULDER_M := 5.0         ## 길섶: 길 옆에서 원지형으로 이어지는 폭 (m) — 오르막 쪽은 깎인 둑, 내리막 쪽은 메운 둑
const AQUEDUCT_DIG := 1.5            ## 수로가 파내는 깊이 (m)
const STREAM_DIG := 2.5              ## 개천 중앙 깊이 (m), V자로 가장자리 0
const STREAM_SPREAD := 14            ## 개천 폭 추정: 중심선 거리를 퍼뜨리는 횟수 (칸) — 반폭이 이보다 넓으면 가운데가 평평해짐
const STEEP_PATH_DEG := 50.0         ## 굽기 뒤 이보다 가파른 길 칸은 경고 (절벽을 지나는 길; 걷기 한계 60도, 갈지자 모퉁이는 40도대)
const STEEP_PATH_MIN_PX := 2         ## 한 곳(32m 칸)에 이만큼 넘어야 경고
const DIR_WINDOW := 3                ## 길 방향 추정 창 반경 (px)
const SMOOTH_RADIUS := 12.0
const DETAIL := 1.5
const SEED := 1

const REQUIRED_LAYERS := ["height", "markers"]     ## "height" 는 "heightmap" 이 있으면 없어도 됨


## layers: {"height": Image, "heightmap": Image, "zones": Image, "paths": Image, "markers": Image} (zones·paths 는 없어도 됨).
## heightmap (선택) = encode_height 와 같은 RGB8 16비트 높이 (R 상위·G 하위, cfg min_h~max_h). 있으면 height 대신 쓴다 (둘 다 있으면 heightmap 이 이김).
##   크기가 size 와 다르면 높이 값으로 풀어 쌍선형 보간으로 맞춘다.
## moat (선택) = 해자 모양 (흑백: 0 없음, 128 물, 255 탑 섬). 있으면 원형 저수호·탑 도장 대신 이 모양을 쓴다
##   (높이는 heightmap 에 이미 파여 있어야 함 — tools/sketch_to_map.py). 결과 moat = MOAT_* 값 (없으면 빈 배열).
## 반환: {height: PackedFloat32Array(m), zones: PackedByteArray, paths: PackedByteArray, moat: PackedByteArray,
##        markers: Array[Dictionary], errors: PackedStringArray, warnings: PackedStringArray, world: float}
##        world: float, meta: {world, size, min_h, max_h}
## cfg (모두 선택): smooth_radius (기본 12), edge_sea (기본 true), min_h·max_h (기본 −16·90, 높이 한계),
##   peak_height (350), peak_radius (700), summit_radius (180), lake_radius (48), tower_radius (10) — MapStamps.apply 로 전달.
##   stream_dig (2.5) — 개천 가운데 깊이 (m).
## errors 가 비어 있지 않으면 굽기 실패 (다른 값은 믿지 말 것).
static func bake(layers: Dictionary, size := 1024, world := 1024.0, cfg := {}) -> Dictionary:
	var result := {
		"height": PackedFloat32Array(), "zones": PackedByteArray(), "paths": PackedByteArray(), "moat": PackedByteArray(),
		"markers": [], "errors": PackedStringArray(), "warnings": PackedStringArray(),
		"world": world, "meta": meta(cfg, size, world),
	}
	var errors: PackedStringArray = result["errors"]
	for name in REQUIRED_LAYERS:
		if name == "height" and layers.get("heightmap") != null:
			continue
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
	var h: PackedFloat32Array
	if layers.get("heightmap") != null:
		if layers.get("height") != null:
			result["warnings"].append(MarkerReader.WARNING_PREFIX + "heightmap.png 가 있어 height.png 는 무시합니다")
		h = decode_heightmap(layers["heightmap"], size, float(result["meta"]["min_h"]), float(result["meta"]["max_h"]))
	else:
		var bands := MapLegend.load_layer(layers["height"], MapLegend.height_palette(), size)
		var cliff := PackedByteArray()
		cliff.resize(size * size)
		for i in size * size:
			if bands[i] == MapLegend.CLIFF_INDEX:
				cliff[i] = 1
		h = HeightBands.build(bands, size, cliff, float(cfg.get("smooth_radius", SMOOTH_RADIUS)), DETAIL, SEED, bool(cfg.get("edge_sea", true)))

	# 길 (구운 값 = 인덱스 + 1, 0 = 없음) — 봉우리 틈 자리를 정하므로 도장보다 먼저 읽는다
	var paths := PackedByteArray()
	paths.resize(size * size)
	if layers.get("paths") != null:
		var pl := MapLegend.load_layer(layers["paths"], MapLegend.path_palette(), size)
		for i in size * size:
			paths[i] = pl[i] + 1       # −1 → 0
	var moat := PackedByteArray()
	if layers.get("moat") != null:
		moat = decode_moat(layers["moat"], size)
	MapStamps.apply(h, size, world, markers, cfg, paths, moat)
	_clear_paths_in_lakes(paths, size, world, markers, moat)

	# 구역 (비어 있음 = 초원 0)
	var zones := PackedByteArray()
	zones.resize(size * size)
	if layers.get("zones") != null:
		var zl := MapLegend.load_layer(layers["zones"], MapLegend.zone_palette(), size)
		for i in size * size:
			zones[i] = maxi(zl[i], 0)

	if layers.get("paths") != null:
		_apply_paths(h, paths, size, world)
		_dig_streams(h, paths, size, float(cfg.get("stream_dig", STREAM_DIG)))

	MapStamps.despike(h, size, world)      # P17: 맨 마지막 (도장·길·개천이 만든 얇은 지느러미까지)
	var warns: PackedStringArray = result["warnings"]
	warns.append_array(steep_path_warnings(h, paths, size, world))
	result["warnings"] = warns

	var lo: float = result["meta"]["min_h"]
	var hi: float = result["meta"]["max_h"]
	for i in size * size:
		h[i] = clampf(h[i], lo, hi)
	result["height"] = h
	result["zones"] = zones
	result["paths"] = paths
	result["moat"] = moat
	return result


## 해자 모양 이미지 → MapStamps.MOAT_* 배열 (size², 최근접 크기 맞춤). 밝기 ≥ 192 섬, ≥ 64 물.
static func decode_moat(img: Image, size: int) -> PackedByteArray:
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_L8)
	if im.get_width() != size:
		im.resize(size, size, Image.INTERPOLATE_NEAREST)
	var src := im.get_data()
	var out := PackedByteArray()
	out.resize(size * size)
	for i in size * size:
		out[i] = MapStamps.MOAT_ISLAND if src[i] >= 192 else (MapStamps.MOAT_WATER if src[i] >= 64 else MapStamps.MOAT_NONE)
	return out


## MOAT_* 배열 → 저장용 흑백 이미지 (0·128·255, decode_moat 로 되읽힘)
static func encode_moat(moat: PackedByteArray, size: int) -> Image:
	var data := PackedByteArray()
	data.resize(size * size)
	for i in size * size:
		data[i] = [0, 128, 255][moat[i]]
	return Image.create_from_data(size, size, false, Image.FORMAT_L8, data)


## 구운 데이터 메타 (baked/meta.json): 게임이 world·높이 범위를 읽는다. world·size 는 인자가 우선.
static func meta(cfg: Dictionary, size: int, world: float) -> Dictionary:
	return {
		"world": world, "size": size,
		"min_h": float(cfg.get("min_h", H_MIN)), "max_h": float(cfg.get("max_h", H_MAX)),
	}


## 흙길·포장길(1, 2): 비탈을 깎고 메워 가로로 수평인 길바닥을 만든다 (길 방향으로는 지형을 따라 오르내림).
## 길바닥 높이 = 길 방향의 수직선 위 ±PATH_CROSS_M 안 길 칸들의 원지형 평균 (변화 ≤ PATH_CUT_MAX).
## 길섶 PATH_SHOULDER_M: 가장 가까운 길 칸 높이 → 원지형으로 부드럽게 (개천·수로 칸은 건드리지 않음).
## 수로(3): 1.5m 파냄. 개천(4)은 _dig_streams 가 맨 뒤에 판다.
static func _apply_paths(h: PackedFloat32Array, paths: PackedByteArray, size: int, world: float) -> void:
	var src := h.duplicate()
	var k := float(size - 1) / world          # px / m
	var cross_steps := int(ceil(PATH_CROSS_M * k * 2.0))
	var step_px := PATH_CROSS_M * k / maxf(cross_steps, 1)
	var big := 1 << 28
	var dist := PackedInt32Array()            # 길섶 거리 (1/3 칸 단위, 3-4 체인퍼), 길 칸 = 0
	dist.resize(size * size)
	dist.fill(big)
	var target := PackedFloat32Array()        # 가장 가까운 길 칸의 길바닥 높이
	target.resize(size * size)
	for y in size:
		for x in size:
			var i := y * size + x
			var p := paths[i]
			if p == 3:
				h[i] = src[i] - AQUEDUCT_DIG
				continue
			if p != 1 and p != 2:
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
			var last := -1
			for st in range(-cross_steps, cross_steps + 1):
				var sxp := clampi(int(round(x + ax * st * step_px)), 0, size - 1)
				var syp := clampi(int(round(y + ay * st * step_px)), 0, size - 1)
				var si := syp * size + sxp
				if si == last:
					continue      # 같은 칸을 두 번 세지 않음 (단면 위치마다 가중치가 달라지면 길이 기움)
				last = si
				var q := paths[si]
				if q == 1 or q == 2:
					total += src[syp * size + sxp]
					cnt += 1
			var t := src[i] + clampf(total / maxi(cnt, 1) - src[i], -PATH_CUT_MAX, PATH_CUT_MAX)
			h[i] = t
			target[i] = t
			dist[i] = 0
	# 길섶: 거리·길바닥 높이를 함께 퍼뜨린다 (앞·뒤 두 번)
	var lim := int(ceil(PATH_SHOULDER_M * k)) * 3 + 4
	for pass_i in 2:
		var y0 := 0 if pass_i == 0 else size - 1
		var y1 := size if pass_i == 0 else -1
		var sgn := 1 if pass_i == 0 else -1
		var y := y0
		while y != y1:
			var x := 0 if pass_i == 0 else size - 1
			while x >= 0 and x < size:
				var i := y * size + x
				if dist[i] != 0:
					for o: Vector3i in [Vector3i(-sgn, 0, 3), Vector3i(0, -sgn, 3), Vector3i(-sgn, -sgn, 4), Vector3i(sgn, -sgn, 4)]:
						var nx := x + o.x
						var ny := y + o.y
						if nx < 0 or nx >= size or ny < 0 or ny >= size:
							continue
						var j := ny * size + nx
						if dist[j] + o.z < dist[i] and dist[j] + o.z <= lim:
							dist[i] = dist[j] + o.z
							target[i] = target[j]
				x += sgn
			y += sgn
	var shoulder_px := PATH_SHOULDER_M * k
	for i in size * size:
		var p := paths[i]
		if p != 0 or dist[i] == 0 or dist[i] >= big:
			continue
		var w := smoothstep(0.0, 1.0, (dist[i] / 3.0) / shoulder_px)
		h[i] = lerpf(target[i], src[i], w)


## 개천(4): V자 파기 (cfg stream_dig, 기본 2.5m). 깊이 = dig × (가장자리 거리 − 1) / (중심선 거리 − 1) — 중앙 −2.5m, 칠한 가장자리 0.
## 가장자리 거리 = 개천 아닌 가장 가까운 칸까지 (3-4 체인퍼, 단위 1/3 칸). 중심선 거리 = 근처(STREAM_SPREAD 칸) 최댓값.
## 개천 칸만 훑어 큰 지도에서도 빠르다. 도장·길 처리 뒤에 호출한다.
static func _dig_streams(h: PackedFloat32Array, paths: PackedByteArray, size: int, dig := STREAM_DIG) -> void:
	var cells := PackedInt32Array()
	for i in size * size:
		if paths[i] == 4:
			cells.append(i)
	if cells.is_empty():
		return
	var d := PackedInt32Array()
	d.resize(size * size)       # 0 = 개천 아님 (가장자리 거리 0)
	var big := 1 << 20
	for i in cells:
		d[i] = big
	for i in cells:             # 앞 방향 (인덱스 오름차순)
		var x := i % size
		var v := d[i]
		if x > 0:
			v = mini(v, d[i - 1] + 3)
		if i >= size:
			v = mini(v, d[i - size] + 3)
			if x > 0:
				v = mini(v, d[i - size - 1] + 4)
			if x < size - 1:
				v = mini(v, d[i - size + 1] + 4)
		d[i] = v
	for ci in range(cells.size() - 1, -1, -1):     # 뒤 방향
		var i := cells[ci]
		var x := i % size
		var v := d[i]
		if x < size - 1:
			v = mini(v, d[i + 1] + 3)
		if i < size * (size - 1):
			v = mini(v, d[i + size] + 3)
			if x < size - 1:
				v = mini(v, d[i + size + 1] + 4)
			if x > 0:
				v = mini(v, d[i + size - 1] + 4)
		d[i] = v
	# 지도 가장자리는 특별 취급 안 함 (밖으로 이어지는 개천은 가장자리에서 얕아지지 않는다)
	# 중심선 거리: 이웃 8방향 최댓값을 STREAM_SPREAD 번 퍼뜨림 (개천 칸 안에서만)
	var m := d.duplicate()
	var nxt := d.duplicate()
	for _it in STREAM_SPREAD:
		for i in cells:
			var x := i % size
			var best := m[i]
			if x > 0:
				best = maxi(best, m[i - 1])
				if i >= size:
					best = maxi(best, m[i - size - 1])
				if i < size * (size - 1):
					best = maxi(best, m[i + size - 1])
			if x < size - 1:
				best = maxi(best, m[i + 1])
				if i >= size:
					best = maxi(best, m[i - size + 1])
				if i < size * (size - 1):
					best = maxi(best, m[i + size + 1])
			if i >= size:
				best = maxi(best, m[i - size])
			if i < size * (size - 1):
				best = maxi(best, m[i + size])
			nxt[i] = best
		var t := m
		m = nxt
		nxt = t
	for i in cells:
		var edge_d := d[i]
		var centre := m[i]
		var t := 1.0
		if centre > 3:
			t = clampf(float(edge_d - 3) / float(centre - 3), 0.0, 1.0)
		h[i] -= dig * t


## encode_height 의 역: RGB8(또는 RGBA8) 16비트 높이 이미지 → size×size 높이 (m).
## 크기가 다르면 높이 값으로 먼저 풀고 나서 쌍선형 보간 (양 끝 칸이 끝 칸에 맞는 HeightField 와 같은 배치).
static func decode_heightmap(img: Image, size: int, min_h := H_MIN, max_h := H_MAX) -> PackedFloat32Array:
	var src := img.duplicate() as Image
	var gray := src.get_format() == Image.FORMAT_L8 or src.get_format() == Image.FORMAT_R8
	src.convert(Image.FORMAT_RGBA8)
	var sw := src.get_width()
	var sh := src.get_height()
	var data := src.get_data()
	var scale := (max_h - min_h) / 255.0
	var hm := PackedFloat32Array()
	hm.resize(sw * sh)
	for i in sw * sh:
		var lo := 0.0 if gray else data[i * 4 + 1] / 256.0
		hm[i] = min_h + (data[i * 4] + lo) * scale
	if sw == size and sh == size:
		return hm
	var out := PackedFloat32Array()
	out.resize(size * size)
	var kx := float(sw - 1) / maxf(size - 1, 1)
	var ky := float(sh - 1) / maxf(size - 1, 1)
	for y in size:
		var fy := y * ky
		var y0 := int(fy)
		var y1 := mini(y0 + 1, sh - 1)
		var ty := fy - y0
		for x in size:
			var fx := x * kx
			var x0 := int(fx)
			var x1 := mini(x0 + 1, sw - 1)
			var tx := fx - x0
			out[y * size + x] = lerpf(lerpf(hm[y0 * sw + x0], hm[y0 * sw + x1], tx), lerpf(hm[y1 * sw + x0], hm[y1 * sw + x1], tx), ty)
	return out


## 높이 (m) → RGB8 16비트 (R 상위·G 하위). HeightField(img, world, min_h, max_h) 가 그대로 읽는다.
static func encode_height(h: PackedFloat32Array, size: int, min_h := H_MIN, max_h := H_MAX) -> Image:
	var data := PackedByteArray()
	data.resize(size * size * 3)
	var scale := 255.0 / (max_h - min_h)
	for i in size * size:
		var t := clampf((h[i] - min_h) * scale, 0.0, 255.0)
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


## 저수호 수면 반경 + 2m 안의 길 칸을 지운다 (길이 해자 안쪽 벽·물속으로 이어지지 않게, 둑 꼭대기에서 끝남).
static func _clear_paths_in_lakes(paths: PackedByteArray, size: int, world: float, markers: Array, moat := PackedByteArray()) -> void:
	if not moat.is_empty():       # 모양 해자: 물·섬 칸의 길을 지운다
		for i in size * size:
			if moat[i] != MapStamps.MOAT_NONE and (paths[i] == 1 or paths[i] == 2):
				paths[i] = 0
		return
	var k := float(size - 1) / world
	for m in markers:
		if m["kind"] != "lake" or not m.has("radius"):
			continue
		var r: float = float(m["radius"]) + 2.0
		var cx: float = m["x"]
		var cz: float = m["z"]
		var x0 := maxi(0, int(floor((cx - r) * k + (size - 1) * 0.5)))
		var x1 := mini(size - 1, int(ceil((cx + r) * k + (size - 1) * 0.5)))
		var z0 := maxi(0, int(floor((cz - r) * k + (size - 1) * 0.5)))
		var z1 := mini(size - 1, int(ceil((cz + r) * k + (size - 1) * 0.5)))
		for pz in range(z0, z1 + 1):
			var dz := (float(pz) / (size - 1) - 0.5) * world - cz
			for px in range(x0, x1 + 1):
				var dx := (float(px) / (size - 1) - 0.5) * world - cx
				var i := pz * size + px
				if dx * dx + dz * dz < r * r and (paths[i] == 1 or paths[i] == 2):
					paths[i] = 0


## 굽기 뒤 STEEP_PATH_DEG 보다 가파른 흙길·포장길 칸을 32m 칸으로 묶어 경고 문장으로 (지도 고칠 곳).
static func steep_path_warnings(h: PackedFloat32Array, paths: PackedByteArray, size: int, world: float) -> PackedStringArray:
	var out := PackedStringArray()
	if paths.size() != size * size:
		return out
	var cell := world / (size - 1)
	var lim := tan(deg_to_rad(STEEP_PATH_DEG))
	var counts := {}
	var keys: Array[Vector2i] = []
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			var i := z * size + x
			if not (_is_road(paths[i]) and _is_road(paths[i - 1]) and _is_road(paths[i + 1]) and _is_road(paths[i - size]) and _is_road(paths[i + size])):
				continue      # 길 안쪽 칸만 (길 가장자리는 깎인 둑 경사가 섞여 잘못 잡힘)
			var gx := (h[i + 1] - h[i - 1]) / (2.0 * cell)
			var gz := (h[i + size] - h[i - size]) / (2.0 * cell)
			if gx * gx + gz * gz <= lim * lim:
				continue
			var key := Vector2i(int(floor(((float(x) / (size - 1) - 0.5) * world) / 32.0)), int(floor(((float(z) / (size - 1) - 0.5) * world) / 32.0)))
			if not counts.has(key):
				counts[key] = 0
				keys.append(key)
			counts[key] += 1
	for key in keys:
		if counts[key] >= STEEP_PATH_MIN_PX:
			out.append(MarkerReader.WARNING_PREFIX + "가파른 길(%.0f도 넘음) 근처 (%d, %d) — 절벽 선을 피하거나 길을 돌리세요" % [STEEP_PATH_DEG, key.x * 32 + 16, key.y * 32 + 16])
	return out


static func _is_road(v: int) -> bool:
	return v == 1 or v == 2
