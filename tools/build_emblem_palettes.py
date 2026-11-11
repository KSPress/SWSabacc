"""Extract decorative palettes from the supplied glyphs; originals stay intact."""
import colorsys
import json
from collections import defaultdict
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def palette(path):
    image = Image.open(path).convert("RGBA")
    image.thumbnail((96, 96))
    buckets = defaultdict(list)
    neutral = []
    for r, g, b, a in image.getdata():
        if a < 160:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if v > .25:
            neutral.append((r, g, b))
        if s > .22 and v > .22:
            buckets[int(h * 24) % 24].append((r, g, b, s * v))
    if buckets:
        ranked = sorted(buckets, key=lambda key: sum(p[3] for p in buckets[key]), reverse=True)
        pixels = buckets[ranked[0]]
        weight = sum(p[3] for p in pixels)
        rgb = [sum(p[i] * p[3] for p in pixels) / weight / 255 for i in range(3)]
        h, s, v = colorsys.rgb_to_hsv(*rgb)
        primary = colorsys.hsv_to_rgb(h, min(s, .78), max(v, .72))
        secondary = colorsys.hsv_to_rgb(h, s * .42, .92)
    else:
        gray = sorted(sum(p) / 3 / 255 for p in neutral)
        value = max(.65, gray[len(gray) * 3 // 4] if gray else .75)
        primary, secondary = (value,) * 3, (.94,) * 3
    return ["#" + "".join(f"{round(c * 255):02x}" for c in color) for color in [primary, secondary]]


def main():
    paths = sorted((ROOT / "Customization/emblems").glob("*_glyph.png"))
    result = {p.stem.removesuffix("_glyph"): palette(p) for p in paths}
    # Visually reviewed multi-tone/neutral glyphs: a small saturated detail must
    # not outweigh the main olive, silver or warm ivory artwork.
    result.update({"fett_crest": ["#c3c79a", "#797e68"],
                   "old_republic": ["#b3a88c", "#e0d3b0"],
                   "iron_crest": ["#b8b7b3", "#b8283a"],
                   "deaths_head": ["#d4d1be", "#f4eddb"]})
    (ROOT / "game/data/emblem_palettes.json").write_text(json.dumps(result, indent=2) + "\n")
    sheet = Image.new("RGB", (1000, 5 * 190), "#091016")
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        identity = path.stem.removesuffix("_glyph")
        x, y = index % 5 * 200, index // 5 * 190
        glyph = Image.open(path).convert("RGBA")
        glyph.thumbnail((130, 130))
        sheet.paste(glyph, (x + 30, y), glyph)
        for i, color in enumerate(result[identity]):
            draw.rectangle((x + 20 + i * 80, y + 135, x + 95 + i * 80, y + 150), fill=color)
        draw.text((x + 12, y + 158), identity, fill="white")
    target = ROOT / "build/qa/polish"
    target.mkdir(parents=True, exist_ok=True)
    sheet.save(target / "emblem_palettes.png")
    print("Reviewed palette inventory:", len(result), "emblems")


if __name__ == "__main__":
    main()
