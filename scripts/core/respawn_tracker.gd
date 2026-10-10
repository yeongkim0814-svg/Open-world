class_name RespawnTracker
extends RefCounted
## 안전 지점 기록과 추락 판정. '안정된 바닥'(사방에 바닥이 있음)에 연속으로 1초 서 있을 때마다
## 그 위치를 안전 지점으로 갱신한다. 가장자리에서는 갱신하지 않아 재시작 직후 다시 떨어지지 않는다.

const SAFE_TIME := 1.0

var safe_point := Vector3.ZERO

var _fall_y: float
var _grounded_time := 0.0


func _init(fall_y: float) -> void:
	_fall_y = fall_y


## 재시작이 필요하면 true. stable = 주변 사방에 바닥이 있는지 (Player가 레이캐스트로 판정).
func update(pos: Vector3, on_floor: bool, stable: bool, delta: float) -> bool:
	if on_floor and stable:
		_grounded_time += delta
		if _grounded_time >= SAFE_TIME:
			safe_point = pos
			_grounded_time = 0.0
	else:
		_grounded_time = 0.0
	return pos.y < _fall_y
