# Spec: the movement reset

> **Status:** built 2026-09-10, **unplayed**. 426 tests pass headless.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Touches:** `scripts/pilot9.gd` export defaults and their doc comments; two existing test
> files re-pointed at the mechanisms they cover; one new test file. No rebuild, no bake, no
> animation change, no new input action, **no logic changed** - not one line of the
> controller's behaviour was edited, only the numbers it starts with.
> **Restore point:** `db2fc2d`, which is the state being reset *from*.
> **Supersedes the shipping values of:** `docs/specs/pilot9-jump-feel.md`,
> `docs/specs/pilot9-slope-momentum.md`, `docs/specs/pilot9-slide-boost.md`. It does not
> supersede their *mechanisms* - every one of them stays in the file, switched off.

## Problem statement

2026-09-10, after the play session:

> *"theres something off about the jumping, the climbing, both need refining. and so does
> the sliding. it all just feels clunky. i think we need to pay less attention to inbetween
> animations. i know i was very thourough abot it not being snappy but our control over
> pilot needs to be increased. the climbing can be laggy and unresponsive at times,
> sometimes it doesnt even grab the ledge. the jump feels like youre not even getting off
> the ground."*

The last four passes each added a layer that decides something on the player's behalf. Taken
one at a time every one of them was defensible; stacked, they are why the controller reads as
clunky. **Between the stick and the body there are now eight things arbitrating**, and a
player who cannot predict which one is talking experiences all of them as lag.

The reset does not argue any single layer was wrong. It argues that **they were never felt
individually**, because each pass shipped on top of the last without a neutral baseline to
compare against.

## What is NOT a tuning problem

Worth stating plainly, because three of the four complaints do not answer to a number and
this spec deliberately does not fix them:

1. **The jump is invisible, not weak.** There is no `jump_land -> jump` transition in the
   state machine. A jump pressed shortly after landing routes
   `jump_land -> Locomotion -> jump` through 0.2 s + 0.1 s of stacked crossfade, so the leap
   is most of the way through its rise before the jump clip is visible. Neutralising
   `jump_cut` will help the *arc*; it will not make the takeoff read.
2. **The ledge probe is one ray.** `_probe_ledge()` casts a single forward ray at a fixed
   `climb_probe_height: 0.85` reaching `climb_probe_reach: 0.6` **from his centre** - and the
   capsule radius is 0.34, so the real grab range past his own body is about **0.26 m**. One
   ray at one height, needing all three casts to agree on a single frame, is why it sometimes
   does not grab.
3. **The mantle is 0.77 s of cutscene.** Position-driven with collision off and explicitly
   not cancellable. That is the "laggy" report, and no dial in this file shortens it.

Each gets its own spec after the baseline is felt. Fixing them *and* resetting in one pass
would leave nothing to attribute an improvement to, which is the mistake this spec exists to
stop repeating.

## The rule

**Every assist goes to its documented off value. Nothing is deleted.**

An off switch that was written into each dial's own range is the whole reason this is a
cheap, reversible change: `jump_cut: 1.0`, `jump_apex_scale: 1.0`, `momentum_decay: 0.0` and
the rest already mean "this layer is not running". The code paths stay live and stay tested;
they simply stop changing the answer.

What survives, and why:

- **`jump_height` / `jump_time_to_apex` stay as the jump's parameterisation.** They are not
  an assist - they are the two numbers that replaced one velocity against an unchosen
  gravity, and they are how the next pass will be tuned. The *values* reset to the arc
  pilot9 actually shipped and played with before 2026-09-10.
- **`speed`, `walk_speed`, `sprint_speed`, `crouch_speed`, `rotation_speed`, `slide_scale`,
  `slide_cooldown` and every `climb_*` probe are untouched**, because they are already at
  their authored defaults and always have been. The audit that found this is the reason the
  reset is as small as it is.

## The values

### Movement

| Dial | From | To | Why this is "off" |
|---|---|---|---|
| `jump_height` | 2.3 | **1.84** | The height the played-and-approved `jump_velocity: 6.0` arc actually reached. Every mantle band and map lip was tuned against it. |
| `jump_time_to_apex` | 0.38 | **0.61** | What 6.0 m/s under Godot's default 9.8 worked out to. Together with the row above this is the pre-2026-09-10 jump, expressed in the new parameterisation. |
| `jump_fall_multiplier` | 1.9 | **1.0** | Symmetric gravity. Real physics, and what he had. |
| `jump_cut` | 0.4 | **1.0** | Off. Every jump is the full arc again. This is the single dial most responsible for "not getting off the ground". |
| `jump_apex_speed` | 1.5 | **0.0** | Apex hang off. |
| `jump_apex_scale` | 0.6 | **1.0** | Apex hang off by the other switch too, so neither reads as half-enabled. |
| `max_fall_speed` | 28.0 | **28.0** | **Kept.** Not an assist - a terminal velocity, and without one a long drop integrates without bound. Unreachable inside the map's drops either way. |
| `coyote_time` | 0.1 | **0.0** | Off. Frame-exact edge launches, as before. |
| `jump_buffer_time` | 0.1 | **0.0** | Off. |
| `air_jumps` | 1 | **1** | **Kept.** A move, not an assist, and not complained about. |
| `momentum_decay` | 12.0 | **0.0** | Off. |
| `air_momentum_decay` | 0.0 | **0.0** | Already off. |
| `air_momentum_brake` | 40.0 | **200.0** | Neutral is the TOP of this range, not the bottom - see below. |
| `momentum_brake` | 60.0 | **200.0** | Same. |

#### The brakes have no zero, and 0.0 is a trap

This spec originally called for 0.0 on all four momentum dials, and tracing the code before
building found that wrong. A released stick puts `carried` above `target`, which enters the
momentum branch of `_apply_movement()` **whatever the brake is set to**. `_decayed_speed()`
then computes:

```
kept = maxf(carried - absf(brake) * delta, target)
```

At `brake: 0.0` that subtracts nothing and returns `carried` unchanged, every frame, forever.
pilot9 would coast at full speed across flat ground on a released stick and fly sideways off
every lip - which is not stock behaviour and is strictly *worse* than the feature being on. It
also re-opens the 2026-09-09 report, *"i need pilot to be able to fall down long pipes in a
straight line"*, which `air_momentum_brake` was added to answer.

Stock Real Controller has no momentum because it **assigns** the horizontal velocity outright:
`move_toward(velocity.x, 0, current_speed)`, deducting a whole `current_speed` per *frame*, or
about 300 m/s^2 at 60 Hz. That is an instant brake, not an absent one. So the neutral value is
the top of the range: **200.0**, which clears a sprint in 0.04 s - stock to within a frame or
two.

The two DRIVE dials do go to 0.0, and there 0.0 is honest: the drive rate is only ever paid
while pushing into speed already carried *above a sprint*, and with the slide's boost and
slope gain off, nothing grants him that any more.

Net effect: the stick's speed is written outright and a released stick stops him. That is the
most *controllable* the body can be, and it is the baseline the momentum feature should have
been judged against in the first place.

### Slide

| Dial | From | To | Why |
|---|---|---|---|
| `slide_entry_boost` | 1.35 | **1.0** | Burst off. Does **not** remove the floor - see below. |
| `slide_boost_time` | 2.0 | **0.0** | Burst off by the second switch as well. |
| `slide_slope_accel` | 1.0 | **0.0** | Off. The flat slide the clip describes, on any grade. |
| `slide_friction` | 2.0 | **2.0** | **Kept.** Only ever applied to `_slide_bonus`, which is now always 0. Inert, and leaving it alone keeps the dial's documented meaning intact. |
| `slide_max_speed` | 20.0 | **20.0** | **Kept.** A ceiling, not a push. |
| `can_auto_slide` | true | **false** | Off. Steep ground no longer takes the slide away from the player, which is exactly the class of thing "our control over pilot needs to be increased" is about. |
| `slide_auto_angle` | 35.0 | **35.0** | Inert while `can_auto_slide` is false. |
| `can_hold_slide` | true | **true** | **Kept.** The hold is a player *choice* - `crouch` again to stand - not an arbitration. |
| `can_buffer_slide` | true | **true** | **Kept.** Same argument: it spends a press the player made. |

#### The slide's speed floor has no off switch either, and is left standing

`_slide_speed_floor_at()` early-returns `reference` when `boost_time <= 0.0`, so with the
burst off the slide is still held at the speed he entered it at: a slide out of a sprint
carries **8.0 m/s** rather than falling to the clip's own ~5.2. Only a code change removes
that, and this pass is values only.

It is left standing deliberately. The floor is the one thing stopping the slide from being a
*brake*, and the cost of keeping it is that his feet no longer match the floor through the
run-in and run-out - which is exactly the trade the session asked for: *"i think we need to
pay less attention to inbetween animations."* If the foot slide reads badly in play, removing
the floor is a two-line change to that static and gets its own pass.

### Camera

Untouched. `docs/specs/pilot9-camera-collision.md` is not part of the complaint and its dials
are a fix for the lens clipping geometry, not a feel layer over the controller.

## What this should feel like

Honestly: **worse in places, and that is the point.** Expect the jump to float again - 1.22 s
of airtime on flat ground - and expect a slide down a hill to stop gaining speed. Those are
the two things the reset gives back, and both were real improvements.

What should improve immediately is **authority**. A stick release stops him. A jump is the
jump every time. Steep ground does not decide to slide him. Nothing between the press and the
body is second-guessing the input.

From there each layer comes back **one at a time, played between each**, in the order the
complaints rank them.

## Acceptance

Headless (`tests/run_tests.gd`) can only check that the switches are where this spec says and
that the mechanisms still behave when switched back on. It cannot check feel. Specifically it
**cannot** verify that the jump reads better, that the slide is controllable, or that any of
the three structural problems above are unchanged - those are the play session's to answer.

- [x] `tests/test_pilot9_jump_feel.gd` - **the assumption was wrong.** Four of its tests read
      the exports off the scene rather than passing values in, so they asserted the *shipping*
      arc and failed the moment it moved. Fixed by adding a `_tuned()` helper that applies the
      jump-feel pass's own values to the instance first: the tests now prove the mechanism
      still works when it is switched back on, which is what the reset promised. The one
      called `test_the_shipping_jump_is_the_specced_arc` is renamed
      `test_the_jump_feel_values_still_produce_the_specced_arc`, because it no longer
      describes what ships.
- [x] `tests/test_pilot9_slide_boost.gd` - same fault in two tests, same fix (`_boosted()`).
      `tests/test_pilot9_slope_momentum.gd` needed nothing: it was already parameterised.
- [x] `tests/test_pilot9_movement_reset.gd` - 13 tests asserting each parked value on a fresh
      instance, plus both traps pinned as executable text so the next reader cannot reach for
      `0.0` on a brake or quietly delete the slide's speed floor.
- [x] Full suite green headless: **426 tests, 1561 checks**. Verified the new file is actually
      discovered by the runner (413 without it, 426 with).
- [ ] **Played.** Then the worklog.

### What the tests could not check

Everything that matters. The suite confirms the numbers are where this spec says and that
each mechanism still behaves when handed its old values; it says nothing about whether the
jump reads better, whether the slide is controllable, or whether losing coyote time and the
jump buffer costs more than the jump cut was costing. It also does not touch the three
structural problems above, which are unchanged by design and will still be there in play.
