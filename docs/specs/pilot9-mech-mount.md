# Spec: pilot9 mounts EXIA

> **Status:** specified 2026-09-07. **Unbuilt.**
> **Scene:** `scenes/trial.tscn`. **Characters:** `scenes/pilot9.tscn`, `scenes/mech.tscn`.
> **Follows:** `docs/specs/exia-pilot.md`, which built the mech and Setsuna's climb into it,
> and `docs/specs/mech-camera-handover.md`, which built the pan. Neither changes here beyond
> one guard.

## Problem statement

EXIA is pilotable and pilot9 is the character being built, and the two have never met. EXIA
stands only in `test_platform.tscn` with Setsuna; `trial.tscn` has pilot9 and no vehicle.

The obvious next step - port Setsuna's climb to pilot9 - is the wrong one, and the reason is
in the clip. `SET embark` is 2 s of authored travel from one exact spot: `EmbarkPoint`, off
EXIA's flank, corrected for the power-down's root motion (`_mount_position()`). Put her a
metre out and she climbs into thin air. The whole sequence is angle-locked by construction,
and pilot9's own `P.sitting` - imported as `sit_down`, unwired, waiting for exactly this
feature - has the same shape.

**The user wants pilot9 to reach the machine from any bearing.** An authored climb cannot
give that, and an animation that only works from one approach is worse than no animation: it
makes the mech a thing you line yourself up with rather than a thing you run to.

So: no climb. **He walks up, presses F, and he is in it.**

## The rule

**Boarding is a cut. Exiting is a cut. There is no mount animation and nothing is
angle-locked.**

- Walk anywhere into EXIA's `InteractionArea` - a 12 x 9 x 12 box, so any bearing, any
  distance up to ~6 m, and any height up to the shoulders - and the prompt reads `F pilot`.
- **F**: pilot9 disappears on the frame it is pressed, the camera pans into EXIA's over 0.6 s,
  and the machine is drivable immediately. `MECH_launch` stands it up over that first ~2 s and
  walks it ~0.96 m forward under root motion; WASD works throughout.
- **F again**: `MECH_idle` powers it down, and pilot9 reappears at `ExitPoint` - 3.6 m out of
  the back of the machine - facing it, with his camera swung round behind him and the pan
  flying the view back into his shot.

## This path already exists

Nothing above is new behaviour in `mech.gd`. It is that file's own documented fallback,
written before the climb existed and kept working ever since: every call into the pilot is
`has_method`-guarded, and a pilot missing the climb methods is taken aboard on the spot
(`_enter_mech()` into `_board()`) and let out at `ExitPoint` (`_can_climb_down()` false, into
the cut in `_exit_mech()`).

**pilot9 is not eligible for it only because he answers to nothing.** `_on_body_entered()`
arms the prompt on `body.has_method("enter_vehicle")`, and `pilot9.gd` has no vehicle methods
at all. The feature is therefore two methods on pilot9 and one guard on the mech.

## The pilot contract

Six methods make a pilot. Setsuna has all six; pilot9 gets the two that are not the climb.

| Method | Setsuna | pilot9 | What its absence means |
|---|---|---|---|
| `enter_vehicle(vehicle)` | yes | **new** | not a pilot at all - the prompt never arms |
| `exit_vehicle(pos, yaw)` | yes | **new** | no way back out |
| `embark_length()` | yes | no | no climb; board on the spot |
| `begin_embark(pos, yaw)` | yes | no | no climb; board on the spot |
| `ride(seat)` | yes | no | **see the guard below** |
| `begin_unseal()` / `begin_disembark()` | yes | no | no descent; cut to `ExitPoint` |

Duck-typed, as it already is - `mech.gd` names no pilot class and must not start.

## The guard: `mech.gd::_board()`

**`seal_left` is gated on `pilot.has_method("ride")`.** This is a live crash, not a
refinement.

`_board()` starts the canopy-close beat whenever the cockpit bone and `MECH_launch` both
exist. It does not ask whether the pilot can be carried. For the ~2 s of `MECH_launch` the
piloting branch of `_physics_process` then calls `pilot.ride(seat_follow(...))` every frame -
and pilot9 has no `ride()`. The first pilot9 to press F takes the machine down with him.

The right condition is the pilot's, not the mech's: the beat exists so the pilot is *seen*
riding the closing cockpit, and there is nobody to see when the pilot has already been hidden
on the spot. With the guard, a climbless pilot is taken aboard by `enter_vehicle()` inside
`_board()` - the branch already written for a mech with no launch clip - and the boot-up
finishes without him. Setsuna's beat is untouched, and `_exit_mech()` needs no matching
change: `_can_climb_down()` already requires `begin_unseal`, so `unseal_left` never arms for a
pilot without it.

## `pilot9.gd::enter_vehicle()`

Four steps, the same four as `player.gd::_hand_over_controls()`, plus the tree, plus his
verbs:

```
velocity = Vector3.ZERO
collision_shape.disabled = true
set_physics_process(false)
set_process_unhandled_input(false)
anim_tree.active = false
visible = false
```

`pilot9.gd` holds no reference to the AnimationTree today - it is driven entirely from the
sibling `Animation` node - so an `@onready var anim_tree: AnimationTree = $AnimationTree` is
added for this. `pilot9_animation.gd::_process` keeps running and keeps writing blend
positions into an inactive tree, which is harmless: it writes parameters and never calls
`travel()`.

### Clearing his verbs

pilot9 carries live state Setsuna does not, and F can be pressed in the middle of any of it -
the interaction box is 9 m tall and he can be sliding, crouched, or mid-mantle inside it.
Boarding therefore **ends** them rather than freezing them:

- `_end_climb(false)` if `is_climbing` - the same "land him on top" stop a freeze mid-mantle
  already takes, and for the same reason: his collision shape is about to be disabled while he
  is being written along a path over an edge.
- `_end_slide()` if `is_sliding` - which also clears `is_slide_holding` and arms the normal
  cooldown.
- `is_crouching = false`, `sprint_toggled = false`, `is_sprinting = false`,
  `is_walking = false`, `_slide_cooldown_left = 0.0`.

A held slide is the case that makes this non-optional: `is_slide_holding` is unbounded by
design, so without this he boards, drives a kilometre, gets out, and resumes a slide he
started somewhere else.

## `pilot9.gd::exit_vehicle(exit_position, facing_yaw)`

The mirror image, landing him in idle. His rig is shaped differently from Setsuna's, and the
same intent writes different nodes:

| Intent | Setsuna | pilot9 |
|---|---|---|
| stand here | `global_transform` rebuilt from scratch | `global_position` - his basis was never touched, because nothing ever rode him |
| face the mech | `rotation.y` (the body) | `character.rotation.y` (the mesh child; the body's yaw is never written) |
| camera behind him | `camera_yaw` field, then `camera_pivot` | `camera_pivot.rotation.y` directly - it *is* the world yaw, the body being unrotated |
| camera pitch | `camera_pitch` field | `camera_pivot.rotation.x` |
| take the picture | `camera.current = true` | `camera_3d.current = true` |

**Facing.** `character.rotation.y = facing_yaw`, and the value needs no correction. pilot9's
mesh convention is that `character.rotation.y = atan2(h.x, h.z)` faces heading `h`
(`_handle_character_rotation`), and the mech passes `rotation.y`, whose nose is
`facing_for(yaw) = (sin yaw, 0, cos yaw)`; `atan2` of that is `yaw` itself. `ExitPoint` is out
of the *back*, so facing along the machine's nose is facing the machine. Identical in value to
Setsuna's line, arrived at through a different node.

**Camera.** `camera_pivot.rotation.y = facing_yaw + PI` and `rotation.x = EXIT_PITCH`. Behind
him, looking at the machine he just climbed out of - `mech-camera-handover.md`'s rule, and the
fix for the bug where the handback dropped the pilot staring at their own back. The 0.6 s pan
into it comes free: `mech.gd::_exit_mech()` reads the viewport camera after `exit_vehicle()`
has made his current, and flies the view into it.

**Restoring him.** `visible = true`, `collision_shape.disabled = false`,
`velocity = Vector3.ZERO`, `set_physics_process(true)`, `set_process_unhandled_input(true)`,
`anim_tree.active = true`, and the state machine started at **`Locomotion`**. Not `idle` -
pilot9's tree has no `idle` state; idle is a corner of the `Locomotion` blend tree, and
`Locomotion` is what `playback.start()` has to be given. Started outright rather than trusting
the advance expressions to walk back: board him mid-jump and the tree is parked in `jump` or
`fall`, and he steps out of a powered-down mech onto flat ground.

## `trial.tscn`

- `EXIA`, instanced from `scenes/mech.tscn`, standing ~12 m in front of spawn on the flat with
  its nose toward the spawn point - visible the moment the scene boots, a couple of seconds'
  walk, and far enough out that approaching it from a chosen bearing is a real exercise of the
  interaction box. Nothing in code depends on the transform; nudge it freely.
- `ApplyCelMech`, a `scripts/rendering/apply_stylized.gd` node with `cel_character` and
  `derive_from_surfaces`, targeting `../EXIA/Model` - copied from `test_platform.tscn`, where
  the mech's cel pass already lives.

`trial.tscn` has no catch-all floor (`test_platform.tscn` carries a `WorldBoundary` 35 m
down). EXIA has gravity, so a transform off `TrainingV`'s collision falls forever. Placing it
on the flat is the whole mitigation; no floor is being added.

## Decisions

| | Taken | Over |
|---|---|---|
| The mount | No animation. F is a cut both ways | Porting Setsuna's climb, or authoring one from `P.sitting`. Both are authored travel from one exact spot, which is the angle-lock this feature exists to escape |
| Setsuna's climb | Left entirely alone | Deleting it. `test_platform.tscn` still runs SETSUNA + EXIA and `test_mech.gd` covers the sequence; this change is purely additive |
| The `ride()` crash | Gate `seal_left` on `pilot.has_method("ride")` | A no-op `ride()` on pilot9, which buys 2 s of dead time with nothing on screen to explain it, purely to satisfy an interface |
| Exit spot | `ExitPoint`, 3.6 m out the back | Remembering the bearing he boarded on, or exiting where the camera looks. Both are new rules serving an entry freedom that already works, and the day a climb-out exists the clip dictates the spot anyway |
| Exit camera | Behind him, facing the machine | Keeping the mech camera's yaw, or restoring the yaw he walked up on. Parity with Setsuna, and the pan is already built for it |
| Boarding mid-verb | Ends the verb | Refusing F, or freezing the verb to resume later. A slide hold is unbounded; resuming one across a drive is worse than losing it |
| `sit_down` | Stays imported, stays unwired | Dropping it from the builder's `GLB_CLIPS`. It costs nothing and it is the seed of whatever a mount animation eventually becomes |
| Exit ground check | None | A downward probe before placing him. Setsuna has the same hole and it has never bitten; inventing a probe here would be the only unshared code between the two pilots |
| `run/main_scene` | Unchanged (`test_platform.tscn`) | Flipping it to `trial.tscn`. That is a separate decision about which character the project is about, and Setsuna stays maintained |

## Risks

1. **Exit into geometry.** `ExitPoint` is a fixed offset with no ground check. Park EXIA
   against one of the trial's blocks, or on a slope, and pilot9 can pop out embedded in it or a
   metre up (gravity handles the second case, not the first). Inherited from Setsuna's cut, now
   reachable far more often because the trial has blocks and `test_platform` did not. Untested
   by anything headless - it is a play-session finding.
2. **`MECH_launch` travels while you drive.** Board and hold W and the machine is standing up,
   walking its own ~0.96 m of root motion, *and* taking your input, all at once. Existing
   behaviour that Setsuna never saw, because her canopy close ate those frames. It may read as
   a lurch; it may read as weight. Unjudged.
3. **The board is abrupt on purpose.** No fade, no delay - he is there and then he is not, with
   only the 0.6 s camera pan to carry it. That is the point of the feature, and also the thing
   most likely to want a beat of something later.
4. **Two pilots, one contract, and no interface holding them together.** Duck typing is right
   for `mech.gd`, but nothing now asserts the two pilots answer to the same shapes. A rename on
   one side degrades silently into a fallback rather than erroring - which is exactly what
   `has_method` is for, and exactly what makes it invisible. The tests below pin the contract
   from both sides for that reason.

## What this does not do

- **No mount or dismount animation**, and `sit_down` stays out of the state machine.
- **Nothing for Setsuna.** `player.gd` is untouched; `mech.gd` gets one guard that cannot fire
  for a pilot with `ride()`.
- **No new input action.** `mech.gd` still reads raw `KEY_F`. `ui_accept` is also bound to F,
  but nothing in `trial.tscn` consumes it.
- **No mech tuning.** Speed, ramp, turn rate, camera distance, root motion: all unchanged.
- **No HUD.** The `F pilot` / `F exit` prompt in `mech.tscn` is the entire UI.
- **No `main_scene` change**, and no floor added to `trial.tscn`.

## Test coverage

**New: `tests/test_pilot9_mech.gd`**

- pilot9 answers `enter_vehicle` and `exit_vehicle`, and answers *neither* `ride` nor
  `begin_embark` - the contract from both ends, so a climb quietly appearing is caught too
- `enter_vehicle()` hides him, disables the collision shape, and stops his physics and input
- boarding mid-slide, mid-held-slide, mid-crouch and mid-mantle leaves none of those flags set
- `exit_vehicle()` puts him at the given position, faces `character` along the given yaw, puts
  `camera_pivot` half a turn round from it, and makes `camera_3d` current
- `exit_vehicle()` restores physics, input, collision and the anim tree, and starts the state
  machine at `Locomotion`
- a board/exit round trip through a real `mech.tscn` leaves him where `ExitPoint` is and the
  mech unpiloted
- `trial.tscn` carries `EXIA` with `mech.gd` on it, and an `ApplyCelMech` targeting
  `../EXIA/Model` with a material

**Amended: `tests/test_mech.gd`** - a climbless pilot boards with `seal_left` at 0 and is
hidden on the frame F is pressed; a pilot with `ride()` still gets the canopy beat.

**Amended: `tests/test_pilot9_retarget.gd`** -
`test_trial_has_exactly_one_camera_and_it_is_the_rc_rig_camera` counted every `Camera3D` in the
scene, which EXIA's two break. It becomes: exactly one camera has `current == true`, it lives
under `Pilot9/CameraPivot`, and EXIA's two are both false. Strictly stronger - the old count
never checked that a *wrong* camera was not current.

**Amended: `tests/test_pilot9_crouch.gd`** -
`test_sit_down_is_imported_but_not_in_the_state_machine` keeps its assertions; only its comment
changes, from "until the mech handover exists" to saying the handover exists and is
deliberately animation-free.

**Not covered headlessly:** whether the cut reads as a mount, whether the launch-while-driving
lurches, and where `ExitPoint` puts him on the trial's uneven ground. Play session.
