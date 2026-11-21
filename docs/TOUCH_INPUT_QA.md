# SWU Sabacc 0.6.2 customization touch input

The user clarified that Android customization would not scroll through emblems
and backgrounds, and that the other menu blockage occurred in the Windows EXE.
These are tracked as separate symptoms.

## Reproduced Android-style gesture failure

The previous customization hierarchy placed the grid inside a plain Control
with the default STOP mouse filter. Texture previews also intercepted input.
Wheel scrolling could pass through this hierarchy, while finger drags and some
trackpad pans did not reach the native ScrollContainer. A drag starting on an
equip button could instead release as a tap and equip an unwanted cosmetic.

Customization now uses TouchScroll, which follows the primary finger across
child controls. Movement past 14 logical pixels sends the standard scroll-begin
notification to cancel child button presses, then updates the scroll offset.
Vertical and horizontal swipes cancel equip taps; stationary taps still equip.
Emulated mouse movement cannot apply scrolling a second time. Scrollbar input
remains native. Decorative preview images ignore input and the centering canvas
passes it through, restoring trackpad pan propagation. Open modals prevent the
underlying customization list from starting a finger gesture.

The tests send ScreenTouch/ScreenDrag events plus the corresponding emulated
mouse events through the viewport GUI pipeline, with touchscreen emulation
enabled. The baseline option removes TouchScroll and restores the old input
filters on the same UI, so the old and fixed paths see the same gestures.

## Executed validation

Local evidence: `build/qa/touch/`.

- `touch-baseline.log`: 42 assertions, 26 failures in the previous hierarchy.
- `touch-final.log`: 42 assertions, zero failures. Emblem, card-back and
  background categories in portrait and landscape: preview swipes, swipes
  starting on buttons, horizontal swipe cancellation, exact scroll displacement
  without duplicate mouse movement, trackpad pans and stationary equip taps.
  A shortened scroll viewport forces the small background catalogue to overflow.
- `menu-input.log`: all 122 existing GUI navigation assertions pass, including
  real splash completion, every main-menu entry, inspector return controls,
  Escape and subsequent menu clicks.
- `layout.log`: 114 assertions across eight ratios and 152 screen states,
  zero detected button bounds or overlap issues.
- `compile-final.log`: zero broken scripts before packaging.
- `update-tests.log`: 24 manifest checks pass at version 0.6.2/code 9.
- `package-probe.log`: the exported Windows PCK loads the customization screen
  with TouchScroll. The signed APK contains its compiled script and remap.

The APK uses version 0.6.2/code 9 and the existing package/signing identity.
Build scripts verify signature, alignment, version and required permissions.
Physical Android installation and finger/touch-performance testing remain
unavailable. Synthetic touch coverage does not replace a device test.

## Windows investigation remains separate

The Windows input suite and the previous packaged native mouse click-through
passed, including an isolated copy of the user's saved settings/loadout. This
does not establish the cause of the user's Windows main-menu lockup. The patch
does not claim an independently reproduced Windows startup-freeze fix.
Always extract the current EXE and PCK together from the Windows archive.
The 0.6.2 fullscreen EXE reached its menu with the isolated loadout, but native
click verification was inconclusive while local mouse input and overlapping
desktop windows were active. No successful fullscreen navigation is claimed.

The earlier inspector, emblem rendering and effect-lifetime fixes are retained;
see `docs/BUGFIX_QA.md`. Card-engine rules and pack rewards are unchanged.
