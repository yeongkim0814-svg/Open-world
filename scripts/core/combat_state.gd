class_name CombatState
extends RefCounted
## 전투 상태 진입/해제. 진입 거리와 해제 거리를 달리해(히스테리시스) 경계선에서 깜빡이지 않게 한다.

var active := false

var _t: CombatTuning
var _out_time := 0.0


func _init(t: CombatTuning) -> void:
	_t = t


## nearest_alert_dist: 플레이어를 경계 중인 가장 가까운 적까지 거리 (없으면 INF).
## engaged: 이번 틱에 공격했거나 맞음 → 즉시 진입.
func update(nearest_alert_dist: float, engaged: bool, delta: float) -> bool:
	if engaged or nearest_alert_dist <= _t.combat_enter_dist:
		active = true
		_out_time = 0.0
	elif active:
		if nearest_alert_dist > _t.combat_exit_dist:
			_out_time += delta
			if _out_time >= _t.combat_exit_delay:
				active = false
				_out_time = 0.0
		else:
			_out_time = 0.0
	return active
