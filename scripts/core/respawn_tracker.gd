class_name RespawnTracker
extends RefCounted
## 안전 지점 기록과 추락 판정. 바닥에 연속으로 1초 서 있을 때마다 그 위치를 안전 지점으로 갱신한다.

const SAFE_TIME := 1.0

var safe_point := Vector3.ZERO

var _fall_y: float
var _grounded_time := 0.0


func _init(fall_y: float) -> void:
	_fall_y = fall_y


## 재시작이 필요하면 true.
func update(pos: Vector3, on_floor: bool, delta: float) -> bool:
	if on_floor:
		_grounded_time += delta
		if _grounded_time >= SAFE_TIME:
			safe_point = pos
			_grounded_time = 0.0
	else:
		_grounded_time = 0.0
	return pos.y < _fall_y
