class_name EnemyShot
extends RefCounted
## 기계가 쏜 탄 하나의 비행·판정 (노드 비의존). 🟡 탄은 패링하면 되받아친다 (C20).
## resolved = 플레이어 판정을 이미 마침(맞음·막음·회피) → 다시 판정하지 않는다.

const REFLECT_SPEED_MULT := 1.5

var position: Vector3
var velocity: Vector3
var parryable: bool
var reflected := false
var resolved := false
var travelled := 0.0


func _init(from: Vector3, to: Vector3, speed: float, is_parryable: bool) -> void:
	position = from
	velocity = (to - from).normalized() * speed
	parryable = is_parryable


## 한 틱 이동. 이전 위치를 돌려준다 (구간 판정용).
func step(delta: float) -> Vector3:
	var prev := position
	position += velocity * delta
	travelled += velocity.length() * delta
	return prev


## 이번 틱 이동 구간(prev → position)이 point 반경 radius 안을 지났는가.
func crosses(prev: Vector3, point: Vector3, radius: float) -> bool:
	var seg := position - prev
	var t := 0.0
	if seg.length_squared() > 0.0:
		t = clampf((point - prev).dot(seg) / seg.length_squared(), 0.0, 1.0)
	return (prev + seg * t).distance_to(point) <= radius


## 플레이어를 향해 날아오는 중이고 range 안 → 회피 문맥 (C16).
func is_threat_to(point: Vector3, threat_range: float) -> bool:
	if reflected or resolved:
		return false
	var to := point - position
	return to.length() <= threat_range and to.dot(velocity) > 0.0


func reflect(toward: Vector3) -> void:
	velocity = (toward - position).normalized() * velocity.length() * REFLECT_SPEED_MULT
	reflected = true
	resolved = true


func expired(max_dist: float) -> bool:
	return travelled > max_dist
