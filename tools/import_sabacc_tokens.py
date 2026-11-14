"""Extract the two supplied Sabacc-card faces without changing their artwork."""
import json
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def main():
    target = ROOT / "game/ip/ui/tokens"
    target.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, filename in [("force", "SWU Kyber  (2).png"), ("initiative", "SWU Kyber  (4).png")]:
        source = Path("E:/Downloads") / filename
        image = Image.open(source).convert("RGBA")
        split = image.width // 2
        for face, region in [("front", (0, 0, split, image.height)), ("back", (split, 0, image.width, image.height))]:
            half = image.crop(region)
            bounds = half.getchannel("A").getbbox()
            if not bounds:
                raise ValueError(f"Missing {name} {face}")
            card = half.crop(bounds)
            canvas = Image.new("RGBA", (400, 550))
            card = ImageOps.contain(card, (384, 534), Image.Resampling.LANCZOS)
            canvas.alpha_composite(card, ((400 - card.width) // 2, (550 - card.height) // 2))
            canvas.save(target / f"sabacc_{name}_{face}.webp", "WEBP", lossless=True)
            report[f"{name}_{face}"] = {"source": str(source), "region": region, "alpha_crop": bounds, "output": [400, 550]}
    qa = ROOT / "build/qa/cinematic"
    qa.mkdir(parents=True, exist_ok=True)
    (qa / "token_import.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Extracted four transparent Sabacc token faces; originals unchanged")


if __name__ == "__main__":
    main()
