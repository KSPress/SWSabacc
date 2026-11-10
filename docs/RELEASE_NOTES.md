SWU Sabacc 0.2.0 — themes, deck identity and radial card inspection.

- Renamed the game to **SWU Sabacc** and the GitHub repository to **KSPress/SWSabacc**.
- Added Settings → Appearance with ten offline backgrounds: Deep Orbit, Violet Nebula, Hyperspace, Tatooine, Dathomir, Coruscant, Death Star, and Imperial, Republic and Outer Rim datapads.
- Deck selection now tints controls and friendly outlines using up to three unique aspects. Datapad orbital lines, scan beam and targeting rings share those deck colors. Villainy outlines are lifted to a readable graphite; printed aspect icons, damage colors and enemy warnings retain their meanings.
- Card inspection now flies the card to the screen centre, blurs the game behind it and opens four connected dossiers with profile, printed text, keyword/timing explanations and live state/support. Layout adapts to portrait, landscape and tall phones. Leader flipping and return animation are included. Performance mode uses a dim backdrop and still schematics.
- Migrates legacy save files and retains the Android package ID and signing key. Do not uninstall before upgrading. A legacy updater manifest/APK alias lets v0.1.1 clients discover this release through GitHub's repository redirect.
- Fixed landscape main-menu title/button overlap.

Validation: 58 visual/behavioral checks; 569 rules/campaign checks; 24 release-manifest checks; 9 updater-flow checks; zero broken GDScripts; 500 bot games without stalls; real mouse drag-to-play and drag-to-attack. Native packages bundle the existing 2,588-card database and 2,760 art files.

Download **swu_sabacc.apk** on Android. For Windows, extract **SWSabacc-windows.zip** and keep SWU_Sabacc.exe and SWU_Sabacc.pck together. The duplicate legacy-named APK and update.json are compatibility assets; new installs use sabacc-update.json.

This remains a foundation build: complete SWU card-ability/rules coverage is unfinished. No Android device was connected; installation, on-device rendering/touch performance and a real installed-app upgrade remain unverified. Browser card art is fetched separately and needs prior caching for offline access; native builds bundle it.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight Games. No affiliation or endorsement.
