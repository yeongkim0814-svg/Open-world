class_name Locomotion
extends RefCounted
## 이동 상태기계. 노드에 의존하지 않으며 step()이 다음 속도를 계산한다.
## sense 키: on_floor: bool, wall_normal: Vector3 (없으면 ZERO), ledge_top: bool

enum State { GROUNDED, AIRBORNE, CLIMBING, GLIDING, DODGING }

const WALL_STICK_SPEED := 1.0    ## 등반 중 벽에 붙어 있도록 벽 방향으로 미는 속도
const LEDGE_HOP_HEIGHT := 2.1    ## 벽 끝에서 올라설 때 솟는 높이 (m) — 끝 감지 레이(머리 1.7m)보다 높아야 발이 턱을 넘는다
const LEDGE_HOP_FORWARD := 3.0   ## 올라설 때 벽 너머로 미는 속도
const REGRAB_BLOCK_TIME := 0.5   ## 올라서기/벽 점프 직후 재등반 금지 시간 (s)

var state := State.GROUNDED
var velocity := Vector3.ZERO

var dodge_kind := Dodge.Kind.HOP_BACK

var _t: MovementTuning
var _c: CombatTuning
var _stamina: Stamina
var _dodge_time := 0.0
var _regrab_block := 0.0          ## > 0 이면 올라서기 도약 중 (재등반 금지 + 수평 속도 유지)
var _climb_jumping := false       ## 벽 점프 직후: 카메라와 무관하게 위로 밀면 다시 붙는다


func _init(tuning: MovementTuning, stamina: Stamina, combat := CombatTuning.new()) -> void:
	_t = tuning
	_c = combat
	_stamina = stamina


func step(intent: InputIntent, sense: Dictionary, delta: float) -> Vector3:
	_regrab_block = maxf(_regrab_block - delta, 0.0)
	match state:
		State.GROUNDED:
			_step_grounded(intent, sense, delta)
		State.AIRBORNE:
			_step_airborne(intent, sense, delta)
		State.CLIMBING:
			_step_climbing(intent, sense, delta)
		State.GLIDING:
			_step_gliding(intent, sense, delta)
		State.DODGING:
			_step_dodging(sense, delta)
	return velocity


func _step_grounded(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	if _try_start_climb(intent, sense):
		return
	var dir := _world_dir(intent)
	if intent.jump_pressed and intent.threatened and not dir.is_zero_approx():
		# 적의 공격 중 스틱+점프 = 회피. 탈진이면 아무것도 하지 않는다 (점프도 안 함).
		if _stamina.can_start():
			_stamina.spend(_c.dodge_cost)
			dodge_kind = Dodge.classify(dir, intent.facing_yaw)
			velocity = dir * _c.dodge_speed
			_dodge_time = 0.0
			state = State.DODGING
		else:
			velocity = Vector3.ZERO
		return
	var speed := 0.0
	if not dir.is_zero_approx():
		speed = _t.walk_speed
		if _wants_run(intent, _t) and _stamina.can_start():
			_stamina.drain(_t.run_cost, delta)
			speed = _t.run_speed
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
		_climb_jumping = false
		_glide_motion(intent, sense, delta)
		return
	if _regrab_block <= 0.0:
		var dir := _world_dir(intent)
		velocity.x = dir.x * _t.run_speed
		velocity.z = dir.z * _t.run_speed
	velocity.y -= _t.gravity * delta
	if sense.get("on_floor", false) and velocity.y <= 0.0:
		velocity.y = 0.0
		state = State.GROUNDED
		_climb_jumping = false


func _step_climbing(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var wn: Vector3 = sense.get("wall_normal", Vector3.ZERO)
	if wn == Vector3.ZERO or _stamina.value <= 0.0:
		state = State.AIRBORNE
		return
	if sense.get("on_floor", false) and intent.move.y < 0.0:
		velocity = Vector3.ZERO
		state = State.GROUNDED
		return
	if sense.get("ledge_top", false):
		velocity = Vector3.UP * sqrt(2.0 * _t.gravity * LEDGE_HOP_HEIGHT) - wn * LEDGE_HOP_FORWARD
		state = State.AIRBORNE
		_regrab_block = REGRAB_BLOCK_TIME
		return
	if intent.jump_pressed:
		_stamina.spend(_t.climb_jump_cost)
		velocity = Vector3.UP * _t.jump_velocity - wn * WALL_STICK_SPEED
		state = State.AIRBORNE
		_climb_jumping = true
		return
	var right := Vector3.UP.cross(wn).normalized()
	velocity = (right * intent.move.x + Vector3.UP * intent.move.y) * _t.climb_speed - wn * WALL_STICK_SPEED
	if intent.move.is_zero_approx():
		_stamina.hold()
	elif not _stamina.drain(_t.climb_cost, delta):
		state = State.AIRBORNE


func _step_dodging(sense: Dictionary, delta: float) -> void:
	_dodge_time += delta
	if not sense.get("on_floor", false):
		velocity.y -= _t.gravity * delta
	if _dodge_time >= _c.dodge_duration:
		velocity = Vector3.ZERO
		state = State.GROUNDED


## 회피 시작 후 무적 시간 동안 true.
func is_invulnerable() -> bool:
	return state == State.DODGING and _dodge_time < _c.dodge_iframes


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
	if wn == Vector3.ZERO or _regrab_block > 0.0 or not _stamina.can_start():
		return false
	var regrab := _climb_jumping and intent.move.y > 0.0
	var into_wall := _world_dir(intent).dot(-wn) >= cos(deg_to_rad(_t.climb_grab_angle_deg))
	if not regrab and not into_wall:
		return false
	_climb_jumping = false
	state = State.CLIMBING
	velocity = Vector3.ZERO
	return true


## 이동 방향(월드 수평, 정규화). 자동 달리기면 카메라 정면. Godot 전방 = -Z. 이동이 없으면 ZERO.
func move_dir(intent: InputIntent) -> Vector3:
	return _world_dir(intent)


## 캐릭터가 이동 방향으로 몸을 돌려야 하는지.
## 자동 달리기·전투 상태 → 항상 / 오른손 시점 조작 중 → 유지 / 달리기 → 회전 / 걷기 → 유지.
static func turns_to_move(intent: InputIntent, tuning: MovementTuning) -> bool:
	if intent.auto_run or intent.in_combat:
		return true
	if intent.camera_held:
		return false
	return _wants_run(intent, tuning)


static func _wants_run(intent: InputIntent, tuning: MovementTuning) -> bool:
	return intent.auto_run or intent.move.length() >= tuning.run_threshold


func _world_dir(intent: InputIntent) -> Vector3:
	var move := Vector2(0.0, 1.0) if intent.auto_run else intent.move
	if move.is_zero_approx():
		return Vector3.ZERO
	return Vector3(move.x, 0.0, -move.y).normalized().rotated(Vector3.UP, intent.camera_yaw)
