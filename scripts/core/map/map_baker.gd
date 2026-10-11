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
const STREAM_SPREAD := 8             ## 개천 폭 추정: 중심선 거리를 퍼뜨리는 횟수 (칸)
const DIR_WINDOW := 3                ## 길 방향 추정 창 반경 (px)
const SMOOTH_RADIUS := 12.0
const DETAIL := 1.5
const SEED := 1

const REQUIRED_LAYERS := ["height", "markers"]


## layers: {"height": Image, "zones": Image, "paths": Image, "markers": Image} (zones·paths 는 없어도 됨).
## 반환: {height: PackedFloat32Array(m), zones: PackedByteArray, paths: PackedByteArray,
##        markers: Array[Dictionary], errors: PackedStringArray, warnings: PackedStringArray, world: float}
##        world: float, meta: {world, size, min_h, max_h}
## cfg (모두 선택): smooth_radius (기본 12), edge_sea (기본 true), min_h·max_h (기본 −16·90, 높이 한계),
##   peak_height (350), peak_radius (700), summit_radius (180), lake_radius (48), tower_radius (10) — MapStamps.apply 로 전달.
## errors 가 비어 있지 않으면 굽기 실패 (다른 값은 믿지 말 것).
static func bake(layers: Dictionary, size := 1024, world := 1024.0, cfg := {}) -> Dictionary:
	var result := {
		"height": PackedFloat32Array(), "zones": PackedByteArray(), "paths": PackedByteArray(),
		"markers": [], "errors": PackedStringArray(), "warnings": PackedStringArray(),
		"world": world, "meta": meta(cfg, size, world),
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
	var h := HeightBands.build(bands, size, cliff, float(cfg.get("smooth_radius", SMOOTH_RADIUS)), DETAIL, SEED, bool(cfg.get("edge_sea", true)))
	MapStamps.apply(h, size, world, markers, cfg)

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
		_dig_streams(h, paths, size)

	MapStamps.despike(h, size, world)      # P17: 맨 마지막 (도장·길·개천이 만든 얇은 지느러미까지)

	var lo: float = result["meta"]["min_h"]
	var hi: float = result["meta"]["max_h"]
	for i in size * size:
		h[i] = clampf(h[i], lo, hi)
	result["height"] = h
	result["zones"] = zones
	result["paths"] = paths
	return result


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


## 개천(4): V자 파기. 깊이 = STREAM_DIG × (가장자리 거리 − 1) / (중심선 거리 − 1) — 중앙 −2.5m, 칠한 가장자리 0.
## 가장자리 거리 = 개천 아닌 가장 가까운 칸까지 (3-4 체인퍼, 단위 1/3 칸). 중심선 거리 = 근처(STREAM_SPREAD 칸) 최댓값.
## 개천 칸만 훑어 큰 지도에서도 빠르다. 도장·길 처리 뒤에 호출한다.
static func _dig_streams(h: PackedFloat32Array, paths: PackedByteArray, size: int) -> void:
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
		h[i] -= STREAM_DIG * t


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
