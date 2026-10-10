class_name Stamina
extends RefCounted
## 스태미나 모델. 0이 되면 탈진하고, 최대치의 일정 비율까지 회복해야 다시 행동을 시작할 수 있다.

const EPSILON := 0.0001

var value: float
var exhausted := false

var _tuning: MovementTuning
var _since_spend: float


func _init(tuning: MovementTuning) -> void:
	_tuning = tuning
	value = tuning.stamina_max
	_since_spend = tuning.stamina_regen_delay


## 일회성 소모. 잔량이 부족하면 남은 만큼만 소모하고 false.
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	_since_spend = 0.0
	var enough := value >= amount
	value = maxf(value - amount, 0.0)
	if value <= EPSILON:
		value = 0.0
		exhausted = true
	return enough


## 지속 소모. 이번 소모로 0에 도달하면 false.
func drain(rate: float, delta: float) -> bool:
	spend(rate * delta)
	return value > 0.0


## 소모 없이 회복만 막는다 (예: 벽에 매달려 정지 중).
func hold() -> void:
	_since_spend = 0.0


func tick(delta: float) -> void:
	var regen_time := delta
	var delay := _tuning.stamina_regen_delay
	if _since_spend < delay:
		regen_time = maxf(delta - (delay - _since_spend), 0.0)
	_since_spend += delta
	value = minf(value + _tuning.stamina_regen * regen_time, _tuning.stamina_max)
	if exhausted and value >= _tuning.stamina_max * _tuning.exhausted_recover_ratio - EPSILON:
		exhausted = false


func can_start() -> bool:
	return not exhausted and value > 0.0
