class_name Arrow
extends Node3D
## 플레이어 화살. 매 틱 이전→다음 위치 구간을 레이캐스트해 지형·적과 충돌을 판정한다 (빠른 화살이 얇은 대상을 뚫지 않게).

const WEAK_POINT_RADIUS := 0.45

var velocity := Vector3.ZERO

var _hit: Hit
var _exclude: Array[RID] = []
var _travelled := 0.0
var _tuning: CombatTuning = preload("res://resources/combat_tuning.tres")


func launch(origin: Vector3, vel: Vector3, hit: Hit, shooter: RID) -> void:
	global_position = origin
	velocity = vel
	_hit = hit
	_exclude = [shooter]
	_orient()


func _physics_process(delta: float) -> void:
	velocity.y -= _tuning.arrow_gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var target: Object = result.collider
		if target is Node and target.is_in_group("enemy") and target.is_alive():
			if target.has_method("core_point"):
				_hit.weak_point = result.position.distance_to(target.core_point()) <= WEAK_POINT_RADIUS
			target.take_hit(_hit)
		queue_free()
		return
	global_position = to
	_travelled += from.distance_to(to)
	_orient()
	if _travelled > _tuning.arrow_max_dist:
		queue_free()


func _orient() -> void:
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
