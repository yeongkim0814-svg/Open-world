#!/usr/bin/env python3
"""스크린샷 모아보기: tools/contact_sheet.py <tag> → /tmp/claude-0/shots/<tag>_sheet.jpg (4시점 × 회복 전/후, 각 480x270)."""
import sys
from PIL import Image, ImageDraw
tag = sys.argv[1]
views = ["village", "dam", "tower", "plateau"]
modes = ["grey", "color"]
W, H = 480, 270
sheet = Image.new("RGB", (W * len(views), H * len(modes)), "black")
for r, m in enumerate(modes):
    for c, v in enumerate(views):
        try:
            im = Image.open(f"/tmp/claude-0/shots/{tag}_{v}_{m}.png").convert("RGB").resize((W, H))
        except FileNotFoundError:
            continue
        sheet.paste(im, (c * W, r * H))
        ImageDraw.Draw(sheet).text((c * W + 6, r * H + 4), f"{v}/{m}", fill="yellow")
out = f"/tmp/claude-0/shots/{tag}_sheet.jpg"
sheet.save(out, quality=80)
print(out)
