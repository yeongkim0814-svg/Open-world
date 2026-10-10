extends TestCase
var blade: MachineData = preload("res://resources/machines/blade.tres")
var cannon: MachineData = preload("res://resources/machines/cannon.tres")
const M := MachineBrain.Mode

func test_idle_until_alert():
	var b := MachineBrain.new(blade)
	assert_eq(b.decide(30.0, 0.0, false), M.IDLE)
	assert_false(b.alerted)

func test_blade_chases_then_attacks():
	var b := MachineBrain.new(blade)
	assert_eq(b.decide(10.0, 0.0, false), M.CHASE)
	assert_eq(b.decide(2.0, 5.0, false), M.ATTACK)

func test_cannon_keeps_distance():
	var b := MachineBrain.new(cannon)
	assert_eq(b.decide(5.0, 0.0, false), M.RETREAT)
	assert_eq(b.decide(12.0, 0.0, false), M.ATTACK)
	assert_eq(b.decide(25.0, 0.0, false), M.CHASE)     # 경계 유지 중 사거리 밖 → 접근

func test_leash_drops_alert_and_returns():             # Review Focus 4
	var b := MachineBrain.new(blade)
	b.decide(5.0, 0.0, false)
	assert_eq(b.decide(5.0, 26.0, false), M.RETURN)
	assert_false(b.alerted)

func test_returning_ignores_player_until_home():
	var b := MachineBrain.new(blade)
	b.decide(5.0, 26.0, true)
	assert_eq(b.decide(3.0, 20.0, false), M.RETURN)     # 귀환 중엔 다시 쫓지 않음
	assert_eq(b.decide(3.0, 0.5, false), M.CHASE)       # 집에 도착하면 다시 경계

func test_hit_alerts_from_far():
	var b := MachineBrain.new(blade)
	assert_eq(b.decide(40.0, 0.0, true), M.CHASE)
	assert_true(b.alerted)

func test_every_third_attack_red():
	var b := MachineBrain.new(blade)
	assert_false(b.is_red(1)); assert_false(b.is_red(2)); assert_true(b.is_red(3))
