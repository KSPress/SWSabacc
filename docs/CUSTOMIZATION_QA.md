# SWU Sabacc 0.3.0 validation

## Cosmetics

The supplied originals remain unchanged. `tools/import_customization.py` imports
25 transparent emblem glyphs and crops 37 card backs to 500×698 WebP. Three
explicit crop overrides are in `tools/customization_crops.json`. The contact
sheet and crop coordinates are in `build/qa/customization/`. Generated assets
and original IP assets stay outside Git.

Normal-account wins award one random unowned item. There are 68 collection items,
including three starter items, with no duplicate rewards. Losses and draws give
no cosmetic. Matching emblem holograms become available with the equipped emblem.
Four existing static scene backgrounds join the reward pool. Play mats are a
future category. Account progress is saved offline.

The red GM toggle grants access with a separate equipment loadout, preserving
earned items and account equipment. GM wins do not earn items. Repeated result
callbacks cannot increment wins or grant rewards twice.

Datapad/hologram traces use leader/base aspects and fade toward enemy aspects on
the enemy turn. Performance mode freezes motion. Profile glyphs use miniature
animated datapad frames. The emblem background shows a faded, scanned and
flickering large glyph beneath the board.

## Checks

- Cosmetic regression and actual UI paths: **90 passed, 0 failed**. Includes the
  entire random pool, persistence, GM separation, turn fades, red settings control,
  actual victory reward, duplicate callback guard and pointer access to Profile.
- Theme/inspection visual and behavioral suite: **49 passed, 0 failed**;
  portrait, landscape and tall phone layouts.
- Added rules regressions: **38 passed, 0 failed**. Upgrade targeting/defeat,
  conditional keywords/auras, undeployed leader auras, capture/rescue/bounty,
  captured tokens, Fortify, Plot/payment using the resource being played,
  and combat damage before defenders.
- GDScript compile check: **0 broken scripts**.
- Release-manifest validation: **24 passed, 0 failed**.
- Updater flow: **9 passed, 0 failed**.
- Full rules/campaign regression: **545 passed, 0 failed**, with **500 bot games**
  across standard and quick modes and no stalls after the resource-payment fix.

The signed Android build passed signature, 16 KB alignment, package/version and
permission checks. Its archive includes the cosmetic catalog, 62 imported asset
mappings and project.binary. The exported Windows game launched and displayed
version 0.3.0 with rendered cards and profile glyph. A real pointer check found
the full-width menu title blocking the Profile button; raising that button above
the title fixes it, verified with viewport mouse input in the 90-check suite.

Logs, reports and screenshots: `build/qa/cosmetics/`. The victory screen test
caught and fixed a stale Settings button signal callback. Texture resources
are cached to prevent transient textures becoming blank GPU draws.

## Every-card audit — incomplete

The inventory includes all **2,588 cards**: **1,033** have complete compiler text
coverage, **542** are partial and **1,013** remain manual. These labels measure
recognized text, not semantic correctness. The strict gate
`python -I tools/check_card_coverage.py --require-full` intentionally exits 1
because **1,555 cards remain incomplete**. Every card's uncompiled text and
unsupported keywords are in `build/qa/cosmetics/card_coverage.json`.

The staged engine smoke audit exercised all **2,558 non-token cards**. Six context
flags remain: two printed "can't attack" units; a leader requiring a qualifying
discard; two versions of a Vehicle search without Vehicles in the staged deck;
and an optional sacrifice/search effect whose chosen branch changed nothing.
These observations do not certify those cards. No runtime script errors were
observed in that audit.

This update implements selected additional mechanics. It does not complete the
user's every-card automation requirement. Piloting, Support and many card-specific
interactions still need implementation and focused semantic tests. Full compiler
coverage, even when reached, must be followed by card-specific correctness checks.

Official rule references checked:
[capture/bounty](https://starwarsunlimited.com/articles/shadows-of-the-galaxy),
[Plot](https://starwarsunlimited.com/articles/secrets-of-power),
[Fortify](https://starwarsunlimited.com/articles/defend-and-destroy).

## Device limits

Native builds bundle the database, card art and cosmetics for offline play.
Android retains its package ID/signing key and both updater manifests for older
clients. Installation/replacement requires Android installer confirmation.
No Android device was attached to verify installation, touch performance or a
real in-place upgrade.

