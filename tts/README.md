# M5 tracker prototype

Build fleets at `m5.html` (also linked from the player fleet builder). M5 ship identifiers use `M5S` followed by three digits: `M5S001` is the initial Neg'Var profile. Programs have separate stable identifiers.

The builder supports signed Captain Skill modifiers, Threat totals, slot capacity, restrictions, multiple hulls, local browser persistence, and JSON import/export. Captain Skill is initiative, not intelligence: lower CS activates first; higher CS attacks first. Threat limits are advisory. The initial physical layout supports up to three ships.

## Tabletop Simulator

Create a separate updated save from an unmodified Remodulated save:

```sh
node scripts/update-tts-m5.cjs original.json M5-Tracker.json
```

The updater refuses to overwrite files or patch an already patched save. It preserves the save's objects and state, adding the runtime and tracker hooks. Keep the original as a backup.

Load the new save, copy the website's **TTS export**, and paste it into the existing Fleet Setup importer. Import spawns one row per ship: ship card followed by installed program reference cards. Deploy the ship normally. Use its tracker for M5 planning, activation, and combat; there is no in-TTS M5 builder. The tracker checks ownership and prevents repeated activation/attacks. Navigation uses Remodulated's existing evaluator.

Lua ship state is authoritative. Moving or deleting a reference program card does not uninstall its program. The export uses the existing schemaVersion 2 fleet envelope, with source.kind `remodulated-m5` and source.m5Version 1.

## Prototype boundaries

The initial catalog contains the Neg'Var and two provisional programs, Focused Barrage and Hunter's Algorithm. These are proof implementations, not verified transcriptions of the 2024 cards. Ship art reuses the existing physical Neg'Var card; program reference tiles are placeholders. Combat is a basic primary-weapon prototype, not comprehensive card/rules automation. Live multiplayer TTS playtesting is still required.

## Verification

```sh
npm ci
npm test
npm run build
node scripts/m5-browser-qa.cjs
```

Browser QA currently uses installed Microsoft Edge. Set `STAW_M5_SAVE` to an original Remodulated save path before running tests to enable the actual-save Lua integration test; otherwise that test is skipped. It exercises real fleet parsing/import, program ordering, duplicate prevention, persisted authoritative state, tracker authorization, and repeat-action guards. Ordinary fleet imports remain supported.
