extends TestCase
## 건축 부품 생성기 테스트.


func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_block_bevel_adds_faces() -> void:
	var size := Vector3(2.0, 1.0, 3.0)
	assert_eq(_verts(StructureGen.block(size, 0.0, 1, 0.0)).size() / 3, 12)
	var b := StructureGen.block(size, 0.1, 1, 0.0)
	assert_true(_verts(b).size() / 3 > 12)
	var bb := b.get_aabb()
	assert_almost(bb.size.x, size.x, size.x * 0.01)
	assert_almost(bb.size.y, size.y, size.y * 0.01)
	assert_almost(bb.size.z, size.z, size.z * 0.01)


func test_parts_in_budget() -> void:
	var counts := {
		"block": _verts(StructureGen.block(Vector3(2, 1, 2), 0.1, 1, 0.0)).size() / 3,
		"stairs": _verts(StructureGen.stairs(5, 2.0, 0.25, 0.4, 1)).size() / 3,
		"pillar": _verts(StructureGen.pillar(3.0, 0.4, 1, false)).size() / 3,
		"broken": _verts(StructureGen.pillar(3.0, 0.4, 1, true)).size() / 3,
		"arch": _verts(StructureGen.arch(3.0, 3.5, 0.6, 1)).size() / 3,
	}
	for k in counts:
		assert_true(counts[k] >= 12 and counts[k] <= 200, "%s: %d 삼각형" % [k, counts[k]])


func test_damage_changes_mesh_deterministically() -> void:
	var size := Vector3(2, 1, 2)
	var a := _verts(StructureGen.block(size, 0.1, 5, 0.0))
	var b := _verts(StructureGen.block(size, 0.1, 5, 0.5))
	assert_true(a != b, "damage가 메시를 바꿔야 함")
	assert_eq(b, _verts(StructureGen.block(size, 0.1, 5, 0.5)), "결정적")


func test_stairs_height() -> void:
	var bb := StructureGen.stairs(6, 2.0, 0.2, 0.35, 3).get_aabb()
	assert_almost(bb.size.y, 6 * 0.2, 0.001)
