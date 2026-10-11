class_name ChunkMesh
extends RefCounted
## 구역 하나의 지형 메시. HeightField 를 step 간격으로 표본해 정점 공유 인덱스 메시를 만든다.
## 정점은 월드 좌표(구역 노드는 원점에 둔다), UV = 월드 xz (m), 법선 = field.normal_at (부드러운 음영).
## 테두리 한 바퀴에 치마(skirt m 아래로 내린 띠, skirt > 0)를 달아, 다른 LOD 이웃과의 높이 차 틈을 가린다.
## 정점 순서: 격자 n² (행 = z) → 치마 4(n-1) (북서 모서리에서 시계 방향).
## build() 는 한 번에 만들고, Job 은 시간 예산만큼씩 나눠 만든다 (1m 구역은 한 번에 수 ms 가 걸린다).

## step ≤ 이 값이면 법선을 표본 격자의 중앙 차분으로 구한다 (height_at 호출 5분의 1).
## 지도 간격(1024m/1023칸 ≈ 1.001m)과 거의 같아 normal_at 과 0.2% 안팎으로 같다. 더 성긴 구역은 normal_at 그대로.
const FAST_NORMAL_MAX_STEP := 1.0

static var _index_cache := {}     # n → PackedInt32Array (격자 + 치마, 높이와 무관)


## origin = 구역 최소 모서리 xz, size = 한 변 길이(m). 한 번에 끝까지 만든다.
static func build(field: HeightField, origin: Vector2, size: float, step: float, skirt: float) -> ArrayMesh:
	var job := Job.new(field, origin, size, step, skirt)
	job.run(0x7FFFFFFFFFFFFFFF)
	return job.mesh


## build() 가 만드는 삼각형 수 (격자 + 치마).
## 이 구역 가장자리(1m 표본)와 가장 거친 간격(16m) 보간의 최대 높이 차 + 여유 2m (최소 6m).
## 이웃이 어떤 LOD든 경계 틈을 이 깊이의 치마가 가린다 (구운 실제 지도에서 측정한 틈 최대 16.7m).
static func skirt_for(field: HeightField, origin: Vector2, size: float, coarse := 16.0) -> float:
	var worst := 0.0
	var n := int(size)
	for e in 4:
		for k in n + 1:
			var s := float(k)
			var s0: float = floor(s / coarse) * coarse
			var s1 := minf(s0 + coarse, size)
			var t: float = 0.0 if s1 == s0 else (s - s0) / (s1 - s0)
			var p := _edge(origin, size, e, s)
			var a := _edge(origin, size, e, s0)
			var b := _edge(origin, size, e, s1)
			var coarse_h := lerpf(field.height_at(a.x, a.y), field.height_at(b.x, b.y), t)
			worst = maxf(worst, absf(field.height_at(p.x, p.y) - coarse_h))
	return maxf(6.0, worst + 2.0)


static func _edge(o: Vector2, size: float, e: int, s: float) -> Vector2:
	match e:
		0: return o + Vector2(s, 0.0)
		1: return o + Vector2(s, size)
		2: return o + Vector2(0.0, s)
		_: return o + Vector2(size, s)


static func triangle_count(size: float, step: float) -> int:
	var n := int(round(size / step)) + 1
	return 2 * (n - 1) * (n - 1) + 8 * (n - 1)


## 테두리 정점 목록 (북서 → 동 → 남 → 서, 시계 방향): 격자 정점 번호.
static func _ring(n: int) -> PackedInt32Array:
	var ring := PackedInt32Array()
	for ix in n:
		ring.append(ix)                              # 북 (iz = 0)
	for iz in range(1, n):
		ring.append(iz * n + (n - 1))                # 동 (ix = n-1)
	for ix in range(n - 2, -1, -1):
		ring.append((n - 1) * n + ix)                # 남 (iz = n-1)
	for iz in range(n - 2, 0, -1):
		ring.append(iz * n)                          # 서 (ix = 0)
	return ring


## 인덱스(격자 + 치마). 감김은 n 에만 달려 있어 한 번 만들어 캐시한다.
static func _indices(n: int) -> PackedInt32Array:
	if _index_cache.has(n):
		return _index_cache[n]
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6 + 4 * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix          # (0,0)
			var b := a + 1                # (1,0)
			var c := a + n                # (0,1)
			var d := c + 1                # (1,1)
			# Godot 앞면 = 시계 방향(위에서 볼 때): a→b→c, b→d→c
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	# 치마: 구역 중심 기준 바깥을 향한 앞면. 단위 구역(0..n-1 격자) 기하로 감김을 정한다.
	var ring := _ring(n)
	var count := ring.size()
	var base := n * n
	var half := (n - 1) * 0.5
	for r in count:
		var r2 := (r + 1) % count
		var t0 := ring[r]
		var t1 := ring[r2]
		var p0 := Vector3(t0 % n, 0.0, t0 / n)
		var p1 := Vector3(t1 % n, 0.0, t1 / n)
		var mid := (p0 + p1) * 0.5
		var out := Vector3(mid.x - half, 0.0, mid.z - half)
		if absf(out.x) > absf(out.z):
			out = Vector3(signf(out.x), 0.0, 0.0)
		else:
			out = Vector3(0.0, 0.0, signf(out.z))
		var b0 := base + r
		var b1 := base + r2
		# 앞면(시계) = 오른손 외적이 바깥과 반대. 아래 방향 = (0,-1,0)
		var cr := (p1 - p0).cross(Vector3(0.0, -1.0, 0.0))
		if cr.dot(out) < 0.0:
			idx[k] = t0; idx[k + 1] = t1; idx[k + 2] = b0
			idx[k + 3] = t1; idx[k + 4] = b1; idx[k + 5] = b0
		else:
			idx[k] = t0; idx[k + 1] = b0; idx[k + 2] = t1
			idx[k + 3] = t1; idx[k + 4] = b0; idx[k + 5] = b1
		k += 6
	_index_cache[n] = idx
	return idx


## 시간 예산으로 나눠 만드는 작업. run(deadline_usec) 를 완료(true)될 때까지 프레임마다 부른다.
## 한 번 부르면 마감을 넘기더라도 최소 한 행은 진행한다.
class Job extends RefCounted:
	var mesh: ArrayMesh

	var _field: HeightField
	var _origin: Vector2
	var _size: float
	var _step: float
	var _skirt: float
	var _n: int
	var _fast: bool
	var _w: int                         # 패딩 격자 폭 (n + 2)
	var _grid := PackedFloat32Array()   # 패딩 격자 높이 (fast 일 때만)
	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _uvs := PackedVector2Array()
	var _phase := 0                     # 0 격자 높이 → 1 정점 → 2 마무리 → 3 끝
	var _row := 0

	func _init(field: HeightField, origin: Vector2, size: float, step: float, skirt: float) -> void:
		_field = field
		_origin = origin
		_size = size
		_step = step
		_skirt = skirt
		_n = int(round(size / step)) + 1
		_fast = step <= ChunkMesh.FAST_NORMAL_MAX_STEP
		_w = _n + 2
		_verts.resize(_n * _n)
		_normals.resize(_n * _n)
		_uvs.resize(_n * _n)
		if _fast:
			_grid.resize(_w * _w)
		else:
			_phase = 1

	func done() -> bool:
		return _phase >= 3

	## 마감(Time.get_ticks_usec 기준)까지 진행. 끝나면 true.
	func run(deadline_usec: int) -> bool:
		while _phase < 3:
			if _phase == 0:
				_grid_row()
			elif _phase == 1:
				_vertex_row()
			else:
				_finish()
			if _phase < 3 and Time.get_ticks_usec() >= deadline_usec:
				return false
		return true

	func _grid_row() -> void:
		var z := _origin.y + (_row - 1) * _step
		var o := _row * _w
		for c in _w:
			_grid[o + c] = _field.height_at(_origin.x + (c - 1) * _step, z)
		_row += 1
		if _row >= _w:
			_row = 0
			_phase = 1

	func _vertex_row() -> void:
		var n := _n
		var z := _origin.y + _row * _step
		var i := _row * n
		for ix in n:
			var x := _origin.x + ix * _step
			var y: float
			if _fast:
				var g := (_row + 1) * _w + ix + 1
				y = _grid[g]
				_normals[i] = Vector3(_grid[g - 1] - _grid[g + 1], 2.0 * _step, _grid[g - _w] - _grid[g + _w]).normalized()
			else:
				y = _field.height_at(x, z)
				_normals[i] = _field.normal_at(x, z)
			_verts[i] = Vector3(x, y, z)
			_uvs[i] = Vector2(x, z)
			i += 1
		_row += 1
		if _row >= n:
			_phase = 2

	func _finish() -> void:
		var n := _n
		var ring := ChunkMesh._ring(n)
		var base := n * n
		var count := ring.size()
		_verts.resize(base + count)
		_normals.resize(base + count)
		_uvs.resize(base + count)
		for r in count:
			var m := ring[r]
			_verts[base + r] = _verts[m] + Vector3(0.0, -_skirt, 0.0)
			_normals[base + r] = _normals[m]
			_uvs[base + r] = _uvs[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_INDEX] = ChunkMesh._indices(n)
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_grid = PackedFloat32Array()
		_phase = 3
