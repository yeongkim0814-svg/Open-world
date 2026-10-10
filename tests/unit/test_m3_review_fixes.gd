extends TestCase
## M3 최종 리뷰 Important 1~4 재현 테스트.

func test_arrow_behind_blade_core_counts_as_weak():          # Important 1
	# 칼날형 코어 (0,1.45,0.3), 뒷면 z=+0.8에 수평으로 맞은 화살: 표면 점은 코어에서 0.5m지만 진행선은 코어를 지난다.
	assert_true(Hit.passes_near(Vector3(0, 1.45, 0.8), Vector3(0, 0, -1), Vector3(0, 1.45, 0.3), 0.4))
	assert_false(Hit.passes_near(Vector3(0.6, 1.0, 0.8), Vector3(0, 0, -1), Vector3(0, 1.45, 0.3), 0.4))

func test_returning_machine_realerts_when_hit_well_inside_leash():   # Important 2
	var b := MachineBrain.new(preload("res://resources/machines/blade.tres"))
	b.decide(5.0, 26.0, false)                                 # 끌려감 → 귀환 시작
	assert_eq(b.decide(10.0, 24.0, true), MachineBrain.Mode.RETURN)   # 경계선 근처 맞음 → 계속 귀환 (진동 방지)
	assert_eq(b.decide(10.0, 18.0, true), MachineBrain.Mode.CHASE)    # 충분히 안쪽에서 맞음 → 반격
	assert_true(b.alerted)

func test_switch_to_bow_while_attack_held_does_not_draw():   # Important 3
	var c := PlayerCombat.new(); c.setup(null)
	c.switch_weapon(); c.switch_weapon()                       # → 활
	var i := InputIntent.new(); i.attack_held = true
	c.tick(i, 1.0 / 60.0)
	assert_false(c.is_drawing(), "교체 전부터 누르던 공격은 무시")
	var up := InputIntent.new(); up.heavy_released = true
	c.tick(up, 1.0 / 60.0)                                     # 떼는 순간도 발사 안 함 (_player가 null이라 발사하면 오류)
	var again := InputIntent.new(); again.attack_held = true
	c.tick(again, 1.0 / 60.0)
	assert_true(c.is_drawing(), "새로 누르면 당긴다")
	c.free()

func test_attack_drag_turns_camera_while_aiming():            # Important 4
	var tc := TouchControls.new(); tc.size = Vector2(1920, 1080)
	var attack: Vector2 = tc._buttons()["attack"]
	tc._on_touch_down(3, attack)
	tc.set_aiming(true)
	var ev := InputEventScreenDrag.new(); ev.index = 3; ev.position = attack + Vector2(40, -10)
	tc._input(ev)
	assert_eq(tc.consume_camera_drag(), Vector2(40, -10))
	tc.set_aiming(false)
	ev.position = attack + Vector2(80, -10)
	tc._input(ev)
	assert_eq(tc.consume_camera_drag(), Vector2.ZERO, "조준 중이 아니면 공격 버튼 드래그는 카메라를 돌리지 않음")
	tc.free()
