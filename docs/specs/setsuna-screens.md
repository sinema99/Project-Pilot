# Spec: Setsuna's Screens

## Problem Statement

Setsuna's third material slot, `Highlights`, ships `baseColorFactor` `[0, 0, 0, 1]`. In
`stylized.gdshader` that colour is load-bearing in the worst way: the shader computes both
`EMISSION = ambient * ALBEDO` and `DIFFUSE_LIGHT += banded * LIGHT_COLOR * ALBEDO / PI`, so an
albedo of zero renders pure `#000000` under any light, in any band, with no halftone. Those
regions are dead voids.

They are also the only places on the character that read as *equipment* rather than as body.
The intent is that black means **screen** — a powered display built into the suit, showing the
player their own state without a corner-of-the-viewport HUD.

Three regions carry the slot today: the backpack (three panels), the backs of both thighs (two
strips each), and the visor. This spec covers the first two.

## Solution

**The black geometry marks where a screen goes; it is not the screen.** Each region gets a thin
`QuadMesh` floating 2mm proud of the panel, running an unshaded shader. The pure-black panel
underneath is left exactly as it is and acts as the bezel.

Quads hang off `BoneAttachment3D` nodes with `use_external_skeleton` set, parented under
`SETSUNA` in `scenes/player.tscn` — never inside the instanced GLB subtree. This is the same
instinct that drives `apply_stylized.gd`'s pre-save/post-save dance: a re-import rebuilds
`PlayerModel`, and anything parented under it goes with it.

Every black island is **rigid-weighted, 1.0 on a single bone, zero blended verts**, so a bone
attachment tracks the panel exactly rather than approximately.

## Measured Geometry

All figures are mesh-space, read out of `assets/setsuna.glb` and confirmed against Godot's
imported `ArrayMesh` AABBs. `metarig` carries a uniform scale of `0.934312`, so world-space sizes
are 6.6% smaller; the pixel column below accounts for it.

The black regions are not free-form. Each is a **subdivided grid on a flat plane**, and the
panels are runs of filled cells:

```
BAG — 4x5 cell grid, 13 filled       x=-0.051  -0.0255   0.0   0.0255  0.051
  y 1.4107   ##  ..  ##  ##
  y 1.3719   ##  ..  ##  ##            all at z = -0.2826, normal (0, 0, -1)
  y 1.3331   ##  ..  ##  ##
  y 1.2942   ..  ..  ..  ..
  y 1.2554   ##  ##  ##  ##
```

| Screen | Bone | Rect | Size | On screen @3m |
|---|---|---|---|---|
| Health | `spine.002` | `x[0.0000, 0.0510] y[1.3331, 1.4496]` | 0.0510 x 0.1165 | 20 x 45 px |
| Stamina | `spine.002` | `x[-0.0510, -0.0255] y[1.3331, 1.4496]` | 0.0255 x 0.1165 | 10 x 45 px |
| Dash | `spine.002` | `x[-0.0510, 0.0510] y[1.2554, 1.2942]` | 0.1020 x 0.0388 | 40 x 15 px |
| Thigh R | `thigh.R` | `x[-0.1449, -0.1146] y[0.6402, 0.8843]` | 0.0303 x 0.2441 | 12 x 95 px |
| Thigh L | `thigh.L` | `x[0.1146, 0.1449] y[0.6402, 0.8843]` | 0.0303 x 0.2441 | 12 x 95 px |

Pixel figures assume `spring_length = 3.0`, `1920x1080`, 75 degree FOV — 417 px/m. The spring arm
only ever *shortens* on collision, so these are minimums.

**Each thigh actually carries two strips, not one**, separated by a gap of `0.0032` — **1.3 px on
screen**. One quad per thigh spans both strips and the gap. Hiding 1.3px of grey costs nothing
and removes two placement problems.

## What A Screen Looks Like Here

Three pipeline facts constrain the visual language, and all three subtract:

- **No bloom.** `glow` appears zero times in `scenes/test2.tscn`. A lit screen is a flat colour
  patch and nothing more. Enabling glow was considered and rejected — it is a whole-scene change
  that would touch the sky, the sun-lit hub faces, and the Moebius look already tuned around it.
- **No ink line, at either boundary.** The black panels are *coplanar* with the surrounding grey
  (`Secondary` has 100 verts at exactly `z = -0.2826`). `moebius_outline.glsl` detects edges from
  depth and normals only, so a pure albedo boundary gets nothing. A quad 2mm proud gets nothing
  either: `depth_edge = length(gradient) / center_distance` against a `0.05` threshold, and 2mm at
  3m is `0.0007`.
- **Grain does reach them.** `grain_luma_falloff = 0.05` keeps grain off the pure-black panels but
  lets it onto anything lit, so a screen sits in the frame rather than on top of it.

So a screen is a flat, unshaded, ungrained-at-the-edges colour patch, 10 to 20 pixels wide, with
no border and no glow. **The unfilled part of a gauge therefore cannot be black** — an empty
gauge would be indistinguishable from no screen at all, at exactly the moment you need to read it.
Every gauge renders a **dim track**: the fill colour at `track_level`, default `0.12`.

## The Shader

`shaders/screen.gdshader`, `render_mode unshaded`. Three uniforms:

```glsl
uniform vec4 fill_color : source_color;
uniform float fill : hint_range(0.0, 1.0);
uniform float track_level : hint_range(0.0, 1.0) = 0.12;
```

One rule covers all five screens, because the three behaviours collapse into one:

- **Health, stamina** — `fill` is the fraction, bar fills bottom-up.
- **Dash** — binary, so `fill` is only ever `1.0` (dashable) or `0.0` (locked). A bar at 1.0 is a
  solid panel; a bar at 0.0 is a solid track. No mode flag needed.
- **Thighs** — solid state lights, so `fill` is pinned at `1.0` and only `fill_color` moves.

`QuadMesh` UVs put `UV.y = 0` at the top, so the filled region is `UV.y >= 1.0 - fill`. The edge is
antialiased across one pixel via `fwidth`, matching `stylized.gdshader`'s `band_softness = 0.02`
philosophy: reads as a hard step, does not shimmer when the camera moves.

## Colours

Backpack: **health red**, **stamina green**, **dash orange**.

Thigh screens are a pure function of horizontal speed. This controller never accelerates — it sets
`velocity.x/z` directly — so speed is only ever one of a handful of exact values. Speed-driven is
chosen because it is three lines and cannot fall out of sync when a movement state is added. What
it cannot do is tell two gaits apart that share a speed, which is now the case for the crouch and
the sprint — see the note under the table.

| Speed | State | Colour |
|---|---|---|
| `0.0` | idle | blue |
| `3.0` | — | green |
| `6.0` | run (`SPEED`) | yellow |
| `9.0` | sprint / slide / **crouch-walk** (`SPRINT_SPEED`, `SLIDE_SPEED`, `CROUCH_SPEED`) | red |
| `18.0` | dash (`DASH_SPEED`) | red |

**`BAND_CROUCH` is currently unreachable.** `CROUCH_SPEED` was `3.0`; it is `SPRINT_SPEED` now,
so a crouch-walk reads red like a sprint and nothing the controller produces lands in the green
band. This is the cost of reading speed rather than state, and it is worth paying while it is
only a colour: the alternative is a second source of truth for the gait that can drift from the
speed. Give the crouch a pace of its own again and the green comes straight back. If the crouch
needs to read green *at* sprint speed, that is the point to switch the thigh screens to state.

Thresholds sit on the midpoints (`1.5`, `4.5`, `7.5`) so the exact values land unambiguously
inside their bands. Airborne keeps whatever speed the player left the ground with — jumping out of
a sprint stays red through the arc.

Snapped, never blended. `band_softness` is `0.02` and `dot_enabled` is off on Setsuna; everything
in this look is hard-stepped, and a cross-fading gauge would be the only smooth gradient on
screen.

**Known collision, accepted:** red means health on his back and sprint on his legs; green means
stamina on his back and crouch on his legs. The two vocabularies are spatially separated and one
is a fill level while the other is a solid, so they are not expected to be confused.

## Movement Change

`DASH_COOLDOWN` goes from `0.6` to **`3.0`**, and `dash_cooldown_left` is set to `DASH_COOLDOWN`
rather than `DASH_TIME + DASH_COOLDOWN`, so the constant means what it says: 3.0 seconds is the
true dash-to-dash interval. This is a 3.3x increase on the current 0.9s lockout and materially
changes how the dash feels; it is a deliberate design change requested alongside the screens, not
a side effect of them.

The dash screen shows **no progress** during those three seconds — full orange when dashable, dim
track when not. A progress fill was considered and rejected: the binary read is unambiguous under
pressure, and the snap back to full is a clear event.

## Code

New `scripts/rendering/setsuna_screens.gd`, one node under `SETSUNA` holding a `NodePath` to the
player and one to each screen `MeshInstance3D`. It reads player state in `_process` and writes
shader parameters. Four `set_shader_parameter` calls per frame; the two thigh quads share one
material instance because they always show the same thing.

The mapping is a **pure static function**, following the pattern `ui_manager.gd` sets out:

> the whole rule set, as a pure function: no nodes, no tree, no side effects. This is the only
> part of the UI that can be silently wrong

`player.gd` gains only `health` and `stamina` floats plus debug keys. It never learns that
materials exist.

### Placeholder data

`dash_cooldown_left` is real. **Health and stamina are not** — nothing in `scripts/` damages the
player, and sprint is an uncosted toggle (`sprinting = not sprinting`), so a stamina gauge next to
it would currently be a lie. Both ship as plain floats defaulting to `1.0`, moved by debug keys
`1`/`2` (health down/up) and `3`/`4` (stamina down/up) at `DEBUG_METER_RATE` per second. The
gauges read real variables from day one, so landing the real systems changes nothing at the screen
end.

## File Layout

```
shaders/screen.gdshader                  new
scripts/rendering/setsuna_screens.gd     new
scenes/player.tscn                       + 5 BoneAttachment3D/MeshInstance3D pairs, + Screens node
scripts/player.gd                        + health, stamina, debug keys; DASH_COOLDOWN 0.6 -> 3.0
tests/test_setsuna_screens.gd            new
```

`resources/`, `scenes/test2.tscn`, `shaders/stylized.gdshader`, `shaders/moebius_outline.glsl` and
`scripts/rendering/apply_stylized.gd` are all unchanged. `ShaderMaterial_highlights` in
`test2.tscn` stays pure black — it is the bezel.

## Tests

`tests/test_setsuna_screens.gd`:

- **The speed band table**, at each exact speed the controller produces (`0`, `3`, `6`, `9`, `18`)
  and on both sides of each threshold. The core claim.
- **Dash fill is binary** — `1.0` at zero cooldown, `0.0` for any positive cooldown.
- **Meter fill clamps** to `[0, 1]` for out-of-range health and stamina.
- **The shader compiles and exposes `fill_color`, `fill`, `track_level`**, using the existing
  `shader_uniform_names` helper.
- **`track_level` ships at `0.12`**, via `declared_default_float` — expected value from this spec,
  not read back from the file.
- **The five quads land on their measured panel centres.** `player.tscn` is instantiated headless
  and each quad's global origin is compared against the rect table above. This is the assertion
  that catches a hand-placed transform being silently wrong, which is the single most likely
  failure in this change.

## Why Not

- **Screen-space `CanvasLayer` overlay tracking unprojected bone positions.** The obvious way to
  build "2D bars that look 3D", and rejected on four counts: it draws through Setsuna and through
  walls; it never skews with the surface, so off-axis it reads as a sticker; it sits on top of the
  `CompositorEffect`, so it would be the only ungrained, unlined element in frame; and it needs
  `BoneAttachment3D` anyway, since these are skinned meshes.
- **Drawing on Setsuna's own surfaces via UV.** The Bag has no unwrap at all — every vert's U is
  `0.406` — and the thigh strips share one overlapping UV rect. This would cost a Blender re-unwrap
  that every future re-export then has to preserve.
- **`SubViewport` per screen, with real `Control` nodes inside.** Buys the whole Godot UI toolkit,
  and every screen here is a filled rectangle. Six render targets for `step(UV.y, fill)`. Left
  available: swapping one quad's material for a viewport texture is a local change if a screen ever
  needs typography.
- **Deriving quad rects from the mesh at runtime** (reconstructing the cell grid, merging filled
  cells, reading bones from vertex weights). Self-healing across re-exports, and by a distance the
  most intricate code in the project — guarding a topology it cannot validate, and failing by
  putting quads in the wrong place with no error. Five hand-placed rectangles are inspectable.
- **A drawn bezel border on each screen.** Would supply the ink line the compositor refuses to
  give. On a 10px-wide panel a 1px border each side leaves 8px of fill, and a world-space border
  that thin crawls and aliases as the camera moves.

## Out of Scope

- **The visor and the mono-eye.** Deferred deliberately. The visor is a curved forward-facing shell
  (0.254 deep against 0.182 tall) that a flat quad cannot sit on, and its UVs are unusable — **68
  of 166 tris have zero area in UV space**, with 26 more mirrored. It is also the one region a
  third-person camera almost never shows. It stays pure black. When it comes back, the likely
  answer is shading the visor mesh directly, parameterised by `spine.006`-local X/Y with Z ignored
  (96 tris face +Z, zero face -Z, so a front projection is unambiguous).
- **Real health and damage.** No hazards or enemies exist.
- **Real stamina drain.** Costing sprint is a movement design change and deserves its own spec.
- **Glow / bloom.** Stays off scene-wide.
- **`scenes/test.tscn` and `Hub.tscn`.** `test2.tscn` is the working scene; both screens nodes live
  in `player.tscn`, so any scene instancing the player gets them.

## Known Gaps

- **A re-export that moves a panel silently misplaces its quad.** Nothing errors — the quad just
  sits wrong. The placement test is the guard: it fails loudly, with the expected and actual
  origins, and the fix is re-running the measurement. This is the accepted cost of hand-placing
  over deriving.
- **`fill` is written every frame even when nothing changed.** Four `set_shader_parameter` calls is
  noise, but it means the screens cannot be driven by signals later without restructuring.
- **The thigh screens are on the backs of the thighs.** During `SPRINT LOOP` a thigh rotates far
  enough that its screen faces the ground and is unreadable for part of the cycle. That is correct
  behaviour for a physical display and may still read as flicker.
- **Health sits on the wider panel and stamina on the narrower**, so stamina gets 10 screen pixels
  of width against health's 20. Deliberate — health is the stat you read under pressure — but 10px
  is thin, and if stamina ever needs finer reading the two panels should swap.
