# SWU Sabacc 0.6.1 bug sweep

## Reproduced and fixed

The expanded radial inspector placed its only return button at the end of
scrolling content. At 1280x720 and 2560x1080, a pointer could not reach it without
scrolling first; the remaining modal continued to block the inspector and menu.
The baseline GUI input regression recorded six failures across those two ratios.
The return button now lives in a fixed footer outside the scroll container.

Android Back now dismisses only the highest open dossier, inspector, card picker
or general modal. Escape also navigates ordinary screens back through their
existing back target. Back on the main menu or active match does not quit or
abandon the game. Repeated modal/picker closure is guarded against duplicate
tweens, and input remains captured until the closing modal is removed.

The large background emblem drew sixteen opaque near-black bars over the glyph.
They were intentional scan detail but looked like rendering corruption. They
are replaced by translucent, palette-colored fragments outside the glyph and a
faint sweep. Reviewed full-emblem Fett/Sith screenshots have no black scan bars.

A rendered pack test also exposed a warning in impact drawing: an effect could
survive until the end of a slow frame with a time beyond its lifetime, producing
negative arc widths/radii and alpha. Impact, muzzle, shockwave, slash and punch
effects now stop drawing at expiration. A dedicated rendered regression verifies
that each live effect changes pixels and each expired effect leaves the exact
background pixels unchanged.

## Validation

Evidence is local in `build/qa/bugfix/`:

- `input-baseline.log`: 106 checks, six failures before the footer fix.
- `input-fixed.log`: 122 checks, zero failures. Sends actual viewport pointer
  events, not emitted button signals. Exercises the real splash, all seven menu
  entries, showcase inspection, expansion, closing, Android Back notification,
  Escape and subsequent menu clicks at four portrait/landscape ratios.
- `layout.log`: 114 checks, zero failures and zero detected button layout issues
  over eight ratios and 152 screen states.
- `cinematic.log`: 75 checks, zero failures, including all 25 emblem fields and
  combat/inspector captures. `visual/` contains the screenshots.
- `polish.log`: 80 checks, zero failures; includes full emblem screenshots and
  pack/collection/customization layouts. Its impact warning led to the lifetime
  fix above. `fx-lifetime.log`: ten rendered pixel assertions, zero failures and
  no rendering warnings after that fix.
- `engine.log`: 553 assertions, zero failures; standard/quick bot simulations
  report zero stuck matches, with campaign and Spotlight checks included.
- `extended.log`: 50 rules checks, zero failures.
- `progression.log`: 50 pack/collection progression checks, zero failures.
- `update.log`: 24 manifest checks, zero failures.
- `updater-flow.log`: nine updater failure/cache checks, zero failures.
- `compile.log`: zero broken scripts.
- The packaged 0.6.1 Windows EXE was launched with an isolated copy of the user's
  saved settings/loadout. Native mouse clicks opened a showcase card, expanded
  anatomy, used the pinned return button, closed inspection and navigated to
  Battles successfully. The Sabacc emblem background had no opaque scan bars.

The fresh Windows menu responded to native mouse input before these changes.
The user's initial-launch freeze has therefore not been independently reproduced;
the inspector exit blockage is a verified issue, not a claim that every possible
input freeze is resolved. Physical Android installation and touch-performance
testing remain unavailable. Existing full/partial/manual card coverage limits
remain; passing these tests does not certify every printed card interaction.
