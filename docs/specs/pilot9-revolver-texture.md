# Revolver texture (2026-11-16)

Grilled 8, built. The revolver gets a chunky PS1 texture painted in code, matching the user's reference
(dull gunmetal with painted streak highlights, black bore, orange wood grip).

- `scripts/items/revolver_texture.gd` re-projects each GLB mesh's UVs (the GLB's own body UVs collapse
  onto one line, so they are unusable), then rasterises a 64x80 atlas (x4 nearest blow-up) through them.
  Each texel's 3D point (GLB space) picks steel / wood / hammer / bore. Grip = x > -0.55, y < 1.3.
- Parts by node name: `Cube` body, `Cube.001` cylinder, `Cube.002` hammer.
- Albedo goes through `pilot_cel_character` (colour white, `base_texture` set), so cel tones, ink and every
  LOOK still apply. Exports on `revolver_model.gd`: `wear`, `texture_seed`. No image files.
- Worn blued steel, edge scuffs, no rust. Rifle untouched (do it the same way if this is liked).
- Probe: `tests/_probe_revolver_texture.gd` (shots in docs/shots/rev_a.png, rev_b.png).
