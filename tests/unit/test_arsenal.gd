extends TestCase

func _three() -> Arsenal:
	var list: Array[WeaponData] = [
		preload("res://resources/weapons/sword.tres"),
		preload("res://resources/weapons/greatsword.tres"),
		preload("res://resources/weapons/bow.tres"),
	]
	return Arsenal.new(list)

func test_wear_stops_at_zero_and_breaks():
	var d := Durability.new(3.0)
	d.wear(5.0)
	assert_almost(d.value, 0.0)
	assert_true(d.is_broken())

func test_repair_restores_full():
	var d := Durability.new(3.0)
	d.wear(5.0); d.repair()
	assert_almost(d.value, 3.0)
	assert_false(d.is_broken())

func test_cycle_wraps():
	var a := _three()
	a.cycle(); a.cycle(); a.cycle()
	assert_eq(a.index, 0)

func test_each_weapon_has_own_durability():
	var a := _three()
	a.durability().wear(10.0)
	a.cycle()
	assert_almost(a.durability().value, a.current().durability)

func test_weapon_tres_values():
	var g: WeaponData = preload("res://resources/weapons/greatsword.tres")
	assert_true(g.armor_pierce)
	assert_almost(g.durability, 30.0)
	var b: WeaponData = preload("res://resources/weapons/bow.tres")
	assert_eq(b.kind, WeaponData.Kind.BOW)
