extends TestCase
var t := CombatTuning.new()

func test_rotates_toward_target_at_limited_speed():
	var f := CameraFollow.new(t)
	assert_almost(f.step(0.0, PI, 0.5, false, false), deg_to_rad(90.0))

func test_held_stops_and_waits_after_release():          # Review Focus 4
	var f := CameraFollow.new(t)
	assert_almost(f.step(0.0, PI, 0.1, true, false), 0.0)
	assert_almost(f.step(0.0, PI, 0.4, false, false), 0.0)   # 뗀 뒤 0.4초: 아직 대기
	assert_true(f.step(0.0, PI, 0.2, false, false) > 0.0)    # 0.6초: 재개

func test_dodging_stops_follow():                        # Review Focus 4
	assert_almost(CameraFollow.new(t).step(0.0, PI, 0.5, false, true), 0.0)

func test_takes_shortest_way_around():
	var y := CameraFollow.new(t).step(deg_to_rad(170), deg_to_rad(-170), 0.05, false, false)
	assert_true(y > deg_to_rad(170))

func test_does_not_overshoot():
	assert_almost(CameraFollow.new(t).step(0.0, 0.1, 1.0, false, false), 0.1)
