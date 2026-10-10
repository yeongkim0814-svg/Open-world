class_name Hit
extends RefCounted
## 플레이어가 적에게 주는 피해 1회. 장갑·약점 적용은 맞는 쪽이 amount_against로 계산한다.

var damage := 0.0
var armor_pierce := false
var stagger := false        ## 맞은 적의 공격을 끊고 경직시킴
var weak_point := false     ## 약점(코어)에 맞음


static func make(dmg: float, pierce := false, staggers := false) -> Hit:
	var h := Hit.new()
	h.damage = dmg
	h.armor_pierce = pierce
	h.stagger = staggers
	return h


## armor = 받는 피해 배율 (1.0 = 장갑 없음).
func amount_against(armor: float, weak_point_mult: float) -> float:
	var amount := damage * (1.0 if armor_pierce else armor)
	return amount * (weak_point_mult if weak_point else 1.0)


## 맞은 점에서 진행 방향으로 length만큼 더 뻗은 선분이 point 반경 radius 안을 지나는가.
## 코어가 충돌체 안에 들어 있어도, 화살이 코어를 향해 날아왔으면 약점 명중으로 본다.
static func passes_near(hit_pos: Vector3, dir: Vector3, point: Vector3, radius: float, length := 1.5) -> bool:
	var d := dir.normalized()
	var t := clampf((point - hit_pos).dot(d), 0.0, length)
	return (hit_pos + d * t).distance_to(point) <= radius
