# SWU Sabacc 0.6.0 cinematic presentation validation

The supplied Force and Initiative sheets are imported by
`tools/import_sabacc_tokens.py`. Each face is cropped by alpha bounds,
contained in a 400 by 550 transparent canvas and saved as lossless WebP in
the ignored `game/ip/ui/tokens/` folder. Originals are unchanged. Crop records:
`build/qa/cinematic/token_import.json`.

Initiative transfer flips between the custom front and back. Force gain turns
the card face up; spending turns it over before it disappears. Match refresh
also reconciles Force markers with initial scenario state. Existing engine
ownership and claim rules remain authoritative.

Combat classification prioritizes ships, then ground Force traits. Force
characters use red sabers for Villainy, green for Heroism with Command/Cunning,
blue for other Heroism and yellow for neutral Force. Blaster allegiance chooses
green, red or yellow, with Villainy taking precedence on mixed allegiance.
Melee adds directional windup and curved contact trails. Rounded compact bolts
and target flashes replace long rectangular projectile trails.

All 25 emblem IDs have separate line geometry: wings, senate orbits, imperial
gears/scanners, hex networks, Sabacc outlines, targeting reticles, signal ribs,
eclipses, diamonds, crossing blades, block frames, horizon grids, chevrons,
slashes, ECG traces, shields, circuits, embers and twin columns. The field uses
the selected emblem palette. Existing noise flicker, input tilt and performance
mode remain active. Default datapad turn-color blending remains intact.

Inspector colors and icons come from the inspected card. Anatomy distinguishes
leader deployment thresholds from resource payment and upgrade HP modifiers
from unit health. Four dossiers retain scrolling and open readable expanded
panels above the inspector. Referenced keywords are explained without granting
them to the card. Expansion reconstructs aspect icons explicitly because native
node duplication resets their non-exported aspect property.

## Executed checks

- `cinematic_tests.tscn`: 75 checks, zero failures. Four texture dimensions;
  allegiance/trait attack classification; token gain/spend/claim; 25 distinct
  field screenshots; six inspector ratios and expanded aspect preservation;
  five real-match attack animation sequences.
- `polish_tests.tscn` bounds sweep: 114 checks, zero failures and zero detected
  button layout issues in 152 screen states at 360x640, 540x1200, 768x1024,
  1024x768, 1280x720, 1920x1080, 2560x1080 and 960x540.
- `compile_all.tscn`: zero broken scripts.
- Update manifest tests: 24 passed, zero failures.
- Signed Android release export completed with version name 0.6.0/code 7.

Logs and screenshots are local under `build/qa/cinematic/`, including
`final-tests.log`, `final-shots/`, `layout.log`, `layout/`, `final-compile.log`,
`update-tests.log` and platform build logs. Rendered saber and impact frames,
token faces and expanded inspector panels were visually reviewed.

No physical Android device was available for installation, gesture or thermal
performance testing. Screenshot uniqueness establishes separate geometry, not
subjective visual quality. Responsive checks detect button bounds/overlap and
are supplemented by inspector/card bounds assertions. These UI tests do not
certify every card rule: 1,060 cards have complete compiler text coverage,
544 partial and 984 manual; coverage alone is not correctness.
