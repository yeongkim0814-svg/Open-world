extends TestCase
var t := CombatTuning.new()

func test_enters_within_15m():
	var c := CombatState.new(t)
	assert_true(c.update(14.0, false, 0.016))

func test_stays_between_15_and_25m():                 # Review Focus 3
	var c := CombatState.new(t); c.update(10.0, false, 0.016)
	for i in 600: c.update(20.0, false, 0.016)        # 10초 경계 안
	assert_true(c.active)

func test_exits_after_3s_beyond_25m():
	var c := CombatState.new(t); c.update(10.0, false, 0.016)
	c.update(30.0, false, 2.9); assert_true(c.active)
	c.update(30.0, false, 0.2); assert_false(c.active)

func test_engaged_enters_immediately_without_enemy():
	var c := CombatState.new(t)
	assert_true(c.update(INF, true, 0.016))
