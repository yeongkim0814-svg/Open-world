class_name MeshKit
extends RefCounted
## 생성기 공용 메시 도구: 삼각형마다 정점을 따로 둬 면 법선(평면 음영)을 쓰고, 정점색 RGB = 명도 배수, A = AO.
## 감기 순서: 바깥에서 보아 반시계 = 앞면(법선 바깥). begin_surface()로 서피스를 나눈다(예: 줄기/잎).

var _surfaces: Array = []   # 각 원소 = [verts: PackedVector3Array, cols: PackedColorArray]


func _init() -> void:
	begin_surface()


func begin_surface() -> void:
	_surfaces.append([PackedVector3Array(), PackedColorArray()])


func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var s: Array = _surfaces[-1]
	s[0].append_array([a, b, c])
	s[1].append_array([color, color, color])


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	add_tri(a, b, c, color)
	add_tri(a, c, d, color)


func tri_count() -> int:
	var n := 0
	for s in _surfaces:
		n += s[0].size() / 3
	return n


## 높이에 따른 AO: min_y에서 1 - strength, max_y에서 1 (정점색 A에 곱함).
func bake_height_ao(min_y: float, max_y: float, strength: float) -> void:
	for s in _surfaces:
		var v: PackedVector3Array = s[0]
		var c: PackedColorArray = s[1]
		for i in v.size():
			var t := clampf(inverse_lerp(min_y, max_y, v[i].y), 0.0, 1.0) if max_y > min_y else 1.0
			c[i].a *= lerpf(1.0 - strength, 1.0, t)
		s[1] = c


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in _surfaces:
		var v: PackedVector3Array = s[0]
		if v.is_empty():
			continue
		var n := PackedVector3Array()
		n.resize(v.size())
		for i in range(0, v.size(), 3):
			# Godot 앞면 = 시계 방향(카메라 기준) → 반시계로 넣은 삼각형은 b,c를 바꿔 넣는다.
			var fn := (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).normalized()
			n[i] = fn; n[i + 1] = fn; n[i + 2] = fn
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		var norms := PackedVector3Array()
		verts.resize(v.size()); cols.resize(v.size()); norms.resize(v.size())
		for i in range(0, v.size(), 3):
			verts[i] = v[i]; verts[i + 1] = v[i + 2]; verts[i + 2] = v[i + 1]
			cols[i] = s[1][i]; cols[i + 1] = s[1][i + 2]; cols[i + 2] = s[1][i + 1]
			norms[i] = n[i]; norms[i + 1] = n[i]; norms[i + 2] = n[i]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
