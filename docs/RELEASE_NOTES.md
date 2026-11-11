SWU Sabacc 0.6.0 — Sabacc tokens, cinematic combat and expanded inspection.

- Replaced Force and Initiative markers with the supplied Sabacc fronts and
  backs. Gain, spend and claim actions animate a face-changing card flip.
- Added melee windup, curved swings and contact flashes. Ground Force characters
  use lightsabers: red for Villainy, blue/green for Heroism. Rounded luminous
  blaster bolts are green for Villainy, red for Heroism and yellow for neutral,
  with target impact flashes and sparks.
- Gave all 25 emblem backgrounds their own animated line geometry while
  retaining matching palettes, irregular flicker and input parallax.
- Expanded radial inspection with actual aspect icons, card anatomy, deployment
  thresholds, upgrade modifiers, referenced keywords and expandable dossiers.

Validation: 75 cinematic/inspector assertions, 114 responsive assertions over
eight ratios and 152 screen states (zero detected layout issues), 24 update
manifest assertions and zero broken scripts. See docs/CINEMATIC_QA.md.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. The existing Android signing identity, saves and legacy update bridge
are retained. No physical Android installation/touch-performance test was possible.
Card-engine automation remains incomplete; this release does not certify full SWU
rules support. Unauthored Saga episodes remain placeholders.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
