extends SceneTree
## 첫 섬 높이 지도 생성기 (일회 실행: godot --headless -s tools/gen_first_island.gd).
## 결과 PNG는 태블릿 그림 앱으로 직접 고쳐도 된다 — 밝을수록 높음 (빨강 0 = -10m, 255 = 60m).
## 정밀도: 빨강 = 상위 8비트, 초록 = 하위 비트(빨강 한 칸의 1/256). 회색 붓으로 칠해도 오차는 0.3m 이하.
## (8비트만 쓰면 0.27m 계단이 부드러운 법선에 줄무늬로 보인다 → HeightField 가 초록을 보정값으로 읽는다.)
## 좌표: 섬 중심 = 원점, 300m, 북쪽 = -Z. 설계서 docs/superpowers/specs/2026-10-10-m4-first-island-design.md 4장.
## 512 판: 기존 지형 요소·좌표·높이 위에 진폭 0.5~2m FBM 디테일(평지 굴곡, 산비탈은 거칠게, 절벽은 약하게).
## 디테일 제외: 호수 분지·둑·탑 섬·둑길, 마을 평지, 전초기지, 수문·바위벽, 고원, 발사 바위, 수로, 협곡 벽.

const SIZE := 512
const WORLD := 300.0
const MIN_H := -10.0
const MAX_H := 60.0
const LAKE := Vector2(0, -10)
const AQUEDUCT: Array[Vector2] = [Vector2(20, 47), Vector2(20, 62), Vector2(12, 78), Vector2(3, 89)]


func _initialize() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise := _noise(7, 1.0 / 28.0, 4)
	var rough := _noise(13, 1.0 / 14.0, 3)
	for pz in SIZE:
		for px in SIZE:
			var x := (float(px) / (SIZE - 1) - 0.5) * WORLD
			var z := (float(pz) / (SIZE - 1) - 0.5) * WORLD
			var h := height(x, z) + detail(x, z, noise, rough)
			var v := clampf((h - MIN_H) / (MAX_H - MIN_H), 0.0, 1.0) * 255.0
			var hi := floorf(v)
			var lo := minf(roundf((v - hi) * 256.0), 255.0)
			img.set_pixel(px, pz, Color8(int(hi), int(lo), int(hi)))
	var err := img.save_png("res://assets/terrain/first_island.png")
	print("first_island.png saved: ", error_string(err))
	quit()


static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 8.0                                                        # 기본 평지
	h = lerpf(h, 3.0, smoothstep(45.0, 30.0, p.distance_to(Vector2(0, 95))))   # 마을 저지대
	h = lerpf(h, 1.5, smoothstep(110.0, 128.0, z))                      # 남쪽 해변
	h += 50.0 * _bump(p, Vector2(0, -120), 25.0)                        # 북쪽 산 (평지 8 + 50 = 58)
	h += 27.0 * _bump(p, Vector2(-70, -30), 12.0)                       # 서쪽 능선 (35, 활공 출발)
	h = maxf(h, lerpf(h, 20.0, smoothstep(22.0, 14.0, p.distance_to(Vector2(-125, -20)))))  # 서쪽 고원
	var canyon := smoothstep(10.0, 6.0, absf(x + 95.0)) * smoothstep(-90.0, -80.0, z) * smoothstep(50.0, 40.0, z)
	h = lerpf(h, 2.0, canyon)                                           # 서쪽 협곡
	h = _lake(p, h)
	var d := p.length()
	return lerpf(MIN_H, h, smoothstep(140.0, 125.0, d))                 # 해안 → 바다


## FBM 디테일 (m). 평지 ±0.6m 완만한 굴곡, 경사·산은 최대 ±2m 결. 제외 구역은 0.
static func detail(x: float, z: float, noise: FastNoiseLite, rough: FastNoiseLite) -> float:
	var m := _detail_mask(x, z)
	if m <= 0.0:
		return 0.0
	var e := 1.5
	var slope := Vector2(height(x + e, z) - height(x - e, z), height(x, z + e) - height(x, z - e)).length() / (2.0 * e)
	var steep := smoothstep(0.2, 0.7, slope)                            # 언덕·산비탈 (약 10~35°)
	var high := smoothstep(20.0, 45.0, height(x, z))
	# 절벽(약 45° 이상)은 각도가 걷기/등반 경계(60~65°)를 오가지 않도록 디테일을 줄인다 — 결은 셰이더 바위가 낸다.
	var cliff := smoothstep(0.7, 1.1, slope)
	var rugged := maxf(steep, high) * (1.0 - cliff)
	var amp := lerpf(lerpf(0.6, 2.0, rugged), 0.2, cliff)
	var d := noise.get_noise_2d(x, z) * amp
	d += rough.get_noise_2d(x, z) * 0.5 * rugged                        # 산비탈의 잔결
	var beach := smoothstep(100.0, 115.0, z) + smoothstep(115.0, 125.0, Vector2(x, z).length())
	return d * m * (1.0 - 0.6 * clampf(beach, 0.0, 1.0))


## 1 = 디테일 전부, 0 = 원래 높이 그대로 (게임 요소가 놓인 평지·호수).
static func _detail_mask(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var m := smoothstep(57.0, 66.0, p.distance_to(LAKE))                # 분지·둑·탑 섬·둑길
	m *= smoothstep(35.0, 48.0, p.distance_to(Vector2(0, 95)))          # 마을
	m *= smoothstep(16.0, 24.0, p.distance_to(Vector2(95, 57)))         # 전초기지·수문 3
	m *= smoothstep(10.0, 16.0, p.distance_to(Vector2(-20, -88)))       # 수문 1·바위벽
	m *= smoothstep(22.0, 28.0, p.distance_to(Vector2(-125, -20)))      # 고원·수문 2
	m *= smoothstep(6.0, 10.0, p.distance_to(Vector2(-72, -28)))        # 발사 바위
	m *= 1.0 - smoothstep(16.0, 11.0, absf(x + 95.0)) * smoothstep(-96.0, -88.0, z) * smoothstep(56.0, 48.0, z)  # 협곡 벽 (등반 경로)
	m *= smoothstep(132.0, 124.0, p.length())                          # 바다
	for i in AQUEDUCT.size() - 1:                                       # 수로 (둑 → 마을)
		m *= smoothstep(4.0, 8.0, _seg_dist(p, AQUEDUCT[i], AQUEDUCT[i + 1]))
	return m


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _noise(seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


## 저수호: 바닥 -4, 반경 45~47 안쪽 벽, 47~55 둑 윗면 16, 55~65 바깥 경사. 탑 섬 반경 10 = 18.
static func _lake(p: Vector2, h: float) -> float:
	var dl := p.distance_to(LAKE)
	if dl < 10.0:
		return 18.0
	if dl < 11.5:
		return lerpf(18.0, -4.0, (dl - 10.0) / 1.5)
	if dl < 45.0:
		return -4.0
	if dl < 47.0:
		return lerpf(-4.0, 16.0, (dl - 45.0) / 2.0)
	if dl < 55.0:
		return 16.0
	return lerpf(16.0, h, smoothstep(55.0, 65.0, dl))


static func _bump(p: Vector2, c: Vector2, sigma: float) -> float:
	return exp(-p.distance_squared_to(c) / (2.0 * sigma * sigma))
