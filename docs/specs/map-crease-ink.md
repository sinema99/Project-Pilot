# Spec: map crease ink

> **Status:** built 2026-09-09, **played 2026-09-28, feels good**. Verified on the real Forward+ renderer by
> screenshot, not by eye in motion. Three claims in the first draft of this spec were wrong and
> were corrected against the running build; all three are marked **[corrected]** below. The
> third correction, on 2026-09-09 after the first look at the build, is the largest: the pass
> drew a line of *variable* width, and fixing that replaced the core of the technique. See
> part 3.
> **Scene:** `scenes/trial.tscn` (map = `assets/mission1.glb` + `assets/TrainingV.glb`).
> **Runs alongside:** `shaders/cel/cel-shader-base.gdshader` (the flat colour) and
> `shaders/cel/outline.gdshader` (the inverted-hull silhouette). Neither changes.
> **Related:** `docs/specs/cel-look-rollout.md` — this brings back the one thing the
> retired Moebius compositor did that the cel hull does not, and only that.

## Problem statement

The map is a blockout, coloured **one flat swatch per Blender material slot**
(`apply_stylized.gd`, `derive_from_surfaces = true`). A room is therefore several walls,
a floor and a ceiling all painted the same value, and the cel shader gives them nothing
to separate with:

1. **The cel bands do not fire on a corner.** `cel-shader-base.gdshader` quantises
   `dot(N, L)` through `diffuse_curve`, a hard 2-band ramp. Two walls of one room meeting
   at 90 degrees can easily land in the same band under a single sun, at which point the
   corner is *invisible* — one uniform rectangle of colour where the player needs to read
   a wall, an edge, and another wall.
2. **The hull outline only draws silhouettes.** `outline.gdshader` is an inverted hull:
   it extrudes along the vertex normal and shows only where the expanded shell escapes
   past the real one — i.e. against whatever is *behind* the object. Interior creases,
   where geometry continues on the far side of the edge, never escape and are never inked.
   That is not a bug in it; a hull cannot do creases.
3. **This is a parkour platformer now** (`docs/game-overview.md`, 2026-09-08). The player
   is reading geometry at speed to decide where to land. An unreadable corner is not an
   art problem, it is a movement problem.

The retired Moebius compositor *did* ink these ("the hub's crease lines",
`docs/worklog/2026-08-27.md`) and went away with the art direction, not because it failed.

## The rule

**A third pass on the map material inks a thin black line wherever the surface it is
drawn on bends away from itself, and nowhere else.**

Three properties fall out of that sentence and they are the whole design:

- **On the map material** — so it is scoped by material assignment, not by a screen-space
  test. It never touches pilot9, EXIA, Setsuna or the sky, because they are not on
  `cel_ground.tres`. This is what makes "only on the map" free.
- **Bends away from itself** — a *crease* test, not a depth-step test. Depth steps are
  silhouettes and the hull already owns those.
- **And nowhere else** — a flat wall must stay clean at every viewing angle, including
  the grazing ones. Naive depth-difference edge detection fails exactly here, and that
  failure is what made the last screen-space attempt unshippable (moire across the whole
  terminator, `shadow-ink-technique`, abandoned 2026-08-31).

### 1. The test is a tangent-plane deviation, not a normal-buffer Sobel

For the fragment being drawn, `fragment()` already hands us the plane of the surface:
`VERTEX` is its view-space position and `NORMAL` its view-space normal. So take taps in a
cross around `SCREEN_UV`, reconstruct each tap's view-space position from `DEPTH_TEXTURE`,
and measure how far it sits **off the centre fragment's tangent plane**:

```glsl
vec3 tap_view(vec2 uv) {                       // official Godot 4 reconstruction
    float d = texture(depth_tex, uv).x;        // reverse-Z: 0.0 == far plane / sky
    vec4 v = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
    return v.xyz / v.w;
}
float deviation = dot(tap_view(uv) - VERTEX, NORMAL);
```

`deviation` is **zero on any flat surface at any angle**, which is the entire reason to do
it this way. A raw depth delta is large on a flat wall seen edge-on, and that is what
hatches everything; a plane deviation is not. It also needs no normal buffer, so
`hint_normal_roughness_texture` and its MSAA caveats stay out of the build.

### 2. Every measure is divided by a real 3D distance, never by a pixel footprint — **[corrected]**

The first draft divided the deviation by the *pixel footprint* (how much world space one
pixel covers at this depth, from `PROJECTION_MATRIX`) to get `tan(dihedral angle)`. **That
was wrong, and wrong in a way that made the first build unusable: it inked every floor in
the scene solid black.** On a surface seen at a grazing angle one pixel spans metres of that
surface, so a deviation of even a millimetre, divided by a footprint of a few millimetres,
reads as a vertical cliff. The whole ground plane was a cliff.

The fix is to divide by an **actual 3D distance** instead. Two taps go out along the same
screen direction, at `r` and `2r` pixels; the segment **between them** lies wholly on the far
face, so its tilt off this fragment's plane is the corner's own dihedral angle:

```glsl
vec3 seg = tap_view(uv + 2.0 * step) - tap_view(uv + step);
float bend = dot(seg, NORMAL) / length(seg);   // sin(dihedral angle), signed
```

That is the sine of the angle between the far face and this tangent plane. It is exactly zero
on a flat surface at **every** viewing angle, by construction rather than by tuning, because
the denominator grows in step with any grazing-angle stretch in the numerator. It is also
dimensionless and scale-free, so a corner reads the same at 2 m and at 80 m, and it needs no
projection matrix at all. Thresholds are therefore `sin(crease_angle_deg)`.

Taking it *between the two taps* rather than from the centre fragment matters: measured from
the centre, the same corner reads shallower the further away it is, which is precisely the
coupling part 3 exists to break.

### 3. Width comes from a measured distance to the crease, not from the angle — **[corrected]**

The first build thresholded the sharpness measure directly and inked wherever it was over the
bar. That draws a line, but **a line of variable width**, which is what the first play-through
of the build showed:

> Take a fragment `k` pixels from a crease and tap `r` pixels towards it. The tap lands on the
> far face, `(r - k)` pixels past the corner, so its elevation off this plane grows as the
> fragment approaches the corner. Thresholding that elevation inks a band whose edge falls
> wherever `sharpness x (r - k)` happens to cross the threshold — so a 90-degree corner inks
> wider than a 30-degree one, and a corner between a face-on wall and a grazing floor inks
> wider on one side of itself than on the other.

Measured off a still of `trial.tscn`, along a **single straight** 90-degree interior corner,
that shipped a line varying from 0.90 px to 1.49 px (sigma/mean 17%) — visibly beating and,
at the shallow end, breaking into dashes.

So sharpness now decides only *whether* an edge is a crease, and the width comes from an
independently measured **screen-space distance to it**. The same two taps give it. Past the
corner the far face's elevation grows linearly with screen distance, so with the crease `k`
pixels away and taps at `r` and `2r`:

```
h_near = c * (r - k)     h_far = c * (2r - k)     q = h_far / h_near
=>  k = r * (q - 2) / (q - 1)
```

The growth rate `c` — the sharpness of the corner, and the foreshortening of **both** faces —
divides out of the ratio. `k` comes back in pixels and in nothing else. The ink is then
`1 - smoothstep` over `k` against a fixed pixel half-width, so the drawn weight is constant by
construction. Same still, same corner, after: **1.70 px to 1.91 px, sigma/mean 3.3%**, and two
lines of different orientation in the same frame agreeing to within 0.5%.

Both faces of a corner ink their own side of it and meet at the crease, so each paints
`line_width_px / 2`.

#### Diagonal creases need the two axis distances composed, not the nearer one

A cross only ever measures along x and y, and a 45-degree crease is a factor of sqrt(2)
further away along both axes than it really is. Taking the nearer axis distance raw would draw
every diagonal corner thinner than every axis-aligned one — the anisotropy is small but it is
exactly the kind of unevenness this part is about. A straight line at perpendicular distance
`p` with axis intercepts `a` and `b` satisfies `1/p^2 = 1/a^2 + 1/b^2`, which is exact at any
screen orientation and is what the shader uses. An axis that found no crease contributes 0 and
drops out, which is the right answer for a crease running parallel to it.

#### It is in pixels, like the hull

`outline.gdshader` offsets its hull by `outline_width / 2` **pixels** in clip space, so its
silhouette is a constant pixel weight at any resolution and any distance. The crease now
matches that, and `line_width_px` defaults to `2.0` for the same reason: at the project's
`outline_width = 4.0` the hull draws 2 px. An earlier version scaled the tap radius by
`VIEWPORT_SIZE.y / 1080.0`; that is gone, because the hull does not do it and the two lines
are supposed to be the same pen.

### 4. Separate objects are rejected by a relative depth jump — **[corrected]**

The first draft rejected a tap whose slope exceeded `tan(silhouette_angle_deg)`, and a later
attempt rejected one further than N pixel-footprints away. Both depended on that same
footprint, and **the footprint came out orders of magnitude wrong in this pass** — measured
against the running build, it silently rejected every tap in the scene, so the shader drew
literally nothing while still compiling and running. The whole quantity is gone from the
shader; the only pixel quantities left are `k` and the line width itself, and nothing at all
is measured in metres.

What replaced it is a ratio, which needs no projection: a tap is discarded when its depth
differs from this fragment's by more than `max_depth_jump` (0.25) **as a fraction of that
depth**. Scale-free, so it behaves the same at 2 m and at 200 m. Also discarded is any tap
on the sky (`depth <= 0.0` in reverse-Z). A direction needs **both** of its taps to survive,
since the pair is read as two samples of one far face. What this buys:

- The roofline against the sky stays a single hull line instead of a doubled one.
- **pilot9 standing against a wall is not outlined twice.** He is a large relative depth jump
  from the wall's point of view, so the wall's own ink pass rejects him and his hull outline
  is the only line there. Verified by screenshot: the ground behind him carries no second
  silhouette.

### 5. Convex creases are held to a stricter bar than concave ones

`bend > 0` is a concave corner (floor meeting wall — the far face rises above the plane).
`bend < 0` is convex (the outside corner of a pillar). Both get inked, but the convex
threshold is multiplied by `convex_scale` (default 1.5), because a tightly curved mesh reads
as a shallow convex corner and is the one false positive this test still has. Raise it if a
rounded mesh starts smudging; the blockout has none today.

### 6. The line is soft-edged and fades out with distance

Two different `smoothstep`s, and they are worth keeping apart:

- **Coverage** — `1 - smoothstep` over the distance to the crease, one pixel of feathering at
  the line's edge. This is what makes the line antialiased. A hard `step` here aliases and
  crawls, which was logged the last time round and is not being relearned.
- **Confidence** — a smoothstep on the *angle*, so a corner near `crease_angle_deg` fades in
  over a few degrees instead of popping. It multiplies the alpha and never touches the width,
  which is the whole point of part 3: a marginal crease draws faint, not thin.

Beyond `fade_start_m` the alpha ramps to zero by `fade_end_m`, so a distant room does not
turn into a wire mesh of its own corners. Defaults are set against `trial.tscn`'s
`directional_shadow_max_distance = 80` and its fog, by eye, not linked to either.

## Files

| Path | What |
|---|---|
| `shaders/cel/crease.gdshader` | new. The pass. `shader_type spatial; render_mode unshaded, blend_mix, cull_back, depth_draw_never;` |
| `resources/cel_crease_material.tres` | new. One `ShaderMaterial` on that shader, sibling of `cel_outline_material.tres` |
| `resources/cel_ground.tres` | edit. Its `next_pass` becomes the crease material; the crease material's `next_pass` becomes `cel_outline_material.tres` |
| `tests/test_map_crease_ink.gd` | new. Wiring only — see **Test coverage** |

`cel_character.tres` is **not** touched. Characters keep base + hull, exactly as today.

### Why the chain order is base → crease → hull

`next_pass` re-renders the same mesh with a wholly separate shader, vertex stage included,
so the hull's extrusion cannot leak into the crease pass whichever way round they go. The
order is chosen so the **hull draws last and therefore over the crease**: the silhouette is
the bolder, more important line, and nothing thin should be allowed to sit on top of it.

## Dials

All plain material uniforms except the colour. There is exactly one crease material in the
project, so these do not need to be shader globals the way `outline_width` does.

| Uniform | Default | Meaning |
|---|---|---|
| `crease_angle_deg` | `28.0` | minimum dihedral angle that gets a line. Below ~20 the blockout's own tessellation starts showing |
| `max_depth_jump` | `0.25` | a tap whose depth differs from this fragment's by more than this **fraction of that depth** is a separate object, not a corner — discarded, left to the hull |
| `convex_scale` | `1.5` | convex creases must clear `crease_angle_deg * this`. See part 5 |
| `line_width_px` | `2.0` | **total drawn width in pixels**, at any resolution and any distance. Each of the two faces paints half. Matches the hull's `outline_width / 2` = 2 px. See part 3 |
| `fade_start_m` | `45.0` | full strength up to here |
| `fade_end_m` | `120.0` | gone by here |
| `ink_opacity` | `1.0` | master alpha, for backing the whole effect off without retuning the angles |

Colour is the existing **`global uniform vec4 outline_color`** from `project.godot`
`[shader_globals]`, reused rather than redeclared, so the crease and the silhouette can
never drift to two different blacks.

## A cross, not a ring — but two taps deep

Four directions (`+`), not a ring of eight. The map is axis-aligned boxes; its creases are
horizontal and vertical in screen space far more often than not, which is the case a cross is
best at. Eight *directions* would double the cost to improve diagonal corners the blockout
barely has, and the intercept composition in part 3 already recovers their width. Revisit if a
curved or rotated map ever ships.

Each direction is two taps deep rather than one, at `r` and `2r` pixels, which is what makes
the width constant. Eight taps total. `r` is derived from `line_width_px` — just past the
line's own edge — and **rounded to whole pixels**, because `filter_nearest` would otherwise
snap the taps to texel centres and skew the very ratio `k` is read from.

## Depth-test behaviour, and the fallback if it misbehaves

The pass is coplanar with geometry that has already written depth, so it ships with
`depth_draw_never` and Godot's default depth test, which passes at equal depth.

If the build shows z-fighting, or whole faces of ink dropping out, the fix is **not** to
nudge a bias. Switch to `render_mode depth_test_disabled` and do the depth test by hand:

```glsl
if (texture(depth_tex, SCREEN_UV).x > FRAGCOORD.z) discard;   // reverse-Z: greater == nearer
```

which is exact, has no bias to tune, and costs one tap that is already being fetched.

## What this does not do

- **It does not ink colour boundaries.** Two differently-coloured Blender slots on one
  flat wall get no line between them; the colours themselves are the separation. Only
  *geometry* creases are inked. If a slot boundary needs a line, that is a modelling
  change (put a real edge there), not a shader change.
- **It does not ink cast-shadow edges.** That is `shadow-ink-technique`, abandoned
  2026-08-31, and nothing here revives it.
- **It does not replace the hull.** Silhouettes stay the hull's, and the map still needs
  the hull for its outer edge against the sky.
- **It does not remove the welded-normals dependency** for the *hull* — but the crease
  pass itself has **no normals requirement at all**, since it reads the depth buffer
  rather than the mesh's normals. A blockout with hard split edges creases correctly on
  import, untouched.
- **It does not run on characters, the sky, or the UI**, by construction.

## Cost

`apply_stylized.gd` duplicates the base material once per Blender slot and the duplicate
is **shallow** — `next_pass` is shared by reference — so there is one crease material
instance no matter how many slots the map has, and tuning a uniform tunes all of them.
Draw calls are a different story: the map is already drawn twice per slot (base + hull)
and becomes three times. Measure on `mission1.glb` before assuming that is fine.

Eight depth taps per fragment, not four — the constant-width fix costs a second tap in each
direction. Each is a fetch plus a `mat4` multiply, on a pass that covers the map and nothing
else. If it ever needs trimming, the far tap of each pair is the one carrying both the angle
and the ratio, so the pair cannot be split; drop to two directions before dropping to one tap.

## Test coverage

Headless (`--headless`) uses the dummy renderer and **never compiles shaders**, so nothing
about the look can be asserted in `tests/`. What is worth pinning, because each of these
fails silently and leaves a game that still runs:

- `shaders/cel/crease.gdshader` loads as a `Shader`.
- `resources/cel_crease_material.tres` loads and its `shader` is that file.
- `cel_ground.tres`'s next_pass chain contains the crease material **and** still contains
  `cel_outline_material.tres` — the regression being one pass silently replacing the other.
- `cel_character.tres`'s chain does **not** contain the crease material.
- Every dial above exists as a uniform with a default, so a rename cannot quietly leave a
  material setting a parameter that no longer exists (Godot stores unknown parameter names
  without complaint — see the `set_shader_parameter("color", ...)` note in
  `apply_stylized.gd`).

Headless is worth more here than the "no shaders compile" line suggests: the dummy renderer
**parses** shader source, and it caught a real compile error on the first run — Godot's
built-ins (`INV_PROJECTION_MATRIX`) exist only in the `vertex`/`fragment` entry points and
cannot be named inside a helper function. It is passed in as a parameter for that reason.

What headless cannot catch is everything that made this build hard, so it was checked by
rendering `trial.tscn` on the real Forward+ renderer and reading stills. Worth knowing if
this is ever debugged that way again: **`unshaded` output still goes through the Filmic
tonemap**, so a debug value written to `ALBEDO` cannot be read back off a screenshot as a
number. Encode diagnostics as thresholds (black/red/yellow/white bands), which survive any
monotonic tonemap, rather than as a linear ramp.

### Measuring line weight off a still

Line weight is the one thing about the look that can be checked without eyes, and it is worth
knowing how, because "is this line even?" is hard to answer by staring at it:

Scan across the line, estimate the un-inked background on each side, and integrate
`coverage = (background - pixel) / background` along the scan. That integral is the line's
footprint in full-coverage pixels; multiply by the sine of the line's angle to the scan axis
for the perpendicular width. **Do it in linear light** — the still is sRGB-encoded, and reading
coverage straight off the encoded values makes every line measure about 35% thinner than it is
drawn. Godot's tonemap sits on top of that and is not invertible from a screenshot, so absolute
widths still read a little low (a drawn 2.0 px measures ~1.8); compare like with like and read
the *spread*, which is the number that matters.

That is how the before/after in part 3 was arrived at: sigma/mean 17% -> 3.3% along one
straight corner.

### Playing it

The look is judged by playing `trial.tscn`, per `spec-before-build-user-does-qa`. Named
things to look at: an interior corner of a mission1 room at 5 m and again at 60 m (line
weight must not change), the same corner seen head-on and then nearly edge-on (must not
change), a 90-degree corner next to a shallow ramp corner (must be the same weight, only the
shallow one may be fainter), a corner running diagonally across the screen next to one running
vertically (must be the same weight), a wall seen at a grazing angle (must stay clean), and
pilot9 standing flat against a wall (must have exactly one line around him, not two).
