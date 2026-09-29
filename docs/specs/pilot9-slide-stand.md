# Spec: a slide stands up

> **Status:** built 2026-09-09, **played 2026-09-28 - feels good**.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Supersedes:** `docs/specs/pilot9-slide-crouch.md` in full. That spec's rule - "a slide
> hands off into a crouch" - is reversed here, and the `slide -> crouch` transition it added
> is removed. Everything else it decided (where `is_crouching` is written, the
> `not is_crouching` slide-start guard) survives, because it was never about the crouch
> hand-off.
> **Follows:** `docs/specs/pilot9-slide-hold.md`, whose "leaving the hold" rule this restores,
> and `docs/specs/pilot9-slide.md`, whose "it ends standing, not crouched" decision this
> restores. Neither entry route, the run-in, the steering, the hold, the slope momentum, the
> cooldown, the ledge exit nor the jump exit changes.

## Problem statement

The 2026-09-07 pass made every slide end in a crouch. Played on 2026-09-08 it is wrong for
one reason, and it is a movement reason rather than an animation one:

> "it does not feel good coming out of a slide and then going super slow cause your
> crouching"

`crouch_speed` is 1.6 m/s. A slide arrives at anywhere from 5 m/s (the clip's own run-out)
to `slide_max_speed` (20) coming off a grade, and the hand-off dropped him from that to a
1.6 m/s shuffle the instant he pressed the button that ended it. `_apply_movement()` does
carry the speed out of the slide - it decays rather than assigns - but a crouch sets the
decay target to `crouch_speed` and it is gone inside a second. The move that exists to *gain*
speed ended by spending all of it, and in a parkour platformer (see `docs/game-overview.md`,
2026-09-08) that is the wrong end for the fastest move in the kit.

The crouch hand-off answered a real question - "he is low, why does he pop up?" - but the
answer cost the run. Standing up is the cheaper mistake: it costs a pose, not a chase.

## The rule

**Every exit from a slide ends standing.** The crouch is no longer any part of a slide.

- `crouch` out of the hold **resumes the clip**: `is_slide_holding` goes false, the run-out
  (frames 30-75, his hips travelling from the settled floor pose back up to standing) plays,
  and when `_slide_time` reaches `slide_duration` the slide ends into standing Locomotion.
  This is exactly the hold's original exit, restored.
- The run-out is a **stand-up**, so it is played and not cut. It was cut in
  `pilot9-slide-crouch.md` because it stood him fully up and then a 0.2 s fade dropped him
  into `crouch_walk` - a visible bob. With nothing to drop into afterwards there is no bob:
  the run-out ends at standing height and `slide -> Locomotion` blends standing to standing.
- The run-out also **keeps him fast**. It is driven off `slide_motion` like the rest of the
  slide, so it carries him at the clip's ~5 m/s plus whatever `_slide_bonus` a grade earned,
  and `_apply_movement()` then decays that toward a sprint rather than toward 1.6.
- A slide with **no hold** (`can_hold_slide` off, or a rig that baked no `slide_hold_time`)
  is unchanged in shape: the clip plays straight through and ends standing. Both paths now
  end on the same branch.
- The **stall** exit - a held slide steered uphill until `_horizontal_speed()` falls under
  `SLIDE_STALL_SPEED` - ends the slide **immediately and standing**, with no run-out. The
  run-out would drive him back up to the clip's ~5 m/s, and accelerating him forward is the
  one thing running out of hill must not do.
- **`jump`**, **off a ledge**, **freeze**, **mantle** and **boarding EXIA** are all unchanged.
  They already ended standing; now they are not the exception, they are the rule.

Crouching is still on the same button, and still a toggle - it is simply no longer reachable
*through* a slide. Slide, stand up, press `crouch` if being low is what you wanted.

## What changes

### `scripts/pilot9.gd::_handle_crouch_and_slide()`

```gdscript
elif is_slide_holding:
    ...
    if Input.is_action_just_pressed("crouch"):
        is_slide_holding = false      # resume: the run-out stands him up
    elif _horizontal_speed() < SLIDE_STALL_SPEED:
        _end_slide()                  # out of hill - no run-out to play at 1.5 m/s
elif _slide_time >= slide_duration:
    _end_slide()                      # the run-out finished; he is standing
```

Three `is_crouching = true` writes are deleted and nothing replaces them. `is_crouching` is
now written in exactly two places on the slide path: `_start_slide()` clears it, and
`_handle_gravity_and_jump()` clears it. It is never set by a slide.

The `_on_auto_slide_slope()` refusal above these branches is **kept**, and the argument for it
is unchanged: on ground too steep to stand on, letting him out only lets `_should_auto_slide()`
restart the slide a frame later, which plays as the entry stuttering. The stand-up now takes
the length of the run-out rather than a frame, so the check happens once, at the press.

### `scripts/pilot9_build_scene.gd::_ensure_slide_state()`

The `slide -> crouch` transition is removed. `is_crouching` cannot be true while `is_sliding`
is, so it was already dead once the controller stopped setting it; leaving a dead transition
on a state machine that is read by three tests is how the next reader gets it wrong.

`slide -> Locomotion` (`not is_sliding`, priority 2) is the exit again. `slide -> jump` (0)
and `slide -> fall` (1) keep their priorities and their reasons.

### `scripts/pilot9_animation.gd::_drive_slide()`

**No code change.** `SLIDE_SCALE` is frozen to 0 while `is_slide_holding or not is_sliding`,
and both halves are still right for the new rule: the hold still freezes the clip, and
`not is_sliding` now parks it on the *last frame of the run-out* - a standing pose - for the
0.2 s blend into Locomotion, instead of parking the hold pose for the blend into the crouch.
Only the comment moves.

## Decisions

| | Taken | Over |
|---|---|---|
| End state | Standing | Crouched (2026-09-07). Crouch speed deleted the run. |
| The stand-up | **Play the run-out** - it is the authored stand-up, and it is fast | Cutting to standing off the hold pose. That saves ~0.5 s and throws away both the animation and the speed it carries. |
| Stall exit | Immediate, no run-out | Playing the run-out, which would accelerate a man who has just run out of hill. |
| Keep `not is_crouching` in the slide-start predicates | Yes | Deleting it with the hand-off it was written for. It is independently correct: the clip opens at 8 m/s with his feet planted, so a slide out of a 1.6 m/s crouch would lurch. |
| `slide -> crouch` transition | Removed | Left in place as dead wiring. |
| Crouch after a slide | Player's own `crouch` press, one frame after standing | A held `crouch` that keeps him low through the exit. No second meaning on that button. |

## Risks

1. **The run-out is a commitment.** `crouch` out of a hold now takes the length of the
   run-out (0.75 s - the trimmed clip is 1.25 s and the hold sits at 0.50 s) instead of
   ending on the press. `jump` still cuts it short at any point, and steering still works
   throughout, so it is not a cutscene - but it is longer than the thing it replaces. The
   dial is `slide_scale`; the escape hatch is `jump`.
2. **A second `crouch` press during the run-out is swallowed**, as every input is for the
   length of a slide (the `return` at the end of the `is_sliding` block). A player mashing
   `crouch` to end a slide early will not get a crouch out of it - which is the point, but it
   is also the one place the button does nothing.
3. **The pose at the end.** `slide -> Locomotion` blends the parked final run-out frame into
   the walk/run blend space. If the trimmed clip's last frame is not quite standing, that
   0.2 s reads as a lean. `SLIDE_KEEP_FRAMES` in the builder is the dial.

## What this does not do

- **No crouch-height collider**, still (`pilot9-slide.md`). The capsule is full height
  through both.
- **No change to the crouch itself** - the toggle, `crouch_speed`, the `crouch` state and its
  clip are all untouched. It simply stops being something a slide can put him into.
- **No change to the hold, the slope momentum, the buffer, the cooldown, the auto-slide or
  any exit other than the two that set the crouch.**
- **Nothing for Setsuna.**

## Test coverage

`tests/test_pilot9_slide_stand.gd` (replaces `tests/test_pilot9_slide_crouch.gd`):

- there is **no** `slide -> crouch` transition on the built state machine
- `slide -> Locomotion` exists, fires on `not is_sliding`, advances automatically, and is
  outranked by both `slide -> jump` and `slide -> fall`
- `_end_slide()` leaves `is_crouching` untouched, and `_start_slide()` clears it
- no branch of `_handle_crouch_and_slide()` writes `is_crouching = true` - a source
  assertion, because the branches need `is_on_floor()` and a real `Input` and so are not
  reachable in a `--script` run
- `_can_start_slide()` / `_should_buffer_slide()` still carry the `not is_crouching` guard

`tests/test_pilot9_slide_hold.gd::test_leaving_the_hold_resumes_the_run_out` already covers
the resume itself and needs no change - it drives `is_slide_holding = false` directly, which
is now exactly what the `crouch` press does.

Whether standing up out of a slide *feels* like keeping the speed is QA, as ever.
