extends TestCase
## 바라보기 규칙 (C14 개정 2): 캐릭터는 항상 카메라 방향. 등반 = 벽, 회피 = 고정.
const S := Locomotion.State
var t := MovementTuning.new()
func _i(move := Vector2.ZERO) -> InputIntent:
	var i := InputIntent.new(); i.move = move; return i

func test_faces_camera_while_walking_sideways():
	assert_eq(ViewRule.facing(S.GROUNDED, _i(Vector2(-0.4, 0))), ViewRule.Facing.CAMERA)

func test_faces_camera_while_running_and_idle():
	assert_eq(ViewRule.facing(S.GROUNDED, _i(Vector2(0, 1))), ViewRule.Facing.CAMERA)
	assert_eq(ViewRule.facing(S.GROUNDED, _i()), ViewRule.Facing.CAMERA)
	assert_eq(ViewRule.facing(S.AIRBORNE, _i()), ViewRule.Facing.CAMERA)
	assert_eq(ViewRule.facing(S.GLIDING, _i(Vector2(1, 0))), ViewRule.Facing.CAMERA)

func test_dodge_keeps_and_climb_faces_wall():
	assert_eq(ViewRule.facing(S.DODGING, _i(Vector2(1, 0))), ViewRule.Facing.KEEP)
	assert_eq(ViewRule.facing(S.CLIMBING, _i(Vector2(1, 0))), ViewRule.Facing.WALL)
