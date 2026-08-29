# Spec: Moebius / Sable Art Direction

Last updated: 2026-08-27

> **Purpose:** define the target visual style for Project Pilot (Mech Delivery Prototype)
> and the concrete Godot rendering pipeline that produces it. The reference is the game
> **Sable** (Shedworks, 2021) and, behind it, the line art of **Moebius** (Jean Giraud).
> This spec is the outcome of a design grilling session (2026-08-27). It covers the
> *look* and *pipeline*, not asset content.

---

## Problem Statement

Project Pilot is an early prototype with no committed art direction: greybox hub, a
placeholder box mech, an untextured character, and a photographic night-sky HDRI. Every
asset from here on — zones, the hub, Exia, props, landmarks — needs a single coherent
visual target to be built against, and the engine needs a rendering pipeline that
produces that target consistently across hand-modelled geometry with minimal per-asset
setup. Without this, art gets authored blind and the "open-world traversal game full of
secrets" pitch has no visual identity.

## The Target Look

Faithfully reproduce Sable's recipe first; earn the right to diverge afterward.

**Sable's pillars, as analysed:**

1. **Uniform black outlines.** Pen-like, fixed screen-space thickness (deliberately *not*
   variable brush weight). Implemented as a screen-space edge-detection post-process over
   depth + normals. Lines fade with distance to kill pop-in. Reviewers describe Sable's
   lines as "entirely single-pixel."
2. **Flat colour.** Low-poly models, single flat albedo or simple gradients. No PBR, no
   tiling textures, no surface normal maps. Detail reads through silhouette + line, not
   texture.
3. **Cel shading, kept deliberately.** Hard-stepped light/shadow. Sable did *not* go fully
   flat — real light and shadow are retained specifically for **traversal readability**
   (shadows tell you where your feet sit on a slope). This matters more for Project Pilot
   than for Sable because the player is piloting a mech across that terrain.
4. **"Dotting."** Comic/bande-dessinée halftone dots in shadow areas instead of smooth
   gradients. Used with restraint.
5. **Distance fog.** Per-biome, time-of-day-linked. Called "really, really key" for
   mid/long-range readability — flattens the far field into a clean coloured horizon band.
6. **Print-grade post.** Film grain that updates every ~10 frames (paper tooth, not
   crawling TV static), plus saturation / contrast / colour adjustments. Painted gradient
   skies with simple clouds.

**Influences behind Sable:** Moebius line art, Studio Ghibli, architect Carlo Scarpa. The
desert setting was partly a scope decision ("we knew we couldn't make a really detailed
open world").

**Project Pilot divergences from Sable, already decided:**

- **Time of day:** Project Pilot targets **daytime** first. Get the day look right, then
  do a night pass. (Sable is a full day-night cycle.)
- **Setting:** mech-traversal, not a desert wanderer. Palette and landmark language will
  drift toward Project Pilot's own identity *after* the faithful-copy pass is validated.

## Fidelity Target

- **First build:** copy Sable's recipe as closely as the pipeline allows — including
  colours (seeded from sampled Sable reference frames).
- **Shipping target:** unmistakably in the Sable/Moebius lineage (flat colour, black line,
  cel bands, dotting), with Project Pilot's own palette and landmark identity.
- **Validation:** the developer opens `scenes/test.tscn` in the Godot editor, walks around
  in it, and judges the look directly. No automated or screenshot-based validation.

---

## Engine Context

- Godot 4.6, **Forward+** renderer (required — the outline compositor needs the depth and
  normal-roughness buffers, which Forward+ provides). Windows.
- Viewport 1920×1080, `canvas_items` stretch.
- Main scene: `res://scenes/main.tscn`. The art pipeline is developed against a new
  `res://scenes/test.tscn` and **not wired into `main.tscn` until the developer approves
  the look.**

---

## The Pipeline

Two cooperating layers plus environment setup:

| Layer | Produces | Mechanism |
|---|---|---|
| **Outline + grain compositor** | Black edge lines; stepped film grain | One `CompositorEffect` (compute), depth + normals edge detect, grain composited in the same pass |
| **Stylized material** | Flat albedo, cel bands, screen-space halftone dotting, optional gradient / specular | One shared `stylized.gdshader` `ShaderMaterial`, assigned via `material_override` |
| **Banded sky** | Posterised gradient sky | `gradient_sky.gdshader` on a `ShaderMaterial` sky |
| **Environment** | Sun, hemisphere ambient, hard shadows, depth+height fog, grade | `WorldEnvironment` + `DirectionalLight3D` settings |

### 1. Outline + grain compositor

- **File:** `scripts/rendering/moebius_compositor.gd` (`CompositorEffect` resource script)
  + `shaders/moebius_outline.glsl` (compute shader). Outline and grain are **one effect,
  one pass chain** — not two effects.
- **Callback:** post-transparent (lines drawn over the resolved colour buffer).
- **Edge sources:** **depth + normals only.**
  - Depth discontinuity → silhouettes.
  - Normal discontinuity (normal-roughness buffer) → creases / corners.
  - Sobel-style 3×3 kernel on each; combine; threshold.
  - **No object/ID buffer** in this phase (see Phase 2).
- **Sky rejection:** samples at infinite/sky depth produce no line; no outline is drawn
  around the sky or where one neighbour is sky.
- **Line weight:** fixed screen-space, **resolution-scaled** (thickness in px scales with
  viewport height so it holds at 4K). Default **1.0 px** — exact-Sable weight. (1.5 gives a
  heavier pen; the tunable is the Sobel tap radius, so heavier also means coarser creases.)
- **Line colour:** default warm near-black **#1A1410**. Tunable to pure black.
- **Distance fade:** line opacity ramps from full to zero between a near and far distance.
  Defaults **60 m → 150 m**. Independent of the fog node; keep the two roughly aligned by
  eye. Guidance, not a hard link.
- **Wobble:** scrolling-noise perturbation of the edge-sample position for a hand-inked
  quiver. **Default 0.5** — roughly a pixel of drift, which against a 1 px pen is a visible
  waver while still reading as a straight line: a steady hand failing to be a ruler, not a
  shaky one. Kept under 1.0 deliberately: wobble in motion is a nausea risk, and past that
  it reads as heat haze instead of ink.
- **Grain:** overlaid noise, **low strength**, **stepped**: the noise field is re-seeded
  every **~10 rendered frames** (tunable interval) rather than per-frame. On by default.

### 2. Stylized material — `shaders/stylized.gdshader`

A `spatial` shader, assigned through `material_override`.

- **Albedo model:** solid `albedo_color` uniform **plus** an optional world-space vertical
  gradient (second colour + up-axis blend) to keep large surfaces from reading dead.
  Gradient strength **defaults to 0** — test-scene materials are flat swatches; turn the
  gradient up per-material only where a surface looks lifeless. Texture sampling is **not**
  in this phase (Phase 2).
- **Cel bands:** tunable step count, **default 3** (lit / mid / shadow). The middle band
  is what makes slopes legible for mech traversal — do not default to 2.
- **Band terminator:** razor-thin `smoothstep`, softness tunable, **default 0.02** — reads
  as a hard step but antialiases so the terminator doesn't shimmer in motion.
- **Shadow floor:** the lowest band's floor, as a fraction of the key light. At **0** (the
  default) an unlit face is lit by the hemisphere ambient alone, which is correct for open
  terrain — dune shadows want to be dark — but crushes anything enclosed: the hub's
  interior receives no sun at all, so every wall of it lands on the darkest band. Raise it
  per-material on interior geometry (hub ships at **0.35**), leave it at 0 on terrain. The
  band edges stay hard; the whole ramp just compresses upward. Applied per light, so keep
  it at 0 on anything lit by more than the key sun.
- **Halftone dotting:** the shadow band renders as a **screen-space** ordered dot matrix
  (locked to the screen like ink on a page; the surface slides underneath). Density ramps:
  thinning toward the lit edge, filling toward full dark. **On by default, low density.**
  Dot scale tunable. No UVs required — works on the greybox hub immediately. Accepted
  tradeoff: dots appear to "crawl" across surfaces as the camera moves (this is what Sable
  does).
- **Specular:** optional hard thresholded white blob (stepped like the bands, gets
  outlined by the compositor). **Off by default** — build now for Exia's "metal" later.
- **Rim light:** **not in this phase.** Deferred to the night pass.
- **Roughness/metal:** all surfaces fully rough, non-metal, including anything
  metallic-looking. Material reads come from shape + line + (later) the spec blob.

### 3. Banded sky — `shaders/gradient_sky.gdshader`

- 3–4 **hard** colour bands, top-to-bottom. Band colours and band heights tunable.
- Optional soft sun disk (position, size, colour tunable).
- **Clouds are Phase 2** (flat cloud decals / sprites).
- Replaces the night `PanoramaSkyMaterial` + `qwantani_night_puresky_4k.exr` in the test
  scene. The EXR stays on disk for the future night pass.

### 4. Environment & lighting

- **Key light** (`DirectionalLight3D`): sun at **~40–45° elevation**, **warm white** (not
  full orange). Angle / colour / energy tunable. Enough shadow length to let the cel bands
  describe the ground without golden-hour route-blackout.
- **Ambient:** **two-colour hemisphere** — sky-tint colour onto upward faces, warm
  ground-bounce colour onto downward faces. Both colours + energy tunable. **SDFGI off.
  Sky reflections off.** No soft GI gradients competing with the bands.
- **Shadows:** **hard-edged** (minimal PCF) to match the band terminators, with the
  directional **shadow-map size bumped** and split distances tuned so the crisp edge
  doesn't stair-step on the hub ramps and terrain.
- **Fog:** Environment **depth fog + height fog**. Depth fog flattens the far field; height
  fog pools a low haze in dune valleys / the hub's lower levels. Fog colour tunable
  per-scene (this becomes the per-zone / per-time knob later). **Volumetric fog is
  Phase 2.**
- **Colour grading:** Godot Environment adjustments only — slight **warm paper tint**,
  modest **saturation lift**, mild **contrast** S-curve. No LUT (Phase 2).
- **Anti-aliasing:** **MSAA 4×** + **FXAA**. **TAA OFF** — temporal AA smears thin
  high-contrast lines and fights the stepped grain. MSAA keeps real geometry edges solid;
  FXAA lightly cleans the screen-space outline and dot stipple without temporal artefacts.

---

## Tunables & Defaults

Everything below is exposed (compositor `CompositorEffect` properties, shader uniforms,
or node properties) so the developer can dial the look while looking at `test.tscn`.

### Outline + grain compositor

| Tunable | Default | Notes |
|---|---|---|
| `line_thickness_px` | 1.0 | screen-space, resolution-scaled; Sable's own weight |
| `line_color` | `#1A1410` | warm near-black; → `#000000` for hard look |
| `depth_edge_threshold` | TBD in editor | depth discontinuity sensitivity |
| `normal_edge_threshold` | TBD in editor | crease sensitivity |
| `fade_start_m` | 60 | full-strength line up to here |
| `fade_end_m` | 150 | line fully faded by here |
| `wobble_strength` | 0.5 | hand-drawn quiver; ~1 px of drift against a 1 px pen |
| `wobble_scale` / `wobble_speed` | 24 / 0.35 | long slow waves; jitter if scale goes high |
| `grain_strength` | low (TBD) | |
| `grain_step_frames` | 10 | re-seed interval |

### Stylized material

| Uniform | Default | Notes |
|---|---|---|
| `albedo_color` | per-material swatch | from master palette |
| `gradient_color` | = `albedo_color` | second colour for vertical gradient |
| `gradient_strength` | 0.0 | raise per-material only where a surface reads dead |
| `band_count` | 3 | do not default to 2 |
| `band_softness` | 0.02 | razor-thin terminator |
| `shadow_floor` | 0.0 | lowest band's floor; raise on interiors (hub = 0.35), leave 0 on terrain |
| `dot_density` | low (TBD) | shadow-band halftone |
| `dot_scale_px` | TBD | screen-space dot size |
| `specular_enabled` | false | hard white blob for Exia later |
| `specular_threshold` / `specular_color` | TBD | only if enabled |

### Banded sky

| Uniform | Default | Notes |
|---|---|---|
| `band_colors[3..4]` | seeded from Sable frames | hard steps |
| `band_heights[]` | TBD in editor | horizon → zenith split points |
| `sun_enabled` | true | |
| `sun_dir` / `sun_size` / `sun_color` | match key light | |

### Environment / lighting

| Setting | Default | Notes |
|---|---|---|
| Sun elevation | 40–45° | warm white |
| Sun energy | TBD in editor | |
| Ambient sky colour / ground colour | seeded from palette | hemisphere split |
| Ambient energy | per-material | ground 0.35; hub 1.1 — enclosed geometry has no sun to fill it |
| SDFGI | off | |
| Sky reflections | off | |
| Directional shadow map size | bumped (e.g. 4096) | fight stair-stepping |
| Shadow blur / PCF | minimal | hard edge |
| Depth fog colour | seeded from palette | per-scene knob |
| Height fog | on, low haze | valleys / hub lower levels |
| Env adjustments | warm tint, +sat, +contrast (mild) | no LUT |
| MSAA | 4× | |
| FXAA | on | |
| TAA | **off** | non-negotiable for this look |

> `TBD in editor` = no sensible number until there's geometry to tune against; set during
> the first `test.tscn` session.

---

## File Layout

```
scenes/test.tscn                        # the test scene (playable)
shaders/stylized.gdshader               # cel bands + dotting + gradient + optional spec
shaders/gradient_sky.gdshader           # banded posterised sky
shaders/moebius_outline.glsl            # compositor compute shader (edge detect + grain)
scripts/rendering/moebius_compositor.gd # CompositorEffect resource script (one effect)
scripts/rendering/apply_stylized.gd     # walks a subtree, sets material_override on every MeshInstance3D
resources/stylized_material.tres        # shared stylized ShaderMaterial (hub + landmark)
resources/moebius_compositor.tres       # Compositor resource referencing the effect
```

- **`apply_stylized.gd`** exists because `material_override` on an imported GLB's root
  `Node3D` does not propagate to its child `MeshInstance3D` nodes. The helper is attached
  in `test.tscn` only — it does **not** modify `scripts/hub_import.gd`, so `main.tscn` is
  untouched. The hub's existing greybox `StandardMaterial3D` (from `hub_import.gd`) is
  replaced by the override in the test scene; its 0.45 grey is superseded by the
  material's `albedo_color`.
- Not an `addons/` plugin — this is project-specific, not distributable.

---

## Blender / Asset Authoring Rules

For every mesh authored against this pipeline:

- **Apply all transforms** before export (scale = 1, rotation = 0), origin sensible
  (on the floor for level geometry). *Pre-existing debt:* `HUB_blockout.glb` still ships
  unapplied scale `(5.32, 5.32, 39.13)` + a `+17.52` origin offset, forcing a manual Y
  counter-offset in `main.tscn`. Fix at the next hub re-export.
- **Hard/soft edge split:** mark sharp edges sharp (split normals / edge-split). The
  normal-based edge detection draws lines where face normals diverge — clean creases in
  the model become clean lines in-engine. Smooth-shade curved surfaces.
- **Flat-shade faces** that should read as facets.
- **Low poly.** Silhouette does the work. No high-frequency surface geometry — it just
  turns into line noise.
- **No baked lighting, no AO maps, no normal maps.** Shading is entirely runtime cel.
- **UVs optional** in this phase — needed only if/when texture sampling (Phase 2) is used.
  The vertical gradient is world-space and needs no UVs.
- **Colour comes from the master palette** (below), assigned as material `albedo_color`,
  not painted into textures.
- **Scale reference (unchanged):** Exia collision 1.6 W × 3.6 H × 1.2 D; on-foot capsule
  0.8 dia × 1.8 tall. Mech routes 3 m+, dismount gaps < 1.6 m.

---

## Colour Palette

**Method:** seed a master palette by sampling ~12–20 key colours from Sable daytime-desert
reference frames, use them in `test.tscn`, then adjust toward Project Pilot's identity
after the developer has seen the look.

**Placeholder swatches** (approximate, from Sable's described palette — *warm desert skew,
cyan midday sky fading toward muted indigo, intentionally flat colours*). **These are
un-sampled guesses — resample against real reference frames before locking:**

| Role | Placeholder | Notes |
|---|---|---|
| Ink / outline | `#1A1410` | warm near-black |
| Sky – zenith | `#4FA6C4` | cyan |
| Sky – mid | `#9FD3DE` | pale cyan |
| Sky – horizon | `#EBD9B4` | warm haze |
| Sand – lit | `#E8C48F` | |
| Sand – mid | `#C99B63` | |
| Sand – shadow | `#8A5E3C` | dot-stippled band |
| Rock – lit | `#C9A98C` | |
| Rock – shadow | `#6E4A3A` | |
| Ambient – sky tint | `#BFE0EA` | hemisphere up |
| Ambient – ground bounce | `#C98F5A` | hemisphere down |
| Fog | `#E7D6B0` | ≈ horizon band |
| Accent (structures / signage) | `#C24A3A` | Sable's warm red |

Locked palette lands in this section once resampled and tuned.

---

## Build Sequence

1. **`git init` + baseline commit.** Initialise the repo, add `.gitignore` (`.godot/`,
   Godot temp), commit the current working state before any art change. Everything after
   is reversible per step.
2. **Banded sky shader** + swap into a throwaway environment — cheapest visible piece.
3. **Stylized material** (bands + terminator + flat albedo; dotting next) on a couple of
   primitives.
4. **Halftone dotting** in the shadow band.
5. **Outline + grain compositor** (depth + normal edge detect; sky rejection; distance
   fade; then grain).
6. **Environment pass:** hemisphere ambient, ~40–45° warm sun, hard shadows + bumped
   shadow map, depth + height fog, Env grade, MSAA 4× + FXAA, TAA off, SDFGI off.
7. **`scenes/test.tscn`:** playable — instance `SETSUNA` (real model + animations) + the
   hub blockout + one landmark primitive (a large tapered pillar / arch for silhouette,
   fog, and outline to act on). `apply_stylized.gd` walks the hub + landmark and sets
   `material_override`. Sun / sky / fog / compositor wired to the scene's
   `WorldEnvironment` + `Camera3D`. **No EXIA.**
8. **Hand to the developer.** They walk around in `test.tscn`, tune the exposed knobs, and
   give the verdict. Only after approval does any of this touch `main.tscn`.

---

## Phase 2 — Deferred

Built into the pipeline as capability (off / absent) or explicitly postponed:

- **Object/ID buffer** for interior & panel lines — needs Exia modelled with panel seams
  that must read.
- **Texture sampling** in `stylized.gdshader` — hand-painted large-shape colour blocking.
- **Stepped specular blob** highlights — turned on for Exia's metal.
- **Rim light** — part of the night pass (silhouette separation against dark backgrounds).
- **Night / day-night cycle** — per-time palette, sun/moon, sky, and per-zone fog swaps.
- **Painted / decal clouds**; **volumetric fog** god-rays.
- **Colour-correction LUT** slot on the Environment.
- **Outline wobble** stepped re-draw (the field currently drifts continuously; stepping it
  the way the grain steps would read as the line being re-inked each frame).

## Out of Scope

- The Blender modelling of zones, the hub, Exia, or landmarks (this spec constrains that
  work; the modelling happens separately).
- Any gameplay, UI, or HUD styling.
- The night pass itself (only flagged here; specified later).
- Performance budgets in numbers — revisit once a real zone blockout exists to profile
  (the compositor and cel material are cheap; the risk area is geometry, per the zone
  spec).

## Further Notes

- Reference: [Sable — Exploration Through Line-Art (Cook & Becker)](https://www.cookandbecker.com/en/article/170/sable-exploration-through-line-art.html),
  [How Shedworks refined the art of Sable in pursuit of readability (Game Developer)](https://www.gamedeveloper.com/marketing/how-shedworks-refined-the-art-of-sable-in-pursuit-of-readability),
  [How is this look achieved? — Sable Steam discussion](https://steamcommunity.com/app/757310/discussions/0/1696049513785363261/),
  [Moebius-Style Rendering — Useless Game Dev](https://uselessgamedev.com/articles/moebius-style-rendering.html).
- Related project docs: [game-overview.md](../game-overview.md),
  [zone-based-map-system.md](zone-based-map-system.md),
  [worklog/2026-08-27.md](../worklog/2026-08-27.md).
