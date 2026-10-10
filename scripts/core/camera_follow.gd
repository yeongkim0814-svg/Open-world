class_name CameraFollow
extends RefCounted
## 전투 상태 카메라 자동 정렬 규칙 (C14). 카메라 yaw를 캐릭터가 바라보는 방향으로 천천히 돌린다.
## 손가락과 싸우지 않게: 오른손이 화면을 누르는 동안과 뗀 뒤 resume_delay 동안, 그리고 회피 중에는 멈춘다.

var _t: CombatTuning
var _since_release := INF


func _init(t: CombatTuning) -> void:
	_t = t


## 새 카메라 yaw. 반환값은 cam_yaw에서 연속적으로 이어진다 (±π로 wrap하지 않음).
func step(cam_yaw: float, target_yaw: float, delta: float, held: bool, dodging: bool) -> float:
	if held:
		_since_release = 0.0
		return cam_yaw
	_since_release += delta
	if dodging or _since_release < _t.camera_resume_delay:
		return cam_yaw
	var diff := wrapf(target_yaw - cam_yaw, -PI, PI)
	if diff <= -PI + 0.0001:
		diff = PI                       # 정반대일 때는 양의 방향으로
	var max_step := deg_to_rad(_t.camera_follow_deg_per_sec) * delta
	return cam_yaw + clampf(diff, -max_step, max_step)
