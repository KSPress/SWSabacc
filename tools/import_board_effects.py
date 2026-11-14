"""Install the supplied sprite sheets for the board renderer."""
import argparse
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Directory containing the five supplied JPG sheets")
    source = parser.parse_args().source
    target = Path(__file__).resolve().parents[1] / "game/ip/ui/board_effects"
    sheets = {
        "heal": "1-1000005206.jpg",
        "coordinate": "2-1000005205.jpg",
        "sentinel": "3-1000005196.jpg",
        "shield": "4-1000005199.jpg",
        "shield_break": "5-1000005198.jpg",
    }
    missing = [name for name in sheets.values() if not (source / name).is_file()]
    if missing:
        parser.error("Missing sheets: " + ", ".join(missing))
    target.mkdir(parents=True, exist_ok=True)
    for effect, filename in sheets.items():
        shutil.copyfile(source / filename, target / f"{effect}.jpg")


if __name__ == "__main__":
    main()
