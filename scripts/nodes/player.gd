class_name Player
extends CharacterBody3D
## 얇은 노드: 감지(레이캐스트) → Locomotion 모델 → move_and_slide.

const GROUND_STICK_SPEED := 1.0     ## 지상에서 바닥에 붙어 있도록 주는 하향 속도
const TURN_SPEED := 12.0

@export var tuning: MovementTuning = preload("res://resources/movement_tuning.tres")
@export var touch_controls: TouchControls

var stamina: Stamina
var locomotion: Locomotion

var _intent := InputIntent.new()

@onready var _facing: Node3D = $Facing
@onready var _wall_ray: RayCast3D = $Facing/WallRay
@onready var _head_ray: RayCast3D = $Facing/HeadRay
@onready var _camera: OrbitCamera = $OrbitCamera


func _ready() -> void:
	stamina = Stamina.new(tuning)
	locomotion = Locomotion.new(tuning, stamina)
	if touch_controls:
		touch_controls.intent_updated.connect(set_intent)


func set_intent(intent: InputIntent) -> void:
	_intent = intent


func _physics_process(delta: float) -> void:
	if touch_controls:
		_camera.apply_drag(touch_controls.consume_camera_drag())
	_intent.camera_yaw = _camera.yaw

	var v := locomotion.step(_intent, _sense(), delta)
	velocity = v
	if locomotion.state == Locomotion.State.GROUNDED and velocity.y <= 0.0:
		velocity.y = -GROUND_STICK_SPEED
	move_and_slide()
	stamina.tick(delta)
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
