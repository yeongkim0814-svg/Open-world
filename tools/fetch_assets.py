#!/usr/bin/env python3
"""Polyhaven(CC0) 에셋 내려받기. 사용: python3 tools/fetch_assets.py  (저장소 루트에서)
지형 텍스처 4세트(1K: 색·노멀(GL)·ARM)와 바위 모델 몇 개(1K glTF)를 assets/ 아래에 받는다."""
import json, os, urllib.request

TEXTURES = {"grass": "leafy_grass", "dirt": "forest_ground_04", "rock": "rock_face", "sand": "coast_sand_01"}
ROCK_MODELS = ["namaqualand_boulder_02", "namaqualand_boulder_04", "boulder_01"]
MAPS = {"diff": "Diffuse", "nor": "nor_gl", "arm": "arm"}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "open-world-asset-fetch"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def save(url: str, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        open(path, "wb").write(get(url))
    print(f"{os.path.getsize(path) // 1024:6d} KB  {path}")


def files(asset: str) -> dict:
    return json.loads(get(f"https://api.polyhaven.com/files/{asset}"))


for slot, asset in TEXTURES.items():
    f = files(asset)
    for short, key in MAPS.items():
        save(f[key]["1k"]["jpg"]["url"], f"assets/textures/terrain/{slot}_{short}.jpg")

for asset in ROCK_MODELS:
    g = files(asset)["gltf"]["1k"]["gltf"]
    base = f"assets/meshes/rocks/{asset}"
    save(g["url"], f"{base}/{asset}.gltf")
    for rel, inc in g.get("include", {}).items():
        save(inc["url"], f"{base}/{rel}")

lic = "assets/LICENSES.md"
with open(lic, "w") as fp:
    fp.write("# 외부 에셋 출처\n\n모두 **CC0** (Poly Haven, https://polyhaven.com/license).\n\n")
    for slot, asset in TEXTURES.items():
        fp.write(f"- 지형 텍스처 `{slot}` ← https://polyhaven.com/a/{asset}\n")
    for asset in ROCK_MODELS:
        fp.write(f"- 바위 모델 `{asset}` ← https://polyhaven.com/a/{asset}\n")
print("done")
