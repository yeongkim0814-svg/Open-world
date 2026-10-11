class_name GrassPlacement
extends RefCounted
## 풀 배치 순수 함수. 지터 격자 → 경사 30° 초과·높이 2m 미만(모래)·물 아래 제외.

const MAX_SLOPE_COS := 0.8660254  # cos(30°)
const MIN_HEIGHT := 2.0


## water_level_fn(x, z) -> 수면 y (물이 없으면 -INF). 점 y가 수면보다 낮으면 제외.
static func points(field: HeightField, chunk_origin: Vector2, size: float, density: float,
		seed: int, water_level_fn: Callable = Callable()) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(1, roundi(size * sqrt(density)))
	var cell := size / n
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(seed, int(floor(chunk_origin.x * 4.0)), int(floor(chunk_origin.y * 4.0))))
	for iz in n:
		for ix in n:
			var x := chunk_origin.x + (ix + rng.randf()) * cell
			var z := chunk_origin.y + (iz + rng.randf()) * cell
			var y := field.height_at(x, z)
			if y < MIN_HEIGHT:
				continue
			if field.normal_at(x, z).y < MAX_SLOPE_COS:
				continue
			if water_level_fn.is_valid() and y < float(water_level_fn.call(x, z)):
				continue
			out.append(Vector3(x, y, z))
	return out
