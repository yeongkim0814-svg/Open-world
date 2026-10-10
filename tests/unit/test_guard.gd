extends TestCase
var t := CombatTuning.new()

func test_press_just_before_hit_parries():
	var g := Guard.new(t); g.press(); g.tick(0.15)
	assert_eq(g.resolve(true, false), Guard.Result.PARRIED)

func test_weapon_window_is_narrower_than_shield():
	var g := Guard.new(t); g.press(); g.tick(0.3)
	assert_eq(g.resolve(true, false), Guard.Result.BLOCKED)   # 무기 0.2 초과, 누르고 있음
	var h := Guard.new(t); h.press(); h.tick(0.3)
	assert_eq(h.resolve(true, true), Guard.Result.PARRIED)    # 방패 0.35 이내

func test_red_attack_cannot_be_parried_and_breaks_guard():
	var g := Guard.new(t); g.press(); g.tick(0.05)
	assert_eq(g.resolve(false, true), Guard.Result.GUARD_BREAK)

func test_spam_shrinks_window():                            # Review Focus 1
	var g := Guard.new(t)
	for k in 3:
		g.press(); g.release(); g.tick(0.2)
	g.press(); g.tick(0.15)                                  # 4번째: 창 0.2×0.7³≈0.069 (최소 0.4배=0.08)
	assert_eq(g.resolve(true, false), Guard.Result.BLOCKED)

func test_window_recovers_after_pause():
	var g := Guard.new(t)
	for k in 3:
		g.press(); g.release(); g.tick(0.2)
	g.tick(1.5)
	g.press(); g.tick(0.15)
	assert_eq(g.resolve(true, false), Guard.Result.PARRIED)

func test_released_late_press_is_hit():
	var g := Guard.new(t); g.press(); g.release(); g.tick(0.5)
	assert_eq(g.resolve(true, false), Guard.Result.HIT)

func test_no_guard_is_hit():
	assert_eq(Guard.new(t).resolve(true, false), Guard.Result.HIT)
