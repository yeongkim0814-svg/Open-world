class_name BowDraw
extends RefCounted
## 활 당기기: 누르고 있는 동안 당기고, 떼면 당긴 비율로 발사한다 (C18).
## 짧게 탭해도 최소 비율로 발사된다. 취소(무기 교체 등)하면 발사하지 않는다.

var drawing := false

var _weapon: WeaponData
var _time := 0.0


func _init(weapon: WeaponData) -> void:
	_weapon = weapon


func start() -> void:
	drawing = true
	_time = 0.0


func tick(delta: float) -> void:
	if drawing:
		_time += delta


func ratio() -> float:
	var t := clampf(_time / _weapon.draw_time, 0.0, 1.0) if _weapon.draw_time > 0.0 else 1.0
	return lerpf(_weapon.min_draw_ratio, 1.0, t)


## 발사 비율. 당기는 중이 아니었으면 -1.0.
func release() -> float:
	if not drawing:
		return -1.0
	drawing = false
	return ratio()


func cancel() -> void:
	drawing = false
	_time = 0.0
