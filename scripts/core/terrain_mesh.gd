class_name TerrainMesh
extends RefCounted
## HeightField → 로우폴리 지형 메시(면마다 평면 셰이딩 + 정점 색)와 충돌용 높이 배열.


## cell 간격 격자. color_fn(height: float, normal: Vector3) -> Color 로 면 색을 정한다.
static func build(field: HeightField, cell: float, color_fn: Callable) -> ArrayMesh:
	var n := int(round(field.world_size / cell)) + 1
	var half := field.world_size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n - 1:
		for ix in n - 1:
			var p := []
			for c in [[0, 0], [1, 0], [0, 1], [1, 1]]:
				var x: float = -half + (ix + c[0]) * cell
				var z: float = -half + (iz + c[1]) * cell
				p.append(Vector3(x, field.height_at(x, z), z))
			_tri(st, p[0], p[1], p[2], color_fn)
			_tri(st, p[1], p[3], p[2], color_fn)
	st.generate_normals()
	return st.commit()


## HeightMapShape3D.map_data 용 (행 = z, 열 = x).
static func heights(field: HeightField, cell: float) -> PackedFloat32Array:
	var n := int(round(field.world_size / cell)) + 1
	var half := field.world_size * 0.5
	var data := PackedFloat32Array()
	data.resize(n * n)
	for iz in n:
		for ix in n:
			data[iz * n + ix] = field.height_at(-half + ix * cell, -half + iz * cell)
	return data


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_fn: Callable) -> void:
	var up := (c - a).cross(b - a).normalized()     # 위를 향하는 면 법선 (색 결정용)
	var col: Color = color_fn.call((a.y + b.y + c.y) / 3.0, up)
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)
