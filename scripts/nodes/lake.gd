class_name Lake
extends Water
## 저수호 (설계서 4장). 원형 수면이 목표 수위로 천천히 움직인다. 노드 위치 = 호수 중심(xz), y는 무시.

@export var radius := 48.0         ## 둑 안쪽 벽까지 (둑 꼭대기 16 > 최고 수위 14.6이라 둑 밖은 잠기지 않음)
@export var base_level := 14.6
@export var bottom_y := -6.0       ## 분지 바닥(-4.24)보다 아래
@export var move_speed := 1.0       ## m/s

var level: float
var _target: float

@onready var _surface: Node3D = $Surface


func _ready() -> void:
	super._ready()
	level = base_level
	_target = base_level
	_place_surface()


func set_target(y: float) -> void:
	_target = y


func is_settled() -> bool:
	return is_equal_approx(level, _target)


func surface_y() -> float:
	return level


func depth_at(pos: Vector3) -> float:
	var center := global_position if is_inside_tree() else position
	if Vector2(pos.x - center.x, pos.z - center.z).length() > radius or pos.y < bottom_y:
		return -1.0
	var d := level - pos.y
	return d if d > 0.0 else -1.0


func _physics_process(delta: float) -> void:
	if not is_settled():
		level = move_toward(level, _target, move_speed * delta)
		_place_surface()


func _place_surface() -> void:
	if _surface:
		_surface.global_position = Vector3(global_position.x, level, global_position.z)
