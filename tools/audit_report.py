#!/usr/bin/env python3
"""Summarize card audit JSON files and matching engine logs."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent


def audit_log(path: Path, audit: dict) -> dict[str, list[str]]:
    errors = defaultdict(list)
    card_id = ""
    completed = None
    inspected = set()
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if match := re.fullmatch(r"AUDIT (\S+)", line):
            card_id = match[1]
            if completed is not None or card_id in inspected:
                raise ValueError(f"Invalid audit marker for {card_id}: {path}")
            inspected.add(card_id)
        elif match := re.fullmatch(r"AUDIT_END (\d+)", line):
            if completed is not None:
                raise ValueError(f"Multiple completion markers: {path}")
            completed = int(match[1])
            card_id = ""
        elif line.startswith(("SCRIPT ERROR:", "ERROR:")):
            errors[card_id].append(line)
    if completed is None:
        raise ValueError(f"Audit log is incomplete: {path}")
    if completed != len(audit) or inspected != audit.keys():
        raise ValueError(f"Audit log and JSON contain different runs: {path}")
    return errors


def table_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audits", type=Path, nargs="+", help="JSON results, with a .log of the same stem to check engine errors.")
    parser.add_argument("--require-logs", action="store_true", help="Fail if any engine log is missing.")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/card_audit.md")
    args = parser.parse_args()

    imported = json.loads((ROOT / "game/ip/data/cards.json").read_text(encoding="utf-8"))["cards"]
    custom = json.loads((ROOT / "game/data/custom_cards.json").read_text(encoding="utf-8"))["cards"]
    cards = imported | custom
    catalog = {}
    by_type = defaultdict(Counter)
    by_scenario = defaultdict(Counter)
    runs_with_errors = []
    flagged = []
    for path in args.audits:
        audit = json.loads(path.read_text(encoding="utf-8-sig"))
        log = path.with_suffix(".log")
        has_log = log.is_file()
        if args.require_logs and not has_log:
            parser.error(f"No matching engine log for {path}")
        errors = audit_log(log, audit) if has_log else {}
        runs_with_errors.extend(f"{path.name}: {message}" for message in errors.get("", []))
        for cid, result in sorted(audit.items()):
            scenario = result.get("scenario", "dense")
            catalog[cid] = result
            issues = list(result["issues"]) + errors.get(cid, [])
            counts = by_type[result["type"]]
            counts["runs"] += 1
            counts["clean"] += not issues
            by_scenario[scenario]["runs"] += 1
            by_scenario[scenario]["clean"] += not issues
            by_scenario[scenario]["engine_errors"] += bool(errors.get(cid))
            by_scenario[scenario]["logs_reviewed"] += has_log
            if issues:
                flagged.append((cid, scenario, result, issues))
    for result in catalog.values():
        by_type[result["type"]]["cards"] += 1
        by_type[result["type"]][result["implemented"]] += 1
    total = sum(counts["runs"] for counts in by_type.values())
    clean = sum(counts["clean"] for counts in by_type.values())
    full = sum(result["implemented"] == "full" for result in catalog.values())
    lines = [
        "# Engine card audit",
        "",
        f"{clean:,} of {total:,} staged runs finished without a flag across {len(catalog):,} of {len(cards):,} catalog cards.",
        f"The importer labels {full:,} of the audited printings full. That label measures text compilation. The staged checks do not establish correctness for every target, trigger or conditional outcome.",
        "",
        "The engine plays units, events and upgrades, checks attacks and attachment lifecycles, and attempts available actions on both leader faces, bases and upgrades. It also plays a bot match for each base and exercises Pilot deployment and token behavior.",
        "",
        "| Scenario | Runs | No staged flags | Runs with engine errors | Logs reviewed |",
        "|---|---:|---:|---:|---:|",
    ]
    for scenario, counts in sorted(by_scenario.items()):
        lines.append(f"| {scenario} | {counts['runs']} | {counts['clean']} | {counts['engine_errors']} | {counts['logs_reviewed']} |")
    lines += [
        "",
        "| Type | Cards | Runs | No staged flags | Full compile | Partial compile | Manual |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for card_type, counts in sorted(by_type.items()):
        lines.append(f"| {card_type} | {counts['cards']} | {counts['runs']} | {counts['clean']} | "
                     f"{counts['full']} | {counts['partial']} | {counts['manual']} |")
    if runs_with_errors:
        lines += ["", "## Engine errors outside a card run", ""] + [f"- {error}" for error in runs_with_errors]
    lines += [
        "",
        "## Staged flags",
        "",
        "A flag requires review. The staged board may lack a legal target or fail to meet a printed condition.",
        "",
        "| Card | Scenario | Observations | Optional choices declined |",
        "|---|---|---|---:|",
    ]
    for cid, scenario, result, issues in sorted(flagged, key=lambda row: (row[0], row[1])):
        name = table_cell(cards.get(cid, {}).get("name", ""))
        observations = table_cell(" · ".join(dict.fromkeys(issues)))
        lines.append(f"| {cid} {name} | {scenario} | {observations} | {result.get('optional_declined', 0)} |")
    lines += ["", "## Missing compiled rules", "", "| Printing | Card | Status | Unparsed lines |",
              "|---|---|---|---:|"]
    for cid, result in sorted(catalog.items()):
        if result["implemented"] != "full":
            card = cards.get(cid, {})
            lines.append(f"| {cid} | {table_cell(card.get('name', ''))} | {result['implemented']} | {len(card.get('unparsed', []))} |")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.output} ({clean}/{total} runs without flags)")
    return 1 if runs_with_errors or any(counts["engine_errors"] for counts in by_scenario.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
