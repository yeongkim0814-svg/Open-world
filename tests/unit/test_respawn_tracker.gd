extends TestCase
func test_falling_below_threshold_requests_respawn():   # Review Focus 3
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(10, 2, 10), true, 1.1)
	assert_true(r.update(Vector3(10, -51, 10), false, 0.016))
	assert_eq(r.safe_point, Vector3(10, 2, 10))

func test_brief_touch_is_not_safe_point():
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(0, 1, 0), true, 1.1)
	r.update(Vector3(5, 1, 5), true, 0.5)
	assert_eq(r.safe_point, Vector3(0, 1, 0))
