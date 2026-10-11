class_name VegContext
extends RefCounted
## 식생 배치용 지도 조회·제외 규칙: 높이장 + 구역/길 이미지 + 표식 + 물 판정을 묶는다.
## 이미지 조회 픽셀 = round((x / world + 0.5) * (N - 1)) (굽기 관례), 밖은 가장자리로 clamp.

enum Layer { GRASS, SHRUB, TREE, ROCK }

# 길 제외 반경 (m): 흙·포장 1.5, 수로 2, 개천 3 (excluded 에서 사용)
const PATH_PRIORITY := [4, 3, 2, 1]
const MIN_HEIGHT := 0.8
const DIRS := [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7071068, 0.7071068), Vector2(-0.7071068, 0.7071068),
	Vector2(0.7071068, -0.7071068), Vector2(-0.7071068, -0.7071068),
]
# 표식 종류별 제외 반경 (m) — 모든 층 제외
const MARKER_R := {"village": 45.0, "sluice": 15.0, "bridge": 10.0, "lookout": 15.0, "ruin": 12.0, "start": 8.0}
const HILL_VILLAGE_R := 35.0
const LAKE_BANK := 12.0
const TOWER_PAD := 5.0

var field: HeightField
var _zones: Image
var _paths: Image
var _cfg: Dictionary
var _water: Callable
var _world: float
# 사전 계산한 표식: {x, z, r2, min_layer (이 층 이상만 제외)}
var _marker_ex: Array = []
var _peaks: Array = []
var _summit_r: float


func _init(p_field: HeightField, zones: Image, paths: Image, markers: Array, cfg := {}, water_level := Callable()) -> void:
	field = p_field
	_zones = zones
	_paths = paths
	_cfg = cfg
	_water = water_level
	_world = field.world_size
	_summit_r = float(cfg.get("summit_radius", 180.0))
	for m in markers:
		_add_marker(m)


func _add_marker(m: Dictionary) -> void:
	var kind := String(m.get("kind", ""))
	var x := float(m.get("x", 0.0)); var z := float(m.get("z", 0.0))
	if kind == "peak":
		_peaks.append(Vector2(x, z))
	elif kind == "hill_village":
		_marker_ex.append({"x": x, "z": z, "r2": HILL_VILLAGE_R * HILL_VILLAGE_R, "min_layer": Layer.TREE})
	elif kind == "tower":
		var r := float(_cfg.get("tower_radius", 0.0)) + TOWER_PAD
		_marker_ex.append({"x": x, "z": z, "r2": r * r, "min_layer": Layer.GRASS})
	elif kind == "lake":
		# 둑 위 풀은 허용(물 판정이 거른다) — 덤불 이상 층만 반경 + 둑 안에서 제외
		var r := float(m.get("radius", _cfg.get("lake_radius", 0.0))) + LAKE_BANK
		_marker_ex.append({"x": x, "z": z, "r2": r * r, "min_layer": Layer.SHRUB})
	elif MARKER_R.has(kind):
		var r2: float = MARKER_R[kind]
		_marker_ex.append({"x": x, "z": z, "r2": r2 * r2, "min_layer": Layer.GRASS})


func zone_at(x: float, z: float) -> int:
	return _read(_zones, x, z)


## 다른 구역까지의 거리: 8방향 × 4 m 단계 표본, 없으면 max_m
func edge_dist_zone(x: float, z: float, max_m := 20.0) -> float:
	var z0 := zone_at(x, z)
	var d := 4.0
	while d <= max_m:
		for dir in DIRS:
			if zone_at(x + dir.x * d, z + dir.y * d) != z0:
				return d
		d += 4.0
	return max_m


## 반경 r 안 (중심 + 8방향 두 고리) 가장 우선인 길 종류. 개천 4 > 수로 3 > 포장 2 > 흙 1, 없음 0
func path_near(x: float, z: float, r: float) -> int:
	return _best_path(_path_kinds(x, z, r))


func slope_ny(x: float, z: float) -> float:
	return field.normal_at(x, z).y


func excluded(layer: int, x: float, z: float) -> bool:
	var g := field.height_at(x, z)
	if g < MIN_HEIGHT:
		return true
	if _water.is_valid() and float(_water.call(x, z)) > g:
		return true
	var p := Vector2(x, z)
	for m in _marker_ex:
		if layer >= m["min_layer"] and p.distance_squared_to(Vector2(m["x"], m["z"])) < m["r2"]:
			return true
	if layer == Layer.TREE:
		for pk in _peaks:
			if p.distance_to(pk) < _summit_r:
				return true
	# 길: 종류마다 제외 반경이 다르다
	if _path_kinds(x, z, 1.5) & 0b00110:
		return true
	if _path_kinds(x, z, 2.0) & 0b01000:
		return true
	if _path_kinds(x, z, 3.0) & 0b10000:
		return true
	return false


## 발 크기 foot > 0 이면 (±foot, ±foot) 네 모서리 중 가장 낮은 높이
func ground_y(x: float, z: float, foot := 0.0) -> float:
	if foot <= 0.0:
		return field.height_at(x, z)
	return minf(
		minf(field.height_at(x - foot, z - foot), field.height_at(x + foot, z - foot)),
		minf(field.height_at(x - foot, z + foot), field.height_at(x + foot, z + foot)))


# 반경 r 안 중심 + 8방향 (r/2, r 두 고리) 표본에 나온 길 종류 비트마스크 (비트 k = 종류 k)
func _path_kinds(x: float, z: float, r: float) -> int:
	var mask := 0
	var v := _read(_paths, x, z)
	if v > 0:
		mask |= 1 << v
	for dir in DIRS:
		for f in [0.5, 1.0]:
			v = _read(_paths, x + dir.x * r * f, z + dir.y * r * f)
			if v > 0:
				mask |= 1 << v
	return mask


func _best_path(mask: int) -> int:
	for k in PATH_PRIORITY:
		if mask & (1 << k):
			return k
	return 0


func _read(img: Image, x: float, z: float) -> int:
	var w := img.get_width(); var h := img.get_height()
	var px := clampi(roundi((x / _world + 0.5) * (w - 1)), 0, w - 1)
	var pz := clampi(roundi((z / _world + 0.5) * (h - 1)), 0, h - 1)
	return img.get_pixel(px, pz).r8
