class_name Interactable
extends Node3D
## 상호작용 대상 (C15). 그룹 "interactable". M2: 줍기만 지원 — 플레이어 parts +1 후 사라진다.

@export var label := "기계 부품"
@export var verb := "줍기"


func _ready() -> void:
	add_to_group("interactable")


func prompt() -> String:
	return "%s: %s" % [verb, label]


func interact(player: Player) -> void:
	player.parts += 1
	queue_free()
