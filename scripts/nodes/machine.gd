class_name Machine
extends CharacterBody3D
## 수호 기계 (02 설계서 5장). 판단은 MachineBrain, 공격 단계는 EnemyAttack, 수치는 MachineData.
## 근접형은 다가와 베고, 원거리형은 거리를 두고 탄을 쏜다. 집(시작 위치)에서 너무 멀어지면 돌아간다.

const COLOR_PARRYABLE := Color(1.0, 0.85, 0.2)
const COLOR_UNPARRYABLE := Color(1.0, 0.15, 0.1)
const TURN_SPEED := 5.0
const GRAVITY := 20.0
const PARRY_STAGGER := 1.0
const PROJECTILE_SCENE := preload("res://scenes/enemy_projectile.tscn")
const PART_SCENE := preload("res://scenes/pickup_part.tscn")

@export var data: MachineData
@export var combat_tuning: CombatTuning = preload("res://resources/combat_tuning.tres")

var hp: float
var attack: EnemyAttack
var brain: MachineBrain

var _home: Vector3
var _slow: Flurry
var _stagger := 0.0
var _cooldown := 1.0
var _count := 0
var _dead_time := 0.0
var _hit_flash := 0.0
var _hit_this_tick := false

@onready var _eye_mat: StandardMaterial3D = ($Eye as MeshInstance3D).get_surface_override_material(0)
@onready var _body_mat: StandardMaterial3D = ($Body as MeshInstance3D).get_surface_override_material(0)
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _label: Label3D = $HpLabel


func _ready() -> void:
	add_to_group("enemy")
	_home = global_position
	_slow = Flurry.new(combat_tuning)
	_reset()


func _reset() -> void:
	hp = data.max_hp
	attack = EnemyAttack.new(data.telegraph, data.active, data.recover)
	brain = MachineBrain.new(data)
	_stagger = 0.0
	_cooldown = 1.0
	_shape.disabled = false


func is_alive() -> bool:
	return hp > 0.0


func is_alerted() -> bool:
	return is_alive() and brain.alerted


func is_threatening() -> bool:
	return is_alive() and attack.is_threatening()


## 약점(발광 코어) 위치 — 화살이 이 근처에 맞으면 weak_point_mult.
func core_point() -> Vector3:
	return ($Core as Node3D).global_position


func take_hit(hit: Hit) -> void:
	if not is_alive():
		return
	hp -= hit.amount_against(data.armor, combat_tuning.weak_point_mult)
	_hit_flash = 0.15
	_hit_this_tick = true
	if hit.stagger:
		attack.cancel()
		_stagger = maxf(_stagger, combat_tuning.hit_stagger_time)
	if hp <= 0.0:
		_die()


## 패링당함: 공격 취소, 경직, 이 개체만 슬로우모션 (C5).
func on_parried() -> void:
	attack.cancel()
	_stagger = PARRY_STAGGER
	_slow.start()


func _die() -> void:
	attack.cancel()
	_dead_time = 0.0
	_shape.set_deferred("disabled", true)
	for i in data.part_drop:
		var part: Node3D = PART_SCENE.instantiate()
		get_parent().add_child(part)
		part.global_position = Vector3(global_position.x + 0.8 * i, global_position.y, global_position.z)


func _physics_process(delta: float) -> void:
	_slow.tick(delta)
	var scaled := delta * _slow.enemy_time_scale()
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_update_visuals()
	if not is_alive():
		_dead_time += delta
		if _dead_time >= data.respawn_time:
			global_position = _home
			velocity = Vector3.ZERO
			_reset()
		return
	var p := _player()
	if p == null:
		return
	var dist_player := _flat(p.global_position - global_position).length()
	var dist_home := _flat(_home - global_position).length()
	var mode := brain.decide(dist_player, dist_home, _hit_this_tick)
	_hit_this_tick = false
	var move := Vector3.ZERO
	if _stagger > 0.0:
		_stagger -= scaled
	else:
		move = _move_dir(mode, p)
		_tick_attack(mode, p, scaled)
		if mode == MachineBrain.Mode.IDLE and hp < data.max_hp:
			hp = data.max_hp            # 집에 돌아와 쉬면 회복
	var look := _flat(p.global_position - global_position) if brain.alerted else move
	_face(look, scaled)
	velocity.x = move.x * data.move_speed * _slow.enemy_time_scale()
	velocity.z = move.z * data.move_speed * _slow.enemy_time_scale()
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


## 공격 중(예고~회복)에는 멈춰 선다.
func _move_dir(mode: MachineBrain.Mode, p: Node3D) -> Vector3:
	if attack.phase != EnemyAttack.Phase.IDLE:
		return Vector3.ZERO
	match mode:
		MachineBrain.Mode.CHASE:
			return _flat(p.global_position - global_position).normalized()
		MachineBrain.Mode.RETREAT:
			return -_flat(p.global_position - global_position).normalized()
		MachineBrain.Mode.RETURN:
			return _flat(_home - global_position).normalized()
	return Vector3.ZERO


func _tick_attack(mode: MachineBrain.Mode, p: Player, scaled: float) -> void:
	var events := attack.tick(scaled)
	if events.has(&"hit"):
		if data.ranged:
			_shoot(p)
		elif _in_reach(p):
			p.combat.on_enemy_hit(attack.parryable, self, data.damage)
	if attack.phase == EnemyAttack.Phase.IDLE:
		_cooldown -= scaled
		if _cooldown <= 0.0 and mode == MachineBrain.Mode.ATTACK:
			_count += 1
			attack.start(not brain.is_red(_count))
			_cooldown = data.attack_interval


func _shoot(p: Node3D) -> void:
	var from := ($Muzzle as Node3D).global_position
	var speed := data.shot_speed if attack.parryable else data.red_shot_speed
	var shot := EnemyShot.new(from, p.global_position + Vector3.UP, speed, attack.parryable)
	var proj: EnemyProjectile = PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.launch(shot, self, data.damage)


func _in_reach(p: Node3D) -> bool:
	var to := _flat(p.global_position - global_position)
	return to.length() <= data.attack_range + 0.5 and (-global_basis.z).angle_to(to) <= deg_to_rad(60.0)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(TURN_SPEED * delta, 1.0))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _update_visuals() -> void:
	var telegraph := attack != null and attack.phase == EnemyAttack.Phase.TELEGRAPH
	var c := COLOR_PARRYABLE if attack == null or attack.parryable else COLOR_UNPARRYABLE
	_eye_mat.emission = c if telegraph else Color(0.2, 0.6, 1.0)
	_eye_mat.emission_energy_multiplier = 4.0 if telegraph else 1.0
	_body_mat.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else (Color(0.2, 0.2, 0.2) if not is_alive() else Color(0.45, 0.5, 0.55))
	_label.text = "%s %d" % [data.display_name, maxi(roundi(hp), 0)] if is_alive() else "…"


func _player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null
