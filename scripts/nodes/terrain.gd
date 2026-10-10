class_name Terrain
extends StaticBody3D
## 높이 지도 PNG → 로우폴리 지형 메시 + 충돌 (설계서 5.2). 시작할 때 만든다.
## 색: 낮은 곳 = 모래, 45° 넘는 경사 = 바위, 그 외 = 풀 (회복 후 색 — 셰이더가 잿빛으로 바꿈).

const SAND := Color("#D8C79A")
const ROCK := Color("#C49A6C")
const GRASS := Color("#7FB45A")
const VITALITY_SHADER := preload("res://shaders/vitality.gdshader")

@export var height_map: Texture2D
@export var world_size := 300.0
@export var min_h := -10.0
@export var max_h := 60.0
@export var cell := 2.0

var field: HeightField
var build_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	field = HeightField.new(height_map.get_image(), world_size, min_h, max_h)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = TerrainMesh.build(field, cell, _color)
	var mat := ShaderMaterial.new()
	mat.shader = VITALITY_SHADER
	mat.set_shader_parameter("use_vertex_color", true)
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	var n := int(round(world_size / cell)) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = TerrainMesh.heights(field, cell)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(cell, 1.0, cell)
	add_child(col)
	build_ms = Time.get_ticks_msec() - t0


static func _color(h: float, normal: Vector3) -> Color:
	if h < 2.0:
		return SAND
	if normal.y < 0.7:
		return ROCK
	return GRASS
