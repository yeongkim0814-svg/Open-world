class_name RockScatter
extends Node3D
## 경사 가장자리에 CC0 바위를 흩뿌린다 (MultiMesh 보기용 + 볼록 충돌). 배치 규칙 = RockPlacement.

const SHADER := preload("res://shaders/rock.gdshader")
const MODELS := ["boulder_01", "namaqualand_boulder_02", "namaqualand_boulder_04"]
## 길·수문·마을·호수·탑섬 제외: Vector3(x, z, 반지름) / Rect2(x, z, 폭, 깊이)
const EXCLUSIONS: Array = [
	Vector3(0, 95, 30),                 # 마을
	Vector3(-20, -90, 15),              # 수문 1 (+ 바위벽)
	Vector3(-125, -20, 24),             # 수문 2 + 고원 오르는 길 (등반 스윕 보호)
	Vector3(95, 60, 15),                # 수문 3 (+ 전초기지)
	Vector3(-72, -28, 12),              # 발사 바위
	Vector3(0, -10, 45),                # 호수 + 탑섬
	Rect2(-6, -4, 12, 42),              # 둑길(+기둥)
]

@export var terrain: NodePath
@export var seed := 7
@export var count := 120

var placed: Array[Transform3D] = []


func _ready() -> void:
	var t := get_node_or_null(terrain) as Terrain
	if t == null:
		push_warning("RockScatter: terrain 없음")
		return
	if t.field == null:
		await t.ready
	build(t.field)


func build(field: HeightField) -> void:
	placed = RockPlacement.points(field, seed, count, EXCLUSIONS)
	var per_model: Array = []
	for m in MODELS:
		per_model.append([])
	for i in placed.size():
		per_model[i % MODELS.size()].append(placed[i])
	for mi in MODELS.size():
		_spawn_model(MODELS[mi], per_model[mi])


func _spawn_model(model: String, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mesh := load("res://assets/meshes/rocks/%s.res" % model) as ArrayMesh
	var box := mesh.get_aabb()
	# 높이 ≤1, 폭 ≤2 로 정규화 (밑면 = y 0 근처) → 크기 s = 대략 s m 높이 바위
	var k := 1.0 / maxf(box.size.y, maxf(box.size.x, box.size.z) * 0.5)
	var center := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var local := Transform3D(Basis.from_scale(Vector3.ONE * k), -center * k)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var dir := "res://assets/meshes/rocks/%s/textures/%s_" % [model, model]
	mat.set_shader_parameter("albedo_tex", load(dir + "diff_1k.jpg"))
	mat.set_shader_parameter("normal_tex", load(dir + "nor_gl_1k.jpg"))
	mat.set_shader_parameter("arm_tex", load(dir + "arm_1k.jpg"))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Visual_" + model
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)

	var convex := mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
	var pts := PackedVector3Array()
	for p in convex.points:
		pts.append(local * p)
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		var shape := ConvexPolygonShape3D.new()
		var scaled := PackedVector3Array()
		var s: float = xf.basis.get_scale().x
		for p in pts:
			scaled.append(p * s)
		shape.points = scaled
		var body := StaticBody3D.new()
		body.name = "Rock_%s_%d" % [model, i]
		body.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
