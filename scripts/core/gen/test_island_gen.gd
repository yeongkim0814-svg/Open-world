class_name TestIslandGen
extends RefCounted
## 스타일 테스트 씬용 128m 섬 높이 지도 (설계서 7장). 완만한 언덕 · 북서쪽 12m 절벽 고원 · 고원을 가르는 협곡 · 작은 연못.
## 16비트 관례: RGB8, R = 상위, G = 하위 (HeightField가 읽는 방식).

const WORLD := 128.0
const MIN_H := -4.0
const MAX_H := 28.0
const ISLAND_R := 52.0
const BASE_H := 5.0
const MESA_H := 17.0             ## 고원 높이 (바닥 5 → 절벽 약 12m)
const POND_CENTER := Vector2(18.0, 14.0)
const POND_R := 8.0
const POND_FLOOR := 0.5
const POND_LEVEL := 2.5          ## 연못 수면


static func height(x: float, z: float, noise: FastNoiseLite) -> float:
	var d := Vector2(x, z).length()
	var land := 1.0 - smoothstep(ISLAND_R - 10.0, ISLAND_R + 4.0, d)
	var h := BASE_H + noise.get_noise_2d(x, z) * 2.5
	# 고원: z < -14 이고 x < 6 인 사다리꼴 — 3m 띠로 솟아 절벽
	var mesa := smoothstep(-12.5, -15.5, z) * smoothstep(7.5, 4.5, x)
	# 협곡: x = -12 근처를 남북으로 가르는 폭 6m 골
	var canyon := 1.0 - smoothstep(2.0, 4.0, absf(x + 12.0 + sin(z * 0.15) * 2.0))
	mesa *= 1.0 - canyon
	h = lerpf(h, MESA_H + noise.get_noise_2d(x * 0.5, z * 0.5) * 1.5, mesa)
	# 연못: 가운데가 깊고 둘레는 완만
	var pd := Vector2(x, z).distance_to(POND_CENTER)
	h = lerpf(h, POND_FLOOR, 1.0 - smoothstep(POND_R * 0.5, POND_R + 3.0, pd))
	return lerpf(MIN_H, h, land)


static func image(size: int, seed: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	var data := PackedByteArray()
	data.resize(size * size * 3)
	for pz in size:
		for px in size:
			var x := (float(px) / (size - 1) - 0.5) * WORLD
			var z := (float(pz) / (size - 1) - 0.5) * WORLD
			var v := clampf((height(x, z, noise) - MIN_H) / (MAX_H - MIN_H), 0.0, 1.0) * 255.0
			var hi := floori(v)
			var lo := clampi(floori((v - hi) * 256.0), 0, 255)
			var i := (pz * size + px) * 3
			data[i] = hi
			data[i + 1] = lo
			data[i + 2] = hi
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)
