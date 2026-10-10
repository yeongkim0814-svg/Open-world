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
@onready var _probe: Node3D = $Probe          ## 벽 감지 레이 묶음: 바라보는 방향이 아니라 이동 방향을 향한다
@onready var _wall_ray: RayCast3D = $Probe/WallRay
@onready var _head_ray: RayCast3D = $Probe/HeadRay
@onready var _camera: OrbitCamera = $OrbitCamera
@onready var combat: PlayerCombat = $PlayerCombat
@onready var _sword: Node3D = $Facing/SwordPivot

const THREAT_RANGE := 6.0          ## 이 거리 안의 적이 공격 중이면 회피 문맥 (C16)
var _swing_tween: Tween


func _ready() -> void:
	stamina = Stamina.new(tuning)
	locomotion = Locomotion.new(tuning, stamina)
	respawn = RespawnTracker.new(tuning.fall_respawn_y)
	respawn.safe_point = global_position
	add_to_group("player")
	combat.setup(self)
	combat.died.connect(_on_died)
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
	_update_combat_context(delta)
	if combat.is_stunned():
		_intent.move = Vector2.ZERO
		_intent.jump_pressed = false
		_intent.auto_run = false

	_aim_probe()
	var v := locomotion.step(_intent, _sense(), delta)
	if locomotion.state == Locomotion.State.CLIMBING and touch_controls:
		touch_controls.cancel_auto_run()
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


## 바라보기 규칙: 회피 = 고정 / 등반 = 벽 / 활공 = 이동 방향 / 그 외는 Locomotion.turns_to_move.
func _update_facing(delta: float) -> void:
	if locomotion.state == Locomotion.State.DODGING:
		return
	var look := Vector3.ZERO
	if locomotion.state == Locomotion.State.CLIMBING:
		if _wall_ray.is_colliding():
			look = -_wall_ray.get_collision_normal()
	elif locomotion.state == Locomotion.State.GLIDING or Locomotion.turns_to_move(_intent, tuning):
		look = Vector3(velocity.x, 0.0, velocity.z)
	if look.length() < 0.1:
		return
	var target_yaw := atan2(-look.x, -look.z)
	_facing.rotation.y = lerp_angle(_facing.rotation.y, target_yaw, minf(TURN_SPEED * delta, 1.0))


## 벽 감지 레이를 이동 방향으로 돌린다 (등반 중에는 벽 쪽 유지, 이동이 없으면 바라보는 방향).
func _aim_probe() -> void:
	if locomotion.state == Locomotion.State.CLIMBING:
		return
	var dir := locomotion.move_dir(_intent)
	_probe.rotation.y = atan2(-dir.x, -dir.z) if not dir.is_zero_approx() else _facing.rotation.y


func _respawn() -> void:
	global_position = respawn.safe_point + Vector3.UP
	velocity = Vector3.ZERO
	locomotion.velocity = Vector3.ZERO
	locomotion.state = Locomotion.State.AIRBORNE
	_await_stick_release = true
	combat.reset_hp()
	if touch_controls:
		touch_controls.cancel_auto_run()
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


## 전투 상태·위협 여부를 갱신하고 InputIntent에 채운다. 전투 중이면 카메라를 등 뒤로 정렬 (C14).
func _update_combat_context(delta: float) -> void:
	var nearest := INF
	var threatened := false
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: float = global_position.distance_to(e.global_position)
		if e.is_alerted():
			nearest = minf(nearest, d)
		if d <= THREAT_RANGE and e.is_threatening():
			threatened = true
	combat.tick(_intent, delta)
	var was_in_combat := combat.state.active
	_intent.in_combat = combat.state.update(nearest, combat.engaged_this_tick, delta)
	_intent.threatened = threatened
	_intent.facing_yaw = _facing.rotation.y
	if touch_controls:
		touch_controls.set_threatened(threatened)
		if _intent.in_combat and not was_in_combat:
			touch_controls.cancel_auto_run()
	if _intent.in_combat:
		_intent.auto_run = false
		_camera.follow(_facing.rotation.y, delta, _intent.camera_held, locomotion.state == Locomotion.State.DODGING)


func facing_forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, _facing.rotation.y)


func face_toward(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		_facing.rotation.y = atan2(-to.x, -to.z)


## 검 휘두르기 연출 (콤보 단계마다 방향을 바꿔 좌우로 벤다). 강공격은 위에서 아래로.
func play_swing(step: int, heavy: bool) -> void:
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	if heavy:
		_sword.rotation = Vector3(deg_to_rad(80), 0, 0)
		_swing_tween.tween_property(_sword, "rotation", Vector3(deg_to_rad(-70), 0, 0), 0.25)
	else:
		var from := -70.0 if step % 2 == 1 else 70.0
		_sword.rotation = Vector3(0, deg_to_rad(from), 0)
		_swing_tween.tween_property(_sword, "rotation", Vector3(0, deg_to_rad(-from), 0), 0.15)
	_swing_tween.tween_property(_sword, "rotation", Vector3.ZERO, 0.15)


func _on_died() -> void:
	_respawn()
