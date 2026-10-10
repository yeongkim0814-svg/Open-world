extends SceneTree
## 첫 섬 높이 지도 생성기 (일회 실행: godot --headless -s tools/gen_first_island.gd).
## 결과 PNG는 태블릿 그림 앱으로 직접 고쳐도 된다 — 밝을수록 높음 (0 = -10m, 255 = 60m).
## 좌표: 섬 중심 = 원점, 300m, 북쪽 = -Z. 설계서 docs/superpowers/specs/2026-10-10-m4-first-island-design.md 4장.

const SIZE := 256
const WORLD := 300.0
const MIN_H := -10.0
const MAX_H := 60.0
const LAKE := Vector2(0, -10)


func _initialize() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for pz in SIZE:
		for px in SIZE:
			var x := (float(px) / (SIZE - 1) - 0.5) * WORLD
			var z := (float(pz) / (SIZE - 1) - 0.5) * WORLD
			var v := (height(x, z) - MIN_H) / (MAX_H - MIN_H)
			img.set_pixel(px, pz, Color(v, v, v))
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


## 저수호: 바닥 -4, 반경 45~47 안쪽 벽, 47~55 둑 윗면 16, 55~65 바깥 경사. 탑 섬 반경 8 = 18.
static func _lake(p: Vector2, h: float) -> float:
	var dl := p.distance_to(LAKE)
	if dl < 8.0:
		return 18.0
	if dl < 9.5:
		return lerpf(18.0, -4.0, (dl - 8.0) / 1.5)
	if dl < 45.0:
		return -4.0
	if dl < 47.0:
		return lerpf(-4.0, 16.0, (dl - 45.0) / 2.0)
	if dl < 55.0:
		return 16.0
	return lerpf(16.0, h, smoothstep(55.0, 65.0, dl))


static func _bump(p: Vector2, c: Vector2, sigma: float) -> float:
	return exp(-p.distance_squared_to(c) / (2.0 * sigma * sigma))
