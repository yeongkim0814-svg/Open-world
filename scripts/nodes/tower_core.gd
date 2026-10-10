class_name TowerCore
extends Node3D
## 착취탑 꼭대기 코어 (그룹 "interactable"). 「정지」하면 섬 루트(FirstIsland)가 회복 연출을 시작한다.


func _ready() -> void:
	add_to_group("interactable")


func prompt() -> String:
	var world := get_tree().get_first_node_in_group("world")
	return "탑 (멈춤)" if world and world.state.tower_stopped else "정지"


func interact(_player: Player) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.stop_tower()
