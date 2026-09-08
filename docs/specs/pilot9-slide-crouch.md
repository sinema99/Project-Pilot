# Spec: a slide hands off into a crouch

> **Status:** built 2026-09-07, revised the same day after the first play (see "The
> 2026-09-07 pass" at the bottom). **The revision is unplayed.**
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide-hold.md`, whose "leaving the hold" rule this replaces,
> and `docs/specs/pilot9-slide.md`, whose "it ends standing, not crouched" decision this
> reverses. Neither entry route, the run-in, the steering, the cooldown or the ledge exit
> changes.

## Problem statement

Every way out of a slide left pilot9 standing. The natural mental model is the opposite: he
drops low to the floor for the slide, so when the slide finishes he should still be low -
*crouched* - and standing back up should be the thing that costs an input. The old rule made
"slide, then keep moving low under something" a two-step (slide, wait for the stand-up, press
crouch), and the stand-up in the middle is exactly the animation the player did not ask for.

## The rule

**A slide hands off into a crouch. `jump` out of a slide is the only exit that ends standing.**

- `crouch` out of the hold **ends the slide outright**, on the frame it is pressed. The clip
  does **not** resume - no run-out - and the `slide -> crouch` transition blends the frozen
  hold pose straight into `crouch_walk`. This is pose-to-pose off the held frame.
- A slide with **no hold** (`can_hold_slide` off, or an old rig that baked no
  `slide_hold_time`) has no held frame to leave from, so the clip plays straight through, the
  run-out and all, and *then* he ends crouched. This is the legacy configuration; the run-out
  is unavoidable there because nothing freezes the clip.
- **`jump`** ends the slide standing, exactly as before: `_handle_gravity_and_jump()` clears
  `is_crouching` and launches him on the same frame, and it runs *after*
  `_handle_crouch_and_slide()` in the physics step, so it always gets the last word.
- **Off a ledge** mid-slide is unchanged and does **not** end crouched: that exit is taken by
  an earlier branch (`if not is_on_floor(): _end_slide()`), before either branch that sets the
  crouch is reached, so an airborne end still lands in `fall`.

Coming out of the crouch afterwards is the crouch's own job - the `crouch` toggle, already
built. A slide now leaves him *in* the crouch state; it does not change what that state is.

## Why the run-out is cut, not played

The first build (below) played the run-out - frames 30-75, his hips travelling from the
settled floor pose back up to standing - and then settled into the crouch. It read as a
stand-up-then-drop bob, because the run-out reaches full standing height before the 0.2 s fade
into the crouch takes. The player asked for it gone: "let's not play the end of the slide,
let's just have it transition into crouch from the slide."

So the held slide now leaves on the *first* `crouch` press, from the hold pose, and the
`slide -> crouch` cross-fade carries him from there into `crouch_walk`. The trimmed run-out
still exists in the clip and still plays in the no-hold legacy config; on the shipping path it
is dead footage.

## The re-slide bug this pass also fixed

The first build let a `crouch` press re-enter the slide instead of standing him up. Coming out
of the hand-off, `sprint_toggled` is still on (sprint is a toggle and survives everything), so
a `crouch` press meant to stand up passed every test in `_can_start_slide()` - sprinting, on
the floor, stick pushed, off cooldown - and started another slide. He could never stand.

`_can_start_slide()` and `_should_buffer_slide()` now both require **`not is_crouching`**.
Crouched, a `crouch` press is a stand-up: it falls through to the `is_crouching = not
is_crouching` toggle at the bottom of `_handle_crouch_and_slide()`. A slide can only be
started from a non-crouched state, which is the only state it ever made sense from.

## The animation side

One transition, added by `scripts/pilot9_build_scene.gd::_ensure_slide_state()`:

| From | To | Expression | Priority |
|---|---|---|---|
| `slide` | `crouch` | `is_crouching` | 1 |

`is_crouching` goes true on the frame `_handle_crouch_and_slide()` ends the slide, the same
frame `is_sliding` goes false. This cannot race `slide -> fall` (also priority 1, but that
needs `not is_on_floor()`, and both crouch-setting branches are only reached on a floor).
Priority 1 puts it **ahead of** `slide -> Locomotion` (2), so the crouch wins the hand-off,
and **behind** `slide -> jump` (0), which clears `is_crouching` the same frame it fires - the
same priority argument the crouch and the slide already needed against a jump.

`scripts/pilot9_animation.gd::_drive_slide()` freezes the slide clip's `SlideScale` to 0 not
only while `is_slide_holding` but also whenever `not is_sliding` - so the clip stays parked on
the hold pose through the whole `slide -> crouch` blend-out instead of advancing a slice of
the run-out into the cross-fade. Re-entering `slide` restarts the clip from frame 0, so a
scale left at 0 never carries into the next slide.

The `crouch` state is built (line 184) before the `slide` state (line 193), so the transition
is added pointing at a node that already exists; a rebuild removes it with either state and
`_ensure_slide_state()` puts it back.

## The controller side

`pilot9.gd::_handle_crouch_and_slide()`, inside the `if is_sliding:` block:

```gdscript
elif is_slide_holding:
    if Input.is_action_just_pressed("crouch"):
        is_crouching = true
        _end_slide()
elif _slide_time >= slide_duration:      # no-hold legacy path only
    is_crouching = true
    _end_slide()
```

`is_crouching` is set at these call sites and **not** inside `_end_slide()`, because
`_end_slide()` is also how a slide ends off a ledge, on a jump cancel, on a freeze, on a
mantle start and on boarding EXIA - every one of which must leave him standing.
`_start_slide()` still clears `is_crouching` on entry: a slide is not a crouch, and the flag
is set again only at these two exits.

## Decisions

| | Taken | Over |
|---|---|---|
| End state | Crouched | Standing (the old rule). The player asked for "crouching when coming out of a slide". |
| The one standing exit | `jump` | Also standing on `crouch` out. No second button was wanted. |
| Run-out on the `crouch` exit | **Cut** - leave from the hold pose, pose-to-pose into the crouch | Playing it and settling into the crouch. That was the first build; it read as a stand-up-then-drop bob and the player rejected it. |
| Re-slide guard | `not is_crouching` in `_can_start_slide()` / `_should_buffer_slide()` | Clearing `sprint_toggled` on the hand-off - which would also silently drop him out of a run for no reason the player asked for. |
| Where `is_crouching` is set | At the two slide-exit call sites | Inside `_end_slide()` - which would also crouch him off a ledge and out of a jump cancel. |
| Non-hold slide | Ends crouched too, run-out and all | Leaving `can_hold_slide` off on the old "ends standing" behaviour. One rule. |

## Risks

1. **The pose jump.** `slide -> crouch` now blends a near-prone hold pose straight into the
   `crouch_walk` squat over 0.2 s. It may pop. The dial is the transition's `xfade_time` in
   `_ensure_slide_state()`; a re-authored hold pose that is less prone would also help.
2. **`crouch` mashed at the end of a slide.** The first press ends the slide into a crouch;
   a second, a frame later, hits the crouch's own `not is_crouching` exit and stands him up.
   Believed fine - it is the crouch toggle behaving normally - but a player who reads "crouch
   = stay down" may not predict it.
3. **A re-export that moves the hold frame** already prints a warning
   (`docs/reimport.md` step 10); nothing here adds to that surface.

## What this does not do

- **No crouch-height collider.** The capsule is full height through the slide and the crouch
  both; sliding or crouching under low geometry is still not a thing (`pilot9-slide.md`).
- **No change to the hold** itself - length, speed, steering, the seam - all as
  `pilot9-slide-hold.md` built them. Only the way *out* of it changes.
- **No change to the entry, the buffer, the cooldown or the ledge exit** beyond the
  `not is_crouching` guard.
- **Nothing for Setsuna.**

## The 2026-09-07 pass

First build: `crouch` out of the hold cleared `is_slide_holding` and let the clip resume, so
the run-out played and he settled into the crouch out of it. Two problems on the first play:

1. The run-out stood him fully up before the crouch fade took - a visible bob.
2. `sprint_toggled` surviving the hand-off meant a `crouch` press to stand up re-entered the
   slide instead. He was stuck crouched.

The revision cuts the run-out (leave from the hold pose) and adds the `not is_crouching`
guard to the two slide-start predicates. The `slide -> crouch` transition, the priorities and
the "set `is_crouching` at the call site" rule are all unchanged from the first build.

## Test coverage

`tests/test_pilot9_slide_crouch.gd`:

- the `slide -> crouch` transition exists, fires on `is_crouching`, advances automatically,
  outranks `slide -> Locomotion` and is outranked by `slide -> jump`
- `_end_slide()` on its own leaves `is_crouching` untouched (the ledge / jump / freeze /
  boarding exits are not dragged into a crouch)
- `_start_slide()` still clears `is_crouching` on entry
- `_can_start_slide()` and `_should_buffer_slide()` carry the `not is_crouching` guard - a
  source assertion, matching `test_pilot9_sprint_fov.gd`, because the behaviour it prevents
  needs `is_on_floor()` and Input and so is not reachable headlessly

The grounded end-to-end feel - press `crouch` in a hold, land in a crouch, press `crouch`
again, stand up - is QA, in line with the rest of the pilot9 build.
