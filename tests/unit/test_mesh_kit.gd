extends TestCase

func test_tri_normal_counter_clockwise_is_outward():
	var k := MeshKit.new()
	# 위에서 보아 반시계 → 법선 +y
	k.add_tri(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), Color.WHITE)
	assert_eq(k.tri_count(), 1)
	var arr := k.commit().surface_get_arrays(0)
	var n: Vector3 = arr[Mesh.ARRAY_NORMAL][0]
	assert_true(n.y > 0.99, "법선 위쪽: %s" % n)

func test_height_ao_darkens_bottom():
	var k := MeshKit.new()
	k.add_tri(Vector3(0, 0, 0), Vector3(0, 2, 1), Vector3(1, 0, 0), Color.WHITE)
	k.bake_height_ao(0.0, 2.0, 0.5)
	var arr := k.commit().surface_get_arrays(0)
	for i in 3:
		var y: float = arr[Mesh.ARRAY_VERTEX][i].y
		var a: float = arr[Mesh.ARRAY_COLOR][i].a
		assert_true(absf(a - (1.0 if y > 1.0 else 0.5)) < 0.01, "y=%s AO=%s" % [y, a])

func test_surfaces_split():
	var k := MeshKit.new()
	k.add_tri(Vector3.ZERO, Vector3(0, 0, 1), Vector3(1, 0, 0), Color.WHITE)
	k.begin_surface()
	k.add_tri(Vector3.ZERO, Vector3(0, 0, 1), Vector3(1, 0, 0), Color.WHITE)
	assert_eq(k.commit().get_surface_count(), 2)
