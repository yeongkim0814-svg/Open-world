class_name Targeting
extends RefCounted
## 자동 조준 대상 선택 (C10). 점수 = 거리 + 각도(라디안)×ANGLE_WEIGHT, 낮을수록 우선.
## 사거리 밖, 정면 원뿔(cone_deg = 전체 각) 밖은 제외. 없으면 -1.

const ANGLE_WEIGHT := 3.0


static func pick(origin: Vector3, forward: Vector3, candidates: Array[Vector3], range: float, cone_deg: float) -> int:
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var half_cone := deg_to_rad(cone_deg) * 0.5
	var best := -1
	var best_score := INF
	for i in candidates.size():
		var to := candidates[i] - origin
		to.y = 0.0
		var dist := to.length()
		if dist > range or dist < 0.001:
			continue
		var angle := fwd.angle_to(to)
		if angle > half_cone:
			continue
		var score := dist + angle * ANGLE_WEIGHT
		if score < best_score:
			best_score = score
			best = i
	return best
