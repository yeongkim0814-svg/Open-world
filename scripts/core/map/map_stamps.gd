class_name MapStamps
extends RefCounted
## 표식 위치에 정확한 모양을 찍는 도장 (M4 수치). 높이 배열을 제자리에서 고친다.
## 순서: 저수호 → 탑 섬 → 마을 (산마을 hill_village 는 도장 없음). 모든 거리는 미터, 좌표는 HeightField 관례.
## 저수호·탑은 주변 지면 기준 상대 높이. 계산한 값은 표식 딕셔너리에 기록한다:
## 저수호 m["crest"] (둑 꼭대기 높이), 탑 m["top"] (섬 윗면 높이) — markers.json 으로 나간다.

const LAKE_FLOOR_R := 46.0      ## 분지 바닥 반경
const LAKE_WALL_R := 48.0       ## 안쪽 벽 끝 = 둑 안쪽 (분지 반경 48m)
const DIKE_OUTER_R := 58.0      ## 둑 꼭대기 바깥 끝 (폭 약 10m)
const SLOPE_END_R := 76.0       ## 바깥 비탈 끝 (18m 걸쳐 원지형으로)
const CREST_RISE := 4.0         ## 둑 꼭대기 = 주변 지면(고리 중앙값) + 4m (설계서 P12)
const LAKE_DEPTH := 22.0        ## 분지 바닥 = 꼭대기 − 22m
const RING_R0 := 60.0           ## 주변 지면을 재는 고리 (m)
const RING_R1 := 80.0
const TOWER_R := 10.0
const TOWER_BLEND := 4.0
const TOWER_RISE := 2.0         ## 탑 섬 윗면 = 둑 꼭대기 + 2m
const VILLAGE_R := 40.0
const VILLAGE_BLEND := 15.0


static func apply(h: PackedFloat32Array, size: int, world: float, markers: Array) -> void:
	var orig := h.duplicate()      # 도장 전 원지형 (고리 중앙값은 이것으로 잰다)
	var lakes: Array = []
	for m in markers:
		if m["kind"] == "lake":
			var crest := ring_median(orig, size, world, m["x"], m["z"]) + CREST_RISE
			m["crest"] = crest
			lakes.append(m)
			_stamp_lake(h, size, world, m["x"], m["z"], crest, crest - LAKE_DEPTH)
	for m in markers:
		if m["kind"] == "tower":
			var top := _tower_top(orig, size, world, m, lakes)
			m["top"] = top
			_stamp_tower(h, size, world, m["x"], m["z"], top)
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


## 중심에서 RING_R0~RING_R1 m 고리 칸들의 높이 중앙값 (지도 밖 칸은 제외, 칸이 없으면 중심 높이).
static func ring_median(src: PackedFloat32Array, size: int, world: float, cx: float, cz: float) -> float:
	var b := _box(size, world, cx, cz, RING_R1)
	var vals := PackedFloat32Array()
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d2 := dx * dx + dz * dz
			if d2 >= RING_R0 * RING_R0 and d2 <= RING_R1 * RING_R1:
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
static func _tower_top(orig: PackedFloat32Array, size: int, world: float, tower: Dictionary, lakes: Array) -> float:
	for lk in lakes:
		var dx: float = tower["x"] - lk["x"]
		var dz: float = tower["z"] - lk["z"]
		if sqrt(dx * dx + dz * dz) <= LAKE_WALL_R:
			return float(lk["crest"]) + TOWER_RISE
	return ring_median(orig, size, world, tower["x"], tower["z"]) + CREST_RISE + TOWER_RISE


static func _stamp_lake(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float, crest: float, floor_h: float) -> void:
	var b := _box(size, world, cx, cz, SLOPE_END_R)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			var i := pz * size + px
			h[i] = lake_profile(d, h[i], crest, floor_h)


## 저수호 단면: 바닥 → 직선 안쪽 벽(테두리가 둥글면 등반 깜빡임) → 평평한 둑 꼭대기 → 바깥 비탈 → 원지형(base).
## crest = 둑 꼭대기 높이, floor_h = 분지 바닥 높이.
static func lake_profile(d: float, base: float, crest: float, floor_h: float) -> float:
	if d <= LAKE_FLOOR_R:
		return floor_h
	if d <= LAKE_WALL_R:
		return lerpf(floor_h, crest, (d - LAKE_FLOOR_R) / (LAKE_WALL_R - LAKE_FLOOR_R))
	if d <= DIKE_OUTER_R:
		return crest
	if d < SLOPE_END_R:
		return lerpf(crest, base, smoothstep(DIKE_OUTER_R, SLOPE_END_R, d))
	return base


static func _stamp_tower(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float, top: float) -> void:
	var b := _box(size, world, cx, cz, TOWER_R + TOWER_BLEND)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			if d >= TOWER_R + TOWER_BLEND:
				continue
			var i := pz * size + px
			h[i] = lerpf(top, h[i], smoothstep(TOWER_R, TOWER_R + TOWER_BLEND, d))


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
