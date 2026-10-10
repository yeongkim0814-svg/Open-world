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
const CLIMB_CAMERA_RETURN_TIME := 0.3
const CLIMB_CAMERA_RETURN_DEG_PER_SEC := 600.0
var _swing_tween: Tween
const ATTACK_FACE_LOCK := 0.35       ## 공격 후 자동 조준 방향 유지 시간 (s)
var _attack_face_lock := 0.0
var _return_yaw := 0.0
var _was_climbing := false
var _camera_return := 0.0
const ARROW_SCENE := preload("res://scenes/arrow.tscn")
var parts := 0                     ## 주운 기계 부품 수 (M2)


func _ready() -> void:
	stamina = Stamina.new(tuning)
	locomotion = Locomotion.new(tuning, stamina, combat.combat_tuning)
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
	_intent.aiming = combat.is_drawing()
	_camera.set_aiming(_intent.aiming)
	if touch_controls:
		touch_controls.set_aiming(_intent.aiming)
	if combat.is_stunned():
		_intent.move = Vector2.ZERO
		_intent.jump_pressed = false
		_intent.auto_run = false

	_update_interaction()
	_aim_probe()
	var v := locomotion.step(_intent, _sense(), delta)
	if locomotion.state == Locomotion.State.CLIMBING and touch_controls:
		touch_controls.cancel_auto_run()
	velocity = v
	if locomotion.drowned:
		_respawn()                  # 바다 쪽으로 밀던 스틱을 한 번 놓을 때까지 대기
		combat.last_result = "익사"
		return
	if locomotion.state == Locomotion.State.GROUNDED and velocity.y <= 0.0:
		velocity.y = -GROUND_STICK_SPEED
	move_and_slide()
	stamina.tick(delta)
	# 물에 잠긴 곳은 안전 지점이 아니다 (익사 후 물속에서 다시 시작하지 않게)
	if respawn.update(global_position, is_on_floor(), _on_stable_ground() and _water_depth() <= 0.0, delta):
		_respawn()
	_update_facing(delta)
	_update_camera(delta)


func _sense() -> Dictionary:
	var wall_normal := Vector3.ZERO
	if _wall_ray.is_colliding():
		var n := _wall_ray.get_collision_normal()
		if Locomotion.is_climbable(n):
			wall_normal = n
	elif is_on_wall() and Locomotion.is_climbable(get_wall_normal()):
		wall_normal = get_wall_normal()     # 가파른 지형 경사: 가슴 높이 레이가 경사면과 나란해 빗나갈 때
	return {
		"on_floor": is_on_floor(),
		"wall_normal": wall_normal,
		"ledge_top": locomotion.state == Locomotion.State.CLIMBING \
				and _wall_ray.is_colliding() and not _head_ray.is_colliding(),
		"water_depth": _water_depth(),
	}


## 발이 가장 깊이 잠긴 물의 깊이 (물 밖이면 -1).
func _water_depth() -> float:
	var depth := -1.0
	for w in get_tree().get_nodes_in_group("water"):
		depth = maxf(depth, w.depth_at(global_position))
	return depth


## 바라보기 (ViewRule): 항상 카메라 방향 / 등반 = 벽 / 회피 = 고정.
## 공격 직후 ATTACK_FACE_LOCK 동안은 자동 조준한 적 쪽을 유지한다.
func _update_facing(delta: float) -> void:
	_attack_face_lock = maxf(_attack_face_lock - delta, 0.0)
	match ViewRule.facing(locomotion.state):
		ViewRule.Facing.KEEP:
			return
		ViewRule.Facing.WALL:
			if _wall_ray.is_colliding():
				var look := -_wall_ray.get_collision_normal()
				_facing.rotation.y = lerp_angle(_facing.rotation.y, atan2(-look.x, -look.z), minf(TURN_SPEED * delta, 1.0))
		ViewRule.Facing.CAMERA:
			if _attack_face_lock <= 0.0:
				_facing.rotation.y = _camera.yaw


## 카메라: 자동 회전 없음. 등반이 끝나면(올라서거나 뛰어내림) 0.3초에 걸쳐 등 뒤(벽 방향)로 복귀.
func _update_camera(delta: float) -> void:
	var climbing := locomotion.state == Locomotion.State.CLIMBING
	if _was_climbing and not climbing and not _intent.camera_held:
		_camera_return = CLIMB_CAMERA_RETURN_TIME
		_return_yaw = _facing.rotation.y
	_was_climbing = climbing
	if _intent.camera_held:
		_camera_return = 0.0
	if _camera_return > 0.0:
		_camera_return -= delta
		_camera.yaw = CameraFollow.turn_toward(_camera.yaw, _return_yaw, deg_to_rad(CLIMB_CAMERA_RETURN_DEG_PER_SEC) * delta)


## 벽 감지 레이를 이동 방향으로 돌린다 (등반 중에는 벽 쪽 유지, 이동이 없으면 바라보는 방향).
func _aim_probe() -> void:
	if locomotion.state == Locomotion.State.CLIMBING:
		return
	var dir := locomotion.move_dir(_intent)
	_probe.rotation.y = atan2(-dir.x, -dir.z) if not dir.is_zero_approx() else _facing.rotation.y


func _respawn(await_release := true) -> void:
	global_position = respawn.safe_point + Vector3.UP
	velocity = Vector3.ZERO
	locomotion.velocity = Vector3.ZERO
	locomotion.state = Locomotion.State.AIRBORNE
	locomotion.drowned = false
	_await_stick_release = await_release
	combat.reset()
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
	for t in get_tree().get_nodes_in_group("threat"):     # 날아오는 탄
		if t.is_threatening():
			threatened = true
	combat.tick(_intent, delta)
	_intent.in_combat = combat.state.update(nearest, combat.engaged_this_tick, delta)
	_intent.threatened = threatened
	_intent.facing_yaw = _camera.yaw     # 회피 방향은 카메라 기준
	if touch_controls:
		touch_controls.set_threatened(threatened)
		touch_controls.set_swimming(locomotion.state == Locomotion.State.SWIMMING)
		touch_controls.set_weapon_label(combat.arsenal.current().display_name)


func facing_forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, _facing.rotation.y)


func face_toward(point: Vector3) -> void:
	if locomotion.state == Locomotion.State.DODGING:
		return
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		_facing.rotation.y = atan2(-to.x, -to.z)
		_attack_face_lock = ATTACK_FACE_LOCK


## 화면 중앙(카메라 정면)이 가리키는 지점. 아무것도 없으면 100m 앞.
func aim_target() -> Vector3:
	var cam := _camera.camera()
	var from := cam.global_position
	var to := from - cam.global_basis.z * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else to


## 가슴 높이에서 조준점으로 화살 발사.
func fire_arrow(hit: Hit, speed: float) -> void:
	var origin := global_position + Vector3.UP * 1.4
	var dir := (aim_target() - origin).normalized()
	var arrow: Arrow = ARROW_SCENE.instantiate()
	get_parent().add_child(arrow)
	arrow.launch(origin, dir * speed, hit, get_rid())


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


## 전투에서 쓰러짐: 스틱을 놓을 때까지 기다리지 않고 바로 조작 가능 (적이 계속 공격 중일 수 있음).
func _on_died() -> void:
	_respawn(false)
	combat.last_result = "쓰러짐"


## 앞쪽 가까운 상호작용 대상을 골라 팝업을 띄우고, 누르면 실행한다. 전투 중에도 동작 (C15).
func _update_interaction() -> void:
	var nodes := get_tree().get_nodes_in_group("interactable")
	var positions: Array[Vector3] = []
	for n in nodes:
		positions.append(n.global_position)
	var i := InteractPicker.pick(global_position, facing_forward(), positions)
	if touch_controls:
		if i == -1:
			touch_controls.hide_interact()
		else:
			touch_controls.show_interact(nodes[i].prompt())
	if i != -1 and _intent.interact_pressed:
		nodes[i].interact(self)
