# Pilot grime (2026-11-16)

Grilled 7, all recommendations taken. pilot9's white suit looks lived-in: placed dirt plus a
per-material detail layer. AIRFRAME only.

- Scope: AIRFRAME (and Jetpack, same shader). RETRO/COMPOSITE keep him clean. Pilot 1 and pilot 2
  both (same four materials). Coat, hat, staff, mech and every other character untouched.
- His base colours stay; everything is added in `shaders/ps1/ps1_surface.gdshader` from the REST
  position (rides the body, no UVs, no Blender work).
- Body pixels: 40 texels/m (matches the coat; JetpackLook.pilot_texels_per_metre). World stays 16.
- Placed dirt, one grime colour (desaturated warm grey-brown, hub2 dust/rust), blended in by a dirt
  amount per texel, stepped and clumped like everything else:
  - heaviest on boots and shins, fading out by mid-thigh,
  - scuffed patches on knees and hands/gloves,
  - a faint speckle everywhere else,
  - chest, shoulders and helmet mostly clean.
  Dark parts barely show it (the blend is weighted by how light the base colour is).
- Material detail (`grime_material`): main = fine scuffs + thin scratch lines a texel wide, slightly
  darker; vest = blotchy canvas tone + stains; scarf = faded, bleached patches; secondary = none.
- Amount: subtle, ~85-90 % of the upper suit reads clean. One export, `grime_amount` 0-1 (default
  0.5) on JetpackLook. No settings row.
- Wiring: JetpackLook picks a pilot body surface by its material name (main / secondary / scarf /
  vest) on a skinned mesh under a Pilot9 body; apply() gives those surfaces the pilot texel size.
