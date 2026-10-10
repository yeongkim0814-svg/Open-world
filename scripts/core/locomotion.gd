class_name Locomotion
extends RefCounted
## 이동 상태기계. 노드에 의존하지 않으며 step()이 다음 속도를 계산한다.
## sense 키: on_floor: bool, wall_normal: Vector3 (없으면 ZERO), ledge_top: bool

enum State { GROUNDED, AIRBORNE, CLIMBING, GLIDING }

const WALK_THRESHOLD := 0.5

var state := State.GROUNDED
var velocity := Vector3.ZERO

var _t: MovementTuning
var _stamina: Stamina


func _init(tuning: MovementTuning, stamina: Stamina) -> void:
	_t = tuning
	_stamina = stamina


func step(intent: InputIntent, sense: Dictionary, delta: float) -> Vector3:
	match state:
		State.GROUNDED:
			_step_grounded(intent, sense, delta)
		State.AIRBORNE:
			_step_airborne(intent, sense, delta)
	return velocity


func _step_grounded(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var dir := _world_dir(intent)
	var speed := 0.0
	if intent.move.length() > 0.0:
		speed = _t.run_speed if intent.move.length() >= WALK_THRESHOLD else _t.walk_speed
		if intent.sprint and _stamina.can_start():
			_stamina.drain(_t.sprint_cost, delta)
			speed = _t.sprint_speed
	velocity = Vector3(dir.x * speed, 0.0, dir.z * speed)
	if intent.jump_pressed:
		velocity.y = _t.jump_velocity
		state = State.AIRBORNE
	elif not sense.get("on_floor", false):
		state = State.AIRBORNE


func _step_airborne(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var dir := _world_dir(intent)
	velocity.x = dir.x * _t.run_speed
	velocity.z = dir.z * _t.run_speed
	velocity.y -= _t.gravity * delta
	if sense.get("on_floor", false) and velocity.y <= 0.0:
		velocity.y = 0.0
		state = State.GROUNDED


## 스틱 입력을 카메라 yaw 기준 월드 수평 방향(정규화)으로 변환. Godot 전방 = -Z.
func _world_dir(intent: InputIntent) -> Vector3:
	if intent.move.is_zero_approx():
		return Vector3.ZERO
	return Vector3(intent.move.x, 0.0, -intent.move.y).normalized().rotated(Vector3.UP, intent.camera_yaw)
