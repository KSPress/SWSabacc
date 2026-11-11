SWU Sabacc 0.6.1 — inspector navigation and graphical fixes.

- Fixed expanded inspector return controls scrolling out of view in landscape.
  Back to card now stays visible while the dossier scrolls.
- Added Android Back and Escape handling for overlays and ordinary screen
  navigation. Repeated modal/picker closure cannot start duplicate close tweens.
- Removed opaque black scan bars crossing the large background emblem. The
  remaining transmission detail is translucent and matches its palette.
- Fixed expired impact effects drawing negative widths/radii after a slow frame.
  Muzzle, impact, shockwave, slash and punch effects stop drawing at expiration.

Validation: 122 GUI input assertions (six baseline failures reproduced, now zero),
114 responsive assertions over eight ratios/152 screen states, 75 cinematic,
80 visual, ten rendered effect-lifetime, 553 gameplay, 50 extended-rules,
50 progression, 24 manifest and nine updater-flow assertions passed.
Zero broken scripts. See docs/BUGFIX_QA.md for evidence and limitations.

Fresh Windows startup clicks worked during investigation. The inspector blockage
was reproduced and fixed; the separate initial-launch freeze was not reproduced.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. The existing Android signing identity, saves and legacy update bridge
are retained. No physical Android installation/touch-performance test was possible.
Card-engine automation remains incomplete; this release does not certify full SWU
rules support. Unauthored Saga episodes remain placeholders.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
