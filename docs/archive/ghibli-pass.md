# Spec: Ghibli / BOTW Pass — `test2.tscn`

Last updated: 2026-08-30

> **Purpose:** shift `scenes/test2.tscn` from the faithful Sable/Moebius comic look toward a
> softer, more painterly **Studio Ghibli / Breath of the Wild** mood — gentle light, a cool
> jungle-ruin palette, atmospheric depth — while keeping the black outline and flat-gradient
> surfaces that already work. The reference is a single piece of concept art: an overgrown
> ruined megacity under a hazy canopy, a small robot on a ledge in the foreground.
>
> This is a **scene-local art-direction experiment**, the same way `test.tscn` is the
> reference the day pipeline is judged against. `stylized.gdshader`, `moebius_outline.glsl`,
> `gradient_sky.gdshader`, `test.tscn` and `main.tscn` are **not touched**. Outcome of a
> grilling session (2026-08-30).

---

## Amendment — 2026-08-30, post-build: HDR panorama sky

After the first build the developer swapped `test2`'s sky and reworked the ambient. This
supersedes parts of Decision 1, Decision 6, the palette table's sky/ambient rows, and the
shader's ambient section:

- **Sky is now an HDR panorama**, not the banded gradient. `assets/citrus_orchard_road_puresky_4k.hdr`
  on a `PanoramaSkyMaterial`. `gradient_sky.gdshader` is unwired from `test2` (still used by
  `test.tscn`, so the file stays). The four sky-band swatches and the sun-disk swatch in the
  palette table no longer apply.
- **The shader's built-in hemisphere ambient is stripped.** `ambient_light_disabled` is
  removed from `render_mode`; the `ambient_sky_color` / `ambient_ground_color` /
  `ambient_energy` uniforms and the `EMISSION = ambient * ALBEDO` line are gone. `EMISSION`
  now carries only the rim. Shadow-side fill comes from the **Environment's sky-source
  ambient**, i.e. the HDR — `ambient_light_source = Sky`, `ambient_light_energy` raised
  0.35 → 1.0 (live dial). The up/down colour split is lost; that was the price the
  developer accepted for HDR-driven fill.
- **Fog warmed** to match the orchard sky: `fog_light_color` `#A9C2BE` → `#F0DCC0` (warm
  pale haze). `fog_sky_affect` stays at 1.0 — drop it toward 0.5 if the fog washes the HDR
  horizon too flat.
- **Known follow-ons:** the HDR has a baked sun that does not line up with the `Sun`
  DirectionalLight3D's shadow direction; and with reflections still off the HDR does not
  show up as specular on the stylized surfaces (intended — they stay matte).

The rest of the spec (the HYBRID ramp, warm/cool shift, breakup, rim, grade, the stone and
moss albedos) stands as written.

---

## Problem Statement

The Moebius/Sable pipeline in `moebius-art-direction.md` is deliberately hard-edged: a
razor-thin 3-band cel terminator, screen-space halftone dots in the shadow band, paper
grain, four hard sky bands, a warm desert palette. It is a faithful copy of *Sable*, and
`test.tscn` should keep being exactly that.

The reference image for this pass is the opposite register. Nothing in it reads as a hard
terminator line — light eases into shadow, and the shadow is *bluer*, not just darker.
Surfaces look hand-painted rather than flat-filled. Depth comes almost entirely from a
luminous haze that desaturates everything past ~40 m. The palette is cool: mossy greens,
weathered blue-grey stone, teal atmosphere, with warm oxide-red banners as the only hot
accent.

`test2.tscn` currently ships the daytime desert environment on the HUB blockout. The task
is to re-dress *that geometry* — no new modelling — so it reads in the reference's mood,
via one new material shader plus scene-local environment tuning.

## What This Pass Is Not

- **Not a new pipeline.** The outline compositor and the sky shader are reused unchanged;
  only their *scene-local settings* move (and the sky's, via the scene's material
  sub-resource, never the `.gdshader`).
- **Not the reference's content.** Foliage, hanging vines, waterfalls, banner meshes, the
  ruined-city silhouette — all asset work, all out of scope here (see *Reserves*). A shader
  pass does not put vines on the hub.
- **Not a change to `test.tscn` or `main.tscn`.** They keep the Sable look as the control.
- **Not the night pass.** `night-pass.md` also claimed `test2.tscn`; it is now shelved (a
  "Superseded / paused" header has been added to it). If the night pass returns it will be
  rebuilt on top of whatever this pass settles, or in its own scene.

---

## The Target Look

- **Soft light, one readable break.** The lit-to-shadow transition is a broad painterly
  wrap, *not* a hard step — but it keeps a single soft quantised plateau at the terminator
  so a mech-scale slope still snaps to a readable value once. `moebius-art-direction.md`'s
  rule that "the middle band is what makes slopes legible" is honoured, just softened.
- **Cool shadows.** Lit surfaces lean warm; shadowed surfaces (and cast shadows) lean
  blue-teal. This colour shift carries as much of the mood as the ramp shape does.
- **Painted, not plastic.** A low-frequency world-space noise mottles the albedo so a flat
  fill reads as brushwork. Subtle; tunable to zero.
- **Depth through haze.** A luminous pale-teal depth fog, pulled close, flattens the far
  field. This is the reference's single biggest depth cue.
- **Edge light on the character.** Setsuna's body gets a soft sky-tinted rim, BOTW-style,
  so she reads against the busier background. The hub does not — a rim on every wall edge
  is line noise the compositor already draws.
- **The black line stays.** The outline is the thing the developer explicitly wanted to
  keep. It is untouched in this spec; its four exposed knobs are tuned live.

---

## Decisions

### 1. Home and scope

`test2.tscn` is repurposed for this pass. The night pass is shelved. The deliverable is:

- **one new spatial shader**, `shaders/stylized_ghibli.gdshader`, used only by `test2`;
- **scene-local retuning** of `test2`'s `WorldEnvironment` (depth fog, grade, ambient
  colour), the sky material sub-resource's band colours, the `DirectionalLight3D`, and the
  six `ShaderMaterial` sub-resources.

No source fork of `moebius_outline.glsl` or `gradient_sky.gdshader`. `stylized.gdshader` is
left alone.

### 2. The light ramp — HYBRID, with a hardness dial

Three ramp shapes were prototyped in `test2` (feathered multi-band / smooth half-Lambert /
hybrid) behind a live switch. The developer walked all three; **HYBRID** read best.

The shipping shader keeps **only** the hybrid ramp:

- a smooth half-Lambert base (`(ndotl * 0.5 + 0.5)²`), so there is no hard terminator;
- **one** soft 3-level quantise blended in around the `0.5` mark, weighted by a `smoothstep`
  knee, so exactly one value plateau survives at the light/shadow line.

`soft_terminator` (0.0–0.6, ships **0.38**) is the exposed **Sable ↔ Ghibli dial**: at
`0.0` the knee collapses to a hard cel step (i.e. back to `stylized.gdshader`'s look); at
`0.5–0.6` it is a broad painterly wrap. This is the one knob to nudge once the palette and
fog are in.

The other two prototype ramps and the `ramp_mode` uniform are **deleted**. So is all the
**halftone-dot** code and its `dot_*` uniforms — the reference has no halftone.

### 3. Warm-lit / cool-shadow colour shift

`light()` mixes the shaded colour between `shadow_tint` (cool) and `lit_tint` (warm) by the
ramp value, then blends that toward white by `1 - warm_cool_strength` so it can be dialled
out. Ships `warm_cool_strength = 0.6` on world geometry, `0.5` on Setsuna.

Because a cast shadow drives `ATTENUATION → 0 → ramp → 0`, cast shadows land on
`shadow_tint` for free — no separate shadow-colour system.

### 4. Subject — reskin, not remodel

The hub geometry, the ground plane, the landmark collider are unchanged. The **palette**
moves wholesale to the reference's cool register (table below). Setsuna keeps her own
colours — `character-coloring.md` owns those and the reference robot is already close.

### 5. Surface breakup

A triplanar value-noise term in `fragment()`: three axis-aligned noise samples of
`world_position / breakup_scale`, averaged, centred on zero. It modulates albedo lightness
by `±breakup_strength * 0.5` and pulls the darkened patches toward `shadow_tint` so it
reads as paint pooling rather than grime. World-space, **no UVs** — the blockout gets it
for free.

Ships `breakup_strength = 0.18` on stone, `0.22` on ground, `0.08` on Setsuna, `0.0` on the
black bezels. `breakup_scale` ships `3.2` world units. `0.0` strength = dead flat.

### 6. Atmospheric depth — Environment fog only

`test2`'s `WorldEnvironment` gets **depth fog** (`fog_mode = FOG_MODE_DEPTH`):

| Setting | Value | Note |
|---|---|---|
| `fog_light_color` | `#A9C2BE` (haze) | must sit **lighter** than the stone, or it reads as a void, not haze (the trap `night-pass.md` hit) |
| `fog_depth_begin` | 15 | live dial |
| `fog_depth_end` | 170 | live dial |
| `fog_density` | 1.0 | depth mode needs this raised from its `0.01` default |
| `fog_sky_affect` | 1.0 | fog the sky-to-ground seam too |

Plus the Environment grade: `adjustment_saturation` 1.12 → **1.0** (the reference is
desaturated overall; global grade can't do selective accent saturation, so the banners get
their punch from their own albedo), `adjustment_contrast` 1.05 → **1.08**.

**No in-shader aerial perspective.** Held as a reserve if the mid-range still reads too
crisp in play.

### 7. Rim light — Setsuna only

The shader keeps the rim term (`rim_enabled`, ships **false**). In `test2` it is enabled on
`ShaderMaterial_char`, `_primary`, `_secondary` (Setsuna's body), with `rim_color`
`#9EB8D9`, `rim_threshold 0.6`, `rim_strength 0.4`. It stays **off** on `ShaderMaterial_sand`
and `_hub` (line noise on the hub) and on `ShaderMaterial_highlights` (the black screen
bezels — a glowing bezel eats the screen, per `setsuna-screens.md`).

### 8. Deliberately unchanged

- **The outline compositor.** `line_color` (pure black in this scene), `grain_strength`,
  `wobble_strength`, `depth_edge_threshold` are all exposed on the `CompositorEffect` and
  tuned live against the render. The grain and wobble arguably fight a painterly look; that
  is a thirty-seconds-into-the-playtest call, not a spec decision.
- **Glow / bloom.** Stays off, scene-wide, as every prior spec has it. A high-`hdr_threshold`
  glow (sun disk and hottest highlights only) is the first reserve if `test2` reads flat.
- **Cast shadows.** Hard (`shadow_blur = 0`). `shadow_blur` and the split blend are live
  dials; the reference's shadows are low-*contrast* (ambient + haze), not soft-*edged*.
- **Setsuna's palette.** Governed by `character-coloring.md`.

---

## Colour Palette — seed

Estimated from the reference image. **A starting point, not a lock** — the same method
`moebius-art-direction.md` used ("placeholder swatches, adjust after the developer has seen
the look"). Values below are the linear RGB written into the `test2` sub-resources; the hex
is the sRGB the picker shows.

Sky and ambient rows are struck by the Amendment — the sky is the HDR now, ambient is
sky-sourced.

| Role | Hex | Lands on |
|---|---|---|
| Stone – lit | `#8A938C` | `ShaderMaterial_hub.albedo_color` |
| Stone – shadow tint | `#9FB9C9` | `_hub.shadow_tint` |
| Moss ground – lit | `#6B7A55` | `ShaderMaterial_sand.albedo_color` |
| Ground – shadow tint | `#586B63` | `_sand.shadow_tint` |
| Haze / fog | `#F0DCC0` | Environment `fog_light_color` (warmed, per Amendment) |
| Lit tint (sun on surfaces) | `#FFF3E0` | every material `lit_tint` |
| Rim (Setsuna) | `#9EB8D9` | `_char/_primary/_secondary.rim_color` |
| Accent – banners | `#B24634` | reserved — no accent meshes in `test2` yet |
| Ink / outline | `#000000` | `CompositorEffect.line_color`, unchanged |

Setsuna's `albedo_color`s (`char` off-white, `primary` tan, `secondary` grey) are **kept as
they are**.

---

## File Layout

```
docs/specs/ghibli-pass.md              new  (this file)
docs/specs/night-pass.md               + "Superseded / paused" header
shaders/stylized_ghibli.gdshader       collapsed to the single HYBRID ramp;
                                       + breakup uniforms; - ramp_mode; - halftone;
                                       - in-shader ambient + ambient_light_disabled (Amendment)
assets/citrus_orchard_road_puresky_4k.hdr   new  (Amendment) — PanoramaSky source
scenes/test2.tscn                      - GhibliModeSwitch node + its script ext_resource;
                                       HDR PanoramaSkyMaterial replaces the gradient sky;
                                       retune Environment (warm fog, grade, sky ambient),
                                       all six ShaderMaterials; rim on the three Setsuna
                                       body materials
scripts/rendering/ghibli_mode_switch.gd   deleted  (+ .uid)
tests/test_ghibli_material.gd          new
```

Untouched: `shaders/stylized.gdshader`, `shaders/moebius_outline.glsl`,
`shaders/gradient_sky.gdshader`, `scripts/rendering/moebius_compositor.gd`,
`scripts/rendering/apply_stylized.gd`, `scenes/test.tscn`, `scenes/main.tscn`,
`scenes/player.tscn`.

---

## The Shader — `shaders/stylized_ghibli.gdshader`

`spatial`, `render_mode blend_mix, depth_draw_opaque, cull_disabled`. Engine ambient is
left **on** (see the Amendment) — the HDR sky is the fill light.

**Uniforms**

| Group | Uniform | Default | Note |
|---|---|---|---|
| albedo | `albedo_color`, `gradient_color` | seed swatch | `source_color` |
| | `gradient_strength` / `gradient_low` / `gradient_high` | 0.0 / 0 / 10 | opt-in vertical gradient, as in `stylized.gdshader` |
| ramp | `soft_terminator` | 0.38 | **Sable(0) ↔ Ghibli(0.6) hardness dial** |
| | `lit_tint` | `#FFF3E0` | warm side |
| | `shadow_tint` | `#9FB9C9` | cool side; also where cast shadows land |
| | `warm_cool_strength` | 0.6 | 0 = no colour shift |
| | `shadow_floor` | 0.0 | per-light floor; raise on interiors, keep 0 on open ground |
| | `band_softness` | 0.02 | AA width on the terminator knee and the rim |
| breakup | `breakup_strength` | 0.18 | 0 = dead flat albedo |
| | `breakup_scale` | 3.2 | world units per noise cell |
| rim | `rim_enabled` | **false** | on for Setsuna's body in `test2` |
| | `rim_color` / `rim_threshold` / `rim_strength` | `#9EB8D9` / 0.6 / 0.4 | |

**Gone from the prototype:** `ramp_mode`, `soft_band_count`, `dot_enabled`, `dot_density`,
`dot_scale_px`, and all halftone code.

---

## Validation

Project's usual loop:

1. Automated tests (`tests/test_ghibli_material.gd`) cover the shader's uniform contract and
   the `test2` wiring — they prove the collapse and the repoint happened cleanly, not that
   it looks like the reference.
2. The developer opens `test2.tscn`, walks it with Setsuna, and tunes the live dials
   (`soft_terminator`, fog begin/end + colour, grade, `breakup_*`, `warm_cool_strength`, rim,
   grain, wobble, `line_color`, `shadow_blur`) against the render.
3. The palette is **locked** in this spec's table once that session is done.
4. Worklog entry written after.

## Tests — `tests/test_ghibli_material.gd`

- **Shader compiles** and exposes the expected uniforms: `soft_terminator`, `lit_tint`,
  `shadow_tint`, `warm_cool_strength`, `breakup_strength`, `breakup_scale`, `rim_enabled`.
- **The collapse happened:** `ramp_mode`, `soft_band_count`, `dot_enabled`, `dot_density`,
  `dot_scale_px` are **absent** from the uniform list.
- **The HDR-sky rework happened** (Amendment): `ambient_sky_color` / `ambient_ground_color`
  and `ambient_light_disabled` are **absent** from the shader source.
- **Spec defaults:** `soft_terminator` = 0.38, `breakup_strength` = 0.18, `rim_enabled`
  ships `false`, `band_softness` = 0.02 (expected values from this spec, read out of the
  source the way `test_case.gd`'s `declared_default*` helpers do).
- **`test2` wiring:** every `ShaderMaterial` sub-resource in `test2.tscn` points at
  `stylized_ghibli.gdshader`; `rim_enabled` is `true` on `ShaderMaterial_char`, `_primary`,
  `_secondary` and `false` on `_sand`, `_hub`, `_highlights`; `ShaderMaterial_highlights`
  keeps `albedo_color` pure black; no node in `test2.tscn` references
  `ghibli_mode_switch.gd`.

---

## Reserves — named, not built

- **Volumetric light shafts.** The reference's most arresting feature. `Environment`
  volumetric fog lit by the sun — its own play-test pass, and it needs canopy geometry to
  cast through, which `test2` does not have yet.
- **High-threshold glow.** Sun disk + hottest highlights only, if the frame reads flat.
- **In-shader aerial perspective.** Distance desaturation + haze tint in the material, if
  Environment depth fog alone leaves the mid-range too crisp.
- **Texture slots** in the shader — hand-painted large-shape colour blocking, once there is
  geometry with UVs.
- **The reference's content** — foliage cards, vine decals, waterfall planes, banner
  meshes, the ruined-city skyline. Each its own spec.

## Known Gaps

- **The palette is guessed.** Estimated off one piece of painterly concert art with its own
  noise and grade. The seed table will be wrong in places; that is what the tune-and-lock
  step is for.
- **`test2` has picked up hand-tuning during prototyping** — the `Sun` energy was raised to
  3.6 and a `SpotLight3D` was added near Setsuna. Both are left in place; whether the
  spotlight stays is a call for the play-test.
- **Grain and wobble are unresolved.** They may read wrong against soft surfaces and get
  cut live, but nothing here decides that.
- **`soft_terminator` interacts with `band_softness`.** The knee width is
  `max(soft_terminator * 0.5, band_softness)`, so at very low `soft_terminator` the
  terminator never goes fully hard unless `band_softness` is also dropped. Intended — a
  fully hard step is `stylized.gdshader`'s job.
