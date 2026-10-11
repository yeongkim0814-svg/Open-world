extends SceneTree
## CC0 바위 glTF(6~10만 삼각형)를 ~2천 삼각형으로 줄여 .res 로 저장. 실행: godot --headless -s tools/decimate_rocks.gd
const NAMES := ["boulder_01", "namaqualand_boulder_02", "namaqualand_boulder_04"]
const TARGET := 2000

func _init() -> void:
	for n in NAMES:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file("res://assets/meshes/rocks/%s/%s.gltf" % [n, n], st)
		if err != OK:
			push_error("load fail " + n); continue
		var im: ImporterMesh = st.get_meshes()[0].mesh
		im.generate_lods(25.0, 60.0, [])
		var arrays := im.get_surface_arrays(0)
		var full: int = arrays[Mesh.ARRAY_INDEX].size() / 3
		var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for l in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, l)
			best = idx
			if idx.size() / 3 <= TARGET:
				break
		arrays[Mesh.ARRAY_INDEX] = best
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		ResourceSaver.save(am, "res://assets/meshes/rocks/%s.res" % n)
		print("%s full=%d lod=%d verts=%d aabb=%s" % [n, full, best.size() / 3, arrays[Mesh.ARRAY_VERTEX].size(), am.get_aabb()])
	quit()
