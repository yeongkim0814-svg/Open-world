class_name VegetationField
extends Node3D
## 식생·바위 스트리밍: 층(풀·덤불·나무·바위)마다 카메라 주변 블록을 계산하고 지운다.
## 블록 = 배치 계산 단위 (mesh id 별 MultiMesh 버퍼 + 충돌 자료). 그리기는 블록보다 큰 칸(cell) 단위로 모은다:
## 그리기 묶음(SETS)마다 칸 하나 × 메시 종류 하나 = MultiMeshInstance3D 하나 → 그리기 호출 = 보이는 칸 × 메시 종류.
## 나무 LOD 는 블록 중심 거리로 고른다 (가까이 LOD0 / 멀리 LOD1, 여유 HYST). 그림자는 근처 나무 LOD1 메시만 그림자 전용으로.
## 전부 메인 스레드 (배치 캐시가 스레드 안전하지 않음) — step(budget_ms) 이 예산 안에서 일을 한 단위씩 한다:
## 단위 = 블록 배치 계산 1개 / 칸 MultiMesh 다시 만들기 1개 / 충돌 블록 1개. 다음 단위의 예상 비용이 남은 예산을 넘으면 멈춘다.

const L := VegContext.Layer
const COLLIDE_R := 48.0          ## 이 거리 안의 나무·바위 블록만 충돌
const COL_ITEM_R := COLLIDE_R + 16.0   ## 충돌 블록 안에서도 이 거리 안 개체만 충돌 모양을 만든다
const COL_REBUILD_MOVE := 12.0   ## 충돌 만든 뒤 중심이 이만큼 움직이면 다시 만든다
const REFRESH_MOVE := 2.0        ## 중심이 이만큼 움직이면 대기열 갱신
const DIAG := 0.7072             ## 블록 대각 / 2 비율
const HYST := 8.0                ## 해제·LOD·그림자 전환 여유 (반경 가장자리에서 흔들려도 다시 만들지 않게)
const ROCK_COLLIDE_MIN := 1.2
const TREE_LOD0_END := 220.0     ## 블록 중심이 이 안이면 나무 LOD0 (그리기 호출 예산: 260 → 220)
const ROCK_SMALL_END := 150.0    ## 블록 중심이 이 밖이면 작은 바위(크기 < ROCK_COLLIDE_MIN)는 그리지 않는다
const SMALL := "|s"              ## 작은 바위 버퍼 키 꼬리
const SHADOW_DIST := 80.0        ## 해 그림자 거리 (island_1km directional_shadow_max_distance 와 맞춤)
const STRIDE := 13               ## 충돌 자료: 변환 12 실수 + 크기
const FLOATS := 20               ## MultiMesh 인스턴스: 변환 12 + 색 4 + 사용자 4
const CYL_BUCKET := 0.05         ## 줄기 원기둥 모양 공유: 크기를 이 단위로 반올림
const FRAME_BUDGET_MS := 2.5     ## _process 의 step 예산 — 예상 비용 오차·마지막 줄 넘침을 감안해 설계서 한도 3 ms 보다 낮게
const DIRTY_WAIT := 6            ## 칸 다시 만들기를 블록 계산 뒤로 미루는 최대 step 수 (여러 블록을 모아 한 번에)

## 층별 보이는 거리 (m) = 블록 스트리밍 반경 기본값
const END := {L.GRASS: 55.0, L.SHRUB: 160.0, L.TREE: 700.0, L.ROCK: 500.0}

## 블록 표시(flags)
const F_NEAR := 1     ## 나무 LOD0 거리 안
const F_SHADOW := 2   ## 그림자 거리 안

## 그리기 묶음: 층, 칸 크기(m, 블록 크기의 배수), LOD(1 = 형태별 메시 하나로 묶음), 그림자 설정,
## 대상 블록 = (flags & mask) == want, small = 작은 바위 포함
const OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
const SHADOW_ONLY := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
const SETS := [
	{"layer": L.GRASS, "cell": 128.0, "lod": 0, "cast": OFF, "mask": 0, "want": 0, "small": true},
	{"layer": L.SHRUB, "cell": 256.0, "lod": 0, "cast": OFF, "mask": 0, "want": 0, "small": true},
	{"layer": L.TREE, "cell": 256.0, "lod": 0, "cast": OFF, "mask": F_NEAR, "want": F_NEAR, "small": true},
	{"layer": L.TREE, "cell": 1024.0, "lod": 1, "cast": OFF, "mask": F_NEAR, "want": 0, "small": true},
	{"layer": L.TREE, "cell": 2048.0, "lod": 1, "cast": SHADOW_ONLY, "mask": F_SHADOW, "want": F_SHADOW, "small": true},
	{"layer": L.ROCK, "cell": 256.0, "lod": 0, "cast": OFF, "mask": F_NEAR, "want": F_NEAR, "small": true},
	{"layer": L.ROCK, "cell": 512.0, "lod": 1, "cast": OFF, "mask": F_NEAR, "want": 0, "small": false},
	{"layer": L.ROCK, "cell": 2048.0, "lod": 1, "cast": SHADOW_ONLY, "mask": F_SHADOW, "want": F_SHADOW, "small": false},
]

## 일 종류
enum Job { COLLISION, BLOCK, CELL }

var _ctx: VegContext
var _cat: VegCatalog
var _seed := 1337
var _reach := END.duplicate()
var _blocks := {}      ## 층 → {Vector2i → {"bufs","count","cdata","body","ccenter","flags"}}
var _cells := []       ## SETS 순서 → {Vector2i → {"node": Node3D, "count": int}}
var _dirty := {}       ## "묶음:x:y" → [묶음, 칸 키, 처음 더러워진 tick]
var _pending: Array = []   ## 내림차순 정렬 [거리, 일, 층, 키] — 끝에서 꺼낸다
var _queued := {}
var _center := Vector2.ZERO
var _last_refresh := Vector2(1e12, 1e12)
var _water: Array = []
var _prev_water := Callable()
var _instances := 0
var _tick := 0
var _cost := {}        ## 일 종류·층 → 최근 비용 (ms, 지수 평균) — 예산 판단용
var _cost_max := {}    ## 같은 키의 최대 비용 (측정 프로브용)
var _cyl := {}         ## "id:크기구간" → CylinderShape3D
var _job: VegPlacement.Job   ## 계산 중인 블록 (없으면 null)
var _job_key := Vector2i.ZERO
## 물 노드 목록 공급자 (기본: 그룹 "water"). 트리 밖 시험용으로 바꿔 끼울 수 있다.
var water_source := Callable()


func setup(ctx: VegContext, catalog: VegCatalog, world_seed := 1337) -> void:
	_clear()
	_ctx = ctx
	_cat = catalog
	_seed = world_seed
	for layer in END:
		_blocks[layer] = {}
	_cells = []
	for i in SETS.size():
		_cells.append({})
	# 기존 물 판정(있으면)과 합쳐 블록 만들 때마다 갱신되는 물 노드 목록을 본다.
	# 이미 이 필드의 판정이 끼워져 있으면 (setup 두 번) 다시 감싸지 않는다 — 자기 자신을 부르는 순환 방지.
	var own := Callable(self, "_water_level")
	var cur := ctx.get_water()
	if cur != own:
		_prev_water = cur
	ctx.set_water(own)


## 테스트용: 층별 스트리밍 반경을 바꾼다 (0 = 그 층 안 만듦)
func set_reach(layer: int, r: float) -> void:
	_reach[layer] = r
	_last_refresh = Vector2(1e12, 1e12)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _ctx == null:
		return
	update_center(cam.global_position)
	step(FRAME_BUDGET_MS)


func busy() -> bool:
	return _job != null or not _pending.is_empty() or not _dirty.is_empty()


func block_keys(layer: int) -> Array:
	return (_blocks[layer] as Dictionary).keys()


## 충돌체를 가진 블록 [[층, 키], ...] (테스트용)
func collision_block_keys() -> Array:
	var out: Array = []
	for layer in [L.TREE, L.ROCK]:
		for k in _blocks[layer]:
			if _blocks[layer][k]["body"] != null:
				out.append([layer, k])
	return out


func stats() -> Dictionary:
	var n := 0
	for layer in _blocks:
		n += (_blocks[layer] as Dictionary).size()
	var mmi := 0
	for cells in _cells:
		for ck in cells:
			mmi += (cells[ck]["node"] as Node).get_child_count()
	return {"blocks": n, "instances": _instances, "collision_blocks": collision_block_keys().size(),
			"pending": _pending.size(), "dirty": _dirty.size(), "multimeshes": mmi}


func update_center(p: Vector3) -> void:
	var c := Vector2(p.x, p.z)
	_center = c
	if c.distance_to(_last_refresh) < REFRESH_MOVE:
		return
	_last_refresh = c
	_refresh()


## 일을 한 단위씩: 가까운 블록 계산·충돌 먼저, 더러운 칸은 블록이 모인 뒤(대기열이 비었거나 DIRTY_WAIT 지남) 다시 만든다.
## 블록 배치 계산은 격자 줄 단위로 나눠 여러 step 에 걸쳐 한다 (VegPlacement.Job).
## 예산을 다 쓰거나 다음 단위(줄)의 예상 비용이 남은 예산보다 크면 멈춘다. 일이 있으면 예산 0 이어도 한 단위는 한다 (진행 보장).
func step(budget_ms := 3.0) -> void:
	_tick += 1
	var t0 := Time.get_ticks_usec()
	var first := true
	while busy():
		var used := (Time.get_ticks_usec() - t0) / 1000.0
		if _job != null:
			var rkey := "row%d" % _job.layer
			if not first and used + float(_cost.get(rkey, 0.0)) > budget_ms:
				break
			first = false
			var ts := Time.get_ticks_usec()
			var fin := VegPlacement.run(_job, 1)
			_note_cost(rkey, ts)
			if fin:
				_finish_block()
			continue
		var cell := _next_dirty()
		if not cell.is_empty():
			var ckey := "cell%d" % cell[0]
			if not first and used + float(_cost.get(ckey, 0.0)) > budget_ms:
				break
			first = false
			var ts := Time.get_ticks_usec()
			_dirty.erase(_dkey(cell[0], cell[1]))
			_build_cell(cell[0], cell[1])
			_note_cost(ckey, ts)
			continue
		var e: Array = _pending.back()
		if e[1] == Job.COLLISION and not first and used + float(_cost.get("col", 0.0)) > budget_ms:
			break
		_pending.pop_back()
		_queued.erase(_qkey(e[1], e[2], e[3]))
		if e[1] == Job.COLLISION:
			first = false
			var ts := Time.get_ticks_usec()
			_build_collision(e[2], e[3])
			_note_cost("col", ts)
		else:
			_start_block(e[2], e[3])   # 시작만 (싸다) — 줄 계산은 다음 바퀴에서


func _note_cost(key: String, since_usec: int) -> void:
	var ms := (Time.get_ticks_usec() - since_usec) / 1000.0
	_cost[key] = ms if not _cost.has(key) else lerpf(_cost[key], ms, 0.3)
	_cost_max[key] = maxf(float(_cost_max.get(key, 0.0)), ms)


# ---------- 대기열 ----------

func _qkey(kind: int, layer: int, k: Vector2i) -> String:
	return "%d:%d:%d:%d" % [kind, layer, k.x, k.y]


func _dkey(si: int, ck: Vector2i) -> String:
	return "%d:%d:%d" % [si, ck.x, ck.y]


func _block_center(layer: int, k: Vector2i) -> Vector2:
	var s: float = VegPlacement.BLOCK[layer]
	return Vector2((k.x + 0.5) * s, (k.y + 0.5) * s)


func _wanted(layer: int, k: Vector2i, extra := 0.0) -> bool:
	var s: float = VegPlacement.BLOCK[layer]
	var r: float = _reach[layer]
	if r <= 0.0:
		return false
	return _block_center(layer, k).distance_to(_center) <= r + s * DIAG + extra


func _col_wanted(layer: int, k: Vector2i) -> bool:
	var s: float = VegPlacement.BLOCK[layer]
	return (layer == L.TREE or layer == L.ROCK) and _block_center(layer, k).distance_to(_center) <= COLLIDE_R + s * DIAG


## 거리 표시: 켜진 것은 경계 + HYST 를 넘어야 꺼진다
func _flags(layer: int, k: Vector2i, old: int) -> int:
	var d := _block_center(layer, k).distance_to(_center)
	var s: float = VegPlacement.BLOCK[layer]
	var f := 0
	if layer == L.TREE or layer == L.ROCK:
		var lim: float = (TREE_LOD0_END if layer == L.TREE else ROCK_SMALL_END) + (HYST if old & F_NEAR else 0.0)
		if d <= lim:
			f |= F_NEAR
	if layer == L.TREE or layer == L.ROCK:
		var lim := SHADOW_DIST + s * DIAG + (HYST if old & F_SHADOW else 0.0)
		if d <= lim:
			f |= F_SHADOW
	return f


func _refresh() -> void:
	_pending.clear()
	_queued.clear()
	for layer in _blocks:
		var have: Dictionary = _blocks[layer]
		var s: float = VegPlacement.BLOCK[layer]
		var r: float = _reach[layer]
		for k in have.keys():
			# 범위 + HYST 를 벗어난 블록 지움
			if not _wanted(layer, k, HYST):
				_free_block(layer, k)
				continue
			var b: Dictionary = have[k]
			var f := _flags(layer, k, b["flags"])
			if f != b["flags"]:
				_mark_block(layer, k, b)   # 옛 표시의 칸
				b["flags"] = f
				_mark_block(layer, k, b)   # 새 표시의 칸
			# 충돌 범위를 벗어난 충돌체 지움
			if not _col_wanted(layer, k):
				_drop_body(b)
		if r <= 0.0:
			continue
		var span := ceili((r + s * DIAG) / s) + 1
		var cc := Vector2i(floori(_center.x / s), floori(_center.y / s))
		for dz in range(-span, span + 1):
			for dx in range(-span, span + 1):
				var k := cc + Vector2i(dx, dz)
				if not _wanted(layer, k):
					continue
				var d := _block_center(layer, k).distance_to(_center)
				if not have.has(k):
					_push(Job.BLOCK, layer, k, d)
				elif _col_wanted(layer, k):
					var b: Dictionary = have[k]
					if b["body"] == null or (b["ccenter"] as Vector2).distance_to(_center) > COL_REBUILD_MOVE:
						_push(Job.COLLISION, layer, k, d - 1000.0)   # 충돌을 먼저
	_pending.sort_custom(func(a, b): return a[0] > b[0])


func _push(kind: int, layer: int, k: Vector2i, d: float) -> void:
	var key := _qkey(kind, layer, k)
	if _queued.has(key):
		return
	_queued[key] = true
	_pending.append([d, kind, layer, k])


func _free_block(layer: int, k: Vector2i) -> void:
	var b: Dictionary = _blocks[layer][k]
	_instances -= int(b["count"])
	_drop_body(b)
	_mark_block(layer, k, b)
	_blocks[layer].erase(k)


func _drop_body(b: Dictionary) -> void:
	if b["body"] != null:
		(b["body"] as Node).queue_free()
		b["body"] = null


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_blocks = {}
	_cells = []
	_dirty.clear()
	_job = null
	_pending.clear()
	_queued.clear()
	_instances = 0
	_last_refresh = Vector2(1e12, 1e12)


# ---------- 물 ----------

func _water_level(x: float, z: float) -> float:
	var level := -INF
	for w in _water:
		var s: float = w.surface_y()
		if w.depth_at(Vector3(x, s - 0.001, z)) > 0.0:
			level = maxf(level, s)
	if _prev_water.is_valid():
		level = maxf(level, float(_prev_water.call(x, z)))
	return level


# ---------- 블록 (배치 계산) ----------

func _start_block(layer: int, k: Vector2i) -> void:
	if _blocks[layer].has(k) or not _wanted(layer, k):
		return
	# 호수 수위 변화 반영: 블록마다 다시 읽는다
	if water_source.is_valid():
		_water = water_source.call()
	elif is_inside_tree():
		_water = get_tree().get_nodes_in_group("water")
	_job = VegPlacement.begin(_ctx, layer, k, _seed)
	_job_key = k


func _finish_block() -> void:
	var layer := _job.layer
	var k := _job_key
	var items := _job.out
	_job = null
	if _blocks[layer].has(k) or not _wanted(layer, k, HYST):
		return   # 계산하는 동안 멀어졌다
	var b := {"bufs": _buffers(items), "count": items.size(), "cdata": _collision_data(layer, items),
			"body": null, "ccenter": Vector2.ZERO, "flags": _flags(layer, k, 0)}
	_blocks[layer][k] = b
	_instances += items.size()
	_mark_block(layer, k, b)
	if _col_wanted(layer, k):
		_push(Job.COLLISION, layer, k, -1000.0)


## 버퍼 키 = mesh id (작은 바위는 + SMALL — 먼 묶음에서 뺀다)
static func _buf_key(it: Dictionary) -> String:
	var id: String = it["mesh"]
	if id.begins_with("rock_") and float(it["size"]) < ROCK_COLLIDE_MIN:
		return id + SMALL
	return id


## mesh id → 인스턴스 버퍼 (변환 12 + 색 4 + 사용자 4)
func _buffers(items: Array) -> Dictionary:
	var counts := {}
	for it in items:
		var key := _buf_key(it)
		counts[key] = int(counts.get(key, 0)) + 1
	var bufs := {}
	var at := {}
	for id in counts:
		var buf := PackedFloat32Array()
		buf.resize(int(counts[id]) * FLOATS)
		bufs[id] = buf
		at[id] = 0
	for it in items:
		var id := _buf_key(it)
		var buf: PackedFloat32Array = bufs[id]
		var i: int = at[id]
		var xf: Transform3D = it["xform"]
		var bs := xf.basis
		var o := xf.origin
		var c: Color = it["custom"]
		buf[i] = bs.x.x; buf[i + 1] = bs.y.x; buf[i + 2] = bs.z.x; buf[i + 3] = o.x
		buf[i + 4] = bs.x.y; buf[i + 5] = bs.y.y; buf[i + 6] = bs.z.y; buf[i + 7] = o.y
		buf[i + 8] = bs.x.z; buf[i + 9] = bs.y.z; buf[i + 10] = bs.z.z; buf[i + 11] = o.z
		buf[i + 12] = 1.0; buf[i + 13] = 1.0; buf[i + 14] = 1.0; buf[i + 15] = 1.0   # 흰색 (정점색이 어두워지지 않게)
		buf[i + 16] = c.r; buf[i + 17] = c.g; buf[i + 18] = c.b; buf[i + 19] = c.a
		at[id] = i + FLOATS
		bufs[id] = buf   # Packed 배열은 값 복사 — 다시 넣는다
	return bufs


# ---------- 칸 (그리기 묶음) ----------

func _cell_key(si: int, layer: int, k: Vector2i) -> Vector2i:
	var c := _block_center(layer, k)
	var cs: float = SETS[si]["cell"]
	return Vector2i(floori(c.x / cs), floori(c.y / cs))


func _in_set(si: int, b: Dictionary) -> bool:
	var st: Dictionary = SETS[si]
	return (int(b["flags"]) & int(st["mask"])) == int(st["want"])


## 블록이 속한 (현재 표시 기준) 모든 묶음의 칸을 더럽힌다
func _mark_block(layer: int, k: Vector2i, b: Dictionary) -> void:
	if int(b["count"]) == 0:
		return
	for si in SETS.size():
		if SETS[si]["layer"] != layer or not _in_set(si, b):
			continue
		var ck := _cell_key(si, layer, k)
		var dk := _dkey(si, ck)
		if not _dirty.has(dk):
			_dirty[dk] = [si, ck, _tick]


## 다시 만들 칸: 대기열이 비었거나 DIRTY_WAIT 이상 기다린 칸 중 가장 가까운 것 (없으면 [])
func _next_dirty() -> Array:
	var best: Array = []
	var bd := INF
	var drain := _pending.is_empty()
	for dk in _dirty:
		var e: Array = _dirty[dk]
		if not drain and _tick - int(e[2]) < DIRTY_WAIT:
			continue
		var cs: float = SETS[e[0]]["cell"]
		var d := Vector2((e[1].x + 0.5) * cs, (e[1].y + 0.5) * cs).distance_to(_center)
		if d < bd:
			bd = d
			best = e
	return best


## 그릴 메시 id: LOD1 묶음은 형태별 메시 하나 (변형 _0) — 멀리서는 변형 차이가 안 보이고 그리기 호출이 줄어든다.
## 바위에는 LOD1 메시가 없어 LOD0 변형 _0 을 쓴다 (그림자 전용·먼 큰 바위).
## 풀(덤불 층 꽃무리 포함)은 칸마다 변형 하나: 칸 좌표 홀짝으로 _0/_1 — 칸 안 그리기 호출 절반, 이웃 칸끼리는 다르다.
static func _render_key(id: String, lod: int, ck: Vector2i) -> String:
	id = id.trim_suffix(SMALL)
	var stem := id.substr(0, id.rfind("_"))
	if lod >= 1:
		return stem + "_0"
	if id.begins_with("grass_"):
		return "%s_%d" % [stem, posmod(ck.x + ck.y, VegPlacement.GRASS_VARIANTS)]
	return id


## 칸 하나를 처음부터 다시 만든다: 칸 안 블록 중 이 묶음 대상인 것의 버퍼를 메시별로 이어 붙임
func _build_cell(si: int, ck: Vector2i) -> void:
	var st: Dictionary = SETS[si]
	var layer: int = st["layer"]
	var lod: int = st["lod"]
	var cs: float = st["cell"]
	var bs: float = VegPlacement.BLOCK[layer]
	var per := int(cs / bs)
	var merged := {}
	var have: Dictionary = _blocks[layer]
	for j in per:
		for i in per:
			var k := Vector2i(ck.x * per + i, ck.y * per + j)
			if not have.has(k):
				continue
			var b: Dictionary = have[k]
			if not _in_set(si, b):
				continue
			var bufs: Dictionary = b["bufs"]
			for id in bufs:
				if not st["small"] and id.ends_with(SMALL):
					continue
				var rk := _render_key(id, lod, ck)
				if merged.has(rk):
					var m: PackedFloat32Array = merged[rk]
					m.append_array(bufs[id])
					merged[rk] = m
				else:
					merged[rk] = (bufs[id] as PackedFloat32Array).duplicate()
	var cells: Dictionary = _cells[si]
	var old: Dictionary = cells.get(ck, {})
	if not old.is_empty():
		(old["node"] as Node).queue_free()
		cells.erase(ck)
	if merged.is_empty():
		return
	var node := Node3D.new()
	add_child(node)
	for rk in merged:
		var buf: PackedFloat32Array = merged[rk]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _cat.mesh(rk, lod)   # 바위 lod 1 → 카탈로그가 LOD0 을 준다
		mm.instance_count = buf.size() / FLOATS
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = st["cast"]
		node.add_child(mmi)
	cells[ck] = {"node": node}


# ---------- 충돌 ----------

## 충돌 후보만 압축 보관 (개체 전체를 들고 있지 않는다): 나무 전부, 바위는 size ≥ 1.2
func _collision_data(layer: int, items: Array) -> Dictionary:
	if layer != L.TREE and layer != L.ROCK:
		return {}
	var ids := PackedStringArray()
	var f := PackedFloat32Array()
	for it in items:
		if layer == L.ROCK and float(it["size"]) < ROCK_COLLIDE_MIN:
			continue
		ids.append(it["mesh"])
		var xf: Transform3D = it["xform"]
		var bs := xf.basis
		var o := xf.origin
		f.append_array([bs.x.x, bs.y.x, bs.z.x, o.x, bs.x.y, bs.y.y, bs.z.y, o.y, bs.x.z, bs.y.z, bs.z.z, o.z, float(it["size"])])
	return {"ids": ids, "f": f} if ids.size() > 0 else {}


func _build_collision(layer: int, k: Vector2i) -> void:
	if not _blocks[layer].has(k) or not _col_wanted(layer, k):
		return
	var b: Dictionary = _blocks[layer][k]
	_drop_body(b)
	_make_body(layer, b)


## 줄기 원기둥: (id, 크기 구간) 마다 한 모양을 공유한다
func _trunk_shape(id: String, sz: float) -> CylinderShape3D:
	var q := roundi(sz / CYL_BUCKET)
	var key := "%s:%d" % [id, q]
	if _cyl.has(key):
		return _cyl[key]
	var tr := _cat.trunk(id)
	var qs := q * CYL_BUCKET
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(tr.x * qs, 0.05)
	cyl.height = maxf(tr.y * qs, 0.1)
	_cyl[key] = cyl
	return cyl


func _make_body(layer: int, b: Dictionary) -> void:
	var body := StaticBody3D.new()
	b["ccenter"] = _center
	var cd: Dictionary = b["cdata"]
	if not cd.is_empty():
		var ids: PackedStringArray = cd["ids"]
		var f: PackedFloat32Array = cd["f"]
		for i in ids.size():
			var o := i * STRIDE
			var pos := Vector3(f[o + 3], f[o + 7], f[o + 11])
			if Vector2(pos.x, pos.z).distance_to(_center) > COL_ITEM_R:
				continue
			var cs := CollisionShape3D.new()
			var sz := f[o + 12]
			if layer == L.TREE:
				var cyl := _trunk_shape(ids[i], sz)
				cs.shape = cyl
				cs.position = pos + Vector3.UP * cyl.height * 0.5
			else:
				cs.shape = _cat.rock_shape(ids[i])
				var bs := Basis(Vector3(f[o], f[o + 4], f[o + 8]), Vector3(f[o + 1], f[o + 5], f[o + 9]), Vector3(f[o + 2], f[o + 6], f[o + 10]))
				cs.transform = Transform3D(bs, pos)
			body.add_child(cs)
	if layer == L.TREE:
		body.add_to_group("no_climb")
	add_child(body)
	b["body"] = body
