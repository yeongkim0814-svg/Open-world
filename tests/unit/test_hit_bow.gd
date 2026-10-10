extends TestCase
var bow: WeaponData = preload("res://resources/weapons/bow.tres")

func test_armor_reduces_unless_pierce():
	assert_almost(Hit.make(20.0).amount_against(0.4, 2.0), 8.0)
	assert_almost(Hit.make(20.0, true).amount_against(0.4, 2.0), 20.0)

func test_weak_point_doubles():
	var h := Hit.make(20.0, true); h.weak_point = true
	assert_almost(h.amount_against(0.4, 2.0), 40.0)

func test_tap_release_fires_min_ratio():          # Review Focus 2
	var d := BowDraw.new(bow); d.start()
	assert_almost(d.release(), 0.3)
	assert_false(d.drawing)

func test_full_draw_ratio_one():
	var d := BowDraw.new(bow); d.start()
	d.tick(0.6); assert_almost(d.ratio(), 1.0)
	d.tick(1.0); assert_almost(d.ratio(), 1.0)

func test_cancel_then_release_fires_nothing():    # Review Focus 3
	var d := BowDraw.new(bow); d.start(); d.tick(0.3); d.cancel()
	assert_almost(d.release(), -1.0)
