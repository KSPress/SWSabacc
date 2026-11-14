# SWU Sabacc 0.2.0 — November 10, 2026

Skirmish reference code was inspected in E:/SW Skirmish/app/scripts/ui/: Holo,
HoloBackground, SkTheme, InspectOverlay and InspectContent. Its orbital linework,
central card flight, screen blur and surrounding dossier layout informed this
implementation. No Skirmish game rules were imported.

## Delivered behavior

Ten saved, offline themes are exposed in Settings. The menu, collection and game
board use the selection. Datapads draw orbital rings, cross markers, circuit
traces, a scan beam and Aurebesh readouts. Space and world themes use local assets.

The selected deck provides up to three unique accents: two gameplay aspects and
an alignment when present. Repeated aspects do not produce duplicate colors.
Quick/Standard Battle selection, deck editing, campaign maps and the actual
human match configuration update the palette. Existing buttons recolor live;
datapad linework uses the same palette. Enemy/damage warnings and printed aspect
icons keep their semantic colors. Villainy decoration is lightened for contrast.

The inspector centers the card and places four scrollable, connected dossiers
around it. It includes printed text, keyword and timing explanations, live
modifiers and honest automation coverage. Portrait/tall devices stack dossiers
above/below; landscape uses both sides. The backdrop uses a 20-tap disc/radial
blur without screen mipmaps, compatible with the GL renderer. Performance mode
uses a dim backdrop and still linework. Flip, close, Escape, rotation and reverse
flight are supported.

## Verification

- Every GDScript compiles with all autoloads: zero broken scripts.
- 58 theme/inspector/migration assertions passed, producing 18 screenshots.
  Covered all ten presets, the real Settings selector, saved preference,
  unique aspect ordering, live button retinting, title/button separation,
  centered cards and non-overlapping dossiers at 540×960, 1280×720 and 480×1040,
  keyword explanation content, leader flip, base/event/upgrade inspection,
  performance mode, closure, legacy save migration and human-deck match tint.
- Rules/campaign suite: 569 passed, zero failed; 500 bot games, zero stalls.
- Release parser: 24 passed. Production updater flow: nine passed.
- Real mouse-event drag-to-play and drag-to-attack both passed.
- The exported Windows EXE launched with the Sabacc title, opened Collection
  Vault and displayed the radial inspector through real right-click input.
- Signed Android export: SWU Sabacc label, version 0.2.0/code 3, original package
  ID and signing certificate, verified resources and 16 KB alignment.
- Both manifests and APK aliases matched by SHA-256. The original v0.1.1
  ReleaseInfo parser accepted the bridge manifest as a newer update.
- The renamed browser build exported successfully (24 MB uncompressed core).

Local logs/captures are in build/qa/theme/; the latest visual captures are in
verified-shots/. Android/Windows exports are tested separately during release.
No Android device was attached, so device installation, actual touch performance
and an installed-app upgrade are not certified by these desktop checks.

## Rename compatibility

The public title, app labels, code singleton/button class, executable filenames,
browser metadata, documentation and GitHub remote use Sabacc/SWSabacc.
Actual SWU card/campaign references to kyber crystals retain their lore names.

Android deliberately retains org.fanproject.swukyber and the original signing
key/alias; changing either would prevent an in-place update. Save reads the old
filename as a fallback. Windows also checks the former game's app-data directory
once, then writes sabacc_save.json under the new application's user directory.
Old saves are retained.

New clients use sabacc-update.json and swu_sabacc.apk under KSPress/SWSabacc.
The original v0.1.1 parser only accepts its old repository URL and APK filename,
so update.json advertises the legacy URL and swu_kyber.apk aliases the same signed
binary. GitHub redirects the old repo name to the renamed repository. The release
publisher verifies that both manifests and both APK names have matching hashes.

Complete SWU rules/card ability coverage remains outside this visual change and
is still incomplete, as recorded in QA_REPORT.md.
