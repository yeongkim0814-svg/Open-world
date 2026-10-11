class_name TreeGen
extends RefCounted
## 나무 생성기: 각진 6각 줄기 + 크고 각진 잎 덩어리 2~4개(찌그러뜨린 다면체). 결정적(seed).
## 서피스 0 = 줄기(style_lit), 서피스 1 = 잎(style_foliage). 잎 정점색: R = 명도(0.8~1.0, 셰이더 ×1.1), G = 바람 가중(나무 높이 비율), A = AO.

enum Kind { ROUND, COLUMN, SHRUB }

const TRUNK_SIDES := 6


static func build(seed: int, kind: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + kind * 104729 + 13
	var k := MeshKit.new()
	var scale_y := 0.8 + 0.45 * fposmod(float(seed) * 0.618034, 1.0)   # 황금비 분포: 이웃 seed도 키가 크게 다름
	var blobs: Array = []   # [center, radii]
	var trunk_h := 0.0
	var trunk_r := 0.0
	match kind:
		Kind.ROUND:
			trunk_h = rng.randf_range(1.6, 2.6)
			trunk_r = rng.randf_range(0.2, 0.28)
			var rr := rng.randf_range(1.2, 1.7)
			blobs.append([Vector3(0.0, trunk_h + rr * 0.6, 0.0), Vector3(rr, rr * 0.85, rr)])
			blobs.append([Vector3(rr * 0.7, trunk_h + rr * 0.1, rr * 0.2), Vector3(rr * 0.7, rr * 0.6, rr * 0.7)])
			blobs.append([Vector3(-rr * 0.6, trunk_h + rr * 0.3, -rr * 0.4), Vector3(rr * 0.65, rr * 0.55, rr * 0.65)])
		Kind.COLUMN:
			trunk_h = rng.randf_range(1.0, 1.6)
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
	# seed마다 키가 달라지게 세로 배율
	trunk_h *= scale_y
	for b in blobs:
		b[0] = Vector3(b[0].x, b[0].y * scale_y, b[0].z)
		b[1] = Vector3(b[1].x, b[1].y * scale_y, b[1].z)
	_trunk(k, rng, trunk_h * 1.15, trunk_r)
	k.begin_surface()
	var top := 0.0
	for b in blobs:
		top = maxf(top, (b[0] as Vector3).y + (b[1] as Vector3).y)
	for b in blobs:
		_blob(k, rng, b[0], b[1], top)
	return k.commit()


## 아래가 굵은 6각 기둥 + 위 뚜껑. 위에서 아래로 갈수록 AO가 어두워진다.
static func _trunk(k: MeshKit, rng: RandomNumberGenerator, h: float, r: float) -> void:
	var phase := rng.randf() * TAU
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)) * h
	var bot: Array = []
	var top: Array = []
	for i in TRUNK_SIDES:
		var a := phase + TAU * float(i) / TRUNK_SIDES
		bot.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		top.append(Vector3(cos(a) * r * 0.65, h, sin(a) * r * 0.65) + lean)
	for i in TRUNK_SIDES:
		var j := (i + 1) % TRUNK_SIDES
		var tone := 0.9 + 0.1 * float(i % 3) / 2.0
		# 바깥에서 보아 반시계 = 각도 증가 쪽이 오른쪽이므로 b[j]가 오른쪽
		k.add_quad(bot[i], bot[j], top[j], top[i], Color(tone, tone, tone, 1.0))
	var center := Vector3(0.0, h, 0.0) + lean
	for i in TRUNK_SIDES:
		k.add_tri(top[i], top[(i + 1) % TRUNK_SIDES], center, Color(1.0, 1.0, 1.0, 1.0))
	k.bake_height_ao(0.0, h, 0.35)


## 한 번 쪼갠 정이십면체를 타원체로 늘리고 정점마다 흔들어 각진 잎 덩어리를 만든다 (80 삼각형).
static func _blob(k: MeshKit, rng: RandomNumberGenerator, center: Vector3, radii: Vector3, tree_top: float) -> void:
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
