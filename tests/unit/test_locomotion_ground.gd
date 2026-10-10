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

func test_walk_keeps_facing():
	assert_false(Locomotion.turns_to_move(_intent(Vector2(0.3, 0)), t))

func test_run_turns_to_move():
	assert_true(Locomotion.turns_to_move(_intent(Vector2(1, 0)), t))

func test_camera_held_run_keeps_facing():
	var i := _intent(Vector2(1, 0)); i.camera_held = true
	assert_false(Locomotion.turns_to_move(i, t))

func test_auto_run_always_turns_even_with_camera_held():
	var i := _intent(); i.auto_run = true; i.camera_held = true
	assert_true(Locomotion.turns_to_move(i, t))

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

func test_in_combat_walk_turns_to_move():
	var i := _intent(Vector2(0.3, 0)); i.in_combat = true
	assert_true(Locomotion.turns_to_move(i, t))
