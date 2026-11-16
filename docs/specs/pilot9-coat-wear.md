# Trench coat wear (2026-11-13)

Grilled 9, all recommendations taken. Worn-leather texture on the trench coat, AIRFRAME only.

- Mesh, shape and fit untouched; colour only. Knight robe untouched; RETRO/COMPOSITE keep the flat coat.
- Coat only has finer pixels: 40 texels/m (JetpackLook.coat_texels_per_metre), the rest stays 16.
- Five stepped brown tones in clumps, some texels one shade off. Leather +-27 %, lining the same
  wear at half strength (+-14 % tones, wear_strength 0.5).
- Wear field in `shaders/ps1/ps1_surface.gdshader::coat_wear` from the REST position (rides the cloth):
  light = shoulders, elbows, front edges, collar rim, hem edge; dark = underarm, sleeve underside,
  waist crease, lower back, grime band above the hem, hanging fold streaks on the skirt.
- Wired in `AirframeLook._coat_ps1` (trial) and `JetpackLook._wear_coat` (Jetpack); apply() skips the
  coat's surface tones.

Built, probe-shot (tests/_probe_coat_shot.gd airframe), not yet played.
