# Cel look rollout

Adopt the `test3.tscn` cel-shaded look as the game's single art direction, and
retire the Moebius compositor / stylized / ghibli passes.

Decisions (from the user, 2026-08-30):

- Every scene gets the `test3.tscn` setup: cel environment, cel sky, cel
  materials, cel outline, softened sun shadow bias.
- The mech (EXIA) is in scope — it gets the cel material + outline too.
- No scenes are deleted. `test.tscn` and `test2.tscn` are converted, not removed.
- Old code and specs are **archived, not deleted** — moved under `*/archive/`.

## The cel look bundle

| Piece | Where |
| --- | --- |
| Surface shader | `shaders/cel/cel-shader-base.gdshader` (+ `includes/`) |
| Outline pass | `shaders/cel/outline.gdshader` via `resources/cel_outline_material.tres` (`next_pass`) |
| Shader globals | `project.godot [shader_globals]`: `diffuse_curve` (→ `resources/cel_diffuse_curve.tres`, ramp `0.38 / 0.52`), `specular_smoothness`, `fresnel_smoothness`, `outline_width`, `outline_color` |
| Materials | `resources/cel_character.tres`, `resources/cel_ground.tres` |
| Sky | `resources/cel_sky.tres` → `shaders/cel/vfx/sky.gdshader` |
| Environment | `Environment_cel` from `test3.tscn`: sky bg, flat teal ambient, filmic tonemap, glow, distance + volumetric fog |
| Sun | `DirectionalLight3D`, low sunset angle, `shadow_bias 0.025`, `shadow_normal_bias 1.5`, shadow mode 1, max distance 220 |
| Applier | `scripts/rendering/apply_stylized.gd` — walks a subtree, sets the cel material. `derive_from_surfaces` on for skinned characters/mech, off for static geometry |

## Per-scene changes

- **main.tscn** — drop the qwantani night panorama; cel sky + `Environment_cel`;
  retune `DirectionalLight3D` to the cel sun; add appliers for `HUB_blockout`
  (ground mat), `SETSUNA/PlayerModel` (character mat, derive), `EXIA` (character
  mat, derive).
- **Hub.tscn** — same environment/sun swap; applier for `HUB_blockout`.
- **test.tscn** — remove `gradient_sky`, moebius compositor, `stylized`
  shader/material, `character_material`; cel environment/sun; ground override and
  both appliers repointed to `cel_ground.tres` / `cel_character.tres`.
- **test2.tscn** — remove citrus panorama, moebius compositor, `stylized_ghibli`
  and its six per-slot `ShaderMaterial` sub-resources (incl. `slot_overrides`);
  cel environment; add a cel sun (test2 had no light); appliers repointed.
- **mech.tscn** — no change; it is a component scene with no environment and
  gets the cel material from the `main.tscn` applier.

## Archived (recoverable from git @ `fef9586`)

```
scripts/archive/    moebius_compositor.gd (+ .uid)
shaders/archive/    moebius_outline.glsl (+ .import), stylized.gdshader,
                    stylized_ghibli.gdshader, gradient_sky.gdshader,
                    character_outline.gdshader (unreferenced)  (+ .uid each)
resources/archive/  moebius_compositor.tres, stylized_material.tres,
                    character_material.tres
docs/archive/       moebius-art-direction.md, ghibli-pass.md
tests/archive/      test_moebius_compositor.gd, test_stylized_material.gd,
                    test_ghibli_material.gd, test_gradient_sky.gd,
                    test_pipeline_smoke.gd  (+ .uid each)
```

The headless runner (`tests/run_tests.gd`) only discovers `tests/*.gd`, so
archived tests stop running automatically. Their hard-coded shader paths are
repointed to `*/archive/` so they still work if run by hand.

## Follow-ups / known tension

- `docs/specs/night-pass.md` describes a deliberate night hub. It is left in
  place but is superseded in practice by the cel sun until revisited.
- No `test_cel_pipeline.gd` yet to replace the smoke test's scene-structure
  checks.
