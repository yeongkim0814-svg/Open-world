extends TestCase

func _map() -> RecoveryMap:
	var m := RecoveryMap.new()
	m.world_rect = Rect2(-64, -64, 128, 128)
	m.resolution = 16
	m.model = Recovery.new()
	m.model.add_region(&"a", Vector2.ZERO, 200.0)
	m.model.neutralize_tower(&"a")
	m.refresh()
	return m

func test_step_moves_toward_target_without_jump():
	var m := _map()
	m.step(0.5)
	assert_almost(m.displayed_at(Vector2.ZERO), 0.25, 0.01, "0.5초 후")
	for i in 8:
		m.step(0.5)
	assert_almost(m.displayed_at(Vector2.ZERO), 1.0, 0.01, "4초 후")
	m.free()

func test_displayed_at_outside_rect_zero():
	var m := _map()
	for i in 8:
		m.step(0.5)
	assert_almost(m.displayed_at(Vector2(500, 0)), 0.0, 0.0001, "rect 밖")
	m.free()

## 최종 리뷰: 목표에 도달한 뒤에는 매 프레임 다시 굽거나 올리지 않는다.
func test_settled_map_skips_upload():
	var m := _map()
	for i in 8:
		m.step(0.5)
	assert_true(m.is_settled(), "수렴 후 정지")
	var n := m.upload_count
	m.step(0.5)
	m.step(0.5)
	assert_eq(m.upload_count, n, "정지 상태에서는 텍스처를 다시 올리지 않음")
	m.model.set_preview(0.2)
	m.refresh()
	assert_false(m.is_settled(), "목표가 바뀌면 다시 움직임")
	m.step(0.5)
	assert_eq(m.upload_count, n + 1)
	m.free()
