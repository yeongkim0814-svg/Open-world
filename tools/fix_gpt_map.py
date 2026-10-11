#!/usr/bin/env python3
"""GPT 지도(maps/first_island/source_gpt/*.png, 2000²) → 설계서 11장(A2) 보정 → maps/first_island/*.png (2048², 1px = 1m).

보정 (사용자 프롬프트 기준):
- 높이(A3): GPT '산'·'고산' 띠(평평한 탁자)를 고원(45m)으로 낮추고 안쪽 절벽 고리 선을 지움 → 산 모양은 굽기의
  봉우리 도장(정상 350m, 절벽대 + 오르는 틈 3곳)이 만든다. 봉우리 표식 = 저수호 자리.
- 표식: 수문 3곳(해안 마을 북쪽 · 북동쪽 산 아래 · 동남쪽 산 중턱), 해안 마을을 스폰 서쪽 해안으로, 산마을(새 색),
  전망대를 남서 절벽 해안 위로, 다리 = 길이 개천을 건너는 곳.
- 개천(새 길 종류): 수문 A → 해안 마을 → 바다 / 수문 C → 폭포 → A 개천 상류 합류 / 수문 B → 동쪽 바다.
- 구역(A3): 첫 지역은 초원·활엽수림만 (침엽수 → 활엽수, 고지·습지·해안·황무지 → 초원).
사용: python3 tools/fix_gpt_map.py   (결정적)
"""
import json, math, os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "maps", "first_island")
SRC = os.path.join(ROOT, "source_gpt")
N = 2048
WORLD = 2048.0

def hx(s): return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
H = {k: hx(v) for k, v in {"deep": "1F3A5F", "shal": "4F81BD", "beach": "F2E6B8", "plain": "9BBB59", "hill": "C4D79B",
     "plat": "E3B46A", "mtn": "B07A4A", "high": "7F6A93", "cliff": "E0218A"}.items()}
Z = {k: hx(v) for k, v in {"meadow": "A9D18E", "broadleaf": "548235", "conifer": "375623", "wetland": "5FB3B3",
     "highland": "A6A6A6", "coast": "FFE699", "wasteland": "C55A11"}.items()}
P = {"dirt": hx("8B5A2B"), "paved": hx("404040"), "aqueduct": hx("2E75B6"), "stream": hx("6FA8DC")}
M = {"start": hx("000000"), "tower": hx("FF0000"), "lake": hx("00B0F0"), "sluice": hx("FF8C00"), "village": hx("FFFF00"),
     "hill_village": hx("FFC000"), "ruin": hx("7030A0"), "lookout": hx("FF66CC"), "bridge": hx("00FF00"),
     "peak": hx("800000")}
WHITE = (255, 255, 255)

LAKE = (26.0, -173.0)
MARKERS = [
    ("start", 700, 690), ("lake", 26, -173), ("tower", 38, -173), ("peak", 26, -190),
    ("village", 430, 735),            # 해안 마을: 스폰 서쪽 해안
    ("hill_village", -60, 215),       # 산마을: 남쪽 어깨(고리 틈 아래), 동남 폭포가 보이는 쪽
    ("sluice", 430, 520),             # A: 해안 마을 북쪽
    ("sluice", 300, 115),             # C: 동남쪽 산 중턱
    ("sluice", 600, -470),            # B: 북동쪽 산 아래
    ("ruin", -233, -333), ("ruin", -420, 300),
    ("lookout", -300, 612),           # 남서 절벽 해안 위
]
STREAMS = [
    [(430, 520), (425, 600), (432, 680), (436, 760), (440, 860)],                     # A → 해안 마을 → 바다
    [(300, 115), (320, 200), (345, 290), (380, 380), (410, 470), (428, 585)],          # C → 폭포 → A 상류 합류
    [(600, -470), (660, -480), (720, -500), (800, -510)],                             # B → 동쪽 바다
]
DIRT = [
    [(700, 690), (600, 700), (500, 720), (430, 735)],                                 # 스폰 → 해안 마을
    [(430, 735), (450, 640), (440, 520)],                                             # 해안 마을 → 수문 A
    [(430, 735), (300, 620), (150, 450), (40, 300), (-60, 215)],                       # 해안 마을 → 산마을
    [(-60, 215), (-20, 140), (-40, 60), (0, -20)],                                    # 산마을 → 고리 틈(남) → 정상
    [(300, 115), (200, 160), (80, 200), (-60, 215)],                                  # 산마을 ↔ 수문 C
    [(-300, 640), (-200, 520), (-60, 215)],                                           # 전망대 ↔ 산마을
]
WATERFALL = (388, 402, 45)   # 개천 C가 고원(45m)→언덕(20m) 경계를 지나는 곳: 반경 45m 안의 띠 경계를 절벽으로 = 폭포 자리


def w2p(x, z): return (round((x + WORLD / 2) * (N - 1) / WORLD), round((z + WORLD / 2) * (N - 1) / WORLD))
def near(c, pal, thr=3600):
    k = min(pal, key=lambda n: sum((a - b) ** 2 for a, b in zip(c, pal[n])))
    return k if sum((a - b) ** 2 for a, b in zip(c, pal[k])) <= thr else None


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGB").resize((N, N), Image.NEAREST)


def clean_height(im):
    """GPT 원본의 흐린 펜 경계(분홍 절벽 선 + 남색 바다가 섞인 색)가 엉뚱한 띠(산·고산)로 읽혀 해안에 가시가 솟는 것을 막는다:
    모든 픽셀을 가장 가까운 범례색으로 맞춘 뒤, 절벽 선이 아닌 픽셀은 5×5 최빈값으로 외톨이 픽셀을 지운다."""
    from PIL import ImageFilter
    names = list(H.keys())
    idx = Image.new("L", (N, N)); ip = idx.load(); px = im.load()
    for y in range(N):
        for x in range(N):
            c = px[x, y]
            ip[x, y] = min(range(len(names)), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, H[names[i]])))
    mode = idx.filter(ImageFilter.ModeFilter(5)); mp = mode.load()
    ci = names.index("cliff")
    out = Image.new("RGB", (N, N)); op = out.load()
    for y in range(N):
        for x in range(N):
            k = ip[x, y] if ip[x, y] == ci else mp[x, y]
            if k == ci and ip[x, y] != ci:
                # 절벽 선 바로 옆: 주변 7×7에서 절벽이 아닌 가장 흔한 띠 (섞인 색이 엉뚱한 띠로 남지 않게)
                from collections import Counter
                votes = Counter(ip[min(max(x + dx, 0), N - 1), min(max(y + dy, 0), N - 1)]
                                for dx in range(-3, 4) for dy in range(-3, 4))
                votes.pop(ci, None)
                k = votes.most_common(1)[0][0] if votes else ip[x, y]
            op[x, y] = H[names[k]]
    # 해안 절벽 선 바깥(바다 쪽)에 남은 1~2px 띠 조각 = 절벽과 바다 사이 지느러미 벽이 됨 → 바다로
    sea = (names.index("deep"), names.index("shal"))
    fix = []
    for y in range(N):
        for x in range(N):
            if ip[x, y] in sea or ip[x, y] == ci:
                continue
            near_cliff = near_sea = None
            for dx in range(-4, 5):
                for dy in range(-4, 5):
                    v = ip[min(max(x + dx, 0), N - 1), min(max(y + dy, 0), N - 1)]
                    if v == ci: near_cliff = True
                    elif v in sea: near_sea = v
            if near_cliff and near_sea is not None:
                fix.append((x, y, near_sea))
    for x, y, v in fix:
        op[x, y] = H[names[v]]
    print("coast slivers -> sea", len(fix))
    return out


def fix_height():
    im = clean_height(load("height")); px = im.load()
    lx, lz = w2p(*LAKE)
    for y in range(N):
        for x in range(N):
            k = near(px[x, y], H)
            if k in ("mtn", "high"):
                px[x, y] = H["plat"]
            elif k == "cliff" and math.hypot(x - lx, y - lz) * WORLD / N < 450:
                px[x, y] = H["plat"]   # 정상 절벽 고리는 봉우리 도장이 만든다
    wx, wz, wr = WATERFALL
    cx, cy = w2p(wx, wz); rp = int(wr * N / WORLD)
    marks = []
    for y in range(cy - rp, cy + rp + 1):
        for x in range(cx - rp, cx + rp + 1):
            if math.hypot(x - cx, y - cy) <= rp and near(px[x, y], H) == "plat":
                if any(near(px[x + dx, y + dy], H) == "hill" for dx in (-2, 0, 2) for dy in (-2, 0, 2)):
                    marks.append((x, y))
    for x, y in marks: px[x, y] = H["cliff"]
    print("waterfall cliff px", len(marks))
    return im


def fix_zones(height):
    """첫 지역 = 초원·활엽수림만 (설계서 12장 P20)."""
    z = load("zones"); zp = z.load()
    for y in range(N):
        for x in range(N):
            k = near(zp[x, y], Z)
            zp[x, y] = Z["broadleaf"] if k in ("broadleaf", "conifer") else Z["meadow"]
    return z


def fix_paths():
    p = load("paths"); dr = ImageDraw.Draw(p)
    # GPT 흙길 유지(오래된 마을 쪽 갈래도 그대로) + 새 길
    for line in DIRT: dr.line([w2p(*q) for q in line], fill=P["dirt"], width=4, joint="curve")
    for s in STREAMS: dr.line([w2p(*q) for q in s], fill=P["stream"], width=6, joint="curve")
    return p


def make_markers(paths):
    m = Image.new("RGB", (N, N), WHITE); dr = ImageDraw.Draw(m)
    pts = list(MARKERS)
    # 다리 = 흙길과 개천이 만나는 곳 (가장 가까운 교차점, 마을·수문에서 30m 이상 떨어진 곳)
    pp = paths.load()
    seen = set()
    for y in range(0, N, 3):
        for x in range(0, N, 3):
            if near(pp[x, y], {"stream": P["stream"]}, 900):
                for dx, dy in ((5, 0), (-5, 0), (0, 5), (0, -5)):
                    q = pp[min(max(x + dx, 0), N - 1), min(max(y + dy, 0), N - 1)]
                    if near(q, {"dirt": P["dirt"]}, 900):
                        wx, wz = x * WORLD / (N - 1) - WORLD / 2, y * WORLD / (N - 1) - WORLD / 2
                        if all(math.hypot(wx - a, wz - b) > 30 for _, a, b in pts) and all(math.hypot(wx - a, wz - b) > 60 for a, b in seen):
                            seen.add((wx, wz)); pts.append(("bridge", wx, wz))
    for kind, x, z in pts:
        cx, cy = w2p(x, z); r = 3 if kind == "tower" else 5
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=M[kind])
    return m, pts


def main():
    h = fix_height(); z = fix_zones(h); p = fix_paths(); m, pts = make_markers(p)
    for name, im in (("height", h), ("zones", z), ("paths", p), ("markers", m)):
        im.save(os.path.join(ROOT, name + ".png"))
    with open(os.path.join(ROOT, "map.json"), "w") as f:
        json.dump({"world": 2048, "size": 2048, "min_h": -20, "max_h": 420, "smooth_radius": 40, "edge_sea": False,
                   "peak_height": 350, "peak_radius": 700, "summit_radius": 180, "lake_radius": 110, "tower_radius": 45}, f, indent=1)
    hp = h.load()
    for kind, x, zz in pts:
        print(f"{kind:13s} ({x:6.0f},{zz:6.0f})  band={near(hp[w2p(x, zz)], H)}")


if __name__ == "__main__":
    main()
