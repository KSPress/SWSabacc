"""Import the supplied title and audio without modifying originals."""
import json
import re
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
OUT = GAME / "ip/audio"


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def main():
    logo = Image.open("E:/Downloads/SWU Kyber  (5).png").convert("RGBA")
    bounds = logo.getchannel("A").getbbox()
    if not bounds:
        raise ValueError("Title image has no visible artwork")
    logo = logo.crop(bounds)
    logo.thumbnail((1600, 600), Image.Resampling.LANCZOS)
    target = GAME / "ip/ui/sabacc_title.webp"
    target.parent.mkdir(parents=True, exist_ok=True)
    logo.save(target, "WEBP", lossless=True)
    catalog = {"characters": {}, "effects": {}, "music": [], "unused": []}
    aliases = {"anakin": "anakin skywalker", "boba_fett": "boba fett", "c3po": "c_3po",
               "chewbacca": "chewbacca", "din_djarn": "din djarin", "han": "han solo",
               "jabba": "jabba", "krennic": "krennic", "luke": "luke skywalker",
               "maul": "maul", "obiwan": "obi_wan kenobi", "palpatine": "palpatine",
               "tarkin": "tarkin", "vader": "darth vader"}
    for folder, dest in [("Sounds", "custom"), ("MUSIC", "music")]:
        source = GAME / folder
        (source / ".gdignore").touch()
        (OUT / dest).mkdir(parents=True, exist_ok=True)
        for path in sorted(source.rglob("*.mp3")):
            relative = path.relative_to(source)
            key = slug(str(relative.with_suffix("")))
            output = OUT / dest / (key + ".mp3")
            shutil.copy2(path, output)
            resource = "res://" + output.relative_to(GAME).as_posix()
            if dest == "music":
                catalog["music"].append(resource)
                continue
            group = slug(relative.parts[0]) if len(relative.parts) > 1 else ""
            name = slug(path.stem)
            event = next((e for e in ["played", "die", "lose"] if e in name.split("_")), "action")
            if event == "die":
                event = "lose"
            if group in aliases:
                catalog["characters"].setdefault(aliases[group], {}).setdefault(event, []).append(resource)
                if group == "boba_fett" and "blaster" in name:
                    catalog["effects"].setdefault("boba_shoot", []).append(resource)
            else:
                effect = {"cantina_band": "hero_win", "imperial_siren": "villain_win", "wilhelmscream": "wilhelm"}.get(name, "")
                if group == "tie":
                    effect = "tie_enter" if "fly" in name else "tie_shoot"
                elif group == "lightsaber":
                    effect = "swing" if "whoosh" in name else "saber_hit"
                elif group == "land_melee":
                    effect = "melee"
                elif group == "land_blaster":
                    effect = "clone_shoot" if "clone" in name else ("walker_shoot" if "walker" in name else ("blaster" if name in ["dl_44", "star_wars_blaster_sound_1"] else ""))
                    if "missile" in name:
                        effect = "heavy_missile"
                    elif "battle_droid" in name:
                        effect = "b1_enter"
                elif group == "boba_fett" and "blaster" in name:
                    effect = "boba_shoot"
                elif group == "explosion":
                    effect = "explosion" if name == "blast_3" else "vehicle_easter_egg"
                if effect:
                    catalog["effects"].setdefault(effect, []).append(resource)
                else:
                    catalog["unused"].append(str(relative))
    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Title cropped to {logo.size}; {len(catalog['music'])} music tracks imported")
    print("Shared DIE/LOSE clips:", sum(len(v.get("lose", [])) for v in catalog["characters"].values()))
    print("Unassigned unlabeled clips:", len(catalog["unused"]))


if __name__ == "__main__":
    main()
