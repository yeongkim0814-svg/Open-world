class_name RockPlacement
extends RefCounted
## 바위 배치 규칙 (순수 함수). 경사 35°+ 칸 우선(≥80% 목표), 나머지 평지. 같은 시드 = 같은 결과.
## 반환 Transform3D: basis = 회전 × 균일 크기(1~8, 단위 높이 바위 기준), origin = 땅 아래로 20~30% 묻힌 위치.

const SLOPE_MIN_DEG := 35.0
const SLOPE_MAX_DEG := 78.0
const STEEP_SHARE := 0.85
const MIN_GROUND_H := 0.5     # 해안·바다 속 제외
const EDGE := 140.0           # 섬 가장자리 여유
const MAX_SIZE := 8.0
const BIG_MIN := 4.0
const BIG_SHARE := 0.1        # 경사 칸 중 큰 바위 비율


static func points(field: HeightField, seed: int, count: int, exclusions: Array) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Transform3D] = []
	var want_steep := int(ceil(count * STEEP_SHARE))
	var steep := 0
	var flat := 0
	var tries := 0
	var max_tries := count * 400
	var min_cos := cos(deg_to_rad(SLOPE_MIN_DEG))
	var max_cos := cos(deg_to_rad(SLOPE_MAX_DEG))
	while out.size() < count and tries < max_tries:
		tries += 1
		var x := rng.randf_range(-EDGE, EDGE)
		var z := rng.randf_range(-EDGE, EDGE)
		var h := field.height_at(x, z)
		if h < MIN_GROUND_H:
			continue
		var n := field.normal_at(x, z)
		var is_steep := n.y <= min_cos and n.y >= max_cos
		if is_steep and steep >= want_steep:
			continue
		if not is_steep and (flat >= count - want_steep or n.y < min_cos):
			continue                                  # 너무 가파른(>78°) 칸도 평지로 치지 않음
		var slope_t := clampf((acos(n.y) - deg_to_rad(SLOPE_MIN_DEG)) / deg_to_rad(35.0), 0.0, 1.0) if is_steep else 0.0
		var s := lerpf(1.0, 3.2, pow(rng.randf(), 1.6)) * lerpf(1.0, 1.9, slope_t)
		var big := rng.randf()
		if is_steep and big < BIG_SHARE:
			s = lerpf(BIG_MIN, MAX_SIZE, big / BIG_SHARE)    # 경사의 큰 바위 몇 개 (4~8 m)
		s = clampf(s, 1.0, MAX_SIZE)
		if _excluded(x, z, s * 0.6, exclusions):
			continue
		var up := Vector3.UP.slerp(n, rng.randf_range(0.35, 0.8)).normalized()
		var tilt := Basis(Quaternion(Vector3.UP, up))
		var yaw := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var basis := (tilt * yaw).scaled(Vector3.ONE * s)
		var sink := rng.randf_range(0.2, 0.3) * s
		out.append(Transform3D(basis, Vector3(x, h - sink, z)))
		if is_steep:
			steep += 1
		else:
			flat += 1
	return out


static func _excluded(x: float, z: float, margin: float, exclusions: Array) -> bool:
	for e in exclusions:
		if e is Vector3:
			if Vector2(x, z).distance_to(Vector2(e.x, e.y)) < e.z + margin:
				return true
		elif e is Rect2:
			if (e as Rect2).grow(margin).has_point(Vector2(x, z)):
				return true
	return false
