# Aether Rift

Aether Rift is an original native iOS MOBA prototype built with SwiftUI + SpriteKit. It intentionally does not copy Mobile Legends hero names, artwork, maps, logos, audio, or exact skill text.

## Included gameplay

- Six roles: Tank, Fighter, Assassin, Mage, Marksman, Support
- Four active skills per role plus basic attacks
- Touch joystick and skill buttons
- Mana, health, shielding, cooldowns, burst and sustained damage
- Dashes, projectiles, AoE attacks, healing, buffs and crowd control
- Enemy hero AI
- Minion waves and lane combat
- Ally/enemy towers with automatic targeting
- Hero death + respawn
- Kill score and victory/defeat state
- Landscape iPhone/iPad support
- Procedural visuals; no third-party game art required

## Build

The GitHub Actions workflow on branch `aether-rift-moba` builds `AetherRift-unsigned.ipa`. The IPA has no embedded provisioning profile or certificate and must be signed for the target device before installation.

Project source is under `AetherRift/` and uses XcodeGen to create `AetherRift.xcodeproj`.
