# Spec: the farmer replaces the firing-range box

> **Status:** grilled and specced 2026-11-02, built 2026-11-02 - see "Built" at the end.
> **Scene:** `scenes/firing_range.tscn` (in `trial.tscn`). **Touches:** `scripts/range/range_dummy.gd`,
> `range_bolt.gd`. Model: `assets/enemie_farmer.glb` (the user's `Enemie_Farmer.glb`).

## The ask

"I just exported an enemy type from Blender ... please replace the testing dummy with this enemy. I
rigged up this enemy, but they have no animations. That is fine because the enemy will move by
sliding around on the ground."

## Decisions

- **Visual swap only.** The farmer is the range dummy: same states (dormant / waking / active), same
  orbit (14 m, 4 m/s strafe), same bolts every 2-3 s, cannot die, `take_hit` hook, HUD, F9/F10/F11.
  The box is removed, no toggle back to it.
- **Modelled size** kept: 3.9 m across, 3.4 m tall (pilot is ~1.8 m). The slab margin it keeps goes
  from 2 m to 3 m so its legs stay on the slab.
- **The model** (measured): a green disc (radius 1.06 m, 0.92-1.67 m up) on four arms to four
  legs on the diagonals (joints 2.48 m up, ~1.5 m out, the leg tops 3.4 m, feet on the ground). Nine
  bones: root `Bone` at the disc centre, arms `Bone.001-.004`, legs `Bone.005-.008`. No clips.
- **Spheres.** The export carries 2 of the 8 joint spheres (the other 6 were not in it). Built in
  Godot: each is copied at 90 / 180 / 270 deg about the centre. The 4 disc spheres ride the root
  `Bone`; the 4 leg-joint spheres each ride their leg bone through a `BoneAttachment3D`, so they
  follow the legs if the legs ever move.
- **Facing:** the window side faces pilot (the windows are on the model's -Z, so it is turned 180).
- **Bolts** leave the middle of the window band, just in front of the disc (1.37 m up).
- **State on the windows; body keeps its olive and black.** Dormant: dark windows. Awake: dull red
  windows. Charging: windows ramp to bright yellow-white over the 0.45 s. Hit: the whole farmer
  flashes white (an additive overlay on every mesh), plus the existing wobble and sparks.
- **Perfect-reflect homing** aims at the disc centre (1.3 m up), not 1.0 m above the origin.
- **Shaped hitbox and collision:** one cylinder for the disc, one per leg (laid along the leg bone,
  0.42 m radius, feet to the leg top). The arms are not hit. Bolts through the gaps miss.
- **Lean:** the visual leans into its direction of travel, up to 4 deg at strafe speed, pivoting at
  the feet, eased over ~0.3 s; a strafe flip rocks it across. Visual only - the shapes stay upright.
  Frozen or dormant, it eases back upright.

## Not in this

New behaviour (health, death, a different attack or movement), clips, a second enemy type.

## Built

2026-11-02. `scripts/range/range_dummy.gd` (the farmer: `_mount_spheres`, `shape_specs`,
`lean_target`, window + flash materials), `range_bolt.gd` (homing reads the shooter's
`homing_height`), `assets/enemie_farmer.glb`. Tests: 7 new in `tests/test_firing_range.gd`.
Probe: `tests/_probe_farmer_shot.gd` (windowed close-ups: front, charge, hit, lean from above).
