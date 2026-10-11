class_name VegPlacement
extends RefCounted
## 식생 배치: (층, 블록 키) → 개체 목록. 순수·결정적 (같은 입력 = 같은 목록).
## 후보 = 흔든 격자, 받아들임 = 밀도 확률. 싼 거름(노이즈·확률)을 먼저, ctx.excluded 는 마지막에.
## 개체: {"mesh": String, "xform": Transform3D, "custom": Color, "size": float}

const BLOCK := {
	VegContext.Layer.GRASS: 16.0,
	VegContext.Layer.SHRUB: 64.0,
	VegContext.Layer.TREE: 128.0,
	VegContext.Layer.ROCK: 128.0,
}

const GRASS_KINDS := ["tuft", "broad", "flower", "low"]
const ROCK_KINDS := ["round", "slab", "pillar"]
const TREE_KINDS := ["round", "column", "spread"]
const GRASS_VARIANTS := 2
const SHRUB_VARIANTS := 4
const TREE_VARIANTS := 6
const ROCK_VARIANTS := 4

# 풀 (설계서 4장)
const GRASS_MAX := 1.6
const GRASS_BARE_BELOW := -0.2        # clump 노이즈가 이 값 아래 = 맨땅 (대략 하위 25 %)
const GRASS_MIN_NY := 0.6428          # cos 50°
const GRASS_TILT := deg_to_rad(8.0)
# 나무
const TREE_MIN_NY := 0.77
const TREE_SPACING := 4.0
const TREE_CLUMP_BELOW := -0.25       # clump_tree 가 이 값 이상 = 상위 약 65 %
# 바위
const ROCK_MAX_SLOPE_NY := 0.342      # cos 70° 보다 가파른 면은 제외
const ROCK_TILT := deg_to_rad(25.0)

static var _noise_cache := {}


## 이 모듈이 낼 수 있는 모든 mesh id (VegCatalog 가 이 목록으로 메시를 만든다)
static func mesh_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in GRASS_KINDS:
		for v in GRASS_VARIANTS:
			out.append("grass_%s_%d" % [k, v])
	for v in SHRUB_VARIANTS:
		out.append("shrub_%d" % v)
	for k in TREE_KINDS:
		for v in TREE_VARIANTS:
			out.append("tree_%s_%d" % [k, v])
	for k in ROCK_KINDS:
		for v in ROCK_VARIANTS:
			out.append("rock_%s_%d" % [k, v])
	return out


## 노이즈 캐시. kind: "clump_grass"(1/25) "clump_tree"(1/70) "species"(1/18)
static func noise(kind: String, world_seed: int) -> FastNoiseLite:
	var key := "%s:%d" % [kind, world_seed]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + hash(kind) % 100003
	match kind:
		"clump_grass": n.frequency = 1.0 / 25.0
		"clump_tree": n.frequency = 1.0 / 70.0
		"species": n.frequency = 1.0 / 18.0
		_: n.frequency = 1.0 / 30.0
	_noise_cache[key] = n
	return n


static func block(ctx: VegContext, layer: int, key: Vector2i, world_seed := 1337) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, layer, key.x, key.y])
	var size: float = BLOCK[layer]
	var origin := Vector2(key.x * size, key.y * size)
	var out: Array = []
	match layer:
		VegContext.Layer.GRASS: _grass(ctx, rng, origin, size, world_seed, out)
		VegContext.Layer.SHRUB: _shrub(ctx, rng, origin, size, world_seed, out)
		VegContext.Layer.TREE: _tree(ctx, rng, origin, size, world_seed, out)
		VegContext.Layer.ROCK: _rock(ctx, rng, origin, size, out)
	return out


# ---------- 공통 ----------

## 최대 밀도에 맞춘 격자: 한 변 칸 수 n, 칸 크기 cell (블록을 딱 나눔)
static func _grid(size: float, max_density: float) -> Vector2:
	var n := maxi(1, ceili(size * sqrt(max_density)))
	return Vector2(n, size / n)


static func _item(mesh: String, xf: Transform3D, custom: Color, sz: float) -> Dictionary:
	return {"mesh": mesh, "xform": xf, "custom": custom, "size": sz}


## 방향 up 을 법선 쪽으로 최대 max_tilt 만큼만 기울인 기저 + 임의 방향 yaw
static func _tilted_basis(n: Vector3, rng: RandomNumberGenerator, max_tilt: float, extra: float) -> Basis:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	var ang := minf(acos(clampf(n.y, -1.0, 1.0)), max_tilt)
	var axis := Vector3.UP.cross(n)
	if axis.length_squared() > 1e-8 and ang > 1e-4:
		b = Basis(axis.normalized(), ang) * b
	if extra > 0.0:
		var ex := rng.randf() * extra
		b = Basis(Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized(), ex) * b
	return b


static func _pick(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1


# ---------- 풀 ----------

static func _grass(ctx: VegContext, rng: RandomNumberGenerator, o: Vector2, size: float, ws: int, out: Array) -> void:
	var g := _grid(size, GRASS_MAX)
	var n := int(g.x); var cell := g.y
	var area := cell * cell
	var clump := noise("clump_grass", ws)
	var species := noise("species", ws)
	for j in n:
		for i in n:
			var x := o.x + (i + rng.randf()) * cell
			var z := o.y + (j + rng.randf()) * cell
			var u := rng.randf()
			var c := clump.get_noise_2d(x, z)
			if c < GRASS_BARE_BELOW:
				continue
			var t := clampf((c - GRASS_BARE_BELOW) / 0.8, 0.0, 1.0)
			var zone := ctx.zone_at(x, z)
			var d: float = (0.4 + 1.2 * t) if zone == 0 else (0.1 + 0.5 * t)
			if u > d * area:
				continue
			var nrm := ctx.field.normal_at(x, z)
			if nrm.y < GRASS_MIN_NY:
				continue
			if ctx.excluded(VegContext.Layer.GRASS, x, z):
				continue
			var sp := species.get_noise_2d(x, z)   # -1..1
			out.append(_grass_item(ctx, rng, x, z, nrm, sp, zone, 1.0))


## 풀 한 포기. sp = species 노이즈, scale_mul = 꽃무리 등 크기 보정
static func _grass_item(ctx: VegContext, rng: RandomNumberGenerator, x: float, z: float, nrm: Vector3, sp: float, zone: int, scale_mul: float, force_kind := -1) -> Dictionary:
	var kind := force_kind
	if kind < 0:
		# 군락마다 우세종이 달라진다: species 노이즈로 가중치 이동
		var w_flower := 0.12 if zone == 0 else 0.04
		kind = _pick(rng, [0.38 - 0.25 * sp, 0.30 + 0.25 * sp, w_flower * (1.0 + sp), 0.2 - 0.12 * sp])
	var sz := rng.randf_range(0.6, 1.4) * scale_mul
	var hr := rng.randf_range(0.85, 1.2)
	var basis := _tilted_basis(nrm, rng, GRASS_TILT, 0.0)
	basis = basis * Basis.from_scale(Vector3(sz, sz * hr, sz))
	var y := ctx.ground_y(x, z)
	var variant := rng.randi() % 2
	var custom := Color(rng.randf(), rng.randf_range(0.0, 1.0), sp * 0.5 + 0.5, rng.randf())
	return _item("grass_%s_%d" % [GRASS_KINDS[kind], variant], Transform3D(basis, Vector3(x, y, z)), custom, sz)


# ---------- 덤불 ----------

static func _shrub(ctx: VegContext, rng: RandomNumberGenerator, o: Vector2, size: float, ws: int, out: Array) -> void:
	var g := _grid(size, 1.0 / 150.0)
	var n := int(g.x); var cell := g.y
	var area := cell * cell
	var species := noise("species", ws)
	for j in n:
		for i in n:
			var x := o.x + (i + rng.randf()) * cell
			var z := o.y + (j + rng.randf()) * cell
			var u := rng.randf()
			var kind_roll := rng.randf()
			var zone := ctx.zone_at(x, z)
			# 초원 기본 1/1500 만으로 끝나면 싼 길, 아니면 가장자리·길섶 확인 (그 밖 숲 안쪽은 없음)
			var base_ok := zone == 0 and u <= area / 1500.0
			if not base_ok:
				if u > area / 150.0:
					continue
				if not (ctx.edge_dist_zone(x, z, 20.0) < 20.0 or ctx.path_near(x, z, 6.0) > 0):
					continue
			var nrm := ctx.field.normal_at(x, z)
			if nrm.y < 0.6:
				continue
			if ctx.excluded(VegContext.Layer.SHRUB, x, z):
				continue
			var sp := species.get_noise_2d(x, z)
			if kind_roll < 0.3:
				_flower_patch(ctx, rng, x, z, sp, zone, out)
			else:
				var sz := rng.randf_range(0.7, 1.4)
				var basis := _tilted_basis(nrm, rng, deg_to_rad(6.0), 0.0) * Basis.from_scale(Vector3.ONE * sz)
				var custom := Color(0.0, rng.randf(), sp * 0.5 + 0.5, 0.0)
				out.append(_item("shrub_%d" % (rng.randi() % 4), Transform3D(basis, Vector3(x, ctx.ground_y(x, z), z)), custom, sz))


## 꽃무리: 풀 꽃 id 를 3~6개 묶어서 (반경 1.5 m)
static func _flower_patch(ctx: VegContext, rng: RandomNumberGenerator, cx: float, cz: float, sp: float, zone: int, out: Array) -> void:
	var count := rng.randi_range(3, 6)
	for k in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 1.5
		var x := cx + cos(a) * r
		var z := cz + sin(a) * r
		var nrm := ctx.field.normal_at(x, z)
		if nrm.y < GRASS_MIN_NY or ctx.excluded(VegContext.Layer.SHRUB, x, z):
			continue
		out.append(_grass_item(ctx, rng, x, z, nrm, sp, zone, 1.0, 2))


# ---------- 나무 ----------

static func _tree(ctx: VegContext, rng: RandomNumberGenerator, o: Vector2, size: float, ws: int, out: Array) -> void:
	var clump := noise("clump_tree", ws)
	var species := noise("species", ws)
	var placed: Array[Vector2] = []
	# 활엽수림: 1/200 m², 무리 노이즈 상위 65 % 안
	var g := _grid(size, 1.0 / 200.0)
	var n := int(g.x); var cell := g.y
	var p_cell := cell * cell / 200.0
	for j in n:
		for i in n:
			var x := o.x + (i + rng.randf()) * cell
			var z := o.y + (j + rng.randf()) * cell
			var u := rng.randf()
			if u > p_cell:
				continue
			if clump.get_noise_2d(x, z) < TREE_CLUMP_BELOW:
				continue
			if ctx.zone_at(x, z) != 1:
				continue
			_try_tree(ctx, rng, x, z, species, placed, out)
	# 초원: 3000 m² 당 1그루, 3~7그루 무리 (무리 중심 밀도 = 1/(3000 × 5))
	var half := size * 0.5
	var area := half * half
	for j in 2:
		for i in 2:
			var cx := o.x + (i + rng.randf()) * half
			var cz := o.y + (j + rng.randf()) * half
			var u := rng.randf()
			if u > area / 15000.0:
				continue
			if ctx.zone_at(cx, cz) != 0:
				continue
			var cnt := rng.randi_range(3, 7)
			for k in cnt:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 7.0
				_try_tree(ctx, rng, cx + cos(a) * r, cz + sin(a) * r, species, placed, out)


static func _try_tree(ctx: VegContext, rng: RandomNumberGenerator, x: float, z: float, species: FastNoiseLite, placed: Array[Vector2], out: Array) -> void:
	var p := Vector2(x, z)
	for q in placed:
		if p.distance_squared_to(q) < TREE_SPACING * TREE_SPACING:
			return
	if ctx.slope_ny(x, z) < TREE_MIN_NY:
		return
	if ctx.excluded(VegContext.Layer.TREE, x, z):
		return
	placed.append(p)
	var kind: String = TREE_KINDS[_pick(rng, [45.0, 25.0, 30.0])]
	var sz := rng.randf_range(0.75, 1.35)
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sz)
	var sp := species.get_noise_2d(x, z)
	var custom := Color(0.0, rng.randf(), sp * 0.5 + 0.5, 0.0)
	out.append(_item("tree_%s_%d" % [kind, rng.randi() % TREE_VARIANTS], Transform3D(basis, Vector3(x, ctx.ground_y(x, z, 0.5), z)), custom, sz))


# ---------- 바위 ----------

const CLIFF_NODE := 8.0   # 절벽 아래 판정용 거친 격자 (m)

static func _rock(ctx: VegContext, rng: RandomNumberGenerator, o: Vector2, size: float, out: Array) -> void:
	var g := _grid(size, 1.0 / 60.0)
	var n := int(g.x); var cell := g.y
	var area := cell * cell
	var cliff: Array = []
	for j in n:
		for i in n:
			var x := o.x + (i + rng.randf()) * cell
			var z := o.y + (j + rng.randf()) * cell
			var u := rng.randf()
			if u > area / 60.0:
				continue
			var nrm := ctx.field.normal_at(x, z)
			var ny := nrm.y
			if ny < ROCK_MAX_SLOPE_NY:
				continue
			var small_bias := false
			if ny >= 0.5 and ny < 0.85:
				if u > area / 150.0:
					# 비탈 1/150 을 넘는 몫은 절벽 아래일 때만 (아래 판정)
					if not _near_cliff(ctx, o, size, x, z, cliff):
						continue
					small_bias = true
			else:
				if not _near_cliff(ctx, o, size, x, z, cliff):
					continue
				small_bias = true
			if ctx.excluded(VegContext.Layer.ROCK, x, z):
				continue
			_rock_item(ctx, rng, x, z, nrm, small_bias, out)
	# 평지 노두: 4000 m² 당 1개, 2~5개 무리 (중심 밀도 1/(4000 × 3.5))
	var half := size * 0.5
	for j in 2:
		for i in 2:
			var cx := o.x + (i + rng.randf()) * half
			var cz := o.y + (j + rng.randf()) * half
			var u := rng.randf()
			if u > half * half / 14000.0:
				continue
			var cnt := rng.randi_range(2, 5)
			for k in cnt:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 4.0
				var x := cx + cos(a) * r
				var z := cz + sin(a) * r
				var nrm := ctx.field.normal_at(x, z)
				if nrm.y < ROCK_MAX_SLOPE_NY or ctx.excluded(VegContext.Layer.ROCK, x, z):
					continue
				_rock_item(ctx, rng, x, z, nrm, false, out)


## 10 m 안에 normal.y < 0.5 인 면이 있나 (거친 노드 격자 지연 계산, 3×3 노드 = 약 ±8 m)
static func _near_cliff(ctx: VegContext, o: Vector2, size: float, x: float, z: float, cliff: Array) -> bool:
	var nn := int(ceil(size / CLIFF_NODE)) + 3   # 가장자리 한 칸 여유 양쪽
	if cliff.size() != nn * nn:
		cliff.resize(nn * nn)
		cliff.fill(255)   # 미계산
	var ci := int(floor((x - o.x) / CLIFF_NODE)) + 1
	var cj := int(floor((z - o.y) / CLIFF_NODE)) + 1
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var a := clampi(ci + di, 0, nn - 1)
			var b := clampi(cj + dj, 0, nn - 1)
			var idx := b * nn + a
			if cliff[idx] == 255:
				var px := o.x + (a - 1) * CLIFF_NODE
				var pz := o.y + (b - 1) * CLIFF_NODE
				cliff[idx] = 1 if ctx.slope_ny(px, pz) < 0.5 else 0
			if cliff[idx] == 1:
				return true
	return false


static func _rock_item(ctx: VegContext, rng: RandomNumberGenerator, x: float, z: float, nrm: Vector3, small_bias: bool, out: Array) -> void:
	var r := rng.randf()
	var sz: float
	if small_bias:
		r *= 0.85   # 돌무더기는 작은 것 위주
	if r < 0.70:
		sz = rng.randf_range(0.4, 1.2)
	elif r < 0.95:
		sz = rng.randf_range(1.2, 2.5)
	else:
		sz = rng.randf_range(2.5, 5.0)
	var kind: String = ROCK_KINDS[_pick(rng, [50.0, 30.0, 20.0])]
	var basis := _tilted_basis(nrm, rng, ROCK_TILT, deg_to_rad(8.0))
	basis = basis * Basis.from_scale(Vector3(sz, sz * rng.randf_range(0.8, 1.2), sz))
	var burial := sz * rng.randf_range(0.2, 0.4)
	var y := ctx.ground_y(x, z, sz * 0.4) - burial
	out.append(_item("rock_%s_%d" % [kind, rng.randi() % 4], Transform3D(basis, Vector3(x, y, z)), Color(0.0, rng.randf(), 0.5, 0.0), sz))
