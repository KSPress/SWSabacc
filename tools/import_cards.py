#!/usr/bin/env python3
"""SWU Sabacc card importer.

Reads the raw SWU-DB dump (swu_data/cards_all.json), keeps one entry per unique
printed card (VariantType == "Normal"), normalises it to the game schema
(build spec section 7.1) and compiles card text into the effect DSL that the
Godot rules engine (game/engine/effects.gd) executes.

Outputs (all IP-bearing, git-ignored):
  game/ip/data/cards.json        normalised card database
  docs/coverage_report.md        what the DSL can / cannot express yet

Usage:  python -I tools/import_cards.py [--src swu_data/cards_all.json]
Stdlib only, so it runs anywhere Python 3.9+ exists.
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = ROOT / "swu_data" / "cards_all.json"
OUT = ROOT / "game" / "ip" / "data" / "cards.json"
REPORT = ROOT / "docs" / "coverage_report.md"

TYPE_MAP = {
    "Unit": "unit", "Event": "event", "Upgrade": "upgrade", "Leader": "leader", "Base": "base",
    "Token Unit": "token_unit", "Token Upgrade": "token_upgrade",
    "Force Token": "force_token", "Credit Token": "credit_token",
}
# Keywords the engine implements natively (no DSL needed).
NATIVE_KEYWORDS = {"sentinel", "shielded", "grit", "saboteur", "ambush", "overwhelm", "raid",
                   "restore", "hidden", "smuggle", "exploit", "coordinate", "piloting",
                   "bounty", "support", "plot", "fortify"}
VALUE_KEYWORDS = {"raid", "restore", "exploit"}
NUM_WORDS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6}

# Printed upgrade modifiers from the standard Jump to Lightspeed cards.
# The source dump supplies only the unit's power and HP.
PILOT_STATS = {
    "034": (2, 3), "035": (2, 2), "036": (3, 3), "045": (2, 3), "046": (2, 2), "048": (1, 3),
    "049": (3, 3), "057": (1, 3), "058": (1, 2), "066": (1, 2), "084": (1, 1), "086": (1, 1),
    "093": (1, 2), "094": (3, 2), "098": (2, 2), "100": (2, 3), "103": (3, 3), "108": (2, 2),
    "109": (2, 2), "139": (1, 2), "141": (0, 3), "142": (3, 3), "145": (1, 2), "148": (2, 2),
    "150": (2, 1), "159": (3, 1), "187": (2, 2), "189": (2, 2), "196": (2, 1), "197": (2, 2),
    "203": (2, 3), "210": (3, 1), "211": (1, 1), "215": (1, 2), "236": (1, 2), "245": (1, 1),
    "246": (1, 3), "255": (1, 1),
}

# ---------------------------------------------------------------------------
# helpers


def card_id(set_code: str, number: str) -> str:
    """SET_NNN, tokens SET_T01. Matches art filenames (tokens: SET_001T.png)."""
    number = number.strip()
    if number.upper().startswith("T"):
        return f"{set_code}_T{int(number[1:]):02d}"
    if number.isdigit():
        return f"{set_code}_{int(number):03d}"
    return f"{set_code}_{number}"


def art_name(cid: str) -> str:
    s, n = cid.split("_", 1)
    if n.startswith("T"):
        return f"{s}_{int(n[1:]):03d}T"
    return cid


def to_int(v, default=None):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return default


def num(word: str) -> int:
    word = word.lower().strip()
    if word.isdigit():
        return int(word)
    return NUM_WORDS.get(word, 1)


def strip_reminders(text: str) -> str:
    return re.sub(r"\s*\([^()]*\)", "", text)


def norm_text(text: str) -> str:
    text = text.replace("–", "-").replace("—", "-").replace("’", "'")
    text = text.replace("“", '"').replace("”", '"').replace("{", "").replace("}", "")
    return text


# ---------------------------------------------------------------------------
# target phrase -> target selector

STOPWORDS = {"a", "an", "the", "that", "with", "shares", "aspect", "of", "to", "and", "or", "for", "each",
              "this", "it", "its", "you", "your", "their", "in", "on", "from", "is", "was", "who", "which",
              "attacking", "defending", "played", "control", "controls", "named", "card", "cards", "token"}


def parse_target(phrase: str) -> dict | None:
    """Turn 'an enemy non-leader ground unit with 3 or less remaining HP' into a selector."""
    p = phrase.strip().rstrip(".").lower()
    if p.startswith("each of up to "):
        p = p.removeprefix("each of ")
    p = re.sub(r"^(?:to|from|on) ", "", p)
    simple = {
        "a unit or base": {"s": "choose", "kind": "unit_or_base", "side": "any"},
        "this leader": {"s": "self"},
        "the played unit": {"s": "subject"},
        "this unit": {"s": "self"}, "this upgrade": {"s": "self"}, "this base": {"s": "self"},
        "it": {"s": "it"}, "him": {"s": "self"}, "her": {"s": "self"},
        "your base": {"s": "own_base"}, "the defender": {"s": "defender"},
        "the defending unit": {"s": "defender"}, "attached unit": {"s": "attached"},
        "an enemy base": {"s": "enemy_base"}, "each enemy base": {"s": "enemy_base"},
        "the defending player's base": {"s": "enemy_base"}, "a base": {"s": "choose", "kind": "base", "side": "any"},
        "each base": {"s": "each", "kind": "base", "side": "any"},
        "this leader": {"s": "self"},
    }
    if p in simple:
        return dict(simple[p])
    t: dict = {"s": "choose", "kind": "unit", "side": "any"}
    m = re.match(r"^(each|a|an|another|up to (\w+)|(\w+)) ", p)
    if not m:
        return None
    lead = m.group(1)
    rest = p[m.end():]
    if lead == "each":
        t["s"] = "each"
    elif lead == "another":
        t["other"] = True
    elif lead.startswith("up to"):
        t["count"] = num(m.group(2)); t["upto"] = True
    elif lead not in ("a", "an"):
        if m.group(3) and m.group(3) in NUM_WORDS:
            t["count"] = num(m.group(3))
        else:
            return None
    # words before "unit"
    m2 = re.match(r"^((?:other |enemy |friendly |non-leader |damaged |exhausted |ready |non-unique |unique |"
                  r"ground |space |non-vehicle |vehicle |[a-z]+ )*)(units? or bases?|units?|bases?|upgrades?)(.*)$", rest)
    if not m2:
        return None
    adjs, noun, tail = m2.group(1).split(), m2.group(2), m2.group(3).strip()
    # "creature or spectre unit" -> any of these traits
    if "or" in adjs and adjs.index("or") > 0 and adjs.index("or") < len(adjs) - 1:
        i = adjs.index("or")
        t["traits_any"] = [adjs[i - 1], adjs[i + 1]]
        adjs = adjs[:i - 1] + adjs[i + 2:]
    if "token" in adjs:
        t["token"] = True
        adjs = [a for a in adjs if a != "token"]
    if "different" in adjs:
        t["different"] = True
        adjs = [a for a in adjs if a != "different"]
    if any(a in STOPWORDS for a in adjs):
        return None
    if noun.startswith("base"):
        t["kind"] = "base"
    elif noun.startswith("upgrade"):
        t["kind"] = "upgrade"
    elif "or base" in noun:
        t["kind"] = "unit_or_base"
    for a in adjs:
        if a == "other": t["other"] = True
        elif a == "enemy": t["side"] = "enemy"
        elif a == "friendly": t["side"] = "friendly"
        elif a == "non-leader": t["nonleader"] = True
        elif a == "leader": t["leader"] = True
        elif a == "damaged": t["damaged"] = True
        elif a == "exhausted": t["exhausted"] = True
        elif a == "ready": t["ready"] = True
        elif a in ("ground", "space"): t["arena"] = a
        elif a == "unique": t["unique"] = True
        elif a == "non-unique": t["unique"] = False
        elif a == "non-vehicle": t["not_trait"] = "vehicle"
        elif a == "random": t["random"] = True
        elif a == "upgraded": t["upgraded"] = True
        elif a in ("vehicle",): t["trait"] = "vehicle"
        elif a in ("heroism", "villainy", "vigilance", "command", "aggression", "cunning"): t["aspect"] = a
        else: t["trait"] = a  # e.g. "rebel", "trooper", "tusken", "force"
    if True:
        mmin = re.match(r"^with (\d+) or more (remaining hp|hp|power)$", tail)
        mwo = re.match(r"^without an? (experience|shield) token on it$", tail)
        if mmin:
            t["min_hp" if "hp" in mmin.group(2) else "min_power"] = int(mmin.group(1))
            tail = ""
        elif mwo:
            t["without_token"] = mwo.group(1)
            tail = ""
        m3 = re.match(r"^with (\d+) or less (remaining hp|hp|power|cost)$", tail) or \
             re.match(r"^that costs (\d+) or less()$", tail)
        m4 = re.match(r"^in (?:this|the) (ground|space) arena$", tail)
        if m3:
            key = {"remaining hp": "max_hp", "hp": "max_hp", "power": "max_power", "cost": "max_cost", "": "max_cost"}[m3.group(2)]
            t[key] = int(m3.group(1))
        elif m4:
            t["arena"] = m4.group(1)
        elif tail in ("in this arena", "in the same arena"):
            t["same_arena"] = True
        elif tail == "you control":
            t["side"] = "friendly"
        elif tail == "an opponent controls":
            t["side"] = "enemy"
        elif tail == "":
            pass
        else:
            return None
    return t


TOKEN_NAMES = {"battle droid": "battle_droid", "clone trooper": "clone_trooper", "tie fighter": "tie_fighter",
               "x-wing": "x_wing", "spy": "spy", "mandalorian": "mandalorian", "credit": "credit",
               "beast": "beast"}

# ---------------------------------------------------------------------------
# sentence -> effect


def compile_sentence(s: str) -> list | None:
    s = s.strip().rstrip(".").strip()
    if not s:
        return []
    low = s.lower()
    opt = False
    if low.startswith("you may "):
        opt = True
        s = s[8:]
        low = low[8:]

    def wrap(eff):
        if opt:
            eff["optional"] = True
            if "t" in eff and eff["t"].get("s") == "choose":
                eff["t"]["opt"] = True
        return [eff]

    discount = re.fullmatch(r"(?:the next|each of the next (\d+)) (.+?) you play this phase costs? (\d+) less", low)
    if discount:
        selector = compile_play_filter(discount.group(2))
        if selector is not None:
            return wrap({"op": "discount_next", "filter": selector, "n": int(discount.group(3)),
                         "uses": int(discount.group(1) or 1)})

    if low in ("attack with attached unit", "attack with this unit"):
        return wrap({"op": "attack_with", "t": {"s": "attached" if "attached" in low else "self"}})
    if low == "put a non-vehicle unit from your discard pile on top of your deck":
        return wrap({"op": "recover", "kind": "unit", "not_trait": "vehicle", "destination": "deck"})
    if low == "it doesn't ready during the next regroup phase":
        return wrap({"op": "skip_regroup_ready", "t": {"s": "it"}})
    if low == "reveal the top card of your deck":
        return wrap({"op": "reveal_top"})
    if low == "defeat this upgrade":
        return wrap({"op": "defeat", "t": {"s": "self"}})
    if low == "while this unit is in play, the chosen unit gets +1/+0 and gains saboteur":
        return [{"op": "linked_bonus", "t": {"s": "it"}, "p": 1, "kw": "saboteur"}]
    if low == "play a non-villainy unit that costs less than the returned unit from your hand for free":
        return [{"op": "play_from_hand", "kind": "unit", "cheaper_than_returned": True, "free": True,
                 "exclude_aspect": "villainy", "if_did": True}]
    m = re.fullmatch(r"choose (.+)", low)
    if m and (target := parse_target(m[1])):
        return wrap({"op": "select", "t": target})
    m = re.fullmatch(r"heal up to (\d+) damage from (.+)", low)
    if m and (target := parse_target(m[2])):
        return [{"op": "heal_up_to", "n": int(m[1]), "t": target}]
    if low in ("an opponent takes control of this unit", "have an opponent take control of this unit"):
        return wrap({"op": "take_control", "who": "opponent", "t": {"s": "self"}})
    m = re.fullmatch(r"take control of (.+?)( and ready it)?", low)
    if m:
        phrase = m[1].removesuffix(" with a weakness token on it")
        target = parse_target(phrase)
        if target and target.get("kind") == "unit" and (target.get("nonleader") or target.get("token")):
            if phrase != m[1]:
                target["with_token"] = "weakness"
            return wrap({"op": "take_control", "t": target, "ready": bool(m[2])})
    if low in ("at the start of the regroup phase, its owner takes control of it",
               "at the start of the regroup phase, that token unit's owner takes control of it",
               "at the start of the next regroup phase, its owner takes control of it"):
        return [{"op": "_mod_control_return"}]
    if low in ("exhaust this unit", "exhaust this leader"):
        return wrap({"op": "exhaust", "t": {"s": "self"}})
    if low == "a friendly unit captures an enemy non-leader unit in the same arena":
        return wrap({"op": "capture"})
    m = re.fullmatch(r"pay (\d+)", low)
    if m:
        return wrap({"op": "pay_resources", "n": int(m.group(1))})
    m = re.fullmatch(r"deal (\d+) indirect damage to (a player|(?:each|an) opponent|the defending player)", low)
    if m:
        return wrap({"op": "indirect_damage", "n": int(m.group(1)),
                     "player": {"a player": "choose", "the defending player": "defender"}.get(m.group(2), "opponent")})
    if low == "deal indirect damage equal to this unit's power to the defending player":
        return wrap({"op": "indirect_damage", "amount": "source_power", "player": "defender"})
    if low == "deal indirect damage to a player equal to the number of vehicle units you control":
        return wrap({"op": "indirect_damage", "amount": "friendly_vehicles", "player": "choose"})
    if low == "exhaust each unit damaged this way":
        return wrap({"op": "exhaust", "t": {"s": "indirect_units"}})

    m = re.fullmatch(r"return (?:a|an) (?:(\w+) )?(unit|event|upgrade|card) from your discard pile to your hand", low)
    if m:
        return wrap({"op": "recover", "kind": m.group(2), "trait": m.group(1) or ""})
    if low == "put this event into play as a resource":
        return wrap({"op": "resource_self"})
    if low in ("resource this unit", "resource this unit from its owner's discard pile",
               "put this unit into play as a resource", "put this unit into play as a resource and ready it"):
        return wrap({"op": "resource_self", "ready": low.endswith("and ready it")})
    if low in ("resource the top card of your deck", "put the top card of your deck into play as a resource",
               "put the top card of your deck into play as a resource and ready it"):
        return wrap({"op": "resource_top", "ready": low.endswith("and ready it")})
    if low == "look at an opponent's hand":
        return wrap({"op": "reveal_hand", "who": "opponent"})
    if low == "an opponent chooses a unit they control. defeat that unit":
        return wrap({"op": "opponent_defeat"})

    m = re.match(r"^deal (\d+) damage to (.+)$", low)
    if m and parse_target(m.group(2)):
        return wrap({"op": "damage", "n": int(m.group(1)), "t": parse_target(m.group(2))})
    if low == "a friendly unit deals damage equal to its power to a non-unique enemy unit":
        return [{"op": "select", "t": parse_target("a friendly unit")},
                {"op": "damage_from_it", "if_did": True, "t": parse_target("a non-unique enemy unit")}]
    m = re.match(r"^deal (\d+) damage to (.+) and (\d+) damage to (.+)$", low)
    if m:
        t1, t2 = parse_target(m.group(2)), parse_target(m.group(4))
        if t1 and t2:
            return [{"op": "damage", "n": int(m.group(1)), "t": t1}, {"op": "damage", "n": int(m.group(3)), "t": t2}]
    m = re.match(r"^heal (\d+) damage from (.+)$", low)
    if m:
        t = parse_target(m.group(2))
        return wrap({"op": "heal", "n": int(m.group(1)), "t": t}) if t else None
    m = re.match(r"^heal all damage from (.+)$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "heal", "n": 999, "t": t}) if t else None
    m = re.match(r"^draw (a|an|one|two|three|\d+) cards?$", low)
    if m:
        return wrap({"op": "draw", "n": num(m.group(1))})
    if low == "each player draws a card":
        return wrap({"op": "draw", "n": 1, "who": "all"})
    m = re.match(r"^discard (a|one|two|\d+) cards? from your deck$", low)
    if m:
        return wrap({"op": "mill", "n": num(m.group(1))})
    m = re.fullmatch(r"discard (a|one|two|\d+) cards? from an opponent's deck", low)
    if m:
        return wrap({"op": "mill", "n": num(m.group(1)), "who": "opponent"})
    if low == "an opponent discards a random card from their hand":
        return wrap({"op": "discard", "n": 1, "who": "opponent", "random": True})
    m = re.match(r"^discard (a|one|two|\d+) cards? from your hand$", low)
    if m:
        return wrap({"op": "discard", "n": num(m.group(1)), "who": "self"})
    m = re.match(r"^each opponent discards (a|one|two|\d+) cards? from their hand$", low) or \
        re.match(r"^an opponent discards (a|one|two|\d+) cards? from their hand$", low)
    if m:
        return wrap({"op": "discard", "n": num(m.group(1)), "who": "opponent"})
    m = re.match(r"^give (a|an|one|two|three|\d+) (shield|experience|advantage|weakness) tokens? to (.+)$", low)
    if m:
        t = parse_target(m.group(3))
        return wrap({"op": m.group(2), "n": num(m.group(1)), "t": t}) if t else None
    m = re.match(r"^give (.+?) (a|an|one|two|three|\d+) (shield|experience|advantage|weakness) tokens?$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": m.group(3), "n": num(m.group(2)), "t": t}) if t else None
    m = re.match(r"^(exhaust|ready|defeat) (.+)$", low)
    if m and not m.group(2).startswith(("a resource", "this leader", "your")):
        t = parse_target(m.group(2))
        return wrap({"op": m.group(1), "t": t}) if t else None
    m = re.match(r"^ready (a|one|two|\d+) resources?$", low)
    if m:
        return wrap({"op": "ready_resource", "n": num(m.group(1))})
    m = re.match(r"^return (.+?) to (?:its|their) owner's hand$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "bounce", "t": t}) if t else None
    m = re.match(r"^(.+?) gets? ([+-]\d+)/([+-]\d+) for this (phase|attack)$", low) or \
        re.match(r"^give (.+?) ([+-]\d+)/([+-]\d+) for this (phase|attack)$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "buff", "p": int(m.group(2)), "h": int(m.group(3)), "dur": m.group(4), "t": t}) if t else None
    m = re.match(r"^(.+?) gains (sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+) for this (phase|attack)$", low) or \
        re.match(r"^give (.+?) (sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+) for this (phase|attack)$", low)
    if m:
        t = parse_target(m.group(1))
        kw = m.group(2).split()
        eff = {"op": "gain_kw", "kw": kw[0], "dur": m.group(3), "t": t}
        if len(kw) > 1:
            eff["v"] = int(kw[1])
        return wrap(eff) if t else None
    m = re.match(r"^(.+?) loses (sentinel) for this phase$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "lose_kw", "kw": m.group(2), "dur": "phase", "t": t}) if t else None
    m = re.match(r"^create (a|an|one|two|three|\d+) (battle droid|clone trooper|tie fighter|x-wing|spy|mandalorian|credit|beast) tokens?$", low)
    if m:
        return wrap({"op": "token", "name": TOKEN_NAMES[m.group(2)], "n": num(m.group(1))})
    # "Deal 1 damage to a unit and 1 damage to a different unit"
    m = re.match(r"^deal (\d+) damage to (.+?) and (\d+) damage to (.+)$", low)
    if m:
        t1, t2 = parse_target(m.group(2)), parse_target(m.group(4))
        if t1 and t2:
            return [{"op": "damage", "n": int(m.group(1)), "t": t1}, {"op": "damage", "n": int(m.group(3)), "t": t2}]
    # "Play a [Trait] unit|event|card from your hand [(paying its cost)]"
    m = re.match(r"^play (a|an|2) ((?:[a-z-]+ )*?)(unit|event|card|upgrade|non-unit card)( that costs (\d+) or less)?( with (\d+) or less power)? from your hand(.*)$", low)
    if m:
        words = m.group(2).replace("capital ship", "capital_ship").replace("bounty hunter", "bounty_hunter").replace("first order", "first_order").replace("new republic", "new_republic").split()
        words = [w.replace("_", " ") for w in words]
        eff = {"op": "play_from_hand", "kind": m.group(3), "count": 2 if m.group(1) == "2" else 1}
        aspects = {"heroism", "villainy", "vigilance", "command", "aggression", "cunning"}
        for w in words:
            if w in aspects:
                eff["aspect"] = w
            elif w == "non-unit":
                eff["kind"] = "non-unit"
            else:
                eff.setdefault("traits_any", []).append(w.rstrip(","))
        if "or" in eff.get("traits_any", []):
            eff["traits_any"] = [w for w in eff["traits_any"] if w != "or"]
        if m.group(5):
            eff["max_cost"] = int(m.group(5))
        if m.group(7):
            eff["max_power"] = int(m.group(7))
        rest = m.group(8)
        if "ignoring its aspect penalties" in rest or "ignoring its" in rest:
            eff["ignore_aspects"] = True
        mm = re.search(r"it costs (\d+) less", rest)
        if mm:
            eff["discount"] = int(mm.group(1))
        if "enters play ready" in rest:
            eff["ready"] = True
        if "give it ambush" in rest:
            eff["gain_kw"] = "ambush"
        leftover = re.sub(r"\(paying (?:its|their) costs?\)|, ignoring its aspect penalties|ignoring its aspect penalties|"
                          r"\. it costs \d+ less|it costs \d+ less|\. it enters play ready|and give it ambush for this phase|"
                          r"(?:one at a time, )|[ .,]", "", rest)
        if leftover:
            return None
        return wrap(eff)
    m = re.match(r"^it costs (\d+) less$", low)
    if m:
        return [{"op": "_mod_last_play", "discount": int(m.group(1))}]
    m = re.match(r"^it enters play ready$", low)
    if m:
        return [{"op": "_mod_last_play", "ready": True}]
    if re.match(r"^attack with (?:a|an|another) ", low):
        t = parse_target(low.removeprefix("attack with "))
        if t and t.get("kind") == "unit" and t.get("side") != "enemy" and t.get("s") == "choose":
            t.update(side="friendly", ready=True, can_attack=True)
            return wrap({"op": "attack_with", "t": t})
    m = re.match(r"^either (.+?),? or (.+)$", low)
    if m:
        opts = []
        for part in (m.group(1), m.group(2)):
            c = compile_sentence(part[0].upper() + part[1:])
            if c is None:
                return None
            opts.append({"label": part[0].upper() + part[1:], "effects": c})
        return [{"op": "choose_one", "options": opts, "who": "self", "optional": opt}]
    m = re.match(r"^use the force$", low)
    if m:
        return wrap({"op": "use_force"})
    m = re.match(r"^the force is with you$", low)
    if m:
        return wrap({"op": "force_token"})
    return None


SPLIT_SENT = re.compile(r"(?<=[.!])\s+(?=[A-Z])")


def compile_condition(phrase: str) -> dict | None:
    p = phrase.lower().strip()
    if p == "you control grand moff tarkin":
        return {"controls_name": "Grand Moff Tarkin"}
    if p == "it's aggression":
        return {"revealed_aspect": "aggression"}
    m = re.match(r"^you attacked with an? ((?:[a-z-]+ )*?)unit this phase$", p)
    if m:
        return {"attacked_trait": m.group(1).strip().replace("non-token ", "")}
    m = re.match(r"^you played an? ((?:[a-z-]+ )*?)card this phase$", p)
    if m:
        return {"played_trait": m.group(1).strip()}
    m = re.match(r"^an? friendly ((?:[a-z-]+ )*?)unit was defeated this phase$", p)
    if m:
        return {"friendly_defeated_trait": m.group(1).strip()}
    m = re.match(r"^(\d+|two) or more friendly units were defeated this phase$", p)
    if m:
        return {"friendly_defeated_min": 2 if m.group(1) == "two" else int(m.group(1))}
    m = re.match(r"^you control (.+)$", p)
    if m:
        t = parse_target(m.group(1))
        if t and t.get("kind") == "unit":
            t["side"] = "friendly"
            t["s"] = "count"
            return {"control": t, "min": t.pop("count", 1)}
    m = re.match(r"^you control (\d+|two|three|four) or more (.+)$", p)
    if m:
        t = parse_target("a " + m.group(2).rstrip("s"))
        if t:
            t["side"] = "friendly"; t["s"] = "count"
            return {"control": t, "min": num(m.group(1))}
    m = re.match(r"^an enemy unit was defeated this phase$", p)
    if m:
        return {"enemy_defeated_this_phase": True}
    m = re.match(r"^(?:you have|you control) the initiative$", p)
    if m:
        return {"has_initiative": True}
    if p in ("you control fewer resources than an opponent", "an opponent controls more resources than you"):
        return {"fewer_resources": True}
    if p == "a base is damaged this way":
        return {"indirect_base_hit": True}
    if p == "you have fewer cards in hand than an opponent":
        return {"fewer_hand_cards": True}
    m = re.match(r"^it's damaged$|^this unit is damaged$", p)
    if m:
        return {"selected_damaged": True} if p == "it's damaged" else {"self_damaged": True}
    m = re.fullmatch(r"it's an? ([a-z]+) unit", p)
    if m:
        return {"selected_trait": m[1]}
    return None


def compile_special(sent: str) -> list | None:
    low = sent.lower().rstrip(".")
    m = re.match(r"^look at the top card of your deck$", low)
    if m:
        return [{"op": "scry", "n": 1}]
    m = re.match(r"^you may put it on the bottom of your deck$", low)
    if m:
        return []  # folded into scry
    m = re.match(r"^search the top (\d+|\w+) cards of your deck for (a|an|up to \w+) (.+?), reveal (?:it|them),? and draw (?:it|them)$", low)
    if m:
        what = m.group(3)
        if what.endswith(("card", "cards")):
            tw = what.replace(" cards", "").replace(" card", "").split()
            if len(tw) > 1 or (tw and tw[0] in STOPWORDS):
                return None
            filt = {"kind": "card", "trait": tw[0]} if tw else {"kind": "card"}
        else:
            filt = parse_target("a " + re.sub(r"s$", "", what))
            if not filt:
                return None
            filt.pop("s", None)
        return [{"op": "search", "n": num(m.group(1)), "filter": filt,
                 "count": num(m.group(2).split()[-1]) if m.group(2).startswith("up to") else 1}]
    return None


def inert(effects: list, ok: bool) -> bool:
    if ok or not effects:
        return False
    if any(e["op"] in {"resource_top", "resource_self", "mill", "take_control"} for e in effects):
        return True  # these effects depend on their printed follow-up rules
    first = effects[0]
    if first["op"] == "defeat" and first.get("t", {}).get("s") == "self":
        return True  # keep self-sacrifice with its printed payoff
    return bool(first.get("if_did") or first.get("t", {}).get("s") == "it" or first.get("op", "").startswith("_"))


def compile_body(body: str) -> tuple[list, bool]:
    if body.strip().lower().rstrip(".") == "look at an opponent's hand. you may discard a card from it. if you do, they draw a card":
        return [{"op": "discard", "who": "opponent", "chooser": "self", "optional": True},
                {"op": "draw", "who": "opponent", "if_did": True}], True
    if body.strip().lower().rstrip(".") == "an opponent chooses a unit they control. defeat that unit":
        return [{"op": "opponent_defeat"}], True
    if re.search(r"chooses? (?:one|two(?:, in any order)?):", body, re.I):
        c = compile_choose_one(body.strip())
        return (c, True) if c else ([], False)
    effects, ok = [], True
    body = re.sub(r"(?<=\.)\s+if ", " If ", body.strip())
    for sent in SPLIT_SENT.split(re.sub(r", then\s+", ". Then ", body, flags=re.I)):
        sent = sent.strip()
        if not sent:
            continue
        low = sent.lower()
        cond, if_did = None, False
        m = re.match(r"^if (.+?), (.+)$", sent, re.I)
        if m and m.group(1).lower() == "you do":
            if_did, sent = True, m.group(2)
        elif m:
            cond = compile_condition(m.group(1))
            if cond is None:
                ok = False
                continue
            sent = m.group(2)
        elif re.match(r"^then,? ", low):
            sent = re.sub(r"^then,? ", "", sent, flags=re.I)
        sp = compile_special(sent)
        if sp is not None:
            c = sp
        elif re.match(r"^(otherwise|an opponent chooses|search|look|for each)", sent.lower()):
            ok = False
            continue
        else:
            c = compile_sentence(sent[0].upper() + sent[1:])
        if c is None and " and " in sent:
            a_part, b_part = sent.split(" and ", 1)
            ca = compile_sentence(a_part[0].upper() + a_part[1:])
            cb = compile_sentence(b_part[0].upper() + b_part[1:])
            if ca is not None and cb is not None:
                if ca and ca[0].get("optional"):
                    for effect in cb:
                        effect["if_did"] = True
                c = ca + cb
        if c is None:
            ok = False
            continue
        for e in c:
            if cond:
                e["if"] = cond
            if if_did:
                e["if_did"] = True
        effects += c
    # "Attack with a unit. It gets +3/+0 for this attack." -> buff applied before combat
    merged = []
    for e in effects:
        if merged and merged[-1]["op"] == "take_control" and e["op"] == "_mod_control_return":
            merged[-1]["regroup_return"] = True
            continue
        if e["op"] == "_mod_control_return":
            ok = False
            continue
        if (merged and merged[-1]["op"] == "attack_with" and e["op"] == "attack_with"
                and e["t"].get("other")):
            e["t"]["different"] = True
            e["t"].pop("other")
        if merged and merged[-1]["op"] == "play_from_hand" and e["op"] == "_mod_last_play":
            merged[-1].update({k: v for k, v in e.items() if k != "op"})
            continue
        if (merged and merged[-1]["op"] == "play_from_hand" and e["op"] == "gain_kw"
                and e["kw"] == "ambush" and e["dur"] == "phase" and e["t"].get("s") == "it"):
            merged[-1]["gain_kw"] = "ambush"
            continue
        if merged and merged[-1]["op"] == "attack_with" and e["op"] in ("buff", "gain_kw")                 and e.get("t", {}).get("s") == "it" and e.get("dur") == "attack":
            merged[-1].setdefault("pre", []).append(e)
        else:
            merged.append(e)
    return merged, ok


TRIGGERS = [
    (r"^when a friendly unit is defeated", ["friendly_unit_defeated"]),
    (r"^when a non-leader ground unit enters play", ["nonleader_ground_enters"]),
    (r"^when attached unit's attack or defense ends", ["host_combat_end"]),
    (r"^when you use the force", ["force_used"]),
    (r"^when you draw 1 or more cards during the action phase", ["action_cards_drawn"]),
    (r"^when you draw 1 or more cards", ["cards_drawn"]),
    (r"^when your base is dealt damage", ["own_base_damaged"]),
    (r"^when an opponent plays an event", ["opponent_event"]),
    (r"^when you play an upgrade on this unit", ["upgrade_played_here"]),
    (r"^when a friendly upgrade is defeated", ["friendly_upgrade_defeated"]),
    (r"^when played/on attack", ["when_played", "on_attack"]),
    (r"^when played as a unit/on attack", ["when_played", "on_attack"]),
    (r"^on attack/when defeated", ["on_attack", "when_defeated"]),
    (r"^when played/when defeated", ["when_played", "when_defeated"]),
    (r"^when played as an upgrade", ["when_played_upgrade"]),
    (r"^when played as a unit", ["when_played"]),
    (r"^when played using smuggle", ["when_smuggled"]),
    (r"^when an enemy unit is defeated", ["enemy_unit_defeated"]),
    (r"^when you deploy a leader", ["friendly_leader_deployed"]),
    (r"^when this unit is attacked", ["when_attacked"]),
    (r"^when you take the initiative", ["when_claiming_initiative"]),
    (r"^when played", ["when_played"]),
    (r"^on attack", ["on_attack"]),
    (r"^when defeated", ["when_defeated"]),
    (r"^when deployed", ["when_deployed"]),
    (r"^when attack ends", ["attack_end"]),
    (r"^when this unit completes an attack", ["attack_end"]),
    (r"^when the regroup phase starts", ["regroup_start"]),
    (r"^when the action phase starts", ["action_start"]),
    (r"^when this unit deals combat damage to (?:a|an opponent's) base", ["base_damage"]),
    (r"^when an enemy unit deals combat damage to your base", ["enemy_combat_damage_to_base"]),
    (r"^when this unit is dealt damage and survives", ["survived_damage"]),
    (r"^when 1 or more damage is healed from this unit", ["unit_healed"]),
]


def parse_action_cost(inner: str) -> dict:
    cost = {"exhaust": False, "resources": 0}
    for part in [p.strip().lower() for p in inner.split(",")]:
        if part == "exhaust":
            cost["exhaust"] = True
        elif part.startswith("c="):
            cost["resources"] = to_int(part[2:], 0)
        elif part:
            cost["other"] = part
    return cost


def compile_limited_body(body: str, action: bool = False):
    match = re.fullmatch(r"(.+?)\.\s*Use this ability (?:only once|no more than (\d+) times) each (round|phase|game)\.?", body, re.I)
    if not match:
        effects, complete = compile_body(body)
        return effects, complete, {}
    effects, complete = compile_body(match[1])
    if not complete or not effects or (not action and any(e.get("optional") for e in effects)):
        return [], False, {}
    return effects, True, {"limit": int(match[2] or 1), "limit_period": match[3].lower()}


CHOICE_SEP = " \u2016 "   # joins option lines into one logical line


def merge_choose_one(text: str) -> str:
    """Fold 'Choose one:' + following option lines into a single line so the
    per-line compiler sees the whole modal ability."""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if re.search(r"(choose|chooses) (?:one|two(?:, in any order)?):\s*$", strip_reminders(line).strip(), re.I):
            opts = []
            j = i + 1
            while j < len(lines):
                nxt = strip_reminders(lines[j]).strip()
                if not nxt:
                    j += 1
                    continue
                if re.match(r"^(when |on attack|action \[|epic action|attached unit|smuggle|bounty|coordinate|piloting)", nxt, re.I):
                    break
                opts.append(nxt.lstrip("\u2022- ").strip())
                j += 1
            out.append(line.strip() + " " + CHOICE_SEP.join(opts))
            i = j
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def compile_choose_one(body: str):
    """'Choose one: A || B' -> choose_one effect (or None if an option can't compile)."""
    who = "self"
    count = 1
    m = re.match(r"^(an opponent|each opponent) chooses? one:\s*(.+)$", body, re.I)
    if m:
        who = "opponent"
        rest = m.group(2)
    else:
        m = re.match(r"^(?:for each opponent, )?choose (one|two)(?:, in any order)?:\s*(.+)$", body, re.I)
        if not m:
            return None
        count, rest = num(m.group(1)), m.group(2)
    parts = [p.strip() for p in rest.split(CHOICE_SEP.strip()) if p.strip()]
    if len(parts) == 1 and re.match(r"^either ", parts[0], re.I):
        e = compile_sentence(parts[0])
        if e:
            e[0]["who"] = who
        return e
    opts = []
    for part in parts:
        effs, ok = compile_body(part)
        if not ok or not effs:
            return None
        opts.append({"label": part.rstrip("."), "effects": effs})
    if len(opts) < 2:
        return None
    return [{"op": "choose_one", "options": opts, "who": who, "count": count}]


def compile_text(text: str, keywords: list, base: bool = False) -> tuple[list, list, str]:
    """Return (abilities, gains, status) where status is full|partial|manual|vanilla."""
    if not text:
        return [], [], "full"
    text = norm_text(text)
    abilities, unparsed, parsed = [], [], 0
    text = merge_choose_one(text)
    for raw_line in text.split("\n"):
        line = strip_reminders(raw_line).strip()
        if not line:
            continue
        low = line.lower()
        constant = compile_continuous(line)
        if constant is not None:
            abilities.append(constant)
            parsed += 1
            continue
        coordinate = re.fullmatch(r"coordinate\s*-\s*(.+)", line, re.I)
        if coordinate:
            inner = coordinate.group(1)
            sub, _, status = compile_text(inner, [])
            if sub and status == "full" and all(a["trigger"] in {
                "action", "on_attack", "when_played", "when_defeated", "attack_end",
            } for a in sub):
                for ability in sub:
                    ability["requires_coordinate"] = True
                    ability["text"] = line
                abilities.extend(sub)
                parsed += 1
            else:
                unparsed.append(line)
            continue
        # keyword lines are handled natively
        first = re.split(r"[\s\[\-]", low, maxsplit=1)[0]
        bounty = re.fullmatch(r"bounty\s*-\s*(.+)", line, re.I)
        if bounty:
            effects, complete = compile_body(bounty.group(1))
            if effects and complete:
                abilities.append({"trigger": "bounty", "effects": [{"op": "choose_one", "optional": True,
                    "options": [{"label": "Collect bounty", "effects": effects}]}], "text": line})
                parsed += 1
            else:
                unparsed.append(line)
            continue
        if first in ("piloting",):
            # Listed keywords are not implementation. Keep unimplemented
            # mechanics visible in coverage until their engine path exists.
            unparsed.append(line)
            continue
        listed = {k["k"] for k in keywords}
        parts = re.split(r",\s*|\s+and\s+", low.rstrip("."))
        entries = [re.fullmatch(r"([a-z]+)(?:\s+\d+)?(?:\s*\[[^\]]+\])?", p.strip()) for p in parts]
        if all(e and e.group(1) in listed - {"bounty", "coordinate", "piloting"} for e in entries):
            parsed += 1
            continue
        if low.startswith("attach to"):
            phrase = low.removeprefix("attach to ").rstrip(".")
            target = parse_target(phrase)
            if phrase == "a capital ship or transport unit":
                target = {"s": "choose", "kind": "unit", "side": "any", "traits_any": ["capital ship", "transport"]}
            if target:
                abilities.append({"trigger": "attach_restriction", "target": target, "text": line})
                parsed += 1
            else:
                unparsed.append(line)
            continue
        epic = re.fullmatch(r"epic action(?: \[([^\]]+)\])?:\s*(.+)", line, re.I) if base else None
        if epic:
            body = epic.group(2)
            effects, complete = compile_body(body)
            if body.lower().rstrip(".") == ("play a card from your hand, ignoring 1 of its vigilance, "
                                            "command, aggression, or cunning aspect penalties"):
                effects, complete = [{"op": "play_from_hand", "kind": "card", "ignore_one_basic_aspect": True}], True
            if effects and complete:
                abilities.append({"trigger": "action", "epic": True, "cost": parse_action_cost(epic.group(1) or ""),
                                  "effects": effects, "text": line})
                parsed += 1
            else:
                unparsed.append(line)
            continue
        m = re.match(r"^action(?: \[([^\]]*)\])?:\s*(.+)$", line, re.I)
        if m:
            eff, ok, limit = compile_limited_body(m.group(2), action=True)
            if eff and not inert(eff, ok):
                abilities.append({"trigger": "action", "cost": parse_action_cost(m.group(1) or ""), "effects": eff, "text": line, **limit})
            else:
                eff = [] if inert(eff, ok) else eff
            (parsed := parsed + 1) if ok and eff else unparsed.append(line)
            continue
        m = re.match(r"^attached (?:unit|base) gains:?\s*\"?(.+?)\"?$", line.rstrip("."), re.I)
        if m:
            inner = m.group(1).strip().strip('"')
            sub, _, sub_status = compile_text(inner, [])
            kw = re.match(r"^(sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+)$", inner.lower())
            if kw:
                parts = inner.lower().split()
                abilities.append({"trigger": "attached_kw", "kw": parts[0], "v": to_int(parts[1], 0) if len(parts) > 1 else 0, "text": line})
                parsed += 1
            elif sub and sub_status == "full":
                for a in sub:
                    a["granted"] = True
                abilities += sub
                parsed += 1
            else:
                unparsed.append(line)
            continue
        mf = re.match(r"^when a friendly ([a-z ]+?) unit attacks\s*:\s*(.+)$", line, re.I)
        if mf:
            eff, ok = compile_body(mf.group(2))
            if eff and ok:
                abilities.append({"trigger": "friendly_attack", "trait": mf.group(1).lower(), "effects": eff, "text": line})
                parsed += 1
            else:
                unparsed.append(line)
            continue
        played = re.fullmatch(r"when you play (.+?):\s*(.+)", line, re.I)
        if played:
            description, body = played.groups()
            play_filter = compile_play_trigger(description.lower())
            if play_filter is not None:
                body = re.sub(r"\bthat unit\b", "the played unit", body, flags=re.I)
                eff, ok = compile_body(body)
                if ok and eff:
                    abilities.append({"trigger": "friendly_card_played", "filter": play_filter,
                                      "effects": eff, "text": line})
                    parsed += 1
                    continue
        matched = False
        for pat, trig in TRIGGERS:
            mm = re.match(pat + r"\s*:\s*(.+)$", line, re.I)
            if mm:
                matched = True
                body = mm.group(1)
                if trig == ["nonleader_ground_enters"]:
                    body = re.sub(r"\bthat unit\b", "the played unit", body, flags=re.I)
                eff, ok, limit = compile_limited_body(body)
                if trig == ["enemy_unit_defeated"] and mm.group(1).lower().rstrip(".") == "deal 1 damage to its controller's base":
                    eff, ok = [{"op": "damage", "n": 1, "t": {"s": "subject_base"}}], True
                if trig == ["opponent_event"] and mm.group(1).lower().rstrip(".") == "deal 1 damage to that player's base":
                    eff, ok = [{"op": "damage", "n": 1, "t": {"s": "subject_base"}}], True
                if trig == ["base_damage"] and mm.group(1).lower().rstrip(".") == "you may deal 3 damage to a ground unit that opponent controls":
                    eff, ok = [{"op": "damage", "n": 3, "optional": True, "t": parse_target("an enemy ground unit")}], True
                if trig == ["unit_healed"] and mm.group(1).lower().rstrip(".") == "you may deal that much damage to a unit":
                    eff, ok = [{"op": "damage", "use_trigger_amount": True, "optional": True, "t": parse_target("a unit")}], True
                if trig[0] in {"enemy_unit_defeated", "friendly_leader_deployed", "when_attacked",
                              "when_claiming_initiative", "when_smuggled"} and not ok:
                    eff = []
                if inert(eff, ok):
                    eff = []
                if eff:
                    for tg in trig:
                        abilities.append({"trigger": tg, "effects": eff, "text": line, **limit})
                (parsed := parsed + 1) if ok and eff else unparsed.append(line)
                break
        if matched:
            continue
        # constant abilities we understand
        mm = re.match(r"^(?:this unit|he|she) can't attack bases$", low)
        if mm:
            abilities.append({"trigger": "constant", "flag": "no_base_attack", "text": line}); parsed += 1; continue
        # bare event body ("Deal 3 damage to a unit.")
        eff, ok = compile_body(line)
        if eff and ok:
            abilities.append({"trigger": "event", "effects": eff, "text": line}); parsed += 1
        else:
            unparsed.append(line)
    if not unparsed:
        status = "full"
    elif parsed or abilities:
        status = "partial"
    else:
        status = "manual"
    return abilities, unparsed, status


def compile_play_trigger(description: str) -> dict | None:
    if description == "a unit with 3 or less power":
        return {"kind": "unit", "max_power": 3}
    match = re.fullmatch(r"(a|an|another) (?:(\w+) )?(unit|card|event|upgrade)"
                         r"(?: that costs (\d+) or less|( from your resources)|( using smuggle))?", description)
    if not match:
        return None
    article, qualifier, kind, maximum, resource, smuggle = match.groups()
    target = {"kind": kind, "other": article == "another"}
    if maximum:
        target["max_cost"] = int(maximum)
    if resource or smuggle:
        target["from_resource"] = True
    if smuggle:
        target["smuggle"] = True
    if qualifier:
        if qualifier == "unique":
            target["unique"] = True
        elif qualifier in {"heroism", "villainy", "vigilance", "command", "aggression", "cunning"}:
            target["aspect"] = qualifier
        else:
            target["trait"] = qualifier
    return target


def compile_continuous(line: str):
    """Only exact recognized ongoing rules; never guess unknown text."""
    text = line.lower().rstrip(".").strip()
    if text == "you may look at the top card of your deck at any time":
        return {"trigger": "constant", "flag": "peek_own_deck", "text": line}
    if text == "if attached base would be dealt 5 or more damage, prevent that damage. if you do, defeat this upgrade and draw a card":
        return {"trigger": "constant", "flag": "base_damage_shield", "text": line}
    price = compile_price_rule(text)
    if price is not None:
        return {**price, "text": line}
    if text == "enemy units lose ambush and support":
        return {"trigger": "constant", "suppress_keywords": ["ambush", "support"], "text": line}
    if text == "opponents can't take control of this unit":
        return {"trigger": "constant", "flag": "cannot_take_control", "text": line}
    if text == "you assign all indirect damage you deal to opponents":
        return {"trigger": "constant", "flag": "assign_indirect", "text": line}
    if text == "you assign all indirect damage dealt by this unit":
        return {"trigger": "constant", "flag": "assign_unit_indirect", "text": line}
    if text == "indirect damage you deal to opponents is increased by 1":
        return {"trigger": "constant", "flag": "increase_indirect", "text": line}
    if text == "while attacking, this unit deals combat damage before the defender":
        return {"trigger": "constant", "flag": "first_strike", "text": line}
    condition = {}
    for pattern, value in [
        (r"^while you have the initiative, (.+)$", {"initiative": True}),
        (r"^while this unit is upgraded, (.+)$", {"upgraded": True}),
        (r"^while this unit is damaged, (.+)$", {"damaged": True}),
        (r"^while this unit is undamaged, (.+)$", {"undamaged": True}),
        (r"^while this unit is ready, (.+)$", {"ready": True}),
        (r"^coordinate\s*-\s*(.+)$", {"units_min": 3}),
    ]:
        match = re.fullmatch(pattern, text)
        if match:
            condition, text = value, match.group(1)
            break
    match = re.fullmatch(r"while you control (\d+) or more resources, (.+)", text)
    if match:
        condition, text = {"resources_min": int(match.group(1))}, match.group(2)
    target, other, trait = "self", False, ""
    match = re.fullmatch(r"(?:each )?(other )?friendly (?:(\w+) )?units? (.+)", text)
    if match:
        target, other, trait, text = "friendly", bool(match.group(1)), match.group(2) or "", match.group(3)
    else:
        match = re.fullmatch(r"each leader unit you control (.+)", text)
        if match:
            target, trait, text = "friendly", "leader", match.group(1)
        else:
            text = re.sub(r"^(this unit|he|she|it) ", "", text)
    match = re.fullmatch(r"gets? ([+-]\d+)/([+-]\d+)(?: for each (resource you control|card in your hand))?", text)
    result = {"trigger": "continuous", "target": target, "other": other, "trait": trait,
              "condition": condition, "text": line}
    if match:
        result.update(p=int(match.group(1)), h=int(match.group(2)))
        if match.group(3):
            result["scale_by"] = "resources" if match.group(3) == "resource you control" else "hand"
        return result
    if condition.get("units_min") and re.fullmatch(r"ambush|sentinel|grit|saboteur|overwhelm|raid \d+|restore \d+", text):
        text = "gains " + text
    if text.startswith(("gain ", "gains ")):
        keywords = re.split(r",\s*(?:and\s+)?|\s+and\s+", text.split(" ", 1)[1])
        entries = [re.fullmatch(r"(ambush|sentinel|grit|saboteur|overwhelm|raid|restore)(?: (\d+))?", part)
                   for part in keywords]
        if all(entries):
            if len(entries) == 1:
                result.update(kw=entries[0][1], v=int(entries[0][2] or 1))
            else:
                result["keywords"] = {entry[1]: int(entry[2] or 1) for entry in entries}
            return result
    if not condition and target == "self" and text == "can't attack":
        return {"trigger": "constant", "flag": "cannot_attack", "text": line}
    if line.lower().rstrip(".") == "this unit enters play ready":
        return {"trigger": "constant", "flag": "enters_ready", "text": line}
    return None


def compile_play_filter(description: str) -> dict | None:
    match = re.fullmatch(r"(?:(non-heroism, non-villainy|[a-z]+(?: [a-z]+)?) )?(card|unit|event|upgrade)", description)
    if not match:
        return None
    qualifier, kind = match.groups()
    result = {"kind": kind}
    if qualifier == "non-heroism, non-villainy":
        result["exclude_aspects"] = ["heroism", "villainy"]
    elif qualifier in {"heroism", "villainy", "vigilance", "command", "aggression", "cunning"}:
        result["aspect"] = qualifier
    elif qualifier:
        result["trait"] = qualifier
    return result


def compile_price_rule(text: str) -> dict | None:
    match = re.fullmatch(r"this (?:unit|event|upgrade|card) costs (\d+) less to play for each (.+)", text)
    if match:
        amount, phrase = match.groups()
        if phrase == "other card you played this phase":
            return {"trigger": "own_discount", "n": int(amount), "played": True}
        target = parse_target("each " + phrase)
        if target and target["kind"] == "unit":
            return {"trigger": "own_discount", "n": int(amount), "targets": target}
    match = re.fullmatch(r"this (?:unit|event|upgrade|card) costs (\d+) less to play for every (\d+) damage on your base", text)
    if match:
        return {"trigger": "own_discount", "n": int(match[1]), "base_damage_divisor": int(match[2])}
    match = re.fullmatch(r"(?:if|while) (.+), this (?:unit|event|upgrade|card) costs (?:c=)?(\d+) less to play", text)
    if match:
        clause, amount = match.groups()
        condition = compile_condition(clause)
        resources = re.fullmatch(r"you control (\d+) or more resources", clause)
        opponent_units = re.fullmatch(r"an opponent controls (\d+) or more (ground|space) units", clause)
        if resources:
            condition = {"resource_count": int(resources[1])}
        elif opponent_units:
            condition = {"control": {"kind": "unit", "side": "enemy", "arena": opponent_units[2]},
                         "min": int(opponent_units[1])}
        if condition is not None:
            return {"trigger": "own_discount", "n": int(amount), "condition": condition}
    match = re.fullmatch(r"each (.+?) you play costs (\d+) less", text)
    if match:
        selector = compile_play_filter(match[1])
        if selector is not None:
            return {"trigger": "play_discount", "filter": selector, "n": int(match[2])}
    match = re.fullmatch(r"the first (.+?) you play each (round|phase) costs (\d+) less", text)
    if match:
        selector = compile_play_filter(match[1])
        if selector is not None:
            return {"trigger": "play_discount", "filter": selector, "n": int(match[3]), "first": match[2]}
    return None


def parse_keywords(card: dict, text: str) -> list:
    out, seen = [], set()
    text = norm_text(text or "")
    # The source DB's Keywords index also lists keywords mentioned in conditional
    # abilities and attached-unit text. It is a search index, not a list of
    # unconditional abilities. Only standalone printed keyword lines grant one.
    listed = []
    for raw in text.split("\n"):
        printed = strip_reminders(raw).strip().rstrip(".").lower()
        for part in re.split(r",\s*|\s+and\s+", printed):
            match = re.fullmatch(r"([a-z]+)(?:\s+\d+)?(?:\s*\[[^\]]+\])?", part.strip())
            if match and match.group(1) in NATIVE_KEYWORDS and match.group(1) not in listed:
                listed.append(match.group(1))
    # The DB sometimes omits keywords from its list; bare keyword lines in the text count too.
    for line in text.split("\n"):
        m = re.match(r"^\s*([A-Za-z]+)(?:\s+\d+)?\s*(?:\(|$|\[|-)", strip_reminders(line) + "\n" if False else line)
        if m and m.group(1).lower() in ("bounty", "coordinate") and m.group(1).lower() not in listed:
            listed.append(m.group(1).lower())
    for kw in listed:
        k = kw.lower()
        if k in ("keyword", "keywords") or k in seen:
            continue
        seen.add(k)
        entry = {"k": k}
        if k in VALUE_KEYWORDS:
            m = re.search(rf"\b{k}\s+(\d+)", text, re.I)
            entry["v"] = int(m.group(1)) if m else 1
        if k in ("smuggle", "piloting"):
            m = re.search(rf"\b{k}\s*\[\s*C=(\d+)([^\]]*)\]", text, re.I)
            if m:
                entry["v"] = int(m.group(1))
                entry["aspects"] = [a.lower() for a in m.group(2).split()]
        out.append(entry)
    return out


SABER_HINTS = [("vader", "red"), ("sidious", "red"), ("palpatine", "red"), ("maul", "red"), ("dooku", "red"),
               ("kylo", "red"), ("ventress", "red"), ("inquisitor", "red"), ("windu", "purple"),
               ("yoda", "green"), ("qui-gon", "green"), ("ahsoka", "white"), ("rey", "yellow"),
               ("luke", "green"), ("obi-wan", "blue"), ("ben kenobi", "blue"), ("anakin", "blue")]


def saber_color(card: dict) -> str | None:
    traits = [t.lower() for t in card.get("Traits") or []]
    if "force" not in traits and "jedi" not in traits and "sith" not in traits:
        return None
    name = card["Name"].lower()
    for key, col in SABER_HINTS:
        if key in name:
            return col
    return "red" if "Villainy" in (card.get("Aspects") or []) or "sith" in traits else "blue"


def normalise(c: dict) -> dict:
    cid = card_id(c["Set"], c["Number"])
    typ = TYPE_MAP.get(c["Type"], c["Type"].lower())
    text = c.get("FrontText") or ""
    out = {
        "id": cid, "set": c["Set"], "number": c["Number"], "name": c["Name"].replace("C-3P0", "C-3PO"),
        "subtitle": c.get("Subtitle") or "", "type": typ,
        "arena": (c.get("Arenas") or [None])[0].lower() if c.get("Arenas") else None,
        "cost": to_int(c.get("Cost"), 0), "power": to_int(c.get("Power"), 0), "hp": to_int(c.get("HP"), 0),
        "aspects": [a.lower() for a in c.get("Aspects") or []],
        "traits": [t.lower() for t in c.get("Traits") or [] if t],
        "unique": bool(c.get("Unique")), "rarity": c.get("Rarity", ""),
        "text": norm_text(text), "art": art_name(cid),
    }
    if cid == "SOR_215":
        # The source dump calls this an Event and omits its printed +1/+1.
        typ = out["type"] = "upgrade"
        out.update(power=1, hp=1)
    out["keywords"] = parse_keywords(c, text)
    pilot_entry = next((k for k in out["keywords"] if k["k"] == "piloting" and "v" in k), None)
    stats = PILOT_STATS.get(cid.removeprefix("JTL_")) if cid.startswith("JTL_") else None
    if pilot_entry is not None and stats is not None and typ == "unit":
        abilities, unparsed, status = compile_pilot(out, pilot_entry, stats)
    else:
        rules_text = norm_text(text)
        if typ == "event":
            rules_text = re.sub(r"(?<=[.!])\n\s*(?=then\b|if you do\b)", " ", rules_text, flags=re.I)
        abilities, unparsed, status = compile_text(rules_text, out["keywords"], base=typ == "base")
    if typ == "leader":
        out["epic_cost"] = out["cost"]
        out["leader_unit"] = {"arena": out["arena"] or "ground", "power": out["power"], "hp": out["hp"],
                              "text": norm_text(c.get("BackText") or "")}
        back_kw = parse_keywords({"Keywords": c.get("Keywords")}, c.get("BackText") or "")
        out["leader_unit"]["keywords"] = [k for k in back_kw if re.search(rf"\b{k['k']}\b", c.get("BackText") or "", re.I)]
        out["keywords"] = [k for k in out["keywords"] if re.search(rf"\b{k['k']}\b", text, re.I)]
        b_ab, b_un, b_status = compile_text(c.get("BackText") or "", out["leader_unit"]["keywords"])
        out["leader_unit"]["abilities"] = b_ab
        out["art_back"] = cid
        unparsed += b_un
        if unparsed and (abilities or b_ab or status == "partial" or b_status == "partial"):
            status = "partial"
        elif unparsed:
            status = "manual"
    out["abilities"] = abilities
    out["unparsed"] = unparsed
    out["implemented"] = status
    sc = saber_color(c)
    if sc:
        out["saber"] = sc
    return out


def compile_pilot(card: dict, keyword: dict, stats: tuple[int, int]):
    unit_lines, upgrade_lines = re.split(r"(?im)^piloting\s*\[[^\]]+\][^\n]*", card["text"], maxsplit=1)
    unit_keywords = parse_keywords({}, unit_lines)
    card["keywords"] = unit_keywords + [keyword]
    abilities, missing, _ = compile_text(unit_lines, unit_keywords)
    upgrade_abilities, upgrade_missing = [], []
    for raw in upgrade_lines.strip().splitlines():
        line = strip_reminders(raw).strip()
        if not line:
            continue
        attach = re.fullmatch(r"when this upgrade attaches to a unit:\s*(.+)", line, re.I)
        if attach:
            body = re.sub(r"\bthat unit\b", "attached unit", attach.group(1), flags=re.I)
            effects, complete = compile_body(body)
            if effects and complete:
                upgrade_abilities.append({"trigger": "when_attached", "effects": effects, "text": line})
                continue
        parsed, rest, _ = compile_text(line, [])
        if not rest and parsed and all(a["trigger"] != "event" for a in parsed):
            # When played as a pilot, "this arena" is the host's arena and
            # "another unit" excludes the host, not the attached card.
            for ability in parsed:
                upgrade_abilities.append(ability)
        else:
            upgrade_missing.append(line)
    pilot = {"cost": keyword["v"], "aspects": keyword.get("aspects", []),
             "power": stats[0], "hp": stats[1], "abilities": upgrade_abilities}
    if card["id"] == "JTL_245":
        pilot["extra_slot"] = True
        upgrade_missing = [line for line in upgrade_missing if line not in {
            "This upgrade can be played on a friendly Vehicle unit with a Pilot on it.",
            'Attached unit gains: "You may play or deploy 1 additional Pilot on this unit."',
        }]
    card["pilot"] = pilot
    missing += upgrade_missing
    return abilities, missing, "partial" if missing else "full"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    args = ap.parse_args()
    raw = json.loads(Path(args.src).read_text(encoding="utf-8"))
    cards, seen = {}, set()
    for c in raw:
        if c.get("VariantType") != "Normal":
            continue
        n = normalise(c)
        if n["id"] in seen:
            continue
        seen.add(n["id"])
        cards[n["id"]] = n
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"version": 1, "count": len(cards), "cards": cards}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # coverage report
    by_status = collections.Counter(c["implemented"] for c in cards.values())
    by_set = collections.defaultdict(collections.Counter)
    for c in cards.values():
        by_set[c["set"]][c["implemented"]] += 1
    unparsed = collections.Counter()
    for c in cards.values():
        for u in c["unparsed"]:
            unparsed[re.sub(r"\d+", "N", u.split(":")[0])[:60]] += 1
    lines = ["# Card coverage report", "",
             f"Generated by `tools/import_cards.py` from `{Path(args.src).name}`. {len(cards)} unique cards.", "",
             "| Status | Cards | Meaning |", "|---|---|---|",
             f"| full | {by_status['full']} | Every line of text is compiled to the effect DSL or is a natively implemented keyword |",
             f"| partial | {by_status['partial']} | Some lines compiled; the rest are shown to the player but not enforced |",
             f"| manual | {by_status['manual']} | Printed rules require engine or importer support |", "",
             "## By set", "", "| Set | full | partial | manual |", "|---|---|---|---|"]
    for s in sorted(by_set):
        b = by_set[s]
        lines.append(f"| {s} | {b['full']} | {b['partial']} | {b['manual']} |")
    lines += ["", "## Most common uncompiled ability openers", "", "| Opener | Count |", "|---|---|"]
    for k, v in unparsed.most_common(40):
        lines.append(f"| {k.replace('|', '/')} | {v} |")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(cards)} cards -> {OUT}")
    print(dict(by_status))
    return 0


if __name__ == "__main__":
    sys.exit(main())
