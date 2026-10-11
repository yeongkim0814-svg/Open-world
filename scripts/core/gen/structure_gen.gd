class_name StructureGen
extends RefCounted
## 건축 부품 생성기: 모서리 깎은 블록 · 계단 · 기둥(8각 + 받침·머리) · 반원 아치(분할 8 + 기둥 2).
## 정점색: 면마다 명도 ±4%, 위쪽 면은 조금 밝게, 아래쪽은 AO로 어둡게. 같은 인자 = 같은 메시.

const AO_STRENGTH := 0.35
const BRIGHTNESS_JITTER := 0.04
const TOP_LIGHTEN := 0.03


## 모서리 깎은 블록(원점 중심). bevel = 모서리 깎임 폭, damage 0~1 = 떨어져 나간 모서리 비율(8개 중).
static func block(size: Vector3, bevel: float, seed: int, damage: float) -> ArrayMesh:
	var rng := _rng(seed, 1)
	var kit := MeshKit.new()
	var h := size * 0.5
	var b := minf(bevel, 0.45 * minf(size.x, minf(size.y, size.z)))
	if damage > 0.0 and b <= 0.0:
		b = 0.05 * minf(size.x, minf(size.y, size.z))   # 모서리가 없으면 떨어질 곳도 없다 → 최소 깎임
	if b <= 0.0:
		_box(kit, -h, h, rng, [])
		kit.bake_height_ao(-h.y, h.y, AO_STRENGTH)
		return kit.commit()

	# 떨어져 나갈 모서리: 8개 중 round(damage × 8)개, seed로 고른다. 안쪽으로 당기는 양도 seed로.
	var corner_pull := {}
	var order := range(8)
	for i in range(7, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var broken := int(round(clampf(damage, 0.0, 1.0) * 8.0))
	var min_h := minf(h.x, minf(h.y, h.z))
	for i in broken:
		corner_pull[order[i]] = rng.randf_range(0.25, 0.5) * min_h

	for a in 3:
		for sa in [-1.0, 1.0]:
			var o1 := (a + 1) % 3
			var o2 := (a + 2) % 3
			var pts: Array = []
			for so in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var s := Vector3.ZERO
				s[a] = sa
				s[o1] = so[0]
				s[o2] = so[1]
				pts.append(_bevel_point(h, b, s, a, corner_pull))
			var dir := Vector3.ZERO
			dir[a] = sa
			_poly(kit, pts, dir, rng)
	# 모서리 띠: 면 a와 b가 만나는 12개 모서리.
	for a in 3:
		var bx := (a + 1) % 3
		var o := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var s1 := Vector3.ZERO
				s1[a] = sa
				s1[bx] = sb
				s1[o] = -1.0
				var s2 := s1
				s2[o] = 1.0
				var pts := [_bevel_point(h, b, s1, a, corner_pull), _bevel_point(h, b, s1, bx, corner_pull),
					_bevel_point(h, b, s2, bx, corner_pull), _bevel_point(h, b, s2, a, corner_pull)]
				var dir := Vector3.ZERO
				dir[a] = sa
				dir[bx] = sb
				_poly(kit, pts, dir, rng)
	# 모서리 삼각형 8개.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_poly(kit, [_bevel_point(h, b, s, 0, corner_pull), _bevel_point(h, b, s, 1, corner_pull),
					_bevel_point(h, b, s, 2, corner_pull)], s, rng)
	kit.bake_height_ao(-h.y, h.y, AO_STRENGTH)
	return kit.commit()


## 계단: 폭 width, 단 steps개, 단 높이 step_h, 단 깊이 step_d. 앞(-z)이 낮고 뒤(+z)가 높다. 바닥 y=0, x 중심.
static func stairs(steps: int, width: float, step_h: float, step_d: float, seed: int) -> ArrayMesh:
	var rng := _rng(seed, 2)
	var kit := MeshKit.new()
	var w := width * 0.5
	var n := maxi(steps, 1)
	for i in n:
		var y0 := i * step_h
		var y1 := (i + 1) * step_h
		var z0 := i * step_d
		var z1 := (i + 1) * step_d
		_poly(kit, [Vector3(-w, y1, z0), Vector3(w, y1, z0), Vector3(w, y1, z1), Vector3(-w, y1, z1)], Vector3.UP, rng)
		_poly(kit, [Vector3(-w, y0, z0), Vector3(w, y0, z0), Vector3(w, y1, z0), Vector3(-w, y1, z0)], Vector3.FORWARD, rng)
		_poly(kit, [Vector3(-w, 0, z0), Vector3(-w, 0, z1), Vector3(-w, y1, z1), Vector3(-w, y1, z0)], Vector3.LEFT, rng)
		_poly(kit, [Vector3(w, 0, z0), Vector3(w, 0, z1), Vector3(w, y1, z1), Vector3(w, y1, z0)], Vector3.RIGHT, rng)
	var h := n * step_h
	var zb := n * step_d
	_poly(kit, [Vector3(-w, 0, zb), Vector3(w, 0, zb), Vector3(w, h, zb), Vector3(-w, h, zb)], Vector3.BACK, rng)
	_poly(kit, [Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, zb), Vector3(-w, 0, zb)], Vector3.DOWN, rng)
	kit.bake_height_ao(0.0, h, AO_STRENGTH)
	return kit.commit()


## 기둥: 8각, 받침 + 몸통(위로 갈수록 가늘어짐) + 머리. broken이면 머리 없이 윗부분이 비스듬히 잘려 있다.
static func pillar(height: float, radius: float, seed: int, broken: bool) -> ArrayMesh:
	var rng := _rng(seed, 3)
	var kit := MeshKit.new()
	var base_h := height * 0.07
	var cap_h := height * 0.08
	var phase := rng.randf_range(0.0, TAU / 8.0)

	var base_lo := _ring(0.0, radius * 1.3, phase, rng, 0.03)
	var base_hi := _ring(base_h, radius * 1.3, phase, rng, 0.03)
	var shaft_lo := _ring(base_h, radius, phase, rng, 0.02)
	_wall(kit, base_lo, base_hi, rng)
	_annulus(kit, base_hi, shaft_lo, true, rng)

	if broken:
		var top_y := height * rng.randf_range(0.55, 0.72)
		var tilt := rng.randf_range(0.6, 1.2) * radius
		var tdir := rng.randf_range(0.0, TAU)
		var shaft_hi := _ring(top_y, radius * 0.9, phase, rng, 0.02)
		var cut_top: Array = []
		for i in 8:
			var p: Vector3 = shaft_hi[i]
			p.y += tilt * cos(i * TAU / 8.0 + phase - tdir) + rng.randf_range(-0.03, 0.03) * height
			cut_top.append(p)
		_wall(kit, shaft_lo, cut_top, rng)
		var c := Vector3.ZERO
		for p in cut_top:
			c += p / 8.0
		for i in 8:
			_poly(kit, [c, cut_top[i], cut_top[(i + 1) % 8]], Vector3.UP, rng)
		kit.bake_height_ao(0.0, height, AO_STRENGTH)
		return kit.commit()

	var shaft_hi := _ring(height - cap_h, radius * 0.88, phase, rng, 0.02)
	var cap_lo := _ring(height - cap_h, radius * 1.2, phase, rng, 0.03)
	var cap_hi := _ring(height, radius * 1.2, phase, rng, 0.03)
	_wall(kit, shaft_lo, shaft_hi, rng)
	_annulus(kit, shaft_hi, cap_lo, false, rng)
	_wall(kit, cap_lo, cap_hi, rng)
	var c := Vector3(0.0, height, 0.0)
	for i in 8:
		_poly(kit, [c, cap_hi[i], cap_hi[(i + 1) % 8]], Vector3.UP, rng)
	kit.bake_height_ao(0.0, height, AO_STRENGTH)
	return kit.commit()


## 아치: 안쪽 반지름 span/2의 반원 띠(분할 8)를 기둥 2개 위에 얹는다. 전체 높이 = height, 깊이 = thickness. x 중심, 바닥 y=0.
static func arch(span: float, height: float, thickness: float, seed: int) -> ArrayMesh:
	var rng := _rng(seed, 4)
	var kit := MeshKit.new()
	var r_in := span * 0.5
	var r_out := r_in + thickness
	var post_h := maxf(height - r_out, 0.05)
	var hz := thickness * 0.5

	# 기둥 2개: 윗면·아랫면은 가려지므로 생략.
	for side in [-1.0, 1.0]:
		var x0 := r_in if side > 0.0 else -r_out
		_box(kit, Vector3(x0, 0.0, -hz), Vector3(x0 + thickness, post_h, hz), rng, ["top", "bottom"])

	# 반원 띠.
	var segs := 8
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var i0 := Vector3(r_in * cos(a0), post_h + r_in * sin(a0), 0.0)
		var i1 := Vector3(r_in * cos(a1), post_h + r_in * sin(a1), 0.0)
		var o0 := Vector3(r_out * cos(a0), post_h + r_out * sin(a0), 0.0)
		var o1 := Vector3(r_out * cos(a1), post_h + r_out * sin(a1), 0.0)
		var mid := (i0 + i1 + o0 + o1) * 0.25 - Vector3(0.0, post_h, 0.0)
		var zf := Vector3(0.0, 0.0, hz)
		_poly(kit, [i0 + zf, o0 + zf, o1 + zf, i1 + zf], Vector3.BACK, rng)
		_poly(kit, [i0 - zf, o0 - zf, o1 - zf, i1 - zf], Vector3.FORWARD, rng)
		_poly(kit, [o0 - zf, o0 + zf, o1 + zf, o1 - zf], mid, rng)
		_poly(kit, [i0 - zf, i0 + zf, i1 + zf, i1 - zf], -mid, rng)
	kit.bake_height_ao(0.0, post_h + r_out, AO_STRENGTH)
	return kit.commit()


# --- 내부 도구 ---

static func _rng(seed: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, salt, 1357])
	return rng


## 블록 모서리 s(±1 벡터)에서, 면 축 axis 위에 놓인 점. 나머지 두 축은 bevel만큼 안쪽. 떨어진 모서리는 안쪽으로 당긴다.
static func _bevel_point(h: Vector3, b: float, s: Vector3, axis: int, pull: Dictionary) -> Vector3:
	var p := Vector3.ZERO
	for i in 3:
		p[i] = s[i] * (h[i] if i == axis else h[i] - b)
	var idx := (1 if s.x > 0.0 else 0) + (2 if s.y > 0.0 else 0) + (4 if s.z > 0.0 else 0)
	if pull.has(idx):
		p -= s * pull[idx]
	return p


## 다각형(볼록) 하나를 부채꼴로 삼각분할해 넣는다. dir = 바깥 방향 힌트(감기 순서 판정), 면 하나에 명도 하나.
static func _poly(kit: MeshKit, pts: Array, dir: Vector3, rng: RandomNumberGenerator) -> void:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var flip := n.dot(dir) < 0.0
	if flip:
		pts = pts.duplicate()
		pts.reverse()
		n = -n
	var ny := n.normalized().y
	var br := 1.0 + rng.randf_range(-BRIGHTNESS_JITTER, BRIGHTNESS_JITTER) + TOP_LIGHTEN * ny
	var col := Color(br, br, br, 1.0)
	for i in range(1, pts.size() - 1):
		kit.add_tri(pts[0], pts[i], pts[i + 1], col)


## 축 정렬 상자. skip에 "top","bottom","left","right","front","back"(front = +z) 중 생략할 면.
static func _box(kit: MeshKit, lo: Vector3, hi: Vector3, rng: RandomNumberGenerator, skip: Array) -> void:
	var p := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z)
	if not "top" in skip:
		_poly(kit, [p.call(lo.x, hi.y, lo.z), p.call(hi.x, hi.y, lo.z), p.call(hi.x, hi.y, hi.z), p.call(lo.x, hi.y, hi.z)], Vector3.UP, rng)
	if not "bottom" in skip:
		_poly(kit, [p.call(lo.x, lo.y, lo.z), p.call(hi.x, lo.y, lo.z), p.call(hi.x, lo.y, hi.z), p.call(lo.x, lo.y, hi.z)], Vector3.DOWN, rng)
	if not "left" in skip:
		_poly(kit, [p.call(lo.x, lo.y, lo.z), p.call(lo.x, lo.y, hi.z), p.call(lo.x, hi.y, hi.z), p.call(lo.x, hi.y, lo.z)], Vector3.LEFT, rng)
	if not "right" in skip:
		_poly(kit, [p.call(hi.x, lo.y, lo.z), p.call(hi.x, lo.y, hi.z), p.call(hi.x, hi.y, hi.z), p.call(hi.x, hi.y, lo.z)], Vector3.RIGHT, rng)
	if not "front" in skip:
		_poly(kit, [p.call(lo.x, lo.y, hi.z), p.call(hi.x, lo.y, hi.z), p.call(hi.x, hi.y, hi.z), p.call(lo.x, hi.y, hi.z)], Vector3.BACK, rng)
	if not "back" in skip:
		_poly(kit, [p.call(lo.x, lo.y, lo.z), p.call(hi.x, lo.y, lo.z), p.call(hi.x, hi.y, lo.z), p.call(lo.x, hi.y, lo.z)], Vector3.FORWARD, rng)


## 높이 y의 8각 고리(반지름 r, 꼭짓점마다 ±jitter 비율 흔들림).
static func _ring(y: float, r: float, phase: float, rng: RandomNumberGenerator, jitter: float) -> Array:
	var out: Array = []
	for i in 8:
		var a := phase + TAU * i / 8.0
		var rr := r * (1.0 + rng.randf_range(-jitter, jitter))
		out.append(Vector3(rr * cos(a), y, rr * sin(a)))
	return out


## 두 고리 사이의 옆면(바깥을 향함).
static func _wall(kit: MeshKit, lo: Array, hi: Array, rng: RandomNumberGenerator) -> void:
	for i in 8:
		var j := (i + 1) % 8
		var mid: Vector3 = (lo[i] + lo[j] + hi[i] + hi[j]) * 0.25
		_poly(kit, [lo[i], lo[j], hi[j], hi[i]], Vector3(mid.x, 0.0, mid.z), rng)


## 두 고리 사이의 수평 띠(받침 윗면이면 up = true, 머리 아랫면이면 false).
static func _annulus(kit: MeshKit, a: Array, b: Array, up: bool, rng: RandomNumberGenerator) -> void:
	for i in 8:
		var j := (i + 1) % 8
		_poly(kit, [a[i], a[j], b[j], b[i]], Vector3.UP if up else Vector3.DOWN, rng)
