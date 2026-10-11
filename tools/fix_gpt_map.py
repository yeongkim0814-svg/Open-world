#!/usr/bin/env python3
"""GPT 지도(maps/first_island/source_gpt/*.png, 2000²) → 설계서 11장(A2) 보정 → maps/first_island/*.png (2048², 1px = 1m).

보정 (사용자 프롬프트 기준):
- 높이: GPT '고산'(보라) 고원을 안쪽 절벽 고리(저수호에서 약 340m) 안 = 고산 160m, 밖 = 산 90m 어깨로 나눔
  → 아래는 완만, 위는 절벽 고리, 고리 틈(남·서) = 오르는 길.
- 표식: 수문 3곳(해안 마을 북쪽 · 북동쪽 산 아래 · 동남쪽 산 중턱), 해안 마을을 스폰 서쪽 해안으로, 산마을(새 색),
  전망대를 남서 절벽 해안 위로, 다리 = 길이 개천을 건너는 곳.
- 개천(새 길 종류): 수문 A → 해안 마을 → 바다 / 수문 C → 폭포 → A 개천 상류 합류 / 수문 B → 동쪽 바다.
- 구역: GPT가 강을 습지 띠로 칠한 것 제거, 해안 구역 = 해변 띠 근처, 개천·저수호 둘레 = 습지.
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
     "hill_village": hx("FFC000"), "ruin": hx("7030A0"), "lookout": hx("FF66CC"), "bridge": hx("00FF00")}
WHITE = (255, 255, 255)

LAKE = (26.0, -173.0)
MARKERS = [
    ("start", 700, 690), ("lake", 26, -173), ("tower", 38, -173),
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
WATERFALL = (343, 285, 45)   # 개천 C가 산(90m)→고원(45m) 경계를 지나는 곳: 반경 45m 안의 띠 경계를 절벽으로 = 폭포 자리


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
    return out


def fix_height():
    im = clean_height(load("height")); px = im.load()
    lx, lz = w2p(*LAKE)
    # 안쪽 절벽 고리 반경 R(각도): 저수호에서 250~450m 거리의 절벽 픽셀, 2° 칸 중앙값, 빈 칸(틈)은 보간
    bins = [[] for _ in range(180)]
    for y in range(0, N, 2):
        for x in range(0, N, 2):
            if near(px[x, y], {"cliff": H["cliff"]}):
                d = math.hypot(x - lx, y - lz) * WORLD / N
                if 250 <= d <= 450:
                    bins[int((math.degrees(math.atan2(y - lz, x - lx)) + 180) // 2) % 180].append(d)
    r = [sorted(b)[len(b) // 2] if b else None for b in bins]
    known = [i for i, v in enumerate(r) if v is not None]
    for i in range(180):
        if r[i] is None:
            a = max([k for k in known if k < i] or [known[-1] - 180])
            b = min([k for k in known if k > i] or [known[0] + 180])
            ra, rb = r[a % 180], r[b % 180]
            r[i] = ra + (rb - ra) * (i - a) / (b - a)
    for y in range(N):
        for x in range(N):
            if near(px[x, y], {"high": H["high"]}):
                d = math.hypot(x - lx, y - lz) * WORLD / N
                i = int((math.degrees(math.atan2(y - lz, x - lx)) + 180) // 2) % 180
                px[x, y] = H["high"] if d < r[i] else H["mtn"]
    wx, wz, wr = WATERFALL
    cx, cy = w2p(wx, wz); rp = int(wr * N / WORLD)
    marks = []
    for y in range(cy - rp, cy + rp + 1):
        for x in range(cx - rp, cx + rp + 1):
            if math.hypot(x - cx, y - cy) <= rp and near(px[x, y], H) == "mtn":
                if any(near(px[x + dx, y + dy], H) == "plat" for dx in (-2, 0, 2) for dy in (-2, 0, 2)):
                    marks.append((x, y))
    for x, y in marks: px[x, y] = H["cliff"]
    print("waterfall cliff px", len(marks))
    return im


def fix_zones(height):
    z = load("zones"); zp = z.load(); hp = height.load()
    src = z.copy(); sp = src.load()
    from collections import Counter
    for y in range(N):
        for x in range(N):
            k = near(zp[x, y], Z)
            hb = near(hp[x, y], H)
            if k in ("wetland", "coast"):
                # GPT가 강·해안을 띠로 칠한 곳 = 주변 구역의 다수결 (8방향 40m 표본)
                votes = Counter()
                for dx, dy in ((40, 0), (-40, 0), (0, 40), (0, -40), (28, 28), (-28, 28), (28, -28), (-28, -28)):
                    q = near(sp[min(max(x + dx, 0), N - 1), min(max(y + dy, 0), N - 1)], Z)
                    if q not in (None, "wetland", "coast"):
                        votes[q] += 1
                zp[x, y] = Z[votes.most_common(1)[0][0] if votes else "meadow"]
            if hb in ("deep", "shal", "beach"):
                zp[x, y] = Z["coast"]
    # 해변 띠에서 25m 안쪽까지 해안 구역 (팽창)
    coast = Image.new("L", (N, N)); cp = coast.load()
    for y in range(N):
        for x in range(N):
            if near(hp[x, y], H) == "beach": cp[x, y] = 255
    from PIL import ImageFilter
    coast = coast.filter(ImageFilter.MaxFilter(51))
    z.paste(Image.new("RGB", (N, N), Z["coast"]), mask=coast)
    dr = ImageDraw.Draw(z)
    for s in STREAMS: dr.line([w2p(*p) for p in s], fill=Z["wetland"], width=16, joint="curve")
    lx, lz = w2p(*LAKE)
    dr.ellipse([lx - 92, lz - 92, lx + 92, lz + 92], outline=Z["wetland"], width=32)
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
        json.dump({"world": 2048, "size": 2048, "min_h": -20, "max_h": 200, "smooth_radius": 40, "edge_sea": False}, f, indent=1)
    hp = h.load()
    for kind, x, zz in pts:
        print(f"{kind:13s} ({x:6.0f},{zz:6.0f})  band={near(hp[w2p(x, zz)], H)}")


if __name__ == "__main__":
    main()
