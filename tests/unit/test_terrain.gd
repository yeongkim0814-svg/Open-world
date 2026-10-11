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
	var arrays := TerrainMesh.build(f, 2.0).surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 24, "격자 2×2칸 × 2삼각형 × 3")
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 9, "정점 3×3 공유 (부드러운 셰이딩)")

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
	var normals: PackedVector3Array = TerrainMesh.build(f, 2.0).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_true(normals[0].y > 0.9, "앞면이 위를 향해야 위에서 보인다 (Godot 시계 방향 = 앞면)")

func test_climbable_hysteresis_while_climbing():         # 경계 근처 경사에서 등반이 깜빡이지 않게
	var n55 := Vector3(0, cos(deg_to_rad(55)), sin(deg_to_rad(55)))
	assert_false(Locomotion.is_climbable(n55), "55°에서는 새로 시작하지 않음 (걸어서 오름)")
	assert_true(Locomotion.is_climbable(n55, true), "이미 등반 중이면 55°에서도 계속 붙어 있음")
	var n48 := Vector3(0, cos(deg_to_rad(48)), sin(deg_to_rad(48)))
	assert_false(Locomotion.is_climbable(n48, true), "48°면 등반을 놓고 걷는다")

func test_mesh_winding_faces_up():                       # 인덱스 순서가 위에서 볼 때 앞면(시계 방향)
	var img := Image.create(4, 4, false, Image.FORMAT_L8); img.fill(Color(0.5, 0.5, 0.5))
	var f := HeightField.new(img, 4.0, -10.0, 60.0)
	var arrays := TerrainMesh.build(f, 2.0).surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := v[idx[0]]; var b := v[idx[1]]; var c := v[idx[2]]
	assert_true((c - a).cross(b - a).y > 0.0)

func test_smooth_normals():                              # 인접 삼각형이 정점 법선을 공유 = HeightField 중앙 차분
	var vals := []
	for y in 9:
		for x in 9:
			vals.append(clampf(0.3 + 0.05 * x + 0.02 * y * y / 8.0 + 0.04 * sin(x * 1.3 + y), 0.0, 1.0))
	var f := HeightField.new(_img(9, 9, vals), 8.0, -10.0, 60.0)
	var arrays := TerrainMesh.build(f, 1.0).surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(v.size(), 81, "정점 공유")
	for i in v.size():
		# 메시 저장 시 법선이 16비트 팔면체로 압축되므로 각도 오차 < 0.5°만 허용
		assert_true(nrm[i].dot(f.normal_at(v[i].x, v[i].z)) > 0.99996, "정점 %d 법선 = normal_at" % i)
	# 안쪽 정점은 여러 삼각형(최대 6)이 같은 인덱스를 쓴다
	var uses := {}
	for k in idx:
		uses[k] = uses.get(k, 0) + 1
	assert_eq(uses[4 * 9 + 4], 6, "가운데 정점을 6 삼각형이 공유")

func test_rgb_low_bits_add_precision():                  # 초록 = 빨강 한 칸의 1/256 (16비트 높이)
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(100, 128, 100))
	var f := HeightField.new(img, 10.0, -10.0, 60.0)
	assert_almost(f.height_at(0, 0), -10.0 + 70.0 * (100.5 / 255.0), 0.001)
