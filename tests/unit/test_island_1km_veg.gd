extends TestCase
## 2 km 첫 지역 장면에 식생이 붙는지 (장면을 열고 스폰 근처에서 몇 단계 돌린 뒤 블록이 생기는지)
## 러너는 _initialize 안에서 동기 실행 (루트가 아직 트리 밖) → _ready 를 직접 부르고 프레임 대신 step 을 돌린다.


func test_scene_has_vegetation_blocks():
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = load("res://scenes/island_1km.tscn").instantiate()
	tree.root.add_child(s)
	if not s.is_inside_tree():
		s._ready()
	var veg := s.get_node_or_null("Vegetation") as VegetationField
	assert_true(veg != null, "Vegetation 노드가 있어야 함")
	if veg == null:
		s.free()
		return
	# 지형 높이장이 준비된 뒤 만들어졌는지
	assert_true(s.get("field") != null, "field 준비 후 생성")
	assert_true(veg.get_parent() == s and veg.get_index() > s.get_node("Terrain").get_index(), "지형 뒤에 붙는다")
	veg.update_center(Vector3(690, 0, 705))
	var n := 0
	while veg.stats()["blocks"] == 0 and n < 200:
		veg.step(50.0)
		n += 1
	assert_true(veg.stats()["blocks"] > 0, "몇 단계 뒤 블록이 생겨야 함")
	assert_true(veg.busy() == (veg.stats()["pending"] + veg.stats()["dirty"] > 0))
	# 장면 busy() 가 식생 대기열을 포함
	if veg.busy():
		assert_true(s.busy(), "장면 busy() 에 식생 포함")
	s.free()


func test_no_climb_collider_is_not_wall():
	var b := StaticBody3D.new()
	assert_true(Player.climbable_collider(b), "일반 충돌체는 등반 가능")
	b.add_to_group("no_climb")
	assert_false(Player.climbable_collider(b), "no_climb 그룹은 벽으로 쓰지 않음")
	assert_false(Player.climbable_collider(null), "충돌체 없음")
	b.free()
