# pilot9 crouch: code kneel + Arma crouch jog

Grilled 2026-11-15. Replaces the Blender `P.crouchwalk` clip (`crouch_walk`), which is scrapped:
it is no longer lifted out of pilot9.glb, and nothing plays it.

## What the user asked for

- Crouched and not moving: **a kneel** - one knee on the ground, one foot planted, like the
  DayZ (Arma 2 mod) rifle kneel reference.
- Crouched and moving: a crouch walk **like DayZ / Arma 2's**.
- Both generated **from code**. **The gun's resting position and the upper body are not touched.**

## Decisions

| # | Question | Answer |
|---|----------|--------|
| 1 | What "upper body untouched" means | Only Hips (position, plus a constant rotation) and the legs (UpperLeg, LowerLeg, Foot) are generated. Spine, chest, neck, head and arms come from the standing pose. The torso rides down on the hips and stays upright. The old clip's ~22 deg UpperChest hunch goes with it. |
| 2 | Direction | **Directional, like normal movement.** He faces camera-back; A/D strafe and S backpedals. Forward / back / left / right cycles from code, diagonals by blending. Crouch leaves `_faces_travel()`. |
| 3 | Speed | `crouch_speed` stays **5 m/s** "for now". So the moving gait is a deep crouch *jog*, not a creep. |
| 4 | Which knee | **Right knee down, left foot forward**, always. |
| 5 | Kneel <-> move | Crossfade inside the state: **0.25 s down** into the kneel, which only starts after **0.15 s** of no input; **0.12 s up** into the jog. Entering crouch stood still goes straight to the kneel. |
| 6 | Upper body source while crouched | The **standing idle** (calm, breathing) in both the kneel and the jog. The jog's life is a hip bob and side sway generated with the legs. Kneel legs are still. |
| 7 | Camera | `camera_crouch_drop` **0.35 m**, crouch only (the slide keeps 0), the same in kneel and jog. |
| 8 | Depth | Jog hips **0.40 m** below the idle's; kneel lower (spec said ~0.55, measured on the rig). Exported constants. |

## How it is built

- `scripts/crouch_bake.gd` - static, no scene state. Two-bone leg IK in skeleton space against
  pilot9's rest pose, writing absolute local rotations (the same convention RC's clips use).
  - `kneel(skel, idle)` -> `crouch_kneel`: one pose, keyed once, looped.
  - `jog(skel, idle, dir)` -> `crouch_jog_forward/back/left/right`: one cycle each, the same
    length and the same phase (left foot touches down at t = 0), so the blend space keeps the
    feet in step. Stance: foot planted, sliding back under him at exactly the design speed
    (so the TimeScale = ground speed / design speed keeps the feet from skating). Swing: an arc forward.
    Sideways cycles stagger the feet fore/aft so the legs pass rather than cross through each other.
  - The Hips rotation is the idle's first key, held - the thigh angles are solved against it, so
    the feet land where the bake put them whatever the spine does above.
- `crouch` state (rebuilt by `_ensure_crouch_state`): `Idle` and the legs layer in a Blend2 with
  a **filter** on Hips + the six leg bones, amount 1. The legs layer is `Kneel` and
  `JogSpace` (BlendSpace2D, the four cycles at the RC run positions) through `CrouchJogScale`,
  mixed by `CrouchMove` (Blend2). Everything outside the filter is the idle's.
- `pilot9_animation.gd::_drive_crouch` feeds the travel blend, the jog rate and the
  kneel/move amount (timings above). Out of the crouch the amount is snapped to "moving or not"
  so the state is entered on the right pose.

## Not in scope

- Collision capsule height, crouch speed changes, a crouch run on Shift, knee-down/rise one-shots.
- The trench coat's crouch pool is left as it is; checked in the probe shots only.

## Built

2026-11-15. Measured on the rig: kneel hips 0.46 m under the idle's, right knee joint 0.07 m off the
ground. **Jog depth is 0.36, not 0.40**: with the planted foot behind him the thigh hangs vertical
and the knee sits at hip height minus the 0.51 m thigh, so 0.40 put it on the floor. The stride is
shifted 0.25 m ahead (`JOG_FOOT_AHEAD`) and the planted phase cut to 27% of the cycle, which keeps
the lowest knee ~0.13 m up. Probe shots of the kneel, forward and left jog looked right. Not yet played.

## Rev 2: Arma kneel + forward lean (2026-11-15)

Played verdict: "it looks so dumb". The kneel's legs were too far apart, and the crouch walk's upper
body did not move at all (upright idle torso on folded legs read as sitting on a stool). Grilled 4.
**Supersedes decision 1** (upper body untouched) and the kneel geometry and camera of decisions 7-8.

| # | Question | Answer |
|---|----------|--------|
| 1 | What looks dumb | Kneel legs too wide; the walk's torso never leans. |
| 2 | The lean | **~25 deg forward** in the walk, spread over Spine / Chest / UpperChest; neck + head turn back by the same so his gaze stays level; arms and gun ride with the chest. Kneel **~10 deg**. All four directions. **Off while aiming** (the aim IK bends the spine itself). |
| 3 | The kneel | Like the user's Arma 2 reference: rear thigh **~10 deg** back (was 42), knee almost under the hip, shin straight back, toes curled under; front shin vertical, foot straight ahead; both legs in toward the centreline. Taller than before. Camera drop **0.25 m kneel / 0.35 m walk**, mixed by the kneel/jog blend. |
| 4 | The walk's legs | Hips sat back over the heels (feet less far ahead) so the knees stop jutting; foot spacing **0.17 -> 0.13 m**. Depth stays 0.36. |

### Built

- `scripts/crouch_lean.gd`: a SkeletonModifier3D added in `pilot9.gd::_setup_idle_arm`, before the item
  holder's, so the arm hold and aim IK read the leaned chest. `pilot9_animation.gd::_drive_crouch`
  writes `crouch_target` (crouching and on the floor), `move` (the CrouchMove mix) and `aim` (the
  arm modifier's `ik_weight`). Eased in/out over 0.25 s. The clips are still hips + legs only.
- `crouch_bake.gd`: `KNEEL_THIGH_BACK` 10, `KNEEL_KNEE_IN` 0.05, `KNEEL_FRONT_IN` 0.03, toe-out 3,
  front knee pole straight ahead; `FOOT_SPREAD` 0.13; `JOG_FOOT_AHEAD` 0.25 -> **0.18**.
- **Deviation:** the grill said hips 0.1 m back (0.15). That put the back jog's trailing knee 0.078 m
  off the floor, under the test's 0.1 m guard; 0.18 (0.07 m back) is the furthest that clears.
- `pilot9.gd`: new `camera_kneel_drop` 0.25; the drop target lerps kneel -> walk on `crouch_lean.move`.
- Probe shots looked right (kneel matches the reference from the side; the walk leans with level
  head). Not yet played.

## Rev 3: the crouch walk, rebuilt by eye (2026-11-15)

Played verdict on rev 2: the kneel is good, the crouch walk still bad. User: "just give me a crouch walk
that looks good", then "have the arms move too". No grill; judged from side-view strips of the whole
cycle (`tests/_probe_coat_shot.gd` poses cf0-3 / cfo0-3).

- What was wrong: 1.5 m steps (5 m/s on a 0.6 s cycle), a 0.36 m sit with the feet thrown ahead
  (the stool look), and a lean that only hunched the spine.
- Gait (`crouch_bake.gd`): `CYCLE` 0.42 s, `STANCE` 0.3, `JOG_HIPS_DROP` 0.26 (shallower),
  `JOG_FOOT_AHEAD` 0.2, `SWING_LIFT` 0.22 peaking early (heel kicks up behind, the shin no longer drags
  flat along the floor). Speed still 5 m/s.
- Hip hinge: new `JOG_HIPS_PITCH` 20 deg baked into the jog's Hips rotation (legs solved against it).
  `crouch_lean.gd` adds 12 on the spine (kneel keeps 10), head takes back 80%, and while aiming the
  spine also takes the hip pitch back out so the aim IK starts upright.
- Arms: `add_arms()` keys the run clip's arm pump onto the jog cycles, phased to the legs by FK on
  the run clip's left foot (forward 1.0, back 0.8, sideways 0.5 of the way from the idle's arms).
  The kneel keys the idle's arms. The filter now covers the arms; a held item still overrides them.
- Camera: walk drop 0.35 -> 0.25 to match the shallower walk; kneel 0.25.
- Tests: crouch 20 / 90, camera 59 / 499, aim IK 8 / 59 green. Not played.

## Rev 4: DayZ crouch walk (2026-11-15)

User, with a DayZ screenshot: "make the crouch walk slower, more lean and arms don't swing as much, I
want them to hang forward just like this photo". Built from side/front cycle strips.

- **Slower:** `crouch_speed` 5.0 -> **2.5** (= `walk_speed`; the old "matches the run" rule and its
  two tests now pin the walk speed). Bake `DESIGN_SPEED` 2.5, `CYCLE` 0.58 s, `STANCE` 0.55 (a walk,
  double support), `JOG_FOOT_AHEAD` 0.2, `JOG_HIPS_DROP` 0.22, `SWING_LIFT` 0.14, `BOB` 0.02.
- **More lean:** `JOG_HIPS_PITCH` 26 + spine `jog_degrees` 14 = ~40 deg.
- **Arms hang:** run-pump share cut to 0.25 forward / 0.2 back / 0.12 sideways; new
  `crouch_lean.gd` `arm_hang` 0.6 turns the upper arms back by 60% of the chest's pitch, so they hang
  a little ahead of plumb instead of riding the chest out front (off while aiming, like the lean).
- Tests: crouch 20 / 90, camera 59 / 499, aim IK 8 / 59, movement reset 13 / 54, slide stand 8 / 20
  green. Not played.

## Rev 5: more lean, arms forward (2026-11-15)

- Lean ~50 deg: `JOG_HIPS_PITCH` 32, spine `jog_degrees` 18.
- Arms out ahead of the front knee (the user's red line): `arm_hang` renamed **`arm_forward`** = 1.2
  (the upper arms swing forward by 1.2 x the chest's lean). Rev 4's comments had the sign backwards
  (a hanging arm turned about +X goes BACK), so the user's "more forward" first pulled them back.
- Probe-shot only. Not played.

- Rev 6: `crouch_lean.gd` `arm_out_degrees` 6 (12 was too wide) - both upper arms swung out from the waist (crouched, off while aiming). Probe-shot, not played.
