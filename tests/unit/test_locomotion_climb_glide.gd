extends TestCase
const DT := 1.0 / 60.0
var t := MovementTuning.new()
var wall := {"on_floor": false, "wall_normal": Vector3(0, 0, 1), "ledge_top": false}
var air := {"on_floor": false, "wall_normal": Vector3.ZERO, "ledge_top": false}
func _intent(move := Vector2.ZERO, jump := false) -> InputIntent:
	var i := InputIntent.new(); i.move = move; i.jump_pressed = jump; return i

func test_pushing_into_wall_starts_climb():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_climb_up_moves_up_and_drains():
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.CLIMBING
	var v := l.step(_intent(Vector2(0, 1)), wall, 1.0)
	assert_almost(v.y, t.climb_speed)
	assert_almost(s.value, t.stamina_max - t.climb_cost)

func test_zero_stamina_falls_off_wall():          # Review Focus 2
	var s := Stamina.new(t); s.spend(100.0)
	var l := Locomotion.new(t, s); l.state = Locomotion.State.CLIMBING
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_exhausted_cannot_start_climb():          # Review Focus 4
	var s := Stamina.new(t); s.spend(100.0); s.tick(1.0); s.tick(0.5)   # 12.5, 탈진 중
	var l := Locomotion.new(t, s); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_ledge_top_hops_up_and_over():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var top := wall.duplicate(); top["ledge_top"] = true
	var v := l.step(_intent(Vector2(0, 1)), top, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	assert_true(v.y * v.y / (2.0 * t.gravity) >= Locomotion.LEDGE_HOP_HEIGHT - 0.01, "몸 높이 이상 솟아야 함")
	assert_true(v.z < 0.0, "벽 너머(앞)로 이동해야 함")

func test_ledge_hop_keeps_vertical_speed_next_tick():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var top := wall.duplicate(); top["ledge_top"] = true
	var v0 := l.step(_intent(Vector2(0, 1)), top, DT)
	var v1 := l.step(_intent(Vector2(0, 1)), wall, DT)   # 아직 벽이 감지되어도
	assert_eq(l.state, Locomotion.State.AIRBORNE, "올라서는 중 다시 벽에 붙으면 안 됨")
	assert_almost(v1.y, v0.y - t.gravity * DT)

func test_jump_while_falling_opens_glider():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.velocity = Vector3(0, -5, 0)
	var v := l.step(_intent(Vector2(0, 1), true), air, DT)
	assert_eq(l.state, Locomotion.State.GLIDING)
	assert_almost(v.y, -t.glide_fall_speed)

func test_glider_closes_when_stamina_empty():      # Review Focus 2
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.GLIDING
	s.spend(99.99)
	l.step(_intent(Vector2(0, 1)), air, 1.0)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func _hop(l: Locomotion) -> void:
	var top := wall.duplicate(); top["ledge_top"] = true
	l.state = Locomotion.State.CLIMBING
	l.step(_intent(Vector2(0, 1)), top, DT)

func test_ledge_hop_forward_ignores_camera_yaw():          # 리뷰 Important 1
	var l := Locomotion.new(t, Stamina.new(t)); _hop(l)
	var i := _intent(Vector2(0, 1)); i.camera_yaw = PI / 2
	var v := l.step(i, air, DT)
	assert_almost(v.x, 0.0, 0.001, "카메라가 옆이어도 옆으로 흐르면 안 됨")
	assert_true(v.z < 0.0, "벽 너머 방향 유지")

func test_ledge_hop_forward_kept_without_stick():           # 리뷰 Important 1
	var l := Locomotion.new(t, Stamina.new(t)); _hop(l)
	var v := l.step(_intent(), air, DT)
	assert_true(v.z < 0.0, "스틱을 놓아도 벽 너머로 넘어가야 함")

func test_pull_down_at_wall_base_lets_go():                 # 리뷰 Important 2
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var base := wall.duplicate(); base["on_floor"] = true
	l.step(_intent(Vector2(0, -1)), base, DT)
	assert_eq(l.state, Locomotion.State.GROUNDED)

func test_hanging_still_does_not_regen():                   # 리뷰 Important 3
	var s := Stamina.new(t); s.spend(50.0)
	var l := Locomotion.new(t, s); l.state = Locomotion.State.CLIMBING
	for k in 300:
		l.step(_intent(), wall, DT)
		s.tick(DT)
	assert_almost(s.value, 50.0, 0.01)

func test_climb_jump_regrabs_regardless_of_camera():        # 리뷰 Important 4
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var i := _intent(Vector2(0, 1), true); i.camera_yaw = PI / 2
	l.step(i, wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	var j := _intent(Vector2(0, 1)); j.camera_yaw = PI / 2
	l.step(j, wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_walking_into_wall_grabs():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(0, 0.3)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING, "걷기로도 벽을 오름")

func test_wall_within_40_degrees_grabs():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(sin(deg_to_rad(35.0)), cos(deg_to_rad(35.0)))), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_wall_beside_does_not_grab():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.step(_intent(Vector2(sin(deg_to_rad(50.0)), cos(deg_to_rad(50.0)))), wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE, "벽을 옆에 끼고 이동할 때는 오르지 않음")
