class_name ViewRule
extends RefCounted
## 바라보기 규칙 (C14 개정 2, 3인칭 슈터 방식).
## 캐릭터는 항상 카메라 방향을 본다 — 오른손으로 카메라를 돌리면 캐릭터도 같이 돈다.
## 이동은 카메라 기준 스틱 방향 (옆·뒤는 게걸음·뒷걸음). 등반 = 벽, 회피 = 시작 방향 고정.

enum Facing { CAMERA, KEEP, WALL }


static func facing(state: Locomotion.State, _intent: InputIntent = null) -> Facing:
	match state:
		Locomotion.State.DODGING:
			return Facing.KEEP
		Locomotion.State.CLIMBING:
			return Facing.WALL
	return Facing.CAMERA
