# Revolver handcannon pass (2026-11-12)

Grilled with the user, then built. Items 1-5 are the user's decisions.

1. **Size.** `revolver_model.gd::length` 0.35 -> **0.6 m** (muzzle to back of grip). Same GLB shape, uniform
   scale only; a chunkier model would be a Blender re-export over `assets/revolver.glb`, judged after seeing it.
2. **Standing / walking: held out wide.** Relaxed gunslinger pose: arm away from the body, out to the right
   and slightly forward, elbow slightly bent, barrel roughly level and forward.
3. **Run / sprint: trailing behind him**, like the staff (the staff's three arm bones; only the hand is
   re-solved so the 0.6 m gun hangs barrel back-and-down).
4. **Switch:** the existing speed blend (`ItemHolder.run_factor`: 0 at walk pace or slower, 1 at run or
   faster, linear between).
5. **Unchanged:** which states hold (`ARM_OVERRIDE_STATES` minus the revolver's `slide`), air off, equip
   materialize (grows to 0.6 m), staff behaviour, reflect staff-only. No aim / fire / reload.

**Correction (same day):** "wide" meant the gun held at his **hip**, not an arm thrown out. Idle pose
re-solved with the probe (args `34 14 50 8 130`): hand at the hip, clear of the coat and thigh.

## How it is built

- `HeldItem.idle_rotations` (new): the pose at walking pace or slower, same format as `hold_rotations`.
  Empty (the staff) means `hold_rotations` at every pace.
- `ItemHolder.current_pose()` slerps `idle_rotations` -> `hold_rotations` by `run_factor` each frame;
  `blend_poses()` is the static helper. `EquipAnim._apply()` settles into `current_pose()`.
- `revolver.tres` keeps `hold_at_any_speed = true` (the arm override stays on at every pace; the blend
  does the rest).
- Both poses were solved by `tests/_probe_revolver_shot.gd` (args: out fwd elbow barrel_down trail_angle,
  used 60 30 30 8 130) and tuned from its screenshots; edit them live in the remote inspector.
