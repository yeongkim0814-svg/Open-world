class_name InteractPicker
extends RefCounted
## 상호작용 대상 선택 (C15). 반경 안·정면 원뿔(cone_deg = 전체 각) 안에서 가장 가까운 대상. 없으면 -1.
## 발밑(수평 거리 FEET_RADIUS 이내)의 대상은 방향과 무관하게 후보.

const FEET_RADIUS := 0.3


static func pick(origin: Vector3, forward: Vector3, positions: Array[Vector3], radius := 2.0, cone_deg := 160.0) -> int:
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var half_cone := deg_to_rad(cone_deg) * 0.5
	var best := -1
	var best_dist := INF
	for i in positions.size():
		var to := positions[i] - origin
		to.y = 0.0
		var dist := to.length()
		if dist > radius:
			continue
		if dist > FEET_RADIUS and fwd.angle_to(to) > half_cone:
			continue
		if dist < best_dist:
			best_dist = dist
			best = i
	return best
