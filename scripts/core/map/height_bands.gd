class_name HeightBands
extends RefCounted
## 높이 색 띠 지도 → 높이(m). 노드 비의존, 결정적.
## 순서: 빈칸 = 가까운 칠한 칸(BFS) → 가장자리 깊은 바다 → 절벽 선 2px 팽창(장벽)
##       → 장벽을 넘지 않는 상자 평활화 3회 → 저주파 굴곡(바다·절벽 근처는 0).

const EDGE_M := 32.0            ## 가장자리 깊은 바다 폭 (1024 기준 px, 크기에 비례)
const DEEP_SEA := -14.0
const BARRIER_GROW := 2         ## 절벽 선 팽창 (px) — 선이 끊겨도 평활화가 새지 않게
const PASSES := 3
const NOISE_PERIOD := 40.0      ## 굴곡 주기 (px)
const DETAIL_FADE_NEAR := 6.0   ## 바다·절벽에서 이 거리 안은 굴곡 0
const DETAIL_FADE_FAR := 12.0   ## 이 거리 밖은 굴곡 전체


## bands: 높이 팔레트 인덱스(0~7 = 띠, 그 외/−1 = 비어 있음), cliff: 1 = 절벽 선 칸. 반환: 행 우선 높이 (m).
## edge_sea = false 이면 강제 깊은 바다 테두리를 만들지 않는다 (칠한 곳만 바다).
## 평활화 한 번의 상자 반경 = smooth_radius / 2 (3회 반복 → 실효 퍼짐 ≈ 0.54 × smooth_radius 표준편차).
static func build(bands: PackedInt32Array, size: int, cliff: PackedByteArray, smooth_radius := 12.0, detail := 1.5, seed := 1, edge_sea := true) -> PackedFloat32Array:
	var n := size * size
	var h := _fill_targets(bands, size)

	# 가장자리 깊은 바다
	var edge := maxi(1, int(round(EDGE_M * size / 1024.0)))
	if edge_sea:
		_stamp_edge(h, size, edge)

	# 절벽 장벽
	var barrier := _dilate(cliff, size, BARRIER_GROW)

	# 평활화
	var r := maxi(1, int(round(smooth_radius * 0.5))) if smooth_radius > 0.0 else 0
	if r > 0:
		var tmp := PackedFloat32Array()
		tmp.resize(n)
		for _p in PASSES:
			_blur_lines(h, tmp, size, barrier, r, size, 1)     # 가로
			_blur_lines(tmp, h, size, barrier, r, 1, size)     # 세로
		if edge_sea:
			_stamp_edge(h, size, edge)

	# 굴곡
	if detail > 0.0:
		_add_detail(h, size, barrier, detail, seed)
	return h


## 칠한 칸 = 띠 목표 높이, 빈 칸 = 가장 가까운 칠한 칸 (4방향 BFS, 먼저 닿은 쪽).
static func _fill_targets(bands: PackedInt32Array, size: int) -> PackedFloat32Array:
	var n := size * size
	var h := PackedFloat32Array()
	h.resize(n)
	var targets := PackedFloat32Array()
	for e in MapLegend.HEIGHT:
		targets.append(e["h"])
	var done := PackedByteArray()
	done.resize(n)
	var queue := PackedInt32Array()
	queue.resize(n)
	var qn := 0
	for i in n:
		var b := bands[i]
		if b >= 0 and b < targets.size():
			h[i] = targets[b]
			done[i] = 1
			queue[qn] = i
			qn += 1
	if qn == 0:
		h.fill(DEEP_SEA)
		return h
	if qn == n:
		return h
	var head := 0
	while head < qn:
		var i := queue[head]
		head += 1
		var x := i % size
		var v := h[i]
		if x > 0 and done[i - 1] == 0:
			done[i - 1] = 1; h[i - 1] = v; queue[qn] = i - 1; qn += 1
		if x < size - 1 and done[i + 1] == 0:
			done[i + 1] = 1; h[i + 1] = v; queue[qn] = i + 1; qn += 1
		if i >= size and done[i - size] == 0:
			done[i - size] = 1; h[i - size] = v; queue[qn] = i - size; qn += 1
		if i < n - size and done[i + size] == 0:
			done[i + size] = 1; h[i + size] = v; queue[qn] = i + size; qn += 1
	return h


static func _stamp_edge(h: PackedFloat32Array, size: int, edge: int) -> void:
	for y in size:
		var row := y * size
		if y < edge or y >= size - edge:
			for x in size:
				h[row + x] = DEEP_SEA
		else:
			for x in edge:
				h[row + x] = DEEP_SEA
				h[row + size - 1 - x] = DEEP_SEA


## 정사각형(체비쇼프) 팽창, 분리형. 반환 0/1.
static func _dilate(mask: PackedByteArray, size: int, grow: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(size * size)
	var out := PackedByteArray()
	out.resize(size * size)
	for y in size:
		var row := y * size
		var last := -1000000
		# 왼쪽 → 오른쪽: 마지막 1에서 grow 안
		for x in size:
			if mask[row + x] != 0:
				last = x
			if x - last <= grow:
				tmp[row + x] = 1
		last = 1000000
		for x in range(size - 1, -1, -1):
			if mask[row + x] != 0:
				last = x
			if last - x <= grow:
				tmp[row + x] = 1
	for x in size:
		var last := -1000000
		for y in size:
			if tmp[y * size + x] != 0:
				last = y
			if y - last <= grow:
				out[y * size + x] = 1
		last = 1000000
		for y in range(size - 1, -1, -1):
			if tmp[y * size + x] != 0:
				last = y
			if last - y <= grow:
				out[y * size + x] = 1
	return out


## 선 단위 상자 평활화. 장벽 칸은 값을 그대로 두고 평균에도 넣지 않으며,
## 창은 장벽을 만나면 거기서 끊긴다 (= 장벽을 넘어 섞이지 않음, 기여 칸 수로 정규화).
## line_stride: 다음 줄까지 간격, step: 줄 안에서 다음 칸까지 간격.
static func _blur_lines(src: PackedFloat32Array, dst: PackedFloat32Array, size: int, barrier: PackedByteArray, r: int, line_stride: int, step: int) -> void:
	for line in size:
		var base := line * line_stride
		var k := 0
		while k < size:
			var idx := base + k * step
			if barrier[idx] != 0:
				dst[idx] = src[idx]
				k += 1
				continue
			var e := k
			while e < size and barrier[base + e * step] == 0:
				e += 1
			# 구간 [k, e) 안에서 슬라이딩 창
			var sum := 0.0
			var lo := k
			var hi := k - 1
			for x in range(k, e):
				var nh := mini(e - 1, x + r)
				while hi < nh:
					hi += 1
					sum += src[base + hi * step]
				var nl := maxi(k, x - r)
				while lo < nl:
					sum -= src[base + lo * step]
					lo += 1
				dst[base + x * step] = sum / float(hi - lo + 1)
			k = e


static func _add_detail(h: PackedFloat32Array, size: int, barrier: PackedByteArray, detail: float, seed: int) -> void:
	var n := size * size
	# 바다·절벽까지의 거리 (체인퍼 3-4, 단위 1/3 px)
	var dist := PackedInt32Array()
	dist.resize(n)
	var big := 1 << 20
	for i in n:
		dist[i] = 0 if (barrier[i] != 0 or h[i] < 0.5) else big
	for y in size:
		for x in size:
			var i := y * size + x
			var d := dist[i]
			if d == 0:
				continue
			if x > 0:
				d = mini(d, dist[i - 1] + 3)
			if y > 0:
				d = mini(d, dist[i - size] + 3)
				if x > 0:
					d = mini(d, dist[i - size - 1] + 4)
				if x < size - 1:
					d = mini(d, dist[i - size + 1] + 4)
			dist[i] = d
	for y in range(size - 1, -1, -1):
		for x in range(size - 1, -1, -1):
			var i := y * size + x
			var d := dist[i]
			if d == 0:
				continue
			if x < size - 1:
				d = mini(d, dist[i + 1] + 3)
			if y < size - 1:
				d = mini(d, dist[i + size] + 3)
				if x < size - 1:
					d = mini(d, dist[i + size + 1] + 4)
				if x > 0:
					d = mini(d, dist[i + size - 1] + 4)
			dist[i] = d

	# 저주파 노이즈: 1/4 해상도로 만들어 쌍선형으로 키움 (8비트 계단 제거)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed
	noise.frequency = 4.0 / NOISE_PERIOD
	var cs := maxi(2, size / 4)
	var img := noise.get_image(cs, cs, false, false, false)
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var data := img.get_data()    # L8
	var near3 := DETAIL_FADE_NEAR * 3.0
	var span3 := (DETAIL_FADE_FAR - DETAIL_FADE_NEAR) * 3.0
	for i in n:
		var d := dist[i]
		if d <= near3:
			continue
		var w := minf(1.0, (d - near3) / span3)
		w = w * w * (3.0 - 2.0 * w)
		h[i] += (data[i] / 127.5 - 1.0) * detail * w
