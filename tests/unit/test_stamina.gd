extends TestCase
var t := MovementTuning.new()

func test_drain_to_zero_sets_exhausted():
	var s := Stamina.new(t)
	for i in 600: s.drain(t.run_cost, 1.0 / 60.0)   # 10초 × 10/s = 100
	assert_almost(s.value, 0.0)
	assert_true(s.exhausted)
	assert_false(s.can_start())

func test_no_regen_during_delay():
	var s := Stamina.new(t)
	s.spend(50.0)
	s.tick(0.9)
	assert_almost(s.value, 50.0)

func test_regen_after_delay():
	var s := Stamina.new(t)
	s.spend(50.0)
	s.tick(1.0); s.tick(1.0)          # 지연 1초 후 1초 회복 = +25
	assert_almost(s.value, 75.0)

func test_exhaustion_clears_at_30_percent():   # Review Focus 4
	var s := Stamina.new(t)
	s.spend(100.0)
	s.tick(1.0); s.tick(1.0)          # 25 → 아직 탈진
	assert_true(s.exhausted)
	s.tick(0.2)                       # 30 → 해제
	assert_false(s.exhausted)

func test_regen_caps_at_max():
	var s := Stamina.new(t)
	s.spend(10.0)
	for i in 10: s.tick(1.0)
	assert_almost(s.value, 100.0)
