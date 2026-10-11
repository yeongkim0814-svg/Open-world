extends TestCase

## 리뷰 #2: 수위가 바뀐 뒤 호수 원과 겹치는 풀 청크만 다시 만든다.
func test_invalidate_disc_requeues_overlapping_chunks():
	var g := GrassField.new()
	var near := Node3D.new()
	var far := Node3D.new()
	g._chunks[Vector2i(0, 0)] = near
	g._chunks[Vector2i(20, 20)] = far
	g.invalidate_disc(Vector2(4, 4), 10.0)
	assert_false(g._chunks.has(Vector2i(0, 0)), "겹치는 청크는 지워짐")
	assert_true(g._pending.has(Vector2i(0, 0)), "겹치는 청크는 다시 대기열에")
	assert_true(g._chunks.has(Vector2i(20, 20)), "먼 청크는 유지")
	far.free()
	g.free()

## 리뷰 #2: 저수호가 목표 수위에 닿으면 한 번 알린다.
func test_lake_emits_settled_once():
	var lake := Lake.new()
	lake.level = 14.6
	lake.set_target(14.0)
	var hits := [0]
	lake.level_settled.connect(func(): hits[0] += 1)
	for i in 120:
		lake._physics_process(1.0 / 60.0)
	assert_eq(hits[0], 1)
	assert_true(lake.is_settled())
	lake.free()
