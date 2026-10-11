class_name MarkerReader
extends RefCounted
## 표식 지도 → 표식 목록. 이어진(4방향) 같은 색 덩어리의 중심 = 위치.
## 좌표는 HeightField 와 같은 관례: 픽셀 0 → −world/2, 픽셀 size−1 → +world/2, x 오른쪽, z 아래(남쪽).

const MIN_BLOB := 4              ## 이보다 작은 덩어리는 펜 얼룩(경계 혼색)으로 보고 버림 (px)
const MAX_SLUICES := 3
const WARNING_PREFIX := "경고: "
const REQUIRED := ["start", "tower", "lake"]


## 반환: [{kind: String, x: float, z: float, yaw: float}] — 종류 순서(범례 표 순서) → 위에서 아래·왼쪽에서 오른쪽 순서.
## yaw = 마을(없으면 저수호) 쪽을 바라보는 Y 회전 (노드 −Z 가 앞). 대상이 없으면 0.
static func read(img: Image, size := 1024, world := 1024.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layer := MapLegend.load_layer(img, MapLegend.marker_palette(), size)
	if layer.is_empty():
		return out
	var kinds := MapLegend.marker_kinds()
	var seen := PackedByteArray()
	seen.resize(size * size)
	var queue := PackedInt32Array()
	queue.resize(size * size)
	var found: Array[Array] = []       # kind index → [Vector2 ...]
	for _k in kinds.size():
		found.append([])
	for start in size * size:
		var k := layer[start]
		if k < 0 or seen[start] != 0:
			continue
		var head := 0
		var tail := 1
		queue[0] = start
		seen[start] = 1
		var sx := 0.0
		var sy := 0.0
		while head < tail:
			var i := queue[head]
			head += 1
			var x := i % size
			var y := i / size
			sx += x
			sy += y
			if x > 0 and seen[i - 1] == 0 and layer[i - 1] == k:
				seen[i - 1] = 1; queue[tail] = i - 1; tail += 1
			if x < size - 1 and seen[i + 1] == 0 and layer[i + 1] == k:
				seen[i + 1] = 1; queue[tail] = i + 1; tail += 1
			if y > 0 and seen[i - size] == 0 and layer[i - size] == k:
				seen[i - size] = 1; queue[tail] = i - size; tail += 1
			if y < size - 1 and seen[i + size] == 0 and layer[i + size] == k:
				seen[i + size] = 1; queue[tail] = i + size; tail += 1
		if tail < MIN_BLOB:
			continue
		var cx := sx / tail
		var cy := sy / tail
		var denom := float(maxi(size - 1, 1))
		found[k].append(Vector2((cx / denom - 0.5) * world, (cy / denom - 0.5) * world))
	for k in kinds.size():
		for p: Vector2 in found[k]:
			out.append({"kind": kinds[k], "x": p.x, "z": p.y, "yaw": 0.0})
	for m in out:
		var t := _facing_target(out, m)
		if t.is_empty():
			continue
		m["yaw"] = atan2(-(t["x"] - m["x"]), -(t["z"] - m["z"]))
	return out


static func _facing_target(markers: Array, self_m: Dictionary) -> Dictionary:
	for kind in ["village", "lake"]:
		for m in markers:
			if m["kind"] == kind and not is_same(m, self_m) and (m["x"] != self_m["x"] or m["z"] != self_m["z"]):
				return m
	return {}


## 오류·경고 목록 (비어 있으면 통과). 경고는 WARNING_PREFIX 로 시작하고 굽기를 멈추지 않는다.
static func validate(markers: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var counts := {}
	for m in markers:
		counts[m["kind"]] = int(counts.get(m["kind"], 0)) + 1
	for kind in REQUIRED:
		if int(counts.get(kind, 0)) == 0:
			out.append("표식 없음: %s (%s)" % [kind, "#" + MapLegend.MARKERS[kind].to_html(false).to_upper()])
	if int(counts.get("sluice", 0)) > MAX_SLUICES:
		out.append("%s수문 표식 %d개 — 앞의 %d개만 사용합니다" % [WARNING_PREFIX, counts["sluice"], MAX_SLUICES])
	return out


## 수문을 앞의 max_count 개만 남긴 새 목록
static func limit_sluices(markers: Array, max_count := MAX_SLUICES) -> Array:
	var out: Array = []
	var n := 0
	for m in markers:
		if m["kind"] == "sluice":
			n += 1
			if n > max_count:
				continue
		out.append(m)
	return out
