SWU Sabacc 0.5.0 — pack reveals, emblem identity and responsive polish.

- Upgraded pack opening with animated foil, an emblem seal, drag/touch seam
  feedback, anticipation, wrapper separation, radial bursts and staggered cards.
- Added a possible bonus beyond the ten cards: 12.5% emblem chance or 5% scene
  background chance. Bonuses are pre-rolled, saved and individually revealed.
  Already-owned/pending cosmetics are excluded from the selected pool at roll
  time. Exhausted pools give no bonus; existing packs keep their saved contents.
- Reviewed all 25 emblem palettes. Backgrounds and profile frames now match the
  selected glyph, including olive Fett, warm ivory Old Republic and silver emblems.
- Replaced repeating hologram pulses with noise and irregular signal drops,
  plus smooth cursor/finger tilt. Performance mode freezes decorative motion.
- Made default datapad enemy-turn transitions more obvious using active-turn
  ownership, faster aspect blending and an ambient color wash.
- Fixed icon-only button padding that overlapped the match Log/Settings/PASS row,
  reset PASS width after rotation, and centered cosmetic/deck/collection grids.

Validation: 114 checks across eight ratios and 152 screen states, with zero
out-of-bounds buttons or detected button overlaps; 50 existing progression checks;
80 visual/interaction checks; zero broken scripts; 24 manifest checks. See docs/POLISH_QA.md for evidence,
visual checks and limitations.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. The existing Android signing identity, saves and legacy update bridge
are retained. No physical Android installation/touch-performance test was possible.
Card-engine automation remains incomplete; this release does not certify full SWU
rules support. Unauthored Saga episodes remain placeholders.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
