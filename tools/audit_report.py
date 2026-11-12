#!/usr/bin/env python3
"""Turns the engine card audit (game/tests/card_audit.gd output) into docs/card_audit.md.
  godot --headless --path game --script res://tests/card_audit.gd -- audit.json
  python -I tools/audit_report.py audit.json
"""
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
audits = [json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[1:]]
cards = json.loads((ROOT / "game/ip/data/cards.json").read_text(encoding="utf-8"))["cards"]
custom = json.loads((ROOT / "game/data/custom_cards.json").read_text(encoding="utf-8"))
cards.update(custom.get("cards", custom))
by_type = collections.defaultdict(lambda: collections.Counter())
flagged = []
scenario_results = {}
for audit in audits:
    for cid, result in audit.items():
        scenario_results[(result.get("scenario", "dense"), cid)] = result
catalog = {}
for (_, cid), result in sorted(scenario_results.items()):
    catalog[cid] = result
    counts = by_type[result["type"]]
    counts["runs"] += 1
    counts["clean"] += not result["issues"]
    if result["issues"]:
        flagged.append((cid, result))
for result in catalog.values():
    by_type[result["type"]]["cards"] += 1
    by_type[result["type"]][result["implemented"]] += 1
lines = ["# Engine card audit", "",
         "The staged runs exercise play, available choices, attacks, deployment, attachments and token behavior. "
         "Each base runs a bot match. The duel declines optional effects, the dense board supplies many legal targets, "
         "and the pressured board starts the acting player behind with a damaged base.", "",
         "| Type | Cards | Runs | No audit flags | Full compile | Partial compile | Manual |", "|---|---|---|---|---|---|---|"]
for t, c in sorted(by_type.items()):
    lines.append(f"| {t} | {c['cards']} | {c['runs']} | {c['clean']} | {c['full']} | {c['partial']} | {c['manual']} |")
total = sum(by_type[t]["runs"] for t in by_type)
clean = sum(by_type[t]["clean"] for t in by_type)
lines += ["", f"**{clean} of {total} runs across {len(catalog)} cards finished without a staged audit flag.** Full compile means the importer "
          "recognized the printed text. Verifying each interaction requires gameplay tests with its conditions and targets.", "",
          "## Flagged", "", "| Card | Scenario | Issue | What the audit observed |", "|---|---|---|---|"]
why = {"no-op": "The staged game recorded no state change for the effect.",
       "not usable": "The action was unavailable on the staged board.",
       "0 attachment targets": "The staged board had no eligible attachment target."}
for cid, r in flagged:
    issue = "; ".join(r["issues"])
    reason = next((v for k, v in why.items() if k in issue), "")
    if declined := r.get("optional_declined", 0):
        reason = f"{reason} The scenario declined {declined} available optional choice(s).".strip()
    lines.append(f"| {cid} {cards.get(cid, {}).get('name', '')} | {r.get('scenario', 'dense')} | {issue} | {reason} |")
(ROOT / "docs/card_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"wrote docs/card_audit.md ({clean}/{total} clean)")
