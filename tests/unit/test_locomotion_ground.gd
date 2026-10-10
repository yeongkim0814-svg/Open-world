extends TestCase
const DT := 1.0 / 60.0
var t := MovementTuning.new()
func _loco() -> Locomotion: return Locomotion.new(t, Stamina.new(t))
func _floor() -> Dictionary: return {"on_floor": true, "wall_normal": Vector3.ZERO, "ledge_top": false}
func _intent(move := Vector2.ZERO, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.jump_pressed = jump; return i

func test_full_stick_runs_forward():
	var v := _loco().step(_intent(Vector2(0, 1)), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.run_speed)
	assert_almost(v.z, -t.run_speed)          # Godot 전방 = -Z

func test_half_stick_walks():
	var v := _loco().step(_intent(Vector2(0, 0.4)), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.walk_speed)

func test_camera_yaw_rotates_direction():
	var i := _intent(Vector2(0, 1)); i.camera_yaw = PI / 2
	var v := _loco().step(i, _floor(), DT)
	assert_almost(v.x, -t.run_speed)

func test_small_stick_walks_without_stamina():
	var s := Stamina.new(t); var l := Locomotion.new(t, s)
	var v := l.step(_intent(Vector2(0, 0.5)), _floor(), 1.0)
	assert_almost(Vector2(v.x, v.z).length(), t.walk_speed)
	assert_almost(s.value, t.stamina_max, 0.001, "걷기는 스태미나를 쓰지 않음")

func test_large_stick_runs_and_drains():
	var s := Stamina.new(t); var l := Locomotion.new(t, s)
	var v := l.step(_intent(Vector2(0, 0.7)), _floor(), 1.0)
	assert_almost(Vector2(v.x, v.z).length(), t.run_speed)
	assert_almost(s.value, t.stamina_max - t.run_cost)

func test_exhausted_run_falls_back_to_walk():
	var s := Stamina.new(t); s.spend(100.0)
	var l := Locomotion.new(t, s)
	var v := l.step(_intent(Vector2(0, 1)), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.walk_speed)

func test_auto_run_runs_toward_camera_without_stick():
	var i := _intent(); i.auto_run = true; i.camera_yaw = PI / 2
	var v := _loco().step(i, _floor(), DT)
	assert_almost(v.x, -t.run_speed)





func test_jump_leaves_ground():
	var l := _loco()
	var v := l.step(_intent(Vector2.ZERO, true), _floor(), DT)
	assert_almost(v.y, t.jump_velocity)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_gravity_applies_in_air():
	var l := _loco(); l.state = Locomotion.State.AIRBORNE
	var air := {"on_floor": false, "wall_normal": Vector3.ZERO, "ledge_top": false}
	var v := l.step(_intent(), air, DT)
	assert_almost(v.y, -t.gravity * DT)


func test_threatened_jump_with_stick_dodges():
	var s := Stamina.new(t); var l := Locomotion.new(t, s)
	var i := _intent(Vector2(0, -1), true); i.threatened = true
	l.step(i, _floor(), DT)
	assert_eq(l.state, Locomotion.State.DODGING)
	assert_true(l.is_invulnerable())
	assert_almost(s.value, t.stamina_max - CombatTuning.new().dodge_cost)

func test_not_threatened_jump_with_stick_is_jump():
	var l := _loco(); l.step(_intent(Vector2(0, -1), true), _floor(), DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_exhausted_dodge_does_nothing():               # Review Focus 2
	var s := Stamina.new(t); s.spend(100.0); var l := Locomotion.new(t, s)
	var i := _intent(Vector2(0, -1), true); i.threatened = true
	var v := l.step(i, _floor(), DT)
	assert_eq(l.state, Locomotion.State.GROUNDED); assert_almost(v.y, 0.0)

func test_dodge_ends_after_duration():
	var l := _loco(); var i := _intent(Vector2(1, 0), true); i.threatened = true
	l.step(i, _floor(), DT)
	for k in 30: l.step(_intent(), _floor(), DT)          # 0.5초 > 0.45
	assert_eq(l.state, Locomotion.State.GROUNDED); assert_false(l.is_invulnerable())
