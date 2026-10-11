extends TestCase

func _img(w: int, h: int, values: Array, fmt := Image.FORMAT_L8) -> Image:
	var img := Image.create(w, h, false, fmt)
	for y in h:
		for x in w:
			var v: float = values[y * w + x]
			img.set_pixel(x, y, Color(v, v, v))
	return img

func test_height_corners_and_center():
	var f := HeightField.new(_img(3, 3, [0, 0, 0, 0, 1, 0, 0, 0, 0]), 10.0, -10.0, 60.0)
	assert_almost(f.height_at(-5, -5), -10.0, 0.01)
	assert_almost(f.height_at(0, 0), 60.0, 0.01)

func test_bilinear_between_pixels():
	var f := HeightField.new(_img(2, 1, [0, 1]), 10.0, -10.0, 60.0)
	assert_almost(f.height_at(0, 0), 25.0, 0.5)

func test_outside_clamps_to_edge():
	var f := HeightField.new(_img(2, 1, [0, 1]), 10.0, -10.0, 60.0)
	assert_almost(f.height_at(999, 0), f.height_at(5, 0))

func test_rgb_and_other_size_images_work():          # Review Focus 1
	var img := Image.create(5, 5, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 0, 0))
	var f := HeightField.new(img, 10.0, -10.0, 60.0)
	assert_almost(f.height_at(1.3, -2.2), 60.0, 0.01)

func test_flat_normal_is_up():
	var img := Image.create(4, 4, false, Image.FORMAT_L8); img.fill(Color(0.5, 0.5, 0.5))
	var f := HeightField.new(img, 10.0, -10.0, 60.0)
	assert_true(f.normal_at(0, 0).is_equal_approx(Vector3.UP))

func test_mesh_triangle_count():
	var img := Image.create(4, 4, false, Image.FORMAT_L8); img.fill(Color(0.5, 0.5, 0.5))
	var f := HeightField.new(img, 4.0, -10.0, 60.0)
	var mesh := TerrainMesh.build(f, 2.0, func(_h, _n): return Color.WHITE)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 24, "격자 2×2칸 × 2삼각형 × 3정점 (평면 셰이딩)")

func test_heights_array_size():
	var img := Image.create(4, 4, false, Image.FORMAT_L8); img.fill(Color(0.5, 0.5, 0.5))
	var f := HeightField.new(img, 4.0, -10.0, 60.0)
	assert_eq(TerrainMesh.heights(f, 2.0).size(), 9)

func test_climbable_slopes():                         # Review Focus 5: 60°까지 걷기, 그 이상 등반
	assert_true(Locomotion.is_climbable(Vector3(0, cos(deg_to_rad(65)), sin(deg_to_rad(65)))))
	assert_false(Locomotion.is_climbable(Vector3(0, cos(deg_to_rad(55)), sin(deg_to_rad(55)))))
	assert_true(Locomotion.is_climbable(Vector3(0, 0, 1)))
	assert_false(Locomotion.is_climbable(Vector3.DOWN))

func test_mesh_faces_up():
	var img := Image.create(4, 4, false, Image.FORMAT_L8); img.fill(Color(0.5, 0.5, 0.5))
	var f := HeightField.new(img, 4.0, -10.0, 60.0)
	var normals: PackedVector3Array = TerrainMesh.build(f, 2.0, func(_h, _n): return Color.WHITE).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_true(normals[0].y > 0.9, "앞면이 위를 향해야 위에서 보인다 (Godot 시계 방향 = 앞면)")

func test_climbable_hysteresis_while_climbing():         # 경계 근처 경사에서 등반이 깜빡이지 않게
	var n55 := Vector3(0, cos(deg_to_rad(55)), sin(deg_to_rad(55)))
	assert_false(Locomotion.is_climbable(n55), "55°에서는 새로 시작하지 않음 (걸어서 오름)")
	assert_true(Locomotion.is_climbable(n55, true), "이미 등반 중이면 55°에서도 계속 붙어 있음")
	var n48 := Vector3(0, cos(deg_to_rad(48)), sin(deg_to_rad(48)))
	assert_false(Locomotion.is_climbable(n48, true), "48°면 등반을 놓고 걷는다")
