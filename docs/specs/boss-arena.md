# Spec: the first boss arena on the RightWide cap

> **Status:** grilled and specced 2026-11-03, built 2026-11-03 - see "Built". Reworked 2026-11-04 - see "Rework" at the end.
> **Scene:** `scenes/boss_arena.tscn` (root `BossArena`, a `MissionMap`) + `Boss_Arena.tscn` wrapper (F6).
> **Reuses:** the arrival shot's builders (`scripts/cutscene/arrival*.gd`).

## The ask

"I want the top of this tower to be a playable surface. It's going to be the first boss arena. I
don't have the boss modeled yet ... the structure should be 3D and then the background, like the
mountains and the spire, should just be a 2D background ... put invisible walls up around the edges
so the player can't jump off." The circled tower is `RightWide` in `ArrivalShot.TOWERS` (the old
landing-pad tower, `role = &"pad"`, `wear = &"bitten"`).

## Decisions

1. **Its own scene.** `scenes/boss_arena.tscn` as a `MissionMap`, plus a root `Boss_Arena.tscn`
   wrapper for F6, like Starter_Map / Internals. The cutscene is untouched. No exit or win
   condition until the boss exists.
2. **True scale.** The cap stays the shot's size: radius 160 m, ~320 m across, one flat octagon
   (pad towers have no raised step) at the shot's height (y ~99.4).
3. **Bites kept.** The rim's bites from the shot stay. The invisible wall follows the *bitten* rim
   outline, a few metres inside the visible edge, so the wall is always where the edge looks to be
   and nobody drops into a bite.
4. **Walls are stop-only.** 60 m tall. Wall-run, wall climb, mantle and vault ignore them, and
   so does the camera. They only stop the body. A kill height 30 m under the cap respawns on the cap.
5. **3D vs 2D.** Real 3D (visual, no collision): RightWide, the rest of the main base (the
   other four towers, the decks, skybridge, road, power line, growth), and the land and forest
   within ~3.5 km of the cap. Everything farther (cloud sea, the ranges, the massif, the spire,
   the sister outpost) is a **2D backdrop**: a 360 deg cube of six images baked from the arrival
   world with the camera at the arena centre and the near 3D hidden. Re-bake with
   `tools/bake_boss_backdrop.gd` whenever the shot changes.
6. **Weather.** The shot's sun, sky and haze (baked into the backdrop), plus light snowfall that
   follows the player. No blizzard. The gameplay look stays whatever is active (Retro by default);
   the cutscene's cinema post is not carried over.
7. **Floor.** Bare: snow and scrub as visuals only, the collision is one flat polygon. Spawn 20 m
   in from the edge facing the cutscene camera, looking across toward the spire. An empty
   `BossAnchor` marker at the centre.
8. **Moveset.** pilot9, full kit. No EXIA.

## How it is built

- **Live, not saved.** The arena builds its 3D from the same builder nodes at load (`ArrivalShot`
  with `cutscene = false`, ~5 s headless). Any later shot revision shows up in the arena on its
  own; only the backdrop needs a re-bake.
- **The land around a viewer.** `ArrivalLand` gains `view_centre` (where the viewer stands: the
  camera origin in the shot, the arena centre in the arena). Its polar grid, its far-normal zone
  and the terrain shader's distance terms are measured from it, and `half_angle_degrees = 180`
  makes the grid a full circle. In the arena the grid runs from ~20 m out to 3.5 km. In the bake it
  runs from 3 km out to 45 km.
- **Forest** scatters within `reach` of the land's `view_centre`.
- **Outpost and spire** are not built in the arena (they are in the backdrop). Of the clouds only
  the level sea stays, in 3D, centred under the arena so the near slopes sink into it the way the
  baked ones do; the shot's camera-facing cards are hidden.
- **Stop-only walls** sit on physics layer 10 (`stop_only`). pilot9's body collides with it; his
  wall-run / climb / mantle / vault rays and shape tests and the camera spring arm use masks
  without it.
- **Backdrop sky.** A sky shader samples the six faces by the view direction (my own face
  convention, written once in the bake tool and once in the shader).

## Not in this

The boss, cover or obstacles on the cap, an exit, checkpoints, the shot-to-arena handoff, EXIA.

## Built (2026-11-03)

- **Files.** `scripts/boss_arena.gd` (`BossArena extends MissionMap`), `scenes/boss_arena.tscn`,
  `Boss_Arena.tscn`, `shaders/boss_arena_backdrop.gdshader`, `tools/bake_boss_backdrop.gd`,
  `assets/boss_arena/backdrop_{px,nx,py,ny,pz,nz}.png` (2048 px), `tests/test_boss_arena.gd`
  (14 tests), `tests/_probe_boss_arena.gd` (windowed screenshots).
- **Shared code touched.** `ArrivalShot.cutscene` (default on: the shot is unchanged);
  `ArrivalLand.view_centre` / `view_on_tower` + full-circle wrap (default origin and 34 deg wedge:
  unchanged); the terrain shader's `view_centre` uniform; `ArrivalForest` reach measured from the
  land's view centre; `ArrivalBase.outpost`; pilot9 `STOP_ONLY_LAYER` / `PROBE_MASK` on all 8
  movement rays and the vault shape test, body mask += layer 10; project layer 10 named `stop_only`.
- **Numbers.** Cap centre (301.2, 99.4, -1977.2), rim radius 160 m. Wall 3 m inside the bitten rim,
  60 m tall, 2 m thick, a box per edge (22). Kill height 69.4. Spawn on the camera side, 20 m
  from the nearest wall (a bite's side, so it walks in until that holds), facing the spire.
  Land: 20 m to 3.5 km, 360 columns (108k verts). Forest: 1.8 km reach at density 0.007 (62k
  trees; the shot's 3.2 km / 0.012 round a full circle hit the 120k cap). Only the cloud sea is
  kept, 100 km across, centred on the arena, frozen at shot time 5 s. Snow: 900 flakes in a
  60 x 24 m box riding with him.
- **The bake.** Land from 3 km out (overlaps the 3D land's last 0.5 km), the outpost, the spire,
  clouds past 1.2 km turned to face the arena. The cinema post, the haze's screen-space lobe,
  its tint toward the light, the light wrap and glow are off in the bake: they are screen-space and
  left seams between faces (seen in the first bake). The backdrop shader un-tonemaps each texel
  (inverse of Godot's filmic at exposure 0.85) so the arena's own tonemap lands on the baked colour.
- **Seen in probe shots.** No seams. The spire, ranges, cloud sea and outpost read in the backdrop;
  the neighbouring towers, base and slopes are 3D. The cap's snow top reads as flat white up close.
- **Not checked headlessly.** Feel, frame rate, whether the wall is ever reachable by an exploit.

## Rework (2026-11-04)

The ask, after looking at `boss1.tscn`: remove the weird things clipping through the floor, bring the
background mountains up, and stop everything being so white. Grilled 4, all on the recommendation.

1. **Clipping.** The black lumps were the scrub `ArrivalGrowth._grow_cap` plants on every cap. New
   `ArrivalGrowth.bare_caps`; the arena lists RightWide. The shot's list is empty, the cap's sides
   keep their moss and rust.
2. **Mountains.** The ranges stand 2x taller on screen, in the bake only: `ArrivalLand.range_lift`
   (1 in the shot, `RANGE_LIFT` 2 in the bake) stretches `ranges_at` over `range_lift_from`, 100 m, the
   eye height. Only the ranges: the spire, its field and the outpost's peak keep their size.
3. **Light.** Overcast, cold, moody, deliberately not the shot's clear day. One table,
   `BossArena.OVERCAST`, feeds the arena (`_enter_tree`, before the builders' `_ready`) and the bake:
   sun 0.42, ambient, snow and rock, cloud tones, and in the bake the sky and a thinner haze (0.4).
4. **Floor.** A wind-scraped pad, about 30% bare deck: `tools/gen_boss_floor.gd` paints
   `assets/boss_arena/floor.png` (4096 px over 340 m, slabs, seams, faded rings, cross and bars), and
   `_build_surface` lays it on the rim 2 cm over the cap on a cel material, so every look takes it.
   Visual only: the collision is still the one flat polygon. Tune tones in the tool's constants.

**PIXEL.** Its golden haze is tuned for small maps (half gone at 90 m) and swallowed the whole world
here. Scene-only override on the arena's PixelLook node: density 0.0004, the overcast's colour, off
the sky.

**Compression matters here.** The floor and the backdrop faces are imported with
`compress/high_quality=true` (BPTC). Plain S3TC put coloured arcs across the sky, a woven grid on the
floor, and swung near-identical greys to teal, purple or green. The backdrop shader also dithers by
one step of 255 before un-tonemapping.

**Checked.** Probe shots in RETRO, CEL and PIXEL. Near-white pixels (all channels 245+) at the spawn:
38% before, 0% after; from the centre toward the spire: 49% before, 0% after. Not checked: how it
plays, and the frame rate.

**Space elevator (same day).** The spire is really a space elevator, so in the arena it runs up into
the sky and has no top. Bake only, the arrival shot keeps its tapering spire: `ArrivalSpire.taper_height`
(0 in the shot, `ELEVATOR_TAPER` 9 km in the bake: still a cone, wide at the foot and narrowing, its
point past where it has faded out; a straight shaft was tried and the user wanted the cone). The bake
renders each face with and without the spire and goes from one to the other between 14 and 38 deg of
elevation (`ELEVATOR_FADE`), so it dissolves into the sky behind it with no end to see.
