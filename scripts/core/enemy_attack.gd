class_name EnemyAttack
extends RefCounted
## 적 공격 한 번의 단계 기계: 대기 → 예고(🟡/🔴 신호) → 공격(판정) → 회복 → 대기.
## 예고~공격 동안은 '위협 중' — 플레이어의 스틱+점프가 회피가 된다 (C16).

enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVER }

var phase := Phase.IDLE
var parryable := true            ## 🟡 true / 🔴 false

var _durations := {}
var _remaining := 0.0


func _init(telegraph := 0.6, active := 0.2, recover := 0.8) -> void:
	_durations = {Phase.TELEGRAPH: telegraph, Phase.ACTIVE: active, Phase.RECOVER: recover}


func start(is_parryable: bool) -> void:
	if phase != Phase.IDLE:
		return
	parryable = is_parryable
	phase = Phase.TELEGRAPH
	_remaining = _durations[Phase.TELEGRAPH]


## 이번 틱의 이벤트: &"hit" = 공격 판정 순간(ACTIVE 진입), &"done" = 회복 끝.
## delta가 커서 여러 단계를 넘으면 넘친 시간을 다음 단계로 이월한다.
func tick(delta: float) -> Array[StringName]:
	var events: Array[StringName] = []
	while phase != Phase.IDLE and delta >= _remaining:
		delta -= _remaining
		match phase:
			Phase.TELEGRAPH:
				phase = Phase.ACTIVE
				events.append(&"hit")
			Phase.ACTIVE:
				phase = Phase.RECOVER
			Phase.RECOVER:
				phase = Phase.IDLE
				events.append(&"done")
		if phase != Phase.IDLE:
			_remaining = _durations[phase]
	if phase != Phase.IDLE:
		_remaining -= delta
	return events


## 중단 (예: 패링당해 경직).
func cancel() -> void:
	phase = Phase.IDLE
	_remaining = 0.0


func is_threatening() -> bool:
	return phase == Phase.TELEGRAPH or phase == Phase.ACTIVE


func time_to_hit() -> float:
	return _remaining if phase == Phase.TELEGRAPH else 0.0
