# SWU Sabacc 0.4.0 — campaign and card-pack validation

## Delivered flow

Main navigation groups modes under Campaigns (Saga and Spotlight Roguelike) and
Battles (Traditional and Custom), with Deck Builder, Collection, Card Packs and
Settings utilities. Custom formats retain preset loaner decks; traditional deck
selection and auto-build use the owned collection. GM grants access without
writing card entitlements into the earned account. GM games do not earn packs or advance the two-game meter.

A new account starts with the first two complete traditional Spotlight decks.
Migration preserves existing vault entries and every saved custom deck. One card
unlock grants deckbuilding access to its legal playset (up to three copies), not
one consumable physical copy. Locked cards remain browsable and inspectable.

Each pack contains ten cards: five Common, two Uncommon, one Rare (1/8 chance of
Legendary instead), one leader and one base. These are game-specific packs, not a
claim to reproduce physical SWU booster collation. Slots prefer unowned cards
within their pool and reserve cards already waiting in unopened packs. After a
pool is exhausted, duplicates are possible; they never remove owned cards.

Rewards:
- One pack for completing a Saga chapter campaign run.
- One pack for each cleared Spotlight sector.
- One pack when a Spotlight run ends in defeat after at least one battle win.
  Abandoning a run or losing without a win gives no pack.
- One pack after every two completed traditional games, regardless of winner.
  Custom games count only when they use the traditional format.

Packs are pre-rolled and saved when earned. Tearing the seal and each individual
reveal are saved; reopening the screen cannot reroll cards or lose revealed
unlocks. Collect is enabled only after all ten cards are revealed. The pack splits
at a jagged seal, throws face-down cards into the screen, and uses rarity borders,
glows, impact bursts and flip animations. Revealed cards can be inspected.

## Balance review

Only Episode IV currently has authored Saga content. Episodes I–III and V–IX are
still placeholders; this update does not invent campaigns for those episodes.

A seeded baseline tested six opening encounters for each of eight traditional
Spotlight decks (48 games). All completed without stalls; individual decks won
2–5 of 6. This is a small bot sample, not a human balance certification. No blanket
Spotlight difficulty change was made from that sample.

The existing Saga suite exercises every combat node with 20 seeds. It exposed a
Death Star chapter spike: Hangar Bay 327 won 30%, Detention Block AA-23 won 20%.
The chapter now starts with 22 base HP instead of 18, and those two encounters
include one Open Fire in the player's bonus hand. With the same 20 seeds, results:

| Death Star encounter | Before | After |
|---|---:|---:|
| Hangar Bay 327 | 30% | 55% |
| Trash Compactor | 95% | 100% |
| Detention Block AA-23 | 20% | 35% |
| Tractor Beam Controls | 85% | 95% |
| Duel on the Death Star | 85% | 95% |

These staged tests use the starting deck without rewards from earlier nodes. The
elite remains challenging. Run deck growth, treasure choices, routes and the
human player's decisions still require human playtesting. Unsupported card text
can affect balance, so difficulty conclusions remain provisional.

## Validation

- Progression/UI: **50 checks passed, zero failed**, including the whole pack flow
  in landscape and portrait, saved partial reveals, duplicate guards, GM access,
  migration, restricted auto-build, and real Saga/Spotlight reward integration.
- Engine extension suite: **50 passed, zero failed**.
- Broader engine/campaign suite: **551 passed, zero failed**, with **500 simulated
  games and zero stalls** across traditional and quick formats.
- GDScript compilation: zero broken scripts. Release-manifest tests: 24 passed.
- Card smoke audit: all **2,558 non-token cards** exercised without script errors.
  Eight contextual flags remain: two cannot-attack units, a leader action lacking
  its qualifying discard, and five optional/search/recursion effects changing
  nothing on the staged fixture. This is not proof of semantic correctness.

Artifacts and screenshots: `build/qa/packs/`. The save/reload test found and fixed
JSON numeric indexes needing normalization to integers. A restricted auto-build
fixture was corrected to use a leader with the card's actual Command aspect.

## Continuing card implementation

Added Support attacks with borrowed keywords and abilities that expire after the
attack; enemy Support/Ambush suppression; discard recovery; event-to-resource;
opponent hand reveal; opponent-chosen defeat; and unit-or-base damage selectors.
Defeat now snapshots granted When Defeated abilities before removing upgrades
and temporary abilities. Tests exercise borrowed Overwhelm, borrowed On Attack,
keyword suppression, recovery and opponent choice ownership.

Inventory: **2,588 cards**, **1,060 complete compiler text coverage**, **544 partial**,
**984 manual**. That is 27 additional fully compiled cards compared with 0.3.0.
The strict full-coverage gate still fails because **1,528 cards remain incomplete**.
Compiler coverage does not establish correct gameplay. Piloting and many complex
card interactions still need implementation and semantic tests.

The signed Android build keeps package ID/signing key and version code advances
to 5 (0.4.0). Installation and updates on a physical Android device remain
unverified. Downloaded updates require Android's installer confirmation.
