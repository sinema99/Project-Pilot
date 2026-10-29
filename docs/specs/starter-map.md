# Spec: Starter map - the new first mission

> **Status:** specced and built 2026-10-26. See docs/worklog/2026-10-26.md. Not yet played.
> **New:** `assets/starter_map.glb`, `scenes/starter_map.tscn` (root `StarterMap`),
> `Starter_Map.tscn` (root wrapper), `scripts/mission_map.gd` (`MissionMap`),
> `tests/test_starter_map.gd`.

## The ask

"i want to create a new scene. i just exported a new glb, starter_map, i want it to replace ichi
as our first map/mission."

## Decisions (grilled 2026-10-26)

| # | Question | Answer |
|---|---|---|
| 1 | Replace Ichi's ground, or the whole mission? | A **fresh mission**. None of Ichi's opening (blizzard, parked ship, tredge, snow shelter). Ichi's files stay, untouched |
| 2 | How do you get in? | Its own scene + root wrapper `Starter_Map.tscn` (like `Ichi.tscn`). `trial.tscn` stays the main scene; not chained to `Intro_Movie` |
| 3 | Sky / weather | Trial's: cel sky, sun, fog, PixelWorld/PixelLook/RetroLook. Clear, no storm |
| 4 | Scale | 1 Blender unit = 1 m, imported at 1.0. Knowingly past the 150 x 150 m / 40-50 m cap |
| 5 | The 2 m pilot-reference cube | User renames it `pilot_ref-noimp` in Blender; Godot's import hint skips it, no code |
| 6 | Spawn | An empty named `spawn` in the .blend; no empty = origin facing +Z |
| 7 | Falling off | Kill height (export, default y -30) -> back on the spawn, velocity zeroed. No fade, no checkpoints |
| 8 | What else comes in | pilot9 only, stock mesh, all his settings toggles. No EXIA, second pilot or test props |
| 9 | Shading | `ApplyCelGround` (`cel_ground.tres`) on the whole map |
| 10 | Where the GLB lives | Blender exports straight to `Project_Pilot/assets/starter_map.glb` from now on |
| 11 | Name | Working name `starter_map` until the mission has one |

## The asset (first export, 2026-10-26)

`C:\Users\panac\Documents\starter_map.glb` (copied once) -> `assets/starter_map.glb`, import script
`scripts/map_import.gd` (trimesh collision solid from both sides, double-sided materials). 7
meshes, no materials. With object transforms applied:

| Object | World size |
|---|---|
| `Plane` (ground) | ~355 x 233 m at y 0 |
| `Cube.001` (501 verts) | ~360 x 229 x 228 m, y -82 to +147, centred 54 m down +Z |
| 4x `Cylinder` | ~17 m thick, ~318 m long, tilted 50 deg about X, at x ~+-102 / +-123 |
| `Cube` | 2 m pilot-height reference at the origin (to become `pilot_ref-noimp`) |

## Spawn and respawn - `MissionMap`

The root script, written to be reused by later mission scenes. Exports: `map`, `pilot`,
`spawn_name` (`"spawn"`), `kill_height` (-30), `spawn_lift` (0.1 m).

- `_ready()` and any physics frame with the pilot below `kill_height` call `respawn()`.
- `respawn()` finds `spawn_name` anywhere under `map`, puts his feet `spawn_lift` above it, zeroes
  velocity, and turns `character` to the empty's forward with `CameraPivot` behind him. The
  pilot9 root is never rotated (pilot9.gd treats character yaw as world yaw; CameraPivot is
  top_level - see docs/specs/ichi-parked-ship.md).
- **Facing:** the empty's Godot -Z, which is its **Blender +Y**. In Blender, rotate the empty so
  its local Y arrow points where he should look (a Plain Axes empty shows it).
- If any playable space ends up below y -30, lower `kill_height` on `StarterMap`.

## Re-export workflow

1. Export from Blender to `Project_Pilot/assets/starter_map.glb` (glTF binary, +Y up).
2. Focus the editor: it reimports. If the map looks stale, delete
   `.godot/imported/starter_map.glb-*` and refocus.
3. `tests/test_starter_map.gd` checks every mesh got collision and that no `pilot_ref*` node came
   through.

## Not done (deliberately)

Checkpoints, a fade on respawn, the intro-to-mission handoff, EXIA, per-object tints, a mission
name. Each is its own spec when wanted.
