extends TestCase

func test_open_sluice_once():                       # Review Focus 2
	var s := WorldState.new()
	assert_true(s.open_sluice(1))
	assert_false(s.open_sluice(1))
	assert_eq(s.open_count(), 1)

func test_out_of_range_ignored():
	var s := WorldState.new()
	assert_false(s.open_sluice(5))
	assert_false(s.open_sluice(-1))
	assert_eq(s.open_count(), 0)

func test_stop_records_outcome_once():              # Review Focus 3
	var s := WorldState.new()
	s.open_sluice(0); s.open_sluice(2)
	assert_true(s.stop_tower())
	assert_eq(s.outcome_at_stop, 2)
	s.open_sluice(1)
	assert_false(s.stop_tower())
	assert_eq(s.outcome_at_stop, 2)
	assert_eq(s.open_count(), 3)

func test_round_trip():
	var s := WorldState.new()
	s.open_sluice(1); s.stop_tower(); s.departed.append(&"아이")
	var r := WorldState.from_dict(s.to_dict())
	assert_eq(r.sluices, [false, true, false])
	assert_true(r.tower_stopped)
	assert_eq(r.outcome_at_stop, 1)
	assert_eq(r.departed, [&"아이"])

func test_from_garbage_defaults():
	var r := WorldState.from_dict({"sluices": "x", "tower_stopped": 5, "outcome_at_stop": "a"})
	assert_eq(r.sluices, [false, false, false])
	assert_false(r.tower_stopped)
	assert_eq(r.outcome_at_stop, -1)

func test_lake_levels():
	assert_almost(LakeLevel.level(14.6, 0), 14.6)
	assert_almost(LakeLevel.level(14.6, 1), 10.7)
	assert_almost(LakeLevel.level(14.6, 2), 6.8)
	assert_almost(LakeLevel.level(14.6, 3), 2.9)
	assert_almost(LakeLevel.level(14.6, 7), 2.9)
