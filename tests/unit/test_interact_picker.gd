extends TestCase
func test_picks_nearest_in_front():
	var p: Array[Vector3] = [Vector3(0, 0, -1.8), Vector3(0, 0, -1.0)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), 1)

func test_ignores_directly_behind_even_if_closer():      # Review Focus 5
	var p: Array[Vector3] = [Vector3(0, 0, 0.5), Vector3(0, 0, -1.5)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), 1)

func test_none_in_radius():
	var p: Array[Vector3] = [Vector3(0, 0, -3)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), -1)

func test_standing_on_top_counts():
	var p: Array[Vector3] = [Vector3(0, -0.5, 0)]
	assert_eq(InteractPicker.pick(Vector3.ZERO, Vector3.FORWARD, p), 0)
