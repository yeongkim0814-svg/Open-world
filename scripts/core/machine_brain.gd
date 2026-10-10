class_name MachineBrain
extends RefCounted
## 수호 기계의 판단: 대기 → (경계) 추적/공격/후퇴 → 집에서 너무 멀어지면 귀환.
## 귀환을 시작하면 집에 닿을 때까지 플레이어를 무시한다 (경계선에서 왔다 갔다 하지 않게).

enum Mode { IDLE, CHASE, ATTACK, RETREAT, RETURN }

const HOME_EPS := 1.0

var alerted := false

var _d: MachineData
var _returning := false


func _init(data: MachineData) -> void:
	_d = data


func decide(dist_player: float, dist_home: float, hit_this_tick: bool) -> Mode:
	if _returning:
		if dist_home > HOME_EPS:
			return Mode.RETURN
		_returning = false
	if hit_this_tick or dist_player <= _d.alert_range:
		alerted = true
	if dist_home > _d.leash:
		alerted = false
		_returning = true
		return Mode.RETURN
	if not alerted:
		return Mode.RETURN if dist_home > HOME_EPS else Mode.IDLE
	if not _d.ranged:
		return Mode.ATTACK if dist_player <= _d.attack_range else Mode.CHASE
	if dist_player < _d.keep_min:
		return Mode.RETREAT
	return Mode.CHASE if dist_player > _d.attack_range else Mode.ATTACK


func is_red(count: int) -> bool:
	return _d.red_every > 0 and count % _d.red_every == 0
