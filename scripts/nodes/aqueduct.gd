class_name Aqueduct
extends Node3D
## 고대 수로: points를 잇는 각진 돌 홈 + 물 띠(자식 "Water", 수문이 하나라도 열리면 보임).

const STONE := Color(0.62, 0.6, 0.56)
const WATER := Color(0.25, 0.65, 0.71)
const VITALITY_SHADER := preload("res://shaders/vitality.gdshader")
const STRUCTURE_SHADER := preload("res://shaders/structure.gdshader")
const ROCK_TEX := "res://assets/textures/terrain/rock_%s.jpg"

@export var points: PackedVector3Array = PackedVector3Array()
@export var width := 2.4


func _ready() -> void:
	var water := Node3D.new()
	water.name = "Water"
	water.visible = false
	add_child(water)
	for i in points.size() - 1:
		_segment(self, points[i], points[i + 1], Vector3(width, 0.8, 0.0), STONE, -0.2)
		_segment(water, points[i], points[i + 1], Vector3(width - 0.8, 0.1, 0.0), WATER, 0.25)


func _segment(parent: Node3D, a: Vector3, b: Vector3, size: Vector3, color: Color, lift: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, a.distance_to(b))
	mi.mesh = box
	mi.material_override = _stone_material() if parent == self else _water_material(color)
	parent.add_child(mi)
	mi.global_position = (a + b) * 0.5 + Vector3.UP * lift
	mi.look_at(b + Vector3.UP * lift, Vector3.UP)


var _stone: ShaderMaterial


## 돌 홈: 구조물 셰이더(삼면 투영 바위 텍스처). 마디마다 같은 재질을 나눠 쓴다.
func _stone_material() -> ShaderMaterial:
	if _stone == null:
		_stone = ShaderMaterial.new()
		_stone.shader = STRUCTURE_SHADER
		_stone.set_shader_parameter("tex_diff", load(ROCK_TEX % "diff"))
		_stone.set_shader_parameter("tex_nor", load(ROCK_TEX % "nor"))
		_stone.set_shader_parameter("tex_arm", load(ROCK_TEX % "arm"))
		_stone.set_shader_parameter("tint", STONE)
		_stone.set_shader_parameter("detail", 0.8)
		_stone.set_shader_parameter("tile", 2.5)
	return _stone


func _water_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VITALITY_SHADER
	mat.set_shader_parameter("albedo", color)
	return mat
