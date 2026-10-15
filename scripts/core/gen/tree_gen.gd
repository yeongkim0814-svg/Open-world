class_name TreeGen
extends RefCounted
## 나무 생성기: 각진 6각 줄기 + 크고 각진 잎 덩어리 2~4개(찌그러뜨린 다면체). 결정적(seed).
## SPREAD = 납작하고 넓은 활엽수 수관. 활엽수(SHRUB 아닌 것)는 BotW 비율: 평균 키 ≈ 12 m, 수관 아래 ≈ 4 m 줄기만 (숲 안 시야).
## lod 1 = 4각 줄기(뚜껑 없음) + 비세분 수관 덩어리 1개(28 삼각형), 키·수관 범위는 lod 0 과 같다.
## 서피스 0 = 줄기(style_lit), 서피스 1 = 잎(style_foliage). 잎 정점색: R = 명도(0.8~1.0, 셰이더 ×1.1), G = 바람 가중(나무 높이 비율), A = AO.

enum Kind { ROUND, COLUMN, SHRUB, SPREAD }

const TRUNK_SIDES := 6
const TREE_SIZE := 2.7       ## 활엽수 크기 배율 (줄기 높이·수관 전부) — 덤불은 1
const TREE_TRUNK_R := 2.0    ## 활엽수 줄기 굵기 배율 (크기 배율보다 작게: 12 m 나무에 지름 ≈ 1 m)


static func build(seed: int, kind: int, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + kind * 104729 + 13
	var k := MeshKit.new()
	var scale_y := 0.8 + 0.45 * fposmod(float(seed) * 0.618034, 1.0)   # 황금비 분포: 이웃 seed도 키가 크게 다름
	var blobs: Array = []   # [center, radii]
	var trunk_h := 0.0
	var trunk_r := 0.0
	match kind:
		Kind.ROUND:
			trunk_h = rng.randf_range(1.9, 2.9)   # 수관 바닥을 들어 올림 (×TREE_SIZE 후 ≈ 4.5 m)
			trunk_r = rng.randf_range(0.2, 0.28)
			var rr := rng.randf_range(1.2, 1.7)
			blobs.append([Vector3(0.0, trunk_h + rr * 0.6, 0.0), Vector3(rr, rr * 0.85, rr)])
			blobs.append([Vector3(rr * 0.7, trunk_h + rr * 0.3, rr * 0.2), Vector3(rr * 0.7, rr * 0.6, rr * 0.7)])
			blobs.append([Vector3(-rr * 0.6, trunk_h + rr * 0.3, -rr * 0.4), Vector3(rr * 0.65, rr * 0.55, rr * 0.65)])
		Kind.COLUMN:
			trunk_h = rng.randf_range(1.4, 2.0)
			trunk_r = rng.randf_range(0.16, 0.22)
			var w := rng.randf_range(0.8, 1.05)
			var y := trunk_h
			for i in 3:
				var s := 1.0 - float(i) * 0.25
				blobs.append([Vector3(rng.randf_range(-0.1, 0.1), y + w * 0.9 * s, rng.randf_range(-0.1, 0.1)),
						Vector3(w * s, w * 1.1 * s, w * s)])
				y += w * 1.2 * s
		Kind.SHRUB:
			trunk_h = rng.randf_range(0.25, 0.45)
			trunk_r = rng.randf_range(0.08, 0.12)
			var rr := rng.randf_range(0.5, 0.75)
			blobs.append([Vector3(0.0, trunk_h + rr * 0.5, 0.0), Vector3(rr, rr * 0.7, rr)])
			blobs.append([Vector3(rr * 0.75, trunk_h + rr * 0.3, rr * 0.2), Vector3(rr * 0.6, rr * 0.5, rr * 0.6)])
			blobs.append([Vector3(-rr * 0.55, trunk_h + rr * 0.35, -rr * 0.45), Vector3(rr * 0.55, rr * 0.5, rr * 0.55)])
		Kind.SPREAD:
			trunk_h = rng.randf_range(2.3, 3.1)
			trunk_r = rng.randf_range(0.22, 0.3)
			var rr := rng.randf_range(2.0, 2.6)
			blobs.append([Vector3(0.0, trunk_h + rr * 0.3, 0.0), Vector3(rr * 1.05, rr * 0.4, rr * 1.05)])
			var n_side := rng.randi_range(2, 3)
			var a0 := rng.randf() * TAU
			for i in n_side:
				var a := a0 + TAU * float(i) / float(n_side)
				blobs.append([Vector3(cos(a) * rr * 1.0, trunk_h + rr * 0.15, sin(a) * rr * 1.0),
							Vector3(rr * 0.5, rr * 0.3, rr * 0.5)])
	# seed마다 키가 달라지게 세로 배율
	trunk_h *= scale_y
	for b in blobs:
		b[0] = Vector3(b[0].x, b[0].y * scale_y, b[0].z)
		b[1] = Vector3(b[1].x, b[1].y * scale_y, b[1].z)
	# 활엽수: 모양 그대로 통째로 키운다 (삼각형 수 같음)
	if kind != Kind.SHRUB:
		trunk_h *= TREE_SIZE
		trunk_r *= TREE_TRUNK_R
		for b in blobs:
			b[0] *= TREE_SIZE
			b[1] *= TREE_SIZE
	# 크기는 모두 위에서 같은 rng 순서로 정해졌으므로 lod 와 무관하게 키·수관 범위가 같다.
	_trunk(k, rng, trunk_h * 1.15, trunk_r, 4 if lod >= 1 else TRUNK_SIDES, lod < 1)
	k.begin_surface()
	var top := 0.0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for b in blobs:
		var c: Vector3 = b[0]
		var r: Vector3 = b[1]
		top = maxf(top, c.y + r.y)
		lo = lo.min(c - r)
		hi = hi.max(c + r)
	if lod >= 1:
		# 수관 전체를 감싸는 하나의 거친 덩어리 (정이십면체 꼭짓점은 구의 85 % 높이라 약간 키운다)
		var mid := (lo + hi) * 0.5
		var half := (hi - lo) * 0.5
		_blob_coarse(k, mid, Vector3(half.x * 1.05, half.y * 1.15, half.z * 1.05), top)
	else:
		for b in blobs:
			_blob(k, rng, b[0], b[1], top)
	return k.commit()


## 아래가 굵은 6각 기둥 + 위 뚜껑. 위에서 아래로 갈수록 AO가 어두워진다.
static func _trunk(k: MeshKit, rng: RandomNumberGenerator, h: float, r: float, sides := TRUNK_SIDES, cap := true) -> void:
	var phase := rng.randf() * TAU
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)) * h
	var bot: Array = []
	var top: Array = []
	for i in sides:
		var a := phase + TAU * float(i) / sides
		bot.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		top.append(Vector3(cos(a) * r * 0.65, h, sin(a) * r * 0.65) + lean)
	for i in sides:
		var j := (i + 1) % sides
		var tone := 0.9 + 0.1 * float(i % 3) / 2.0
		# 바깥에서 보아 반시계 = 각도 증가 쪽이 오른쪽이므로 b[j]가 오른쪽
		k.add_quad(bot[i], bot[j], top[j], top[i], Color(tone, tone, tone, 1.0))
	var center := Vector3(0.0, h, 0.0) + lean
	if cap:
		for i in sides:
			k.add_tri(top[i], top[(i + 1) % sides], center, Color(1.0, 1.0, 1.0, 1.0))
	k.bake_height_ao(0.0, h, 0.35)


## 단위 정이십면체: [정점 12개(정규화), 면 20개].
static func _icosahedron() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	return [v, faces]


## LOD1 용: 세분·흔들기 없는 20면 타원체 한 덩어리 (20 삼각형). 정점색 규칙은 _blob 과 같다.
static func _blob_coarse(k: MeshKit, center: Vector3, radii: Vector3, tree_top: float) -> void:
	var ico := _icosahedron()
	var v: Array = ico[0]
	for f in ico[1]:
		var p: Array = []
		for idx in f:
			var q: Vector3 = v[idx]
			p.append(center + Vector3(q.x * radii.x, q.y * radii.y, q.z * radii.z))
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var c: Vector3 = p[2]
		if (b - a).cross(c - a).dot((a + b + c) / 3.0 - center) < 0.0:
			var tmp := b
			b = c
			c = tmp
		var up := clampf(((a + b + c) / 3.0 - center).y / radii.y * 0.5 + 0.5, 0.0, 1.0)
		k.add_tri(a, b, c, Color(lerpf(0.8, 1.0, up), 0.0, 0.0, 1.0))
	_weights_last(k, 60, center.y - radii.y, tree_top)


## 한 번 쪼갠 정이십면체를 타원체로 늘리고 정점마다 흔들어 각진 잎 덩어리를 만든다 (80 삼각형).
static func _blob(k: MeshKit, rng: RandomNumberGenerator, center: Vector3, radii: Vector3, tree_top: float) -> void:
	var ico := _icosahedron()
	var v: Array = ico[0]
	var faces: Array = ico[1]
	var cache := {}
	var new_faces := []
	for f in faces:
		var m: Array = []
		for e in 3:
			var a: int = f[e]
			var b: int = f[(e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not cache.has(key):
				v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
				cache[key] = v.size() - 1
			m.append(cache[key])
		new_faces.append([f[0], m[0], m[2]])
		new_faces.append([f[1], m[1], m[0]])
		new_faces.append([f[2], m[2], m[1]])
		new_faces.append([m[0], m[1], m[2]])
	# 정점마다 반지름 흔들기 (공유 정점이라 틈 없음) → 타원체 배율 → 중심 이동
	for i in v.size():
		var wob := rng.randf_range(0.82, 1.12)
		var p: Vector3 = v[i] * wob
		v[i] = center + Vector3(p.x * radii.x, p.y * radii.y, p.z * radii.z)
	var y_lo := center.y - radii.y
	for f in new_faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		if (b - a).cross(c - a).dot((a + b + c) / 3.0 - center) < 0.0:
			var tmp := b
			b = c
			c = tmp
		var up := clampf(((a + b + c) / 3.0 - center).y / radii.y * 0.5 + 0.5, 0.0, 1.0)
		var tone := lerpf(0.8, 1.0, up) + rng.randf_range(-0.03, 0.03)
		k.add_tri(a, b, c, Color(tone, 0.0, 0.0, 1.0))
	# 바람 가중·AO: 이 덩어리의 정점들만 (마지막 80 삼각형)
	_weights_last(k, 240, y_lo, tree_top)


static func _weights_last(k: MeshKit, vert_count: int, y_lo: float, tree_top: float) -> void:
	var s: Array = k._surfaces[-1]
	var v: PackedVector3Array = s[0]
	var c: PackedColorArray = s[1]
	for i in range(v.size() - vert_count, v.size()):
		var g := clampf(v[i].y / tree_top, 0.0, 1.0)
		c[i].g = g
		c[i].a = lerpf(0.55, 1.0, clampf(inverse_lerp(y_lo, tree_top, v[i].y), 0.0, 1.0))
	s[1] = c
