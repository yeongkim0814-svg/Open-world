class_name Sluice
extends Node3D
## 고대 수로의 수문 (그룹 "interactable", "sluice"). 열면 문짝이 올라가고 섬 루트(FirstIsland)에 알린다.

const GATE_RAISE := 3.0

@export var index := 0

var opened := false
var _gate_base := Vector3.ZERO

@onready var _gate: Node3D = $Gate


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("sluice")
	_gate_base = _gate.position


func prompt() -> String:
	return "수문 (열림)" if opened else "수문 열기"


func interact(_player: Player) -> void:
	if opened:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.open_sluice(index)


## 섬 루트가 상태를 반영할 때 호출 (불러오기 포함).
func set_opened(value: bool) -> void:
	if opened == value:
		return
	opened = value
	var goal := _gate_base + Vector3(0, GATE_RAISE if value else 0.0, 0)
	if is_inside_tree():
		create_tween().tween_property(_gate, "position", goal, 1.5)
	else:
		_gate.position = goal
