# Spec: the slide's playback rate

> **Status:** built 2026-09-11. **Played 2026-09-28 - feels good.**
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide.md` (the slide itself),
> `docs/specs/pilot9-slide-hold.md` (the hold, and the TimeScale this generalises),
> `docs/specs/pilot9-slide-boost.md` and `docs/specs/pilot9-slope-momentum.md` (the two
> speeds that ride beside the clip's). None of those rules change here.

## Problem statement

The slide reads slow. The clip is 1.25 s of run-in, hold pose and run-out, and played at the
rate it was authored it is a *long* move - the drop into it takes half a second before the
hold is even reachable. Asked for in one line: **the slide animation should play twice as
fast, and everything else should stay exactly as it is.**

`slide_scale` is not that dial. It multiplies distance and leaves duration alone, so a
faster slide built out of it is also a *longer* one - 1.25 s of clip covering twice the
ground, with the run-in still taking half a second to get him down. What is wanted is the
same slide, same distance, at twice the rate.

## The rule

**The slide's two clocks share one rate, and that rate is `slide_time_scale`.**

- The `slide` state's TimeScale is `slide_time_scale` while the clip runs and `0.0` while it
  is frozen. It was `1.0` and `0.0` before; frozen is unchanged.
- `_slide_time` advances by `delta * slide_time_scale`, so the distance curve is read at
  exactly the clip time the animation is showing.
- Everything measured in *clip* seconds is still measured in clip seconds:
  `slide_hold_time`, `slide_duration` and `SLIDE_SPEED_WINDOW` are untouched. The hold still
  begins on the clip's frame 30 and the run-out still ends at the clip's end.
- Everything measured on the *wall* clock stays on the wall clock: `slide_boost_time`,
  `slide_cooldown`, `slide_friction` and `slide_slope_accel` all keep integrating against
  real `delta`.

Default: **2.0**. `1.0` is the slide exactly as it shipped, and it is left an export so the
rate is a dial rather than an edit.

## Why this does not break the TimeScale rule

The rule (`_ensure_slide_state` in `scripts/pilot9_build_scene.gd`, and the guard test in
`tests/test_pilot9_slide_hold.gd`) used to read: *the scale is only ever 0 or 1, because the
state machine plays the clip on its own clock while `_slide_time` runs in
`_physics_process`, and the only thing holding them together is that both are real time.*

The reason was never "1", it was **"the same rate"**. A rate the controller does not mirror
drifts by the integral of the difference; a rate it mirrors exactly does not drift at all -
which is precisely why the hold's `0.0` was always legal. So the rule is restated rather
than broken:

> Both clocks may stop and start together, and both may run at `slide_time_scale`. Neither
> may run at a rate the other does not, and neither may run at a rate that *varies* - the
> crouch's eased scale right beside it is still exactly what must not be copied here.

The guard test now asserts the shared-rate write rather than the literal `1.0`, and a second
test asserts the controller advances its clock by the same export - the two halves checked
against each other rather than against a constant.

## What the player will feel

At 2.0, against the shipping bake (6.46 m over 1.25 s, hold at 0.50 s):

| | 1.0 | 2.0 |
|---|---|---|
| run-in to the hold pose | 0.50 s | 0.25 s |
| whole clip, hold off | 1.25 s | 0.625 s |
| distance over the whole clip | 6.46 m | 6.46 m |
| speed at the run-in's peak | ~8 m/s | ~16 m/s |
| held speed (the clip's contribution) | ~5 m/s | ~10 m/s |

**The slide is twice as fast on the ground, not just on screen.** That is the whole point of
the way the slide is built - `slide_motion` *is* the travel, and feet that agree with the
floor are the reason there is no speed constant anywhere near it. Playing the clip faster
and leaving the body at the old speed would be skate, which is the one thing every rule in
`pilot9-slide.md` exists to prevent.

Two knock-ons worth watching on the first play:

1. **A held slide is faster.** `_slide_hold_speed` is measured off the curve at the hold
   frame, so it doubles with the rate. A long descent therefore opens about twice as fast;
   `slide_max_speed` (20 m/s) is still the ceiling and is now nearer to hand.
2. **A short slide covers its 6.46 m in 0.625 s.** With `can_hold_slide` on this only affects
   the run-in and the run-out, which is what "the drop into it is too slow" was about.

## Tuning

One dial, in the inspector's **Slide** group:

- `slide_time_scale` - 2.0. How fast the clip plays and how fast the curve is read, together.
  Lower it to 1.0 to get the old slide back exactly.
- `slide_scale` is unchanged and still means distance. The two compose: rate 2.0 with scale
  1.5 is 9.7 m in 0.625 s.

## Tests

`tests/test_pilot9_slide_rate.gd`, plus the two updated guards in
`tests/test_pilot9_slide_hold.gd`:

1. The export exists, is positive, and is not in `SLIDE_BAKED` (a rig swap must not reset it).
2. `_drive_slide()` writes `slide_time_scale` and never a constant or a lerp.
3. The controller's clock advances by `delta * slide_time_scale` - measured, by stepping a
   slide with the hold off and demanding `_slide_time` come out at the scaled time.
4. The rate does not change the distance: integrating the whole clip at 1.0 and at 2.0 comes
   back to `slide_distance` both times.
5. The rate does scale the speed: the same slide at 2.0 peaks at twice the speed it does
   at 1.0.
6. The hold identity from `pilot9-slide-hold.md` still holds, with the clip's own duration
   converted to wall seconds by the rate.
