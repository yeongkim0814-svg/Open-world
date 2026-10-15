extends TestCase
## 수영: 깊은 물 = SWIMMING, 이동 시 스태미나 소모, 가만히 있으면 회복 정지, 점프 = 가속, 탈진하면 익사.
const DT := 1.0 / 60.0
var t := MovementTuning.new()

func _sense(depth: float, floor := false, wall := Vector3.ZERO) -> Dictionary:
	return {"on_floor": floor, "wall_normal": wall, "ledge_top": false, "water_depth": depth}
func _intent(move := Vector2.ZERO, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.jump_pressed = jump; return i

func test_enters_swim_when_deep():
	var l := Locomotion.new(t, Stamina.new(t))
	l.step(_intent(), _sense(1.5, true), DT)
	assert_eq(l.state, Locomotion.State.SWIMMING)

func test_shallow_water_walks():
	var l := Locomotion.new(t, Stamina.new(t))
	l.step(_intent(Vector2(0, 1)), _sense(0.6, true), DT)
	assert_eq(l.state, Locomotion.State.GROUNDED)

func test_swim_speed_and_drain():
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.SWIMMING
	var v := Vector3.ZERO
	for i in 60: v = l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.swim_speed)
	assert_almost(s.value, t.stamina_max - t.swim_cost, 0.01)

func test_idle_swim_does_not_regen():
	var s := Stamina.new(t); s.spend(50.0); var l := Locomotion.new(t, s); l.state = Locomotion.State.SWIMMING
	for i in 180:
		l.step(_intent(), _sense(t.swim_depth), DT); s.tick(DT)
	assert_almost(s.value, 50.0, 0.01, "물에 떠 있는 동안은 소모도 회복도 없음")

func test_jump_dashes():
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.SWIMMING
	var v := l.step(_intent(Vector2(0, 1), true), _sense(t.swim_depth), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.swim_dash_speed)
	assert_true(s.value <= t.stamina_max - t.swim_dash_cost)
	for i in int(t.swim_dash_time / DT) + 2: v = l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.swim_speed)

func test_floats_up_when_deep():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.SWIMMING
	var v := l.step(_intent(), _sense(3.0), DT)
	assert_true(v.y > 0.0)

func test_exhausted_drowns_after_time():
	var s := Stamina.new(t); s.spend(100.0); var l := Locomotion.new(t, s); l.state = Locomotion.State.SWIMMING
	var v := Vector3.ZERO
	for i in int(t.drown_time / DT) - 5: v = l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth), DT); s.tick(DT)
	assert_false(l.drowned)
	assert_almost(Vector2(v.x, v.z).length(), 0.0, 0.001, "탈진하면 헤엄치지 못하고 가라앉음")
	for i in 10: l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth), DT); s.tick(DT)
	assert_true(l.drowned)

func test_walks_out_on_shallow_floor():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.SWIMMING
	l.step(_intent(Vector2(0, 1)), _sense(0.5, true), DT)
	assert_eq(l.state, Locomotion.State.GROUNDED)

func test_wall_from_water_climbs():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.SWIMMING
	l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth, false, Vector3(0, 0, 1)), DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_climbing_down_into_water_swims():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	l.step(_intent(Vector2(0, -1)), _sense(t.swim_depth + 0.5, false, Vector3(0, 0, 1)), DT)
	assert_eq(l.state, Locomotion.State.SWIMMING)

func test_climbing_up_out_of_water_keeps_climbing():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	l.step(_intent(Vector2(0, 1)), _sense(t.swim_depth + 0.5, false, Vector3(0, 0, 1)), DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_glide_into_water_swims():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.GLIDING
	l.step(_intent(), _sense(1.5), DT)
	assert_eq(l.state, Locomotion.State.SWIMMING)

func test_water_volume_depth():
	var w := Water.new(); w.size = Vector3(10, 4, 10)       # 중심 원점 → 수면 y = 2
	assert_almost(w.depth_at(Vector3(1, 0.5, 1)), 1.5)
	assert_true(w.depth_at(Vector3(20, 0.5, 1)) < 0.0, "수평 범위 밖")
	assert_true(w.depth_at(Vector3(1, 3.0, 1)) < 0.0, "수면 위")
	w.free()

## 둥근 물(저수호): 상자 모서리(원 밖)는 물이 아니다.
func test_round_water_corner_is_dry():
	var w := Water.new()
	w.size = Vector3(220, 20, 220)
	w.circular = true
	assert_true(w.depth_at(Vector3(0, 5, 100)) > 0.0, "원 안은 물")
	assert_eq(w.depth_at(Vector3(105, 5, 105)), -1.0, "모서리(148m)는 물 아님")
	w.free()

## 모양 해자: area 가 false 인 칸(섬·둑)은 상자 안이어도 물이 아니다.
func test_shaped_water_area():
	var w := Water.new()
	w.size = Vector3(100, 20, 100)
	w.circular = true
	w.area = func(x: float, _z: float) -> bool: return absf(x) > 20.0
	assert_true(w.depth_at(Vector3(30, 5, 0)) > 0.0, "물 칸")
	assert_eq(w.depth_at(Vector3(0, 5, 0)), -1.0, "섬 칸은 물 아님")
	w.free()
