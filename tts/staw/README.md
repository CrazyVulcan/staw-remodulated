# STAW playtest release and predictive AI

Load `STAW_Remodulated_Base_Arcs_Echo_2026_10_25.json` in Tabletop Simulator as **Attack Wing Remodulated - Base, Arcs & Echo 25 Oct 2026**. Copy it into your TTS Saves folder as a separate save. Its table preserves the player's latest local October 25 layout, all 101 physical objects and saved game state. The M5 tracker prototype and predictive AI remain included.

## October 25 base, arc and Echo fixes

Range boundaries, arc validation, modern/legacy guide lines, AI projections and Echo previews now carry the physical collider's center offset through rotation. Guide lines convert world measurements independently along X and Z for unevenly scaled bases. The 180° firing arc uses the center of the base, matching its drawn guide. These calculations follow the [TTS normalized bounds and scale API](https://api.tabletopsimulator.com/object/#getboundsnormalized).

Decorative miniatures follow the final settled base pose after manual placement, including missed pickup/drop events, interrupted long drags and an independently moved miniature. A throttled update scan recovers those cases; the follower never moves or changes the velocity of the base. During settling, the miniature is temporarily hidden and locked above the table, clear of both the base and the below-table area. Integrated bases/models remain one physical object.

The cloak bag's token now has ECHO controls on both faces. One click opens the existing GUI for side, template, and Forward/Lateral/Back placement, including reverse banks. Ship-spawned tokens retain their ship association. A manually taken token can use one unambiguous nearby friendly ship; place it closer if two bases are equally near. Opponents cannot use another ship's linked token. Existing linked tokens receive the controls on reload, and the cloak action repairs tokens from an older bag.

## Changes in this release

- Enemy selection uses allegiance and valid ships; automatic tactical movement evaluates maneuvers, firing opportunities, hazards and board edges. Manual preferences are **Get a shot**, **Close distance**, and **Open distance**.
- When moving before an unactivated target, the AI scores multiple plausible future target positions. Captain Skill and known equal-skill initiative determine whether to forecast. The forecast uses public maneuver options, geometry and completed move history; it never reads a concealed dial. Current-position checks still govern attacks, actions and Target Lock.
- Ownership transfer, shared controls during cooperative missions, ship removal, range checks and AI sector tools address the Act I playtest feedback. Movement and measurement results remain visible longer.
- Guide heights follow the playmat surface; the two-player setup helper faces correctly. Dice controls fit the player's custom tray. Generic class ship references accompany maneuver cards.
- Decorative ship models follow bases after they settle. The follower never changes the base's position or velocity, avoiding the earlier physics tugging.
- Alliance Parts I–III mission tools, interactive captain names/XP, three Talent slots, two flexible captain slots and mapped AP upgrades are included from the preceding local passes.
- Alliance captain progress from website TTS JSON exports initializes the matching captain tile's name, all five XP tracks and both expansion choices. Invalid tracker data is rejected before spawning. Exports without this optional data retain the importing player's name and default tracks.

## Editable sources and rebuilding

`src/Global.base.lua` contains the existing runtime and catalog; `src/anticipation.lua` adds predictive navigation. `src/cloak-token.lua` supplies both the embedded runtime script and the token inside the cloak bag. `src/5084a4.lua` is the tray script and `src/2a5e01.lua` is the standard-game helper. The JSON retains the other table object scripts and geometry. `release.json` records the release checksum, source paths and physical layout checksum. Layout checks exclude Lua source recursively, including objects contained in bags.

From the repository root:

```sh
npm ci
npm run check:tts
npm run test:staw
npm run build:tts
```

Build updates the included release from those Lua sources and refreshes its checksum. It refuses unexpected physical layout changes. Check verifies the release matches its sources and recorded checksum. These commands use repository-relative paths and do not require previous local output directories. Website builds and TTS builds are separate.

## Validation and limits

The offline harness compiles 112 packaged/generated Lua scripts and runs 276 behavior checks. It covers missions, movement, collision resolution, ownership, captain state and website progress imports, class references, tray controls and predictive navigation. Twelve new checks cover offset/rotated boundaries, range bands, unevenly scaled guides, 180° firing coverage, AI/Echo projections, missed events, long drags, model drops, cloak script repair, and the Echo GUI's reverse-bank/Back path. Use `node scripts/test-tts-staw.cjs --focus-base` to run those twelve checks alone. The ordinary Node suite also imports an M5 website export through this packaged runtime and checks tracker authorization, persistence and repeated-action guards.

These are Fengari/Lua 5.3 checks with mocked TTS APIs. Live TTS physics, asset loading, multiplayer behavior and tactical strength still require playtesting. Forecast coverage is a heuristic over modeled routes, not a calibrated hit probability. Captain Skill controls timing; it does not set AI intelligence.
