class_name Guard
extends RefCounted
## 방어·패링 판정 (C7, C11). 방어 버튼을 '누르는 순간'으로부터 판정 창 안에 적의 공격이 맞으면 패링,
## 누른 채 유지 중이면 막기. 1초 안에 다시 누를수록 판정 창이 줄어 연타가 최적해가 되지 않는다.

enum Result { PARRIED, BLOCKED, GUARD_BREAK, HIT }

var holding := false

var _t: CombatTuning
var _since_press := INF
var _ratio := 1.0


func _init(t: CombatTuning) -> void:
	_t = t


func press() -> void:
	if _since_press < _t.parry_spam_window:
		_ratio = maxf(_ratio * (1.0 - _t.parry_spam_shrink), _t.parry_min_ratio)
	else:
		_ratio = 1.0
	_since_press = 0.0
	holding = true


func release() -> void:
	holding = false


func tick(delta: float) -> void:
	_since_press += delta


## 적 공격이 맞는 순간(&"hit") 호출. parryable = 🟡, has_shield = 방패 장착,
## can_afford_block = 막기에 쓸 스태미나가 남아 있는지 (없으면 막기가 가드 브레이크로 바뀜).
func resolve(parryable: bool, has_shield: bool, can_afford_block := true) -> Result:
	var window := (_t.parry_window_shield if has_shield else _t.parry_window_weapon) * _ratio
	if parryable and _since_press <= window:
		return Result.PARRIED
	if holding:
		return Result.BLOCKED if parryable and can_afford_block else Result.GUARD_BREAK
	return Result.HIT
