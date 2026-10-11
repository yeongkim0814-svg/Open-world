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

func _held(move := Vector2.ZERO, pressed := false) -> InputIntent:
	var i := _intent(move, pressed); i.jump_held = true; return i

func test_holding_jump_while_falling_glides():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.AIRBORNE
	l.velocity = Vector3(0, -5, 0)
	var v := l.step(_held(Vector2(0, 1)), air, DT)
	assert_eq(l.state, Locomotion.State.GLIDING)
	assert_almost(v.y, -t.glide_fall_speed)

func test_releasing_jump_closes_glider():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.GLIDING
	l.step(_intent(Vector2(0, 1)), air, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

func test_tap_jump_in_air_does_not_toggle():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.GLIDING
	l.step(_held(Vector2(0, 1), true), air, DT)
	assert_eq(l.state, Locomotion.State.GLIDING)

func test_held_from_ground_jump_glides_after_apex():       # Review Focus 1
	var l := Locomotion.new(t, Stamina.new(t))
	var ground := {"on_floor": true, "wall_normal": Vector3.ZERO, "ledge_top": false}
	l.step(_held(Vector2.ZERO, true), ground, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	var opened_while_rising := false
	for i in 120:
		var rising := l.velocity.y > 0.0
		l.step(_held(), air, DT)
		if l.state == Locomotion.State.GLIDING:
			opened_while_rising = rising
			break
	assert_eq(l.state, Locomotion.State.GLIDING)
	assert_false(opened_while_rising, "올라가는 중에는 펼치지 않음")

func test_wall_regrab_beats_glide():                       # Review Focus 2
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	l.step(_held(Vector2(0, 1), true), wall, DT)          # 벽 점프
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	l.velocity.y = -1.0
	l.step(_held(Vector2(0, 1)), wall, DT)                 # 떨어지며 버튼 유지 + 벽
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_gliding_into_wall_grabs():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.GLIDING
	l.step(_held(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_exhausted_glider_does_not_reopen_while_held():   # Review Focus 3
	var s := Stamina.new(t); var l := Locomotion.new(t, s); l.state = Locomotion.State.GLIDING
	s.spend(99.99)
	l.step(_held(Vector2(0, 1)), air, 1.0)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	l.velocity.y = -3.0
	for i in 30:
		l.step(_held(Vector2(0, 1)), air, DT); s.tick(DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)

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


func test_ledge_hop_does_not_regrab_next_wall_before_landing():   # 탑 계단식 단: 도약 중 다음 단 벽을 잡지 않음
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	_hop(l)
	var into_wall := _intent(Vector2(0, 1))
	for i in 50:                      # 0.83s — 기존 재등반 금지(0.5s)보다 길게, 아직 공중
		l.step(into_wall, wall, DT)
	assert_eq(l.state, Locomotion.State.AIRBORNE)
	var floor_wall := wall.duplicate(); floor_wall["on_floor"] = true
	l.velocity.y = -1.0
	l.step(into_wall, floor_wall, DT)                    # 착지
	l.step(into_wall, floor_wall, DT)                    # 착지 후 벽으로 밀면 다시 등반
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_ledge_hop_missed_can_regrab_when_falling_fast():
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	_hop(l)
	l.velocity.y = -13.0
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING, "단을 놓쳐 크게 떨어지면 다시 잡을 수 있음")

func test_steep_slope_head_on_starts_climb():           # 지형 경사(70°) 정면으로 밀면 등반
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.GROUNDED
	var slope := {"on_floor": true, "wall_normal": Vector3(0, 0.342, 0.94), "ledge_top": false}
	l.step(_intent(Vector2(0, 1)), slope, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

func test_climbing_slope_follows_surface():              # 경사면 등반은 면을 따라 위로 (면에서 떨어지지 않음)
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	var slope := {"on_floor": false, "wall_normal": Vector3(0, 0.342, 0.94), "ledge_top": false}
	var v := l.step(_intent(Vector2(0, 1)), slope, DT)
	assert_true(v.y > 0.0)
	assert_true(v.dot(Vector3(0, 0.342, 0.94)) <= 0.0, "면에서 멀어지지 않음 (속도·법선 ≤ 0): %s" % v)

func test_hop_then_glide_landing_clears_guard():          # 리뷰 Important 1: 활공 착지 후에도 벽을 잡을 수 있어야 함
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	_hop(l)
	l.velocity.y = -1.0
	l.step(_held(), air, DT)                              # 떨어지며 점프 버튼 유지 → 활공
	assert_eq(l.state, Locomotion.State.GLIDING)
	var floor_air := {"on_floor": true, "wall_normal": Vector3.ZERO, "ledge_top": false}
	l.step(_held(Vector2(0, 1)), floor_air, DT)           # 활공 중 착지
	assert_eq(l.state, Locomotion.State.GROUNDED)
	assert_false(l._hop_guard, "착지하면 올라서기 가드가 풀려야 함")
	var into_wall := _intent(Vector2(0, 1))
	for i in 60:                                           # 1초: 재등반 금지(0.5s)는 이미 풀린 뒤
		l.step(into_wall, wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING, "착지 후 벽을 잡을 수 있어야 함 (가드가 남아 있으면 실패)")

func test_hop_guard_expires_without_landing():            # 경사에 착지(바닥 아님) 못 해도 1초 뒤엔 다시 잡을 수 있음
	var l := Locomotion.new(t, Stamina.new(t)); l.state = Locomotion.State.CLIMBING
	_hop(l)
	for i in 70:                                          # 1.17s 공중, 벽 감지 없음
		l.step(_intent(), air, DT)
		l.velocity.y = maxf(l.velocity.y, -2.0)           # 경사를 미끄러지는 느린 낙하
	l.step(_intent(Vector2(0, 1)), wall, DT)
	assert_eq(l.state, Locomotion.State.CLIMBING)

## 2km 리뷰: 가슴 레이 3개 평균 — 계단 절벽은 평균으로 바로잡되, 옆 레이가 엉뚱한 면(앞의 경사 바닥·옆 물체)에 맞아도 벽을 잃지 않음.
func test_side_rays_fix_staircase_wall():
	var n := Locomotion.average_wall_normal(Vector3(0.707, 0.0, 0.707), [Vector3(-0.707, 0.0, 0.707), Vector3(0.707, 0.0, 0.707)])
	assert_true(Vector3(0, 0, 1).angle_to(n) < deg_to_rad(30.0), "계단 법선 평균이 실제 벽(+z) 쪽: %s" % n)

func test_side_ray_on_floor_ignored():
	var n := Locomotion.average_wall_normal(Vector3(0, 0, 1), [Vector3(0, 0.9, 0.436), Vector3.ZERO])
	assert_true(n.is_equal_approx(Vector3(0, 0, 1)), "옆 레이가 바닥에 맞으면 가운데 법선만: %s" % n)

func test_side_ray_facing_away_ignored():
	var n := Locomotion.average_wall_normal(Vector3(0, 0, 1), [Vector3(0, 0, -1), Vector3(1, 0, 0)])
	assert_true(Vector3(0, 0, 1).angle_to(n) < deg_to_rad(46.0), "반대쪽 면은 빼고, 옆 벽까지만 섞음: %s" % n)
