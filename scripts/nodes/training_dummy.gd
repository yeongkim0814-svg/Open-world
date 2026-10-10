class_name TrainingDummy
extends CharacterBody3D
## 허수아비 적 (M2 전투 검증용). 이동하지 않고 플레이어를 향해 돌며, 가까이 오면 공격을 반복한다.
## 3번 중 1번은 🔴(패링 불가). 패링당하면 경직 + 슬로우모션(이 개체만).

const COLOR_PARRYABLE := Color(1.0, 0.85, 0.2)
const COLOR_UNPARRYABLE := Color(1.0, 0.15, 0.1)
const TURN_SPEED := 4.0

@export var combat_tuning: CombatTuning = preload("res://resources/combat_tuning.tres")
@export var max_hp := 100.0
@export var alert_range := 15.0
@export var attack_range := 2.5
@export var damage := 20.0
@export var attack_interval := 1.2
@export var respawn_time := 3.0

var hp: float
var attack := EnemyAttack.new(0.6, 0.2, 0.8)

var _slow: Flurry
var _stagger := 0.0
var _cooldown := 1.0
var _count := 0
var _dead_time := 0.0
var _hit_flash := 0.0
var _alerted := false

@onready var _head_mat: StandardMaterial3D = ($Head as MeshInstance3D).get_surface_override_material(0)
@onready var _body_mat: StandardMaterial3D = ($Body as MeshInstance3D).get_surface_override_material(0)
@onready var _label: Label3D = $HpLabel


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	_slow = Flurry.new(combat_tuning)


func is_alive() -> bool:
	return hp > 0.0


## 한 번 경계하면 전투 해제 거리(25m)를 벗어날 때까지 유지 (전투 상태 히스테리시스가 실제로 작동하도록).
func is_alerted() -> bool:
	return is_alive() and _alerted


func _update_alert(p: Node3D) -> void:
	var d := global_position.distance_to(p.global_position)
	if d <= alert_range:
		_alerted = true
	elif d > combat_tuning.combat_exit_dist:
		_alerted = false


func is_threatening() -> bool:
	return is_alive() and attack.is_threatening()


func take_hit(hit: Hit) -> void:
	if not is_alive():
		return
	hp -= hit.amount_against(1.0, combat_tuning.weak_point_mult)
	if hit.stagger:
		attack.cancel()
		_stagger = maxf(_stagger, combat_tuning.hit_stagger_time)
	_hit_flash = 0.15
	if hp <= 0.0:
		attack.cancel()
		_dead_time = 0.0


## 패링당함: 공격 취소, 1초 경직, 이 개체만 슬로우모션.
func on_parried() -> void:
	attack.cancel()
	_stagger = 1.0
	_slow.start()


func _physics_process(delta: float) -> void:
	_slow.tick(delta)
	var scaled := delta * _slow.enemy_time_scale()
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_update_visuals()
	if not is_alive():
		_dead_time += delta
		if _dead_time >= respawn_time:
			hp = max_hp
		return
	var p := _player()
	if p == null:
		return
	_update_alert(p)
	_face(p.global_position, scaled)
	if _stagger > 0.0:
		_stagger -= scaled
		return
	var events := attack.tick(scaled)
	if events.has(&"hit") and _in_reach(p):
		p.combat.on_enemy_hit(attack, self, damage)
	if attack.phase == EnemyAttack.Phase.IDLE:
		_cooldown -= scaled
		if _cooldown <= 0.0 and global_position.distance_to(p.global_position) <= attack_range:
			_count += 1
			attack.start(_count % 3 != 0)
			_cooldown = attack_interval


func _in_reach(p: Node3D) -> bool:
	var to := p.global_position - global_position
	to.y = 0.0
	var fwd := -global_basis.z
	return to.length() <= attack_range + 0.5 and fwd.angle_to(to) <= deg_to_rad(60.0)


func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(TURN_SPEED * delta, 1.0))


func _update_visuals() -> void:
	var telegraph := attack.phase == EnemyAttack.Phase.TELEGRAPH
	_head_mat.emission_enabled = telegraph
	_head_mat.emission = COLOR_PARRYABLE if attack.parryable else COLOR_UNPARRYABLE
	_head_mat.emission_energy_multiplier = 3.0
	_head_mat.albedo_color = (COLOR_PARRYABLE if attack.parryable else COLOR_UNPARRYABLE) if telegraph else Color(0.3, 0.3, 0.3)
	_body_mat.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else (Color(0.25, 0.25, 0.25) if not is_alive() else Color(0.55, 0.45, 0.35))
	($Body as Node3D).rotation.x = -0.4 if attack.phase == EnemyAttack.Phase.ACTIVE else (0.25 if _stagger > 0.0 else 0.0)
	_label.text = "%d" % maxi(roundi(hp), 0) if is_alive() else "…"


func _player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null
