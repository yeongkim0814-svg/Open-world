class_name Water
extends Node3D
## 물 영역 (그룹 "water"). 중심이 이 노드 위치인 상자, 윗면 = 수면. 물리 충돌 없이 깊이만 계산한다.

@export var size := Vector3(10, 4, 10)
@export var circular := false   ## true = 원기둥 (지름 size.x) — 둥근 호수


func _ready() -> void:
	add_to_group("water")


func surface_y() -> float:
	return global_position.y + size.y * 0.5 if is_inside_tree() else position.y + size.y * 0.5


## pos(발 위치)가 수면 아래 몇 m인지. 수평 범위 밖이거나 수면 위·바닥 아래면 -1.
func depth_at(pos: Vector3) -> float:
	var center := global_position if is_inside_tree() else position
	var local := pos - center
	if absf(local.x) > size.x * 0.5 or absf(local.z) > size.z * 0.5 or local.y < -size.y * 0.5:
		return -1.0
	if circular and local.x * local.x + local.z * local.z > size.x * size.x * 0.25:
		return -1.0
	var d := surface_y() - pos.y
	return d if d > 0.0 else -1.0
