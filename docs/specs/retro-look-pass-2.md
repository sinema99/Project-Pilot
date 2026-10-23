# Retro Look, pass 2 — cool grade, cels over a painted background

Status: grilled and specced 2026-10-21.

The user loves RETRO (docs/specs/retro-look.md) but found it too orange, and against the reference
frame (a 90s anime chase across a slate-blue deck) "everything looks so 2d and drawn, but ours
doesn't". Probe shots of trial showed four gaps: a warm cast over the whole screen; characters and
level drawn the same way (the frame inks only the characters and paints the background); a dark,
empty floor; and figures nearly all in light tone with nothing sitting on the ground.

RETRO only. CEL, PIXEL and every cutscene are unchanged.

## Decisions (grilled 2026-10-21, every recommendation taken)

| # | Question | Decision |
|---|----------|----------|
| 1 | The orange | Cool shift: blacks to a cool dark blue-grey (~0.06, 0.07, 0.09), whites to a neutral off-white (~0.93, 0.93, 0.92), the video pass's warm highlight tint neutral, saturation 0.8 -> ~0.9. Warm lines and the violet shadow lean stay |
| 2 | Cels vs background | Full split. Cels (skinned meshes, anything under a moving body) keep flat two tones + ink. Background (static level geometry) gets no ink, a soft painted light/shadow gradient, a faint world-space brush texture, and sits a little darker, cooler and lower in contrast. Fallback if ledges stop reading: a thin low-contrast BG line |
| 3 | Floor | The big ground slabs go light cool slate (~0.55, 0.62, 0.66) with 4 m painted panel lines that fade with distance. Platforms and blocks keep their colours |
| 4 | Cel shadows | The light/shadow threshold biased so ~30-40% of each cel form is in shadow (the sun does not move). Soft cool contact ellipses under each cel that shrink and fade with height. Real cast shadows stay |
| 5 | Sky | Muted, paler slate gradient. Clouds stepped into two soft-edged tones (light top, lavender underside). Cool distance haze on far BG |

## How it works

### Cel or background

RetroLook decides per node, at swap time: a mesh is a **cel** when it, or any ancestor, is a
Skeleton3D, CharacterBody3D, RigidBody3D or AnimatableBody3D (pilot9 and the staff on his
skeleton, the mechs, the range dummy, moving platforms). Everything else is **background**. Nothing
is tagged by hand. PixelLook's `_swap_geometry` asks `twin_for(node, material)` (default: the old
`twin_of`) so the subclass can choose per node; cel and background twins are cached apart.

### New cel-base knobs (all default to today's behaviour)

- `shade_bias`: added to the wrapped light term before the cel step. Negative = more of the form in
  shadow. Cel twins only.
- `shadow_tone`: the dark tone's brightness (was the constant 0.45). BG twins lift it (less contrast).
- `paint_soft`: 0 = the hard cel step. Above 0 the step is averaged over that width (a soft painted
  gradient) and cast-shadow edges soften to match. BG twins only.
- `bg_paint`: rgb multiplies the fill (darker, cooler), alpha = world-space brush texture strength.
- `floor_color` (rgb, alpha = how much) and `floor_panel` (rgb line colour, alpha = strength) +
  `floor_panel_size` (4 m): applied on up-facing fragments only. Lines are anti-aliased on their
  screen footprint and fade out before they would shimmer.

### Floor

RetroLook's `floor_paths` (set in trial.tscn) name the ground subtrees: TrainingV, the jump grid's
slab and floors, the firing range slab. BG meshes under them get the floor twin.

### Contact shadows

`RetroContactShadow` (scripts/rendering/retro_contact_shadow.gd): one per body (CharacterBody3D or
AnimatableBody3D) while RETRO is on, freed when it goes off. A top-level quad, multiply-blended,
unshaded, a soft violet ellipse sized from the body's visual footprint. A ray down from the body
puts it on the ground; it shrinks to half and fades to a quarter by 6 m above its resting height.

### Grade, sky, haze

- RetroLook black/white points and retro_post.tres tints and saturation as decision 1.
- The environment copy also duplicates the sky material and sets muted slate colours plus the new
  sky-shader knobs `clouds_paint` (0 = today's clouds) and `clouds_shade_color`: the cloud body
  is a soft-edged flat shape whose lower part (cloud above it) takes the lavender tone.
- Fog in the RETRO environment: cool pale blue, light density, so far BG fades lighter and bluer.

## Not in scope

Cutscenes, CEL and PIXEL looks, new art assets.

## Built (2026-10-21)

As above, tuned from probe shots in trial (tests/_probe_retro_shot.gd plus a jump-grid shot).
Departures and findings:

- **Ambient scaled to 0.45 in RETRO** (`ambient_scale`). Not in the grill: under the Linear tonemap,
  trial's flat 0.6 ambient plus the sun pushed a white fill past 1.0 in BOTH tones, so the white
  mech had no shadow at all whatever the shade bias. Lower ambient = two visible tones.
- **Trial's sun is nearly on the horizon, from -X.** Up-facing floor sits in its shadow tone, so the
  deck colour is brighter than the reference (0.72, 0.78, 0.8) to land near it on screen.
- **Sky:** the shader blends its sunset gradient in whenever the sun is low, which turned the muted
  sky pink; RETRO sets the sunset colours to the same slate. `sky_horizon` is ADDED by the shader, so
  it is a small value (0.1, 0.12, 0.13).
- **Clouds:** the painted shape uses the noise at a mip bias (`clouds_paint_blur` 3) so the wisps go
  broad, and the lavender is a band along each cloud's UNDERSIDE (no cloud just below = shade), not
  "cloud above" (that put lavender in the middle and read as marble).
- `cel_shade_bias` -0.25 (spec said ~30-40% shadow; -0.15 barely moved), `haze_density` 0.0025.
- Ledges at the jump grid read by value without BG lines; the thin-line fallback was not needed.
