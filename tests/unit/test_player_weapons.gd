extends TestCase

func _combat() -> PlayerCombat:
	var c := PlayerCombat.new(); c.setup(null); return c

func test_broken_weapon_deals_quarter():           # Review Focus 1
	var c := _combat()
	var sword := c.arsenal.current()
	c.arsenal.durability().wear(999.0)
	assert_almost(c.melee_hit(sword, false).damage, 2.5)
	c.arsenal.durability().repair()
	assert_almost(c.melee_hit(sword, false).damage, 10.0)
	c.free()

func test_greatsword_heavy_staggers_and_pierces():
	var c := _combat()
	var h := c.melee_hit(preload("res://resources/weapons/greatsword.tres"), true)
	assert_almost(h.damage, 50.0)
	assert_true(h.stagger)
	assert_true(h.armor_pierce)
	c.free()

func test_switch_cycles_and_resets_combo():
	var c := _combat()
	c._combo_step = 2
	c.switch_weapon()
	assert_eq(c.arsenal.current().display_name, "대검")
	assert_eq(c._combo_step, 0)
	c.free()
