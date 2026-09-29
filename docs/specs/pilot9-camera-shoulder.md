# Spec: pilot9's over-the-shoulder camera

> **Status:** grilled, specced and built 2026-09-29. Not yet played.
> **Touches:** `scripts/pilot9.gd`, `project.godot` (`shoulder_swap`),
> `tests/test_pilot9_camera_shoulder.gd`. No scene change - the arm's position is written in code.

## The ask

"A slight offset to one side ... swap shoulders with a button, for now X. For wall running, don't
let the player choose their side, just auto put the camera away from the wall."

## Decisions

| | |
|---|---|
| Offset | 0.4 m (`camera_shoulder_offset`), on the **SpringArm3D's local x**, so the camera still orbits him and the arm's cast runs from the shifted origin |
| Default | Right shoulder. The choice persists (`_shoulder_side`) - across wall-runs, not reset by anything |
| Swap | `shoulder_swap`: **X** and **joypad X**. Ease ~0.25 s (`camera_shoulder_swap_time`), exponential, within 2% at the end. Never a snap |
| Wall-run | Camera goes to the side away from the wall (wall right -> camera left), same ease, both ways. The choice is never written, so the camera returns to it afterwards. X is **ignored** during a run, not buffered |
| Collision | A sphere (`camera_clearance`) cast sideways from the pivot clamps the offset so the lens never starts inside a wall beside him. The limit is damped with the arm's own asymmetric step (fast in, slow out) |
| First person | No offset: scaled by `_camera_mode_length / camera_distance`, and X does nothing |
| Other states | Rail, climb, mantle, vault, slide, dash keep the chosen shoulder. No special cases |

Away-from-wall framing puts him toward the wall side of the screen with the open space ahead of
him visible; a camera on the wall side would be squeezed by the SpringArm.

## Not tested headlessly

The framing and the feel of the slide. Asserted in the suite: the binding, defaults, the
wall-run's side and the return, the ease curve, the arm's settled x either side, first person.
The sideways clamp against real geometry is not asserted.
