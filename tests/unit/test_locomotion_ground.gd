extends TestCase
const DT := 1.0 / 60.0
var t := MovementTuning.new()
func _loco() -> Locomotion: return Locomotion.new(t, Stamina.new(t))
func _floor() -> Dictionary: return {"on_floor": true, "wall_normal": Vector3.ZERO, "ledge_top": false}
func _intent(move := Vector2.ZERO, sprint := false, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.sprint = sprint; i.jump_pressed = jump; return i

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

func test_sprint_spends_stamina_and_falls_back_when_exhausted():
	var l := _loco()
	for k in 301: l.step(_intent(Vector2(0, 1), true), _floor(), DT)
	var v := l.step(_intent(Vector2(0, 1), true), _floor(), DT)
	assert_almost(Vector2(v.x, v.z).length(), t.run_speed)   # 탈진 → 달리기로 복귀

func test_jump_leaves_ground():
	var l := _loco()
	var v := l.step(_intent(Vector2.ZERO, false, true), _floor(), DT)
	assert_almost(v.y, t.jump_velocity)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_gravity_applies_in_air():
	var l := _loco(); l.state = Locomotion.State.AIRBORNE
	var air := {"on_floor": false, "wall_normal": Vector3.ZERO, "ledge_top": false}
	var v := l.step(_intent(), air, DT)
	assert_almost(v.y, -t.gravity * DT)
