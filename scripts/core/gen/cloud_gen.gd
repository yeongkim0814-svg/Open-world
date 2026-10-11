class_name CloudGen
extends RefCounted
## 구름 생성기: 변형 구(경도 6 × 위도 4 = 36면) 3~6개를 가로로 뭉치고, 아랫면을 y=0 평면으로 눌러 납작하게 만든다.
## 정점색: R/B = 명도(0.9~1.1), G = 정점 애니메이션 가중(바닥 0 → 윗면 1), A = AO(아래쪽 어둡게).

const SEGMENTS := 6
const RINGS := 4
const AO_STRENGTH := 0.35


## 구름 메시를 만든다. 바닥이 y=0, 가로 중심이 원점.
static func build(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, 90210])
	var blobs := rng.randi_range(3, 6)

	var tris: Array = []   # 각 원소 = [a, b, c] (바깥에서 보아 반시계)
	var x := 0.0
	for i in blobs:
		var r := rng.randf_range(0.8, 1.3)
		var center := Vector3(x, r * rng.randf_range(0.3, 0.45), rng.randf_range(-0.5, 0.5))
		var radii := Vector3(r * rng.randf_range(1.0, 1.25), r * rng.randf_range(0.75, 0.95), r * rng.randf_range(0.95, 1.2))
		_add_blob(tris, rng, center, radii)
		x += r * rng.randf_range(0.9, 1.2)

	# 바닥 평평하게: y < 0 → 0. 가로 중심 맞춤.
	var hi := 0.0
	var sum_x := 0.0
	for t in tris:
		for j in 3:
			t[j] = Vector3(t[j].x, maxf(t[j].y, 0.0), t[j].z)
			hi = maxf(hi, t[j].y)
			sum_x += t[j].x
	var shift := Vector3(sum_x / (tris.size() * 3.0), 0.0, 0.0)
	hi = maxf(hi, 0.001)

	var kit := MeshKit.new()
	for t in tris:
		var a: Vector3 = t[0] - shift
		var b: Vector3 = t[1] - shift
		var c: Vector3 = t[2] - shift
		var fn := (b - a).cross(c - a).normalized()
		var br := clampf(1.0 + 0.06 * fn.y + rng.randf_range(-0.03, 0.03), 0.9, 1.1)
		kit.add_tri(a, b, c, Color(br, 0.0, br, 1.0))
	kit.bake_height_ao(0.0, hi, AO_STRENGTH)
	var mesh := kit.commit()

	# 정점 애니메이션 가중(G)은 정점 단위라 커밋 뒤 배열에 직접 쓴다.
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in v.size():
		cols[i].g = clampf(v[i].y / hi, 0.0, 1.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _add_blob(tris: Array, rng: RandomNumberGenerator, center: Vector3, radii: Vector3) -> void:
	# 격자 정점(극점은 한 점). 공유 정점은 같은 흔들림을 쓴다.
	var grid: Array = []   # grid[k][s]
	for k in RINGS + 1:
		var row: Array = []
		var phi := PI * k / RINGS
		var pole := k == 0 or k == RINGS
		var jit_row := rng.randf_range(0.92, 1.08)
		for s in SEGMENTS:
			if pole and s > 0:
				row.append(row[0])
				continue
			var th := TAU * s / SEGMENTS
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var j := jit_row * rng.randf_range(0.95, 1.05) if not pole else 1.0
			row.append(center + d * radii * j)
		grid.append(row)
	for k in RINGS:
		for s in SEGMENTS:
			var s2 := (s + 1) % SEGMENTS
			var p00: Vector3 = grid[k][s]
			var p01: Vector3 = grid[k][s2]
			var p10: Vector3 = grid[k + 1][s]
			var p11: Vector3 = grid[k + 1][s2]
			if k == 0:
				_push(tris, center, p00, p10, p11)
			elif k == RINGS - 1:
				_push(tris, center, p00, p10, p01)
			else:
				_push(tris, center, p00, p10, p11)
				_push(tris, center, p00, p11, p01)


## 바깥(구 중심 반대)을 향하도록 감기 순서를 맞춰 넣는다.
static func _push(tris: Array, center: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - center) < 0.0:
		tris.append([a, c, b])
	else:
		tris.append([a, b, c])
