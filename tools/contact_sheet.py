#!/usr/bin/env python3
"""스크린샷 모아보기: tools/contact_sheet.py <tag> → /tmp/claude-0/shots/<tag>_sheet.jpg
<tag>_<view>_<mode>.png 를 찾아 행 = 모드, 열 = 시점으로 배치 (각 480x270)."""
import glob, os, sys
from PIL import Image, ImageDraw
tag = sys.argv[1]
D = "/tmp/claude-0/shots"
views, modes = [], []
for p in sorted(glob.glob(f"{D}/{tag}_*_*.png"), key=os.path.getmtime):
    v, m = os.path.basename(p)[len(tag) + 1:-4].rsplit("_", 1)
    if v not in views: views.append(v)
    if m not in modes: modes.append(m)
W, H = 480, 270
sheet = Image.new("RGB", (W * max(1, len(views)), H * max(1, len(modes))), "black")
for r, m in enumerate(modes):
    for c, v in enumerate(views):
        p = f"{D}/{tag}_{v}_{m}.png"
        if not os.path.exists(p):
            continue
        sheet.paste(Image.open(p).convert("RGB").resize((W, H)), (c * W, r * H))
        ImageDraw.Draw(sheet).text((c * W + 6, r * H + 4), f"{v}/{m}", fill="yellow")
out = f"{D}/{tag}_sheet.jpg"
sheet.save(out, quality=80)
print(out)
