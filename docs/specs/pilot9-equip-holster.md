# pilot9 equip / holster animation

2026-10-13. Grilled with the user the same day.

Today `R` (`equip`) snaps the staff between the back socket and the hand in a single frame. This pass
replaces that snap with a short procedural draw: he reaches back, grabs the staff, whips it through an
arc in the plane of his back, and spins it once in his hand before settling. Holstering plays the same
thing backwards. No Blender clip.

## The motion (equip)

Seen from behind (the camera's view), the staff starts on his back with its top over his LEFT
shoulder and its bottom by his RIGHT hip. It ends trailing low behind him in his right hand (the
running hold).

| Beat | Time | What happens |
|---|---|---|
| Reach | 0.15 s | the right arm eases into the running hold pose (`hold_rotations`), back toward the staff |
| Swing | 0.12 s | grab: the staff leaves the back and pivots on his hand in the plane of his back. The top end goes down his left side and the bottom end comes up and out to his right (the user's blue arcs). Seen from behind it turns counter-clockwise |
| Spin | 0.20 s | the same rotation keeps going for a fast full turn in that plane, with the reflect's blur disc |
| Settle | 0.08 s | at running pace it is already in the red trailing hold. At any other pace the arm blends to whatever the drawn arm normally does there (idle keeps the natural arm) |

- The swing and the spin are one continuous turn, easing in at the grab and out at the settle, so
  there is no hitch between them.
- The staff only counts as **drawn** once the settle ends.
- **Holster:** the same timeline played backwards. The staff stops counting as drawn on the press.

## Rules

- **Blocked** in mantle (`is_climbing`), vault and wall-run. A press there is ignored, not queued.
- **R during an equip or holster** is ignored until it finishes.
- **Reflect during an equip or holster** is ignored. That falls out of the staff not counting as
  drawn until the equip ends.
- **A mantle, vault or wall-run starting mid-animation** finishes the animation instantly: an equip
  snaps to the hand and counts as drawn, a holster snaps to the back.
- **Movement** is fully free throughout.
- **Spawn** stays holstered, with no animation.
- Holstering mid-reflect cancels the reflect (as today), then plays the holster.
- An item swap mid-animation finishes it instantly first.

## How it is built

- `scripts/items/equip_anim.gd`, a pilot9 child node built at runtime by `pilot9.gd::_setup_equip_anim()`
  (called right after `_setup_reflect()`), the same way the item holder and the reflect are.
- The arm uses its own `ArmPoseModifier` (added last, so it wins), holding the item's
  `hold_rotations` at a weight the timeline sets directly. At the handovers the item holder's own
  arm modifier is set to the same weight, so the arm never pops.
- Every rendered frame the staff is placed in world space from three live transforms: where it sits
  on the back, where it sits in the hand, and the model's facing. During the swing its grip point
  slides from the back placement to the hand and its tilt flattens into the back plane, so the grab
  never pops either way.
- The turn is in-plane, about the model's facing axis. It starts at the back placement's angle and
  ends at the in-hand angle plus `extra_turns` full turns.
- The blur disc is a second instance of `spin_disc.gdshader`, using the reflect's disc settings.
- `pilot9.toggle_drawn()` stays the instant snap (tests, probes and scripts use it). The `equip`
  input now goes through `pilot9.press_equip()`, which plays the animation.

## Tunables (exports on `EquipAnim`)

`reach_time` 0.10, `swing_time` 0.08, `spin_time` 0.133, `settle_time` 0.053, `extra_turns` 1,
`turn_ease_in` 0.033, `turn_ease_out` 0.053. (2026-10-13: every time divided by 1.5 - 0.55 s -> ~0.37 s.)

## Built

Built 2026-10-13. Departures:

- **The spin is one extra full turn, not 1.5.** The turn has to end at the in-hand angle, or the settle
  would swing the staff through a visible half turn into the hand. Swing plus one turn comes to about
  1.3 turns in the hand. `extra_turns` is an int.
- **The running hold is not in the back plane.** In the hold, the staff trails mostly along his facing
  (model axis about (-0.13, -0.21, 0.97)). So the spinning plane tilts over to it while the spin slows,
  mirroring how the grab flattens the back placement's tilt. The settle then only has to cover the arm.
  The end angle is read from the hold pose itself (`hold_transform()`, the arm chain posed with
  `hold_rotations`), not from the live hand, so it holds still while the arm blends at idle.
- **The disc is mirrored on a draw.** `spin_disc.gdshader` smears behind a tip turning the reflect's
  way, and the draw turns the other way. A holster runs backwards, so it is unmirrored.
- Probe: `tests/_probe_equip_shot.gd` (windowed) shoots a slow-motion draw and holster from behind.
  Tests: `tests/test_pilot9_equip_holster.gd`.
