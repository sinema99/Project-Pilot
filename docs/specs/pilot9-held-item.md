# pilot9 held item (staff, pass 1)

2026-09-25. Grilled with the user the same day. Pass 1 of a draw/holster system: the staff can be
carried on his back or in his right hand, toggled with a button, with no draw animation yet.

## What it is

- A **generic held item** system. The staff is its first item. pilot9's code only ever knows "the
  current item", never "the staff".
- **Purely cosmetic.** No collision, no gameplay effect, no change to any movement number.
- **Swappable.** Each item is its own scene plus a data resource. A future staff means authoring a
  new resource, with no code change. Finding or customizing staffs is far future and out of scope,
  but nothing here may assume there is only one.
- **"No item" is a valid state.** `equip` does nothing, the arm override stays at 0 and nothing
  errors. This is the base case, not an edge case.

## Pieces

### The item: `HeldItem` resource (`scripts/items/held_item.gd`)

| field | type | meaning |
|---|---|---|
| `scene` | PackedScene | the visual, e.g. `scenes/items/staff.tscn` |
| `hand_offset` | Transform3D | the item's transform in the hand socket, lining the grip up with his fist |
| `back_offset` | Transform3D | the item's transform in the back socket |
| `hold_rotations` | Dictionary[StringName, Vector3] | the right arm's hold: bone name to rotation in degrees (see "The arm override") |

The staff: `resources/items/staff.tres` pointing at `scenes/items/staff.tscn`, a Node3D with one
MeshInstance3D holding a `CylinderMesh`, **1.6 m long, 2.5 cm radius** to start. It uses the cel
character material (`resources/pilot_cel_character.tres`) and so gets the ink outline. It does
**not** get the rim light, which stays pilot-only per [pilot9-rim-light.md](pilot9-rim-light.md).
The staff is hidden with pilot's mesh during the dash, the same way the rim light is.

### Sockets

Two `BoneAttachment3D` under `%GeneralSkeleton`:

- **HandSocket** on `RightHand`.
- **BackSocket** on `UpperChest`. The staff sits **diagonally: top end over the left shoulder,
  bottom end by the right hip.** The bottom end is where the future draw clip grabs it (see
  Deferred).

Drawing or holstering reparents the item's instance between the two sockets and applies that
socket's offset from the resource. Both offsets are tuned in play.

### pilot9

- `@export var starting_item: HeldItem`, defaulting to the staff. Empty is the no-item test.
- It spawns **holstered** (on the back).
- State: `held_item` (resource or null) and `is_drawn` (bool).
- Public API: `set_item(item: HeldItem)` (swaps, and keeps `is_drawn` if the new item exists) and
  `toggle_drawn()`. A future pickup calls `set_item`.

### Input

A new action **`equip`**: keyboard **R**, gamepad **d-pad right**. Each press toggles drawn and
holstered. Pass 1 **snaps**: the item changes socket in a single frame. It works **anytime**,
whether on the ground, in the air or mid-move, and nothing blocks it.

### The arm override

While drawn **and running**, pilot's **right arm** (`RightShoulder`, `RightUpperArm`,
`RightLowerArm`, `RightHand`) is held in the item's hold. The rest of the body keeps playing
whatever the AnimationTree says.

**The hold is not a clip** (changed 2026-09-25, user's call: *"id prefer it not to be a seperate
animation"*). It is four bone rotations stored on the item itself, `hold_rotations`, as Euler
degrees (YXZ, parent-relative, like a Blender pose bone). The hold rides the chest, and the run
clips lean it ~30 degrees and sprint ~57, so the staff's are solved for a 45-degree lean: upper arm
60 degrees behind straight down and angled out from his side (hand ~37 cm out from his
centreline, was ~21 - user: "holding it out a little more"), elbow bent ~28 degrees **forward** as a pure hinge (RightLowerArm's
first number is the bend), staff steep, tail up behind him and front end down toward his lead
foot (user drew it in red, 2026-09-25). Checked on the clips: the hand sits 10-20 cm behind his
hips; the staff tilts ~33 degrees off level in the run and ~57 in the sprint, its front end
20-30 cm off the ground. The first solve straightened the arm backwards and hyperextended the elbow (user,
2026-09-25: "his elbow is bending backwards"). The holder re-reads them every
frame, so they can be tuned live in the remote inspector (pilot9 → `starting_item` →
`hold_rotations`) while the game runs. `RightShoulder` is pinned at its rest rotation, which
flattens every clip's shrug while held.

**Only while running and sprinting** (user's call, 2026-09-25). Idle and walk keep the natural
arm. The target is scaled by `run_factor`: 0 at `walk_speed` (2.5 m/s) or slower, 1 at `speed`
(5.0 m/s) or faster, linear between, from his horizontal velocity. The same gate covers every
listed state, so a slide
(always fast) holds, and a crouch-walk (slower than walk) does not.

**How it is built: a `SkeletonModifier3D`, not an AnimationTree layer.** In chat this was
described as a bone-filtered blend layer in the AnimationTree. It is built as a small modifier
under `%GeneralSkeleton` instead, with the same effect. The reason is that the tree's root is the
state machine itself: the build script's `_ensure_*_state()` functions all cast
`tree_root as AnimationNodeStateMachine`, and 37 parameter paths in scripts and tests start with
`parameters/<state>` or `parameters/playback`. Wrapping the root in a BlendTree for a filter would
move every one of them. The modifier:

- takes the item's `hold_rotations` for the right-arm bones
- applies those rotations on top of the animated pose, weighted by its `influence`
- eases `influence` toward its target over **~0.15 s**

**Per-move list.** The target influence is the run gate above when drawn **and** the tree's current
state is on the list below, otherwise 0. The staff stays in his hand either way. When the override is off,
it just follows whatever his hand does in that clip.

| state | override |
|---|---|
| `Locomotion` (idle, walk, run, sprint) | on |
| `jump`, `fall` | **off** (2026-09-26: a running jump opened with the arm still locked back; the user wants both arms out like a normal jump) |
| `jump_land` | on |
| `crouch`, `slide` | on |
| `climb` (ledge mantle) | **off** |
| `wall_run` | **off** |
| `rail` | **off** |

The list is a dictionary in one place, so moving a state between on and off is a one-line change.
Any state not listed defaults to **off**, so a future move never gets a stuck arm. The initial
split is a guess, to be tuned when the user plays.

## Tests (`tests/test_pilot9_held_item.gd`)

- `equip` exists and is bound to R and d-pad right.
- Spawning with the staff: it is under BackSocket and `is_drawn` is false.
- `toggle_drawn()` moves it to HandSocket, and toggling again moves it back.
- `starting_item = null`: toggling does nothing and throws no error. Setting the item later works.
- `set_item()` with a second HeldItem while drawn: the old instance is freed, and the new one is
  in the hand.
- The staff's `hold_rotations` names every arm bone and each resolves on the rig.
- `run_factor` / `arm_target_for`: 0 idle and walking, 1 running and sprinting, jump and fall 0
  at any speed, an off-list state 0 at any speed.
- The per-move list: the target influence is 0 in `jump`, `fall`, `climb`, `wall_run` and `rail`, and 1 in
  `Locomotion`, and an unlisted state name gives 0.
- HandSocket follows the *modified* pose, not the pre-modifier pose. This is a mechanism check,
  since the staff must be in the posed fist.

## User's Blender task

None. The hold used to be a Blender clip, `P_hold-staff`, and is now `hold_rotations` on the item.

## Deferred (not pass 1)

- **Draw/holster clip.** He grabs the **bottom end at the right hip** and pulls it out. The socket
  change moves to the clip's grab frame. The clip will probably be ~0.4–0.5 s.
- **Blocked moves and queued presses**: once the clip exists, likely queue a press made during an
  arm-heavy move and run it when the move ends.
- **Pickups** and finding and customizing staffs.
- Per-move **auto-holster**, if clipping in a specific "off" move bothers the user.
- **Breakable** staffs. "Destructible" in the grill meant swappable, and breaking was ruled out.

## Built (2026-09-25, everything except the pose)

Files: `scripts/items/held_item.gd` (the `HeldItem` class), `scripts/items/item_holder.gd`
(sockets, swap, toggle, per-move list), `scripts/items/arm_pose_modifier.gd`,
`scenes/items/staff.tscn`, `resources/items/staff.tres`, the `equip` action in `project.godot`,
and the "Held Item" group plus `set_item()`, `toggle_drawn()` and `is_item_drawn()` on pilot9.

Departures and specifics:

- **Everything is built at runtime** in `pilot9._ready()` (`_setup_item_holder()`), not saved into
  `pilot9.tscn`, so a rig swap by the build script cannot drop the sockets.
- **The hold is `hold_rotations` on the item, not a clip** (same day, see "The arm override").
  The `P_hold-staff` `GLB_CLIPS` entry and `arm_pose_modifier.gd`'s clip sampler were removed.
- **The hold sets rotations only**, and only on RightShoulder/UpperArm/LowerArm/Hand. The
  blockout rig has no finger bones.
- **The run gate** reads `velocity`, `walk_speed` and `speed` off pilot9, which is passed to
  `item_holder.setup()` as its body.
- **The staff uses `material_override`** with the cel character material. That wins over the
  scene's `apply_stylized` surface overrides, so it looks the same whether or not an applier walks
  pilot9.
- **Offsets were checked against the posed rig with a probe, not guessed from the rest pose.**
  Holstered, the top sits over his left shoulder and ~20 cm above his head, and the bottom is by
  his right hip, both behind him. Drawn with no pose, the idle arm hangs it forward-back at hip height. **He grips it at the
  middle** (user's call after the first build, 2026-09-25): 0.8 m ahead of his fist and 0.8 m
  behind. The first build gripped it 0.3 m off centre so most of it trailed. Note: a `Transform3D` in a `.tres`
  is row-major. The first pass wrote it column-major and mirrored everything.
- **`tests/test_pilot9_rim_light.gd`** now leaves the held item out of "every pilot mesh".
- **Test not written**: "HandSocket follows the *modified* pose". It needs a real skeleton update
  headlessly; judged in play instead.

## Tunables

| where | name | default |
|---|---|---|
| staff mesh | length / radius | 1.6 m / 0.025 m |
| staff.tres | `hand_offset`, `back_offset` | set in play |
| staff.tres | `hold_rotations` | solved from rest, tune live in play |
| item_holder | run gate | 0 at `walk_speed`, 1 at `speed` |
| modifier | blend time | 0.15 s |
| modifier | per-move list | table above |

## 2026-10-13: draw / holster animation

The `R` snap is now an animation: reach back, grab, a turn in the back plane, then settle. See
[pilot9-equip-holster.md](pilot9-equip-holster.md). `pilot9.toggle_drawn()` is still the instant snap.
