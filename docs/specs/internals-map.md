# Spec: Internals - map 1 greybox

> **Status:** grilled 2026-10-28, plan v2 drawn (longer route), **built 2026-10-28**. Not yet played.
> **Plan:** `docs/specs/internals-plan.html` (published as a private artifact). Its `P` / `R` /
> `MARK` tables are the layout the builder reads: change the plan, then build from it.

## The ask

A Dark Souls / metroidvania first map in the industrial internals of the megacity. Blockout only:
rooms, halls, corridors, elevation. Top-down plan first, user edits, then a greybox to run around in.

## Decisions (grilled 2026-10-28)

| # | Question | Answer |
|---|---|---|
| 1 | Map #1 per game-overview? | Yes: 150 x 150 m, ~50 m vertical, chase-boss finale (route only this pass). `starter_map` stays on disk untouched |
| 1b | EXIA? | **Left out.** Pilot hasn't found the mech yet. pilot9 only, fully indoors |
| 2 | Vertical direction | **The whole mission descends**: the end is lower than the start |
| 3 | Double jump | Found ~75% through; required to progress; a short climb back up after it pays off the locked ledges; DJ gaps at the end |
| 4/12 | Zones | (v2) 1 Service Hatch, 2 Fan Hall, 3 Vent Stack, 4 Control Block, 5 Turbine Hall, 6 Coolant Galleries, 7 Undercroft, 8 Capacitor Vault (DJ), 9 Return climb, 10 Press Shaft |
| 5 | Dying | `kill*` volumes in every pit/shaft floor + global kill height backstop. 3 rest pads (Control Block, Capacitor Vault, Press Shaft top), touch to save, respawn at the last one. No moving press this pass |
| 6 | Medium | **Godot**, not Blender |
| 7 | Editability | One-shot builder `tools/gen_internals_blockout.gd` writes `scenes/internals.tscn` as owned CSG nodes (CSGBox3D, `use_collision`), grouped per zone, rooms as CSGCombiner3D shells with drag-able door cutouts. Nothing regenerates over hand edits |
| 8 | Plan form | Interactive page: plan view with height layers, unrolled section, route overlay, piece schedule with ids |
| 9-11 | Moves | Always on: walk, run, sprint, jump, crouch, slide, mantle, vault. Off: wall-run, wall climb, dash, rail grind. Double jump (`air_jumps`) starts 0, the pickup sets 1. Overrides live on this scene's pilot9 only |
| 10 | Breaker / power-on | Considered, **dropped** (Q12): the DJ climb back is the payoff |
| 13 | Look | Fully enclosed, roof over everything, light slots from above as landmarks; dark local ambient + ~12 OmniLights, one colour per zone; cel shader, LOOK toggles still work |
| 14 | Entry | `scenes/internals.tscn` (root `Internals`, a `MissionMap`) + `Internals.tscn` wrapper; trial stays main. Debug: F1-F3 teleport to rest pads, F12 toggles double jump (check keys are free first) |

## Design numbers

Before DJ: ledges <= 4 m (hard 4.9), gaps <= 7 m (hard 9). DJ gates: 5.5-6 m ledges, 10-12 m gaps.
Teases: 12 m+ gaps / 15 m+ heights, closed this mission. Source: game-overview "the grid".

## Open

- Route length: v1 was ~725 m. **v2 (user: "lengthen the route")** adds the Fan Hall (new zone 2,
  the empty north strip), a Control Block detour (shutter + floor duct), a Coolant switchback + service
  crawl, the **Undercroft** (new zone 7: catwalks along the Turbine Hall floor at +10, under the
  turbines) and a longer exit tunnel. Now 10 zones, **1228 m** flat, ~5 min of pure running; double
  jump at 69% of the route. A 12-15 min first run depends on platforming pace and deaths, unknown
  until played. The 150 m footprint is nearly full: more length means more vertical laps or a
  bigger footprint.
- Overview says 3 chests per map: placed as markers only.

## Built (2026-10-28)

Open `Internals.tscn` (or `scenes/internals.tscn`) and play.

**Files.** `tools/gen_internals_blockout.gd` (the one-shot builder: reads the `P`, `D`, `R`, `MARK`
tables out of `internals-plan.html`, refuses to overwrite `scenes/internals.tscn` without `-- --force`),
`scenes/internals.tscn` (root `Internals`, a `MissionMap`), `Internals.tscn` wrapper,
`resources/internals/*.tres` (cel tones: shell, floor, solid, gate, chest; glow materials),
`scripts/mission/` (`KillVolume`, `RestPad`, `AbilityPickup`, `OneWayGate`, `ExitVolume`,
`MissionHud`), `tests/test_internals.gd`, `tests/_probe_internals_route.gd`,
`tests/_probe_internals_shots.gd`. `MissionMap` gained `checkpoint` / `set_checkpoint()` /
`MissionMap.of()`; the starter map is unaffected (no checkpoint = the spawn, as before).

**How the scene is laid out for editing.** `Map/Shell` is one CSGCombiner3D (collision on):
`Walls_Zxx` (enclosures grown 1 m) union, `Air_Zxx` (enclosures shrunk 0.5 m, so touching spaces
keep a 1 m wall) subtract, `Nested_*` (the valve room inside the pump gallery), then `Doors`
subtract. Move a door = move its box under `Shell/Doors`. Floors, blocks, kill volumes and
lights sit under `Map/Zxx_<Zone>`; markers (rest pads, pickup, chests, exit) under `Map/Markers`.
Every floor and block has its plan id painted on top (fades past 40 m) so feedback can name it.

**HUD + debug.** Run clock top left, event line (rest saved, double jump, shortcut opened,
`EXIT - m:ss` stops the clock). F1-F3 = go to rest pad 1-3 and save it, F12 = double jump on/off.

**Departures from the plan / grilling.**
- Low ducts (Control Block floor duct, slide pipe) have **2.2 m** roofs, not 1.2: pilot9's crouch
  doesn't appear to shrink his collision capsule, so 1.2 m would wall him off. The floor duct is at
  +30 (the plan drew +27 with a drop hatch) so it's a plain low corridor between the two rooms.
- Added a door table `D` to the plan (37 openings, 3 one-way: shutter, shortcut door, riser door).
  `NK` (chest 2 alcove), and the two teases became small rooms so they have walls.
- `G1` widened to x 116 to meet the Turbine Hall door (the plan left a 4 m hole); chest 1 moved
  off the route; one route node re-pointed round a corridor corner.
- No light slots in the roof (there is no sky inside); each zone is lit by OmniLights in its own
  colour instead (amber control block, blue turbine hall, green coolant, red press shaft...).
  Ambient (0.34, 0.37, 0.42), dark fog. CSG isn't a MeshInstance3D, so ApplyCelGround / RetroLook
  floor lines don't touch it: the cel tone is set as the CSG material directly.
- The in-game ABILITIES menu can still turn moves back on for a session.

**Verified.** `_probe_internals_route.gd`: the pilot settles on the spawn; all 87 route nodes have
ground under them and 2.1 m of headroom; every same-height hop between nodes is clear at waist
height (the riser's one-way gate blocks, as it should from the hall side). Suite: test_internals
passes; the only failures (2 checks, test_ichi_parked_ship) are in a test that shares no code
with this work. Probe screenshots read: walls, floors, blocks and the Overlook window all as
planned. **Not checked:** that each jump is makeable at the intended speed - that's play.
