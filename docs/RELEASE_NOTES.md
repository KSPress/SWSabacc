Offline Android and Windows foundation build, with bundled card data and artwork.

- Fixed the portrait main menu so all seven buttons and the footer fit.
- Fixed a reference cycle that leaked units and attached upgrades between matches.
- Android checks GitHub Releases at startup, downloads newer APKs in the background, and validates their size and SHA-256 digest. Install from the menu prompt or Settings; Android requires installation confirmation. Offline launch and gameplay do not depend on the update server.
- Existing installs can update in place with the same package name and signing key. Save data is retained; do not uninstall first.

Validation: 569 rules/campaign checks; 24 update-manifest checks; 9 updater-flow checks; script compilation; 500 bot games across battle modes; card-by-card engine audit; portrait/landscape/tall layout screenshots; mouse drag-to-play and drag-to-attack; Windows executable launch and match setup; Android signature, alignment, permissions, and resource checks.

Known limitations: this is an early foundation build. The bundled database contains 2,588 cards, but 979 are marked fully compiled, 574 partially compiled, and 1,035 require custom ability logic. The audit checks safe engine behavior, not complete fidelity to official SWU rules. Android installation and update installation have not been tested on a physical device in this session. Android build is ARM64 only. The presentation is a work in progress.

Download `swu_kyber.apk` on Android. For Windows, extract `SWU-Kyber-windows.zip` and keep the EXE and PCK together. `update.json` is used by the Android updater.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited characters, names, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight Games. No affiliation or endorsement.
