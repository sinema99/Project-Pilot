# Spec: pilot9's held slide

> **Status:** built 2026-09-07. **Unplayed** - the feel is unjudged.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide.md`, which built the slide this changes the *middle*
> of, and `docs/specs/pilot9-jump-slide.md`, which changed its entry. Neither entry route
> changes here.

## Problem statement

The slide as built is a 1.25 s verb with a fixed length. It travels 6.46 m and then stands
him up, whatever the floor is doing. Two things the player wants are therefore impossible:

1. **Sliding down a slope.** A slope is longer than 6.46 m. Getting down one means a queue
   of slides, each with a 0.4 s cooldown and a stand-up in between - which is a stutter, not
   a descent.
2. **Sliding further, deliberately.** `slide_scale` stretches the whole clip, so a longer
   slide is also a *faster* one over the same 1.25 s. There is no way to simply stay down.

The clip has the answer already. At frame 30 of the Blender action he is fully down on the
floor with the pose settled - the user picked it by eye - and that pose is holdable for an
unbounded length of time. Everything before it is the drop into the slide; everything after
it is coming back up. The clip is a run-in and a run-out with a perfectly good hold pose
sitting between them, and the old build played straight past it.

## The rule

**The slide parks on its hold pose and stays there until the player says otherwise.**

- `crouch` at a sprint starts a slide - unchanged, both entry routes included.
- 0.50 s in (frame 30) the clip and the distance curve **both stop**. He carries on at the
  speed he had reached, in the direction he is steering, for as long as the player leaves
  him there.
- **`crouch` again** ends the hold. *(Built 2026-09-07 to resume the clip and play out the
  run-out; **revised the same day** - `docs/specs/pilot9-slide-crouch.md` - to end the slide
  on the press instead. The clip does not resume; `slide -> crouch` blends the held pose
  straight into the crouch, and he ends **crouched**, not standing.)*
- **`jump`** ends the slide outright, on the frame it is pressed. The run-out does **not**
  play; the leap cuts straight in from the held pose. This is the only exit that ends
  standing.

Everything else about the slide is untouched: the entry conditions, the cooldown, the
steering, the run-in, the run-out, and coming off a ledge mid-slide.

## Why frame 30

Quoted on Blender's timeline, at 60 fps, exactly like `SLIDE_KEEP_FRAMES` - so 0.500 s into
the trimmed 1.25 s clip. Against the window table in `pilot9-slide.md` that lands early in
the third row (`0.37 - 0.87 s`, on the ground and decelerating, ~6.1 down to 3.4 m/s): he is
down, he is settled, and the pose is not yet reaching for the stand-up.

It is the one number in this feature chosen by eye rather than measured, which is right - it
is an animation judgement about a pose, and the animator is the one who can see it.

The builder **refuses** a hold frame at or past the trim rather than clamping it. The two
constants describe different intentions (`SLIDE_KEEP_FRAMES` cuts the run-out short,
`SLIDE_HOLD_FRAME` picks a pose), and silently reconciling them would produce a slide that
holds somewhere in the stand-up.

## The speed during the hold

**Constant. No friction, no gravity term along the floor.** The user's call, taken over an
alternative that added a slope-acceleration and a friction constant.

The value is *measured, not declared*: it is the clip's own forward speed across the 50 ms
ending at the hold frame, read off `slide_motion` the moment the hold begins
(`_slide_speed_at()`). So the entry into the hold is continuous by construction, it scales
with `slide_scale` like everything else does, and there is no number here to keep in tune
with the animation. Re-author the clip and it re-derives.

A window rather than a two-sample derivative because `slide_motion` is 64 linear segments -
a derivative across less than one segment reads that segment's slope alone and steps as the
sample point crosses a knot. This number is then held for an unbounded time, so unlike the
per-frame difference `_apply_slide_velocity()` uses, an error in it never washes out.

### What this means on a slope

The horizontal velocity is constant and `velocity.y` is left to gravity, so `move_and_slide()`
projects that constant along the floor and he follows the slope down. That is the whole of
"slide down slopes": he does not accelerate downhill, he simply does not stop, and a slope
of any length is now one slide.

On the flat it means he coasts at a fixed speed indefinitely. That is the literal shape of
what was asked for - *stays sliding until the player presses* - and it is the thing most
likely to want revisiting after a play: a hold that never decays is free travel.
`can_hold_slide` off restores the old behaviour without a rebuild.

## The seam

The frame that crosses into the hold is **split** between the two speeds: the curve is read
up to exactly the hold frame, and the remainder of that frame is already travelling at the
hold speed.

Neither rounding works. Give the whole frame to the curve and it travels metres the run-out
covers again when it resumes from the same point. Give it to the clock and a part-frame's
distance gets divided by a whole `delta`, dropping his speed for one frame - a hitch on the
exact frame the hold is meant to be seamless. Splitting is exact in both, and the identity
that says so is asserted directly:

```
travelled == curve travel up to _slide_time + hold_speed * (elapsed - _slide_time)
```

Run to the end of the clip, `_slide_time` is `slide_duration` and the first term is the whole
`slide_distance` - the held metres are additive and nothing at the seam is lost or doubled.

## The animation side, and the rule that was broken to get here

`pilot9-slide.md` said, emphatically, that a TimeScale must never go near the `slide` state:
the state machine plays the clip on its own clock while `pilot9.gd::_slide_time` runs in
`_physics_process`, and the only reason those two agree is that both are real time.

That reasoning still holds, and the hold does not break it - it uses it. The `slide` state is
now the clip through an `AnimationNodeTimeScale` (`SlideScale`), and
`pilot9_animation.gd::_drive_slide()` writes it **hard 0 or 1** off `is_slide_holding`. Both
clocks stop on the same flag and start again on the same flag, so the offset between them
coming out of a hold is the offset they had going in - however long the hold was.

What remains forbidden is a *rate* other than 1. The crouch's eased scale sitting right
beside it in the same file is exactly what must not be copied here: an ease would drift by
its own integral on every hold, and the animation never gets that back. A test asserts the
shape of the write, not just its value, for that reason.

## Decisions

| | Taken | Over |
|---|---|---|
| Hold mechanism | One clip, frozen by a TimeScale | Splitting the clip into `slide_hold` + `slide_out` with two states. Cleaner on paper - each state plays its own clip start to finish, no shared clock at all - but it doubles the bake (two curves) and the trim machinery to avoid a drift that a hard 0/1 scale does not have. |
| Hold speed | Constant, measured off the curve | Slope gravity + friction, with an auto-stand at a minimum speed. The user chose constant; it adds no tuning surface and does exactly what was asked. |
| The crossing frame | Split between curve and hold | Rounding either way - both are wrong by about a frame of travel, in opposite directions. |
| Ending the hold | `crouch` resumes the clip from the hold frame | Restarting the clip, which would replay the drop into a slide he is already in. *(2026-09-07: superseded - `crouch` now ends the slide on the press, no run-out, straight into the crouch - `docs/specs/pilot9-slide-crouch.md`.)* |
| Jump out | Ends the slide outright, no run-out | Playing the run-out first. The user's call and obviously right: standing up and *then* jumping is not what the button asked for. *(2026-09-07: also the only slide exit that still ends standing.)* |
| Off switch | `can_hold_slide`, an inspector bool | Ripping it out if the feel is wrong. The old behaviour is one checkbox away and the tests hold it green. |

## Risks

1. **The two clocks.** The mitigation is the hard 0/1 above, and the tests pin both halves -
   the parameter path the builder builds against the one the animation script writes, and
   the literal shape of the write. What none of them can catch is the AnimationTree running
   in `_process` while the controller runs in `_physics_process`: the freeze lands within a
   render frame or so of the crossing, so he can park on frame 29 or 31 rather than 30. It
   is a pose either side of a settled pose and it does not accumulate.
2. **Coasting forever on the flat.** Called out under "What this means on a slope". This is
   the one the play will judge.
3. **A re-export that moves the pose.** `SLIDE_HOLD_FRAME` is a frame number, not a feature
   of the animation, so a re-authored `P.slide` can leave the hold on a different pose while
   every test still passes. The builder prints the frame and its seconds on every sync;
   `docs/reimport.md` step 4 is where that gets looked at.
4. **A hold entered off a cliff edge.** Unchanged from the old slide - `is_on_floor()` false
   ends it and `fall` takes over - but the window is now unbounded rather than 1.25 s, so it
   will happen far more often. Believed correct; unplayed.

## What this does not do

- **No maximum hold.** Deliberately - the ask was "until the player presses".
- **No slope acceleration.** He does not pick up speed downhill; see the decision table.
- **No steering change.** `_steer_slide()` runs through a hold exactly as it does through
  the rest of the slide, at `rotation_speed`.
- **No new input action.** `crouch` in, `crouch` out, `jump` to cancel.
- **Nothing for Setsuna.** Her animation tree is untouched.

## Test coverage

`tests/test_pilot9_slide_hold.gd`, 15 tests:

- the hold time is `SLIDE_HOLD_FRAME` at `SLIDE_SOURCE_FPS`, is inside the trimmed clip, and
  is a baked property the builder owns
- the clock stops **exactly** on the hold frame, and the slide outlives the clip by 8x
- the hold speed is flat over 5 s, is a plausible measurement of the curve where it parked,
  and carries `slide_scale`
- `can_hold_slide` off and a zero `slide_hold_time` both play the clip straight through
- leaving the hold resumes the run-out rather than restarting it, and does not fall back in
- the seam identity above, over a full run-in / hold / run-out
- the TimeScale parameter path, from both sides, and the hard-0/1 shape of the write

`tests/test_pilot9_slide.gd` keeps the pre-hold assertions: its integration tests now run
with `can_hold_slide` false, which is a shipping configuration in its own right.
