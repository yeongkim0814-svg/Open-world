class_name TerrainMesh
extends RefCounted
## HeightField → 부드러운 지형 메시(정점 공유 인덱스 메시, 정점 법선 = HeightField.normal_at 중앙 차분)
## 와 충돌용 높이 배열. UV = 월드 xz (m) — 지형 셰이더가 배율을 정한다.


## cell 간격 격자 (정점 (n)², 삼각형 2(n-1)²).
static func build(field: HeightField, cell: float) -> ArrayMesh:
	var n := int(round(field.world_size / cell)) + 1
	var half := field.world_size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	var i := 0
	for iz in n:
		var z := -half + iz * cell
		for ix in n:
			var x := -half + ix * cell
			verts[i] = Vector3(x, field.height_at(x, z), z)
			normals[i] = field.normal_at(x, z)
			uvs[i] = Vector2(x, z)
			i += 1
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix          # (0,0)
			var b := a + 1                # (1,0)
			var c := a + n                # (0,1)
			var d := c + 1                # (1,1)
			# Godot 앞면 = 시계 방향(위에서 볼 때): a→b→c, b→d→c
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
