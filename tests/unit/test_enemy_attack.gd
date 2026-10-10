extends TestCase
func test_full_cycle_emits_hit_then_done():
	var a := EnemyAttack.new(0.6, 0.2, 0.8); a.start(true)
	assert_eq(a.phase, EnemyAttack.Phase.TELEGRAPH)
	assert_true(a.is_threatening())
	assert_eq(a.tick(0.6), [&"hit"]); assert_eq(a.phase, EnemyAttack.Phase.ACTIVE)
	a.tick(0.2); assert_eq(a.phase, EnemyAttack.Phase.RECOVER); assert_false(a.is_threatening())
	assert_eq(a.tick(0.8), [&"done"]); assert_eq(a.phase, EnemyAttack.Phase.IDLE)

func test_time_to_hit_counts_down():
	var a := EnemyAttack.new(0.6, 0.2, 0.8); a.start(false)
	a.tick(0.4); assert_almost(a.time_to_hit(), 0.2)

func test_start_ignored_unless_idle():
	var a := EnemyAttack.new(); a.start(true); a.start(false)
	assert_true(a.parryable)

func test_large_delta_carries_over_phases():
	var a := EnemyAttack.new(0.6, 0.2, 0.8); a.start(true)
	assert_eq(a.tick(2.0), [&"hit", &"done"])
	assert_eq(a.phase, EnemyAttack.Phase.IDLE)
