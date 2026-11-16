# hub2 pipe routing: no loose ends

2026-11-15. Grilled (6 questions), then built. Replaces the pipe part of `docs/specs/hub2-storage.md` item 9.

Ask: every pipe on hub2 connects to something or goes into a wall, none just stops in the air; pipes go
around corners.

## What was wrong

`tools/gen_hub2_dressing.gd` `_pipes()` put one straight bundle on each concave wall/ceiling crease and pulled
every pipe up to 1 m back from both ends of its crease (`length_trim`), so every run stopped in mid-air short
of its corner. 4 % were `snapped` on purpose (a jagged stub). Nothing ever turned a corner.

## Decisions

1. **Routes, not segments.** A route starts on a wall/ceiling crease and walks along it in both directions,
   following the walls from crease to crease (about 2-5 creases), until it ends. Same overall pipe coverage
   as before, in fewer, longer routes. Bundles stay 1-4 pipes (0.15-0.6 m), one service colour per route
   (other pipes in the bundle 40 % odd colour, as before).
2. **Inside corners** (the wall ahead): the bundle turns the corner with elbows and carries on along the next
   wall, keeping its stack order (a horizontal bundle is stacked down the wall, so every pipe turns at its
   own offset; bend radius 1.5 x its radius, so thin pipes bend tighter). It only turns when the next wall
   is clear for at least 4 m and the route still has turns left. Otherwise it runs **straight into the
   wall ahead**, with a square wall sleeve/flange plate where it goes in.
3. **Outside corners** (the wall it hangs on ends: corridor mouth, pillar, door edge): the bundle **wraps
   around** the edge and follows the new wall. If it can't (new wall too short, blocked, a lower ceiling),
   it **elbows into the wall it was on** just before the edge, with a sleeve.
4. **Vertical drops** in wall-wall inside corners: the top **tees** into a ceiling bundle that turns in
   that corner (lined up with that bundle's lowest pipe, collar at the joint); if none, it goes **up into
   the ceiling** with a sleeve. The bottom goes **into the floor** with a round floor flange.
5. **No snapped pipes.** The `snapped` option is removed from `Hub2PipeRun`. Sagging spans stay (both
   ends still connected); they now dip downward, not toward the room.
6. **Scope:** B, C, the halls, and now **Room A** (floor -273): its ceiling creases (ceiling -164/-173),
   kept clear of the shaft mouth and the landing strip around (0, -273, -190).
7. **Also blocked by:** props with collision, crane meshes (cranes have no collision, so their visual mesh
   is used for the check), and pipes already placed. A blocked route elbows into its wall before the blocker.
8. **Check:** the tool refuses to save if any pipe end is not inside/at a map surface (wall, ceiling,
   floor) or on a tee; a test checks every pipe end is capped (WALL or TEE) and every tee sits on another
   pipe.

## Build notes

- `tools/gen_hub2_pipes.gd` (new) rewrites only the `Pipes` group of `scenes/hub2_dressing_src.tscn` (a
  top-level group, so the dressing generator leaves it alone); the logic is `tools/hub2_pipe_router.gd`.
  Then bake (`tools/bake_hub2_dressing.gd`) through `tools/godot_bg.ps1`.
- `gen_hub2_dressing.gd` no longer builds pipes (old `Halls/Pipes` and its sag vines are removed by the pipe
  tool). A future re-run of the dressing generator reshuffles hall lamps/kit (its random stream no longer
  passes through the pipe pass); re-run the pipe tool after it.
- `Hub2PipeRun`: per-segment `mount_dirs`, chamfered elbows at every bend, `end_a`/`end_b` (OPEN, WALL, TEE)
  with `end_a_normal`/`end_b_normal` (WALL: the surface normal; TEE: the host pipe's direction) and
  `tee_radius`, `view_range` (A's ceiling pipes are ~100 m up).

## Built

2026-11-15. `tools/gen_hub2_pipes.gd` (headless, ~1 s routing) then the bake through `tools/godot_bg.ps1`.
Result: 290 old straight runs (and 4 sag vines) removed; 52 routes / 109 pipes: 48 inside turns, 29
outside wraps, 14 drops teed into bends, 2 drops into the ceiling; ~2.3 km outside A (old: 2.3 km), ~2.2 km
in A. Room A's wall/ceiling joints are mesh SEAMS (the ceiling slab cuts into the walls), so seam lines seed
routes there only. Wall-wall drop corners: most vertical creases aren't clean 90 degree corners (61
rejected), so drops are few. Probe-shot; tests `test_a_pipe_sags_and_bends_round_corners_with_capped_ends`,
`test_every_pipe_end_goes_into_a_surface_or_another_pipe`. Not played.
