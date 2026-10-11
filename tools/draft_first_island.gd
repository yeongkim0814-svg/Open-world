extends SceneTree
## 첫 섬 1km 초안 색칠 지도 4장 (설계서 2026-10-12 6장). 사용: godot --headless -s tools/draft_first_island.gd
## 결과: res://maps/first_island/{height,zones,paths,markers}.png (1024², 1px = 1m, 중심 = 원점, 위 = 북쪽 −z)
## 사용자가 이 그림 위에 Notein으로 덧칠해 고친다. 색은 MapLegend 범례만 쓴다.

const S := 1024
const OUT := "res://maps/first_island/"

var noise := FastNoiseLite.new()


func _initialize() -> void:
	noise.seed = 7
	noise.frequency = 0.012
	var hb := MapLegend.HEIGHT
	var height := _blank(hb[0]["color"])
	# 섬 윤곽: 얕은 바다 → 해변 → 평지 (가장자리는 노이즈로 들쭉날쭉)
	_blob(height, Vector2(0, 0), Vector2(455, 455), hb[1]["color"], 40.0)
	_blob(height, Vector2(0, 0), Vector2(425, 425), hb[2]["color"], 40.0)
	_blob(height, Vector2(0, 10), Vector2(395, 395), hb[3]["color"], 40.0)
	# 북쪽 산덩이 (샘): 언덕 → 고원 → 산 → 고산
	_blob(height, Vector2(0, -320), Vector2(330, 150), hb[4]["color"], 30.0)
	_blob(height, Vector2(-10, -345), Vector2(250, 110), hb[5]["color"], 25.0)
	_blob(height, Vector2(-40, -375), Vector2(150, 70), hb[6]["color"], 20.0)
	_blob(height, Vector2(-30, -395), Vector2(70, 38), hb[7]["color"], 10.0)
	# 서쪽 고원 + 협곡 (가운데를 평지로 파고 양쪽 절벽 선)
	_blob(height, Vector2(-300, -10), Vector2(150, 235), hb[5]["color"], 25.0)
	_line(height, [Vector2(-262, -230), Vector2(-255, -80), Vector2(-248, 60), Vector2(-240, 190)], hb[3]["color"], 26)
	_line(height, [Vector2(-276, -230), Vector2(-269, -80), Vector2(-262, 60), Vector2(-254, 190)], MapLegend.CLIFF, 3)
	_line(height, [Vector2(-248, -230), Vector2(-241, -80), Vector2(-234, 60), Vector2(-226, 190)], MapLegend.CLIFF, 3)
	# 북쪽 바위벽 (수문 1): 고원 남쪽 끝 절벽
	_line(height, [Vector2(-150, -250), Vector2(-60, -262), Vector2(40, -262), Vector2(130, -248)], MapLegend.CLIFF, 3)
	# 동쪽 숲 언덕, 동남 거점 언덕, 전망대 언덕
	_blob(height, Vector2(270, -60), Vector2(165, 195), hb[4]["color"], 30.0)
	_blob(height, Vector2(255, 230), Vector2(60, 45), hb[4]["color"], 12.0)
	_blob(height, Vector2(300, -250), Vector2(55, 45), hb[5]["color"], 10.0)
	_save(height, "height.png")

	var zc := MapLegend.ZONES
	var zones := _blank(Color.WHITE)   # 비어 있음 = 초원
	_blob(zones, Vector2(0, 0), Vector2(440, 440), zc[0]["color"], 40.0)
	_ring(zones, Vector2(0, 0), 398, 440, zc[5]["color"], 40.0)                 # 해안
	_blob(zones, Vector2(0, -300), Vector2(320, 120), zc[2]["color"], 30.0)     # 침엽수 (산기슭)
	_blob(zones, Vector2(-40, -380), Vector2(170, 80), zc[4]["color"], 20.0)    # 고지·바위산
	_blob(zones, Vector2(265, -50), Vector2(160, 185), zc[1]["color"], 30.0)    # 활엽수
	_blob(zones, Vector2(-300, -10), Vector2(140, 220), zc[6]["color"], 25.0)   # 황무지 (서쪽 고원)
	_blob(zones, Vector2(0, -150), Vector2(95, 55), zc[6]["color"], 15.0)       # 황무지 (탑 북쪽)
	_ring(zones, Vector2(0, -40), 58, 100, zc[3]["color"], 12.0)                # 습지 (저수호 둘레)
	_blob(zones, Vector2(0, 330), Vector2(70, 50), zc[0]["color"], 0.0)         # 마을 주변은 초원
	_save(zones, "zones.png")

	var pc := MapLegend.PATHS
	var paths := _blank(Color.WHITE)
	# 수로: 샘 → 수문 1 → 저수호 / 저수호 → 마을 우물 / 서쪽(수문 2)·동남(수문 3) 갈래
	_line(paths, [Vector2(-30, -390), Vector2(-20, -300), Vector2(0, -258), Vector2(0, -150), Vector2(0, -100)], pc[2]["color"], 5)
	_line(paths, [Vector2(0, 25), Vector2(0, 150), Vector2(0, 300)], pc[2]["color"], 5)
	_line(paths, [Vector2(-60, -60), Vector2(-160, -40), Vector2(-240, -20), Vector2(-330, 0)], pc[2]["color"], 5)
	_line(paths, [Vector2(55, 0), Vector2(150, 120), Vector2(250, 220)], pc[2]["color"], 5)
	# 흙길: 마을 ↔ 둑 남쪽, 마을 ↔ 수문 3, 마을 ↔ 서쪽 다리, 둑 북쪽 ↔ 수문 1
	_line(paths, [Vector2(10, 310), Vector2(25, 180), Vector2(20, 30)], pc[0]["color"], 4)
	_line(paths, [Vector2(30, 320), Vector2(150, 290), Vector2(240, 245)], pc[0]["color"], 4)
	_line(paths, [Vector2(-20, 315), Vector2(-150, 230), Vector2(-240, 125)], pc[0]["color"], 4)
	_line(paths, [Vector2(-20, -100), Vector2(-60, -180), Vector2(-40, -240)], pc[0]["color"], 4)
	# 고대 포장길: 저수호 동쪽 ↔ 동쪽 폐허 ↔ 전망대
	_line(paths, [Vector2(65, -40), Vector2(180, 80)], pc[1]["color"], 6)
	_line(paths, [Vector2(180, 80), Vector2(250, -100), Vector2(300, -240)], pc[1]["color"], 6)
	_save(paths, "paths.png")

	var mk := MapLegend.MARKERS
	var markers := _blank(Color.WHITE)
	_dot(markers, Vector2(0, 335), mk.start)
	_dot(markers, Vector2(0, 300), mk.village)
	_dot(markers, Vector2(0, -40), mk.lake)
	_dot(markers, Vector2(0, -30), mk.tower, 2)
	_dot(markers, Vector2(0, -268), mk.sluice)     # 수문 1: 북쪽 바위벽 위
	_dot(markers, Vector2(-330, 0), mk.sluice)     # 수문 2: 협곡 건너 서쪽
	_dot(markers, Vector2(255, 230), mk.sluice)    # 수문 3: 동남 거점
	_dot(markers, Vector2(-150, 150), mk.ruin)
	_dot(markers, Vector2(180, 80), mk.ruin)
	_dot(markers, Vector2(-60, -200), mk.ruin)
	_dot(markers, Vector2(300, -250), mk.lookout)
	_dot(markers, Vector2(-330, 250), mk.lookout)
	_dot(markers, Vector2(-248, 120), mk.bridge)
	_save(markers, "markers.png")
	print("draft done")
	quit()


func _blank(c: Color) -> Image:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _px(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x + S / 2.0), int(p.y + S / 2.0))


## 노이즈로 가장자리가 흔들리는 타원 칠하기 (월드 m)
func _blob(img: Image, c: Vector2, r: Vector2, col: Color, wobble: float) -> void:
	var lo := _px(c - r - Vector2.ONE * wobble)
	var hi := _px(c + r + Vector2.ONE * wobble)
	for y in range(maxi(lo.y, 0), mini(hi.y + 1, S)):
		for x in range(maxi(lo.x, 0), mini(hi.x + 1, S)):
			var w := Vector2(x - S / 2.0, y - S / 2.0)
			var d := (w - c) / r
			var a := d.angle()
			var edge := 1.0 + noise.get_noise_2d(cos(a) * 60.0 + c.x, sin(a) * 60.0 + c.y) * wobble / maxf(r.x, r.y)
			if d.length() <= edge:
				img.set_pixel(x, y, col)


func _ring(img: Image, c: Vector2, r0: float, r1: float, col: Color, wobble: float) -> void:
	for y in range(maxi(int(c.y - r1 - wobble) + S / 2, 0), mini(int(c.y + r1 + wobble) + S / 2 + 1, S)):
		for x in range(maxi(int(c.x - r1 - wobble) + S / 2, 0), mini(int(c.x + r1 + wobble) + S / 2 + 1, S)):
			var w := Vector2(x - S / 2.0, y - S / 2.0) - c
			var n := noise.get_noise_2d(w.x * 0.5, w.y * 0.5) * wobble
			var d := w.length()
			if d >= r0 + n and d <= r1 + n:
				img.set_pixel(x, y, col)


## 굵은 선 (점 사이를 원으로 찍어 잇기)
func _line(img: Image, pts: Array, col: Color, width: int) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b))
		for k in n + 1:
			_disc(img, a.lerp(b, float(k) / maxf(n, 1)), width / 2.0, col)


func _disc(img: Image, p: Vector2, rad: float, col: Color) -> void:
	var c := _px(p)
	var ri := int(ceil(rad))
	for y in range(c.y - ri, c.y + ri + 1):
		for x in range(c.x - ri, c.x + ri + 1):
			if x >= 0 and y >= 0 and x < S and y < S and Vector2(x - c.x, y - c.y).length() <= maxf(rad, 0.5):
				img.set_pixel(x, y, col)


func _dot(img: Image, p: Vector2, col: Color, rad := 4) -> void:
	_disc(img, p, rad, col)


func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT + name)
	img.save_png(path)
	print("saved ", path)
