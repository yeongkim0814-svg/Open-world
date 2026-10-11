class_name GrassGen
extends RefCounted
## 덩어리형 풀 생성기: 끝이 넓은 꽃잎형 잎 3~5장을 둥글게 모은 낮은 폴리 덩어리 (뾰족한 털 금지).
## 정점색(ArrayMesh는 정점색을 8비트 0~1로 저장하므로 1 초과 불가):
## R = 명도(0.8~1.0, 셰이더가 ×1.1 → 0.88~1.1), G = 바람 가중(높이 비율, 뿌리 0), B = 꽃 표시(1 = 꽃 정점), A = AO(뿌리 0.5).
## 단위 m, 원점 = 뿌리 중심.

## PATCH = 풀 덩어리(B2: 잎 다발 여러 개를 한 둔덕으로, ≤ 120 삼각형), FLOWER_PATCH = 꽃무리(꽃 8~15송이, 지름 2~4 m, ≤ 200 삼각형).
enum Kind { TUFT, BROAD, FLOWER, LOW, PATCH, FLOWER_PATCH }

const TIP_RATIO_MIN := 0.6   ## 잎 끝 폭 / 뿌리 폭 하한 (뾰족함 방지)


## variant 0 = 기본, 1+ = 같은 종류의 다른 잎 배치 (seed 만 다름)
static func build(kind: int, variant := 0) -> ArrayMesh:
	var k := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + kind + variant * 131
	var top := 0.0
	match kind:
		Kind.TUFT:
			top = _leaves(k, rng, 5, 0.10, 0.06, 0.26, 0.12, 1.1, 0.3)
		Kind.BROAD:
			top = _leaves(k, rng, 4, 0.17, 0.08, 0.17, 0.14, 1.0, 0.6)
		Kind.FLOWER:
			top = _leaves(k, rng, 3, 0.10, 0.06, 0.2, 0.10, 1.05, 0.2)
			_flower(k, 0.4)
			top = 0.4
		Kind.LOW:
			# 낮고 넓게 퍼진 잎 7장 (높이 0.10~0.14, 바깥으로 크게 기울임)
			top = _leaves(k, rng, 7, 0.10, 0.05, 0.12, 0.13, 1.0, 0.4)
		Kind.PATCH:
			top = _patch(k, rng)
		Kind.FLOWER_PATCH:
			top = _flower_patch(k, rng)
	_apply_weights(k, top)
	return k.commit()


## 풀 덩어리: 가운데 다발 1 + 둘레 다발 5 (다발마다 잎 7~8장 = 사각형 → 삼각형 ≤ 112). 가운데가 높은 둔덕. 폭 ≈ 2.2 m, 높이 ≈ 0.8~1.1 m.
static func _patch(k: MeshKit, rng: RandomNumberGenerator) -> float:
	var top := 0.0
	top = maxf(top, _leaves(k, rng, 6, 0.22, 0.10, 0.95, 0.30, 0.85, 0.5))
	var a0 := rng.randf() * TAU
	for i in 5:
		var a := a0 + TAU * float(i) / 5.0 + rng.randf_range(-0.2, 0.2)
		var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.55, 0.7)
		top = maxf(top, _leaves(k, rng, 7, 0.20, 0.08, rng.randf_range(0.6, 0.8), 0.32, 0.85, 0.5, o))
	return top


## 꽃무리: 낮은 잎 12장 + 꽃 8~15송이를 반지름 ≤ 1.7 m 안에 흩뿌린다 (꽃 한 송이 = 줄기 2 + 꽃잎 4 = 6 삼각형).
static func _flower_patch(k: MeshKit, rng: RandomNumberGenerator) -> float:
	var top := 0.0
	var a0 := rng.randf() * TAU
	for i in 4:
		var a := a0 + TAU * float(i) / 4.0
		var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.5, 1.0)
		top = maxf(top, _leaves(k, rng, 3, 0.16, 0.06, 0.28, 0.14, 0.9, 0.4, o))
	var n := rng.randi_range(8, 15)
	for i in n:
		# 면적 균일 분포(√)에 가까운 원판 안 무작위, 바깥쪽을 약간 선호해 지름 2 m 이상을 보장
		var a := TAU * (float(i) + rng.randf_range(0.0, 0.8)) / float(n)
		var d := lerpf(0.5, 1.75, sqrt(rng.randf()))
		var h := rng.randf_range(0.35, 0.6)
		_flower(k, h, Vector3(cos(a) * d, 0.0, sin(a) * d), rng.randf() * TAU)
		top = maxf(top, h + 0.03)
	return top


## 잎 n장을 방사형으로 세운다. 각 잎 = 사각형(뿌리 폭 w, 끝 폭 w×ratio). 가장 높은 y를 돌려준다.
static func _leaves(k: MeshKit, rng: RandomNumberGenerator, n: int, root_w: float, r0: float,
		height: float, lean: float, ratio: float, tone_var: float, origin := Vector3.ZERO) -> float:
	var top := 0.0
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
		var d := Vector3(cos(a), 0.0, sin(a))
		var p := Vector3(-d.z, 0.0, d.x)
		var h := height * rng.randf_range(0.8, 1.15)
		var out := lean * rng.randf_range(0.8, 1.2)
		var tip_w := root_w * maxf(ratio * rng.randf_range(0.9, 1.15), TIP_RATIO_MIN + 0.05)
		var base := origin + d * r0
		var tipc := origin + d * (r0 + out) + Vector3(0.0, h, 0.0)
		var tone := 0.9 + (rng.randf() - 0.5) * 0.2 * tone_var
		var col := Color(tone, 0.0, 0.0, 1.0)
		# 바깥에서 보아 반시계: 왼쪽 아래 → 오른쪽 아래 → 오른쪽 위 → 왼쪽 위 (왼쪽 = +p)
		k.add_quad(base + p * root_w * 0.5, base - p * root_w * 0.5,
				tipc - p * tip_w * 0.5, tipc + p * tip_w * 0.5, col)
		top = maxf(top, h)
	return top


## 가운데 줄기(사각형) + 4면 꽃송이. 꽃 정점은 B = 1.
## pos = 뿌리 위치, yaw = 줄기 판이 향하는 방향 (꽃무리에서 송이마다 다르게).
static func _flower(k: MeshKit, stem_h: float, pos := Vector3.ZERO, yaw := 0.0) -> void:
	var w := 0.06
	var col := Color(0.9, 0.0, 0.0, 1.0)
	var rot := Basis(Vector3.UP, yaw)
	k.add_quad(pos + rot * Vector3(-w * 0.5, 0.0, 0.0), pos + rot * Vector3(w * 0.5, 0.0, 0.0),
			pos + rot * Vector3(w * 0.42, stem_h - 0.05, 0.0), pos + rot * Vector3(-w * 0.42, stem_h - 0.05, 0.0), col)
	var y0 := stem_h - 0.07
	var s := 0.07
	var fc := Color(0.95, 0.0, 1.0, 1.0)
	var ring := [pos + rot * Vector3(s, y0, 0.0), pos + rot * Vector3(0.0, y0, s),
			pos + rot * Vector3(-s, y0, 0.0), pos + rot * Vector3(0.0, y0, -s)]
	var apex := pos + rot * Vector3(0.0, stem_h + 0.03, 0.0)
	for i in 4:
		# 바깥에서 보아 반시계: ring[i] → apex → ring[i+1]이 아래에서 올려다본 방향이므로 순서 맞춤
		k.add_tri(ring[i], ring[(i + 1) % 4], apex, fc)


## G = 높이 비율(바람 가중), A = 뿌리 0.5 → 꼭대기 1.0 (AO).
static func _apply_weights(k: MeshKit, top: float) -> void:
	var surfaces: Array = k._surfaces
	for s in surfaces:
		var v: PackedVector3Array = s[0]
		var c: PackedColorArray = s[1]
		for i in v.size():
			var t := clampf(v[i].y / top, 0.0, 1.0)
			c[i].g = t
			c[i].a = lerpf(0.5, 1.0, t)
		s[1] = c
