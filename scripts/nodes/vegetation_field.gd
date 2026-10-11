class_name VegetationField
extends Node3D
## 식생·바위 스트리밍: 층(풀·덤불·나무·바위)마다 카메라 주변 블록을 만들고 지운다.
## 블록 = mesh id 별 MultiMeshInstance3D (나무는 LOD0·LOD1 두 벌). 근처 나무·바위 블록만 충돌체를 가진다.
## 전부 메인 스레드 (배치 캐시가 스레드 안전하지 않음) — step(budget_ms) 이 예산 안에서 블록을 나눠 만든다.

const L := VegContext.Layer
const COLLIDE_R := 48.0          ## 이 거리 안의 나무·바위 블록만 충돌
const COL_ITEM_R := COLLIDE_R + 16.0   ## 충돌 블록 안에서도 이 거리 안 개체만 충돌 모양을 만든다
const COL_REBUILD_MOVE := 12.0   ## 충돌 만든 뒤 중심이 이만큼 움직이면 다시 만든다
const REFRESH_MOVE := 2.0        ## 중심이 이만큼 움직이면 대기열 갱신
const DIAG := 0.7072             ## 블록 대각 / 2 비율
const ROCK_COLLIDE_MIN := 1.2
const TREE_LOD0_END := 260.0
const TREE_LOD1_BEGIN := 240.0
const TREE_MARGIN := 20.0
const STRIDE := 13               ## 충돌 자료: 변환 12 실수 + 크기

## 층별 보이는 거리 (m) = 블록 스트리밍 반경 기본값
const END := {L.GRASS: 55.0, L.SHRUB: 160.0, L.TREE: 700.0, L.ROCK: 500.0}

var _ctx: VegContext
var _cat: VegCatalog
var _seed := 1337
var _reach := {L.GRASS: 55.0, L.SHRUB: 160.0, L.TREE: 700.0, L.ROCK: 500.0}
var _blocks := {}      ## 층 → {Vector2i → {"node","count","col","cdata","body","ccenter"}}
var _pending: Array = []   ## 내림차순 정렬 [거리, 종류(0 = 충돌, 1 = 블록), 층, 키] — 끝에서 꺼낸다
var _queued := {}
var _center := Vector2.ZERO
var _last_refresh := Vector2(1e12, 1e12)
var _water: Array = []
var _prev_water := Callable()
var _instances := 0
## 물 노드 목록 공급자 (기본: 그룹 "water"). 트리 밖 시험용으로 바꿔 끼울 수 있다.
var water_source := Callable()


func setup(ctx: VegContext, catalog: VegCatalog, world_seed := 1337) -> void:
	_ctx = ctx
	_cat = catalog
	_seed = world_seed
	for layer in END:
		_blocks[layer] = {}
	# 기존 물 판정(있으면)과 합쳐 블록 만들 때마다 갱신되는 물 노드 목록을 본다
	_prev_water = ctx.get_water()
	ctx.set_water(_water_level)


## 테스트용: 층별 스트리밍 반경을 바꾼다 (0 = 그 층 안 만듦)
func set_reach(layer: int, r: float) -> void:
	_reach[layer] = r


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _ctx == null:
		return
	update_center(cam.global_position)
	step(3.0)


func busy() -> bool:
	return not _pending.is_empty()


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
	var c := 0
	for layer in _blocks:
		n += (_blocks[layer] as Dictionary).size()
	c = collision_block_keys().size()
	return {"blocks": n, "instances": _instances, "collision_blocks": c, "pending": _pending.size()}


func update_center(p: Vector3) -> void:
	var c := Vector2(p.x, p.z)
	_center = c
	if c.distance_to(_last_refresh) < REFRESH_MOVE:
		return
	_last_refresh = c
	_refresh()


## 대기열에서 가까운 것부터 만든다. 예산이 소진되면 새 블록을 시작하지 않는다 (한 블록은 넘겨 끝낼 수 있음).
## 대기열이 있으면 예산 0 이어도 한 건은 처리 (진행 보장).
func step(budget_ms := 3.0) -> void:
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var first := true
	while not _pending.is_empty():
		if not first and Time.get_ticks_usec() >= deadline:
			break
		first = false
		var e: Array = _pending.pop_back()
		_queued.erase(_qkey(e[1], e[2], e[3]))
		if e[1] == 0:
			_build_collision(e[2], e[3])
		else:
			_build_block(e[2], e[3])


# ---------- 대기열 ----------

func _qkey(kind: int, layer: int, k: Vector2i) -> String:
	return "%d:%d:%d:%d" % [kind, layer, k.x, k.y]


func _block_center(layer: int, k: Vector2i) -> Vector2:
	var s: float = VegPlacement.BLOCK[layer]
	return Vector2((k.x + 0.5) * s, (k.y + 0.5) * s)


func _wanted(layer: int, k: Vector2i) -> bool:
	var s: float = VegPlacement.BLOCK[layer]
	var r: float = _reach[layer]
	if r <= 0.0:
		return false
	return _block_center(layer, k).distance_to(_center) <= r + s * DIAG


func _col_wanted(layer: int, k: Vector2i) -> bool:
	var s: float = VegPlacement.BLOCK[layer]
	return (layer == L.TREE or layer == L.ROCK) and _block_center(layer, k).distance_to(_center) <= COLLIDE_R + s * DIAG


func _refresh() -> void:
	_pending.clear()
	_queued.clear()
	for layer in _blocks:
		var have: Dictionary = _blocks[layer]
		var s: float = VegPlacement.BLOCK[layer]
		var r: float = _reach[layer]
		# 지금 범위를 벗어난 블록 지움
		for k in have.keys():
			if not _wanted(layer, k):
				_free_block(layer, k)
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
					_push(1, layer, k, d)
				elif _col_wanted(layer, k):
					var b: Dictionary = have[k]
					if b["body"] == null or (b["ccenter"] as Vector2).distance_to(_center) > COL_REBUILD_MOVE:
						_push(0, layer, k, d - 1000.0)   # 충돌을 먼저
		# 충돌 범위를 벗어난 충돌체 지움
		for k in have.keys():
			if not _col_wanted(layer, k):
				_drop_body(have[k])
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
	(b["node"] as Node).queue_free()
	_blocks[layer].erase(k)


func _drop_body(b: Dictionary) -> void:
	if b["body"] != null:
		(b["body"] as Node).queue_free()
		b["body"] = null


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


# ---------- 블록 ----------

func _build_block(layer: int, k: Vector2i) -> void:
	if _blocks[layer].has(k) or not _wanted(layer, k):
		return
	# 호수 수위 변화 반영: 블록마다 다시 읽는다
	if water_source.is_valid():
		_water = water_source.call()
	elif is_inside_tree():
		_water = get_tree().get_nodes_in_group("water")
	var items := VegPlacement.block(_ctx, layer, k, _seed)
	var node := Node3D.new()
	add_child(node)
	var groups := {}
	for it in items:
		var id: String = it["mesh"]
		if not groups.has(id):
			groups[id] = []
		groups[id].append(it)
	for id in groups:
		_add_multimesh(node, layer, id, groups[id])
	var cdata := _collision_data(layer, items)
	var b := {"node": node, "count": items.size(), "col": cdata.size() > 0, "cdata": cdata, "body": null, "ccenter": Vector2.ZERO}
	_blocks[layer][k] = b
	_instances += items.size()
	if _col_wanted(layer, k):
		_make_body(layer, k, b)


func _add_multimesh(node: Node3D, layer: int, id: String, list: Array) -> void:
	var n := list.size()
	var buf := PackedFloat32Array()
	buf.resize(n * 20)   # 변환 12 + 색 4 + 사용자 4
	var i := 0
	for it in list:
		var xf: Transform3D = it["xform"]
		var bs := xf.basis
		var o := xf.origin
		var c: Color = it["custom"]
		buf[i] = bs.x.x; buf[i + 1] = bs.y.x; buf[i + 2] = bs.z.x; buf[i + 3] = o.x
		buf[i + 4] = bs.x.y; buf[i + 5] = bs.y.y; buf[i + 6] = bs.z.y; buf[i + 7] = o.y
		buf[i + 8] = bs.x.z; buf[i + 9] = bs.y.z; buf[i + 10] = bs.z.z; buf[i + 11] = o.z
		buf[i + 12] = 1.0; buf[i + 13] = 1.0; buf[i + 14] = 1.0; buf[i + 15] = 1.0   # 흰색 (정점색이 어두워지지 않게)
		buf[i + 16] = c.r; buf[i + 17] = c.g; buf[i + 18] = c.b; buf[i + 19] = c.a
		i += 20
	var is_tree := layer == L.TREE
	var lods := 2 if is_tree else 1
	for lod in lods:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _cat.mesh(id, lod)
		mm.instance_count = n
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var shadow := (is_tree or layer == L.ROCK) and lod == 0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_tree:
			if lod == 0:
				mmi.visibility_range_end = TREE_LOD0_END
				mmi.visibility_range_end_margin = TREE_MARGIN
			else:
				mmi.visibility_range_begin = TREE_LOD1_BEGIN
				mmi.visibility_range_begin_margin = TREE_MARGIN
				mmi.visibility_range_end = END[L.TREE]
				mmi.visibility_range_end_margin = TREE_MARGIN
		else:
			mmi.visibility_range_end = END[layer]
		node.add_child(mmi)


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
	_make_body(layer, k, b)


func _make_body(layer: int, k: Vector2i, b: Dictionary) -> void:
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
				var tr := _cat.trunk(ids[i])
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(tr.x * sz, 0.05)
				cyl.height = maxf(tr.y * sz, 0.1)
				cs.shape = cyl
				cs.position = pos + Vector3.UP * cyl.height * 0.5
			else:
				cs.shape = _cat.rock_shape(ids[i])
				var bs := Basis(Vector3(f[o], f[o + 4], f[o + 8]), Vector3(f[o + 1], f[o + 5], f[o + 9]), Vector3(f[o + 2], f[o + 6], f[o + 10]))
				cs.transform = Transform3D(bs, pos)
			body.add_child(cs)
	if layer == L.TREE:
		body.add_to_group("no_climb")
	(b["node"] as Node3D).add_child(body)
	b["body"] = body
