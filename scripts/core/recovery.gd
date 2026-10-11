class_name Recovery
extends RefCounted
## 지역별 회복(0~1) 모델. 노드에 의존하지 않는다.
## 과제 기여는 TASK_CAP에서 멈추고, 탑 무력화만 1.0(복원)에 도달시킨다.

enum Stage { DEPLETED, REGENERATING, RESTORED }

## 탑 외 과제 합계 상한
const TASK_CAP := 0.4
## 이 값 미만이면 고갈
const DEPLETED_BELOW := 0.3
## 지역 가장자리에서 0으로 번지는 거리(m)
const EDGE := 12.0

## id -> { "center": Vector2, "radius": float, "progress": float, "tower": bool }
var _regions: Dictionary = {}
var _preview := -1.0

## 지역을 등록한다. 같은 id면 덮어쓴다.
func add_region(id: StringName, center: Vector2, radius: float) -> void:
	_regions[id] = {"center": center, "radius": radius, "progress": 0.0, "tower": false}

## 과제 진행을 더한다. 음수는 무시, 합계는 TASK_CAP에서 멈춘다.
func add_progress(id: StringName, amount: float) -> void:
	if amount <= 0.0 or not _regions.has(id):
		return
	var r: Dictionary = _regions[id]
	r["progress"] = minf(float(r["progress"]) + amount, TASK_CAP)

## 탑을 무력화한다(값 1.0 고정).
func neutralize_tower(id: StringName) -> void:
	if _regions.has(id):
		_regions[id]["tower"] = true

## 지역의 회복 값. 미리보기가 켜져 있으면 그 값.
func value(id: StringName) -> float:
	if _preview >= 0.0:
		return _preview
	if not _regions.has(id):
		return 0.0
	var r: Dictionary = _regions[id]
	return 1.0 if r["tower"] else float(r["progress"])

func stage(id: StringName) -> Stage:
	var v := value(id)
	if v >= 1.0:
		return Stage.RESTORED
	if v < DEPLETED_BELOW:
		return Stage.DEPLETED
	return Stage.REGENERATING

## -1이면 끔, 0~1이면 모든 지역 값을 덮어쓴다(테스트 씬 슬라이더용).
func set_preview(v: float) -> void:
	_preview = -1.0 if v < 0.0 else clampf(v, 0.0, 1.0)

## 월드 xz 위치의 회복 값. 겹치면 최댓값, 반경 밖 EDGE m 동안 0으로 번진다.
func value_at(p: Vector2) -> float:
	var best := 0.0
	for id in _regions:
		var r: Dictionary = _regions[id]
		var d := p.distance_to(r["center"])
		var rad: float = r["radius"]
		var k := 1.0
		if d > rad:
			k = 1.0 - (d - rad) / EDGE
		if k <= 0.0:
			continue
		best = maxf(best, value(id) * k)
	return best

## rect를 res×res 칸(행 우선)으로 나눠 칸 중심에서 value_at을 굽는다.
func bake(rect: Rect2, res: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(res * res)
	for y in res:
		for x in res:
			var p := rect.position + Vector2(
				(x + 0.5) / res * rect.size.x, (y + 0.5) / res * rect.size.y)
			out[y * res + x] = value_at(p)
	return out

func to_dict() -> Dictionary:
	var regions := {}
	for id in _regions:
		var r: Dictionary = _regions[id]
		var c: Vector2 = r["center"]
		regions[String(id)] = {"x": c.x, "y": c.y, "radius": r["radius"],
			"progress": r["progress"], "tower": r["tower"]}
	return {"regions": regions}

static func from_dict(d: Dictionary) -> Recovery:
	var rec := Recovery.new()
	var regions: Dictionary = d.get("regions", {})
	for key in regions:
		var r: Dictionary = regions[key]
		var id := StringName(key)
		rec.add_region(id, Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))),
			float(r.get("radius", 0.0)))
		rec._regions[id]["progress"] = clampf(float(r.get("progress", 0.0)), 0.0, TASK_CAP)
		rec._regions[id]["tower"] = bool(r.get("tower", false))
	return rec
