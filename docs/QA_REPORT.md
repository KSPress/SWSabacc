# Offline build verification — November 9, 2026

Godot 4.7.2, Windows host; release version 0.1.1, Android version code 2.

## Findings and fixes

- Portrait main menu: seven buttons overflowed the window and overlapped the footer. Layout now reserves the complete button grid and footer before fitting decorative cards. Verified at 540×960, 1280×720, and 480×1040.
- Match memory: strong references in both directions between units and attached upgrades caused persistent RefCounted cycles. Upgrade-to-host references are now weak. The original rules suite leaked 1,532 objects; the original card audit leaked 10,457. Both repeated runs now exit without those warnings. Regression tests verify live host access and release of units/tokens after a match.
- Android updates: added a release manifest validator and nonblocking updater. Newer APKs download to a partial file, must match the expected length and SHA-256, then move to the installable cache. Updates use the existing package name and signing key. Install offers are deferred until the main menu; Settings permits manual checks and install. Android confirms installation. No phone is required for offline gameplay after installation.
- Packaging: rebuilt Android and Windows, included the native card data/art, and restored the themed icon missing from Godot's exported APK. Export scripts now generate the matching updater manifest and verify Android identity, version, permissions, signature, alignment, and resources.

## Completed checks

| Check | Result |
|---|---|
| All GDScript compilation with autoloads | 0 broken scripts |
| Rules, campaign, format, AI, attachment lifetime | 569 passed, 0 failed |
| Bot battle modes | 500 games, 0 stuck (one draw in quick-space simulation) |
| Campaign validator and simulations | Passed within the rules suite |
| Update manifest validation | 24 passed, 0 failed |
| Production updater completion/failure paths | 9 passed, 0 failed |
| Card-by-card engine audit | 2,558 non-token cards exercised; 2,554 clean; four unmet-condition flags |
| Screen captures | 41 captures across portrait, landscape, tall phone, deck editor/picker, collection, campaign and match screens |
| Mouse input events | Drag-to-play PASS; drag-to-attack PASS |
| Exported Windows EXE | Launched, displayed bundled artwork, entered Quick Battle, kept opening hand |
| APK bundled resources | 2,760 card-art files, card database, nonempty project settings, themed icon; no test scripts |
| APK signing | v2 and v3 verified; certificate matches the previous APK |
| APK alignment/resources | 16 KB alignment verified; aapt2 resource inspection passed |
| APK identity | org.fanproject.swukyber; version 0.1.1/code 2; ARM64 |
| APK permissions | INTERNET and REQUEST_INSTALL_PACKAGES |

Detailed logs, audit JSON and PNGs are local under `build/qa/` (not committed).
The headless and screenshot tests used an isolated APPDATA under that directory
to protect existing progress. The exported Windows UI was also exercised directly.

## Material limits

This is a playable foundation, not a complete digital implementation of SWU.
The bundled database has 2,588 cards: importer status is 979 full, 574 partial,
1,035 manual. The 30 token cards are excluded from the 2,558-card engine audit.
These labels describe compiler coverage, not independent confirmation that every
rule interaction is correct. Partly automated or manual abilities can fail to
perform their printed text. Latest official card-database completeness, format
rotation/ban lists and complete official rules fidelity have not been certified.

The four audit flags are ASH_110, JTL_128, SEC_007 and SOR_125: the staged board
cannot meet their effect conditions or extra costs. No runtime script errors,
stalls or invariant violations appeared in the repeated audit. This does not
turn unimplemented text into supported behavior.

No Android device was connected. APK install, Android rendering/touch performance,
rotation on hardware, save persistence across a real APK upgrade, and the native
installer handoff remain unverified on a device. The updater's parser, checksum,
truncation/tampering rejection, cache promotion, same-version and offline-failure
logic were tested locally; a genuine older-to-newer installed APK update still
needs device testing. The existing 0.1.0 app has no updater, so its first upgrade
to this build is manual.

The UI is usable but still needs further art direction, animation, audio, input,
accessibility and device performance work to reach the requested Hearthstone
level of polish. Existing simplified battle modes and the roguelike campaign
remain separate from traditional Standard Battle.
