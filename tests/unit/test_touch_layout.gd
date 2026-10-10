extends TestCase
## 리뷰 Important 5: 상호작용 팝업이 점프/회피 버튼과 겹치거나 너무 붙으면 회피 탭이 줍기로 새어 나간다.

func _gap_ok(size: Vector2) -> bool:
	var tc := TouchControls.new()
	tc.size = size
	var rect: Rect2 = tc._interact_rect()
	var ok := true
	var buttons: Dictionary = tc._buttons()
	for name in buttons:
		var c: Vector2 = buttons[name]
		var nearest := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
		if c.distance_to(nearest) < TouchControls.BUTTON_RADIUS + 40.0:
			ok = false
	tc.free()
	return ok

func test_popup_keeps_40px_from_buttons_on_s11_ultra():
	assert_true(_gap_ok(Vector2(2960, 1848)))

func test_popup_keeps_40px_from_buttons_on_16_9():
	assert_true(_gap_ok(Vector2(1920, 1080)))
