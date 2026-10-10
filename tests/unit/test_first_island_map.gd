extends TestCase
## 첫 섬 높이 지도(assets/terrain/first_island.png)의 지형 요소가 설계 위치에 있는지.

var f: HeightField

func _init() -> void:
	var tex := load("res://assets/terrain/first_island.png") as Texture2D
	f = HeightField.new(tex.get_image(), 300.0, -10.0, 60.0)

func test_village_lowland():
	var h := f.height_at(0, 95); assert_true(h > 2.0 and h < 4.0, "마을 %.1f" % h)

func test_lake_basin_below_causeway():
	assert_true(f.height_at(0, -40) < 0.0, "분지 %.1f" % f.height_at(0, -40))

func test_dam_ring_high():
	var h := f.height_at(0, 40); assert_true(h > 15.0 and h < 17.0, "둑 %.1f" % h)

func test_tower_islet_above_lake():
	assert_true(f.height_at(0, -10) > 16.0, "탑 섬 %.1f" % f.height_at(0, -10))

func test_mountain_peak():
	assert_true(f.height_at(0, -120) > 50.0, "산 %.1f" % f.height_at(0, -120))

func test_canyon_and_plateau():
	assert_true(f.height_at(-95, -20) < 4.0, "협곡 %.1f" % f.height_at(-95, -20))
	assert_true(f.height_at(-70, -30) > 30.0, "능선 %.1f" % f.height_at(-70, -30))
	var p := f.height_at(-125, -20); assert_true(p > 17.0 and p < 23.0, "고원 %.1f" % p)

func test_sea_outside():
	assert_true(f.height_at(149, 149) < 0.0)
