class_name VirtualStick
extends RefCounted
## 플로팅 가상 스틱의 수학. 자기를 잡은 터치 index 하나만 추적한다 (멀티터치 안전).
## 스틱을 위로 반경의 LOCK_ZONE 배 이상 끌어올린 채 놓으면 자동 달리기 요청 (PUBG/Arena Breakout 방식).

const LOCK_ZONE := 1.4

var _radius: float
var _dead_zone: float
var _index := -1
var _origin := Vector2.ZERO
var _offset := Vector2.ZERO
var _raw := Vector2.ZERO        ## 반경 제한 전 오프셋 (잠금 구역 판정용)


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
	_raw = Vector2.ZERO
	return true


func drag(index: int, pos: Vector2) -> void:
	if index == _index:
		_raw = pos - _origin
		_offset = _raw.limit_length(_radius)


## 자기 손가락이 잠금 구역에서 떨어졌으면 true (= 자동 달리기 시작).
func release(index: int) -> bool:
	if index != _index:
		return false
	var lock := in_lock_zone()
	_index = -1
	_offset = Vector2.ZERO
	_raw = Vector2.ZERO
	return lock


## 스틱 위쪽으로 반경의 LOCK_ZONE 배 이상, 좌우로는 반경 이내.
func in_lock_zone() -> bool:
	return _index != -1 and -_raw.y >= _radius * LOCK_ZONE and absf(_raw.x) <= _radius


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
