extends TestCase

func _one(radius := 50.0) -> Recovery:
	var r := Recovery.new()
	r.add_region(&"a", Vector2.ZERO, radius)
	return r

func test_stage_bounds():
	var r := _one()
	assert_eq(r.stage(&"a"), Recovery.Stage.DEPLETED, "0.0")
	r.add_progress(&"a", 0.29)
	assert_eq(r.stage(&"a"), Recovery.Stage.DEPLETED, "0.29")
	r.add_progress(&"a", 0.01)
	assert_eq(r.stage(&"a"), Recovery.Stage.REGENERATING, "0.3")
	r.add_progress(&"a", 0.09)
	r.neutralize_tower(&"a")
	assert_eq(r.stage(&"a"), Recovery.Stage.RESTORED, "탑")
	var p := _one()
	p.set_preview(0.99)
	assert_eq(p.stage(&"a"), Recovery.Stage.REGENERATING, "0.99")

func test_task_progress_capped_below_tower():
	var r := _one()
	r.add_progress(&"a", 0.3)
	r.add_progress(&"a", 0.3)
	assert_almost(r.value(&"a"), 0.4, 0.0001, "과제 합계 상한")
	r.neutralize_tower(&"a")
	assert_almost(r.value(&"a"), 1.0, 0.0001, "탑 무력화")

func test_progress_after_tower_stays_one():
	var r := _one()
	r.neutralize_tower(&"a")
	r.add_progress(&"a", 0.3)
	assert_almost(r.value(&"a"), 1.0, 0.0001, "탑 후에도 1.0")

func test_negative_progress_ignored():
	var r := _one()
	r.add_progress(&"a", -0.2)
	assert_almost(r.value(&"a"), 0.0, 0.0001, "음수 무시")

func test_value_at_inside_edge_outside():
	var r := _one(50.0)
	r.neutralize_tower(&"a")
	assert_almost(r.value_at(Vector2.ZERO), 1.0, 0.0001, "중심")
	assert_almost(r.value_at(Vector2(50, 0)), 1.0, 0.0001, "반경 위")
	assert_almost(r.value_at(Vector2(50.0 + Recovery.EDGE, 0)), 0.0, 0.0001, "가장자리 끝")
	var mid := r.value_at(Vector2(50.0 + Recovery.EDGE * 0.5, 0))
	assert_true(mid > 0.0 and mid < 1.0, "번짐 구간 0~1: %s" % mid)

func test_overlapping_regions_take_max():
	var r := Recovery.new()
	r.add_region(&"a", Vector2.ZERO, 30.0)
	r.add_region(&"b", Vector2(10, 0), 30.0)
	r.add_progress(&"a", 0.4)
	r.neutralize_tower(&"b")
	assert_almost(r.value_at(Vector2(5, 0)), 1.0, 0.0001, "합산 아닌 최댓값")

func test_bake_size_and_values():
	var r := _one(100.0)
	r.neutralize_tower(&"a")
	var a := r.bake(Rect2(-64, -64, 128, 128), 8)
	assert_eq(a.size(), 64, "8x8")
	assert_almost(a[4 * 8 + 4], 1.0, 0.0001, "중심 근처 칸")

func test_bake_outside_rect_is_zero():
	var r := Recovery.new()
	r.add_region(&"far", Vector2(1000, 1000), 50.0)
	r.neutralize_tower(&"far")
	var a := r.bake(Rect2(-64, -64, 128, 128), 8)
	for v in a:
		assert_almost(v, 0.0, 0.0001, "rect 밖 지역은 0")

func test_preview_overrides_and_clears():
	var r := _one()
	r.add_progress(&"a", 0.2)
	r.set_preview(0.7)
	assert_almost(r.value(&"a"), 0.7, 0.0001, "프리뷰")
	r.set_preview(-1.0)
	assert_almost(r.value(&"a"), 0.2, 0.0001, "원래 값")

func test_dict_roundtrip():
	var r := Recovery.new()
	r.add_region(&"a", Vector2(3, 4), 20.0)
	r.add_region(&"b", Vector2(-5, 6), 30.0)
	r.add_progress(&"a", 0.2)
	r.neutralize_tower(&"b")
	var r2 := Recovery.from_dict(r.to_dict())
	assert_almost(r2.value(&"a"), 0.2, 0.0001, "a")
	assert_almost(r2.value(&"b"), 1.0, 0.0001, "b")
	assert_almost(r2.value_at(Vector2(3, 4)), r.value_at(Vector2(3, 4)), 0.0001, "위치")

## 최종 리뷰: 저장값의 음수 진행도는 0으로.
func test_from_dict_negative_progress_clamped():
	var r := Recovery.new()
	r.add_region(&"a", Vector2.ZERO, 10.0)
	var d := r.to_dict()
	d["regions"]["a"]["progress"] = -5.0
	assert_almost(Recovery.from_dict(d).value(&"a"), 0.0, 0.0001)
