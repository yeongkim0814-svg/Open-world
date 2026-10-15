class_name MapStamps
extends RefCounted
## 표식 위치에 정확한 모양을 찍는 도장 (M4 수치). 높이 배열을 제자리에서 고친다.
## 순서: 저수호 → 탑 섬 → 마을 (산마을 hill_village 는 도장 없음). 모든 거리는 미터, 좌표는 HeightField 관례.
## 저수호·탑은 주변 지면 기준 상대 높이. 계산한 값은 표식 딕셔너리에 기록한다:
## 저수호 m["crest"] (둑 꼭대기 높이), 탑 m["top"] (섬 윗면 높이) — markers.json 으로 나간다.

const LAKE_WALL_R := 48.0       ## 저수호 수면 반경 기본값 (= 안쪽 벽 끝 = 둑 안쪽). cfg lake_radius 로 바꿈
const LAKE_FLOOR_INSET := 2.0   ## 분지 바닥 평탄 반경 = 수면 반경 − 2
const DIKE_WIDTH := 12.0        ## 둑 꼭대기 폭: 수면 반경 ~ +12
const SLOPE_WIDTH := 18.0       ## 바깥 비탈: 둑 바깥 끝 + 18m 에 걸쳐 원지형으로
const CREST_RISE := 4.0         ## 둑 꼭대기 = 주변 지면(고리 중앙값) + 4m (설계서 P12)
const LAKE_DEPTH := 22.0        ## 분지 바닥 = 꼭대기 − 22m
const RING_R0 := 60.0           ## 주변 지면을 재는 고리 (m): 둑 바깥 끝 근처부터 20m 폭
const RING_R1 := 80.0
const TOWER_R := 10.0           ## 탑 섬 반경 기본값 (cfg tower_radius)
const TOWER_BLEND := 4.0
const TOWER_RISE := 2.0         ## 탑 섬 윗면 = 둑 꼭대기 + 2m
const VILLAGE_R := 40.0
const VILLAGE_BLEND := 15.0

# 봉우리 (설계서 P18). 칠한 높이에 더한다.
const PEAK_HEIGHT := 350.0
const PEAK_RADIUS := 700.0
const SUMMIT_RADIUS := 180.0
const CLIFF_WIDTH := 48.0           ## 정상 아래 절벽대 폭 (m)
const CLIFF_DROP := 90.0            ## 절벽대 높이 (m): 평균 경사 약 62도
const GAP_COUNT := 3                ## 틈 최소 개수 (길이 더 많이 지나면 더 많아짐)
const GAP_MERGE := 0.35             ## 이 각(약 20도) 안의 길은 한 틈으로
const GAP_MIN_SEP := 0.87           ## 시드로 채우는 틈은 기존 틈과 50도 이상 떨어짐
const GAP_FULL_HALF := 0.1222       ## 틈 완전 경사로 반각 (7도)
const GAP_BLEND := 0.0524           ## 틈 가장자리 전이 (3도)
const SUMMIT_FADE := 100.0          ## 정상 평탄 보정(원지형 → 기준 높이)이 사라지는 거리
const FALL_POWER := 1.3             ## 절벽 아래 오목한 비탈 지수 (1.3: 절벽 바로 아래 약 30도)
const SPUR_SLOPE := 0.577           ## 틈 경사로 기울기 (tan 30도): 절벽대 안에서만
const SPUR_FLANK := 0.47            ## 지맥 옆면 기울기 (tan 25도) — 옆면도 걸을 만한 넓은 능선
const SPUR_LEN := 400.0             ## 절벽대 아래 틈 능선(지맥)이 원래 비탈로 녹아드는 거리 (m)
const RIDGE_AMP := 16.0             ## 방사형 능선·골짜기 최대 진폭 (m)
const RIDGE_FADE_IN := 90.0
const ANGLE_STEPS := 1440

# 지느러미 제거 (P17)
const DESPIKE_RISE := 6.0
const DESPIKE_RING := 4.0


## cfg (선택): lake_radius(48), tower_radius(10), peak_height(350), peak_radius(700), summit_radius(180).
## paths (선택): 구운 길 인덱스 (1 흙길·2 포장길) — 봉우리 절벽대를 지나는 길 자리에 틈을 낸다.
static func apply(h: PackedFloat32Array, size: int, world: float, markers: Array, cfg := {}, paths := PackedByteArray()) -> void:
	var lake_r := float(cfg.get("lake_radius", LAKE_WALL_R))
	var tower_r := float(cfg.get("tower_radius", TOWER_R))
	for m in markers:
		if m["kind"] == "peak":
			var summit_r := float(cfg.get("summit_radius", SUMMIT_RADIUS))
			var roads := road_crossings(paths, size, world, m["x"], m["z"], summit_r + 8.0, summit_r + CLIFF_WIDTH - 8.0)
			_stamp_peak(h, size, world, m, float(cfg.get("peak_height", PEAK_HEIGHT)),
				float(cfg.get("peak_radius", PEAK_RADIUS)), summit_r, roads)
	var orig := h.duplicate()      # 봉우리까지 찍은 지형 (고리 중앙값은 이것으로 잰다)
	var lakes: Array = []
	for m in markers:
		if m["kind"] == "lake":
			var ring0 := lake_r + DIKE_WIDTH
			var crest := ring_median(orig, size, world, m["x"], m["z"], ring0, ring0 + (RING_R1 - RING_R0)) + CREST_RISE
			m["crest"] = crest
			m["radius"] = lake_r
			lakes.append(m)
			_stamp_lake(h, size, world, m["x"], m["z"], crest, crest - LAKE_DEPTH, lake_r)
	for m in markers:
		if m["kind"] == "tower":
			for lk in lakes:      # 해자 안의 탑은 해자 한가운데로 (점 두 개는 붙여 찍을 수 없어 조금 떨어져 있다)
				if Vector2(m["x"] - lk["x"], m["z"] - lk["z"]).length() <= float(lk["radius"]):
					m["x"] = lk["x"]
					m["z"] = lk["z"]
			var top := _tower_top(orig, size, world, m, lakes, tower_r)
			m["top"] = top
			_stamp_tower(h, size, world, m["x"], m["z"], top, tower_r)
	for m in markers:
		if m["kind"] == "village":
			_stamp_village(h, size, world, m["x"], m["z"])


## 격자 칸 (px, pz) 의 세계 좌표
static func _w(p: int, size: int, world: float) -> float:
	return (float(p) / float(maxi(size - 1, 1)) - 0.5) * world


## 반경 r (m) 이 덮는 칸 범위 [x0, x1] × [z0, z1]
static func _box(size: int, world: float, cx: float, cz: float, r: float) -> Rect2i:
	var k := float(size - 1) / world
	var x0 := maxi(0, int(floor((cx - r) * k + (size - 1) * 0.5)))
	var x1 := mini(size - 1, int(ceil((cx + r) * k + (size - 1) * 0.5)))
	var z0 := maxi(0, int(floor((cz - r) * k + (size - 1) * 0.5)))
	var z1 := mini(size - 1, int(ceil((cz + r) * k + (size - 1) * 0.5)))
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


## 중심에서 r0~r1 m 고리 칸들의 높이 중앙값 (지도 밖 칸은 제외, 칸이 없으면 중심 높이).
static func ring_median(src: PackedFloat32Array, size: int, world: float, cx: float, cz: float, r0 := RING_R0, r1 := RING_R1) -> float:
	var b := _box(size, world, cx, cz, r1)
	var vals := PackedFloat32Array()
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d2 := dx * dx + dz * dz
			if d2 >= r0 * r0 and d2 <= r1 * r1:
				vals.append(src[pz * size + px])
	if vals.is_empty():
		var k := float(size - 1) / world
		var ix := clampi(int(round(cx * k + (size - 1) * 0.5)), 0, size - 1)
		var iz := clampi(int(round(cz * k + (size - 1) * 0.5)), 0, size - 1)
		return src[iz * size + ix]
	vals.sort()
	var n := vals.size()
	return vals[n / 2] if n % 2 == 1 else 0.5 * (vals[n / 2 - 1] + vals[n / 2])


## 탑 섬 윗면: 탑이 저수호 분지 안(둑 안쪽)이면 그 호수 꼭대기 + 2, 아니면 탑 자리 고리 중앙값 + 4 + 2.
static func _tower_top(orig: PackedFloat32Array, size: int, world: float, tower: Dictionary, lakes: Array, tower_r: float) -> float:
	for lk in lakes:
		var dx: float = tower["x"] - lk["x"]
		var dz: float = tower["z"] - lk["z"]
		if sqrt(dx * dx + dz * dz) <= float(lk["radius"]):
			return float(lk["crest"]) + TOWER_RISE
	var ring0 := maxf(RING_R0, tower_r + TOWER_BLEND + 10.0)      # 섬·가장자리 밖에서 잰다
	return ring_median(orig, size, world, tower["x"], tower["z"], ring0, ring0 + (RING_R1 - RING_R0)) + CREST_RISE + TOWER_RISE


static func _stamp_lake(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float, crest: float, floor_h: float, radius := LAKE_WALL_R) -> void:
	var b := _box(size, world, cx, cz, radius + DIKE_WIDTH + SLOPE_WIDTH)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			var i := pz * size + px
			h[i] = lake_profile(d, h[i], crest, floor_h, radius)


## 저수호 단면: 바닥 → 직선 안쪽 벽(테두리가 둥글면 등반 깜빡임) → 평평한 둑 꼭대기 → 바깥 비탈 → 원지형(base).
## crest = 둑 꼭대기 높이, floor_h = 분지 바닥 높이, radius = 수면(안쪽 벽 끝) 반경.
## 바닥 평탄 = radius − 2 까지, 안쪽 벽 radius − 2 ~ radius (날카로운 테두리), 둑 radius ~ +12, 바깥 비탈 +18m.
static func lake_profile(d: float, base: float, crest: float, floor_h: float, radius := LAKE_WALL_R) -> float:
	var floor_r := radius - LAKE_FLOOR_INSET
	var dike_r := radius + DIKE_WIDTH
	var slope_r := dike_r + SLOPE_WIDTH
	if d <= floor_r:
		return floor_h
	if d <= radius:
		return lerpf(floor_h, crest, (d - floor_r) / (radius - floor_r))
	if d <= dike_r:
		return crest
	if d < slope_r:
		return lerpf(crest, base, smoothstep(dike_r, slope_r, d))
	return base


static func _stamp_tower(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float, top: float, tower_r := TOWER_R) -> void:
	var b := _box(size, world, cx, cz, tower_r + TOWER_BLEND)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			if d >= tower_r + TOWER_BLEND:
				continue
			var i := pz * size + px
			h[i] = lerpf(top, h[i], smoothstep(tower_r, tower_r + TOWER_BLEND, d))


static func _stamp_village(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float) -> void:
	var outer := VILLAGE_R + VILLAGE_BLEND
	var b := _box(size, world, cx, cz, outer)
	var sum := 0.0
	var cnt := 0
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			if dx * dx + dz * dz <= VILLAGE_R * VILLAGE_R:
				sum += h[pz * size + px]
				cnt += 1
	if cnt == 0:
		return
	var mean := sum / cnt
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			if d >= outer:
				continue
			var i := pz * size + px
			h[i] = mean if d <= VILLAGE_R else lerpf(mean, h[i], smoothstep(VILLAGE_R, outer, d))


## 봉우리 틈 각도 3개 (라디안, atan2(dz, dx) 관례). 표식 위치 + 시드로 결정 — 같은 입력 = 같은 틈.
## 약 120도 간격에 ±20도 흔들림.
## 틈 각도: 절벽대를 지나는 길 각도(road_angles, 20도 안은 하나로) 먼저, 모자라면 시드 각도 중
## 기존 틈과 50도 이상 떨어진 것으로 GAP_COUNT 까지 채운다. 그래도 모자라면 가장 넓은 빈 각의 가운데.
static func peak_gap_angles(x: float, z: float, road_angles := []) -> Array:
	var out: Array = []
	var sorted_roads := road_angles.duplicate()
	sorted_roads.sort()
	for a in sorted_roads:
		var merged := false
		for i in out.size():
			if _ang_dist(out[i], a) < GAP_MERGE:
				merged = true
		if not merged:
			out.append(_cluster_mean(sorted_roads, a))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([MapBaker.SEED, int(round(x)), int(round(z))])
	var start := rng.randf() * TAU
	for i in GAP_COUNT:
		if out.size() >= GAP_COUNT:
			break
		var c := wrapf(start + i * TAU / GAP_COUNT + rng.randf_range(-0.35, 0.35), -PI, PI)
		if _far_from(out, c):
			out.append(c)
	while out.size() < GAP_COUNT:
		out.append(_widest_gap_mid(out))
	return out


## 길 각도 a 둘레(GAP_MERGE 안) 각도들의 평균
static func _cluster_mean(angles: Array, a: float) -> float:
	var sx := 0.0
	var sy := 0.0
	for b in angles:
		if _ang_dist(a, b) < GAP_MERGE:
			sx += cos(b)
			sy += sin(b)
	return atan2(sy, sx)


static func _ang_dist(a: float, b: float) -> float:
	return absf(wrapf(a - b + PI, 0.0, TAU) - PI)


static func _far_from(list: Array, a: float) -> bool:
	for b in list:
		if _ang_dist(a, b) < GAP_MIN_SEP:
			return false
	return true


static func _widest_gap_mid(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var s := list.duplicate()
	s.sort()
	var best := 0.0
	var mid := 0.0
	for i in s.size():
		var a: float = s[i]
		var b: float = s[(i + 1) % s.size()] + (TAU if i == s.size() - 1 else 0.0)
		if b - a > best:
			best = b - a
			mid = wrapf(a + (b - a) * 0.5, -PI, PI)
	return mid


## 고리 r0~r1 (m) 안 길 칸(흙길·포장길)의 각도 목록 (중심 cx, cz 기준). paths 가 비면 빈 목록.
static func road_crossings(paths: PackedByteArray, size: int, world: float, cx: float, cz: float, r0: float, r1: float) -> Array:
	var out: Array = []
	if paths.size() != size * size:
		return out
	var b := _box(size, world, cx, cz, r1)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var q := paths[pz * size + px]
			if q != 1 and q != 2:
				continue
			var dx := _w(px, size, world) - cx
			var d2 := dx * dx + dz * dz
			if d2 >= r0 * r0 and d2 <= r1 * r1:
				out.append(atan2(dz, dx))
	return out


## 봉우리 도장 (P18). 정상 평탄지(summit_radius) = peak_height 정확히, 그 밖은 원지형에 "더한다":
## 절벽대(폭 48m·높이 90m, 틈 3곳은 경사로) → 오목한 비탈(peak_radius 에서 0) + 방사형 능선·골짜기.
## 정상 보정은 원지형 평균(기준 높이)과의 차를 summit_radius 밖 SUMMIT_FADE 에 걸쳐 없앤다 → 먼 곳의 칠한 단차는 그대로.
## 마커에 m["gaps"] (틈 각도) 기록.
static func _stamp_peak(h: PackedFloat32Array, size: int, world: float, m: Dictionary, peak_h: float, peak_r: float, summit_r: float, road_angles := []) -> void:
	var cx: float = m["x"]
	var cz: float = m["z"]
	var gaps := peak_gap_angles(cx, cz, road_angles)
	m["gaps"] = gaps
	# 각도 표: 틈 가중치(1 = 완전 경사로), 능선·골짜기 노이즈 (−1~1)
	var gap_w := PackedFloat32Array()
	var noise := PackedFloat32Array()
	gap_w.resize(ANGLE_STEPS)
	noise.resize(ANGLE_STEPS)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([MapBaker.SEED, int(round(cx)), int(round(cz)), 7])
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var ph3 := rng.randf() * TAU
	for k in ANGLE_STEPS:
		var a := (float(k) / ANGLE_STEPS - 0.5) * TAU
		var dd := PI
		for g in gaps:
			dd = minf(dd, absf(wrapf(a - g + PI, 0.0, TAU) - PI))
		gap_w[k] = 1.0 - smoothstep(GAP_FULL_HALF, GAP_FULL_HALF + GAP_BLEND, dd)
		noise[k] = 0.5 * sin(4.0 * a + ph1) + 0.3 * sin(7.0 * a + ph2) + 0.2 * sin(11.0 * a + ph3)
	var b := _box(size, world, cx, cz, peak_r)
	# 정상 평탄지 안 원지형 평균 = 기준 높이
	var sum := 0.0
	var cnt := 0
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			if dx * dx + dz * dz <= summit_r * summit_r:
				sum += h[pz * size + px]
				cnt += 1
	var base0 := peak_h
	if cnt > 0:
		base0 = sum / cnt
	else:
		var kk := float(size - 1) / world
		base0 = h[clampi(int(round(cz * kk + (size - 1) * 0.5)), 0, size - 1) * size + clampi(int(round(cx * kk + (size - 1) * 0.5)), 0, size - 1)]
	var top := maxf(peak_h - base0, 0.0)               # 정상에서 더하는 양
	var drop := minf(CLIFF_DROP, top)
	var cliff_end := summit_r + CLIFF_WIDTH
	var fall0 := top - drop                            # 절벽 아래에서 더하는 양
	var span := maxf(peak_r - summit_r, 1.0)
	var fall_span := maxf(peak_r - cliff_end, 1.0)
	var spur0 := maxf(drop - SPUR_SLOPE * CLIFF_WIDTH, 0.0)   # 절벽대 끝에서 지맥이 비탈보다 높은 양
	var n := float(ANGLE_STEPS)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d2 := dx * dx + dz * dz
			if d2 >= peak_r * peak_r:
				continue
			var i := pz * size + px
			var d := sqrt(d2)
			if d <= summit_r:
				h[i] = peak_h
				continue
			var u := (atan2(dz, dx) / TAU + 0.5) * n
			var k0 := int(u) % ANGLE_STEPS
			var k1 := (k0 + 1) % ANGLE_STEPS
			var f := u - floorf(u)
			var gw := lerpf(gap_w[k0], gap_w[k1], f)
			var a_cliff: float
			if d < cliff_end:
				a_cliff = top - drop * (d - summit_r) / CLIFF_WIDTH
			else:
				a_cliff = fall0 * pow(1.0 - (d - cliff_end) / fall_span, FALL_POWER)
			# 틈 = 정상에서 내려오는 지맥: 절벽대 안에서는 30도 경사로, 그 아래는 SPUR_LEN 동안 원래 비탈로 녹아든다
			var a_gap: float
			if d < cliff_end:
				a_gap = top - SPUR_SLOPE * (d - summit_r)
			else:
				var e := spur0 * (1.0 - smoothstep(cliff_end, cliff_end + SPUR_LEN, d))
				a_gap = a_cliff + e
				# 절벽대 아래 지맥 옆면은 약 40도로 넓힌다 (칼날 능선 금지)
				var dd := PI
				for g in gaps:
					dd = minf(dd, absf(wrapf(atan2(dz, dx) - g + PI, 0.0, TAU) - PI))
				var full_m := GAP_FULL_HALF * d
				var blend_m := GAP_BLEND * d + e / SPUR_FLANK * smoothstep(cliff_end, cliff_end + 40.0, d)
				gw = 1.0 - smoothstep(full_m, full_m + blend_m, dd * d)
			var add := lerpf(a_cliff, maxf(a_cliff, a_gap), gw)
			var amp := RIDGE_AMP * smoothstep(cliff_end, cliff_end + RIDGE_FADE_IN, d) * (1.0 - (d - summit_r) / span)
			amp *= 1.0 - gw   # 틈 길(지맥 등)은 능선 노이즈 없이 매끈하게
			if amp > 0.0:
				add += amp * lerpf(noise[k0], noise[k1], f)
			var c := 1.0 - smoothstep(summit_r, summit_r + SUMMIT_FADE, d)
			var base := h[i]
			h[i] = base + add + (base0 - base) * c


## 지느러미 제거 (P17): 반경 ring_m 고리의 최고점보다 rise 넘게 솟은 칸을 그 최고점으로 깎는다.
## 경사가 이어지는 봉우리·비탈은 4m 안에 6m 넘는 홀로 솟음이 없어 그대로. 읽기는 원본 복사본, 쓰기는 h.
static func despike(h: PackedFloat32Array, size: int, world: float, rise := DESPIKE_RISE, ring_m := DESPIKE_RING) -> void:
	var k := float(size - 1) / world
	var offs: Array[Vector2i] = []
	for s in 16:
		var a := TAU * s / 16.0
		var o := Vector2i(int(round(cos(a) * ring_m * k)), int(round(sin(a) * ring_m * k)))
		if o != Vector2i.ZERO and not offs.has(o):
			offs.append(o)
	if offs.is_empty():
		return
	var src := h.duplicate()
	var o0 := offs[0]
	var oi0 := o0.y * size + o0.x
	for y in size:
		var row := y * size
		var y0_ok := y + o0.y >= 0 and y + o0.y < size
		for x in size:
			var i := row + x
			var v := src[i]
			# 빠른 거름: 첫 고리 칸과 차이가 rise 이하면 지느러미 아님
			if y0_ok and x + o0.x >= 0 and x + o0.x < size and v - src[i + oi0] <= rise:
				continue
			var mx := -1.0e30
			for o in offs:
				var qx := x + o.x
				var qy := y + o.y
				if qx < 0 or qx >= size or qy < 0 or qy >= size:
					continue
				mx = maxf(mx, src[qy * size + qx])
			if mx > -1.0e29 and v - mx > rise:
				h[i] = mx
