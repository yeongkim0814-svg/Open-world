class_name Terrain
extends StaticBody3D
## 높이 지도 PNG → 부드러운 지형 메시 + 충돌 (설계서 5.2, 03 그래픽 설계서 6장). 시작할 때 만든다.
## 재질 = shaders/terrain.gdshader (풀·흙·바위·모래 텍스처 섞기, 회색↔컬러 포함).
## 메시 격자 cell (기본 1m ≈ 18만 삼각형), 충돌 격자 collision_cell (기본 1m — 2m는 등반 스윕 4곳 실패).

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const TEX_DIR := "res://assets/textures/terrain/"

@export var height_map: Texture2D
@export var world_size := 300.0
@export var min_h := -10.0
@export var max_h := 60.0
@export var cell := 1.0
@export var collision_cell := 1.0

var field: HeightField
var build_ms := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	field = HeightField.new(height_map.get_image(), world_size, min_h, max_h)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = TerrainMesh.build(field, cell)
	mesh_instance.material_override = make_material()
	add_child(mesh_instance)
	var n := int(round(world_size / collision_cell)) + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = TerrainMesh.heights(field, collision_cell)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(collision_cell, 1.0, collision_cell)
	add_child(col)
	build_ms = Time.get_ticks_msec() - t0


static func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	for layer in ["grass", "dirt", "rock", "sand"]:
		for kind in ["diff", "nor", "arm"]:
			mat.set_shader_parameter("%s_%s" % [layer, kind], load(TEX_DIR + "%s_%s.jpg" % [layer, kind]))
	return mat
