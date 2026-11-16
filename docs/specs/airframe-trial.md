# AIRFRAME in trial (Jetpack look at 75 %)

2026-11-11. Grilled with the user (9 questions, every recommendation taken). The user loves the
Airframe Ultra / PS1 look built in `res://Jetpack.tscn` (docs/specs/jetpack-look.md) but finds it
"super strong": bring it into trial at about 75 % of the original.

## Decisions

1. **A third LOOK: RETRO / COMPOSITE / AIRFRAME, and AIRFRAME is the default.** I cycles all
   three; the LOOK row in settings has the new value. RETRO and COMPOSITE are untouched.
2. **Every effect a quarter of the way to neutral** (one `intensity` export, 0.75):

   | Effect | Original | 75 % |
   |---|---|---|
   | Pixel shade spread | 0.85 / 1.10 | 0.8875 / 1.075 |
   | Lone-texel jitter | 0.12 | 0.09 |
   | CRT stripes | 0.14 | 0.105 |
   | Colour fringe | 1.0 px, edge boost 1.5 | 0.75 px, 1.125 |
   | Saturation | 1.2 | 1.15 |
   | Contrast | 1.12 | 1.09 |
   | Lift / gain | (0,0,0.02) / (1.02,1,1.04) | 75 % of their offsets |
   | Vertex snap grid | 240 lines | 320 lines (snaps 75 % as big) |

   Pixel size stays the project rule (16 texels/m); clumps, Gouraud light and hard shadows are
   on/off and stay. No cel, no ink in AIRFRAME (the PS1 material has no outline pass).
3. **Everything gets the surfaces**: the whole world (blockout, jump grid, pipe hall, habitat,
   firing range, pads, rails, Vanguard), both pilots, EXIA, the farmer dummy. Left alone: glows,
   transparent and unshaded materials, laser bolts, particles, afterimages, hologram, staff
   materialize edges, HUD and menus. A map that looks bad can be excluded afterwards (meta
   `airframe_skip` on any node opts it and its children out).
4. **Jetpack's environment while AIRFRAME is on**: gradient sky, linear tonemap, bluish ambient,
   60-150 m fog (now one shared file, `resources/airframe_environment.tres`, used by Jetpack too),
   no compositor; the sun goes to 45 deg up on the map's own compass bearing, with Jetpack's
   colour, energy (1.6), biases and no blur; directional shadows hard. All restored on switching
   away. Trial's painted clouds go with its sky.
5. **One-time migration**: a save without the `airframe_default` meta flag (every save before this)
   loads with LOOK = AIRFRAME once; every save from now on writes the flag, so the player's LOOK
   then sticks.
6. **Pilot extras keep working**: staff, hat and body get the surfaces (things on bones are object
   projected, skinned bodies rest-pose projected). Movement VFX stay as they are under their
   MOVEMENT EFFECTS toggle. Afterimages keep their own ghost shader.
7. **QA keys 5-9** (look / snap / affine / texels 16<->8 / filter) in trial, only while AIRFRAME
   is on. The corner label shows for 3 s after one of them is pressed. 5 turns the AIRFRAME
   materials and filter off in place; I is still the real LOOK switch.
8. **`intensity` on JetpackLook**: Jetpack stays at 1.0 as the untouched reference; trial's
   AirframeLook is 0.75. One number to retune.
9. **Other maps** (boss arena, Internals, starter map) have no AirframeLook: with LOOK =
   AIRFRAME they show RETRO, and the setting is not changed (`Settings.retro_shows`).

## How it works

- `AirframeLook` (scripts/rendering/airframe_look.gd) extends `JetpackLook`. Settings calls
  `set_active` on a LOOK change, after the look being left lets go (same order as RETRO).
- On: walks its parent's subtree; each slot whose material is cel-base (colour x base_texture
  mean), metre grid (base colour) or opaque lit StandardMaterial3D without emission is recorded
  and given a shared PS1 material of that colour. Mapping: world for the level, object for
  anything under a Skeleton3D / CharacterBody3D / RigidBody3D / AnimatableBody3D, rest pose for
  skinned meshes (mesh swapped for a CUSTOM0/1 copy, cached, put back on off). Nodes added while on
  are swapped a deferral later.
- Off: every slot, mesh, environment, compositor, sun property and the shadow filter (the SHADOW
  QUALITY setting's) is put back.

## Files

- `scripts/rendering/airframe_look.gd` - new.
- `scripts/rendering/jetpack_look.gd` - `intensity`, slot helpers (material_override slots),
  `new_ps1_colour`, `rest_pose_mesh`, shadow filter restored from the SHADOW QUALITY setting.
- `scripts/settings.gd` - LOOK values + default, `AIRFRAME_FLAG` migration, `retro_shows`,
  `soft_shadow_quality`, the LOOK hand-over.
- `scripts/rendering/retro_look.gd` - boots on `retro_shows`.
- `resources/airframe_environment.tres` - Jetpack's environment, shared.
- `scenes/trial.tscn` - AirframeLook node (sun, intensity 0.75). `Jetpack.tscn` - uses the shared
  environment.
- `tests/test_airframe_look.gd`; `tests/test_live_composite.gd` updated for the new row/default.
- Probes: `tests/_probe_airframe_inventory.gd` (what materials trial has),
  `tests/_probe_airframe_shot.gd` (75 % / 100 % / RETRO screenshots).

## Not in this pass

AIRFRAME on the other maps; chunky-pixel particles; a settings row for intensity.
