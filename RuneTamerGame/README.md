# RuneTamer

RuneTamer is an original native iOS fantasy creature-collector RPG prototype. It draws on the broad genre feel of classic top-down MMORPGs and collectible-creature adventures without copying names, characters, maps, sprites, music, or other protected assets.

Included gameplay:
- Runehaven exploration hub
- touch directional controls
- roaming creature encounters
- four-skill turn-based combat
- HP-dependent Bond Rune capture mechanic
- Creature Codex and active companion switching
- player level, EXP, HP, coins and potions
- quest board and claimable rewards
- six original species: Cindrake, Mosskin, Voltwing, Aqualume, Craglet and Whispling
- pure SwiftUI/vector visuals with no external game assets

Build locally with Xcode 16+ and iOS 17+:

```bash
brew install xcodegen
cd RuneTamerGame
xcodegen generate
open RuneTamer.xcodeproj
```

The GitHub Actions workflow on the creature-rune-rpg branch builds an unsigned device IPA. Sign that IPA with your own Apple development/distribution credentials or a compatible IPA signer before installation.
