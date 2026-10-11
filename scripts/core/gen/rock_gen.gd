class_name RockGen
extends RefCounted
## 바위 생성기: 정이십면체(세분 1회, 80면) → 저주파 변위 → 크기 맞춤 → 평면 깎기 2~4개 → 평면 음영용 메시.
## 같은 (seed, kind) = 같은 메시. 둥글고 묵직한 덩어리 위주(뾰족한 가시 금지).
## 정점색: R = G = 명도, B = 윗면 표시 (B2 9.2: 법선 y > 0.6 인 면 = 1.0, 그 밖은 명도 × 0.9 < 0.95 — 이끼 셰이더가 B ≥ 0.95 를 윗면으로 읽는다), A = AO.

enum Kind { ROUND, SLAB, PILLAR }

const PILLAR_HEIGHT := 2.5
const AO_STRENGTH := 0.45
const TOP_NORMAL_Y := 0.6   ## 이 값보다 법선 y 가 크면 윗면(이끼) 표시


## 바위 메시를 만든다. 바닥이 y=0, 가로 중심이 원점.
static func build(seed: int, kind: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind, 4711])

	var mesh_data := _icosphere()
	var verts: PackedVector3Array = mesh_data[0]
	var faces: Array = mesh_data[1]

	# 1) 저주파 변위: 방향의 함수라 공유 정점끼리 갈라지지 않는다.
	var waves: Array = []
	for i in 4:
		waves.append([_rand_dir(rng), rng.randf_range(1.2, 2.4), rng.randf_range(0.0, TAU), rng.randf_range(0.5, 1.0)])
	var amp := 0.16 if kind == Kind.ROUND else 0.12
	for i in verts.size():
		var d := verts[i].normalized()
		var s := 0.0
		for w in waves:
			s += w[3] * sin(d.dot(w[0]) * w[1] * PI + w[2])
		verts[i] = d * (1.0 + amp * s / 2.0)

	# 2) 종류별 비율.
	var scale := Vector3(1.0, 0.85, 0.95)
	if kind == Kind.SLAB:
		scale = Vector3(1.6, 0.4, 1.25)
	elif kind == Kind.PILLAR:
		scale = Vector3(0.62, 2.5, 0.55)
	for i in verts.size():
		verts[i] *= scale

	# 3) 평면 깎기 2~4개.
	var cuts := rng.randi_range(2, 4)
	for c in cuts:
		var n := _rand_dir(rng)
		n = Vector3(n.x, maxf(n.y, -0.1), n.z).normalized()   # 아래로 향한 깎임(처마) 방지
		if kind == Kind.PILLAR and c == 0:
			n = Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35)).normalized()
		elif kind == Kind.ROUND and c == 0:
			n = Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()   # 윗면 이끼가 덩어리로 읽히게 위쪽 평면 하나
		elif kind == Kind.SLAB and c == 0:
			n = Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
		var reach := -INF
		for v in verts:
			reach = maxf(reach, v.dot(n))
		var off := reach * rng.randf_range(0.62, 0.82)
		for i in verts.size():
			var dn := verts[i].dot(n)
			if dn > off:
				verts[i] *= off / dn   # 원점에서 쏜 광선 방향으로 평면에 붙임 → 별 모양 유지, 면이 뒤집히지 않음

	# 4) 크기 정규화: 가장 긴 변 ≈ 1m (PILLAR는 높이 2.5), 바닥을 y=0으로.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var ext := hi - lo
	var k := PILLAR_HEIGHT / ext.y if kind == Kind.PILLAR else 1.0 / maxf(ext.x, maxf(ext.y, ext.z))
	var origin := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	for i in verts.size():
		verts[i] = (verts[i] - origin) * k
	var height := ext.y * k

	# 5) 면 단위 색: 위쪽이 밝고 면마다 ±3% 변주 → 0.9~1.1, 아래쪽 AO.
	var kit := MeshKit.new()
	for f in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var cc: Vector3 = verts[f[2]]
		var fn := (b - a).cross(cc - a).normalized()
		var br := clampf(1.0 + 0.07 * fn.y + rng.randf_range(-0.03, 0.03), 0.9, 1.1)
		if fn.y > TOP_NORMAL_Y:
			kit.add_tri(a, b, cc, Color(br, br, 1.0, 1.0))
		else:
			var bn := clampf(br * 0.9, 0.8, 0.9)   # 0.9 이하 → 윗면 표시(≥ 0.95)와 8비트 저장 후에도 구분됨
			kit.add_tri(a, b, cc, Color(bn, bn, bn, 1.0))
	kit.bake_height_ao(0.0, height, AO_STRENGTH)
	return kit.commit()


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var t := rng.randf_range(0.0, TAU)
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(t), z, r * sin(t))


## 세분 1회 정이십면체: [정점 배열, 면 인덱스 배열(바깥에서 보아 반시계)].
static func _icosphere() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in base.size():
		base[i] = base[i].normalized()
	var idx := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var verts := base
	var cache := {}
	var out: Array = []
	for f in idx:
		var m01 := _mid(verts, cache, f[0], f[1])
		var m12 := _mid(verts, cache, f[1], f[2])
		var m20 := _mid(verts, cache, f[2], f[0])
		out.append_array([[f[0], m01, m20], [f[1], m12, m01], [f[2], m20, m12], [m01, m12, m20]])
	# 안전장치: 중심 기준 안쪽을 향하면 뒤집는다(별 모양 구라 항상 성립).
	for f in out:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		if (b - a).cross(c - a).dot(a + b + c) < 0.0:
			var tmp: int = f[1]
			f[1] = f[2]
			f[2] = tmp
	return [verts, out]


static func _mid(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
