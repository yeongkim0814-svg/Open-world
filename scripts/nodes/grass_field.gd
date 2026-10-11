class_name GrassField
extends Node3D
## 활성 카메라 주변 radius m 안에 풀 청크(MultiMesh)를 깐다. 반경에 들어오는/나가는 청크만 만들고 지운다.

const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const CHUNKS_PER_FRAME := 6

@export var terrain: NodePath
@export var radius := 40.0
@export var density := 6.0
@export var chunk_size := 8.0
@export var world_seed := 1337

var _chunks := {}  # Vector2i -> MultiMeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _field: HeightField
var _water: Array = []
var _last_center := Vector2i(1 << 30, 1 << 30)
var _pending: Array[Vector2i] = []


func _ready() -> void:
	_mesh = build_clump_mesh()
	_material = ShaderMaterial.new()
	_material.shader = GRASS_SHADER
	_material.set_shader_parameter("fade_end", radius)
	_material.set_shader_parameter("fade_start", radius * 0.7)


func chunk_count() -> int:
	return _chunks.size()


func instance_count() -> int:
	var n := 0
	for c in _chunks.values():
		n += (c as MultiMeshInstance3D).multimesh.instance_count
	return n


func triangles_per_instance() -> int:
	return _mesh.get_faces().size() / 3


## 풀 덩어리: 서로 다른 방향의 가는 삼각형 잎 5장 (UV.y = 높이 0..1).
static func build_clump_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var blades := 5
	for i in blades:
		var a := TAU * float(i) / blades + 0.4 * i
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var out_d := 0.12 + 0.05 * (i % 2)
		var base := dir * out_d
		var tall := 0.55 + 0.18 * float(i % 3)
		var wd := 0.065
		var tip := base + dir * 0.10 + Vector3(0, tall, 0)
		verts.append_array([base - side * wd, base + side * wd, tip])
		var u := float(i) / (blades - 1)
		uvs.append_array([Vector2(u, 0), Vector2(u, 0), Vector2(u, 1)])
		var n := side.cross(Vector3.UP).normalized()
		normals.append_array([n, n, n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _field == null:
		var t := get_node_or_null(terrain)
		if t == null or t.get("field") == null:
			return
		_field = t.field
	var p := cam.global_position
	var center := Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))
	if center != _last_center:
		_last_center = center
		_refresh(Vector2(p.x, p.z))
	var budget := _pending.size() if _chunks.is_empty() else CHUNKS_PER_FRAME
	while budget > 0 and not _pending.is_empty():
		_build_chunk(_pending.pop_front())
		budget -= 1


func _refresh(cam_xz: Vector2) -> void:
	var half := chunk_size * 0.5
	var reach := radius + chunk_size * 0.71
	var want := {}
	var r := ceili(reach / chunk_size) + 1
	var cc := Vector2i(floori(cam_xz.x / chunk_size), floori(cam_xz.y / chunk_size))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := cc + Vector2i(dx, dz)
			var ctr := Vector2(k.x * chunk_size + half, k.y * chunk_size + half)
			if ctr.distance_to(cam_xz) <= reach:
				want[k] = true
	for k in _chunks.keys():
		if not want.has(k):
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
	_pending.clear()
	for k in want:
		if not _chunks.has(k):
			_pending.append(k)
	_pending.sort_custom(func(a, b):
		return Vector2(a) .distance_squared_to(Vector2(cc)) < Vector2(b).distance_squared_to(Vector2(cc)))
	_water = get_tree().get_nodes_in_group("water")


## 수위가 바뀐 원(호수)과 겹치는 청크를 지우고 다시 만들 대기열에 넣는다 (드러난 호수 바닥에 풀).
func invalidate_disc(center: Vector2, r: float) -> void:
	var reach := r + chunk_size * 0.71
	var half := chunk_size * 0.5
	for k in _chunks.keys():
		var ctr := Vector2(k.x * chunk_size + half, k.y * chunk_size + half)
		if ctr.distance_to(center) <= reach:
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
			if not _pending.has(k):
				_pending.append(k)
	_water = get_tree().get_nodes_in_group("water") if is_inside_tree() else _water


func _water_level(x: float, z: float) -> float:
	var level := -INF
	for w in _water:
		var s: float = w.surface_y()
		if w.depth_at(Vector3(x, s - 0.001, z)) > 0.0:
			level = maxf(level, s)
	return level


func _build_chunk(k: Vector2i) -> void:
	if _chunks.has(k) or _field == null:
		return
	var origin := Vector2(k.x * chunk_size, k.y * chunk_size)
	var seed_k := world_seed + k.x * 73856093 + k.y * 19349663
	var pts := GrassPlacement.points(_field, origin, chunk_size, density, seed_k, _water_level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_k
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, pts[i]))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	_chunks[k] = inst
