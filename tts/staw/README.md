# STAW playtest release and predictive AI

Load `STAW_Remodulated_AI_Anticipation_2026_10_19.json` in Tabletop Simulator. Copy it into your TTS Saves folder as a separate save. Its table is the player's returned refined layout, including the custom dice tray and all 101 physical objects. The M5 tracker prototype remains included.

## Changes in this release

- Enemy selection uses allegiance and valid ships; automatic tactical movement evaluates maneuvers, firing opportunities, hazards and board edges. Manual preferences are **Get a shot**, **Close distance**, and **Open distance**.
- When moving before an unactivated target, the AI scores multiple plausible future target positions. Captain Skill and known equal-skill initiative determine whether to forecast. The forecast uses public maneuver options, geometry and completed move history; it never reads a concealed dial. Current-position checks still govern attacks, actions and Target Lock.
- Ownership transfer, shared controls during cooperative missions, ship removal, range checks and AI sector tools address the Act I playtest feedback. Movement and measurement results remain visible longer.
- Guide heights follow the playmat surface; the two-player setup helper faces correctly. Dice controls fit the player's custom tray. Generic class ship references accompany maneuver cards.
- Decorative ship models follow bases after they settle. The follower never changes the base's position or velocity, avoiding the earlier physics tugging.
- Alliance Parts I–III mission tools, interactive captain names/XP, three Talent slots, two flexible captain slots and mapped AP upgrades are included from the preceding local passes.

## Editable sources and rebuilding

`src/Global.base.lua` contains the existing runtime and catalog; `src/anticipation.lua` adds predictive navigation. `src/5084a4.lua` is the tray script and `src/2a5e01.lua` is the standard-game helper. The JSON retains the other original table object scripts and geometry. `release.json` records the release checksum, source paths and physical layout checksum.

From the repository root:

```sh
npm ci
npm run check:tts
npm run test:staw
npm run build:tts
```

Build updates the included release from those Lua sources and refreshes its checksum. It refuses unexpected physical layout changes. Check verifies the release matches its sources and recorded checksum. These commands use repository-relative paths and do not require previous local output directories. Website builds and TTS builds are separate.

## Validation and limits

The offline harness compiles 110 packaged/generated Lua scripts and runs 262 behavior checks. It covers missions, movement, collision resolution, ownership, captain state, class references, tray controls and predictive navigation. The ordinary Node suite also imports an M5 website export through this packaged runtime and checks tracker authorization, persistence and repeated-action guards.

These are Fengari/Lua 5.3 checks with mocked TTS APIs. Live TTS physics, asset loading, multiplayer behavior and tactical strength still require playtesting. Forecast coverage is a heuristic over modeled routes, not a calibrated hit probability. Captain Skill controls timing; it does not set AI intelligence.
