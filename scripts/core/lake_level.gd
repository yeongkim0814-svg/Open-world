class_name LakeLevel
extends RefCounted
## 저수호 수위: 수문을 하나 열 때마다 drop만큼 내려간다 (14.6 → 10.7 → 6.8 → 2.9).

static func level(base_y: float, open_count: int, drop := 3.9) -> float:
	return base_y - drop * clampi(open_count, 0, WorldState.SLUICE_COUNT)
