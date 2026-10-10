class_name Locomotion
extends RefCounted
## 이동 상태기계. 노드에 의존하지 않으며 step()이 다음 속도를 계산한다.
## sense 키: on_floor: bool, wall_normal: Vector3 (없으면 ZERO), ledge_top: bool,
##          water_depth: float (발이 수면 아래 몇 m인지, 물 밖이면 0 이하)

enum State { GROUNDED, AIRBORNE, CLIMBING, GLIDING, DODGING, SWIMMING }

const WALL_STICK_SPEED := 1.0    ## 등반 중 벽에 붙어 있도록 벽 방향으로 미는 속도
const LEDGE_HOP_HEIGHT := 2.1    ## 벽 끝에서 올라설 때 솟는 높이 (m) — 끝 감지 레이(머리 1.7m)보다 높아야 발이 턱을 넘는다
const LEDGE_HOP_FORWARD := 3.0   ## 올라설 때 벽 너머로 미는 속도
const REGRAB_BLOCK_TIME := 0.5   ## 올라서기/벽 점프 직후 재등반 금지 시간 (s)
const FLOAT_GAIN := 4.0          ## 수면 높이로 떠오르는 속도 계수
const FLOAT_MAX_SPEED := 3.0
const SWIM_EXIT_RATIO := 0.75    ## 이 비율보다 얕고 발이 바닥에 닿으면 걸어 나감
const CLIMB_TO_SWIM_EXTRA := 0.3 ## 벽을 타고 내려가다 이만큼 더 잠기면 헤엄으로
const DROWN_SINK_SPEED := 1.0

var state := State.GROUNDED
var velocity := Vector3.ZERO

var dodge_kind := Dodge.Kind.HOP_BACK
var drowned := false               ## 물에서 탈진해 익사함 → Player가 재시작 후 false로

var _t: MovementTuning
var _c: CombatTuning
var _stamina: Stamina
var _dodge_time := 0.0
var _regrab_block := 0.0          ## > 0 이면 올라서기 도약 중 (재등반 금지 + 수평 속도 유지)
var _climb_jumping := false       ## 벽 점프 직후: 카메라와 무관하게 위로 밀면 다시 붙는다
var _dash := 0.0                  ## 수영 가속 남은 시간
var _dash_dir := Vector3.ZERO
var _drown := 0.0                 ## 물에서 탈진한 시간


func _init(tuning: MovementTuning, stamina: Stamina, combat := CombatTuning.new()) -> void:
	_t = tuning
	_c = combat
	_stamina = stamina


func step(intent: InputIntent, sense: Dictionary, delta: float) -> Vector3:
	_regrab_block = maxf(_regrab_block - delta, 0.0)
	var depth: float = sense.get("water_depth", 0.0)
	if depth >= _t.swim_depth and state not in [State.SWIMMING, State.CLIMBING]:
		_enter_swim()
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
		State.SWIMMING:
			_step_swimming(intent, sense, delta)
	return velocity


func _enter_swim() -> void:
	state = State.SWIMMING
	_dash = 0.0
	_drown = 0.0
	_climb_jumping = false
	velocity.x = 0.0
	velocity.z = 0.0


## 수영: 카메라 기준 스틱 방향으로 헤엄(소모), 점프 = 가속, 가만히 = 소모·회복 없음, 탈진 = 가라앉다 익사.
func _step_swimming(intent: InputIntent, sense: Dictionary, delta: float) -> void:
	var depth: float = sense.get("water_depth", 0.0)
	if depth <= 0.0 or (sense.get("on_floor", false) and depth < _t.swim_depth * SWIM_EXIT_RATIO):
		state = State.GROUNDED if sense.get("on_floor", false) else State.AIRBORNE
		velocity.y = 0.0
		return
	if _stamina.exhausted:
		_stamina.hold()
		_drown += delta
		velocity = Vector3.DOWN * DROWN_SINK_SPEED
		if _drown >= _t.drown_time:
			drowned = true
		return
	_drown = 0.0
	if _try_start_climb(intent, sense):
		return
	var dir := _world_dir(intent)
	_dash = maxf(_dash - delta, 0.0)
	if intent.jump_pressed and _stamina.can_start():
		_stamina.spend(_t.swim_dash_cost)
		_dash = _t.swim_dash_time
		_dash_dir = dir if not dir.is_zero_approx() else Vector3.FORWARD.rotated(Vector3.UP, intent.camera_yaw)
	var horizontal := Vector3.ZERO
	if _dash > 0.0:
		horizontal = (dir if not dir.is_zero_approx() else _dash_dir) * _t.swim_dash_speed
		_stamina.hold()
	elif not dir.is_zero_approx():
		horizontal = dir * _t.swim_speed
		_stamina.drain(_t.swim_cost, delta)
	else:
		_stamina.hold()
	velocity = Vector3(horizontal.x, clampf((depth - _t.swim_depth) * FLOAT_GAIN, -FLOAT_MAX_SPEED, FLOAT_MAX_SPEED), horizontal.z)


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
		if wants_run(intent, _t) and _stamina.can_start():
			_stamina.drain(_t.run_cost, delta)
			speed = _t.run_speed
	velocity = Vector3(dir.x * speed, 0.0, dir.z * speed)
	if intent.jump_pressed and _stamina.can_start():
		_stamina.spend(_t.jump_cost)
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
	if sense.get("water_depth", 0.0) >= _t.swim_depth + CLIMB_TO_SWIM_EXTRA and intent.move.y < 0.0:
		_enter_swim()
		return
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


## 달리기인지: 자동 달리기, 또는 스틱을 정면 run_cone_deg 안으로 run_threshold 이상 밀었을 때.
## 옆·뒤로 미는 것은 세기와 상관없이 걷기 (캐릭터는 항상 카메라를 보므로 게걸음·뒷걸음).
static func wants_run(intent: InputIntent, tuning: MovementTuning) -> bool:
	if intent.aiming:            # 활을 당기는 중 = 걷기만 (C18)
		return false
	if intent.auto_run:
		return true
	if intent.move.length() < tuning.run_threshold:
		return false
	return absf(Vector2.UP.angle_to(Vector2(intent.move.x, -intent.move.y))) <= deg_to_rad(tuning.run_cone_deg) * 0.5


func _world_dir(intent: InputIntent) -> Vector3:
	var move := Vector2(0.0, 1.0) if intent.auto_run else intent.move
	if move.is_zero_approx():
		return Vector3.ZERO
	return Vector3(move.x, 0.0, -move.y).normalized().rotated(Vector3.UP, intent.camera_yaw)
