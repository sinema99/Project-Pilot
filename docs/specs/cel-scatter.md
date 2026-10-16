# Cel Scatter — chipped, scattered band edges

Reference: the user's close-up of a worn pipe (2026-10-06). Dark flecks sit inside the lit band
and a few light flecks inside the dark one, so the edge between two cel tones reads as dry,
worn-through paint instead of a clean line. CEL look only; the PIXEL look has its own shader.

## Decisions (grilled 2026-10-06)

| # | Question | Decision |
|---|---|---|
| 1 | What texture | Scatter at the cel band edges, not the painted patches |
| 2 | Anchor | Surface: UV on characters, world on level geometry (same split as `paint_anchor`) |
| 3 | Direction | Both ways, weighted 2:1 toward dark into light |
| 4 | Painted shading | Kept as is; scatter is a separate layer with its own toggle |
| 5 | Chips | Small, hard-edged, unstretched (flat Voronoi cells) |
| 6 | Reach | Densest at the edge, fading to nothing a fleck or two away; cast-shadow penumbra included |
| 7 | Palette / band count | Unchanged this build |
| 8 | Scope | Everything on `cel-shader-base`, characters included |

## How it works

`fragment()` computes `scatter_shift` (a varying) from the flat Voronoi cell value at the pixel:
`s = (cell - 0.5) * 2`, `shift = s^3 * weight * scatter_reach * scatter_strength`. Cubing keeps
most cells near zero, so only a few reach far from the edge. `diffuse_sample` adds the shift to
the curve input, so every flecked pixel flips band only if it was within reach of the edge.
`is_lit` also pushes shadow attenuation by `shift * 4 * 4a(1-a)`, which only moves the penumbra.

World anchor uses the dominant axis only (blending planes would soften the hard cells).

## Tunables (shader globals, `project.godot`)

| Global | Default | Meaning |
|---|---|---|
| `scatter_strength` | 1.0 | Master, set by the CEL SCATTER setting |
| `scatter_dark` | 1.0 | Weight of dark flecks in the lit band |
| `scatter_light` | 0.5 | Weight of light flecks in the dark band |
| `scatter_reach` | 0.12 | Max shift, in diffuse-curve input units (the curve edge is 0.38..0.52) |
| `scatter_world_size` | 0.03 | World cell size, metres |
| `scatter_uv_size` | 0.015 | Character cell size, UV units |

Setting: `cel_scatter`, graphics, OFF / ON, default ON, greyed in the PIXEL look like PAINTED SHADING.

## Built

`shaders/cel/includes/scatter.gdshaderinc` (new), `base-cel-shader.gdshaderinc` (shift + shadow
gain), `cel-shader-base.gdshader`, `project.godot` (6 globals), `settings.gd`, `tab_settings.gd`,
`tests/test_cel_scatter.gd`, `tests/_probe_scatter_shot.gd` (windowed; headless cannot compile
shaders).

## Known limits

- Cast-shadow edges only chip where the shadow has a penumbra. A hard shadow edge has attenuation
  0/1 with nothing to push, and `light()` has no derivatives to find the edge another way.
- A surface whose light value sits right on the curve edge (a floor at a grazing sun) is flecked
  all over. That is the effect working, but it can read as terrazzo.
- Not yet played; chip size and reach are tuned from probe screenshots only.

## Revised 2026-10-06 (after first look: "expected more bands, smudgy like the reference")

- **Five bands.** `resources/cel_diffuse_curve.tres` is now a five-level staircase (0, .25, .5, .75, 1)
  with soft edges at wrapped-light 0.14-0.17, 0.28-0.31, 0.42-0.45, 0.56-0.59. Applies to everything
  on `cel-shader-base`. Supersedes decision 7.
- **Brush-stroke smudge, not chips.** `scatter.gdshaderinc` is now stretched (8x) value noise with a
  slow sideways bend and a bristle octave, strokes lying along the surface (horizontal on walls,
  along x on floors, along U on characters). Supersedes decision 5. `scatter_reach` 0.10, `scatter_world_size` 0.05.
- Probe: `screenshots/cel-scatter2/`. Not yet played. Strokes run across a vertical pipe's bands,
  which reads a little ragged; flip the stroke axis if it should run along the pipe instead.
