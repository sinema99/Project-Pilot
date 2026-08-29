# Spec: Character Coloring

## Problem Statement

Setsuna renders as a single flat off-white. `ApplyStylizedCharacter` in `scenes/test.tscn`
points `scripts/rendering/apply_stylized.gd` at her `PlayerModel` subtree, and that helper sets
`material_override` on every `MeshInstance3D` it finds. `material_override` replaces *all*
surfaces of a mesh with one material, so a mesh with four material slots renders as one colour —
and `resources/character_material.tres` runs `shaders/stylized.gdshader`, which exposes exactly
one `albedo_color` uniform. One material, one colour, whole character.

This was correct while she was a greybox. It is now the thing stopping her from having skin,
hair, and clothes. Whatever material work happens in Blender is currently discarded on arrival.

## Solution

Blender decides **which faces are which part**. Godot decides **what the shader does with that**.

Setsuna gets a material slot per part in Blender, each carrying a flat Base Color. glTF exports
one surface per material, so she imports as a multi-surface mesh. The applier grows a second
mode: instead of one `material_override` per mesh, it walks each surface, reads the imported
material's albedo, and stamps that colour into a duplicate of the base stylized material, which
it sets via `set_surface_override_material`.

The result is that the palette lives in the `.glb` and every other cel parameter — band count,
halftone density, ambient, shadow floor — stays centralised in one `.tres` that gets art-directed
against the lit scene.

## Blender Authoring Contract

Only two things survive the export and matter here:

- **Material slot names.** These are the key everything else maps on, and they must be stable
  across re-exports. Slot *order* is not stable and is never used. The shipped export uses three:
  `Primary`, `Secondary`, `Highlights`. Matching is case-sensitive, and surrounding whitespace is
  trimmed off — the export's slot is literally named `"Secondary "`, and a key nobody can type
  without an invisible character is not a key.
- **Base Color** on each slot's Principled BSDF, exported as glTF `baseColorFactor`.

Everything else in a Blender material is ignored: node graphs, roughness, metallic, textures,
emission. `stylized.gdshader` forces `ROUGHNESS = 1.0`, `METALLIC = 0.0`, `SPECULAR = 0.0` and
computes its own lighting, so there is nothing for those inputs to feed.

Two constraints carry over from existing work and do not change:

- **Every piece stays rigid-weighted** — 1.0 on a single bone. Splitting geometry to assign a
  material slot must not introduce blended weights, or the outline pass inks the seam.
- **Colour breaks want geometry seams.** `shaders/moebius_outline.glsl` detects edges from depth
  and normals only; it has no albedo or object-ID input. A colour boundary across a flat face
  gets no ink line and reads as a decal rather than a shape. On a box seam the line is free.

## Applier Changes

`scripts/rendering/apply_stylized.gd` gains one exported flag:

```gdscript
@export var derive_from_surfaces := false
```

**False (default) is today's behaviour, byte for byte.** `ApplyStylized` — the hub and the
landmark — keeps setting one `material_override` per mesh. This is not a nicety: the hub's
imported material is the flat grey `hub_import.gd` bakes in, so deriving colours from it would
repaint the whole hub grey and throw away the sand swatch in `stylized_material.tres`.

**True** switches to the per-surface path, and `ApplyStylizedCharacter` sets it. For every
surface of every mesh in the target subtree:

1. Read the imported surface material's `resource_name` — the Blender slot name — and trim it.
2. If that name is in `slot_overrides`, use that material and stop.
3. Otherwise look in a per-pass cache; on a miss, `duplicate()` the base `material` and stamp in
   the imported `albedo_color`, keyed by name so every surface called `skin` shares one material.
4. `mi.set_surface_override_material(i, mat)`.

A surface with no imported material, or one whose material is not a `StandardMaterial3D`, falls
back to the base material unchanged and pushes one warning naming the mesh.

Derived materials get `resource_name = "stylized:<slot>"` so they are identifiable in the remote
inspector while tuning a running game.

### Slot overrides

```gdscript
@export var slot_overrides: Dictionary[String, Material] = {}
```

The escape hatch for a slot that needs more than a colour — hair that wants a heavier
`dot_density`, skin that wants a higher `shadow_floor`. Drop a hand-authored `.tres` in against
the slot name and it wins over the derived material. **None ship in this pass.** The mechanism
exists so that the first slot needing individual treatment is a one-line scene edit rather than a
code change.

### Colour space

`baseColorFactor` is linear and `albedo_color` is a `source_color` uniform that Godot runs
`srgb_to_linear` on at render time, so this spec originally called for
`imported.albedo_color.linear_to_srgb()`. **That was wrong, and the correction is: hand the
imported value straight across, unconverted.**

Godot's glTF importer already does the encoding step itself. Verified against Setsuna's own
export: `Primary` ships `baseColorFactor` `0.07513` and `StandardMaterial3D.albedo_color` reads
back `0.303791` — exactly `linear_to_srgb(0.07513)`. Converting again in the applier would light
everything a stop and a half hot.

This is still the single easiest thing in the change to get backwards, and backwards still
*looks* like a plausible art choice rather than a bug. It gets checked against a known swatch — a
slot authored at a mid grey must derive as that mid grey — not by eye.

`gradient_color` is stamped alongside `albedo_color` with the same value. `gradient_strength` is
0 on the character material so it changes nothing today; setting it means raising the strength
later fades toward the slot's own colour instead of snapping to the base swatch.

### Ownership and clear

The existing pre-save / post-save dance has to keep working — editor-side overrides are stripped
before `test.tscn` is written so they never serialise onto the instanced GLB subtree.

`_applied` becomes a list of `{mesh, surface, material}` entries rather than a flat mesh array.
`clear_now()` sets each surface override back to `null` only where the current override is still
the material this node put there, preserving the existing rule that a hand-changed override is
not ours to reset.

`apply_now()` returns **surfaces touched** in derive mode, meshes touched otherwise. Both are
positive-when-working, which is all `tests/test_pipeline_smoke.gd` asserts.

## Why Not

- **Vertex colours.** One draw call, palette in the mesh, and it would need `COLOR` folded into
  the shader's `ALBEDO`. Rejected because it makes every colour tweak a Blender round trip, and
  because the whole point of `slot_overrides` — per-part cel parameters, not just per-part colour
  — has nowhere to live.
- **Hand-authoring one `.tres` per slot in the Godot editor.** That is `slot_overrides` with no
  derivation, and it puts the palette in two places: the Blender viewport shows one set of colours
  and the game shows another. Deriving by default keeps Blender honest.
- **An import script on the `.glb`.** Would bake the stylized material at import time and skip the
  applier entirely, but re-imports are frequent here and an import script that goes wrong is
  harder to see than a node in the scene tree with a "Re-apply now" button.

## File Layout

```
scripts/rendering/apply_stylized.gd    + derive_from_surfaces, + slot_overrides
scenes/test.tscn                       ApplyStylizedCharacter sets derive_from_surfaces = true
assets/setsuna.glb                     re-exported with material slots
tests/test_apply_stylized.gd           + per-surface cases
```

No new files. `resources/character_material.tres` is unchanged — it stays the base every derived
material duplicates.

## Tests

Added to `tests/test_apply_stylized.gd`, built on an `ArrayMesh` with two named
`StandardMaterial3D` surfaces:

- **Each surface gets its own material, carrying its own albedo.** The core claim.
- **Two surfaces sharing a slot name share one material instance.** Dedup, so a five-box torso
  named `coat` is one material and not five.
- **A slot in `slot_overrides` gets that material, not a derived one.**
- **A surface with no imported material falls back to the base material** instead of erroring or
  rendering default white.
- **`derive_from_surfaces = false` still sets `material_override`** and touches no surface
  override — the hub's contract, asserted rather than assumed.
- **Clear puts every surface override back to `null`**, and leaves a surface someone else
  overrode alone.

The existing five tests are unchanged and must stay passing; they cover the default path.

## Out of Scope

- **Any actual palette.** Which colours Setsuna wears is authored in Blender, not fixed here.
- **Shipping any `slot_overrides` entries.** The mechanism only.
- **Exia.** Her metal wants `specular_enabled` and a different treatment; she is not in
  `test.tscn` in this phase.
- **The hub.** Stays on a single swatch. Multi-material hub surfaces are a separate decision about
  whether the world should carry colour at all.
- **Textures of any kind.** The art direction is silhouette and ink, not surface detail.
- **`main.tscn`.** Only `test.tscn` gets the character applier; `scripts/hub_import.gd` is
  untouched.

## Known Gaps

- **Renaming a slot in Blender silently drops its `slot_overrides` entry.** The lookup misses, the
  surface falls back to a derived colour, and nothing errors. Acceptable while zero overrides
  ship; if that changes, an unmatched override key should warn.
- **Derived materials are rebuilt on every `apply_now()`.** A tweak made in the remote inspector
  is lost on the next re-apply. Fine for a re-import step, annoying if it ever runs per-frame —
  it must not.
- **Surface count is now an art-side performance decision.** Each slot is a draw call per mesh. At
  four or five slots this is noise; it is worth remembering before a slot gets added per finger.
- **The colour a slot renders is not the colour Blender shows.** Cel banding, the halftone in the
  shadow band, and the hemisphere ambient all move it. Blender's viewport is for checking
  *assignment*, never for judging palette.
