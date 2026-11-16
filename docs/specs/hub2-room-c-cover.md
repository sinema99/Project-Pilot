# hub2 room C: crane column fix + enemy cover

2026-11-15. Grilled with the user (6 questions). Builds on [hub2-storage.md](hub2-storage.md). BUILT same day.

Ask: room C (the small dock hall, x 69..113, z -136..-80, floor ~31, ceiling 47) needs work. The crane's mounts clip
through the ramp. The room will be where enemies spawn, so add cover (barricades, stacked boxes).

## Decisions

1. **Room.** C, the dock hall. Not A (the user corrected this; A is the huge storage hall, C is much smaller).
2. **Crane fix.** C's `BridgeCrane` (scenes/hub2_dressing_src.tscn, origin (90.75, 30.95, -111), span 37.5,
   runway 47, column pitch 11.75) stands on columns at x = 72 and 109.5. The south end pair (z ~ -87.5) sits where
   the south dock ledge and the ramp begin (z -87..-82).
   - `Hub2Crane` gains a skip-columns setting (e.g. `skip_column_zs`). Skipped columns get no mesh and no collision.
   - The generator/build ray-checks every column footprint against hub2.glb and skips only the ones that hit the map.
   - Girder, rails and bridge stay as they are; the runway rests on the last clear column. Other cranes untouched.
3. **Cover goes in a new `C/Cover` group.** C is NOT regenerated, so anything hand-edited in C survives.
4. **Mix:** low barricades, stacked crates and pallets, a few full-height pieces.
   - Low: concrete jersey barriers (the main type, ~1.1 m high, grimy, some with faded yellow/black hazard stripes, runs of
     2-3 end to end) plus a few welded steel plate shields, tilted slightly. ~1.1 m, vaultable. No sandbags.
   - Crates/pallets: 1-2 high, in piles.
   - Full height: 2-3 containers or tall crate stacks to break long sightlines.
5. **Density.** 8-10 clusters of 2-4 pieces: ~5 low runs, 3-4 crate piles, 2-3 full-height. No sightline longer than
   ~20 m. A 4 m lane stays open through the middle; the ramp foot and the entrance stay clear.
6. **Style.** Code-built PS1 props like the other hub2 dressing (vertex colour, flat normals, worn). All solid with box
   collision. New jersey barrier / plate shield kinds are added to the prop kit.
7. **No spawn markers, no spawner, no AI.** The user places enemy spawns by hand.

## Engineering notes (not grilled)

- Every piece is ray-checked: clear of the map, of existing C dressing, of the lane, ramp foot and entrance.
- Seeded and deterministic, like the rest of the generator output.
- Tests: no Cover piece overlaps map or other props, lane and ramp foot clear, skipped columns have no collision,
  existing hub2 tests stay green.
- Probe shots: the crane columns near the ramp, and a view across the room from the entrance.
- Window bake rule from hub2-storage.md applies if containers are instanced (bake with a window, not headless).

## Built (2026-11-15)

`tools/gen_hub2_c_cover.gd` (headless, re-runnable) writes `Dressing/C/Cover` and the crane skip list into
`scenes/hub2_dressing_src.tscn`; then bake windowed (`tools/godot_bg.ps1 --script tools/bake_hub2_dressing.gd`). `"C"` is now in
`LOCKED` in `tools/gen_hub2_dressing.gd`. New: `Hub2Crane.skip_columns` (+ `column_slots()`, `is_column_skipped()`),
`Hub2Prop.Kind.JERSEY_BARRIER` (variant 1 = hazard stripes, `length` = metres) and `PLATE_SHIELD` (appended to the enum).

Result: 5 jersey runs (13 barriers) + 3 plate shields, 3 crate piles, a container L-pair, a 2x3 crate tower with a locker.
Deviations from the spec:
- The columns that stand in the map are the EAST pair at z -99.25 and -87.5 (the ramp is on the east side), not the south pair;
  they are skipped per column (`skip_columns` is `(side, z)`, not a `skip_column_zs` list).
- Keep-clear zones are constants in the tool (entrance (70.5,-108), ramp foot (104,-100), 4 m lane between them) and stored as
  metadata on the Cover node for the test.
- The 20 m sightline rule is not met: at eye height 594 of 1440 sample rays are still over 20 m (793 before cover). Two full-height
  pieces cannot break a 40 x 49 m room; the tool places them where they cut the most. Add a third full-height piece if wanted.

Tests: `tests/test_hub2_c_cover.gd` (6 / 5844 green). Probe shots `tests/_probe_hub2_c_cover.gd`. Not played, uncommitted.
