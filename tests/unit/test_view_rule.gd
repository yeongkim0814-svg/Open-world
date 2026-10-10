extends TestCase
## 바라보기·카메라 규칙: 걷기 = 둘러보기(방향 유지), 달리기 = 카메라와 한 몸, 등반 = 카메라 자유.
const S := Locomotion.State
var t := MovementTuning.new()
func _i(move := Vector2.ZERO) -> InputIntent:
	var i := InputIntent.new(); i.move = move; return i

func test_walking_keeps_facing_even_while_camera_turns():
	var i := _i(Vector2(0.3, 0)); i.camera_held = true
	assert_eq(ViewRule.facing(S.GROUNDED, i, t, false), ViewRule.Facing.KEEP)

func test_walking_in_combat_keeps_facing():
	var i := _i(Vector2(-0.4, 0)); i.in_combat = true
	assert_eq(ViewRule.facing(S.GROUNDED, i, t, false), ViewRule.Facing.KEEP)

func test_walk_start_aligns_to_camera_outside_combat():
	assert_eq(ViewRule.facing(S.GROUNDED, _i(Vector2(0, 0.3)), t, true), ViewRule.Facing.CAMERA)

func test_walk_start_in_combat_keeps_facing():
	var i := _i(Vector2(0, 0.3)); i.in_combat = true
	assert_eq(ViewRule.facing(S.GROUNDED, i, t, true), ViewRule.Facing.KEEP)

func test_running_faces_movement():
	assert_eq(ViewRule.facing(S.GROUNDED, _i(Vector2(1, 0)), t, false), ViewRule.Facing.MOVE)

func test_auto_run_faces_movement():
	var i := _i(); i.auto_run = true
	assert_eq(ViewRule.facing(S.GROUNDED, i, t, false), ViewRule.Facing.MOVE)

func test_dodge_climb_glide():
	assert_eq(ViewRule.facing(S.DODGING, _i(Vector2(1, 0)), t, false), ViewRule.Facing.KEEP)
	assert_eq(ViewRule.facing(S.CLIMBING, _i(Vector2(1, 0)), t, false), ViewRule.Facing.WALL)
	assert_eq(ViewRule.facing(S.GLIDING, _i(Vector2(0.3, 0)), t, false), ViewRule.Facing.MOVE)

func test_camera_follows_only_while_running():
	assert_true(ViewRule.camera_follows(S.GROUNDED, _i(Vector2(0, 1)), t))
	var a := _i(); a.auto_run = true
	assert_true(ViewRule.camera_follows(S.AIRBORNE, a, t))
	assert_false(ViewRule.camera_follows(S.GROUNDED, _i(Vector2(0.4, 0)), t), "걷기")
	assert_false(ViewRule.camera_follows(S.GROUNDED, _i(), t), "정지")
	assert_false(ViewRule.camera_follows(S.CLIMBING, _i(Vector2(0, 1)), t), "등반")
	assert_false(ViewRule.camera_follows(S.DODGING, _i(Vector2(0, 1)), t), "회피")
