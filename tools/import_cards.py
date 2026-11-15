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
PLANET_TRAITS = "tatooine|naboo|endor|kashyyyk"

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
MULTIWORD_TRAITS = ("bounty hunter", "capital ship", "first order", "new republic")


def trait_words(phrase: str) -> list[str]:
    return re.findall(rf"(?:{'|'.join(MULTIWORD_TRAITS)})(?=\s|$)|\S+", phrase)


def parse_target(phrase: str) -> dict | None:
    """Turn 'an enemy non-leader ground unit with 3 or less remaining HP' into a selector."""
    p = phrase.strip().rstrip(".").lower()
    if p.startswith("each of up to "):
        p = p.removeprefix("each of ")
    p = re.sub(r"^(?:to|from|on) ", "", p)
    simple = {
        "a unit or base": {"s": "choose", "kind": "unit_or_base", "side": "any"},
        "another unit or base": {"s": "choose", "kind": "unit_or_base", "side": "any", "other": True},
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
    m = re.match(r"^(each|all|a|an|another|up to (\w+)|(\w+)) ", p)
    if not m:
        return None
    lead = m.group(1)
    rest = p[m.end():]
    if lead in ("each", "all"):
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
                  r"ground |space |non-vehicle |vehicle |twi'lek |[a-z]+ )*)(units? or bases?|units?|bases?|upgrades?)(.*)$", rest)
    if not m2:
        return None
    adjs, noun, tail = trait_words(m2.group(1)), m2.group(2), m2.group(3).strip()
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
        mmin = re.fullmatch(r"with (\d+) or more (remaining hp|hp|power|cost)", tail) or \
            re.fullmatch(r"that costs (\d+) or more()", tail)
        mwo = re.match(r"^without an? (experience|shield) token on it$", tail)
        if mmin:
            field = {"remaining hp": "min_hp", "hp": "min_hp", "power": "min_power", "cost": "min_cost", "": "min_cost"}[mmin[2]]
            t[field] = int(mmin[1])
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
        elif (keyword := re.fullmatch(r"with (sentinel|hidden|overwhelm|saboteur|grit|ambush)", tail)):
            t["keyword"] = keyword[1]
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

    if disclosure := re.fullmatch(r"disclose ((?:(?:vigilance|command|aggression|cunning|heroism|villainy) ?)+)", low):
        return [{"op": "disclose", "aspects": disclosure[1].split(), "optional": opt}]
    if low == "reveal an event from your hand":
        return [{"op": "disclose", "kind": "event", "optional": opt}]
    if low == "ready a unit that didn't attack or enter play this phase":
        return wrap({"op": "ready", "t": {**parse_target("a unit"), "idle_this_phase": True}})
    if low == "you and an opponent each draw 2 cards":
        return [{"op": "draw", "n": 2, "who": "all"}]
    if entry := re.fullmatch(r"the next unit you play this phase(?: with (\d+) or less (?:printed )?power)? enters play ready", low):
        effect = {"op": "modify_next_unit", "ready": True}
        if entry[1]:
            effect["max_power"] = int(entry[1])
        return wrap(effect)
    if entry := re.fullmatch(r"the next unit you play this phase gains (ambush|hidden)(?: for this phase)?", low):
        return wrap({"op": "modify_next_unit", "keyword": entry[1]})
    if low == "bases can't be healed for this phase":
        return wrap({"op": "prevent_base_heal"})
    if ready := re.fullmatch(r"ready up to (\d+) resources", low):
        return [{"op": "choose_ready_resources", "n": int(ready[1])}]
    if low == "each opponent may ready a resource":
        return [{"op": "choose_ready_resources", "n": 1, "who": "opponent"}]
    if low == "that unit can't ready while this unit is in play":
        return [{"op": "prevent_ready", "while_source": True, "t": {"s": "it"}}]
    if low == "that unit can't ready during this regroup phase":
        return [{"op": "prevent_ready", "dur": "regroup", "t": {"s": "it"}}]
    if movement := re.fullmatch(r"move (this unit|a (?:ground|space) unit) to the (ground|space) arena", low):
        return wrap({"op": "move_arena", "arena": movement[2], "t": parse_target(movement[1])})
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
    if low == "play it again from your discard pile for free":
        return wrap({"op": "play_from_hand", "kind": "event", "source_zone": "discard", "only_selected": True, "free": True})
    if low == "put a card from your hand on top of your deck":
        return wrap({"op": "_bottom_from_hand", "top": True})
    phase_targets = {
        "ready a unit that was damaged this phase": ("ready", "damaged_this_phase"),
        "defeat a unit that dealt damage to a base this phase": ("defeat", "damaged_a_base"),
    }
    if low in phase_targets:
        op, qualification = phase_targets[low]
        return wrap({"op": op, "t": {**parse_target("a unit"), qualification: True}})
    if low in ("put this card into play as a resource", "put this unit into play as a resource"):
        return wrap({"op": "resource_self"})
    if low == "defeat a friendly resource":
        return wrap({"op": "_choose_defeat_resource"})
    if low in ("return a resource you control to its owner's hand", "return a friendly resource to its owner's hand"):
        return wrap({"op": "_return_resource"})
    if bottom := re.fullmatch(r"put a (?:(clone) unit|(aggression) card|(card)) from your discard pile on the bottom of your deck", low):
        effect = {"op": "recover", "destination": "deck", "bottom": True}
        if bottom[1]:
            effect.update(kind="unit", trait=bottom[1])
        if bottom[2]:
            effect["aspect"] = bottom[2]
        return wrap(effect)
    if recover := re.fullmatch(r"return (.+) from (your discard pile|a discard pile) to (?:your|its owner's) hand", low):
        description = recover[1]
        was_defeated = description.endswith((" that was defeated this phase", " that were defeated this phase"))
        description = re.sub(r" that (?:was|were) defeated this phase$", "", description)
        target = {"kind": "event"} if description == "an event" else parse_target(description)
        if target and target["kind"] in {"unit", "upgrade", "event"}:
            effect = {"op": "recover", "kind": target["kind"], "other_discard": recover[2] == "a discard pile"}
            if was_defeated:
                effect["defeated_this_phase"] = True
            if target.get("s") == "each":
                effect["count"] = 999
            for key in ("trait", "not_trait", "max_cost", "count", "upto"):
                if key in target:
                    effect[key] = target[key]
            return wrap(effect)
    if low in ("it doesn't ready during the next regroup phase", "this unit doesn't ready during the next regroup phase"):
        return wrap({"op": "skip_regroup_ready", "t": {"s": "it" if low.startswith("it ") else "self"}})
    if low == "heal all damage from him and give a shield token to him":
        return [{"op": "heal", "all_damage": True, "t": {"s": "attached"}},
                {"op": "shield", "t": {"s": "attached"}}]
    if low == "reveal the top card of your deck":
        return wrap({"op": "reveal_top"})
    if low == "discard a card from the defending player's deck":
        return wrap({"op": "mill", "n": 1, "who": "defending_player"})
    if low == "exhaust a resource that player controls":
        return wrap({"op": "exhaust_defender_resource"})
    if low == "search your deck for a card and draw it":
        return [{"op": "search", "whole_deck": True, "reveal_selected": False}]
    search = compile_deck_draw_search(low)
    if search is not None:
        return wrap(search)
    search = compile_deck_play_search(low)
    if search is not None:
        return wrap(search)
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
    if low in ("a friendly unit captures an enemy non-leader unit", "a friendly unit captures an enemy non-leader unit in the same arena"):
        return wrap({"op": "capture", "same_arena": low.endswith("in the same arena")})
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
    if low in ("put this event into play as a resource", "resource this card"):
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

    if low == "defeat all units":
        return wrap({"op": "defeat", "t": {"s": "each", "kind": "unit"}})
    if low == "that unit can't ready this round":
        return [{"op": "prevent_ready", "t": {"s": "it"}}]
    if low == "that unit's controller draws a card":
        return [{"op": "draw", "who": "selected_controller", "if_did": True}]
    if low == "that player discards a card from their hand":
        return [{"op": "discard", "who": "selected_player"}]
    if low == "choose a player":
        return [{"op": "choose_player"}]
    m = re.fullmatch(r"they draw (a|an|one|two|three|\d+) cards?", low)
    if m:
        return [{"op": "draw", "n": num(m[1]), "who": "selected_player"}]
    m = re.fullmatch(r"look at an opponent's hand and discard (a card|a non-unit card|an event|a unit) from it", low)
    if m:
        kinds = {"a card": "card", "a non-unit card": "non-unit", "an event": "event", "a unit": "unit"}
        return [{"op": "discard", "who": "opponent", "chooser": "self", "kind": kinds[m[1]], "look_at_hand": True}]

    m = re.match(r"^deal (\d+) damage to (.+)$", low)
    if m and parse_target(m.group(2)):
        return wrap({"op": "damage", "n": int(m.group(1)), "t": parse_target(m.group(2))})
    m = re.fullmatch(r"(an?(?:other)? friendly (?:[a-z ]+ )?unit) deals damage equal to its power to (.+)", low)
    if m and (source := parse_target(m[1])) and (target := parse_target(m[2])):
        return [{"op": "select", "t": source}, {"op": "damage_from_it", "if_did": True, "t": target}]
    if low == "a friendly unit deals damage to an enemy unit equal to the amount of damage on the friendly unit plus 1":
        return [{"op": "select", "t": parse_target("a friendly unit")},
                {"op": "damage_from_it", "amount": "damage_plus_one", "if_did": True,
                 "t": parse_target("an enemy unit")}]
    if low == "that unit deals damage equal to its power to an enemy unit in the same arena":
        return [{"op": "damage_from_it", "if_did": True,
                 "t": {**parse_target("an enemy unit"), "arena_of_it": True}}]
    m = re.match(r"^deal (\d+) damage to (.+) and (\d+) damage to (.+)$", low)
    if m:
        t1, t2 = parse_target(m.group(2)), parse_target(m.group(4))
        if t1 and t2:
            first = wrap({"op": "damage", "n": int(m.group(1)), "t": t1})
            second = {"op": "damage", "n": int(m.group(3)), "t": t2}
            if opt:
                second["if_did"] = True
            return first + [second]
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
    if dual := re.fullmatch(r"give (?:a|an) (shield|experience|advantage|weakness) token and (?:a|an) (shield|experience|advantage|weakness) token to (.+)", low):
        target = parse_target(dual[3])
        if target and target.get("count", 1) == 1:
            return [{"op": "give_pair", "tokens": [dual[1], dual[2]], "t": {**target, **({"opt": True} if opt else {})}}]
    m = re.match(r"^give (.+?) (a|an|one|two|three|\d+) (shield|experience|advantage|weakness) tokens?$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": m.group(3), "n": num(m.group(2)), "t": t}) if t else None
    m = re.match(r"^(exhaust|ready|defeat) (.+)$", low)
    if m and not m.group(2).startswith(("a resource", "this leader", "your")):
        t = parse_target(m.group(2))
        return wrap({"op": m.group(1), "t": t}) if t else None
    m = re.match(r"^ready (a|one|two|\d+) (?:friendly )?resources?$", low)
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
    m = re.match(r"^(.+?) gains? (sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+) (?:for )?this (phase|attack)$", low) or \
        re.match(r"^give (.+?) (sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+) (?:for )?this (phase|attack)$", low)
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
    m = re.fullmatch(r"create (a|an|one|two|three|\d+) (battle droid|clone trooper|tie fighter|x-wing|spy|mandalorian|credit|beast) tokens?( and ready (?:it|them))?", low)
    if m:
        effect = {"op": "token", "name": TOKEN_NAMES[m[2]], "n": num(m[1])}
        if m[3]:
            if effect["name"] == "credit":
                return None
            effect["ready"] = True
        return wrap(effect)
    if m := re.fullmatch(r"create another (battle droid|clone trooper|tie fighter|x-wing|spy|mandalorian|beast) token", low):
        return wrap({"op": "token", "name": TOKEN_NAMES[m[1]]})
    # "Play a [Trait] unit|event|card from your hand [(paying its cost)]"
    m = re.match(r"^play (a|an|2) ((?:[a-z-]+ )*?)(unit|event|card|upgrade|non-unit card)( that costs (\d+) or less)?( with (\d+) or less power)? from your hand(.*)$", low)
    if m:
        words = trait_words(m.group(2))
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
    if p == "the force is with you":
        return {"force_token": True}
    if m := re.fullmatch(rf"you control an? ({PLANET_TRAITS}) base", p):
        return {"base_trait": m[1]}
    if m := re.fullmatch(rf"you control (another \w+ unit) or an? ({PLANET_TRAITS}) base", p):
        return {"any": [compile_condition("you control " + m[1]), {"base_trait": m[2]}]}
    if p == "you control an upgraded base":
        return {"base_upgraded": True}
    if leave := re.fullmatch(r"an? (?:(friendly|enemy) )?unit left play this phase", p):
        return {"units_left_play": leave[1] or "any"}
    if p == "it's the first round of the game":
        return {"round_is": 1}
    if p == "a leader unit has been defeated this phase":
        return {"leader_defeated_this_phase": True}
    if p == "this unit is attacking an exhausted unit that didn't enter play this round":
        return {"exhausted_older_defender": True}
    if p in ("you've attacked with a token unit this phase", "you attacked with a token unit this phase"):
        return {"attacked_trait": "", "attacked_token": True}
    if match := re.fullmatch(r"(?:you've|you) dealt (?:(\d+) or more )?damage to an enemy base this phase", p):
        return {"enemy_base_damage_dealt": int(match[1] or 1)}
    if p == "an enemy unit has attacked your base this phase":
        return {"your_base_attacked": True}
    if p == "you control another resistance card":
        return {"any": [{"control": {"kind": kind, "side": "friendly", "trait": "resistance", "other": True}}
                        for kind in ("unit", "upgrade", "leader", "base")]}
    if p == "you control a ground unit and a space unit":
        return {"both_arenas": True}
    if p == "you control no token units":
        return {"not": {"control": parse_target("a friendly token unit")}}
    if p in ("this unit is upgraded", "this unit has a pilot on it"):
        return {"upgraded": True} if p.endswith("upgraded") else {"piloted": True}
    if m := re.fullmatch(r"this unit has (\d+) or more power", p):
        return {"source_min_power": int(m[1])}
    if p in ("you control more units than an opponent", "you control fewer units than an opponent"):
        return {"compare_units": "more" if " more " in p else "fewer"}
    if p == "each resource you control is exhausted":
        return {"all_resources_exhausted": True}
    if m := re.fullmatch(r"you have (\d+) or more cards in your hand", p):
        return {"hand_min": int(m[1])}
    if p == "you have more cards in hand than an opponent":
        return {"more_hand_cards": True}
    if p == "there are at least 3 aspects among other friendly units":
        return {"other_unit_aspects_min": 3}
    if m := re.fullmatch(r"a base has (\d+) or more damage on it", p):
        return {"any_base_damage_min": int(m[1])}
    if m := re.fullmatch(r"an enemy unit is (damaged|exhausted|upgraded)", p):
        return {"control": parse_target(f"an enemy {m[1]} unit")}
    if m := re.fullmatch(r"(?:you control|an opponent controls) (\d+) or more (.+ units?|units)", p):
        if t := parse_target("a " + m[2].removesuffix("s")):
            t.update(side="friendly" if p.startswith("you ") else "enemy", s="count")
            return {"control": t, "min": int(m[1])}
    if m := re.fullmatch(r"an opponent controls (.+ unit)", p):
        if t := parse_target(m[1]):
            t.update(side="enemy", s="count")
            return {"control": t}
    if p in ("you control a force unit or upgrade", "you control a force unit or a force upgrade"):
        return {"any": [compile_condition("you control a force unit"), compile_condition("you control a force upgrade")]}
    if p == "you control a force leader":
        return {"leader_trait": "force"}
    if p in ("you control jabba the hutt", "you control emperor palpatine", "you control padm� amidala", "you control padmé amidala"):
        return {"controls_name": p.removeprefix("you control ").replace("padm�", "padmé")}
    if p == "you control boba fett or jango fett":
        return {"any": [{"controls_name": name} for name in ("Boba Fett", "Jango Fett")]}
    if p in ("attached unit is luke skywalker", "attached unit is darth vader"):
        return {"attached_name": p.removeprefix("attached unit is ")}
    if p == "you control grand moff tarkin":
        return {"controls_name": "Grand Moff Tarkin"}
    if p == "it's aggression":
        return {"revealed_aspect": "aggression"}
    if p == "it's not a unit":
        return {"revealed_kind_not": "unit"}
    if p in ("it's an event", "you discarded an upgrade this way"):
        return {"discarded_kind": "event" if p.startswith("it's") else "upgrade"}
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
        if t and t.get("kind") in {"unit", "upgrade"}:
            t["side"] = "friendly"
            t["s"] = "count"
            return {"control": t, "min": t.pop("count", 1)}
    m = re.match(r"^you control (\d+|two|three|four) or more (.+)$", p)
    if m:
        t = parse_target("a " + m.group(2).rstrip("s"))
        if t:
            t["side"] = "friendly"; t["s"] = "count"
            return {"control": t, "min": num(m.group(1))}
    m = re.fullmatch(r"an enemy unit (?:was|has been) defeated this phase", p)
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


def compile_deck_draw_search(text: str) -> dict | None:
    if text == "search the top 8 cards of your deck for a card and resource it":
        return {"op": "search", "n": 8, "destination": "resource"}
    ordered = re.fullmatch(r"search the top (\d+) cards of your deck for up to (\d+) (.+? units), reveal them, and put them on top of your deck in any order", text)
    if ordered and (selector := parse_target("a " + ordered[3])):
        return {"op": "search", "n": int(ordered[1]), "count": int(ordered[2]),
                "filter": selector, "destination": "deck_top"}
    search = re.fullmatch(r"search (?:the top (\w+) cards of )?your deck for (a|an|(?:up to )?(?:\d+|one|two|three|four|five)) (.+?)"
                          r"(, reveal (?:it|them),?)? and draw (?:it|them)", text)
    if not search:
        return None
    scope, amount, what, reveal = search.groups()
    filters = {
        "vigilance, aggression, or cunning unit": {"kind": "unit", "aspects_any": ["vigilance", "aggression", "cunning"]},
        "bounty hunter, item, or transport card": {"traits_any": ["bounty hunter", "item", "transport"]},
        "mandalorian and/or upgrade cards": {"any_of": [{"trait": "mandalorian"}, {"kind": "upgrade"}]},
        "unit that shares an aspect with a friendly unit": {"kind": "unit", "shared_aspect": True},
        "card that shares a trait with a unit you control": {"shared_trait": True},
        "non-unit cards": {"kind": "non-unit"},
    }.get(what)
    if filters is None:
        if what.endswith(("card", "cards")):
            qualifier = re.sub(r"(?:^| )cards?$", "", what)
            if qualifier and not (re.fullmatch(r"[a-z]+", qualifier) or qualifier in MULTIWORD_TRAITS):
                return None
            filters = compile_play_filter(qualifier + " card") if qualifier else {}
        elif event := re.fullmatch(r"([a-z]+) event", what):
            filters = compile_play_filter(event[0])
        else:
            filters = parse_target("a " + what)
        if filters is None:
            return None
    effect = {"op": "search", "filter": filters, "reveal_selected": bool(reveal),
              "count": 1 if amount in {"a", "an"} else num(amount.split()[-1])}
    if scope:
        effect["n"] = num(scope)
    else:
        effect["whole_deck"] = True
    return effect


def compile_special(sent: str) -> list | None:
    low = sent.lower().rstrip(".")
    if low.startswith("search "):
        return compile_sentence(sent)
    if low == "look at the top card of your deck":
        return [{"op": "scry", "n": 1}]
    if low == "you may put it on the bottom of your deck":
        return []  # folded into scry
    return None


def compile_deck_play_search(text: str) -> dict | None:
    if text == ("search the top 7 cards of your deck for a vehicle and play it. it costs 5 less and enters play ready. "
                "return it to its owner's hand at the end of the phase"):
        return {"op": "search", "n": 7, "filter": {"trait": "vehicle"},
                "play": {"discount": 5, "ready": True, "return_at_phase_end": True}}
    if text == ("search the top 5 cards of your deck for an underworld unit and play it. it costs 4 less and enters play ready. "
                "at the start of the regroup phase, put that unit on the bottom of your deck"):
        return {"op": "search", "n": 5, "filter": {"kind": "unit", "trait": "underworld"},
                "play": {"discount": 4, "ready": True, "bottom_at_regroup": True}}
    if text == ("search the top 5 cards of your deck, or 10 cards instead if this unit is unique, "
                "for a unit that costs 3 or less and play it for free"):
        return {"op": "search", "n": 5, "n_if_unique": 10, "filter": {"kind": "unit", "max_cost": 3},
                "play": {"free": True}}
    multiple = re.fullmatch(r"search the top (\d+) cards of your deck for (any number of|up to \d+) "
                            r"((?:.+? )?units) with combined cost (\d+) or less,? and play each of them for free", text)
    if multiple:
        scope, quantity, units, limit = multiple.groups()
        selector = parse_target("a " + units)
        if selector is not None and selector.get("kind") == "unit":
            return {"op": "search", "n": int(scope), "filter": selector, "play": {"free": True},
                    "count": int(scope) if quantity == "any number of" else int(quantity.split()[-1]),
                    "combined_cost": int(limit)}
    single = re.fullmatch(r"search the top (\d+) cards of your deck for (a (?:.+? )?unit), reveal it, and play it\. it costs (\d+) less", text)
    if single and (selector := parse_target(single[2])):
        return {"op": "search", "n": int(single[1]), "filter": selector, "play": {"discount": int(single[3])}}
    source_power = re.fullmatch(r"search the top (\d+) cards of your deck for a unit that costs the same as or less than this unit's power\. "
                                r"play it for free\. it enters play ready", text)
    if source_power:
        return {"op": "search", "n": int(source_power[1]), "filter": {"kind": "unit"},
                "max_from_source_power": True, "play": {"free": True, "ready": True}}
    damage = re.fullmatch(r"search the top (\d+) cards of your deck for up to (\d+) units that each cost (\d+) or less, "
                          r"play them for free, and deal (\d+) damage to each of them", text)
    if damage:
        return {"op": "search", "n": int(damage[1]), "count": int(damage[2]),
                "filter": {"kind": "unit", "max_cost": int(damage[3])}, "play": {"free": True}, "damage_played": int(damage[4])}
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
    text = body.strip().rstrip(".").lower()
    if text == "draw 2 cards. each opponent whose base you've damaged this phase discards 2 cards from their hand":
        return [{"op": "draw", "n": 2}, {"op": "discard", "n": 2, "who": "opponent", "if": {"enemy_base_damage_dealt": 1}}], True
    if text in ("choose a friendly unit. each enemy unit gets -4/-0 while attacking that unit this phase",
                "choose a friendly unit. for this phase, while that unit is defending, the attacker gets -4/-0"):
        return [{"op": "reduce_attackers_power", "n": 4, "t": parse_target("a friendly unit")}], True
    if text == "you may defeat a unit that attacked your base this phase. if it's a leader unit, defeat this unit":
        return [{"op": "defeat", "t": {**parse_target("a unit"), "attacked_your_base": True, "opt": True}},
                {"op": "defeat", "t": {"s": "self"}, "if_did": True, "if": {"selected_leader": True}}], True
    if text == "use the force. if you do, attack with a unit. it gets +2/+0 for this attack and deals its combat damage before the defender":
        return [{"op": "use_force"}, {"op": "attack_with", "if_did": True, "first_strike": True,
                "pre": [{"op": "buff", "p": 2}], "t": {**parse_target("a friendly unit"), "ready": True, "can_attack": True}}], True
    if re.fullmatch(r"if you played an event this phase, this unit gets \+1/\+0 for this attack and deals combat damage before the defend(?:er|ing unit)", text):
        condition = {"played_kind": "event"}
        return [{"op": "buff", "p": 1, "h": 0, "dur": "attack", "if": condition, "t": {"s": "self"}},
                {"op": "combat_first_strike", "if": condition, "t": {"s": "self"}}], True
    if defender := re.fullmatch(r"if the defender (is exhausted|has a bounty), it gets -4/-0 for this attack", text):
        return [{"op": "buff", "p": -4, "dur": "attack", "t": {"s": "defender"},
                "if": {"defender_state": "exhausted" if defender[1] == "is exhausted" else "bounty"}}], True
    if search := compile_deck_play_search(text):
        return [search], True
    han = re.fullmatch(r"put (a card from your hand|the top card of your deck) into play as a resource and ready it\. "
                       r"at the start of the next action phase, defeat a resource you control", text)
    if han:
        op = "_resource_hand" if han[1] == "a card from your hand" else "resource_top"
        return [{"op": op, "ready": True}, {"op": "schedule_action_start", "effects": [{"op": "_choose_defeat_resource"}]}], True
    # Apply the official errata for SEC_245 to the original printed wording too.
    if text in ("play a card with plot from your resources. put the top card of your deck into play as a resource",
                "play a card with plot from your resources. if you do, put the top card of your deck into play as a resource"):
        return [{"op": "play_from_hand", "source_zone": "resource", "keyword": "plot", "resource_on_play": True}], True
    if text in ("defeat a friendly non-leader unit. then, you may play that unit from your discard pile for free",
                "you may defeat a friendly night unit not named old daka. then, you may play that unit from your discard pile for free"):
        if text.startswith("you may "):
            target = {**parse_target("a friendly night unit"), "opt": True, "not_name": "old daka"}
        else:
            target = parse_target("a friendly non-leader unit")
        return [{"op": "defeat", "t": target}, {"op": "play_from_hand", "kind": "unit", "source_zone": "discard",
                "optional": True, "only_selected": True, "free": True, "if_did": True}], True
    if text == ("if an enemy unit was defeated this phase, play an upgrade from your hand or from any player's discard pile, "
                "ignoring its aspect penalty"):
        return [{"op": "play_from_hand", "kind": "upgrade", "source_zone": "hand_or_discard", "ignore_aspects": True,
                "if": {"enemy_defeated_this_phase": True}}], True
    if text == "you may play an upgrade from your discard pile on a friendly non-vehicle unit. it costs 1 less":
        return [{"op": "play_from_hand", "kind": "upgrade", "source_zone": "discard", "discount": 1, "optional": True,
                 "attachment_filter": parse_target("a friendly non-vehicle unit")}], True
    if text == ("play an upgrade from your hand on a friendly non-vehicle unit. it costs 1 less. "
                "if you do, deal 1 damage to that unit"):
        return [{"op": "play_from_hand", "kind": "upgrade", "discount": 1, "attachment_filter": parse_target("a friendly non-vehicle unit"),
                 "attachment_damage": 1}], True
    if text == ("choose another card in your discard pile. search the top 5 cards of your deck "
                "for a card that shares a trait with the chosen card, reveal it, and draw it"):
        return [{"op": "recover", "select_only": True, "exclude_source": True},
                {"op": "search", "n": 5, "share_selected_trait": True, "if_did": True}], True
    if text == "you may return a force unit and a lightsaber upgrade from your discard pile to your hand":
        return [{"op": "choose_one", "optional": True, "options": [{"label": "Return cards from your discard pile", "effects": [
            {"op": "recover", "kind": "unit", "trait": "force"},
            {"op": "recover", "kind": "upgrade", "trait": "lightsaber"}]}]}], True
    if text == ("put up to 3 force units from your discard pile on the bottom of your deck in a random order. "
                "give that many units +4/+4 for this phase"):
        return [{"op": "recover", "kind": "unit", "trait": "force", "count": 3, "upto": True,
                 "destination": "deck", "bottom": True, "random_order": True},
                {"op": "buff", "p": 4, "h": 4, "dur": "phase", "if_did": True,
                 "t": {**parse_target("a unit"), "count_from_discard": True}}], True
    if text == "put a unit from your discard pile on the bottom of your deck. deal damage equal to that unit's power to an enemy ground unit":
        return [{"op": "recover", "kind": "unit", "destination": "deck", "bottom": True},
                {"op": "damage", "amount": "selected_printed_power", "t": parse_target("an enemy ground unit"), "if_did": True}], True
    if text in ("choose a unit in your discard pile. if it was defeated this phase, put it into play as a resource",
                "choose a card in your discard pile. put it into play as a resource if it shares a name with a unit you control"):
        defeated = "defeated this phase" in text
        return [{"op": "recover", "kind": "unit" if defeated else "card", "select_only": True},
                {"op": "resource_selected_discard", "if_did": True,
                 "if": {"selected_defeated" if defeated else "selected_name_controlled": True}}], True
    if text == "you may put this card from your discard pile on top of your deck. if you do, heal 2 damage from a base":
        return [{"op": "recover_self", "optional": True, "top": True},
                {"op": "heal", "n": 2, "t": parse_target("a base"), "if_did": True}], True
    if text == ("search the top 10 cards of your deck for 2 non-unit cards, reveal them, and draw them. "
                "then, if this unit isn't unique, discard a card from your hand"):
        search = compile_deck_draw_search(text.split(". ")[0])
        return [search, {"op": "discard", "if": {"source_nonunique": True}}], True
    if text == ("you may search the top 8 cards of your deck for a droid unit, reveal it, and draw it. "
                "if it costs 2 or less, you may play it for free"):
        search = compile_deck_draw_search(text.split(". ")[0].removeprefix("you may "))
        return [{**search, "optional": True}, {"op": "play_from_hand", "kind": "unit", "optional": True,
                "max_cost": 2, "only_selected": True, "free": True}], True
    discard_play = re.fullmatch(r"(you may )?play (a (?:heroism )?unit(?: that was defeated this phase)?) "
                                r"from your discard pile\. it costs (\d+) less", text)
    if discard_play:
        optional, target, discount = discard_play.groups()
        effect = {"op": "play_from_hand", "kind": "unit", "source_zone": "discard", "discount": int(discount),
                  "optional": bool(optional), "defeated_this_phase": "defeated" in target}
        if "heroism" in target:
            effect["aspect"] = "heroism"
        return [effect], True
    if text == "play up to 3 non-vehicle units that each cost 2 or less from your discard pile for free":
        return [{"op": "play_from_hand", "kind": "unit", "source_zone": "discard", "not_trait": "vehicle",
                 "max_cost": 2, "count": 3, "optional": True, "free": True}], True
    if text == "play a vehicle unit from your discard pile. then, deal 1 damage to it":
        return [{"op": "play_from_hand", "kind": "unit", "source_zone": "discard", "trait": "vehicle", "deal_damage_on_play": 1}], True
    temporary_play = re.fullmatch(r"(you may )?play (a unit(?: that was defeated this phase)?|an item upgrade) "
                                  r"from your (hand|discard pile)\. it costs (\d+) less( and enters play ready)?\. "
                                  r"at the start of the(?: next)? regroup phase, defeat it", text)
    if temporary_play:
        optional, target, zone, discount, ready = temporary_play.groups()
        effect = {"op": "play_from_hand", "kind": "upgrade" if target == "an item upgrade" else "unit",
                  "optional": bool(optional), "source_zone": "discard" if zone == "discard pile" else "hand",
                  "discount": int(discount), "ready": bool(ready), "defeat_at_regroup": True}
        if target == "an item upgrade":
            effect["trait"] = "item"
        if "defeated" in target:
            effect["defeated_this_phase"] = True
        return [effect], True
    if text == "play a unit from your discard pile. it costs 6 less. if it's a force unit, it costs 8 less instead":
        return [{"op": "play_from_hand", "kind": "unit", "source_zone": "discard", "discount": 6, "force_discount": 8}], True
    if text in ("play a non-vehicle from your discard pile and give an experience token to it",
                "play a non-vehicle unit from your discard pile and give an experience token to it"):
        return [{"op": "play_from_hand", "kind": "unit", "not_trait": "vehicle", "source_zone": "discard", "give_experience": 1}], True
    if text == ("put a force unit from your discard pile on the bottom of your deck. "
                "if you do, play a unit from your hand and give 2 experience tokens to it"):
        return [{"op": "recover", "kind": "unit", "trait": "force", "destination": "deck", "bottom": True},
                {"op": "play_from_hand", "kind": "unit", "if_did": True, "give_experience": 2}], True
    if text == "you may deal damage to a unit equal to the number of damaged enemy units":
        return [{"op": "damage", "t": {**parse_target("a unit"), "opt": True, "min_hp": 1},
                 "count_targets": {**parse_target("a damaged enemy unit"), "min_hp": 1}}], True
    if counted := compile_counted_trigger(body):
        return counted, True
    if text == "you may use the force. if you do, draw 2 cards. if you do not, draw a card":
        return [{"op": "use_force", "optional": True}, {"op": "draw", "n": 2, "if_did": True},
                {"op": "draw", "if_not_did": True}], True
    if text == "exhaust a friendly unit. if you do, give a shield token and 2 experience tokens to it":
        return [{"op": "exhaust", "t": parse_target("a friendly unit")},
                {"op": "give_pair", "tokens": ["shield", "experience", "experience"], "t": {"s": "it"}, "if_did": True}], True
    if text == ("discard a lightsaber card from your hand. if you do, "
                "deal 4 damage to a ground unit and draw a card"):
        return [{"op": "discard", "trait": "lightsaber"},
                {"op": "damage", "n": 4, "t": parse_target("a ground unit"), "if_did": True},
                {"op": "draw", "if": {"discarded_trait": "lightsaber"}}], True
    if text == "choose a player. they discard 2 cards from their hand":
        return [{"op": "choose_player"}, {"op": "discard", "n": 2, "who": "selected_player"}], True
    if text in ("each player discards a card from their hand", "each player discards all but 2 cards from their hand"):
        return [{"op": "discard", "who": who, **({"keep": 2} if "all but" in text else {})}
                for who in ("self", "opponent")], True
    if text == "return each unit in your discard pile that was defeated this phase to your hand":
        return [{"op": "recover", "kind": "unit", "defeated_this_phase": True, "all": True}], True
    if text == "draw 3 cards, then put a card from your hand on the top of your deck and another card from your hand on the bottom of your deck":
        return [{"op": "draw", "n": 3}, {"op": "_bottom_from_hand", "top": True}, {"op": "_bottom_from_hand"}], True
    if text == "draw 2 cards. if you control no token units, put 2 cards from your hand on the bottom of your deck in any order":
        return [{"op": "draw", "n": 2}, {"op": "_bottom_from_hand", "n": 2, "if": compile_condition("you control no token units")}], True
    if text == "ready a unit that was played this phase. if it costs 3 or less, create a spy token":
        return [{"op": "ready", "t": {**parse_target("a unit"), "played_by_either": True}},
                {"op": "token", "name": "spy", "if_did": True, "if": {"selected_max_cost": 3}}], True
    if text == "ready each unit you control. at the start of the regroup phase, you lose the game":
        return [{"op": "ready", "t": parse_target("each friendly unit")},
                {"op": "schedule_regroup", "effects": [{"op": "game_result"}]}], True
    if text == "draw a card. at the start of the regroup phase, discard a card from your hand":
        return [{"op": "draw"}, {"op": "schedule_regroup", "effects": [{"op": "discard"}]}], True
    arena_regroup = {
        "choose an arena. at the start of the next regroup phase, deal 3 damage to each enemy unit in that arena": "damage",
        "choose an arena. at the start of the regroup phase, if you are the only player who controls units in that arena, you win the game": "game_result",
    }.get(text)
    if arena_regroup:
        options = []
        for arena in ("ground", "space"):
            effect = {"op": arena_regroup}
            if arena_regroup == "damage":
                effect.update(n=3, t={"s": "each", "kind": "unit", "side": "enemy", "arena": arena})
            else:
                effect.update(win=True, **{"if": {"sole_arena_control": arena}})
            options.append({"label": arena.title(), "arena": arena,
                            "effects": [{"op": "schedule_regroup", "effects": [effect]}]})
        return [{"op": "choose_one", "options": options}], True
    if text == "you may pay 2. if you do, move this unit to the ground arena and give 2 experience tokens to it":
        return [{"op": "pay_resources", "optional": True, "n": 2},
                {"op": "move_arena", "arena": "ground", "t": {"s": "self"}, "if_did": True},
                {"op": "experience", "n": 2, "t": {"s": "self"}, "if_did": True}], True
    if combat := compile_attack_action(text):
        return combat, True
    if text == 'deal 7 damage to an enemy unit unless its controller says "no." if they do, draw 3 cards':
        return [{"op": "select", "t": parse_target("an enemy unit")},
                {"op": "choose_one", "who": "selected_controller", "if_did": True, "options": [
                    {"label": "Take 7 damage", "effects": [{"op": "damage", "n": 7, "t": {"s": "it"}}]},
                    {"label": "Say no · opponent draws 3 cards", "effects": [{"op": "draw", "n": 3}]},
                ]}], True
    if text == ("heal up to 3 damage from a unit. if you control a force unit, "
                "you may deal that much damage to another unit"):
        return [{"op": "heal_up_to", "n": 3, "t": parse_target("a unit")},
                {"op": "damage", "amount": "healed", "if_did": True,
                 "if": compile_condition("you control a force unit"), "optional": True,
                 "t": {**parse_target("a unit"), "different": True, "opt": True}}], True
    if text == ("choose a player. that player discards a card from their hand. "
                "then, if you control a force unit, you may deal damage to a unit equal to the cost of the discarded card"):
        return [{"op": "choose_player"}, {"op": "discard", "who": "selected_player"},
                {"op": "damage", "amount": "discarded_cost", "if_did": True,
                 "if": compile_condition("you control a force unit"), "optional": True,
                 "t": {**parse_target("a unit"), "opt": True}}], True
    if text == "choose a player. that player discards a card from their hand. if it costs 3 or less, create a spy token":
        return [{"op": "choose_player"}, {"op": "discard", "who": "selected_player"},
                {"op": "token", "name": "spy", "if_did": True, "if": {"discarded_max_cost": 3}}], True
    arena_effects = re.fullmatch(r"choose an arena\. (exhaust|deal (\d+) damage to) each unit in that arena\.?", body.strip().lower())
    if arena_effects:
        effect = {"op": "damage", "n": int(arena_effects[2])} if arena_effects[2] else {"op": "exhaust"}
        return [{"op": "choose_one", "options": [
            {"label": arena.capitalize(), "effects": [{**effect, "t": {"s": "each", "kind": "unit", "arena": arena}}]}
            for arena in ("ground", "space")
        ]}], True
    if body.strip().lower().rstrip(".") == ("if an opponent controls a space unit, give a shield token to this unit. "
                                           "otherwise, give 2 advantage tokens to this unit"):
        condition = compile_condition("an opponent controls a space unit")
        return [{"op": "shield", "if": condition, "t": {"s": "self"}},
                {"op": "advantage", "n": 2, "if": {"not": condition}, "t": {"s": "self"}}], True
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
        elif m and m.group(1).lower() == "you don't" and effects and effects[-1]["op"] == "disclose":
            sent = m.group(2)
            cond = {"disclose_declined": True}
        elif m:
            cond = compile_condition(m.group(1))
            if cond is None and (resources := re.fullmatch(r"you control (\d+) or more resources", m.group(1).lower())):
                cond = {"resource_count": int(resources[1])}
            if cond is None:
                ok = False
                continue
            sent = m.group(2)
        elif re.match(r"^then,? ", low):
            sent = re.sub(r"^then,? ", "", sent, flags=re.I)
        sp = compile_special(sent)
        if sp is not None:
            c = sp
        elif re.match(r"^(otherwise|an opponent chooses|search|for each)", sent.lower()):
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
    (r"^when you reveal or discard 1 or more cards from your hand", ["hand_revealed_or_discarded"]),
    (r"^when a player draws 1 or more cards during the action phase", ["any_action_cards_drawn"]),
    (r"^when an enemy unit leaves play", ["enemy_unit_leaves"]),
    (r"^when a friendly unit is defeated", ["friendly_unit_defeated"]),
    (r"^when a non-leader ground unit enters play", ["nonleader_ground_enters"]),
    (r"^when attached unit's attack or defense ends", ["host_combat_end"]),
    (r"^when you use the force", ["force_used"]),
    (r"^when you draw 1 or more cards during the action phase", ["action_cards_drawn"]),
    (r"^when you draw 1 or more cards", ["cards_drawn"]),
    (r"^when your base is dealt damage", ["own_base_damaged"]),
    (r"^when an opponent plays an event", ["opponent_event"]),
    (r"^when you play an upgrade on this unit", ["upgrade_played_here"]),
    (r"^when a pilot upgrade attaches to this unit", ["pilot_attached"]),
    (r"^when a friendly upgrade is defeated", ["friendly_upgrade_defeated"]),
    (r"^when played/on attack/when defeated", ["when_played", "on_attack", "when_defeated"]),
    (r"^when played/when a friendly unit is defeated", ["when_played", "friendly_unit_defeated"]),
    (r"^when played/when this unit completes an attack", ["when_played", "attack_complete"]),
    (r"^when played/when attack ends", ["when_played", "attack_end"]),
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
    (r"^when this unit completes an attack", ["attack_complete"]),
    (r"^when the regroup phase starts", ["regroup_start"]),
    (r"^when the action phase starts", ["action_start"]),
    (r"^when this unit deals combat damage to (?:a|an opponent's) base", ["base_damage"]),
    (r"^when an enemy unit deals combat damage to your base", ["enemy_combat_damage_to_base"]),
    (r"^when your base is dealt combat damage", ["enemy_combat_damage_to_base"]),
    (r"^when this unit is dealt damage and survives", ["survived_damage"]),
    (r"^when 1 or more damage is healed from this unit", ["unit_healed"]),
]


def compile_attack_action(text: str) -> list | None:
    choose_unit = {"s": "choose", "kind": "unit", "side": "friendly", "ready": True, "can_attack": True}
    if text == ("attack with a space unit. it gains saboteur and can attack ground units for this attack. "
                "if it attacks a ground unit, it gets +2/+0 and the defender gets -2/-0 for this attack"):
        modifiers = [{"kw": "saboteur", "dur": "attack"}, {"dur": "attack", "abilities": [
            {"trigger": "constant", "flag": "attack_other_arena", "arenas": ["ground"]}]}]
        return [{"op": "attack_with", "t": {**choose_unit, "arena": "space", "attack_modifiers": modifiers}, "swoop_bonus": True}]
    if text == "attack with a unit. it gets +1/+0 for this attack for each damage on the defender at the start of this attack":
        return [{"op": "attack_with", "t": choose_unit, "defender_damage_bonus": True}]
    if text == ("attack with a unit. it gets +1/+0 and gains overwhelm for this attack. "
                "if it attacks a unit, the defender loses all abilities for this attack"):
        return [{"op": "attack_with", "t": choose_unit, "blank_defender": True,
                "pre": [{"op": "buff", "p": 1}, {"op": "gain_kw", "kw": "overwhelm"}]}]
    if text == ('attack with a unit. for this attack, it gains: "on attack: '
                'return any number of non-unique upgrades attached to the defender to their owners\' hands."'):
        effect = {"op": "bounce", "t": {"s": "choose", "kind": "upgrade", "unique": False, "attached_to_defender": True, "opt": True, "count": 99}}
        modifier = {"dur": "attack", "abilities": [{"trigger": "on_attack", "effects": [effect]}]}
        return [{"op": "attack_with", "t": {**choose_unit, "attack_modifiers": [modifier]}}]
    attack = re.fullmatch(r"(you may )?attack with (.+?)(, even if it's exhausted)?\. (.+)", text)
    if not attack:
        return None
    optional, subject, exhausted, follow_up = attack.groups()
    selector = {"s": "self"} if subject == "this unit" else parse_target(subject)
    if not selector or selector.get("kind", "unit") != "unit":
        return None
    selector = {**selector, "side": "friendly", "can_attack": True, "allow_exhausted": bool(exhausted)}
    if optional and selector["s"] == "choose":
        selector["opt"] = True
    effect = {"op": "attack_with", "t": selector, "optional": bool(optional)}
    boost = re.fullmatch(r"(?:for this attack, )?it gets ([+-]\d+)/([+-]\d+)(?: and gains (overwhelm|saboteur|restore \d+))?(?: for this attack)?", follow_up)
    restricted = re.fullmatch(r"it (?:gets ([+-]\d+)/([+-]\d+) and )?can't attack bases for this attack", follow_up)
    if restricted:
        selector["units_only"] = True
        if restricted[1]:
            effect["pre"] = [{"op": "buff", "p": int(restricted[1]), "h": int(restricted[2])}]
        return [effect]
    if boost:
        effect["pre"] = [{"op": "buff", "p": int(boost[1]), "h": int(boost[2])}]
        if boost[3]:
            keyword, *value = boost[3].split()
            effect["pre"].append({"op": "gain_kw", "kw": keyword, "v": int(value[0]) if value else 1})
        return [effect]
    comparisons = {
        "if you control more units than the defending player": {"compare_units": "more"},
        "if you played an event this phase": {"played_kind": "event"},
        "if it's a bounty hunter": {"selected_trait": "bounty hunter"},
        "if it's attacking a unit": {"attack_defender_is_unit": True},
    }
    if conditional := re.fullmatch(r"(.+), (?:the attacker|it) gets ([+-]\d+)/([+-]\d+) for this attack", follow_up):
        if conditional[1] in comparisons:
            effect["pre"] = [{"op": "buff", "p": int(conditional[2]), "h": int(conditional[3]), "if": comparisons[conditional[1]]}]
            return [effect]
    if follow_up == "it gains saboteur for this attack. if it's a trooper, it also gains +2/+0 for this attack":
        effect["pre"] = [{"op": "gain_kw", "kw": "saboteur"}, {"op": "buff", "p": 2, "if": {"selected_trait": "trooper"}}]
        return [effect]
    if follow_up == "for this attack, it deals damage equal to its remaining hp instead of its power":
        effect["attack_with_hp"] = True
        return [effect]
    return None


def compile_attack_end_body(body: str, triggers: list[str]):
    condition = {}
    match = re.match(r"if (the defend(?:ing unit|er) was defeated|this unit survived|"
                     r"this unit deal[st] combat damage to (?:a base|an opponent's base|1 or more non-leader units)), (.+)",
                     body, re.I)
    if match and any(t in {"attack_end", "attack_complete", "friendly_attack_end"} for t in triggers):
        cause, body = match.groups()
        cause = cause.lower()
        if cause.startswith("the defend"):
            condition = {"combat_result": "defender_defeated"}
        elif cause == "this unit survived":
            condition = {"combat_result": "attacker_survived"}
        elif cause.endswith("non-leader units"):
            condition = {"combat_result": "nonleader_combat_uid"}
        else:
            condition = {"combat_result": "base_combat_damage"}
    low = body.lower().rstrip(".")
    if low in ("ready him", "ready her") and triggers == ["attack_end"]:
        effects = [{"op": "ready", "t": {"s": "self"}}]
    elif low == "give an experience token to this unit and heal 3 damage from him":
        effects = [{"op": "experience", "t": {"s": "self"}}, {"op": "heal", "n": 3, "t": {"s": "self"}}]
    elif low == "heal that much damage from your base" and condition.get("combat_result") == "base_combat_damage":
        effects = [{"op": "heal", "use_trigger_amount": True, "t": {"s": "own_base"}}]
    elif low == "defeat those units" and condition.get("combat_result") == "nonleader_combat_uid":
        effects = [{"op": "defeat", "t": {"s": "combat_damaged_unit"}}]
    elif low == "deal 2 damage to each unit that opponent controls in this unit's arena" and condition.get("combat_result") == "base_combat_damage":
        effects = [{"op": "damage", "n": 2, "t": {"s": "each", "kind": "unit", "side": "enemy", "attack_arena": True}}]
    elif low == "give a number of experience tokens to this unit equal to the defeated unit's cost":
        effects = [{"op": "experience", "count_from": "defender_cost", "t": {"s": "self"}}]
    elif low == "put the defeated unit into play as a resource under your control":
        effects = [{"op": "resource_defender"}]
    elif low == "you may choose an enemy non-leader unit. this unit captures it":
        effects = [{"op": "capture", "source_captures": True}]
    elif low == "you may defeat a unit with less power than this unit":
        effects = [{"op": "defeat", "t": {"s": "choose", "kind": "unit", "less_power_than_source": True, "opt": True}}]
    elif low == "you may defeat a unit with less remaining hp than this unit's power":
        effects = [{"op": "defeat", "t": {"s": "choose", "kind": "unit", "hp_less_than_source_power": True, "opt": True}}]
    elif low == "you may exhaust this leader. if you do, give an experience token to that friendly unit":
        effects = [{"op": "exhaust", "optional": True, "t": {"s": "self"}},
                   {"op": "experience", "if_did": True, "t": {"s": "subject"}}]
    elif low == "you may give an experience token to that friendly unit":
        effects = [{"op": "experience", "optional": True, "t": {"s": "subject"}}]
    elif low == "defeat an experience token on it":
        effects = [{"op": "defeat", "t": {"s": "choose", "kind": "upgrade", "token_name": "experience", "attached_to_source": True}}]
    else:
        effects, ok, limit = compile_limited_body(body)
        if condition and ok:
            for e in effects:
                e.setdefault("if", {}).update(condition)
        return effects, ok, limit
    if condition:
        for e in effects:
            e["if"] = condition
    return effects, True, {}


def compile_shared_trigger_body(body: str, triggers: list[str]):
    low = body.lower().rstrip(".")
    if low == "an opponent chooses a non-leader unit they control. defeat that unit":
        return [{"op": "opponent_defeat", "nonleader": True}], True, {}
    if low == "you may use the force. if you don't, deal 9 damage to your base":
        return [{"op": "use_force", "optional": True},
                {"op": "damage", "n": 9, "t": {"s": "own_base"}, "if_not_did": True}], True, {}
    if low == "give another friendly unit +1/+0 and saboteur for this phase":
        return [{"op": "buff", "p": 1, "t": parse_target("another friendly unit")},
                {"op": "gain_kw", "kw": "saboteur", "if_did": True, "t": {"s": "it"}}], True, {}
    if low == "give this unit and an enemy unit sentinel for this phase":
        return [{"op": "gain_kw", "kw": "sentinel", "t": {"s": "self"}},
                {"op": "gain_kw", "kw": "sentinel", "t": parse_target("an enemy unit")}], True, {}
    if low == "you may give an experience token to another friendly unit. it gains sentinel for this phase":
        target = parse_target("another friendly unit")
        target["opt"] = True
        return [{"op": "experience", "t": target},
                {"op": "gain_kw", "kw": "sentinel", "if_did": True, "t": {"s": "it"}}], True, {}
    counted = compile_counted_trigger(body)
    if counted:
        return counted, True, {}
    if any(t in {"attack_end", "attack_complete", "friendly_attack_end"} for t in triggers):
        return compile_attack_end_body(body, triggers)
    return compile_limited_body(body)


def compile_counted_trigger(body: str):
    text = body.lower().rstrip(".")
    if text == "draw a card. you may deal damage to a ground unit equal to the number of cards you've drawn this phase":
        return [{"op": "draw"}, {"op": "damage", "count_from": "cards_drawn", "t": {**parse_target("a ground unit"), "opt": True}}]
    if damage := re.fullmatch(r"deal damage equal to this unit's power to (.+)", text):
        if t := parse_target(damage[1]):
            return [{"op": "damage", "count_from": "source_power", "t": t}]
    if text == "if this unit had 7 or more power, return him to his owner's hand":
        return [{"op": "recover_self", "minimum_power": 7}]
    if text == "you may give a weakness token to this unit. if you do, create a beast token for each weakness token on this unit":
        return [{"op": "weakness", "optional": True, "t": {"s": "self"}},
                {"op": "token", "name": "beast", "count_from": "source_weakness", "if_did": True}]
    if text == "for each other friendly wookiee unit, resource the top card of your deck. ready each card resourced this way":
        return [{"op": "resource_top", "ready": True, "count_targets": parse_target("another friendly wookiee unit")}]
    if text == "this unit gets +1/+0 for this attack for each damaged unit the defending player controls":
        return [{"op": "buff", "p": 1, "dur": "attack", "count_targets": parse_target("an enemy damaged unit"), "t": {"s": "self"}}]

    counts = {
        "(the number of )?resources you control": "resources",
        "(the number of )?cards in your hand": "hand",
        "the number of units you control in its arena": "friendly_target_arena",
        "the (?:amount of )?damage on this unit": "source_damage",
        "this unit's power": "source_power",
        "different aspect among units you control": "friendly_unit_aspects",
        "other card you played this phase": "other_cards_played",
        "different cost among cards in your discard pile": "discard_costs",
        "enemy unit that was defeated this phase": "enemy_defeated",
        "friendly unit that was defeated this phase": "friendly_defeated",
        "the number of experience tokens on friendly units": "friendly_experience",
    }
    for pattern, source in counts.items():
        count_phrase = rf"(?:{pattern})"
        match = re.fullmatch(rf"(?:(.+?) (?:equal to|for each) {count_phrase}|for each {count_phrase}, (.+))", text)
        if match:
            # The count regex may contain capture groups, so use the first and last groups.
            effects = compile_sentence(match[1] or match.groups()[-1])
            if effects and len(effects) == 1:
                return [{**effects[0], "count_from": source}]

    scaled_damage = re.fullmatch(r"you may deal damage(?: to (.+?))? equal to (.+?)(?: minus (\d+))?(?: to (.+))?", text)
    scaled_heal = re.fullmatch(r"you may heal damage from (.+) equal to (.+)", text)
    if scaled_damage or scaled_heal:
        if scaled_damage:
            target_phrase = scaled_damage[1] or scaled_damage[4]
            source_phrase = scaled_damage[2]
        else:
            target_phrase, source_phrase = scaled_heal.groups()
        target = parse_target(target_phrase) if target_phrase else None
        source = next((key for pattern, key in counts.items() if re.fullmatch(pattern, source_phrase)), None)
        unit_count = source_phrase.removeprefix("twice ").removeprefix("the number of ").removesuffix(" you control")
        if source_phrase.endswith(" you control") and (unit_count == "units" or unit_count.endswith(" units")):
            unit_count = "friendly " + unit_count
        selector = parse_target("a " + unit_count.replace(" units", " unit", 1)) if unit_count.endswith(" units") else None
        if target and (source or selector):
            target["opt"] = True
            effect = {"op": "damage" if scaled_damage else "heal", "t": target}
            if source:
                effect["count_from"] = source
            else:
                effect["count_targets"] = selector
                if source_phrase == "twice the number of units you control":
                    effect["n"] = 2
            if scaled_damage and scaled_damage[3]:
                effect["count_offset"] = -int(scaled_damage[3])
            return [effect]

    # "Choose ..., deal/heal ... for each ..." resolves through the same target picker.
    match = re.fullmatch(r"choose (.+?)\. (deal|heal) (\d+) damage (?:to|from) it for each (.+)", text)
    if match:
        text = f"{match[2]} {match[3]} damage {'to' if match[2] == 'deal' else 'from'} {match[1]} for each {match[4]}"
    match = re.fullmatch(r"(?:(.+) for each (.+)|for each (.+?), (.+))", text)
    if not match:
        return None
    phrase, filter_phrase = (match[1], match[2]) if match[1] else (match[4], match[3])
    if filter_phrase.endswith("unit you control"):
        selector = parse_target("a friendly " + filter_phrase.removesuffix(" you control"))
    elif filter_phrase.startswith(("friendly ", "enemy ", "other friendly ")):
        selector = parse_target("a " + filter_phrase)
    else:
        return None
    if phrase == "ready a friendly resource":
        effects = [{"op": "ready_resource"}]
    else:
        effects = compile_sentence(phrase)
    if selector and selector["kind"] == "unit" and effects and len(effects) == 1:
        return [{**effects[0], "count_targets": selector}]
    return None


def parse_action_cost(inner: str) -> dict:
    cost = {"exhaust": False, "resources": 0}
    for part in [p.strip().lower() for p in inner.split(",")]:
        if part == "exhaust":
            cost["exhaust"] = True
        elif part.startswith("c="):
            cost["resources"] = to_int(part[2:], 0)
        elif part.isdecimal():
            cost["resources"] = int(part)
        elif part:
            cost["other"] = part
    return cost


def compile_limited_body(body: str, action: bool = False):
    match = re.fullmatch(r"(.+?)\.\s*Use this ability (?:only once|no more than (\d+) times) each (round|phase|game)\.?", body, re.I)
    if not match:
        effects, complete = compile_body(body)
        return effects, complete, {}
    effects, complete = compile_body(match[1])
    if not complete or not effects:
        return [], False, {}
    limit = {"limit": int(match[2] or 1), "limit_period": match[3].lower()}
    if not action and match[1].lower().startswith("you may "):
        first = effects[0]
        if not (first.get("optional") or first.get("t", {}).get("opt")):
            return [], False, {}
        limit["optional_limit"] = True
    return effects, True, limit


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


def attachment_requirement(phrase: str) -> dict | None:
    phrase = phrase.lower().strip()
    if " or " in phrase:
        alternatives = [attachment_requirement(part) for part in phrase.split(" or ")]
        return {"any": alternatives} if all(alternatives) else None
    if phrase == "a non-heroism, non-villainy unit":
        return {"exclude_aspects": ["heroism", "villainy"]}
    match = re.fullmatch(r"an? ([a-z][a-z' -]*?)(?: unit)?", phrase)
    if match:
        if match[1] in {"heroism", "villainy", "vigilance", "command", "aggression", "cunning"}:
            return {"aspect": match[1]}
        return {"trait": match[1]}
    if re.fullmatch(r"(?:the )?[a-z][a-z'-]+(?: [a-z][a-z'-]+)*", phrase):
        return {"name": phrase}
    return None


def compile_granted_ability(text: str) -> list | None:
    low = text.rstrip(".").lower()
    modifier = re.fullmatch(r"on attack: (?:give the defender|the defender gets) (-\d+)/(-?\d+) for this (phase|attack)", low)
    if modifier:
        return [dict(trigger="on_attack", effects=[dict(op="buff", p=int(modifier[1]), h=int(modifier[2]),
                                                        dur=modifier[3], t={"s": "defender"})], text=text)]
    if low == "on attack: deal 1 damage to each ground unit the defending player controls":
        return [dict(trigger="on_attack", effects=[dict(op="damage", n=1, t=parse_target("each enemy ground unit"))], text=text)]
    if low == "on attack: if this unit isn't attacking a base, you may deal 2 damage to a unit in the defender's arena":
        target = dict(s="choose", kind="unit", same_arena=True, opt=True)
        return [dict(trigger="on_attack", effects=[dict(op="damage", n=2, t=target, unit_defender=True)], text=text)]
    if low == "while attacking a force unit, this unit gets +2/+0":
        return [dict(trigger="constant", flag="attack_force_bonus", p=2, text=text)]
    rules, _, status = compile_text(text, [])
    return rules if rules and status == "full" else None


def compile_attachment_line(line: str) -> list | None:
    text = line.rstrip(".").strip()
    low = text.lower()
    prevents = {
        "attached unit can't attack bases": "no_base_attack",
        "attached unit can't ready": "cannot_ready",
        "this unit can't be exhausted by enemy card abilities": "enemy_exhaust_immune",
        "this unit can't be captured, defeated, or returned to its owner's hand by enemy card abilities": "enemy_removal_immune",
    }
    if low in prevents:
        return [dict(trigger="constant", flag=prevents[low], text=line, granted=low.startswith("attached unit"))]
    if low == "attached unit gets -3/-0 while attacking a base":
        return [dict(trigger="constant", flag="attack_base_bonus", p=-3, text=line, granted=True)]
    if low == "attached unit's printed power is considered to be 5 and its printed hp is considered to be 5":
        return [dict(trigger="printed_stats", power=5, hp=5, text=line)]
    if low == "while attached unit is defending, the attacker gets -1/-0":
        return [dict(trigger="constant", flag="enemy_attack_power", p=-1, text=line, granted=True)]
    if low == "when attached unit's attack ends: deal 4 damage to it and defeat this upgrade":
        return [dict(trigger="host_attack_end", effects=[dict(op="damage", n=4, t={"s": "attached_unit"}),
                                                         dict(op="defeat", t={"s": "self"})], text=line)]
    if low.startswith("when played: "):
        body = low.removeprefix("when played: ")
        direct = {
            "deal damage to an enemy unit equal to attached unit's power": [
                dict(op="damage", amount="attached_power", t=parse_target("an enemy unit"))],
            "you may have attached unit deal 1 damage to a ground unit": [
                dict(op="damage", attached_is_source=True, n=1, t=dict(s="choose", kind="unit", arena="ground", opt=True))],
            "you may exhaust a unit in attached unit's arena": [
                dict(op="exhaust", t=dict(s="choose", kind="unit", same_arena=True, opt=True))],
            "attached unit can't be attacked this phase": [dict(op="cannot_be_attacked", t={"s": "attached"})],
            "you may deal 1 damage to a ground unit. then, deal 1 damage to the same unit. then, deal 1 damage to the same unit": [
                dict(op="damage", n=1, t=dict(s="choose", kind="unit", arena="ground", opt=True)),
                dict(op="damage", n=1, if_did=True, t={"s": "it"}),
                dict(op="damage", n=1, if_did=True, t={"s": "it"})],
        }.get(body)
        if direct:
            return [dict(trigger="when_played", effects=direct, text=line)]
    if low.startswith("attached unit can't ready. it gains:"):
        inner = text.split(":", 1)[1].strip().strip('"')
        rules, _, status = compile_text(inner, [])
        if rules and status == "full":
            return [dict(trigger="constant", flag="cannot_ready", granted=True, text=line)] + [
                dict(rule, granted=True) for rule in rules]
        return None
    match = re.fullmatch(r"When Played: If attached unit is (.+?), (.+)", text, re.I)
    if match and (requirement := attachment_requirement(match[1])):
        if match[2].lower() == "heal all damage from him and give a shield token to him":
            effects, complete = [dict(op="heal", all_damage=True, t={"s": "attached"}),
                                 dict(op="shield", t={"s": "attached"})], True
        else:
            body = re.sub(r"\b(to|from) (?:it|him|her)$", r"\1 attached unit", match[2], flags=re.I)
            effects, complete = compile_body(body)
        if effects and complete:
            return [dict(trigger="when_played", host_requires=requirement, effects=effects, text=line)]
        return None
    requirement = None
    match = re.fullmatch(r"If attached unit is (.+?), (?:it|he|she) gains[:,]?\s+(.+)", text, re.I)
    if match:
        requirement = attachment_requirement(match[1])
        if requirement is None:
            return None
        payload = match[2]
    else:
        match = re.fullmatch(r"While attached unit is exhausted, it gains[:,]?\s+(.+)", text, re.I)
        if match:
            requirement, payload = {"exhausted": True}, match[1]
        else:
            match = re.fullmatch(r"While attached unit has (\d+) or more upgrades on it, it gains[:,]?\s+(.+)", text, re.I)
            if match:
                requirement, payload = {"upgrades_min": int(match[1])}, match[2]
            else:
                match = re.fullmatch(r"Attached (?:unit|base) gains[:,]?\s+(.+)", text, re.I)
                if not match:
                    loss = re.fullmatch(r"Attached unit loses the (.+?) trait and gains (.+)", text, re.I)
                    if not loss:
                        return None
                    rules = compile_attachment_line("Attached unit gains " + loss[2])
                    return [dict(trigger="attached_traits", remove_trait=loss[1].lower(), text=line)] + rules if rules else None
                payload = match[1]
    quoted = re.findall(r'"([^"]+)"', payload)
    outer = re.sub(r'"[^"]+"', '', payload).strip()
    outer = re.sub(r"(?:\s+and)?[:,]?$|^and\b", "", outer).strip()
    rules = []
    if outer:
        traits = re.fullmatch(r"the ([a-z' -]+) trait", outer, re.I)
        if traits:
            rules.append(dict(trigger="attached_traits", add_trait=traits[1].lower(), text=line))
        else:
            keywords = re.split(r",\s*(?:and\s+)?|\s+and\s+", outer.lower())
            for part in keywords:
                keyword = re.fullmatch(r"(sentinel|saboteur|overwhelm|grit|ambush|hidden|raid|restore)(?: (\d+))?", part)
                if not keyword:
                    return None
                rules.append(dict(trigger="attached_kw", kw=keyword[1], v=int(keyword[2] or 1), text=line))
    for inner in quoted:
        sub = compile_granted_ability(inner)
        if not sub:
            return None
        rules.extend(dict(rule, granted=True) for rule in sub)
    if requirement:
        for rule in rules:
            rule["host_requires"] = requirement
    return rules or None


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
        if low.rstrip(".") == "you may play that upgrade" and abilities and abilities[-1]["trigger"] == "event":
            preceding = abilities[-1]["effects"]
            if len(preceding) == 1 and preceding[0].get("op") == "search" and preceding[0].get("filter", {}).get("kind") == "upgrade":
                preceding.append({"op": "play_from_hand", "kind": "upgrade", "optional": True, "only_selected": True})
                abilities[-1]["text"] += "\n" + line
                parsed += 1
                continue
        if combat_defeat := re.fullmatch(r"when this unit deals combat damage to a (non-leader unit|unit) while attacking: defeat that unit\.?", low):
            selector = "combat_damaged_unit" if combat_defeat[1] == "non-leader unit" else "any_combat_damaged_unit"
            abilities.append({"trigger": "attack_end", "effects": [{"op": "defeat", "t": {"s": selector}}], "text": line})
            parsed += 1
            continue
        constant = compile_continuous(line)
        if constant is not None:
            abilities.append(constant)
            parsed += 1
            continue
        if low.startswith("while ") and len(parts := SPLIT_SENT.split(line)) > 1:
            ongoing = [compile_continuous(part) for part in parts]
            if all(ongoing):
                abilities.extend(ongoing)
                parsed += 1
                continue
        coordinate = re.fullmatch(r"coordinate\s*-\s*(.+)", line, re.I)
        if coordinate:
            inner = coordinate.group(1)
            sub, _, status = compile_text(inner, [])
            if sub and status == "full" and all(a["trigger"] in {
                "action", "on_attack", "when_played", "when_defeated", "attack_end", "attack_complete",
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
        attachments = compile_attachment_line(line)
        if attachments:
            abilities.extend(attachments)
            parsed += 1
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
                eff, ok, limit = compile_shared_trigger_body(body, ["friendly_card_played"])
                if ok and eff:
                    abilities.append({"trigger": "friendly_card_played", "filter": play_filter,
                                      "effects": eff, "text": line, **limit})
                    parsed += 1
                    continue
        attack_defeat = re.fullmatch(r"when (this|a friendly) unit attacks and defeats a (unit|non-leader unit)\s*:\s*(.+)", line, re.I)
        friendly_attack_end = re.fullmatch(r"when a friendly(?: (.+?))? unit's attack ends\s*:\s*(.+)", line, re.I)
        if attack_defeat or friendly_attack_end:
            trigger = "attack_end" if attack_defeat and attack_defeat[1].lower() == "this" else "friendly_attack_end"
            body = attack_defeat[3] if attack_defeat else friendly_attack_end[2]
            eff, ok, limit = compile_shared_trigger_body(body, [trigger])
            if eff and ok:
                rule = {"trigger": trigger, "effects": eff, "text": line, **limit}
                if attack_defeat:
                    rule["combat_result"] = "nonleader_defender_defeated" if attack_defeat[2] == "non-leader unit" else "defender_defeated"
                if friendly_attack_end and friendly_attack_end[1]:
                    rule["attacker_trait"] = friendly_attack_end[1].lower()
                abilities.append(rule)
                parsed += 1
            else:
                unparsed.append(line)
            continue
        matched = False
        for pat, trig in TRIGGERS:
            mm = re.match(pat + r"\s*:\s*(.+)$", line, re.I)
            if mm:
                matched = True
                body = mm.group(1)
                if trig == ["nonleader_ground_enters"]:
                    body = re.sub(r"\bthat unit\b", "the played unit", body, flags=re.I)
                eff, ok, limit = compile_shared_trigger_body(body, trig)
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
    if copies := re.fullmatch(r"a deck can have up to (\d+) copies of this card", text):
        return {"trigger": "deck_copy_limit", "count": int(copies[1]), "text": line}
    if text == "if damage would be dealt to attached unit, prevent that damage. if you do, defeat a shield token on it":
        return {"trigger": "constant", "flag": "shield_token", "text": line}
    if text == "each event an opponent plays costs 1 more":
        return {"trigger": "opponent_cost_increase", "filter": {"kind": "event"}, "n": 1, "text": line}
    if text == "the first event played by each opponent each round loses all abilities":
        return {"trigger": "constant", "flag": "blank_first_opponent_event", "text": line}
    if text == "this unit can't be defeated by enemy card abilities":
        return {"trigger": "constant", "flag": "enemy_defeat_immune", "text": line}
    if text == "this unit can't be captured, damaged, or defeated by enemy card abilities":
        return {"trigger": "constant", "flags": ["enemy_defeat_immune", "enemy_damage_immune", "enemy_capture_immune"], "text": line}
    if text == "this unit costs 1 less to play for each friendly pilot unit and upgrade":
        return {"trigger": "own_discount", "n": 1, "target_groups": [
            {"kind": kind, "side": "friendly", "trait": "pilot"} for kind in ("unit", "upgrade")], "text": line}
    if text == "each friendly unit that was healed this phase gets +1/+0":
        return {"trigger": "continuous", "target": "friendly", "selector": {"healed_this_phase": True}, "p": 1, "text": line}
    if text == "bases can't be healed":
        return {"trigger": "constant", "flag": "prevent_base_heal", "text": line}
    if text == "play only as your first action in the action phase":
        return {"trigger": "constant", "flag": "first_action_only", "text": line}
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
    if text == "while attacking, you may have the defending unit deal combat damage before this unit":
        return {"trigger": "constant", "flag": "may_defender_strike_first", "text": line}
    if text == "while attacking, if no other units have attacked this phase, this unit deals combat damage before the defending unit":
        return {"trigger": "constant", "flag": "first_strike", "no_other_attacks": True, "text": line}
    if text == "while attacking an exhausted unit that didn't enter play this phase, this unit deals combat damage before the defender":
        return {"trigger": "constant", "flag": "first_strike", "exhausted_older_defender": True, "text": line}
    if cross_arena := re.fullmatch(r"this unit (?:can|may) attack (ground|space) units|this unit (?:can|may) attack units in (?:the (ground|space)|either) arena", text):
        arena = cross_arena[1] or cross_arena[2]
        return {"trigger": "constant", "flag": "attack_other_arena", "arenas": [arena] if arena else ["ground", "space"], "text": line}
    if text == "if attached unit is luke skywalker, he gains sentinel":
        return {"trigger": "attached_kw", "host_name": "luke skywalker", "kw": "sentinel", "text": line}
    if combat := compile_combat_bonus(text):
        return {**combat, "text": line}
    condition = {}
    conditional = re.fullmatch(r"(?:while|if) (.+?),\s*(.+)", text) or \
        re.fullmatch(r"while (this unit is undamaged) (it gains .+)", text)
    if conditional:
        clause, text = conditional.groups()
        condition = compile_condition(clause)
        if condition is None:
            states = {"this unit is damaged": {"damaged": True}, "this unit is undamaged": {"undamaged": True},
                      "this unit is ready": {"ready": True}, "this unit is exhausted": {"exhausted": True}}
            condition = states.get(clause)
        if condition is None:
            resources = re.fullmatch(r"you control (\d+) or more resources", clause)
            if resources is None:
                return None
            condition = {"resources_min": int(resources[1])}
    elif match := re.fullmatch(r"coordinate\s*-\s*(.+)", text):
        condition, text = {"units_min": 3}, match[1]
        if combat := compile_combat_bonus(text):
            return {**combat, "condition": condition, "text": line}
    if text == "this unit can't attack" and not condition:
        return {"trigger": "constant", "flag": "cannot_attack", "text": line}
    if text == "this unit can't attack unless it's damaged":
        return {"trigger": "constant", "flag": "cannot_attack", "condition": {"undamaged": True}, "text": line}
    if text == "this unit can't attack bases" and not condition:
        return {"trigger": "constant", "flag": "no_base_attack", "text": line}
    result = {"trigger": "continuous", "target": "self", "condition": condition, "text": line}
    target = re.fullmatch(r"(?:each )?((?:other )?(?:friendly|enemy) .*?units?(?: (?:that costs \d+ or more|named .+?|with sentinel))?) (gets? .+|gains? .+|enters? play ready)", text)
    if target:
        qualifier, text = target.groups()
        name = re.fullmatch(r"(friendly units?) named (zuckuss|4-lom)", qualifier)
        description = (name[1] if name else qualifier).replace("units", "unit")
        # The selector handles multiple qualifiers (e.g. another friendly ground unit with Sentinel).
        t = parse_target(("another " if description.startswith("other ") else "a ") + description.removeprefix("other "))
        if t is None:
            return None
        if name:
            t["name"] = name[2]
        result.update(target=t["side"], selector=t)
    elif text.startswith("each leader unit you control "):
        result.update(target="friendly", trait="leader")
        text = text.removeprefix("each leader unit you control ")
    else:
        text = re.sub(r"^(this unit|he|she|it) ", "", text)
    if text in ("enters play ready", "enter play ready"):
        if result["target"] == "self" and not condition:
            return {"trigger": "constant", "flag": "enters_ready", "text": line}
        if (selector := result.get("selector", {})).get("side") != "enemy":
            result["enter_ready"] = 1
            return result
    if text == "can't be attacked" and condition:
        result["cannot_be_attacked"] = 1
        return result
    if text == "each token unit you create enters play ready":
        result.update(target="friendly", selector={"kind": "unit", "side": "friendly", "token": True}, enter_ready=1)
        return result
    # Record what the rule counts separately from what receives the bonus.
    scale = re.fullmatch(r"(.+) for each (.+)", text)
    if scale:
        text, description = scale.groups()
        if description in ("damage on it", "damage on him", "damage on her"):
            result["scale_by"] = "target_damage"
        elif description in ("resource you control", "card in your hand", "upgrade on him", "upgrade on it",
                             "exhausted resource you control", "captured card it's guarding", "upgrade on other friendly units"):
            result["scale_by"] = {"resource you control": "resources", "card in your hand": "hand",
                                  "exhausted resource you control": "exhausted_resources", "captured card it's guarding": "captives",
                                  "upgrade on other friendly units": "upgrades_on_other_units"}.get(description, "target_upgrades")
        elif discard := re.fullmatch(r"(trooper unit|law card) in your discard pile", description):
            result["scale_by"] = "discard"
            word, kind = discard[1].split()
            result["scale_filter"] = {"trait": word, "kind": kind}
        elif description == "other friendly swarming vulture droid":
            result["scale_target"] = {"side": "friendly", "other": True, "name": "swarming vulture droid"}
        elif re.fullmatch(r"(?:other )?(?:(?:exhausted|damaged) )?(?:(?:friendly|enemy) )?(?:[\w -]+ )?unit", description):
            selector = parse_target("a " + description)
            if selector is None:
                return None
            result["scale_target"] = selector
        else:
            return None
    elif divisor := re.fullmatch(r"(.+) for every (\d+) resources you control", text):
        text = divisor[1]
        result.update(scale_by="resources", scale_divisor=int(divisor[2]))
    elif divisor := re.fullmatch(r"(.+) for every (\d+) damage on your base", text):
        text = divisor[1]
        result.update(scale_by="base_damage", scale_divisor=int(divisor[2]))
    mixed = re.fullmatch(r"gets? ([+-]\d+)/([+-]\d+)(?: and (gains? .+))?", text)
    if mixed:
        result.update(p=int(mixed[1]), h=int(mixed[2]))
        if mixed[3] is None:
            return result
        text = mixed[3]
    keywords_pattern = r"ambush|sentinel|grit|saboteur|overwhelm|hidden|shielded|raid|restore"
    if condition.get("units_min") and re.fullmatch(rf"(?:{keywords_pattern})(?: \d+)?", text):
        text = "gains " + text
    if text.startswith(("gain ", "gains ")):
        keywords = re.split(r",\s*(?:and\s+)?|\s+and\s+", text.split(" ", 1)[1])
        entries = [re.fullmatch(rf"({keywords_pattern})(?: (\d+))?", part)
                   for part in keywords]
        if all(entries):
            if len(entries) == 1:
                result.update(kw=entries[0][1], v=int(entries[0][2] or 1))
            else:
                result["keywords"] = {entry[1]: int(entry[2] or 1) for entry in entries}
            return result
    return None


def compile_combat_bonus(text: str) -> dict | None:
    """Continuous modifiers to combatants, active only for the current attack."""
    rules = [
        (r"while this unit is defending, (?:it|he|she) gets? (.+)", "defender", "defender", {}),
        (r"this unit gets? (.+) while defending", "defender", "defender", {}),
        (r"while this unit is defending, the attacker gets? (.+)", "defender", "attacker", {}),
        (r"while this unit is attacking, the defending unit gets? (.+)", "attacker", "defender", {"kind": "unit"}),
        (r"while this unit is attacking, the defender gets? (.+)", "attacker", "defender", {"kind": "unit"}),
        (r"while this unit is attacking a ground unit, the defender gets? (.+)", "attacker", "defender", {"arena": "ground"}),
        (r"while attacking a space unit, this unit gets? (.+)", "attacker", "attacker", {"arena": "space"}),
        (r"this unit gets? (.+) while attacking a damaged unit", "attacker", "attacker", {"damaged": True}),
        (r"while attacking a damaged unit, this unit gets? (.+)", "attacker", "attacker", {"damaged": True}),
        (r"while attacking a unit with a bounty, this unit gets? (.+)", "attacker", "attacker", {"keyword": "bounty"}),
    ]
    for pattern, source, target, selector in rules:
        if match := re.fullmatch(pattern, text):
            stats = re.fullmatch(r"([+-]\d+)/([+-]\d+)(?: and gains (overwhelm))?", match[1])
            if stats is None:
                continue
            result = dict(trigger="continuous", target=target, combat_source=source, defender=selector,
                          p=int(stats[1]), h=int(stats[2]))
            if stats[3]:
                result["kw"] = stats[3]
            return result
    if text == "while a friendly unit is attacking a damaged unit, the attacker gains overwhelm":
        return dict(trigger="continuous", target="attacker", combat_source="friendly_attacker",
                    defender={"damaged": True}, kw="overwhelm")
    if m := re.fullmatch(r"while (a|another) friendly unit is attacking, the defend(?:er|ing unit) gets? ([+-]\d+)/([+-]\d+)", text):
        return dict(trigger="continuous", target="defender", combat_source="friendly_attacker", other_combatant=m[1] == "another",
                    p=int(m[2]), h=int(m[3]))
    if m := re.fullmatch(r"while (a|another) friendly unit is defending, it gets? ([+-]\d+)/([+-]\d+)", text):
        return dict(trigger="continuous", target="defender", combat_source="friendly_defender", other_combatant=m[1] == "another",
                    p=int(m[2]), h=int(m[3]))
    if m := re.fullmatch(r"while a friendly unit is attacking using ambush, the defender gets ([+-]\d+)/([+-]\d+)", text):
        return dict(trigger="continuous", target="defender", combat_source="friendly_attacker", ambush=True, p=int(m[1]), h=int(m[2]))
    if m := re.fullmatch(r"while attacking using ambush, this unit gets ([+-]\d+)/([+-]\d+)", text):
        return dict(trigger="continuous", target="attacker", combat_source="attacker", ambush=True, p=int(m[1]), h=int(m[2]))
    if text == "each exhausted enemy unit gets -2/-0 while defending":
        return dict(trigger="continuous", target="defender", combat_source="any",
                    selector={"side": "enemy", "exhausted": True}, p=-2)
    if text == "enemy ground units get -1/-0 while attacking":
        return dict(trigger="continuous", target="attacker", combat_source="any", selector={"side": "enemy", "arena": "ground"}, p=-1)
    if text == "each friendly unit that costs 3 or less gets +1/+0 and gains overwhelm while attacking an enemy unit":
        return dict(trigger="continuous", target="attacker", combat_source="friendly_attacker", selector={"max_cost": 3},
                    defender={"kind": "unit"}, p=1, kw="overwhelm")
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
    ignore = re.fullmatch(r"(?:while (.+?), )?ignore the aspect penalt(?:y|ies) on (.+) you play", text)
    if ignore:
        condition = compile_condition(ignore[1]) if ignore[1] else {}
        selector = compile_play_filter(ignore[2].removesuffix("s"))
        if condition is not None and selector is not None:
            return {"trigger": "ignore_play_aspects", "condition": condition, "filter": selector}
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
        parts = re.split(r",\s*(?:and\s+)?|\s+and\s+", printed)
        matches = [re.fullmatch(r"([a-z]+)(?:\s+\d+)?(?:\s*\[[^\]]+\])?", part.strip()) for part in parts]
        if all(match and match[1] in NATIVE_KEYWORDS for match in matches):
            listed.extend(match[1] for match in matches)
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


PILOT_LEADER_STATS = {
    "001": (3, 4), "003": (5, 5), "006": (5, 5), "008": (3, 4), "009": (4, 4),
    "011": (3, 3), "012": (4, 5), "013": (2, 1), "015": (3, 5), "017": (3, 4), "018": (2, 3),
}


def compile_pilot_leader(card, number, back, front, abilities, missing):
    def ab(trigger, effects, text=back, **extra):
        return dict(trigger=trigger, effects=effects, text=text, **extra)

    def target(**extra):
        return dict(s="choose", kind="unit", **extra)

    def damage(n, **extra):
        return dict(op="damage", n=n, t=target(**extra))

    def give(kw):
        return dict(trigger="attached_kw", kw=kw)

    def on_attack(effects, **extra):
        return ab("on_attack", effects, granted=True, **extra)

    def deploy(effects):
        return ab("when_deployed_upgrade", effects)

    def front_action(effects, resources=0):
        return ab("action", effects, front, cost={"resources": resources, "exhaust": True})

    blank = {"op": "blank_abilities", "t": target(side="friendly", opt=True, count=999)}
    power, hp = PILOT_LEADER_STATS[number]
    upgrade = {
        "001": [give("grit"), on_attack([damage(1, side="friendly", opt=True),
                                         dict(damage(1, side="enemy", arena_of_it=True), if_did=True)])],
        "003": [give("sentinel"), deploy([dict(op="shield", t=target(different_arena=True, opt=True))])],
        "006": [deploy([dict(op="token", name="tie_fighter", n=2)])],
        "008": [on_attack([dict(op="discount_next", n=1, filter=dict(kind="card", trait="pilot"))])],
        "009": [deploy([dict(op="split_unit_damage", n=4)])],
        "011": [on_attack([dict(op="buff", p=1, t=target(other=True, same_arena=True, opt=True))])],
        "012": [dict(trigger="constant", flag="enemy_defeat_immune"),
                on_attack([damage(3, opt=True)], host_trait="fighter")],
        "013": [ab("action", [{"op": "_reattach_pilot"}], cost={"resources": 1}, limit=1, limit_period="round")],
        "015": [give("saboteur"), dict(trigger="continuous", target="self", p=1, host_trait="transport", granted=True)],
        "017": [deploy([dict(op="ready_resource", amount="odd_permanent")])],
        "018": [on_attack([blank])],
    }[number]
    card["pilot"] = dict(power=power, hp=hp, aspects=card["aspects"], abilities=upgrade,
                         makes_leader=number != "013", text=back)
    if number == "013":
        card["pilot"]["flip_cost"] = 1
        missing = []
    if number == "001":
        abilities = [front_action([damage(1, side="friendly"),
                                   dict(damage(1, side="enemy", arena_of_it=True), if_did=True)])]
    if number == "003":
        abilities = [front_action([dict(op="play_from_hand", kind="card"),
                                   {"op": "shield", "t": target(), "if": {"both_arenas": True}, "if_did": True}], 1)]
        missing = []
    if number == "006":
        abilities[0]["effects"][0]["if"]["attacked_non_token"] = True
    if number == "008":
        abilities = [front_action([dict(op="play_from_hand", kind="upgrade", pilot_only=True, discount=1)])]
        missing = []
    if number == "009":
        abilities = [ab("noncombat_damage", [
            dict(op="exhaust", t={"s": "self"}, optional=True),
            dict(op="indirect_damage", n=1, player="choose", if_did=True)], front)]
        missing = []
    if number == "015":
        abilities = [front_action([dict(op="attack_with", t=target(side="friendly", arena="space", ready=True, can_attack=True),
                                       pre=[{"op": "buff", "p": 1}, {"op": "gain_kw", "kw": "saboteur"}])], 1)]
        missing = []
    if number == "017":
        abilities[0]["effects"][-1]["different_odd_power"] = True
        missing = []
    if number == "018":
        abilities = [front_action([dict(op="blank_abilities", t=target(side="friendly")), dict(op="extra_action")])]
        missing = []
    unit_text = re.split(r"\n(?:Attached unit|This upgrade|When deployed as an upgrade)", back, maxsplit=1)[0]
    if unit_text.startswith(("Attached unit", "This upgrade", "Action")):
        unit_text = ""
    leader_unit = card["leader_unit"]
    leader_unit["text"] = unit_text
    leader_unit["keywords"] = parse_keywords({}, unit_text)
    leader_unit["abilities"] = [ab("on_attack", [blank])] if number == "018" else []
    return abilities, missing


def compile_special_base(card, abilities, missing):
    cid = card["id"]
    setup = {"JTL_021": {"opening_hand_delta": -1}, "JTL_024": {"deck_size_delta": 10},
             "JTL_025": {"deck_size_delta": -5}, "JTL_028": {"opening_hand_delta": 3, "no_mulligan": True}}
    if cid in setup:
        card.update(setup[cid])
        if cid != "JTL_028":
            return [], []
        return [dict(trigger="action_start", effects=[dict(op="_bottom_opening_hand", n=3)], text=card["text"])], []
    if cid == "LOF_025":
        return [dict(trigger="friendly_combat_damage_to_base", effects=[dict(op="force_token")], text=card["text"])], []
    target = {"s": "choose", "kind": "unit"}
    table = {
        "LAW_019": ({"other": "defeat a friendly token"}, [{"op": "choose_one", "options": [
            {"label": "Give an Experience token", "effects": [{"op": "experience", "t": target}]},
            {"label": "Give a Shield token", "effects": [{"op": "shield", "t": target}]},
            {"label": "Create a Credit token", "effects": [{"op": "token", "name": "credit"}]},
        ]}]),
        "LAW_029": ({"resources": 1}, [{"op": "_recycle_resource"}]),
        "LAW_023": ({"other": "discard a unit from your hand"}, [{"op": "_search_named", "name": "The Sarlacc of Carkoon"}]),
        "LAW_026": ({}, [{"op": "_mill_recover_top", "n": 3}]),
        "TS26_010": ({}, [{"op": "play_from_hand", "kind": "unit", "discount_by_leaders": True}]),
        "TS26_011": ({}, [{"op": "_per_leader", "effects": [{"op": "damage", "n": 2, "t": {**target, "opt": True}}]}]),
        "TS26_009": ({}, [{"op": "_per_leader", "effects": [{"op": "experience", "t": target}]}]),
        "TS26_012": ({}, [{"op": "_sundari"}]),
    }
    if cid not in table:
        return abilities, missing
    cost, effects = table[cid]
    return [dict(trigger="action", epic=True, cost=cost, effects=effects, text=card["text"])], []


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
        number = cid.removeprefix("JTL_")
        if number in PILOT_LEADER_STATS and cid.startswith("JTL_"):
            abilities, unparsed = compile_pilot_leader(out, number, out["leader_unit"]["text"], norm_text(text), abilities, unparsed)
            b_ab, b_un, b_status = out["leader_unit"]["abilities"], [], "full"
            status = "partial" if unparsed else "full"
        else:
            b_ab, b_un, b_status = compile_text(c.get("BackText") or "", out["leader_unit"]["keywords"])
        out["leader_unit"]["abilities"] = b_ab
        out["art_back"] = cid
        unparsed += b_un
        if unparsed and (abilities or b_ab or status == "partial" or b_status == "partial"):
            status = "partial"
        elif unparsed:
            status = "manual"
    if typ == "base":
        abilities, unparsed = compile_special_base(out, abilities, unparsed)
        status = "partial" if unparsed and abilities else ("manual" if unparsed else "full")
    if cid in {"HMW_009", "JTL_123", "SOR_217", "SHD_128", "TWI_123", "JTL_124"}:
        pick = {"s": "choose", "kind": "unit", "side": "friendly", "can_attack": True}
        if cid in {"HMW_009", "JTL_123"}:
            pick.update(allow_exhausted=True, units_only=True)
        attack = {"op": "attack_with", "t": pick}
        if cid == "HMW_009":
            abilities = [{"trigger": "action", "cost": {"resources": 2, "exhaust": True},
                          "effects": [attack], "text": out["text"]}]
            out["leader_unit"]["abilities"] = [
                {"trigger": "action", "effects": [attack], "limit": 1, "limit_period": "round",
                 "text": out["leader_unit"]["text"]}]
        else:
            effects = [attack]
            if cid == "SOR_217":
                attack.update(first_strike=True, pre=[{"op": "buff", "p": 1}])
            if cid in {"SHD_128", "TWI_123"}:
                effects.append({"op": "attack_with", "t": {**pick, "not_it": True}})
            if cid == "JTL_124":
                attack["t"] = {**pick, "arena": "space"}
                effects.append({"op": "attack_with", "t": {**pick, "arena": "ground"},
                                "if_did": True, "pre": [{"op": "buff", "p": 2}]})
            abilities = [{"trigger": "event", "effects": effects, "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "SHD_120":
        abilities = [{"trigger": "when_played", "effects": [{"op": "capture", "source_captures": True}], "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "SOR_228":
        abilities = [{"trigger": "when_played", "effects": [{"op": "reveal_hand"}], "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "ASH_005":
        abilities = [{"trigger": "friendly_attack_end", "text": out["text"], "effects": [
            {"op": "exhaust", "optional": True, "t": {"s": "self"}},
            {"op": "heal", "n": 1, "if_did": True, "t": {"s": "subject"}},
        ]}]
        out["leader_unit"]["abilities"] = [
            {"trigger": "friendly_attack_end", "text": out["leader_unit"]["text"], "effects": [
                {"op": "heal", "n": 2, "t": {"s": "choose", "kind": "unit_or_base", "side": "friendly", "attacking_unit_or_base": True}}
            ]}
        ]
        unparsed, status = [], "full"
    if cid == "HMW_004":
        rule = {"trigger": "constant", "flag": "ignore_fortify_aspects"}
        abilities.append(rule)
        out["leader_unit"]["abilities"].append(rule)
        unparsed, status = [], "full"
    if cid == "JTL_249":
        abilities = [{"trigger": "constant", "flag": flag} for flag in ("extra_pilot", "power_per_pilot")]
        unparsed, status = [], "full"
    if cid == "JTL_144":
        abilities = [{"trigger": "event", "effects": [{"op": "damage", "leave_at_one": True,
                      "t": {"s": "choose", "kind": "unit", "nonleader": True}}], "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "JTL_209":
        abilities = [{"trigger": "event", "effects": [{"op": "ready", "if": {"fewer_units_in": "space"},
                      "t": {"s": "each", "kind": "unit", "arena": "space", "side": "friendly"}}], "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "SOR_005":
        abilities = [{"trigger": "action", "cost": {"resources": 1, "exhaust": True},
                      "effects": [{"op": "shield", "t": {"s": "choose", "kind": "unit", "side": "friendly",
                                   "aspect": "heroism", "played_this_phase": True}}], "text": out["text"]}]
        unparsed, status = [], "full"
    if cid == "SEC_001":
        abilities = [{"trigger": "action", "cost": {"resources": 1, "exhaust": True}, "text": out["text"],
                      "effects": [{"op": "search", "n": 5, "count": 1, "filter": {"keyword": "plot"}}]}]
        out["leader_unit"]["abilities"] = [{"trigger": "when_deployed", "text": out["leader_unit"]["text"],
            "effects": [{"op": "discount_next", "n": 3, "plot_only": True, "filter": {"kind": "card"}}]}]
        unparsed, status = [], "full"
    if cid == "TWI_015":
        pick = {"s": "choose", "kind": "unit", "trait": "droid", "opt": True}
        out["leader_unit"]["abilities"] = [{"trigger": "on_attack", "text": out["leader_unit"]["text"],
            "effects": [{"op": "buff", "p": 1, "dur": "phase", "t": pick},
                        {"op": "gain_kw", "kw": "sentinel", "dur": "phase", "if_did": True, "t": {"s": "it"}}]}]
        unparsed, status = [], "full"
    if cid in {"ASH_078", "HMW_257", "TWI_180", "TWI_142", "HMW_061"}:
        friendly = lambda **kw: {"s": "choose", "kind": "unit", "side": "friendly", **kw}
        patch = {
            "ASH_078": dict(trigger="continuous", target="self", kw="sentinel", condition={"friendly_unit": friendly(arena="ground")}),
            "HMW_257": dict(trigger="continuous", target="self", kw="ambush", condition={"friendly_unit": friendly(other=True, max_cost=3)}),
            "TWI_180": dict(trigger="continuous", target="self", kw="raid", v=2, condition={"friendly_unit": friendly(other=True, trait="separatist")}),
            "TWI_142": dict(trigger="continuous", target="self", p=2, condition={"base_damage_min": 15}),
            "HMW_061": dict(trigger="on_attack", effects=[dict(op="draw", n=1, **{"if": {"base_upgraded": True}})]),
        }[cid]
        abilities = [{**patch, "text": out["text"]}]
        unparsed, status = [], "full"
    out["abilities"] = abilities
    out["unparsed"] = unparsed
    out["implemented"] = status
    sc = saber_color(c)
    if sc:
        out["saber"] = sc
    return out


def complete_pilot_rules(card, pilot, unit, unit_missing, upgrade_missing):
    cid = card["id"].removeprefix("JTL_")
    def target(**extra):
        return dict(s="choose", kind="unit", **extra)
    def ability(trigger, effects, granted=False):
        lines = upgrade_missing if trigger in {"when_played_upgrade", "host_attack_end"} or granted else unit_missing
        return dict(trigger=trigger, effects=effects, granted=granted, text=" ".join(lines))
    def attack(*effects):
        return ability("on_attack", list(effects), True)
    immune = dict(trigger="constant", flag="enemy_defeat_bounce_immune")
    damaged = dict(trigger="continuous", target="self", condition={"enemy_damaged": True}, p=3)
    pilots = dict(trigger="continuous", target="self", scale_by="other_pilots", p=1)
    on_upgrade = {
        "197": [ability("host_attack_end", [dict(op="bounce", t={"s": "self"}, optional=True)])],
        "150": [dict(trigger="attached_kw", kw="overwhelm", host_trait="fighter"),
                dict(trigger="continuous", target="self", h=1, host_trait="transport", granted=True),
                dict(trigger="attached_kw", kw="grit", host_trait="speeder")],
        "215": [ability("when_played_upgrade", [dict(op="_mill_return_odd", n=2)])],
        "189": [ability("when_played_upgrade", [dict(op="_pilot_boba_damage")])],
        "048": [attack(dict(op="_mill_defender_draw"))],
        "103": [dict(immune, granted=True)],
        "142": [attack(dict(op="_vader_pilot_damage", t=target(opt=True)))],
        "139": [attack(dict(op="indirect_damage", n=2, player="choose", underworld_bonus=True))],
        "203": [ability("when_played_upgrade", [dict(op="attack_with", t={"s": "attached"},
                                                    optional=True, falcon_first_strike=True)])],
        "141": [dict(damaged, granted=True)],
        "109": [dict(trigger="continuous", target="self", condition={"both_arenas": True}, kw="sentinel", granted=True)],
        "094": [dict(trigger="constant", flag="defeat_into_unit")],
        "093": [dict(pilots, granted=True)],
        "066": [attack(dict(op="split_unit_damage", n=2, heal=True))],
    }
    on_unit = {
        "103": [immune],
        "141": [damaged],
        "093": [pilots],
        "049": [dict(trigger="constant", flag="defeat_into_pilot")],
        "100": [ability("when_played", [dict(op="token", name="x_wing"),
                                       dict(op="_unit_into_pilot", optional=True)])],
    }
    if cid in on_upgrade:
        pilot["abilities"].extend(on_upgrade[cid])
        upgrade_missing.clear()
    if cid in on_unit:
        # Some compound lines were only partially compiled; replace their trigger as a whole.
        if cid == "100":
            unit[:] = [a for a in unit if a["trigger"] != "when_played"]
            # The printed card and official card entry give Piloting cost 2.
            pilot["cost"] = 2
            for kw in card["keywords"]:
                if kw["k"] == "piloting":
                    kw["v"] = 2
            card["text"] = card["text"].replace("Piloting [C=3", "Piloting [C=2")
        unit.extend(on_unit[cid])
        unit_missing.clear()


def compile_pilot(card: dict, keyword: dict, stats: tuple[int, int]):
    pilot_block = re.search(r"(?im)^piloting\s*\[[^\]]+\][^\n]*", card["text"])
    unit_lines = card["text"][:pilot_block.start()]
    upgrade_lines = card["text"][pilot_block.end():]
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
             "power": stats[0], "hp": stats[1], "abilities": upgrade_abilities,
             "text": card["text"][pilot_block.start():].strip()}
    if card["id"] == "JTL_245":
        pilot["extra_slot"] = True
        upgrade_missing = [line for line in upgrade_missing if line not in {
            "This upgrade can be played on a friendly Vehicle unit with a Pilot on it.",
            'Attached unit gains: "You may play or deploy 1 additional Pilot on this unit."',
        }]
    complete_pilot_rules(card, pilot, abilities, missing, upgrade_missing)
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
