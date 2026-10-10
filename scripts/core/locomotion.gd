class_name Locomotion
extends RefCounted
## 이동 상태기계. 노드에 의존하지 않으며 step()이 다음 속도를 계산한다.
## sense 키: on_floor: bool, wall_normal: Vector3 (없으면 ZERO), ledge_top: bool

enum State { GROUNDED, AIRBORNE, CLIMBING, GLIDING }

const WALK_THRESHOLD := 0.5
const CLIMB_GRAB_DOT := 0.5      ## 벽 쪽으로 미는 입력 성분이 이 이상이면 등반 시작
const WALL_STICK_SPEED := 1.0    ## 등반 중 벽에 붙어 있도록 벽 방향으로 미는 속도

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
		State.CLIMBING:
			_step_climbing(intent, sense, delta)
		State.GLIDING:
			_step_gliding(intent, sense, delta)
	return velocity


func _step_grounded(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	if _try_start_climb(intent, sense):
		return
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
	if _try_start_climb(intent, sense):
		return
	if intent.jump_pressed and velocity.y < 0.0 and _stamina.can_start():
		state = State.GLIDING
		_glide_motion(intent, sense, delta)
		return
	var dir := _world_dir(intent)
	velocity.x = dir.x * _t.run_speed
	velocity.z = dir.z * _t.run_speed
	velocity.y -= _t.gravity * delta
	if sense.get("on_floor", false) and velocity.y <= 0.0:
		velocity.y = 0.0
		state = State.GROUNDED


func _step_climbing(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var wn: Vector3 = sense.get("wall_normal", Vector3.ZERO)
	if wn == Vector3.ZERO or _stamina.value <= 0.0:
		state = State.AIRBORNE
		return
	if sense.get("ledge_top", false):
		velocity = Vector3.UP * _t.jump_velocity * 0.5 - wn * WALL_STICK_SPEED
		state = State.GROUNDED
		return
	if intent.jump_pressed:
		_stamina.spend(_t.climb_jump_cost)
		velocity = Vector3.UP * _t.jump_velocity - wn * WALL_STICK_SPEED
		state = State.AIRBORNE
		return
	var right := Vector3.UP.cross(wn).normalized()
	velocity = (right * intent.move.x + Vector3.UP * intent.move.y) * _t.climb_speed - wn * WALL_STICK_SPEED
	if not intent.move.is_zero_approx() and not _stamina.drain(_t.climb_cost, delta):
		state = State.AIRBORNE


func _step_gliding(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	if intent.jump_pressed:
		state = State.AIRBORNE
		return
	_glide_motion(intent, sense, delta)


func _glide_motion(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var dir := _world_dir(intent)
	velocity = Vector3(dir.x * _t.glide_speed, -_t.glide_fall_speed, dir.z * _t.glide_speed)
	if sense.get("on_floor", false):
		velocity.y = 0.0
		state = State.GROUNDED
	elif not _stamina.drain(_t.glide_cost, delta):
		state = State.AIRBORNE


## 벽이 있고, 벽 쪽으로 밀고 있고, 스태미나로 시작할 수 있으면 등반 상태로 전환.
func _try_start_climb(intent: InputIntent, sense: Dictionary) -> bool:
	var wn: Vector3 = sense.get("wall_normal", Vector3.ZERO)
	if wn == Vector3.ZERO or not _stamina.can_start():
		return false
	if _world_dir(intent).dot(-wn) * intent.move.length() <= CLIMB_GRAB_DOT:
		return false
	state = State.CLIMBING
	velocity = Vector3.ZERO
	return true


## 스틱 입력을 카메라 yaw 기준 월드 수평 방향(정규화)으로 변환. Godot 전방 = -Z.
func _world_dir(intent: InputIntent) -> Vector3:
	if intent.move.is_zero_approx():
		return Vector3.ZERO
	return Vector3(intent.move.x, 0.0, -intent.move.y).normalized().rotated(Vector3.UP, intent.camera_yaw)
