#!/usr/bin/env python3
"""Inventory every card; --require-full fails until all printed text compiles.

This is a coverage gate, not a substitute for semantic gameplay tests. It never
changes a card's status to hide unsupported text. Reports remain local under build.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNIMPLEMENTED_KEYWORDS = {"piloting"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-full", action="store_true")
    args = parser.parse_args()
    source = json.loads((ROOT / "game/ip/data/cards.json").read_text(encoding="utf-8"))["cards"]
    rows = []
    for identity, card in sorted(source.items()):
        missing = list(card.get("unparsed", []))
        unsupported = sorted({entry["k"] for face in [card, card.get("leader_unit", {})]
                              for entry in face.get("keywords", []) if entry["k"] in UNIMPLEMENTED_KEYWORDS})
        rows.append({"id": identity, "type": card["type"], "compiler_status": card.get("implemented", "manual"),
                     "uncompiled_text": missing, "unsupported_keywords": unsupported,
                     "text_covered": card.get("implemented") == "full" and not missing and not unsupported})
    counts = Counter(row["compiler_status"] for row in rows)
    missing = [row for row in rows if not row["text_covered"]]
    report = {"total": len(rows), "compiler_status": dict(counts), "text_covered": len(rows) - len(missing),
              "still_incomplete": len(missing), "cards": rows}
    target = ROOT / "build/qa/cosmetics/card_coverage.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "cards"}))
    print("Every-card inventory:", target)
    return 1 if args.require_full and missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
