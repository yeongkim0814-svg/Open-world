extends TestCase
func test_flurry_slows_enemy_for_duration():
	var f := Flurry.new(CombatTuning.new()); f.start()
	assert_almost(f.enemy_time_scale(), 0.2)
	f.tick(1.4); assert_true(f.active)
	f.tick(0.2); assert_false(f.active); assert_almost(f.enemy_time_scale(), 1.0)

func test_inactive_by_default():
	assert_almost(Flurry.new(CombatTuning.new()).enemy_time_scale(), 1.0)
