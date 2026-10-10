class_name OrbitCamera
extends Node3D
## 3인칭 오빗 카메라. 대상 위치를 따라가고, 드래그로 yaw/pitch를 돌린다.
## SpringArm3D가 지형에 닿으면 카메라를 당겨 벽 뚫림을 막는다.

const SENSITIVITY := 0.005          ## rad / px
const PITCH_MIN := deg_to_rad(-70.0)
const PITCH_MAX := deg_to_rad(40.0)
const TARGET_HEIGHT := 1.5

@export var target: Node3D

var yaw := 0.0
var pitch := deg_to_rad(-15.0)

var _follow := CameraFollow.new(preload("res://resources/combat_tuning.tres"))

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _cam: Camera3D = $SpringArm3D/Camera3D

const AIM_FOV := 50.0
const AIM_BLEND_TIME := 0.15
var _base_fov := 75.0
var _aiming := false


func _ready() -> void:
	top_level = true
	_base_fov = _cam.fov
	if target:
		_arm.add_excluded_object(target.get_rid())


## 전투 상태에서 캐릭터 등 뒤로 자동 정렬 (C14). held = 오른손이 화면을 누르는 중, dodging = 회피 중.
func follow(target_yaw: float, delta: float, held: bool, dodging: bool) -> void:
	yaw = _follow.step(yaw, target_yaw, delta, held, dodging)


func camera() -> Camera3D:
	return _cam


## 활 조준: 시야를 좁혀 확대 (C18).
func set_aiming(on: bool) -> void:
	_aiming = on


func apply_drag(drag_px: Vector2) -> void:
	yaw -= drag_px.x * SENSITIVITY
	pitch = clampf(pitch - drag_px.y * SENSITIVITY, PITCH_MIN, PITCH_MAX)


func _physics_process(delta: float) -> void:
	if target:
		global_position = target.global_position + Vector3.UP * TARGET_HEIGHT
	rotation = Vector3(pitch, yaw, 0.0)
	var goal := AIM_FOV if _aiming else _base_fov
	_cam.fov = move_toward(_cam.fov, goal, (_base_fov - AIM_FOV) / AIM_BLEND_TIME * delta)
