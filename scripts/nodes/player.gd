class_name Player
extends CharacterBody3D
## 얇은 노드: 감지(레이캐스트) → Locomotion 모델 → move_and_slide.

const GROUND_STICK_SPEED := 1.0     ## 지상에서 바닥에 붙어 있도록 주는 하향 속도
const TURN_SPEED := 12.0
const SAFE_GROUND_RADIUS := 3.0   ## 안전 지점 판정: 이 거리 사방에 바닥이 있어야 함

@export var tuning: MovementTuning = preload("res://resources/movement_tuning.tres")
@export var touch_controls: TouchControls

var stamina: Stamina
var locomotion: Locomotion
var respawn: RespawnTracker

var _intent := InputIntent.new()
var _await_stick_release := false   ## 재시작 직후: 스틱을 한 번 놓을 때까지 이동 무시

@onready var _facing: Node3D = $Facing
@onready var _wall_ray: RayCast3D = $Facing/WallRay
@onready var _head_ray: RayCast3D = $Facing/HeadRay
@onready var _camera: OrbitCamera = $OrbitCamera


func _ready() -> void:
	stamina = Stamina.new(tuning)
	locomotion = Locomotion.new(tuning, stamina)
	respawn = RespawnTracker.new(tuning.fall_respawn_y)
	respawn.safe_point = global_position
	if touch_controls:
		touch_controls.intent_updated.connect(set_intent)


func set_intent(intent: InputIntent) -> void:
	_intent = intent


func _physics_process(delta: float) -> void:
	if touch_controls:
		_camera.apply_drag(touch_controls.consume_camera_drag())
	_intent.camera_yaw = _camera.yaw
	if _await_stick_release:
		if _intent.move.is_zero_approx():
			_await_stick_release = false
		else:
			_intent.move = Vector2.ZERO
			_intent.sprint = false

	var v := locomotion.step(_intent, _sense(), delta)
	velocity = v
	if locomotion.state == Locomotion.State.GROUNDED and velocity.y <= 0.0:
		velocity.y = -GROUND_STICK_SPEED
	move_and_slide()
	stamina.tick(delta)
	if respawn.update(global_position, is_on_floor(), _on_stable_ground(), delta):
		_respawn()
	_update_facing(delta)


func _sense() -> Dictionary:
	var wall_normal := Vector3.ZERO
	if _wall_ray.is_colliding():
		var n := _wall_ray.get_collision_normal()
		if absf(n.y) < 0.3:
			wall_normal = n
	return {
		"on_floor": is_on_floor(),
		"wall_normal": wall_normal,
		"ledge_top": locomotion.state == Locomotion.State.CLIMBING \
				and _wall_ray.is_colliding() and not _head_ray.is_colliding(),
	}


func _update_facing(delta: float) -> void:
	var look := Vector3.ZERO
	if locomotion.state == Locomotion.State.CLIMBING and _wall_ray.is_colliding():
		look = -_wall_ray.get_collision_normal()
	else:
		look = Vector3(velocity.x, 0.0, velocity.z)
	if look.length() < 0.1:
		return
	var target_yaw := atan2(-look.x, -look.z)
	_facing.rotation.y = lerp_angle(_facing.rotation.y, target_yaw, minf(TURN_SPEED * delta, 1.0))


func _respawn() -> void:
	global_position = respawn.safe_point + Vector3.UP
	velocity = Vector3.ZERO
	locomotion.velocity = Vector3.ZERO
	locomotion.state = Locomotion.State.AIRBORNE
	_await_stick_release = true
	reset_physics_interpolation()
	_camera.reset_physics_interpolation()


## 발밑 기준 사방 SAFE_GROUND_RADIUS 지점 아래에 바닥이 있는지.
func _on_stable_ground() -> bool:
	if not is_on_floor():
		return false
	var space := get_world_3d().direct_space_state
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var from: Vector3 = global_position + dir * SAFE_GROUND_RADIUS + Vector3.UP
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
		query.exclude = [get_rid()]
		if space.intersect_ray(query).is_empty():
			return false
	return true
