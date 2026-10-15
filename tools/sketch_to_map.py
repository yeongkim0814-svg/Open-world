#!/usr/bin/env python3
"""손그림 등고선 지도 → 굽기 입력 PNG (heightmap · zones · paths · markers).

사용: python3 tools/sketch_to_map.py [--debug DIR]
읽기: maps/first_island/source_sketch/sketch.jpg (범례 포함 원본 사진/내보내기)
쓰기: maps/first_island/{heightmap,zones,paths,markers}.png  (height.png 는 heightmap 이 있으면 무시됨)
필요: Python 3 + numpy, scipy, scikit-image, Pillow

원리
1. 색 분리: 검정 = 등고선, 갈색 = 절벽, 남색/파랑 선 = 해안선·숲 경계, 하늘색 = 강, 보라 = 수문, 노랑 = 해자,
   빨강 = 탑, 주황 = 마을. (JPEG 번짐 때문에 색상(H)·채도(S)·명도(V) 범위로 나눈다)
2. 선 끊김 잇기: 선 골격의 끝점에서 진행 방향 ±60도 안 45px 이내의 다른 선으로 잇는다. 가장자리 근처 끝은 가장자리까지.
3. 선(등고선·절벽·해안선)이 나누는 "띠 영역"마다 아래 등고선 높이(LEVELS)를 정한다.
   자동(정상에서 건넌 선 수)으로는 그림에서 생략된 등고선 때문에 틀려서, 라벨(25·50·…·300)을 기준으로 손으로 정한 표.
   영역 번호는 이 스크립트의 분할 결과에 묶여 있다 — 그림을 바꾸면 --debug 로 영역 지도를 보고 표를 다시 정할 것.
4. 영역마다 라플라스 보간: 경계값 = 이웃 띠와의 관계
   - 이웃이 한 단계 위/아래 등고선: 그 등고선 높이 (양쪽 연속)
   - 절벽: 위쪽 = 자기 띠 바닥, 아래쪽 = 위 띠 바닥 − 25 → 25m 벽 (그림에서 절벽이 등고선 한 칸을 대신함)
   - 두 단계 이상 차이(등고선 생략): 아래쪽 = 자기 띠 꼭대기, 위쪽 = 자기 띠 바닥 → 그 차만큼 벽
   - 바다: 높이 0 띠는 0.5m(해변), 그 밖(곶)은 자기 높이 → 바다 절벽
5. 협곡: 북서쪽 두 절벽 사이 강길을 수문 높이에서 협곡 입구까지 내려가는 바닥으로 판다.
6. 바다 깊이: 해안에서 멀어질수록 −14m 로.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as nd
from scipy.spatial import cKDTree
from skimage.draw import line as draw_line
from skimage.morphology import skeletonize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "maps", "first_island")
SRC = os.path.join(MAP_DIR, "source_sketch", "sketch.jpg")

FRAME = (0, 377, 1541, 1920)  # 원본에서 지도 테두리 (x0, y0, x1, y1) — 범례 아래 가로선 2개 사이
BRIDGE_R = 45                 # 끊긴 선 잇기 최대 거리 (px)
STEP = 25.0                   # 등고선 간격 (m)
SEA_DEPTH = -14.0
SEA_FALL_M = 45.0             # 해안에서 이 거리 (m) 정도면 거의 최대 깊이
BEACH_H = 0.5

# 띠 영역 번호 → 아래 등고선 높이 (m). None = 바다.
LEVELS = {
    1: 50, 2: 125, 3: 100, 4: 75, 5: 25, 6: 0, 7: None, 8: 150, 9: 150, 10: 25,
    11: 150, 12: 175, 13: 175, 14: 100, 15: 200, 16: 200, 17: 175, 18: 175, 19: 225, 20: 200,
    21: 150, 22: 200, 23: 225, 24: 200, 25: 175, 26: 100, 27: 225, 28: 250, 29: 200, 30: 175,
    31: 175, 32: 225, 33: 175, 34: 275, 35: 300, 36: 275, 37: 175, 38: 125, 39: 50, 40: 300,
    41: 300, 42: 25, 43: 100, 44: 25, 45: 0, 46: 150, 47: 100, 48: 25, 49: 50, 50: 25,
    51: 25, 52: 25, 53: 25, 54: 25, 55: 25, 56: 25, 57: 25, 58: 25, 59: 25, 60: 25,
    61: None, 62: 50, 63: 50,
}
SUMMIT_DOME = 8.0      # 꼭대기 띠(더 높은 이웃 없음) 가운데를 이만큼 둥글게 올림 (m)
HEADLAND_DOME = 4.0
SMOOTH_PX = 4.0        # 그린 절벽 밖 지형 다듬기 (px, 약 5m)
FOREST_SIGMA = 35.0    # 빗금 밀도를 재는 반경 (px)
FOREST_DENSITY = 0.008 # 이 밀도 넘으면 숲

# 표식 (원본 그림 좌표 px) — 점·빗금 중심을 그림에서 읽은 값
MARKERS = [
    ("start", 873, 1728),
    ("lookout", 158, 1847),        # 전망대 (observatory)
    ("tower", 652, 782),
    ("lake", 660, 772),            # 해자 = 저수호 도장 (탑 둘레 고리 물)
    ("sluice", 420, 592),
    ("sluice", 790, 922),
    ("sluice", 628, 1297),
    ("hill_village", 805, 995),    # 비탈 마을 (평탄화 없음)
    ("hill_village", 655, 1515),   # 절벽 위 마을 (평탄화하면 절벽이 뭉개짐)
]
# 협곡: 강 중심선 위 (원본 px, 바닥 높이 m) — 수문 → 두 절벽 사이 → 입구 → 북쪽 가장자리 (그 너머 지역으로 흘러감)
CANYON = [(420, 592, 228), (427, 542, 214), (400, 527, 205), (365, 509, 192), (345, 497, 184), (320, 472, 172),
          (295, 457, 162), (287, 447, 156), (296, 420, 148), (302, 397, 143), (305, 378, 138)]
CANYON_HALF_W = 6              # 협곡 바닥 반폭 (px ≈ 8m)
CANYON_WALL_PX = 3             # 바닥 → 원지형까지 벽 폭 (px)
# 숲 (구역 지도 색 인덱스는 MapLegend.ZONES 순서: 활엽수 숲)
FOREST_COLOR = (0x54, 0x82, 0x35)
HIGHLAND_COLOR = (0xA6, 0xA6, 0xA6)
HIGHLAND_H = 230.0
COAST_COLOR = (0xFF, 0xE6, 0x99)
STREAM_COLOR = (0x6F, 0xA8, 0xDC)
MARKER_COLORS = {
    "start": (0, 0, 0), "tower": (255, 0, 0), "lake": (0, 0xB0, 0xF0), "sluice": (0xFF, 0x8C, 0),
    "village": (0xFF, 0xFF, 0), "hill_village": (0xFF, 0xC0, 0), "ruin": (0x70, 0x30, 0xA0),
    "lookout": (0xFF, 0x66, 0xCC), "bridge": (0, 0xFF, 0),
}


def hsv(img):
    mx = img.max(2)
    mn = img.min(2)
    d = mx - mn + 1e-6
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return h, s, mx


def hue_in(h, a, b):
    return (h >= a) & (h <= b) if a <= b else (h >= a) | (h <= b)


def classify(rgb):
    h, s, v = hsv(rgb)
    # 겹치면 뒤 규칙이 이긴다 (영역 번호·LEVELS 표가 이 결과에 묶여 있으니 바꾸지 말 것)
    cls = np.zeros(h.shape, np.uint8)
    cls[(v < 0.42) & (s < 0.35)] = 1
    cls[hue_in(h, 205, 245) & (s > 0.55) & (v < 0.75)] = 2
    cls[hue_in(h, 200, 250) & (s > 0.12) & (s <= 0.55) & (v > 0.45) & (v < 0.9)] = 3
    cls[hue_in(h, 330, 25) & (s > 0.22) & (s < 0.7) & (v > 0.25) & (v < 0.75)] = 4
    cls[hue_in(h, 170, 200) & (s > 0.35) & (v > 0.5)] = 5
    cls[hue_in(h, 250, 290) & (s > 0.3)] = 6
    cls[hue_in(h, 8, 38) & (s > 0.55) & (v > 0.7)] = 7
    cls[hue_in(h, 40, 65) & (s > 0.45) & (v > 0.6)] = 8
    cls[hue_in(h, 335, 8) & (s > 0.7) & (v > 0.6)] = 9
    out = {}
    out["blue"] = cls == 3
    out["cliff"] = nd.binary_closing(cls == 4, iterations=2)
    out["river"] = hue_in(h, 170, 200) & (s > 0.18) & (v > 0.45)
    blk = (v < 0.78) & (s < 0.22) & (cls != 3) & (cls != 4)
    lb, n = nd.label(nd.binary_dilation(blk, iterations=1))
    sz = nd.sum(blk, lb, range(1, n + 1))
    out["contour"] = np.isin(lb, [i + 1 for i in range(n) if sz[i] >= 60]) & blk   # 숫자 라벨 같은 작은 덩어리 제외
    return out


def coast_mask(blue):
    """해안선 = 그림의 해안선을 따라 찍은 점들에 닿는 파란 선 덩어리 (숲 경계선과 같은 색이라 위치로 고른다)."""
    pts = [(1420, 5), (1440, 300), (1430, 550), (1450, 700), (1430, 850), (1330, 910), (1280, 1030), (1255, 1160),
           (1190, 1190), (1000, 1260), (910, 1290), (890, 1420), (640, 1410), (380, 1440), (170, 1380), (80, 1440), (3, 1445)]
    bl, _ = nd.label(nd.binary_dilation(blue, iterations=3))
    ids = set()
    for x, y in pts:
        w = bl[max(0, y - 12):y + 12, max(0, x - 12):x + 12]
        ids |= set(np.unique(w[w > 0]).tolist())
    return np.isin(bl, list(ids)) & blue


def bridge_lines(lines):
    """선 골격의 끊김을 잇는다. 반환: (골격, 이은 선)"""
    H, W = lines.shape
    L = skeletonize(nd.binary_dilation(lines, iterations=1))
    lab, n = nd.label(L, structure=np.ones((3, 3)))
    sz = nd.sum(L, lab, range(1, n + 1))
    L = np.isin(lab, [i + 1 for i in range(n) if sz[i] >= 15])
    lab, n = nd.label(L, structure=np.ones((3, 3)))
    nb = nd.convolve(L.astype(int), np.ones((3, 3)), mode="constant") - 1
    ey, ex = np.where(L & (nb == 1))
    ys, xs = np.where(L)
    tree = cKDTree(np.c_[xs, ys])
    add = np.zeros_like(L)
    for x, y in zip(ex, ey):
        bd = min(x, y, W - 1 - x, H - 1 - y)
        if bd <= 25:                      # 가장자리 근처 끝 → 가장자리까지
            tx, ty = x, y
            if bd == x:
                tx = 0
            elif bd == y:
                ty = 0
            elif bd == W - 1 - x:
                tx = W - 1
            else:
                ty = H - 1
            r_, c_ = draw_line(y, x, ty, tx)
            add[r_, c_] = True
            continue
        own = lab[y, x]
        idx = tree.query_ball_point([x, y], 10)
        pts = np.array([[xs[i], ys[i]] for i in idx if lab[ys[i], xs[i]] == own])
        d = np.array([x, y]) - pts.mean(0)
        nrm = np.linalg.norm(d)
        if nrm < 1e-3:
            continue
        d /= nrm
        best = None
        for i in tree.query_ball_point([x, y], BRIDGE_R):
            px, py = xs[i], ys[i]
            v = np.array([px - x, py - y])
            dist = np.linalg.norm(v)
            if dist < 3:
                continue
            if lab[py, px] == own and dist < BRIDGE_R:
                continue
            cos = v @ d / dist
            if cos < 0.5:
                continue
            score = dist * (2 - cos)
            if best is None or score < best[0]:
                best = (score, px, py)
        if best is not None:
            r_, c_ = draw_line(y, x, best[2], best[1])
            add[r_, c_] = True
    return L, add


def regions(bar):
    reg, rn = nd.label(~bar)
    rs = nd.sum(np.ones_like(reg), reg, range(1, rn + 1))
    keep = [i + 1 for i in range(rn) if rs[i] >= 300]
    rr = np.zeros_like(reg)
    for j, k in enumerate(keep):
        rr[reg == k] = j + 1
    return rr


def boundary_value(a, b, cliff):
    """띠 a(자기)·b(이웃) 경계에서 자기 쪽 높이."""
    if b is None:                        # 바다
        return BEACH_H if a == 0 else float(a)
    if b == a:
        return a + STEP / 2
    if b > a:                            # 이웃이 위
        if cliff or b >= a + 2 * STEP:
            return float(b - STEP)       # 절벽 / 생략된 등고선: 벽 아래
        return float(b)                  # 등고선
    if cliff or b <= a - 2 * STEP:
        return float(a)                  # 벽 위
    return float(a)                      # 아래 이웃 등고선 = 자기 바닥


def solve(rr, cliffd, levels):
    """영역마다 라플라스 (경계값은 4방향 이웃 영역과의 관계). 반환: 높이 (영역 밖 = nan)."""
    H, W = rr.shape
    lvl = np.full(rr.max() + 1, np.nan)
    for k, v in levels.items():
        if k <= rr.max():
            lvl[k] = np.nan if v is None else v
    land = (rr > 0) & ~np.isnan(lvl[rr])
    # 방향별: 이웃이 다른 영역이면 경계값
    bvals, bmask = [], []
    for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
        found = np.zeros((H, W), np.int32)
        hit_cliff = np.zeros((H, W), bool)
        for k in range(1, 14):
            sh = np.zeros_like(rr)
            sc = np.zeros((H, W), bool)
            ys0, ys1 = max(0, -dy * k), H - max(0, dy * k)
            xs0, xs1 = max(0, -dx * k), W - max(0, dx * k)
            sh[ys0:ys1, xs0:xs1] = rr[ys0 + dy * k:ys1 + dy * k, xs0 + dx * k:xs1 + dx * k]
            sc[ys0:ys1, xs0:xs1] = cliffd[ys0 + dy * k:ys1 + dy * k, xs0 + dx * k:xs1 + dx * k]
            hit_cliff |= sc & (found == 0)
            new = (found == 0) & (sh > 0) & (sh != rr)
            found[new] = sh[new]
            if k == 1:
                same = sh == rr
        boundary = land & ~same & (found > 0)
        val = np.full((H, W), np.nan, np.float32)
        ys, xs = np.where(boundary)
        for y, x in zip(ys, xs):
            a = levels[int(rr[y, x])]
            nb = levels.get(int(found[y, x]))
            val[y, x] = boundary_value(a, nb, bool(hit_cliff[y, x]))
        bvals.append(val)
        bmask.append(boundary)
    # 희소 연립방정식 (5점 라플라스, 경계 = 고정값, 지도 가장자리 = 기울기 0) — 대수 다중격자로 푼다
    import pyamg
    import scipy.sparse as sp
    idx = np.full((H, W), -1, np.int64)
    n = int(land.sum())
    idx[land] = np.arange(n)
    diag = np.zeros(n)
    rhs = np.zeros(n)
    rows, cols = [], []
    for (dy, dx), bv, bm in zip([(0, 1), (0, -1), (1, 0), (-1, 0)], bvals, bmask):
        ys, xs = np.where(land)
        ny, nx = ys + dy, xs + dx
        inside = (ny >= 0) & (ny < H) & (nx >= 0) & (nx < W)
        i_self = idx[ys, xs]
        b = bm[ys, xs]
        diag += b
        rhs += np.where(b, np.nan_to_num(bv[ys, xs]), 0)
        nyc, nxc = np.clip(ny, 0, H - 1), np.clip(nx, 0, W - 1)
        same = inside & ~b & (rr[nyc, nxc] == rr[ys, xs])
        diag += same
        rows.append(i_self[same])
        cols.append(idx[nyc[same], nxc[same]])
    rows = np.concatenate(rows)
    cols = np.concatenate(cols)
    A = sp.csr_matrix((np.concatenate([diag, -np.ones(rows.size)]),
                       (np.concatenate([np.arange(n), rows]), np.concatenate([np.arange(n), cols]))), shape=(n, n))
    # 경계가 하나도 없는 영역(고립) 대비: 아주 약한 고정
    rhs += 1e-6 * (lvl[rr][land] + STEP / 2)
    A = A + sp.identity(n) * 1e-6
    ml = pyamg.smoothed_aggregation_solver(A, symmetry="symmetric")
    x = ml.solve(rhs, tol=1e-8, maxiter=200)
    print(f"  보간: 미지수 {n}, 잔차 {np.linalg.norm(rhs - A @ x) / np.linalg.norm(rhs):.2e}")
    h = np.full((H, W), np.nan, np.float32)
    h[land] = x
    return h, land


def dome(h, rr, levels, land):
    """더 높은 이웃이 없는 띠(정상·곶)는 가운데를 둥글게."""
    for k, a in levels.items():
        if a is None:
            continue
        m = rr == k
        if not m.any():
            continue
        nbrs = np.unique(rr[nd.binary_dilation(m, iterations=14) & ~m])
        if any(levels.get(int(n)) is not None and levels[int(n)] > a for n in nbrs if n > 0):
            continue
        dt = nd.distance_transform_edt(nd.binary_dilation(m, iterations=6))
        amp = SUMMIT_DOME if a >= 250 else HEADLAND_DOME
        h[m] += amp * np.clip(dt[m] / 60.0, 0, 1) ** 0.7
    return h


def fill_gaps(h, valid, iters=400):
    """선(벽) 칸: 양옆 값 사이를 라플라스로 메워 경사 벽."""
    out = np.where(valid, h, 0.0)
    _, (iy, ix) = nd.distance_transform_edt(~valid, return_indices=True)
    out = np.where(valid, out, out[iy, ix])
    k = np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]], np.float32) / 4
    for _ in range(iters):
        sm = nd.convolve(out, k, mode="nearest")
        out = np.where(valid, out, sm)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--debug", help="영역 번호 지도 등 확인용 그림을 쓸 폴더")
    ap.add_argument("--size", type=int, default=2048)
    args = ap.parse_args()
    cfg = json.load(open(os.path.join(MAP_DIR, "map.json")))
    size = args.size
    min_h, max_h = float(cfg["min_h"]), float(cfg["max_h"])

    src = Image.open(SRC).convert("RGB").crop(FRAME)
    rgb = np.asarray(src).astype(np.float32) / 255
    H, W = rgb.shape[:2]
    c = classify(rgb)
    coast = coast_mask(c["blue"])
    forest_lines = c["blue"] & ~nd.binary_dilation(coast, iterations=2)
    L, add = bridge_lines(c["contour"] | c["cliff"] | coast)
    bar = nd.binary_dilation(L | add, iterations=2)
    rr = regions(bar)
    print(f"띠 영역 {rr.max()}개 (표 {len(LEVELS)}개)")
    if rr.max() != len(LEVELS):
        print("경고: 영역 수가 LEVELS 표와 다릅니다 — --debug 로 영역 지도를 보고 표를 고칠 것")
    cliffd = nd.binary_dilation(c["cliff"], iterations=4)

    h, land = solve(rr, cliffd, LEVELS)
    h = dome(h, rr, LEVELS, land)

    # 바다: 해안선에서 거리
    sea_reg = np.isin(rr, [k for k, v in LEVELS.items() if v is None])
    # 선 칸은 가장 가까운 영역을 따른다 → 바다 쪽 절반·바다 위 글씨(SPAWN 등)는 바다
    _, (iy, ix) = nd.distance_transform_edt(rr == 0, return_indices=True)
    sea_zone = sea_reg[iy, ix]
    land_all = fill_gaps(np.nan_to_num(h), land)
    # 그림에 그린 절벽이 아닌 곳은 부드럽게: 좁은 띠가 선에 먹혀 생긴 계단·벽을 비탈로 (그린 절벽·해안은 그대로)
    keep_sharp = nd.binary_dilation(c["cliff"], iterations=6) | nd.binary_dilation(sea_zone, iterations=6)
    soft = nd.gaussian_filter(land_all, SMOOTH_PX)
    wgt = nd.gaussian_filter((~keep_sharp).astype(np.float32), 3)
    land_all = land_all + (soft - land_all) * wgt
    dist_land = nd.distance_transform_edt(sea_zone)
    m_per_px = cfg["world"] / W
    sea_h = SEA_DEPTH * (1 - np.exp(-dist_land * m_per_px / SEA_FALL_M))
    full = np.where(sea_zone, np.minimum(sea_h, 0.0), land_all)

    # 협곡
    pts = [(x - FRAME[0], y - FRAME[1]) for x, y, _ in CANYON]
    floors = [f for _, _, f in CANYON]
    yy, xx = np.mgrid[0:H, 0:W]
    best_d = np.full((H, W), 1e9, np.float32)
    cfloor = np.zeros((H, W), np.float32)
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        vx, vy = x1 - x0, y1 - y0
        t = np.clip(((xx - x0) * vx + (yy - y0) * vy) / float(vx * vx + vy * vy), 0, 1)
        d = np.hypot(xx - (x0 + t * vx), yy - (y0 + t * vy))
        better = d < best_d
        best_d = np.where(better, d, best_d)
        cfloor = np.where(better, floors[i] + (floors[i + 1] - floors[i]) * t, cfloor)
    wall = np.clip((best_d - CANYON_HALF_W) / CANYON_WALL_PX, 0, 1)
    carved = cfloor + (full - cfloor) * wall
    full = np.where(best_d <= CANYON_HALF_W + CANYON_WALL_PX, np.minimum(full, carved), full)

    # 잔결 (±1.2m) — 바다 제외
    rng = np.random.default_rng(1)
    noise = np.zeros((H, W), np.float32)
    for period, amp in [(40, 1.0), (12, 0.35)]:
        g = rng.standard_normal((H // period + 3, W // period + 3)).astype(np.float32)
        noise += amp * nd.zoom(g, period, order=3)[:H, :W] / 1.0
    full = full + noise * np.clip(full / 3.0, 0, 1)

    # 지도 격자로
    hm = nd.zoom(full, (size / H, size / W), order=1)[:size, :size]
    t = np.clip((hm - min_h) / (max_h - min_h) * 255.0, 0, 255)
    r = np.floor(t).astype(np.int32)
    g = np.clip(np.round((t - r) * 256.0), 0, 255).astype(np.int32)
    g[r == 255] = 0
    enc = np.zeros((size, size, 3), np.uint8)
    enc[..., 0] = r
    enc[..., 1] = g
    Image.fromarray(enc).save(os.path.join(MAP_DIR, "heightmap.png"))
    print(f"heightmap.png {size}² — 높이 {hm.min():.1f} ~ {hm.max():.1f} m")

    # 구역: 숲(숲 경계선 안 빗금 영역), 높은 곳 = 고지, 해안 띠 = 해안, 나머지 = 초원(흰색)
    # 숲 = 빗금이 촘촘한 곳 (경계선이 군데군데 끊겨 영역 채우기로는 새어 나감 → 빗금 밀도로)
    hatch = (c["blue"] & ~nd.binary_dilation(coast, iterations=4)).astype(np.float32)
    dens = nd.gaussian_filter(hatch, FOREST_SIGMA)
    forest = nd.binary_fill_holes(nd.binary_closing(nd.binary_opening(dens > FOREST_DENSITY, iterations=8), iterations=25))
    forest_ids = list(range(1, nd.label(forest)[1] + 1))
    zones = np.full((H, W, 3), 255, np.uint8)
    zones[forest] = FOREST_COLOR
    zones[(full > HIGHLAND_H) & ~forest] = HIGHLAND_COLOR
    near_sea = nd.binary_dilation(sea_zone, iterations=12) & ~sea_zone & (full < 4) & ~forest
    zones[near_sea] = COAST_COLOR
    Image.fromarray(zones).resize((size, size), Image.NEAREST).save(os.path.join(MAP_DIR, "zones.png"))
    print(f"zones.png — 숲 영역 {len(forest_ids)}개")

    # 길: 강 = 개천 (협곡 안은 협곡 중심선)
    river = skeletonize(nd.binary_closing(c["river"], iterations=3))
    lab, n = nd.label(river, structure=np.ones((3, 3)))
    sz = nd.sum(river, lab, range(1, n + 1))
    river = np.isin(lab, [i + 1 for i in range(n) if sz[i] >= 25])
    rl, radd = bridge_lines(river)                 # 마을 빗금·절벽에 가려 끊긴 강을 잇는다
    river = rl | radd
    river &= ~sea_zone
    paths = Image.new("RGB", (W, H), (255, 255, 255))
    pimg = np.asarray(paths).copy()
    rv = nd.binary_dilation(river, iterations=2)
    pimg[rv] = STREAM_COLOR
    paths = Image.fromarray(pimg)
    dr = ImageDraw.Draw(paths)
    dr.line(pts, fill=STREAM_COLOR, width=5)          # 협곡 바닥 = 개천
    paths.resize((size, size), Image.NEAREST).save(os.path.join(MAP_DIR, "paths.png"))
    print(f"paths.png — 개천 {int(river.sum())} px")

    # 표식
    mk = Image.new("RGB", (size, size), (255, 255, 255))
    dr = ImageDraw.Draw(mk)
    for kind, x, y in MARKERS:
        mx = (x - FRAME[0]) * size / W
        my = (y - FRAME[1]) * size / H
        r_ = 4
        dr.ellipse((mx - r_, my - r_, mx + r_, my + r_), fill=MARKER_COLORS[kind])
    mk.save(os.path.join(MAP_DIR, "markers.png"))
    print(f"markers.png — 표식 {len(MARKERS)}개")

    if args.debug:
        os.makedirs(args.debug, exist_ok=True)
        rng = np.random.default_rng(11)
        pal = rng.integers(110, 250, (rr.max() + 1, 3)).astype(np.uint8)
        pal[0] = 0
        img = Image.fromarray(pal[rr])
        d2 = ImageDraw.Draw(img)
        try:
            f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
        except OSError:
            f = None
        for k in range(1, rr.max() + 1):
            m = rr == k
            dt = nd.distance_transform_edt(m)
            a = np.unravel_index(dt.argmax(), dt.shape)
            d2.text((a[1] - 16, a[0] - 10), f"{k}:{LEVELS.get(k)}", fill=(0, 0, 0), font=f)
        img.save(os.path.join(args.debug, "regions.png"))
        shade = np.clip((full - full.min()) / (full.max() - full.min()) * 255, 0, 255).astype(np.uint8)
        Image.fromarray(shade).save(os.path.join(args.debug, "height_gray.png"))
        print(f"확인용 그림: {args.debug}")


if __name__ == "__main__":
    sys.exit(main())
