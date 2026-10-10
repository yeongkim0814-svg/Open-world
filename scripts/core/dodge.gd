class_name Dodge
extends RefCounted
## 회피 종류 판정. 캐릭터 정면 기준 이동 방향으로 결정한다 (C16).
## 앞 ±45° = 구르기, 뒤 ±45° = 뒤로 도약, 나머지 = 좌·우 옆 도약.

enum Kind { ROLL_FORWARD, HOP_BACK, HOP_LEFT, HOP_RIGHT }

const COS_45 := 0.7071


static func classify(move_world: Vector3, facing_yaw: float) -> Kind:
	var forward := Vector3.FORWARD.rotated(Vector3.UP, facing_yaw)
	var right := forward.cross(Vector3.UP)
	var dir := Vector3(move_world.x, 0.0, move_world.z).normalized()
	var f := dir.dot(forward)
	if f >= COS_45:
		return Kind.ROLL_FORWARD
	if f <= -COS_45:
		return Kind.HOP_BACK
	return Kind.HOP_RIGHT if dir.dot(right) > 0.0 else Kind.HOP_LEFT
