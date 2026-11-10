SWU Sabacc 0.4.0 — Campaigns, Battles and earned card packs.

- Grouped game modes under Campaigns and Battles, with collection/deckbuilding,
  card packs and settings utilities on the main menu.
- Added saved ten-card packs: five Common, two Uncommon, Rare-or-better, leader
  and base. Rip the seal, watch face-down cards burst out, then flip each card
  with rarity colors/effects. Reveals persist immediately; reopening cannot
  reroll or lose rewards. One unlock grants a legal deckbuilding playset.
- Earn packs for Saga chapter-run completion, cleared Spotlight sectors, the end
  of a Spotlight run with a victory, and every two traditional games. Abandoning
  a new run does not unlock the borrowed run deck or award a pack.
- Added starter collections, saved-deck migration and owned-card enforcement in
  the deck editor and traditional auto-build. GM access preserves earned cards.
- Reviewed seeded campaign results and softened the Death Star chapter entrance:
  22 starting base HP and an extra removal card in Hangar/Detention encounters.
- Implemented Support attacks with temporary borrowed abilities, recovery,
  opponent hand reveals, event-to-resource and opponent-chosen defeat. Fixed
  granted When Defeated snapshots and unit-or-base targeting.

Validation: 50 progression/UI checks, 50 extended rule checks, 551 broader engine
assertions, 500 simulated games without stalls, 48 Spotlight opening encounters,
100 tuned Death Star encounters, and an audit of all 2,558 non-token cards.
See docs/PACKS_CAMPAIGN_QA.md for evidence and limitations.

**Card automation is still incomplete:** 1,060 cards have complete compiler text
coverage, 544 are partial and 984 remain manual. Coverage is not proof of correct
rules. Only Episode IV currently has authored Saga content.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. Native builds bundle offline assets. Existing package/signing key and
legacy updater bridge are retained. No Android device was attached for physical
installation/upgrade or touch-performance testing; Android confirms installation.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
