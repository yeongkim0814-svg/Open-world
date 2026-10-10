extends TestCase
func test_prefers_enemy_in_front_over_closer_one_to_the_side():
	var c: Array[Vector3] = [Vector3(2.5, 0, 0), Vector3(0, 0, -3)]
	assert_eq(Targeting.pick(Vector3.ZERO, Vector3.FORWARD, c, 6.0, 120.0), 1)

func test_ignores_out_of_range_and_behind():
	var c: Array[Vector3] = [Vector3(0, 0, -7), Vector3(0, 0, 2)]
	assert_eq(Targeting.pick(Vector3.ZERO, Vector3.FORWARD, c, 6.0, 120.0), -1)

func test_closer_wins_when_angles_similar():
	var c: Array[Vector3] = [Vector3(0.5, 0, -5), Vector3(-0.3, 0, -2)]
	assert_eq(Targeting.pick(Vector3.ZERO, Vector3.FORWARD, c, 6.0, 120.0), 1)
