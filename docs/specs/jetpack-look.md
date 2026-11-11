# Jetpack look (Airframe Ultra / PS1)

2026-11-10. Grilled with the user (10 questions, every recommendation taken). A clean test
scene, `res://Jetpack.tscn`, for a new look modelled on Airframe Ultra (Videocult, 2026). The
shader starts from scratch: nothing from cel, RETRO, PixelWorld, CinemaPost or DepthComposite.

## What Airframe Ultra actually does (from its Steam screenshots at 1920x1080, 2x zoom)

There is no developer write-up; this is read off the frames plus press ("smeary, low-poly",
"jittering textures").

- Geometry is drawn at FULL resolution. Edges are clean at 1080p. It is not a low-res render.
- The PS1 read is the TEXTURES: small, grungy, photo-sourced, unfiltered, so every texel is a
  hard block on a sharp screen.
- No outlines, no cel bands. Soft shading, hard sun shadows, strong saturated grade.
- A screen filter: fine vertical CRT stripes, a slight red/blue fringe.
- Effects are chunky square pixels (sparks, debris, jet trails).
- Low-poly models (the user is redoing pilot / mech / ship in Blender).

## Decisions

1. **No cel, no ink in Jetpack.** Plain lit materials. The other scenes are untouched.
2. ~~Textures generated in code (concrete, rust, paint)~~ - REPLACED by the colour pixels below
   (texture pass 2).
3. ~~32 texels per metre~~ - now **16 texels per metre** (texture pass 2).
4. **Vertex snapping on, subtle**: clip-space positions rounded to a 320x240-style grid
   (scaled by aspect) at full render resolution. **Affine texture warping built, off by
   default.** Floors and boxes are cut into ~1-2 m cells so affine has something to bend.
5. **Per-vertex (Gouraud) lighting**, no specular. The sun's lambert term is worked out per
   vertex; the sun's SHADOW is per pixel and hard (no blur, hard filter while in Jetpack).
6. **Screen filter**: subtle vertical stripes, light colour fringe, saturated grade. No
   dither, no letterbox. Its own pass (a CanvasLayer below the HUD), Jetpack only.
7. **Pilot**: full pilot9 controller + camera + pause menu. His materials are swapped to the
   new shader in Jetpack only (his own albedo colours/textures carried over). Off: rim light
   (already off), movement effects + afterimages (`movement_effects_allowed = false`, new
   export), hat (off at boot), staff (`starting_item = null`).
8. **Scene**: `res://Jetpack.tscn` at the root, F6 standalone, not the main scene. 200 x 200 m
   concrete slab, 12 boxes 0.5-4 m (some stacked/adjacent for jump, wall-run, mantle), saturated
   blue gradient sky, one sun ~45 deg up, pilot spawns at the centre facing the boxes.
9. **Fog**: depth fog in the horizon colour, 60 m to 150 m. Nothing else.
10. **QA keys** (Jetpack only; no settings row):
    - 5 whole look on/off (off = plain StandardMaterial3D, same textures, linear filtering)
    - 6 vertex snapping
    - 7 affine warping
    - 8 texel density 32 <-> 16
    - 9 screen filter
    A corner label shows the state. Every number is an export on the `JetpackLook` node.

## Texture pass 2: colour pixels (2026-11-10)

Grilled again (8 questions, every recommendation taken). The photo-grime textures read as fine
noise, not as the blocky surfaces in the references. The user wants Minecraft-style pixels: whatever
colour a surface is, that colour with variation and randomness. Look only: the scene, filter,
lighting, snap, fog and keys are unchanged.

1. **No textures at all.** Every surface is its material's albedo colour (the user's Blender
   exports are solid colours only) turned into pixels in the shader. The `Ps1Textures` grime and
   the `ps1_surface` tags are deleted; every MeshInstance3D under `world_root` gets the look.
2. **16 texels per metre** is the project rule now (Minecraft scale; a 0.5 m step still gets 8 px).
   The 8 key flips 16 <-> 8.
3. **Clumped variation**: texels share shades in 2-4 texel patches (two octaves of cell noise in
   texel space), plus a few lone texels nudged one shade either way.
4. **Stepped shades**: 4 brightness levels, from -15 % to +10 % of the base colour. Brightness
   only, no hue shift. `shade_count`, `shade_dark`, `shade_light`, `clump_texels`,
   `jitter_chance` are exports on JetpackLook.
5. **No UVs**: the grid is projected along the dominant axis of the surface normal, one axis per
   face. The world (`world_root`) projects in world space, so neighbouring boxes line up. Skinned
   models project from their REST pose: at load, each skinned surface's mesh-space positions and
   normals are copied into CUSTOM0 / CUSTOM1, so the pixels stick to the body as it animates.
   Seams show where a curved surface changes axis; accepted.
6. **Look off (5)**: the meshes' own materials come back.

## Files

- `shaders/ps1/ps1_surface.gdshader` - the surface shader (colour pixels, world or rest-pose
  projected).
- `shaders/ps1/ps1_screen.gdshader` - the screen filter (canvas_item, screen texture).
- `scripts/rendering/jetpack_look.gd` - `JetpackLook`: applies materials, filter, keys, label.
- `Jetpack.tscn` - the scene. Boxes carry plain StandardMaterial3D colours.
- `tests/test_jetpack_look.gd` - scene loads, materials applied, toggles flip.

## Not in this pass

Chunky-pixel particles for jetpack/trails; low-poly models (user, Blender); a settings row;
taking the look to other scenes.
