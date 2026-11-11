SWU Sabacc 0.6.2 — Android customization scrolling.

- Fixed finger scrolling over emblem, card-back and background previews.
- Swipes starting on equip buttons scroll without accidentally equipping items.
  Horizontal swipes cancel taps too; stationary taps still equip normally.
- Fixed trackpad pan events blocked by cosmetic preview/centering controls.
- Retained 0.6.1 inspector navigation, emblem scan-bar and expired-effect fixes.

Validation: 42 touch-input assertions passed (26 baseline failures reproduced),
122 menu/inspector GUI input assertions passed, and 114 responsive assertions
over eight ratios/152 screen states passed with zero detected layout issues.
Zero broken scripts. See docs/TOUCH_INPUT_QA.md for evidence and limitations.

The Windows main-menu lockup remains unreproduced in native testing and is
tracked separately from the confirmed Android scrolling failure.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. The existing Android signing identity, saves and legacy update bridge
are retained. No physical Android installation/touch-performance test was possible.
Card-engine automation remains incomplete; this release does not certify full SWU
rules support. Unauthored Saga episodes remain placeholders.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
