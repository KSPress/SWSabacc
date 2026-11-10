SWU Sabacc 0.3.0 — earned cosmetics and additional rules support.

- Added an offline cosmetic collection: 25 profile emblems, 37 cropped card backs,
  and four static scene backgrounds. Each normal-account win awards one random
  unowned item. Emblems include their matching holographic background.
- Added animated datapad profile frames and faded, flickering emblem backdrops.
  Board traces use leader/base aspects and fade to enemy colors on enemy turns.
  Performance mode freezes motion. Play mats remain a future option.
- Added a red GM toggle in Settings with a separate all-access equipment loadout.
  Returning to account mode restores earned equipment and collection.
- Added selected conditional auras/keywords, upgrade targeting, capture/rescue,
  bounty choices, Fortify attachments, Plot and combat damage before defenders.
  Fixed keyword extraction incorrectly granting conditionally mentioned keywords.
- Kept the Android package/signing key, save migration and legacy updater bridge.
  Install over the existing app to retain progress.

Validation: 90 cosmetic checks, 49 theme/inspection checks, 38 added rules checks,
24 manifest checks, zero broken scripts and a staged audit of 2,558 non-token
cards. See docs/CUSTOMIZATION_QA.md for evidence and limitations.

**Complete card automation remains unfinished:** of 2,588 cards, 1,033 have complete
compiler text coverage, 542 are partial and 1,013 remain manual. Compiler coverage
does not certify correct behavior. This release does not fulfill the every-card
automation requirement. Piloting, Support and many interactions need more work.

Android: install **swu_sabacc.apk**. Windows: extract **SWSabacc-windows.zip** and
keep SWU_Sabacc.exe with SWU_Sabacc.pck. Native builds bundle offline assets.
Legacy APK/update.json assets support older installed clients. No Android device
was attached; installation and real device upgrades remain unverified. Android
requires user confirmation to install downloaded updates.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
