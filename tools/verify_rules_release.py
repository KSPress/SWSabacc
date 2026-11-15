#!/usr/bin/env python3
"""Require complete card rules and passing gameplay evidence before a stable release."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ("dense", "duel", "pressured")


def run_godot(godot, script, evidence_path, env, *args):
    command = [godot, "--headless", "--path", str(ROOT / "game"), "--script", f"res://tests/{script}.gd"]
    if args:
        command.extend(["--", *args])
    with evidence_path.open("w", encoding="utf-8") as evidence:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=evidence, stderr=subprocess.STDOUT)
    lines = evidence_path.read_text(encoding="utf-8").splitlines()
    if result.returncode or any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in lines):
        raise SystemExit(f"Rules verification failed in {script}. See {evidence_path}")
    return lines


def require_card_cases(catalog, lines):
    tested = {line.removeprefix("CARD_RULE_CASE ") for line in lines if line.startswith("CARD_RULE_CASE ")}
    unknown = tested - catalog
    missing = catalog - tested
    if unknown:
        raise SystemExit(f"Rules tests refer to unknown cards: {', '.join(sorted(unknown))}")
    if missing:
        raise SystemExit(f"Rules verification needs explicit passing gameplay tests for {len(missing):,} cards. "
                         f"First missing IDs: {', '.join(sorted(missing)[:12])}.")


def require_audit(catalog, scenario, lines, output):
    results = json.loads(output.read_text(encoding="utf-8"))
    run_ids = [line.removeprefix("AUDIT ") for line in lines if line.startswith("AUDIT ")]
    completion = [line for line in lines if line.startswith("AUDIT_END ")]
    if (results.keys() != catalog or set(run_ids) != catalog or len(run_ids) != len(catalog)
            or completion != [f"AUDIT_END {len(catalog)}"]
            or any(card.get("scenario") != scenario for card in results.values())):
        raise SystemExit(f"The {scenario} card audit did not complete the required catalog. See {output}")
    for card_id, result in results.items():
        for issue in result["issues"]:
            if issue.startswith("stuck after ") or issue == "bot game did not finish":
                raise SystemExit(f"The {scenario} card audit stalled on {card_id}: {issue}. See {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4"))
    args = parser.parse_args()
    subprocess.run([sys.executable, "-I", str(ROOT / "tools/check_card_coverage.py"), "--require-full"], check=True)
    if not args.godot:
        raise SystemExit("Provide the Godot executable with --godot or the GODOT environment variable.")
    catalog = set()
    for path in ("game/ip/data/cards.json", "game/data/custom_cards.json"):
        catalog.update(json.loads((ROOT / path).read_text(encoding="utf-8"))["cards"])
    if not catalog:
        raise SystemExit("The release card catalog is empty.")
    qa = ROOT / "build/qa/release-rules"
    qa.mkdir(parents=True, exist_ok=True)
    evidence = Path(tempfile.mkdtemp(dir=qa))
    with tempfile.TemporaryDirectory() as profile:
        env = dict(os.environ, APPDATA=profile, XDG_DATA_HOME=profile)
        lines = run_godot(args.godot, "extended_rules", evidence / "extended.log", env)
        require_card_cases(catalog, lines)
        run_godot(args.godot, "run_tests", evidence / "core.log", env)
        for scenario in SCENARIOS:
            output = evidence / f"{scenario}.json"
            lines = run_godot(args.godot, "card_audit", evidence / f"{scenario}.log", env, str(output), "", scenario)
            require_audit(catalog, scenario, lines, output)
    print(f"Release rules verified. Evidence saved in {evidence}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
