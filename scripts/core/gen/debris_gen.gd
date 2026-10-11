class_name DebrisGen
extends RefCounted
## 숲 바닥 잔해 생성기 (B2 설계서 9.1): 쓰러진 통나무(LOG)·그루터기(STUMP). 결정적(seed), 모두 ≤ 60 삼각형.
## 단일 서피스, 정점색 RGB = 명도 배수, A = AO (style_lit + 줄기색 재질). 바닥 = y 0.
## LOG: 길이 4~7 m, 지름 0.6~0.9 m, X 축으로 누운 6각 기둥 (한쪽 끝은 찢긴 듯 비스듬히 잘림). STUMP: 높이 0.4~0.9 m, 밑동이 퍼진 7각.

enum Kind { LOG, STUMP }


static func build(seed: int, kind: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind, 9173])
	var k := MeshKit.new()
	if kind == Kind.LOG:
		_log(k, rng)
	else:
		_stump(k, rng)
	return k.commit()


## 누운 통나무: 바닥 y=0 이 되도록 중심축 높이 = 반지름. 앞쪽 끝은 비스듬히 잘라 단면이 보이게 한다.
static func _log(k: MeshKit, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(4.0, 7.0)
	var r := rng.randf_range(0.36, 0.46)   # 외접 반지름 (6각이라 높이 = 1.73r~2r → 지름 0.62~0.92)
	var sides := 6
	var phase := rng.randf() * TAU
	var taper := rng.randf_range(0.8, 0.92)   # 가는 쪽(우듬지 쪽) 반지름 비율
	var cut := rng.randf_range(0.1, 0.35)     # 비스듬히 잘린 정도 (m)
	var a: Array = []   # x = -L/2 (밑동 쪽, 굵음)
	var b: Array = []   # x = +L/2 (끝, 가늘고 비스듬)
	for i in sides:
		var ang := phase + TAU * float(i) / sides
		var cy := cos(ang)
		var cz := sin(ang)
		a.append(Vector3(-length * 0.5, r + cy * r, cz * r))
		b.append(Vector3(length * 0.5 + cz * cut, r + cy * r * taper, cz * r * taper))
	# 6각 꼭짓점이 바닥에 정확히 닿도록 가장 낮은 정점을 y=0 으로 내린다 (중심축도 같이)
	var drop := INF
	for v in a + b:
		drop = minf(drop, v.y)
	for i in sides:
		a[i] -= Vector3(0.0, drop, 0.0)
		b[i] -= Vector3(0.0, drop, 0.0)
	for i in sides:
		var j := (i + 1) % sides
		var tone := 0.88 + 0.12 * float(i % 3) / 2.0
		# 축 방향(+X)을 따라 보았을 때 단면이 반시계가 되도록 각도 방향을 맞춘다 → 바깥에서 보아 반시계: a[i], b[i], b[j], a[j]
		k.add_quad(a[i], b[i], b[j], a[j], Color(tone, tone, tone, 1.0))
	var ca := Vector3(-length * 0.5, r - drop, 0.0)
	var cb := Vector3(length * 0.5, r - drop, 0.0)
	var cap_col := Color(0.8, 0.8, 0.8, 1.0)   # 단면은 살짝 어둡게 (나이테 느낌)
	for i in sides:
		var j := (i + 1) % sides
		k.add_tri(a[j], a[i], ca, cap_col)    # -X 쪽 뚜껑 (바깥 = -X)
		k.add_tri(b[i], b[j], cb, cap_col)    # +X 쪽 뚜껑
	k.bake_height_ao(0.0, 2.0 * r, 0.3)


## 그루터기: 밑동이 퍼진 7각 기둥 (아래 고리 → 몸통 → 윗면). 윗면은 약간 기울고 가장자리가 들쭉날쭉.
static func _stump(k: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.45, 0.85)
	var r := rng.randf_range(0.32, 0.48)
	var sides := 7
	var phase := rng.randf() * TAU
	var flare: Array = []
	var waist: Array = []
	var top: Array = []
	for i in sides:
		var ang := phase + TAU * float(i) / sides
		var d := Vector3(cos(ang), 0.0, sin(ang))
		flare.append(d * r * 1.35)
		waist.append(d * r * rng.randf_range(0.95, 1.05) + Vector3(0.0, h * 0.3, 0.0))
		top.append(d * r * 0.9 + Vector3(0.0, h * rng.randf_range(0.88, 1.0), 0.0))
	for i in sides:
		var j := (i + 1) % sides
		var tone := 0.88 + 0.12 * float(i % 3) / 2.0
		var c := Color(tone, tone, tone, 1.0)
		k.add_quad(flare[i], flare[j], waist[j], waist[i], c)
		k.add_quad(waist[i], waist[j], top[j], top[i], c)
	var center := Vector3(0.0, h * 0.97, 0.0)
	for i in sides:
		k.add_tri(top[(i + 1) % sides], top[i], center, Color(0.8, 0.8, 0.8, 1.0))   # 윗면 (바깥 = 위)
	k.bake_height_ao(0.0, h, 0.35)
