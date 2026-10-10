class_name Durability
extends RefCounted
## 무기 내구도. 0이 되면 파손(사라지지 않음, 성능 저하) — 수리하면 최대치로 (C4).

var value: float
var max_value: float


func _init(max_v: float) -> void:
	max_value = max_v
	value = max_v


func wear(amount: float) -> void:
	value = maxf(value - amount, 0.0)


func is_broken() -> bool:
	return value <= 0.0


func repair() -> void:
	value = max_value
