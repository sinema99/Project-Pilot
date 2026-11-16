# pilot9 gun aim (2026-11-15)

Grilled 2, then built. Supersedes the aim parts of pilot9-rifle.md Rev 4 / Rev 5 and the revolver's
solved aim pose. Only the right-click aim changed: hip holds, reload, camera, recoil, effects and
the gun models are untouched.

## Decisions
- The gun is placed from his BODY, never from his head. The earlier passes put the barrel on an
  "eye line" through the Head bone, which is inside his helmet (a ~0.19 m sphere); that was the clip.
- Rifle: butt of the stock in the right shoulder pocket, right hand on the grip with the elbow down,
  left hand under the fore-end, torso bladed (the existing `aim_twist_deg`). Head upright.
- Revolver: two hands on the gun, both arms pushed out in front of the chest, shoulders square.
- Aiming up / down bends his upper body with the camera (spine 30%, chest 35%, upper chest 35%,
  limit 60 deg); the arms and gun keep one arrangement. Hips and legs untouched.

## How it is built
- `scripts/items/aim_ik.gd`: `anchor_point()` (from the right shoulder joint, or the midpoint of
  both for `aim_center`) -> `item_frame()` (pins an item-frame point there, barrel at the crosshair
  point) -> `two_bone()` per arm. `bend()` is the upper-body pitch.
- `ArmPoseModifier`: hip pose, twist, `apply_bend()`, then the IK.
- Numbers per gun on `HeldItem`: `aim_anchor_item`, `aim_anchor_offset` (right, up, forward),
  `aim_center`, `aim_left_hand` (left WRIST frame, item space), `aim_right_pole` / `aim_left_pole`,
  `aim_bend`. Both guns set `aim_ik`; the old `aim_rotations*` data was removed from both .tres
  (the fields stay for an item without IK).
- A placed aim holds in every move he can aim in, the air included (`ItemHolder.arm_target`).
- The rifle sits 3.5 cm right and 3.5 cm below the shoulder joint: nearer and the stock grazes the
  helmet. Its left hand is at the edge of his reach; further forward the arm goes straight and misses.

## Checking
- `tests/test_aim_ik.gd`: on the real skeleton, both guns, at 0 / +-40 / +-60 deg: no gun triangle
  within 1 cm of the helmet sphere, both wrists on their grips, torso bent with the aim.
- `tests/_probe_gun_aim.gd` (windowed): game, side, front and top shots at 0 / +40 / -40 plus the
  same numbers from the live game. `tests/_probe_aim_measure.gd` prints bone, helmet and gun sizes;
  re-run it and retune the anchors if a gun model or his head changes.
- Gotcha: outside `skeleton_updated` a Skeleton3D hands back the UNMODIFIED animation pose, and
  outside the tree its global poses go stale after a bone is set.
- `tests/_probe_solve_aim.gd` and `_probe_aim_ik_setup.gd` are obsolete.

Probe-shot only, not played. Shots: docs/shots/gun-aim-*.png.
