class_name MapStamps
extends RefCounted
## 표식 위치에 정확한 모양을 찍는 도장 (M4 수치). 높이 배열을 제자리에서 고친다.
## 순서: 저수호 → 탑 섬 → 마을. 모든 거리는 미터, 좌표는 HeightField 관례.

const LAKE_FLOOR_R := 46.0      ## 분지 바닥 반경
const LAKE_WALL_R := 48.0       ## 안쪽 벽 끝 = 둑 안쪽 (분지 반경 48m)
const DIKE_OUTER_R := 58.0      ## 둑 꼭대기 바깥 끝 (폭 약 10m)
const SLOPE_END_R := 76.0       ## 바깥 비탈 끝 (18m 걸쳐 원지형으로)
const LAKE_FLOOR := -6.0
const DIKE_TOP := 16.0
const TOWER_R := 10.0
const TOWER_BLEND := 4.0
const TOWER_TOP := 18.0
const VILLAGE_R := 40.0
const VILLAGE_BLEND := 15.0


static func apply(h: PackedFloat32Array, size: int, world: float, markers: Array) -> void:
	for m in markers:
		if m["kind"] == "lake":
			_stamp_lake(h, size, world, m["x"], m["z"])
	for m in markers:
		if m["kind"] == "tower":
			_stamp_tower(h, size, world, m["x"], m["z"])
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


static func _stamp_lake(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float) -> void:
	var b := _box(size, world, cx, cz, SLOPE_END_R)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			var i := pz * size + px
			if d <= LAKE_FLOOR_R:
				h[i] = LAKE_FLOOR
			elif d <= LAKE_WALL_R:
				h[i] = lerpf(LAKE_FLOOR, DIKE_TOP, smoothstep(LAKE_FLOOR_R, LAKE_WALL_R, d))
			elif d <= DIKE_OUTER_R:
				h[i] = DIKE_TOP
			elif d < SLOPE_END_R:
				h[i] = lerpf(DIKE_TOP, h[i], smoothstep(DIKE_OUTER_R, SLOPE_END_R, d))


static func _stamp_tower(h: PackedFloat32Array, size: int, world: float, cx: float, cz: float) -> void:
	var b := _box(size, world, cx, cz, TOWER_R + TOWER_BLEND)
	for pz in range(b.position.y, b.end.y):
		var dz := _w(pz, size, world) - cz
		for px in range(b.position.x, b.end.x):
			var dx := _w(px, size, world) - cx
			var d := sqrt(dx * dx + dz * dz)
			if d >= TOWER_R + TOWER_BLEND:
				continue
			var i := pz * size + px
			h[i] = lerpf(TOWER_TOP, h[i], smoothstep(TOWER_R, TOWER_R + TOWER_BLEND, d))


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
