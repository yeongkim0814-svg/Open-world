class_name ViewRule
extends RefCounted
## 바라보기·카메라 규칙 (C14 개정).
## 걷기 = 둘러보기 모드: 카메라를 돌려도 캐릭터 방향 유지, 카메라 자동 회전 없음 (평상시·전투 공통).
##   단, 평상시 정지 상태에서 걷기를 시작하는 순간에만 카메라 방향으로 몸을 맞춘다.
## 달리기(직접·자동) = 카메라와 한 몸: 캐릭터는 이동 방향을 보고, 카메라는 등 뒤를 따라간다.
## 등반 = 카메라 자유 (입력은 벽 기준), 회피 = 방향 고정.

enum Facing { KEEP, MOVE, CAMERA, WALL }


## walk_start = 정지 상태에서 막 걷기 시작해 정렬 중인지 (Player가 판정).
static func facing(state: Locomotion.State, intent: InputIntent, tuning: MovementTuning, walk_start: bool) -> Facing:
	match state:
		Locomotion.State.DODGING:
			return Facing.KEEP
		Locomotion.State.CLIMBING:
			return Facing.WALL
		Locomotion.State.GLIDING:
			return Facing.MOVE
	if Locomotion.wants_run(intent, tuning):
		return Facing.MOVE
	if walk_start and not intent.in_combat:
		return Facing.CAMERA
	return Facing.KEEP


## 카메라가 캐릭터 등 뒤로 자동 정렬하는지: 지상·공중에서 달리는 동안만.
static func camera_follows(state: Locomotion.State, intent: InputIntent, tuning: MovementTuning) -> bool:
	if state != Locomotion.State.GROUNDED and state != Locomotion.State.AIRBORNE:
		return false
	return Locomotion.wants_run(intent, tuning) and (intent.auto_run or not intent.move.is_zero_approx())
