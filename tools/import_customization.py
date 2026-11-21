#!/usr/bin/env python3
"""Deterministically crop supplied card backs and convert cosmetics to WebP.

Originals remain untouched. Outputs live in git-ignored game/ip/cosmetics.
Review build/qa/customization/crops.png and crop_report.json after importing.
Requires Pillow (including AVIF support).
"""
from collections import deque
import json
from pathlib import Path
import shutil
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Customization"
OUT = ROOT / "game/ip/cosmetics"
QA = ROOT / "build/qa/customization"
RATIO = 250 / 349


def card_bounds(image, white=False):
    small = image.convert("RGB")
    small.thumbnail((360, 360))
    w, h = small.size
    pixels = list(small.getdata())
    mask = bytearray(min(p) < 238 if white else sum(p) < 240 for p in pixels)
    candidates = []
    for pos in range(w * h):
        if not mask[pos]:
            continue
        mask[pos] = 0
        queue = deque([pos])
        left = right = pos % w
        top = bottom = pos // w
        count = 0
        while queue:
            p = queue.popleft()
            x, y = p % w, p // w
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            count += 1
            for q in ([p - 1] if x else []) + ([p + 1] if x + 1 < w else []) + ([p - w] if y else []) + ([p + w] if y + 1 < h else []):
                if mask[q]:
                    mask[q] = 0
                    queue.append(q)
        cw, ch = right - left + 1, bottom - top + 1
        if .55 < cw / ch < .92 and ch > h * .35 and cw * ch > w * h * .035:
            candidates.append((cw * ch, (left, top, right + 1, bottom + 1)))
    if not candidates:
        if not white:
            return card_bounds(image, True)
        raise ValueError("No card-shaped dark frame detected; supply an explicit crop")
    bounds = max(candidates)[1]
    sx, sy = image.width / w, image.height / h
    return tuple(round(v * (sx if i % 2 == 0 else sy)) for i, v in enumerate(bounds))


def main():
    (OUT / "cardbacks").mkdir(parents=True, exist_ok=True)
    (OUT / "emblems").mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    catalog = {"emblems": [], "cardbacks": [], "scenes": []}
    report = {}
    overrides_path = ROOT / "tools/customization_crops.json"
    overrides = json.loads(overrides_path.read_text()) if overrides_path.exists() else {}
    previews = []
    for source in sorted((SOURCE / "Cardbacks").iterdir()):
        if source.suffix.lower() not in (".jpg", ".avif", ".webp", ".png"):
            continue
        image = ImageOps.exif_transpose(Image.open(source)).convert("RGB")
        bounds = overrides.get(source.name) or card_bounds(image)
        cropped = image.crop(bounds)
        cropped = ImageOps.fit(cropped, (500, 698), method=Image.Resampling.LANCZOS)
        identity = source.stem.removeprefix("SWU ").lower().replace(" ", "_")
        cropped.save(OUT / "cardbacks" / (identity + ".webp"), "WEBP", quality=93, method=6)
        catalog["cardbacks"].append({"id": identity, "name": source.stem.removeprefix("SWU ")})
        report[source.name] = {"original": image.size, "crop": bounds, "output": [500, 698]}
        previews.append((identity, cropped))
    for source in sorted((SOURCE / "emblems").glob("*_glyph.png")):
        identity = source.stem.removesuffix("_glyph")
        # Preserve the existing glyph's alpha; do not regenerate its artwork.
        Image.open(source).convert("RGBA").save(OUT / "emblems" / (identity + ".webp"), "WEBP", lossless=True)
        catalog["emblems"].append({"id": identity, "name": identity.replace("_", " ").title()})
    for identity in ["tatooine", "dathomir", "coruscant", "deathstar"]:
        catalog["scenes"].append({"id": identity, "name": identity.title(), "art": identity})
    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")
    (QA / "crop_report.json").write_text(json.dumps(report, indent=2) + "\n")
    sheet = Image.new("RGB", (800, ((len(previews) + 5) // 6) * 200), "#151b24")
    draw = ImageDraw.Draw(sheet)
    for i, (identity, image) in enumerate(previews):
        thumb = image.copy()
        thumb.thumbnail((118, 166))
        x, y = (i % 6) * 133, (i // 6) * 200
        sheet.paste(thumb, (x + 5, y))
        draw.text((x + 5, y + 173), identity, fill="white")
    sheet.save(QA / "crops.png")
    print("Imported:", {key: len(value) for key, value in catalog.items()})


if __name__ == "__main__":
    main()
