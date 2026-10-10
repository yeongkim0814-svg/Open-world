extends TestCase
## 리뷰 Important 6: 쓰러진 뒤 재시작하면 경직·연타·방어 상태가 남지 않아야 한다.

func test_reset_clears_combat_leftovers():
	var c := PlayerCombat.new()
	c.setup(null)
	c._stun = 1.0
	c.flurry.start()
	c.guard.press()
	c.hp = 5.0
	c.reset()
	assert_false(c.is_stunned())
	assert_false(c.flurry.active)
	assert_false(c.guard.holding)
	assert_almost(c.hp, c.combat_tuning.player_max_hp)
	c.free()
