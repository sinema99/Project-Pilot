# Spec: a second pilot body, and 1 / 2 to switch

> **Status:** specced and built 2026-10-12. See docs/worklog/2026-10-12.md.
> **Scene:** `scenes/trial.tscn`. **Touches:** `scripts/pilot9.gd` (two small additions),
> new `scripts/pilot_switcher.gd`, new `assets/pilot9_decimate.glb`.

## The ask

"I just exported PILOT9decimateTest.glb ... do not replace the current pilot ... same animations
same movement same everything, it just has different mesh. The current pilot is the default, the
new one stands next to him, 2 switches control to it, 1 switches back."

## The asset

`C:\Users\panac\Documents\PILOT9decimateTest.glb` is copied to `assets/pilot9_decimate.glb` and
imported with `assets/pilot9.glb.import`'s exact settings (same humanoid BoneMap), so it comes in
on the same 25-bone `GeneralSkeleton`. Checked on import: identical bone names and order, identical
Hips rest, every skin binds by bone name, and the Blender material slot names (`main`,
`secondary`, `scarf`) are the same ones the cel applier derives colours from. It is 11 meshes,
~1.1k verts in total against the original's ~58k.

Re-exporting it: copy over `assets/pilot9_decimate.glb`, clear `.godot/imported/pilot9_decimate.glb-*`,
`--import`. No scene rebuild - only its meshes are used.

## How the body is swapped

Not a second scene. `Pilot9Decimate` in trial.tscn is another instance of `scenes/pilot9.tscn` with
one export set: `body_glb = pilot9_decimate.glb`. First thing in `pilot9.gd::_ready()`,
`_swap_body_meshes()` frees the skeleton's MeshInstance3D children and moves the GLB's meshes onto
it (`skeleton = ".."`). Everything after it in `_ready()` - afterimage pool, rim light, held item,
hologram masks - and the trial's `ApplyCelPilot9` (now targeting both pilots) sees the new body.
Animations, AnimationTree, verbs, VFX, hurtbox: all the same nodes, untouched.

So any future pilot9.tscn change - a rig swap, a new clip, a new verb - reaches both pilots.

The editor viewport shows the second pilot with the *original* mesh: pilot9.gd isn't `@tool`, so
the swap only happens in the running game.

## How control switches

`PilotSwitcher` (after both pilots and the cel appliers in trial.tscn) holds an ordered
`pilots` list - `Pilot9` first, `Pilot9Decimate` second. Number keys 1-9 pick by index (physical
keys, like the F7-F11 debug keys - no InputMap action, no settings row). On load it selects 1.

`pilot9.set_controlled(on)`:
- `frozen = not on` - the existing pause flag. A parked pilot stands where he is, still falls, reads
  no input, and any mantle/vault in progress ends the way a freeze already ends it.
- the controlled one's `Camera3D` goes current. trial.tscn also sets the second pilot's camera
  `current = false` in the file, so the scene starts with one current camera.
- only the controlled one is in `reflect_target` (the firing range dummies shoot the first one) and
  only his hologram is in `hologram_host` (the pause menu opens on the first one).

Switching is refused while the current pilot is aboard EXIA (his physics is off), so nobody is
left stranded in the mech.

## Not done

- The camera does not carry over: each pilot keeps his own camera angle.
- EXIA's interaction box arms on whichever pilot body entered it last; a parked pilot left standing
  inside it could be the one F boards. Not handled - park him somewhere else.
