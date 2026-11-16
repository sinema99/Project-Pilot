# EXIA weathered paint

Grilled 2026-11-12 (9 questions), built the same day. EXIA is a rusted, chipped factory-worker machine,
never clean and new. All in the editor and in Godot: no Blender, no textures, no UVs.

## Decisions

| Question | Answer |
|---|---|
| Look | Destroyed and rusted, worn down. Not a clean Gundam. |
| Paints | **Faded safety yellow** (default), **faded blue-green**, **dull orange**. Switched from an **inspector dropdown**; nothing in the menu. |
| Technique | One procedural shader, tinted by the chosen paint: paint over noise-carved rust, bare-metal chips on the paint/rust border plus lone scratches, vertical grime drips. Cut into 16 texels per metre like the AIRFRAME look. |
| Parts | **Shell** (chest, torso, shoulders, thighs) takes the paint and the wear. **Frame** (shins, ankles, feet, forearms, hands, the two cylinders, the eye) is oily dark metal with a rust bloom and sparse flecks of the paint colour. Hazard stripes on the two foot slabs. |
| Wear gradient | About **70 %** of the paint left on chest, torso and shoulders; **40 %** on the thighs; frame parts keep 55-75 % of their dark finish; the back boxes **30 %** (heavier wear, extra grime). |
| Back boxes | No longer white: the same shell shader, heavier wear. |
| Eye | ~~A dim amber glow on `Sphere_006`.~~ Removed by the placement pass: plain frame metal. |

## How it is built

- `shaders/mech_weathered.gdshader`: `is_frame`, `paint_left` (share still in its original finish),
  `hazard`, `glow`, `seed`. The pixel grid is projected along the dominant axis of the normal. Skinned
  parts read mesh-space rest positions from `CUSTOM0/1` (`use_rest`), so the patches ride the body
  through every animation; the back boxes and the editor use `VERTEX`.
- `scripts/mech_paint.gd` (`MechPaint`, `@tool`), a child of the Mech scene root named `MechPaint`.
  The dropdown (`scheme`) and a `wear` slider (1 = as specced, 0 = clean paint, 2 = twice the rust) are
  on that node, in `scenes/mech.tscn`; the editor viewport repaints live. `PARTS` maps each of the 19
  mesh names to its role, paint share and stripes.
- It puts a `material_override` on every mesh. ApplyCelMech (derive mode) skips a mesh that has one,
  AIRFRAME leaves a material that is neither a cel nor a plain standard material alone, so the paint
  shows under AIRFRAME (the default), RETRO and COMPOSITE alike. Consequence: in RETRO the mech has no
  cel ink or two-tone light, it is lit by the shader's plain diffuse.
- Like `ApplyStylized` it strips its overrides on `NOTIFICATION_EDITOR_PRE_SAVE` and puts them back on
  POST_SAVE, so the .tscn never carries them. Only the running game swaps a skinned mesh for its
  rest-pose copy (`JetpackLook.bake_rest_pose`); the editor shows the bind pose.
- `Mech._add_back_panels` hands the two boxes to `MechPaint.dress_panels` once built.

## Not done / limits

- Not played. Verified by tests and by probe shots (`tests/_probe_mech_paint_shot.gd`, standing, run
  pose, AIRFRAME and RETRO, all three paints).
- The blue-green and orange palettes, the wear gradient and the eye's brightness are my picks; they
  are constants at the top of `mech_paint.gd` and uniforms in the shader.
- Supersedes the "cel-shaded white" look in `docs/specs/exia-back-panels.md`.

## Placement pass (2026-11-12)

Grilled 6 the same day, after the user saw it: the colours were right, *where* each colour sat was
not. The noise-only rust read as camo, the chips sat on the blob borders instead of the real edges,
the grime drips were random. And the head sphere glowed. This pass only moves the wear; the paints,
the dropdown, the `wear` slider, the 16 px/m grid and the shell/frame split are unchanged.
**It supersedes the Technique, Wear gradient and Eye rows above.**

| # | Decision |
|---|---|
| 1 | **Physical logic, not random blobs.** Flat faces keep their paint; chips on the edges and corners; rust grows from edges, bottoms and seams; streaks run down; lower is dirtier. |
| 2 | **Less rust.** Chest, torso, shoulders ~85 % paint; thighs ~70 %; back boxes ~60 % (was 30 %, nearly all rust); frame 60-85 % (feet most worn, cylinders least), rust gathered low and at the joints. |
| 3 | **Same part split.** Yellow: chest, torso, shoulders, thighs, back boxes. Dark frame: shins, ankles, feet (hazard), lower arms, hands, cylinders. |
| 4 | **Ragged edge chips**, 1-3 px, gappy; heaviest on bottom edges and outer corners, light on top edges; bare metal on the outside of a bite, rust in the core of the bigger bites; hazard stripes chewed the same way. The frame's chips are narrower, duller steel. |
| 5 | **Streaks and grime.** Rust streaks only hang below edges and seams, 0.3-1 m, fading orange-brown. Grime rises from the ground to mid-shin; under-faces darker than tops. Scratches cut to about a third, shell only, open faces away from the edges. The random black drips are gone. |
| 6 | **Head sphere** (`Sphere_006`): no glow at all, dark frame metal worn like the rest. |

### How it is built

- **The bake** (`scripts/mech_wear_bake.gd`, `MechWearBake`; run `tools/bake_mech_wear.gd`, ~1 min
  headless) writes `assets/mech_wear/<mesh>.res`: each GLB part subdivided so no triangle edge is over
  0.1 m, with CUSTOM0/1 = rest position/normal and CUSTOM2 = four distances in metres:
  - **chip**: to the nearest convex edge (a crease of 60° or more, or a tighter-than-0.15 m bevel;
    spheres and cylinder sides don't count), divided by that edge's weight (bottom ×1.6, top ×0.6);
  - **seam**: to the nearest concave crease or another part's surface (0.1 m voxels);
  - **drop**: how far a side-facing point hangs below the nearest edge or crease above it;
  - **corner**: to the nearest point where two convex edges of different directions meet.
  Each part is rigid on one bone, so new vertices take the nearest corner's bone and nothing cracks.
  The bake is stamped with the source vertex count; `MechPaint` falls back to the plain mesh (and the
  shader to "far from everything") with a warning when a part no longer matches. **Re-run the tool
  after every Mech_V1.glb re-export.**
- **The back boxes** are true `BoxMesh`es: the shader works the same four distances out of
  `box_half` (no seam, no ground grime: their local y is not the body's height).
- **The shader** builds a rust *potential* from those fields (edges 0.6, seams 0.9, under-faces 0.6,
  height 0.3, corners 0.75), roughens it with noise, and cuts it at `1.2 - 1.6 × wear`, where
  wear = 1 - `paint_left`. Then come the chips and bites on `chip` and `corner`, the streak columns on
  `drop`, and the grime on height and under-faces. `paint_left >= 1` turns every kind of wear off.
- `MechPaint` swaps each part's mesh for its bake (in the editor too) and swaps it back on undress /
  PRE_SAVE, so the scene file never carries it.

### Verification

- `tests/test_mech_paint.gd`: the new shares, no glow / no EMISSION, every part has a fresh bake, the
  bake on a 1 m box (bottom edge nearer than top, middle farthest, drop starts under the top edge, no
  seams on a lone box), the box uniforms, and undress gives the GLB mesh back.
- Debug render of the three fields, then before/after probe shots (`tests/_probe_mech_paint_shot.gd`):
  `screenshots/mech_wear/` (before_yellow, after_yellow_standing, after_run_scheme0-2).
- Not played.
