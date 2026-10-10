extends TestCase
func test_back_relative_to_facing_is_hop_back():
	assert_eq(Dodge.classify(Vector3(0, 0, 1), 0.0), Dodge.Kind.HOP_BACK)     # 정면 -Z, 이동 +Z

func test_forward_is_roll():
	assert_eq(Dodge.classify(Vector3(0, 0, -1), 0.0), Dodge.Kind.ROLL_FORWARD)

func test_side_respects_facing_yaw():
	assert_eq(Dodge.classify(Vector3(0, 0, -1), PI / 2), Dodge.Kind.HOP_RIGHT)  # 정면 -X일 때 -Z는 오른쪽

func test_left_when_facing_forward():
	assert_eq(Dodge.classify(Vector3(-1, 0, 0), 0.0), Dodge.Kind.HOP_LEFT)
