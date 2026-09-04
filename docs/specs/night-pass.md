# Spec: Night Pass — the HUB after dark

> **⚠ Superseded / paused (2026-08-30).** This spec claimed `scenes/test2.tscn`, which has
> since been repurposed for the Ghibli/BOTW art-direction experiment — see
> [ghibli-pass.md](ghibli-pass.md). The night pass is **not built** and is on hold. If it
> resumes it will be rebuilt on top of whatever the Ghibli pass settles, or in its own
> scene. Nothing below has been implemented; keep it as the design of record for a future
> night pass, not as a description of the current `test2`.

Last updated: 2026-08-29

> **Purpose:** take the Moebius/Sable pipeline, already validated in daylight, and produce a
> **night** version of it in `scenes/test2.tscn`. The fiction the lighting has to serve: the
> HUB is a **half-destroyed, half-rebuilt base of operations for a military robot outfit**.
> It should read dark, cold and quiet, with the base's own work lighting as the only warmth.
> This is the "night pass" that [moebius-art-direction.md](moebius-art-direction.md) defers
> to Phase 2. It is an art-direction pass, not a day/night *cycle*.

---

## Problem Statement

`test2.tscn` currently ships the daytime environment: a warm cyan sky, a 1.6-energy warm
sun, warm sand fog, and materials whose ambient fill was tuned so the hub's interior stays
readable under that sun. The result is bright, open and neutral — which is the wrong mood
for a wrecked forward base. The hub reads as a greybox in a desert at noon, not as a place
where somebody strung up work lamps over the rubble.

Nothing about the pipeline needs to change to fix this. The look is almost entirely a
question of what the environment, the key light and the per-material ambient are set to.
The two real gaps are (1) nothing separates a dark silhouette from a dark background, and
(2) the scene has no *practical* lights, which is what would sell "somebody is rebuilding
this."

## The Target Look

- **Deep, cold and legible.** Dark enough to read as night, never so dark the player cannot
  tell where the floor is. Traversal readability is still the rule the day pass was built
  on, and the night pass does not get to break it.
- **One cold key, many warm practicals.** A high moon supplies a dim blue-white key that
  describes large shapes and casts the same hard cel shadows the sun did. Everything warm in
  the frame comes from the base's own lamps.
- **Pools of light, softly edged — for now.** A lamp's distance falloff arrives through
  `LIGHT_COLOR`, not `ATTENUATION`, so `stylized.gdshader` never quantises it: the *terminator
  on each surface* is still hard-stepped, but the pool a lamp casts on the floor fades
  smoothly, which is the one un-Sable thing in this pass. Quantising it would mean banding
  the incoming light magnitude, which cannot be done without also re-tuning the day scene
  that shares the shader. Left as a known deviation; see Out of Scope.
- **Story through light colour.** Warm sodium = the parts crews are working on. Red beacons
  = the parts still wrecked and cordoned off. Cold cyan = the powered, rebuilt technology.
  Three light colours, each meaning one thing, so the base reads as being in mid-repair.
- **Silhouettes hold.** Setsuna gets a rim so she never dissolves into a dark wall.

## Decisions

### 1. Sky and moon

Same `gradient_sky.gdshader`, night colours. Four hard bands, indigo at the horizon falling
to near-black at the zenith. The sun disk becomes the moon: smaller, tighter, pale
blue-white. The disk tracks `LIGHT0_DIRECTION`, so it stays welded to the key light for free.

| | Day | Night |
|---|---|---|
| horizon | `#EBD9B4` | `#574F6E` dusty violet |
| mid | `#9FD3DE` | `#3B3654` |
| upper | `#78BFD1` | `#262340` |
| zenith | `#4FA6C4` | `#16142B` near-black indigo |
| disk size / softness | 0.04 / 0.02 | 0.018 / 0.012 |
| disk colour | warm | `#E8EEFF` cold |

**No stars.** The banded sky has no star layer and inventing one is a separate piece of
work (it wants to be stepped and hand-placed, not a noise field, or it fights the grain).
Flagged, not built.

### 2. Key light

The `Sun` node becomes `Moon`: `#A9BEE8` at **energy 2.2** (against the day sun's 1.6 warm
white — a cold, heavily-tinted key needs more raw energy to land the same read), same pitch
as the day sun with the **azimuth swung ~120°** so the shadow direction visibly changes
rather than just dimming. Shadows stay **on** and stay hard — a dim key still has to
describe the ground plane. Shadow max distance pulls in with the fog.

The hub's north face ends up unlit, filled by ambient only: correct for a moon on one side,
but it means the entrance elevation reads as a black mass. Swinging the Moon's yaw is the
one-drag fix if that face should catch light instead.

### 3. Fog

Depth fog recoloured to the horizon band (`#5C5680`) and pulled **much** closer —
25 m → 170 m, against the day's 40 → 220. Night fog is doing more work than day fog: it is
what stops the far half of a 300 m ground plane from being a flat black void, and it is what
makes the far side of the base read as distance rather than as nothing. Height fog keeps
pooling haze in the hub's lower levels, same as day.

The fog colour has to sit **lighter than the surfaces it eats**, or it is not haze, it is a
void: the first pass used the sky's dark mid band and turned the whole far field black.

### 4. Ambient, and the `shadow_floor` trap

`stylized.gdshader` owns ambient (Godot's is disabled inside the shader), so night ambient is
a per-material edit: a moonlit blue `#6E85B8` onto up-faces, a dark violet `#4A3D45` onto
down-faces, at `ambient_energy` 1.0 (ground) / 1.7 (hub interior) / 1.1 (Setsuna).

Ambient is the single most sensitive number in the pass. It is multiplied by albedo, and the
night albedos are already dark, so a value that *looks* like a reasonable night blue on the
colour picker lands two orders of magnitude under readable. Tune it against the render, not
against the swatch.

**`shadow_floor` must go to 0 on every material in this scene.** The floor is applied *per
light, and after attenuation*, so a material with `shadow_floor = 0.35` receives that fill
from **every light in the scene regardless of distance** — an omni 200 m away lights it as
strongly as one directly overhead. That is invisible in the day scene, which has exactly one
light, and it floods everything the moment practicals are added. So:

- day: `shadow_floor` carries the interior fill (hub `0.35`), one light, works fine
- night: `shadow_floor = 0` everywhere; interior fill comes from `ambient_energy`, which is
  light-count-independent, and shaping comes from the practicals

The shader is **not** changed to fix this. Attenuating the floor would also kill it inside
cast shadows, which would re-crush exactly what the day pass raised it to fix.

### 5. Rim light — the deferred piece, now built

`stylized.gdshader` gains the rim light the art-direction spec defers to this pass: a
view-space fresnel term, **stepped with the same `band_softness`** as the cel bands (so it
reads as flat shape next to the ink, not as a soft glow), added through `EMISSION` so it
survives on surfaces no light reaches. Uniforms: `rim_enabled` (**ships false**),
`rim_color`, `rim_threshold`, `rim_strength`.

Not keyed to the light direction: `fragment()` has no `LIGHT`, and a uniform rim is what
actually solves the problem here, which is silhouette separation against a dark background
rather than physical plausibility.

Enabled on **Setsuna's body materials only** — not on the hub (a rim on every wall edge is
line noise, and the compositor already draws those edges) and not on the black `Highlights`
panels (they are the bezels around the screens; a glowing bezel eats the screen).

### 6. Practical lights

A `Lights` node holds the base's own lighting. Everything is `shadow_enabled = false` except
the two floodlight masts — shadow-casting omnis are the expensive thing here, and the cel
bands hide their absence well.

| Role | Colour | Type | Energy / range / attenuation | Reads as |
|---|---|---|---|---|
| Corridor + work lamps (8) | `#FFC385` sodium | Omni | 55 / 22 / 0.6 | crews are working here |
| Hazard beacons (3) | `#E24B32` | Omni | 20 / 16 / 0.9 | still wrecked, cordoned off |
| Powered tech (2) | `#4FD8E8` | Omni | 28 / 18 / 0.8 | rebuilt and running |
| Floodlight masts (2) | `#DCE8FF` | Spot, straight down, shadows on | 60 / 34 / 0.5 | the main work area |

**Those energies are not typos.** Godot scales omni/spot energy by `1/4π` and its falloff is
`distance^-attenuation`, so a lamp 6 m up reaches the floor at roughly 1% of its nominal
energy. Anything in the 1–5 range — the number that feels right next to a DirectionalLight3D
at 1.6 — is invisible. Keep `attenuation` low (0.5–0.9) and the energy in the tens.

**Placement came from a raycast probe, not from guessing.** `HUB_blockout.glb` is a single
mesh with unapplied scale, so the interior was mapped by casting rays down and up on a 2.5 m
grid to find deck height and headroom. The usable interior is narrower than the hub's bounds
suggest: a ~7 m corridor on `x ≈ 0` running `z +38 → −40`, a large hall on the east side
(`x 12…50`, `z −8…+38`), a small west pocket (`x −10…0`, `z 0…−8`), and an open south end
(`x 20…45`, `z −40…−50`). Everything else inside the footprint is solid. The rig lights those
four spaces; the first attempt, placed against the hub's outer bounds, was entirely buried
inside geometry and lit nothing.

### 7. Deliberately unchanged

- **Glow stays off.** The screens spec and the art-direction spec both assume no bloom, and
  the screen shader's `track_level` exists precisely because there is no glow to lean on.
  Night is the obvious moment to want it — but turning it on changes how *every* emissive
  surface reads, so it is its own decision, not a side effect of this pass.
- **The compositor.** Outline, wobble and grain are unchanged. The line colour is already
  pure black in this scene and stays that way.
- **`test.tscn`** keeps the day look, unchanged, as the reference to compare against.
- **`main.tscn`** is untouched, per the same rule the day pass followed.

## Validation

Per the project's usual loop: automated tests cover the shader's uniform contract and the
scene's wiring (they can prove `shadow_floor` is 0 everywhere and that the rim ships off;
they cannot prove it looks like night). The developer plays `test2.tscn` and judges. The
worklog entry gets written after that session.

## Out of Scope

- A day/night **cycle** (time-of-day driver, animated sun/moon, per-zone fog swaps).
- Stars, moon phase, clouds.
- Volumetric fog / god-rays off the floodlight masts — Phase 2 in the parent spec.
- Any hub *geometry* for the destroyed/rebuilt fiction (scaffolding, rubble, tarps, cable
  runs). This pass lights the blockout that exists; it does not model debris.
- Emissive window/panel materials on the hub itself.
- **Hard-edged light pools.** Would need an opt-in uniform that quantises the incoming light
  magnitude in `light()`. Worth doing if the soft pools read wrong in play, but it is a
  shader change with day-scene blast radius, not a lighting tweak.
