# SWU Sabacc 0.7.0 menu and audio validation

## Menu and customization

The main menu uses the supplied Sabacc title artwork, alpha-cropped without
altering the original. Eight entries include Customization and Exit. Native
Exit closes the application; browser Exit explains that the tab must be closed.
The existing Profile shortcut remains available.

Cosmetic tiles show equipped, unlocked and locked states. Equipped items sort
first, followed by other unlocked items, then locked items. Locked previews use
a grey shader rather than simply disappearing into the background. Emblem and
datapad backgrounds have animated previews, scenes show their supplied images,
and card backs retain their proper aspect ratio. Selection preserves scroll
position. Touch scrolling and swipe cancellation remain active.

The settings GM control is a large two-position red slider with a 56px thumb.
Left restores normal progression; right grants GM access without writing new
earned cosmetics. Scroll-wheel movement cannot toggle it. Touch scrolling gives
sliders ownership of their gestures rather than capturing horizontal drags.

## Supplied audio rules

`tools/import_presentation.py` imports all 52 supplied sound clips and six music
tracks into ignored `game/ip/audio/`, with a generated catalogue. Raw Sounds and
MUSIC folders are ignored by Git and Godot; originals are unchanged. Every clip
has an assignment. Named folder aliases include Ben/Obi-Wan and Din Djarin.

- PLAYED clips: when the matching unit enters the board, including leader
  deployment and token entry. TIE-family cards/tokens use the TIE fly-by clip.
- DIE and LOSE labels share one character pool. It is used for a defeated
  character and for the losing leader at match end.
- Unlabeled named-character clips: randomly selected on that unit/leader's
  attacks and activated abilities. They are excluded from PLAYED pools.
- Wilhelm: a fresh roll below 0.05 only for defeated ground units that have
  neither Creature nor Vehicle traits. Space units, upgrades and bases do not
  qualify. The rare clip replaces the character's normal death voice.
- Minecraft/Creeper explosions: a fresh roll below 0.05 for any defeated Vehicle,
  in either arena. Normal vehicle deaths use the standard blast when no named
  death voice applies. The rare pool is not used for ordinary attack impacts.
- TIE shooting uses the supplied TIE cannon/fire clips. Clone, walker, heavy
  vehicle, Boba, blaster, melee and saber sounds use their mapped categories.
- Match victory: Imperial Siren for a Villainy winner, Cantina for Heroism.
  The losing leader's voice uses a separate player, so it can accompany the cue.
  Draws do not trigger either side's victory clips.

Music uses a shuffled bag of six tracks. Every track plays before the bag is
refilled, with no immediate repeat across the boundary. It continues between
screens, quietly attenuated by 24dB in addition to the user's music volume.
Settings provide music enable/mute, music volume and sound-effect volume.
Volume changes affect current playback. Victory cues temporarily duck music.
Voice/result players are separate from the effect pool so bolt volleys cannot
steal a character line or victory cue. Imported clips retain their original pitch.

## Executed checks

Local logs and captures are under `build/qa/audio/`:

- `presentation-final.log`: 117 checks, zero failures, plus an actual pointer
  click on native Exit that terminates the test process successfully. Includes
  decoding every audio resource, label mapping, probability boundaries, arena/
  trait exclusions, TIE cues, both victory cues, music shuffle and mute, touch
  dragging GM both ways, earned-collection preservation, locked previews, title
  artwork and Customization navigation.
- `visual-final.log` and `visual/`: rendered menu, settings, grey locked emblems
  and animated background preview checks in portrait/landscape; 117 passed.
- `touch-final.log`: all 42 existing customization touch checks pass.
- `layout-final.log`: 114 checks across eight ratios/152 screen states, zero
  detected button bounds or overlap issues.
- `cinematic.log`: 75 existing combat/token/emblem/inspector checks pass.
- `compile-final.log`: zero broken scripts. `update.log`: 24 manifest checks pass.
- Browser build: four data chunks reconstruct the 50.7MB resource pack, each
  beneath the hosting file-size limit. All chunks participate in the offline
  service-worker cache. Local browser startup, Customization navigation and Exit
  message were verified with no browser warning/error logs.

Android uses version 0.7.0/code 10 and the existing signing/package identity.
Export scripts verify signature, alignment, version and update metadata. Physical
Android installation and real-device audio levels/gesture performance remain
untested. Automated audio tests mute the output bus while exercising decoding
and playback; they do not certify subjective loudness on every speaker.
The user subsequently confirmed that the earlier Windows menu issue was working.
Card rules and automation coverage are unchanged; this is not full rules certification.
