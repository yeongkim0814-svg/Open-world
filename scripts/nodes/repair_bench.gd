class_name RepairBench
extends Node3D
## 수리대 (C19): 기계 부품 1개로 장착 무기를 완전히 수리한다. M3 임시 시설 — 이후 마을 대장장이로 바뀐다.

const COST := 1


func _ready() -> void:
	add_to_group("interactable")


func prompt_for(weapon_name: String, durability: Durability, parts: int) -> String:
	if durability.value >= durability.max_value:
		return "수리: %s (최대)" % weapon_name
	if parts < COST:
		return "수리: 부품 부족"
	return "수리: %s (부품 %d)" % [weapon_name, COST]


func prompt() -> String:
	var p := _player()
	if p == null:
		return "수리"
	return prompt_for(p.combat.arsenal.current().display_name, p.combat.arsenal.durability(), p.parts)


func interact(player: Player) -> void:
	var d := player.combat.arsenal.durability()
	if player.parts >= COST and d.value < d.max_value:
		player.parts -= COST
		d.repair()


func _player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null
