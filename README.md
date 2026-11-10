# SWU Sabacc (working title)

A fan-made, non-commercial digital version of **Star Wars: Unlimited** with a
Hearthstone-style mobile/desktop/browser presentation and a roguelike campaign
through the Skywalker saga. Built with **Godot 4.7** (GL Compatibility renderer).

- Build spec: [`SWU_SABACC_BUILD_SPEC.md`](SWU_SABACC_BUILD_SPEC.md)
- Research & design notes: [`docs/DESIGN.md`](docs/DESIGN.md)
- Card engine coverage: `docs/coverage_report.md` (generated)

> Star Wars, Star Wars: Unlimited, card names, text and art belong to Lucasfilm Ltd.
> and Fantasy Flight Games. This repo's code is IP-free; all IP-bearing assets are
> generated locally into the git-ignored `game/ip/` folder.

## Themes and card inspection
Campaigns groups Saga and Spotlight roguelike runs; Battles groups Traditional
and Custom formats. Card Packs on the main menu opens saved rewards. Complete a
Saga chapter run, clear a Spotlight sector, finish a Spotlight run with a win,
or complete two traditional games to earn a pack. Packs contain ten cards with
a leader, base and rare-or-better slot. Rip open the pack and flip the cards;
each reveal permanently unlocks a legal playset for custom deckbuilding.
Two starter decks are available on new accounts, and existing saved decks retain
their cards on migration. See [pack/campaign validation](docs/PACKS_CAMPAIGN_QA.md).

Settings → Appearance → Profile, card backs & backgrounds opens the cosmetic
collection. Normal-account wins award one random unowned cosmetic: 25 emblems,
37 card backs and four static scene backgrounds are supported. Emblems include
their matching faded hologram background. Play mats are reserved for a future
release. The default datapad is free; its slow orbital traces use leader/base
aspects and fade to the opposing palette on enemy turns. Deck aspects also tint
buttons and friendly outlines. The red GM toggle grants access to all cosmetics
with a separate loadout; returning to account mode restores earned selections.

Import the supplied local `Customization/` assets with
`python -I tools/import_customization.py` (Pillow with AVIF support required).
Card backs are cropped and converted to 500×698 WebP. Originals remain intact;
generated files and the source asset folder are excluded from Git.

Every-card automation is **unfinished**: the current inventory contains 1,060
cards with complete compiler text coverage, 544 partial and 984 manual.
Compiler coverage is not proof of correct rules behavior. Run
`python -I tools/check_card_coverage.py --require-full` to generate a per-card
inventory and fail the gate while incomplete cards remain. See
[`docs/CUSTOMIZATION_QA.md`](docs/CUSTOMIZATION_QA.md) for this release's checks.

Inspecting a card flies it to the screen centre, blurs the surrounding game and
opens four connected dossiers: card profile, printed ability, keyword/timing
explanations, and live state/engine support. Dossiers scroll when needed. Flip
leaders to inspect both sides; close or press Escape to return. Performance mode
uses a dim backdrop and still linework instead of blur and rotation.

The game is now **SWU Sabacc**, hosted at **KSPress/SWSabacc**. Android keeps its
existing package ID/signing key so updates retain progress. Existing desktop and
Android saves migrate automatically. The legacy-named APK and `update.json` release
assets are compatibility bridges for v0.1.1; new versions use `swu_sabacc.apk` and
`sabacc-update.json`.

## What works now (foundation)
- **Rules engine** (pure GDScript, headless-testable): rounds, strict alternating actions, pass/initiative, regroup, resources and aspect penalties, ground/space arenas, combat, Shield/Experience tokens, leaders (actions + Epic Action deploy), upgrades, events, Smuggle, and the keywords Sentinel, Shielded, Grit, Saboteur, Ambush, Overwhelm, Raid, Restore, Hidden. Data-driven claimable tokens (Initiative, Blast, Plan, Krayt Call, Alarm), objectives (standard, survive N rounds, defend a unit, hunt, attrition) and turn modes (alternating / burst).
- **Card pipeline**: 2,588 unique cards imported; ability text compiled to an effect DSL (979 full, 574 partial, 1,035 needing custom logic); 2,760 art renders bundled in native builds. This foundation does **not yet implement every SWU card ability or the complete official rules**.
- **Bot AI** with aggressive / tempo / defensive profiles (~0.7 ms per decision).
- **Formats**: *Standard Battle* = traditional SWU (Premier: 50-card decks, printed base HP, both arenas with Ground nearest you, aspect penalties, 3-copy limit) using your saved decks, a Spotlight deck, or an auto-built deck. *Quick Battle* = Expansion Spotlight decks with 20-HP bases in the mode chosen in Settings: **One Lane** (space units fight in the ground lane), **Traditional** (two arenas), **Ground Only** or **Space Only** (balanced single-arena decks; pilot leaders only in Space Only).
- **Spotlight Campaign**: an endless roguelike per Spotlight deck. Start with its leader, base and 20 of its 50 cards (30-HP base, 20 credits); win battles to earn the rest of the list plus loot in your aspects. Each sector is a random branching map of battles, missions (hold the line / hunt a target / supply raid), elites, events, black markets, safe houses and hidden caches, ending in a boss (another Spotlight deck). Edit your deck between nodes, upgrade cards with permanent Experience/Shield, collect perks; damage carries over until your base falls. Every Spotlight deck keeps its own record (runs, best sector, most wins, bosses, last 10 runs).
- **Deck Builder**: save decks with a name, icon and favourite mark; each shows its leader's and base's aspect icons. Leader/base chosen from a radial card menu filtered by aspect; live curve, counts and Premier legality.
- **UI** for portrait and landscape: animated menu, collection vault (search/filter/inspect), quick battle vs bot, Episode IV campaign with branching node maps, events, rest stops, rewards and treasures, and the match board with drag-to-play, drag-to-attack arrows, inspect-anything zoom, hex unit tokens and combat FX.
- **Episode IV** fully authored: Tatooine (C-3PO), Death Star Rescue (Han or Chewbacca), Battle of Yavin (Luke, all-space).

## Play in the browser / install as an app
The web build is an installable web app (PWA): play it in any modern browser, or
use *Add to Home Screen* (iPhone/iPad: Safari → Share; Android: Chrome menu) to
install it like an app. After the first visit it starts offline, and installed
copies update themselves on the next launch after a new publish.

No card art is hosted with the game: each image is loaded in the player's browser
straight from the official card image server (the same one the official card
database uses), so the site itself is only ~24 MB. The fly-by ships are left out
of the web build.

```bash
# (when a new set comes out) refresh the index of official card image URLs
python -I tools/web/build_art_map.py
```

```bash
# build build/web/ (and a zip); test locally at http://localhost:8060 with play.py
python -I tools/web/build_web.py
```

```bash
# publish to GitHub Pages (branch gh-pages; one-time: Settings -> Pages -> gh-pages / root)
python -I tools/web/publish_pages.py
```

> Unofficial, non-commercial fan project. Not affiliated with Disney, Lucasfilm or
> Fantasy Flight Games. Star Wars characters, cards, logos and art are property of
> Disney and/or Fantasy Flight Games.

## Android app
`python -I tools/android/build_android.py` builds a signed `build/android/swu_sabacc.apk`
(ARM64, plays offline with all local card art). It needs a local JDK 17 +
Android SDK in the git-ignored `tools/android-sdk/` (see the script). Sideload it:
copy it to the phone or download the APK from GitHub Releases, then allow
"install unknown apps" for your browser. Keep `kyber-release.keystore`: updates
must be signed with the same key. Public builds are distributed through
[GitHub Releases](https://github.com/KSPress/SWSabacc/releases/latest).

Android automatically checks the latest release at startup and downloads a newer
APK in the background. Its size and SHA-256 digest must match `sabacc-update.json` before
it can be installed. The menu offers installation after the download; Settings
also provides **Check for updates / Install update** and an automatic-download
toggle. Android asks you to allow this app to install updates and confirm the
installation. This is not silent installation. Keep the existing app installed
to preserve progress. Internet and request-install-packages are the only requested
permissions; an unavailable update server never blocks offline gameplay.

To ship the next update: increase `VERSION_CODE` and `VERSION_NAME` in
`game/engine/release_info.gd`, match the Android preset versions, run the tests,
build both platforms, commit/push the tested source, and run
`python -I tools/publish_release.py --publish`. This uploads the APK, matching
manifests, compatibility APK alias, and Windows ZIP to one public release. Without `--publish`, it prepares
a draft. Use the same keystore for every release. A Git commit alone does not
publish an update; the signed builds must be released.

## Windows app

`python -I tools/build_windows.py` produces `build/SWSabacc-windows.zip`.
Extract it and launch `SWU_Sabacc.exe`, keeping `SWU_Sabacc.pck` alongside it.
Card data and art are bundled; no browser or network connection is required.

The verification results and remaining gaps are recorded in
[`docs/QA_REPORT.md`](docs/QA_REPORT.md).

## Setup
Requirements: Godot 4.7 (tested 4.7.2, with export templates for web builds), Python 3.9+ (stdlib only).

```bash
# 1. Import the card DB (reads swu_data/cards_all.json -> game/ip/data/cards.json)
python -I tools/import_cards.py
```

```bash
# 2. Convert card art (swu_data/art -> game/ip/art/cards/*.kart, ~10 min first time)
godot --headless --path tools/godot_tool --script res://convert_art.gd -- "swu_data/art" "game/ip/art/cards"
```

3. Build the official UI assets (logo, card backs, aspect icons, Initiative/Plan/Blast/Force tokens, fly-by ships, planets) from the reference images in the project root into `game/ip/ui/`:

```bash
godot --headless --path tools/godot_tool --script res://build_assets.gd -- "."
```

4. Copy fonts/UI art into `game/ip/` (`fonts/Aurebesh-English.ttf`, `ui/tatooine.jpg`, `ui/deathstar.jpg`, `ui/swu_background.jpg`, `ui/banner.webp`, `ui/card_back.png`, …) — already done in this checkout.
5. Open `game/project.godot` in Godot and press Play (F5).

## Tests and tools
```bash
# Rules tests + 200 bot-vs-bot games + campaign validator/simulator
godot --headless --path game --script res://tests/run_tests.gd -- 200
```

```bash
# Compile-check every script with autoloads active
godot --headless --path game res://tests/compile_all.tscn
```

```bash
# Screenshot every screen in portrait + landscape (needs a GPU window)
godot --path game res://tests/shots.tscn -- shots_out
```

```bash
# Rebuild the Quick Play / Spotlight deck pool (game/data/spotlight_decks.json)
python -I tools/build_spotlight.py
```

```bash
# Engine audit of every card, then the readable report (docs/card_audit.md)
godot --headless --path game --script res://tests/card_audit.gd -- audit.json
python -I tools/audit_report.py audit.json
```

```bash
# Find candidate cards for a chapter (heroism gate, fully-supported first)
python -I tools/assign_cards.py --names "Luke,Leia,Han" --side heroism --only-full
```

## Exporting
Presets for Android, iOS, Web and Windows are in `game/export_presets.cfg`
(install export templates via *Editor → Manage Export Templates* first). Presets
include `ip/art/cards/*.kart` and the JSON data as non-resource files.

## Controls
| Do | Touch | Mouse |
|---|---|---|
| Inspect any card/token/base | long-press | right-click or double-click |
| Play a card | drag it up out of the hand | same |
| Attack | drag your unit onto a glowing target (or tap unit, then target) | same |
| Leader action / deploy | tap the leader tile | click |
| Smuggle | tap your resource pips | click |
| Claim initiative / tokens | token tray | click |

## Layout
```
tools/        importer, art converter (godot_tool/), card-assignment helper
game/engine/  rules engine, AI, campaign logic (no Nodes)
game/ui/      kit, cards, board, screens
game/data/    campaign JSON + custom KYB_ cards (ids only, IP-free)
game/ip/      git-ignored card DB, art, fonts, UI art
docs/         design notes, coverage report
```
