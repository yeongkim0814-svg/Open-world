extends TestCase
const DT := 1.0 / 60.0

func _shot() -> EnemyShot:
	return EnemyShot.new(Vector3.ZERO, Vector3(0, 0, -10), 12.0, true)

func test_flies_toward_target():
	var s := _shot()
	s.step(0.5)
	assert_almost(s.position.z, -6.0)
	assert_almost(s.travelled, 6.0)

func test_crosses_detects_pass_through():
	var s := EnemyShot.new(Vector3.ZERO, Vector3(0, 0, -10), 60.0, true)
	var prev := s.step(0.1)                       # 0 → -6, 점 (0,0,-3)을 한 틱에 지나침
	assert_true(s.crosses(prev, Vector3(0, 0, -3), 0.7))
	assert_false(s.crosses(prev, Vector3(2, 0, -3), 0.7))

func test_threat_only_when_close_and_approaching():
	var s := _shot()
	assert_false(s.is_threat_to(Vector3(0, 0, -10), 6.0))   # 10m: 아직 멀다
	s.step(0.5)                                              # -6, 남은 4m
	assert_true(s.is_threat_to(Vector3(0, 0, -10), 6.0))
	s.step(0.5)                                              # -12, 지나감
	assert_false(s.is_threat_to(Vector3(0, 0, -10), 6.0))

func test_reflected_is_not_threat():                         # Review Focus 5
	var s := _shot(); s.step(0.5)
	s.reflect(Vector3.ZERO)
	assert_true(s.reflected)
	assert_almost(s.velocity.length(), 18.0)
	assert_true(s.velocity.z > 0.0)
	assert_false(s.is_threat_to(Vector3(0, 0, -10), 6.0))

func test_resolved_is_not_threat():                          # Review Focus 5
	var s := _shot(); s.step(0.5)
	s.resolved = true
	assert_false(s.is_threat_to(Vector3(0, 0, -10), 6.0))

func test_expired():
	var s := _shot(); s.step(3.0)
	assert_true(s.expired(30.0))
