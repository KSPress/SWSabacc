SWU Sabacc 0.7.0 — title, customization and character audio.

- Added main-menu Exit and Customization entries and the supplied Sabacc title.
- Polished cosmetic tiles, grey locked previews, equipped/unlocked sorting and
  live datapad/emblem background previews. Selection preserves scroll position.
- Replaced the GM button with a large red slider: normal progression on the
  left, everything unlocked on the right, while preserving earned cosmetics.
- Imported 52 sound clips and six quietly shuffled background music tracks.
  Settings control music enable/volume and current sound-effect volume.
- PLAYED clips accompany entry. DIE/LOSE clips share death/losing-leader cues.
  Unlabeled character clips accompany attacks and activated abilities.
- Wilhelm rolls at 5% only for ground non-Creature, non-Vehicle units. All
  Vehicles have a 5% Minecraft/Creeper death explosion chance.
- Added TIE entry/shooting, combat sound categories, Villainy victory siren and
  Heroism victory Cantina cues, with temporary soundtrack ducking.

Validation: 117 presentation/audio assertions, 42 touch checks, 114 responsive
checks over eight ratios/152 screen states, 75 cinematic checks and 24 manifest
checks passed. Native Exit and chunked browser startup/navigation were verified.
Zero broken scripts. See docs/PRESENTATION_AUDIO_QA.md for evidence and limitations.

The user confirmed the earlier Windows menu was working again.

Android: swu_sabacc.apk. Windows: extract SWSabacc-windows.zip and keep the EXE/PCK
together. The existing Android signing identity, saves and legacy update bridge
are retained. No physical Android installation/touch-performance test was possible.
Card-engine automation remains incomplete; this release does not certify full SWU
rules support. Unauthored Saga episodes remain placeholders.

Unofficial, non-commercial fan project. Star Wars and Star Wars: Unlimited
characters, card text and artwork belong to Lucasfilm Ltd. and Fantasy Flight
Games. No affiliation or endorsement.
