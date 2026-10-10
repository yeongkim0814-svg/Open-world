extends TestCase
func test_falling_below_threshold_requests_respawn():   # Review Focus 3
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(10, 2, 10), true, true, 1.1)
	assert_true(r.update(Vector3(10, -51, 10), false, false, 0.016))
	assert_eq(r.safe_point, Vector3(10, 2, 10))

func test_brief_touch_is_not_safe_point():
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(0, 1, 0), true, true, 1.1)
	r.update(Vector3(5, 1, 5), true, true, 0.5)
	assert_eq(r.safe_point, Vector3(0, 1, 0))

func test_ground_near_edge_is_not_safe_point():        # 재시작 직후 다시 떨어지는 버그
	var r := RespawnTracker.new(-50.0)
	r.update(Vector3(0, 0, 100), true, true, 1.1)
	r.update(Vector3(0, 0, 145), true, false, 5.0)      # 가장자리: 사방에 바닥이 없음
	assert_eq(r.safe_point, Vector3(0, 0, 100))
