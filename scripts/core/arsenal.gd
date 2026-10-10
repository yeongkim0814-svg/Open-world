class_name Arsenal
extends RefCounted
## 소지 무기 목록과 장착 무기. 무기마다 내구도를 따로 가진다.

var index := 0

var _weapons: Array[WeaponData] = []
var _durability: Array[Durability] = []


func _init(weapons: Array[WeaponData]) -> void:
	_weapons = weapons
	for w in weapons:
		_durability.append(Durability.new(w.durability))


func current() -> WeaponData:
	return _weapons[index]


func durability() -> Durability:
	return _durability[index]


## 다음 무기 (끝이면 처음으로).
func cycle() -> void:
	index = (index + 1) % _weapons.size()
