class_name ChunkedTerrain
extends Node3D
## 1km 지형: 64m 구역마다 거리별 LOD 메시(1 / 4 / 16 m) + 플레이어 주변 3×3 구역 충돌.
## 높이 = <baked_dir>/height.png (RGB8 16비트, −16 ~ 90 m, 1024 m). 설계서 5장.
## 메시는 실행 중 메인 스레드에서 나눠 만든다(웹은 스레드 없음): 프레임당 frame_budget_ms 까지,
## 대기열은 가까운 순 — 카메라 주변 3×3 구역이 항상 먼저. 원하는 간격이 바뀐 구역만 교체한다.
## 1m 초과 구역은 그림자를 드리우지 않는다. 구역 노드는 모두 원점에 있고 메시 정점이 월드 좌표다.

const MAP_SIZE := 1024.0
const MIN_H := -16.0
const MAX_H := 90.0
const SAMPLES := 65               # 충돌 구역 표본 수 (64m + 1, 간격 1m)
const REQUEUE_MOVE := 1.0         # 카메라가 이만큼(m) 움직이면 대기열 다시 계산

## 이 높이보다 낮기만 한 구역은 그리지 않는다 (바다 불투명: 깊이 약 1m부터)
const SKIP_BELOW := -2.0

@export var baked_dir := ""
@export var material: Material:
	set(value):
		material = value
		for inst: MeshInstance3D in _chunks.values():
			inst.material_override = value
@export var frame_budget_ms := 4.0

var field: HeightField
## 구역 키 → 지금까지 만든 것 중 가장 느린 생성 시간 (격자 간격별, ms) — 측정용.
var max_build_ms_by_step := {}

var _chunks := {}                 # Vector2i → MeshInstance3D
var _steps := {}                  # Vector2i → float (지금 걸려 있는 간격)
var _tris := {}                   # Vector2i → int
var _queue: Array = []            # [priority, key, step] — 우선순위 내림차순 (pop_back = 가장 급함)
var _last_cam := Vector2(INF, INF)
var _last_build_ms := 0.0
var _focus: Node3D
var _skip := {}                   # Vector2i → true: 깊은 바다 아래라 그리지 않는 구역 (충돌은 따로 만든다)
var _body: StaticBody3D
var _shapes := {}                 # Vector2i → CollisionShape3D
var _shape_queue: Array = []      # [dist, key] — 내림차순
var _shape_job := {}              # 만드는 중인 충돌 구역: key, data, row, ox, oz
var _focus_chunk := Vector2i(-9999, -9999)
var _job: ChunkMesh.Job           # 만드는 중인 메시
var _job_key := Vector2i.ZERO
var _job_step := 1.0
var _job_usec := 0


func _ready() -> void:
	if field == null and baked_dir != "":
		load_map()


## <baked_dir>/height.png 를 읽어 지형을 준비한다.
func load_map() -> void:
	var path := baked_dir.path_join("height.png")
	# 구운 PNG 는 무손실 Image 리소스로 가져온다 (내보낸 빌드·웹에서도 동작, 16비트 높이 보존).
	var res = load(path) if ResourceLoader.exists(path) else null
	var img: Image = res if res is Image else (res.get_image() if res is Texture2D else Image.load_from_file(path))
	if img == null or img.is_empty():
		push_error("ChunkedTerrain: 높이 지도를 읽을 수 없음: %s" % path)
		return
	use_field(HeightField.new(img, MAP_SIZE, MIN_H, MAX_H))


## 이미 만든 HeightField 로 시작한다 (테스트·도구용). 기존 구역은 모두 지운다.
func use_field(f: HeightField) -> void:
	_clear()
	field = f
	_skip = _underwater_chunks(f)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)


## 충돌(3×3)을 따라갈 대상. 없으면 카메라.
func set_focus(node: Node3D) -> void:
	_focus = node


func _process(_delta: float) -> void:
	if field == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	step(cam.global_position, frame_budget_ms)


## 한 프레임 분량 작업: 충돌 갱신 → 메시 대기열 처리, 마감 = 시작 + budget_ms.
## 구역 하나가 예산보다 오래 걸리면 여러 프레임에 나눠 만든다. 각 단계는 최소 한 조각은 반드시 진행한다.
func step(cam_pos: Vector3, budget_ms: float) -> void:
	if field == null:
		return
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var focus_pos := cam_pos
	if _focus != null and is_instance_valid(_focus):
		focus_pos = _focus.global_position
	_update_collision(Vector2(focus_pos.x, focus_pos.z), deadline)
	_update_meshes(Vector2(cam_pos.x, cam_pos.z), deadline)


func stats() -> Dictionary:
	var tris := 0
	for k: Vector2i in _tris:
		tris += _tris[k]
	return {"chunks": _chunks.size(), "pending": _queue.size() + (1 if _job != null else 0), "last_build_ms": _last_build_ms, "triangles": tris}


## 충돌 3×3 이 모두 준비됐는가 (플레이어 낙하 방지용으로 시작할 때 기다린다).
func collision_ready() -> bool:
	return _body != null and _shape_job.is_empty() and _shape_queue.is_empty() and not _shapes.is_empty()


func has_chunk(key: Vector2i) -> bool:
	return _chunks.has(key)


func chunk_node(key: Vector2i) -> MeshInstance3D:
	return _chunks.get(key)


func chunk_step(key: Vector2i) -> float:
	return _steps.get(key, 0.0)


func collision_shapes() -> Dictionary:
	return _shapes


# --- 메시 -------------------------------------------------------------------

func _update_meshes(cam_xz: Vector2, deadline: int) -> void:
	if _last_cam.x == INF or cam_xz.distance_to(_last_cam) > REQUEUE_MOVE:
		_last_cam = cam_xz
		_requeue(cam_xz)
	var first := true
	while true:
		if _job == null:
			_start_next_job()
			if _job == null:
				return
		if not first and Time.get_ticks_usec() >= deadline:
			return
		first = false
		var t := Time.get_ticks_usec()
		var finished := _job.run(deadline)
		_job_usec += Time.get_ticks_usec() - t
		if finished:
			_install(_job_key, _job_step, _job.mesh)
			_job = null


func _requeue(cam_xz: Vector2) -> void:
	var world := field.world_size
	var want := TerrainLod.wanted(cam_xz, world)
	var cam_chunk := TerrainLod.chunk_of(cam_xz, world)
	_queue.clear()
	for key: Vector2i in want:
		if _skip.has(key):
			continue
		var s: float = want[key]
		if _steps.get(key, 0.0) == s:
			continue
		var d := cam_xz.distance_to(TerrainLod.chunk_center(key, world))
		var ring := absi(key.x - cam_chunk.x) <= 1 and absi(key.y - cam_chunk.y) <= 1
		_queue.append([d if ring else 1.0e6 + d, key, s])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])


func _start_next_job() -> void:
	while not _queue.is_empty():
		var q: Array = _queue.pop_back()
		var key: Vector2i = q[1]
		var step_m: float = q[2]
		if _steps.get(key, 0.0) == step_m:
			continue
		var world := field.world_size
		var origin := Vector2(-world * 0.5 + key.x * TerrainLod.CHUNK, -world * 0.5 + key.y * TerrainLod.CHUNK)
		_job = ChunkMesh.Job.new(field, origin, TerrainLod.CHUNK, step_m, maxf(6.0, 2.0 * step_m))   # 1m 구역도 6m: 가파른 곳의 4m 이웃 보간 오차까지 가림
		_job_key = key
		_job_step = step_m
		_job_usec = 0
		return


func _install(key: Vector2i, step_m: float, mesh: ArrayMesh) -> void:
	var inst: MeshInstance3D = _chunks.get(key)
	if inst == null:
		inst = MeshInstance3D.new()
		inst.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(inst)
		_chunks[key] = inst
	inst.mesh = mesh
	inst.material_override = material
	inst.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if step_m <= 1.0
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_steps[key] = step_m
	_tris[key] = ChunkMesh.triangle_count(TerrainLod.CHUNK, step_m)
	_last_build_ms = _job_usec / 1000.0
	max_build_ms_by_step[step_m] = maxf(max_build_ms_by_step.get(step_m, 0.0), _last_build_ms)


# --- 충돌 -------------------------------------------------------------------

func _update_collision(focus_xz: Vector2, deadline: int) -> void:
	var world := field.world_size
	var n := TerrainLod.chunks_per_side(world)
	var c := TerrainLod.chunk_of(focus_xz, world)
	if c != _focus_chunk:
		_focus_chunk = c
		_requeue_shapes(focus_xz, n, world)
	var first := true
	while true:
		if _shape_job.is_empty():
			_start_next_shape()
			if _shape_job.is_empty():
				return
		if not first and Time.get_ticks_usec() >= deadline:
			return
		first = false
		_shape_rows(deadline)


func _requeue_shapes(focus_xz: Vector2, n: int, world: float) -> void:
	var c := _focus_chunk
	var desired := {}
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := Vector2i(c.x + dx, c.y + dz)
			if k.x >= 0 and k.y >= 0 and k.x < n and k.y < n:
				desired[k] = true
	for k: Vector2i in _shapes.keys():
		if not desired.has(k):
			_body.remove_child(_shapes[k])
			_shapes[k].free()
			_shapes.erase(k)
	if not _shape_job.is_empty() and not desired.has(_shape_job["key"]):
		_shape_job = {}
	_shape_queue.clear()
	for k: Vector2i in desired:
		if not _shapes.has(k) and (_shape_job.is_empty() or _shape_job["key"] != k):
			_shape_queue.append([focus_xz.distance_to(TerrainLod.chunk_center(k, world)), k])
	_shape_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])


func _start_next_shape() -> void:
	if _shape_queue.is_empty():
		return
	var key: Vector2i = _shape_queue.pop_back()[1]
	var world := field.world_size
	var data := PackedFloat32Array()
	data.resize(SAMPLES * SAMPLES)
	_shape_job = {
		"key": key, "data": data, "row": 0,
		"ox": -world * 0.5 + key.x * TerrainLod.CHUNK,
		"oz": -world * 0.5 + key.y * TerrainLod.CHUNK,
	}


## 충돌 구역 하나의 1m 표본을 행 단위로 채운다 (마감 전까지, 최소 한 행).
func _shape_rows(deadline: int) -> void:
	var data: PackedFloat32Array = _shape_job["data"]
	var row: int = _shape_job["row"]
	var ox: float = _shape_job["ox"]
	var oz: float = _shape_job["oz"]
	while row < SAMPLES:
		var i := row * SAMPLES
		for ix in SAMPLES:
			data[i + ix] = field.height_at(ox + ix, oz + row)
		row += 1
		if Time.get_ticks_usec() >= deadline:
			break
	_shape_job["data"] = data
	_shape_job["row"] = row
	if row >= SAMPLES:
		_finish_shape(_shape_job["key"], data, ox, oz)
		_shape_job = {}


## HeightMapShape3D: 노드 = 구역 중심, 표본 i 의 월드 x = 구역 원점 x + i (간격 1m).
func _finish_shape(key: Vector2i, data: PackedFloat32Array, ox: float, oz: float) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = SAMPLES
	shape.map_depth = SAMPLES
	shape.map_data = data
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(ox + TerrainLod.CHUNK * 0.5, 0.0, oz + TerrainLod.CHUNK * 0.5)
	_body.add_child(col)
	_shapes[key] = col


func _clear() -> void:
	for inst: MeshInstance3D in _chunks.values():
		remove_child(inst)
		inst.free()
	_chunks.clear()
	_steps.clear()
	_tris.clear()
	_queue.clear()
	_shape_queue.clear()
	_shape_job = {}
	_shapes.clear()
	_job = null
	_focus_chunk = Vector2i(-9999, -9999)
	_last_cam = Vector2(INF, INF)
	if _body != null:
		remove_child(_body)
		_body.free()
		_body = null


## 가장 높은 곳도 SKIP_BELOW 아래인 구역 = 불투명한 깊은 바다에 완전히 가려짐 → 메시 생략 (8m 간격 표본).
static func _underwater_chunks(f: HeightField) -> Dictionary:
	var out := {}
	var n := TerrainLod.chunks_per_side(f.world_size)
	var half := f.world_size * 0.5
	for iz in n:
		for ix in n:
			var top := -INF
			for sz in 9:
				for sx in 9:
					top = maxf(top, f.height_at(-half + ix * TerrainLod.CHUNK + sx * 8.0, -half + iz * TerrainLod.CHUNK + sz * 8.0))
			if top < SKIP_BELOW:
				out[Vector2i(ix, iz)] = true
	return out
