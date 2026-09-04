# Cel shader — third-party

Source: https://github.com/eldskald/godot4-cel-shader
Author: Rafael de Lima Bordoni (github.com/eldskald)
License: MIT (see LICENSE text in the upstream repo)

Files taken verbatim from the upstream `src/` folder:
- `cel-shader-base.gdshader`
- `outline.gdshader`
- `includes/*.gdshaderinc`

`cel-shader-base.gdshader` and `includes/` must stay siblings — the
`#include "includes/..."` paths are relative.

## Wiring in this project

- Global shader params live in `project.godot` under `[shader_globals]`
  (`diffuse_curve`, `specular_smoothness`, `fresnel_smoothness`,
  `outline_width`, `outline_color`).
- `diffuse_curve` points at `res://resources/cel_diffuse_curve.tres`
  (a GradientTexture1D, hard 2-band step matching the upstream demo).
- Sample material: `res://resources/cel_sample_material.tres`
  (base shader + `res://resources/cel_outline_material.tres` as `next_pass`).

To add an optional feature (emission, normal map, etc.), copy
`cel-shader-base.gdshader` and flip the matching `#define USE_* 0` to `1`.
