# Aether Rift 2.1 — Reforged

An offline iPhone/iPad 5v5 MOBA by Rey Victor Mendillo. This version replaces the earlier SpriteKit presentation with a native SceneKit battlefield, animated 3D characters, and a new combat simulation. Original procedural models, map, effects, and synthesized audio are included; no third-party game assets are bundled.

## Playable systems

### Reforged improvements

- Rebuilt original character meshes with shaped armor, articulated legs, layered cloth, animated capes, fitted greaves, facial geometry, and role-specific weapon silhouettes.
- Textured lane paving, curb stones, animated river water, detailed crossings, faceted moss-covered rocks, denser brush, woodland, and objective shrines.
- Environment-lit materials, softer shadows, a closer follow camera, smoother turning and attack animations, projectile trails, hit sparks, and subtle damage shake.
- Nearby enemy portrait lock-on; closest, lowest-HP, or lowest-HP-percent targeting; optional attack approach that yields to manual movement.
- Analog joystick speed, cooldown progress rings, skill/purchase haptics, contextual turret warnings, and less cluttered turret range indicators.
- Bots retreat from unsupported turret dives; allied damage, target-mode overrides, out-of-range execute cooldowns, and dead-hero equipment healing are guarded.
- Hero preview no longer constructs the full battlefield; static terrain materials are shared before geometry batching; aiming geometry is reused until the aim changes.

### Core match

- 12 selectable heroes across Tank, Fighter, Assassin, Mage, Marksman, Support; 36 active abilities and role passives.
- One human plus four allied bots against five opposing bots; three difficulty reaction settings and practice mode.
- Three lanes, 18 sequentially protected turrets, two bases, minion waves and super minions.
- Eight jungle camps, Azure/Ember buffs, a team-reward Sentinel, and a Colossus that sends a siege unit down a lane.
- Levels 1–15; manual skill upgrades, ultimate gates at 4/8/12, mana, cooldowns, shields, stuns, slows, dashes and skill shots.
- 24 equipment items, six inventory slots, component upgrades, selling, quick-buy, physical/magic defense, penetration, crit, lifesteal and haste.
- Brush concealment and team vision; minimap camera inspection and pings; recall, regeneration, Flicker, Sprint, Purify, Retribution.
- Fountain healing, deaths/respawns, assists, scoreboards, match results, synthesized music/SFX, and a companion fox.
- Full-screen landscape layout, adaptive HUD, settings pause and background pause.

## Build and install

The existing `aether-rift-moba` branch workflow builds the IPA with Xcode on a GitHub macOS runner. It parses all Swift sources, runs standalone combat/control regression checks and a bot match through victory (up to 25 simulated minutes), compiles for a physical iPhone, then runs simulator launch/interaction tests and captures screenshots.

The resulting `AetherRift-3D-5v5-unsigned.ipa` needs signing with the user's own eligible certificate/profile (for example, in Feather). No certificate or provisioning profile is included. This is an offline prototype, with stylized procedural 3D assets and original balance values. It is not production-equivalent to Mobile Legends and does not implement online matchmaking, ranked servers, its full roster, animation library, skins, or photorealistic art.

Source: `AetherRift/Sources3D/`. Earlier 2D source is retained in `Sources/` for reference and excluded from the active app target.
