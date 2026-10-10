class_name Flurry
extends RefCounted
## 패링 성공 후 슬로우모션 연타 창 (C5). 전역 time_scale이 아니라 적에게만 적용할 시간 배율을 제공한다.

var active := false

var _t: CombatTuning
var _left := 0.0


func _init(t: CombatTuning) -> void:
	_t = t


func start() -> void:
	active = true
	_left = _t.flurry_duration


func tick(delta: float) -> void:
	if not active:
		return
	_left -= delta
	if _left <= 0.0:
		active = false


func enemy_time_scale() -> float:
	return _t.flurry_enemy_time_scale if active else 1.0
