class_name HeightField
extends RefCounted
## 흑백 높이 지도 → 높이·법선. 섬 중심 = 원점, 이미지 좌상 = (-size/2, -size/2) (x 오른쪽, z 아래 = 남쪽).
## 밝기는 빨강 채널로 읽으므로 L8이든 RGB든, 크기가 몇이든 동작한다.

var world_size: float

var _img: Image
var _w: int
var _h: int
var _min: float
var _max: float


func _init(image: Image, size: float, min_h: float, max_h: float) -> void:
	_img = image
	if _img.is_compressed():
		_img = _img.duplicate()
		_img.decompress()
	world_size = size
	_w = _img.get_width()
	_h = _img.get_height()
	_min = min_h
	_max = max_h


func height_at(x: float, z: float) -> float:
	var px := clampf((x / world_size + 0.5) * (_w - 1), 0.0, _w - 1)
	var pz := clampf((z / world_size + 0.5) * (_h - 1), 0.0, _h - 1)
	var x0 := int(floor(px)); var z0 := int(floor(pz))
	var x1 := mini(x0 + 1, _w - 1); var z1 := mini(z0 + 1, _h - 1)
	var tx := px - x0; var tz := pz - z0
	var top := lerpf(_sample(x0, z0), _sample(x1, z0), tx)
	var bottom := lerpf(_sample(x0, z1), _sample(x1, z1), tx)
	return lerpf(top, bottom, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := world_size / maxf(_w - 1, 1)
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _sample(px: int, pz: int) -> float:
	return lerpf(_min, _max, _img.get_pixel(px, pz).r)
