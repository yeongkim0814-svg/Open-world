class_name VirtualStick
extends RefCounted
## 플로팅 가상 스틱의 수학. 자기를 잡은 터치 index 하나만 추적한다 (멀티터치 안전).

const FULL_PUSH := 0.95

var _radius: float
var _dead_zone: float
var _index := -1
var _origin := Vector2.ZERO
var _offset := Vector2.ZERO


func _init(radius_px: float = 120.0, dead_zone: float = 0.15) -> void:
	_radius = radius_px
	_dead_zone = dead_zone


## 이미 다른 손가락이 잡고 있으면 false.
func press(index: int, pos: Vector2) -> bool:
	if _index != -1:
		return false
	_index = index
	_origin = pos
	_offset = Vector2.ZERO
	return true


func drag(index: int, pos: Vector2) -> void:
	if index == _index:
		_offset = (pos - _origin).limit_length(_radius)


func release(index: int) -> void:
	if index == _index:
		_index = -1
		_offset = Vector2.ZERO


func is_active() -> bool:
	return _index != -1


func origin() -> Vector2:
	return _origin


## 길이 ≤ 1, 데드존 안이면 0. 화면 위쪽 = +y.
func value() -> Vector2:
	var v := Vector2(_offset.x, -_offset.y) / _radius
	var len := v.length()
	if len < _dead_zone:
		return Vector2.ZERO
	return v.normalized() * minf((len - _dead_zone) / (1.0 - _dead_zone), 1.0)


func is_full_push() -> bool:
	return value().length() >= FULL_PUSH
