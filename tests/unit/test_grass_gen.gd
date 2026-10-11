extends TestCase

## 낮은 풀(LOW): 높이 ≤ 0.16, 폭 ≥ 0.3.
func test_grass_low():
	var bb := GrassGen.build(GrassGen.Kind.LOW).get_aabb()
	assert_true(bb.size.y <= 0.16, "LOW 높이 %.3f > 0.16" % bb.size.y)
	assert_true(maxf(bb.size.x, bb.size.z) >= 0.3, "LOW 폭 %.3f < 0.3" % maxf(bb.size.x, bb.size.z))
