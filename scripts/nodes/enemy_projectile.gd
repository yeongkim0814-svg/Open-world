class_name EnemyProjectile
extends Node3D
## 기계가 쏜 탄. 비행·판정 규칙은 EnemyShot. 그룹 "threat": 가까이 날아오면 점프 버튼이 회피가 된다 (C16).
## 🟡 탄을 패링하면 쏜 기계에게 되돌아가 피해를 준다 (C20).

const PLAYER_RADIUS := 0.7
const SHOOTER_RADIUS := 1.0
const MAX_DIST := 60.0
const REFLECT_DAMAGE_MULT := 2.0

var shot: EnemyShot

var _shooter: Node3D
var _damage := 0.0


func _ready() -> void:
	add_to_group("threat")


func launch(s: EnemyShot, shooter: Node3D, damage: float) -> void:
	shot = s
	_shooter = shooter
	_damage = damage
	global_position = s.position
	var mat: StandardMaterial3D = ($Mesh as MeshInstance3D).get_surface_override_material(0)
	var c := Color(1.0, 0.85, 0.2) if s.parryable else Color(1.0, 0.15, 0.1)
	mat.albedo_color = c
	mat.emission = c
	if not s.parryable:
		scale = Vector3.ONE * 1.5


func is_threatening() -> bool:
	var p := _player()
	return shot != null and p != null and shot.is_threat_to(_target_point(p), Player.THREAT_RANGE)


## 패링당함 → 쏜 기계 쪽으로 되돌아간다.
func on_parried() -> void:
	if is_instance_valid(_shooter):
		shot.reflect(_shooter.global_position + Vector3.UP)


func _physics_process(delta: float) -> void:
	if shot == null:
		return
	var prev := shot.step(delta)
	global_position = shot.position
	var p := _player()
	if not shot.resolved and p != null and shot.crosses(prev, _target_point(p), PLAYER_RADIUS):
		shot.resolved = true
		p.combat.on_enemy_hit(shot.parryable, self, _damage)
		if not shot.reflected and not p.locomotion.is_invulnerable():
			queue_free()            # 맞거나 막힘 → 소멸. 회피했으면 그대로 지나간다
			return
	if shot.reflected and is_instance_valid(_shooter) and _shooter.is_alive() \
			and shot.crosses(prev, _shooter.global_position + Vector3.UP, SHOOTER_RADIUS):
		_shooter.take_hit(Hit.make(_damage * REFLECT_DAMAGE_MULT))
		queue_free()
		return
	if _hits_terrain(prev, p) or shot.expired(MAX_DIST):
		queue_free()


func _hits_terrain(prev: Vector3, p: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(prev, shot.position)
	var exclude: Array[RID] = []
	if is_instance_valid(_shooter):
		exclude.append(_shooter.get_rid())
	if p != null:
		exclude.append(p.get_rid())
	query.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _target_point(p: Node3D) -> Vector3:
	return p.global_position + Vector3.UP


func _player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null
