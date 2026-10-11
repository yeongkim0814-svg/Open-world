class_name TerrainLod
extends RefCounted
## 구역(64m) 단위 LOD 선택. 카메라 xz → 구역 중심 거리로 격자 간격(1 / 2 / 4 / 16 m)을 정한다.
## 구역 (ix, iz) 의 원점(최소 모서리) = (-world/2 + ix·CHUNK, -world/2 + iz·CHUNK).

const CHUNK := 64.0
const NEAR := 96.0    # 이 거리 미만 → 1m (1km 측정: 160m면 삼각형 30만 초과)
const NEAR2 := 224.0  # 이 거리 미만 → 2m
const MID := 480.0    # 이 거리 미만 → 4m, 그 밖 → 16m


## 거리(m) → 격자 간격(m).
static func step_for(dist: float) -> float:
	if dist < NEAR:
		return 1.0
	if dist < NEAR2:
		return 2.0
	if dist < MID:
		return 4.0
	return 16.0


## 한 변의 구역 수.
static func chunks_per_side(world: float) -> int:
	return int(round(world / CHUNK))


## 구역 중심 xz.
static func chunk_center(key: Vector2i, world: float) -> Vector2:
	return Vector2(-world * 0.5 + (key.x + 0.5) * CHUNK, -world * 0.5 + (key.y + 0.5) * CHUNK)


## 월드 xz 가 속한 구역 (범위 밖이면 가장자리 구역으로 맞춤).
static func chunk_of(xz: Vector2, world: float) -> Vector2i:
	var n := chunks_per_side(world)
	var ix := int(floor((xz.x + world * 0.5) / CHUNK))
	var iz := int(floor((xz.y + world * 0.5) / CHUNK))
	return Vector2i(clampi(ix, 0, n - 1), clampi(iz, 0, n - 1))


## 전 구역의 원하는 격자 간격. Vector2i(ix, iz) → step.
static func wanted(cam_xz: Vector2, world: float) -> Dictionary:
	var out := {}
	var n := chunks_per_side(world)
	for iz in n:
		for ix in n:
			var key := Vector2i(ix, iz)
			out[key] = step_for(cam_xz.distance_to(chunk_center(key, world)))
	return out
