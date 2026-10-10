extends TestCase
func test_full_deflection_up_is_plus_y():
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(200, 380))
	assert_almost(s.value().y, 1.0); assert_almost(s.value().x, 0.0)

func test_dead_zone_returns_zero():
	var s := VirtualStick.new(100.0, 0.15)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(210, 500))
	assert_eq(s.value(), Vector2.ZERO)

func test_second_finger_ignored():                 # Review Focus 1
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(300, 500))
	assert_false(s.press(1, Vector2(250, 450)))
	s.drag(1, Vector2(900, 100))
	assert_almost(s.value().x, 1.0)

func test_release_other_finger_keeps_stick():      # Review Focus 1
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(300, 500))
	s.release(1)
	assert_almost(s.value().x, 1.0)
	s.release(0)
	assert_eq(s.value(), Vector2.ZERO)

func test_release_in_lock_zone_requests_auto_run():
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(200, 350))   # 반경의 1.5배 위
	assert_true(s.in_lock_zone())
	assert_true(s.release(0))

func test_release_inside_radius_does_not_lock():
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(200, 400))   # 반경 1.0배
	assert_false(s.in_lock_zone())
	assert_false(s.release(0))

func test_value_stays_clamped_in_lock_zone():
	var s := VirtualStick.new(100.0)
	s.press(0, Vector2(200, 500)); s.drag(0, Vector2(200, 300))
	assert_almost(s.value().y, 1.0)
