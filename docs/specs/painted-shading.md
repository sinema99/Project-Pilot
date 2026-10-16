# Painted Shading — hand-painted variation inside each cel tone

Status: specced and built 2026-10-04.

The cel look shades every surface in two flat tones (lit / shadow). The user likes that and keeps it,
but finds the flat areas too flat. They want each tone broken up into colours very close to the
original, Arcane-style, without painting any textures.

## Decisions (grilled 2026-10-04)

| # | Question | Decision |
|---|----------|----------|
| 1 | Screen filter or on the objects | **On the objects**, inside `shaders/cel/cel-shader-base.gdshader`. A screen-space filter's noise belongs to the screen, so it slides across moving surfaces (shower-door effect), and finding colour edges from the image means edge detection, which was tried for shadow ink and abandoned 2026-08-31 |
| 2 | What the pattern is pinned to | **Both, per material.** Characters use **UVs** (sticks to animated limbs; skinning runs before the shader, so model space would slide at the joints). World geometry uses **world-space triplanar** (no UVs needed, uniform size, no seams, nothing moves). `paint_anchor` uniform: `cel_ground.tres` = World, `cel_character.tres` / `pilot_cel_character.tres` = UV |
| 3 | What changes | **Brightness plus a warm/cool lean**: lighter patches slightly warm, darker patches slightly cool. Separate strengths, warmth 0 = brightness only |
| 4 | Shape | **Stepped patches**: cloudy noise cut into flat levels (3 by default) with crisp edges. Step count and edge softness are tunable |
| 5 | Size | **Large**: about 2–4 patches across Pilot's torso, about 1 m on the world. Separate size controls for UV and world |
| 6 | Toggle | **PAINTED SHADING** row in settings (graphics), OFF / ON, **default ON**. Drives one shader global `paint_strength`. Detailed tunables are developer-side shader globals |
| 7 | Scope | **Cel shader only.** `metre_grid.gdshader` (jump grid, blockout boxes) stays clean: it is a measuring tool |
| 8 | Repetition | **Per-instance seed.** `apply_stylized.gd` sets the `paint_seed` instance uniform on every mesh it styles, derived from the node path so it is stable between runs. Only UV-anchored materials use it |

## How it works

The variation is applied to `ALBEDO` in `fragment()`, before `light()` runs, so the two-band
diffuse curve is untouched. Each tone gets the same mottling; the shadow tone's is just darker.

1. **Coordinate.** UV anchor: the mesh's raw `UV` (before `uv_scale` / `uv_offset`) divided by
   `paint_uv_size`, plus an offset from `paint_seed`. World anchor: world position divided by
   `paint_world_size`, sampled on three planes and blended by the world normal (weights raised to
   the 4th power so a face mostly reads one plane).
2. **Noise.** Two octaves of value noise, 0..1.
3. **Steps.** Contrast is pushed out from 0.5 so the outer levels actually appear, then the value
   is cut into `paint_steps` levels. `paint_softness` is the width of the blend at each step edge
   (0 = hard). The result is a level `v` in -1..1; with 3 steps that is dark / base / light.
4. **Colour.** `albedo *= (1 + v * paint_value) * vec3(1 + v * paint_warmth, 1, 1 - v * paint_warmth)`,
   all scaled by `paint_strength`.

**Warm/cool is a temperature tint, not a hue rotation.** Rotating the hue of a white or grey does
nothing, and Pilot is mostly white and grey. Pushing red up and blue down (or the reverse) moves
whites towards cream or blue-grey, and moves saturated colours a few degrees of hue, which is what
the grill asked for.

### Tunables (shader globals in `project.godot`)

| Global | Default | Meaning |
|---|---|---|
| `paint_strength` | 1.0 | Master. Set by the PAINTED SHADING setting: 1 on, 0 off |
| `paint_value` | 0.03 | Brightness swing per level, as a fraction of the base colour (was 0.06; halved 2026-10-04, the darks read too dark on the floor) |
| `paint_warmth` | 0.015 | Red/blue swing per level (was 0.03, halved with paint_value) |
| `paint_steps` | 3 | Number of flat levels |
| `paint_softness` | 0.08 | Edge blend width, in noise units |
| `paint_world_size` | 1.0 | World patch size in metres |
| `paint_uv_size` | 0.1 | Character patch size in UV units |

### Settings

`painted_shading` row, section `graphics`, values `["off", "on"]`, default `on`. `_apply` sets the
`paint_strength` global. Instant, no material swaps.

## Out of scope

- `metre_grid.gdshader` (decision 7). A separate small pass if wanted later.
- The sky, outline, crease, rim light, VFX and hologram shaders.
- Brush-stroke direction (rejected in decision 4).

## Known limits

- UV-anchored patches follow the Blender unwrap: seams show where islands meet, and a squashed island
  stretches its patches. The fix is in Blender, or switch that material to World.
- The seed is per MeshInstance3D. Surfaces inside one instance share it. pilot9 is 12 instances
  (`Cube.039` … `Sphere.007`), so his parts are already separate.
- Anything that uses a cel material without going through `apply_stylized.gd` (the staff,
  procedural map parts) gets seed 0. World-anchored parts ignore the seed anyway.

## Built (2026-10-04)

- `shaders/cel/includes/painted.gdshaderinc` (new): globals, hash, value noise, triplanar, stepping,
  colour shift.
- `shaders/cel/cel-shader-base.gdshader`: includes it; `paint_anchor` uniform, `paint_seed` instance
  uniform, three varyings; applies after the `ALBEDO` line.
- `resources/cel_ground.tres`: `paint_anchor = 1`. The character materials keep the default (UV).
- `project.godot`: seven `paint_*` shader globals.
- `scripts/settings.gd` / `scripts/ui/tabs/tab_settings.gd`: PAINTED SHADING row (now 17 rows).
- `scripts/rendering/apply_stylized.gd`: `paint_seed_for(path)`, stamped on every styled mesh, removed
  in `clear_now()` so it never serialises into a scene.
- `tests/test_painted_shading.gd` (6 tests), `tests/_probe_paint_shot.gd` (windowed screenshots;
  optional second arg overrides `paint_uv_size`).

Departures from the grill, all tuning:

- **Brightness swing is ±6 %, not the ±4 % proposed.** It acts on linear colour, so 4 % barely
  showed on Pilot's greys.
- **Hue drift is `paint_warmth` 0.03**, a temperature tint (see How it works), not ±3° of hue.
- **`paint_uv_size` 0.1** (10 patches per UV unit). 0.25 was larger than pilot9's UV islands, so each
  limb landed in a single level and looked flat. 0.1 gives 2–4 patches across the vest; 0.05 read as
  camouflage.

Probe findings: at full strength the variation is subtle (vest, helmet, walls, floor, mech); 5x
`paint_value` shows the patch shapes clearly. It survives the 3X pixel filter. pilot9's limbs show
patches stretched along their length, which is his Blender unwrap (cylinders unwrapped long and
thin); see Known limits. Not checked headless: how it looks in motion.

## v2: map scale and angular shape (grilled + built 2026-10-04)

The user liked v1 but found the patches on big map surfaces too small and too even: at 1 m, a
20 × 6 m platform carried about 120 blobs. On Pilot and the mech, patches are big relative to
the part they sit on. They also wanted sharper shapes: angles and straight cuts, not clouds
everywhere.

| # | Question | Decision |
|---|----------|----------|
| 1 | How map patch size works | **Two world layers**: a big one so large surfaces get broad patches, plus a small one so crates and pillars aren't left inside one flat patch. Rejected: a single bigger size (small pieces go flat) and scaling per object (patch sizes jump at box seams) |
| 2 | The sharper shape | **Voronoi polygons mixed with the cloud**: flat-valued cells give straight edges at random angles, and the cloud bends some edges so it doesn't read as stained glass |
| 3 | Where | **Everywhere.** Characters (UV) get the new shape too; they stay single-layer |
| 4 | Combining the layers | **Added before stepping**, so there are still 3 tones and the small layer chips edges and drops islands |
| 5 | Sizes | Big **5 m**, small **1.25 m**, small weight **0.35** |
| 6 | Angularity | `paint_angularity` **0.6** (0 = v1 clouds, 1 = pure polygons), shared |

### How it works

- `paint_voronoi(p)`: nearest of the 3×3 neighbouring fully-jittered feature points, and returns that
  cell's random value. Cells merge into bigger irregular polygons wherever neighbours land on the
  same level.
- The cell value is scaled down by 0.56 (`PAINT_VORONOI_SPREAD`) so its spread matches the cloud's
  (std 0.29 → 0.16). `paint_blend` mixes two centred noises and divides by the length of the weight
  vector to restore the spread a mix loses. Simulated: the dark / base / light split stays
  0.34 / 0.32 / 0.33, matching v1's thirds, so the retuned `paint_value` still means the same thing.
- `paint_noise_world` = `paint_blend(big triplanar, small triplanar, paint_world_detail_weight)`.
  The triplanar now skips planes with no weight (two of three on axis-aligned boxes), because the
  Voronoi costs nine cells per sample.

### New / changed globals

| Global | Default | Meaning |
|---|---|---|
| `paint_world_size` | 5.0 (was 1.0) | Big world layer, metres |
| `paint_world_detail_size` | 1.25 | Small world layer, metres |
| `paint_world_detail_weight` | 0.35 | Small layer's share of the mix |
| `paint_angularity` | 0.6 | Polygon vs cloud mix, characters and map |

### Built

- `painted.gdshaderinc`: `paint_cloud` (the v1 noise), `paint_voronoi`, `paint_blend`, `paint_noise`
  (the mix), `paint_noise_triplanar`, `paint_noise_world` (two layers, takes the raw world position).
- `cel-shader-base.gdshader`: the world branch passes the raw world position.
- `project.godot`: three new globals, `paint_world_size` 5.
- `tests/test_painted_shading.gd`: checks the new globals and defaults.

Probe (5× strength): the floor shows big straight-cut patches a few metres across with small angular
islands. Walls and the mech show faceted patches. On Pilot, the patches are angular on the vest
and helmet and still stretched along the limbs (his unwrap). At shipped strength it stays subtle.
