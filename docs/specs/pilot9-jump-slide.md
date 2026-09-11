# Spec: pilot9's land-and-slide buffer

> **Status:** built 2026-09-06; **loosened 2026-09-06** after the first read of the feel -
> see "The 2026-09-06 loosening" below. The revised feel is unjudged.
> **Fixed 2026-09-11:** the clip froze on the wrong frame coming out of a jump - see
> "The 2026-09-11 freeze" below. Unjudged on play.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide.md`, which built the slide this only changes the
> *entry* of.

## Problem statement

The slide starts on `crouch` pressed while **sprinting and on the floor**
(`pilot9.gd::_can_start_slide()`). Coming down from a jump that means the player has a
single physics frame - the one where `is_on_floor()` first reads true - to press `crouch`
and get a slide. A press one frame early lands in the air, where `_can_start_slide()` fails
and the press falls through to the crouch toggle; a press one frame late is an ordinary
grounded slide that has already lost its run-up.

Jump, then slide, is a move the player will want to chain - clear a gap and immediately go
under something on the far side - and right now it demands frame-perfect timing to look
like anything but a fumbled crouch.

## The rule

**A `crouch` press made while airborne is remembered until he lands, and spent the instant
he does.** If the slide's normal conditions still hold at touchdown (sprint on, stick
pushed, off cooldown) he goes straight into the slide from the landing frame. If they do
not, the remembered press evaporates - it does not become a crouch.

Nothing about the grounded slide changes. This is a second way *in*, not a new move.

## What arms the buffer

The press is remembered (rather than toggling the crouch, which is what an airborne
`crouch` press does today) only when all of these hold at the moment it is pressed:

- `can_slide`, and the slide is actually baked (`slide_motion` present, `slide_duration > 0`)
- `can_buffer_slide` - the feature's off switch, a plain bool
- **not** on the floor
- off cooldown (`_slide_cooldown_left <= 0`)
- `sprint` toggled on, `walk` not held
- the stick is pushed - `Input.get_vector(...) != Vector2.ZERO`

Any other airborne `crouch` press still toggles `is_crouching`, exactly as before.

### The 2026-09-06 loosening

The first cut of this buffer was a **time window** - `slide_buffer_time`, defaulting to
0.15 s - and that window doubled as a proximity check: a press only survived to be spent if
he actually reached the floor within it, so a press at the apex of a jump simply lapsed.

0.15 s turned out to be barely looser than the frame-perfect press it was meant to fix, and
raising it re-opened the apex problem it was designed around. So the window is gone. **Any
`crouch` press made in the air is now remembered until he lands, no matter how long the
fall or how high it was made.** Two things it also drops:

- **No timer.** `_slide_buffered` is a bool, armed on the press and cleared on the first
  grounded frame (whether or not it starts a slide). It does not count down.
- **No rise/fall gate.** The old rule refused to arm while `velocity.y > 0`, on the theory
  that a press just after a jump was the jump input's tail. With sprint now a toggle (see
  below) that theory is weaker - the press meets the sprint condition only if the player
  deliberately has sprint on - and the stricter feel is exactly what this pass is undoing.
  Press `crouch` at any point in the air and the slide is waiting for the floor.

The apex press now landing as a slide is **intended**, not a hazard: if the player does not
want to slide on landing, they do not press `crouch` in the air. The move reads as "ask for
the slide any time before you land."

### Why still no proximity probe

This does **not** raycast for the floor or run a `test_move()` probe, and now there is not
even a time window standing in for one. A buffered `crouch` is a committed intent: he will
slide when he lands if he still can. If play shows that wants a height gate after all,
`test_move(..., Vector3.DOWN * h)` is the cheap add - it uses the body's own capsule and
mask and needs no new node. Not doing it now.

## What spends it

Every physics frame, `_handle_crouch_and_slide()`:

1. **before** it looks at a fresh `crouch` press: if `_slide_buffered` and `is_on_floor()`,
   it clears the flag and runs the ordinary `_can_start_slide()` check against the stick as
   it is *now*. Pass -> `_start_slide()` from this frame. Fail -> the press is gone, and the
   frame does **not** fall through to the crouch toggle.

Consuming the buffer before the just-pressed check is the same discipline the grounded path
already uses: one press, read in one place, never spent twice.

`frozen` clears the flag, for the reason freezing already ends a running slide - a stale
queued press should not fire on unfreeze.

## The entry heading

`_start_slide()` is unchanged: in third person the slide leaves along the **mesh's facing**,
not the stick (entering mid-turn the two differ, and the mesh is about to be welded to the
heading - see the slide spec's feel pass). A buffered slide inherits that. Whatever way he
was pointing as he came down is the way the slide sets off, and the stick steers it from
there at the ordinary `rotation_speed`.

## Sprint is a toggle

Bundled with this pass, and load-bearing for it. `sprint` (Shift / right trigger) now
**toggles** rather than being held - `_update_sprint_toggle()` flips `sprint_toggled` on the
press, `walk` clears it - and everything that read `Input.is_action_pressed("sprint")` now
reads `sprint_toggled`: `is_sprinting` in `_apply_movement()`, `_can_start_slide()`, and
`_should_buffer_slide()`.

Two reasons it belongs here:

- **The accidental-release problem.** With a held sprint, coming down from a sprint-jump the
  player has to keep the button down through the whole jump or the landing is an ordinary
  run. Letting go by reflex at the apex - very common - silently costs the slide. A toggle
  means the sprint intent outlives the button and survives the jump.
- **It makes the aggressive buffer safe.** The old spec worried that a buffered press which
  *fails* on landing should evaporate rather than become a crouch, because "letting go of
  sprint mid-air and then landing leaves him crouched" was a bad surprise. With a toggle
  there is no mid-air let-go: if `sprint_toggled` is on, the `crouch` press unambiguously
  means slide. If the player wants to crouch on landing instead, they toggle sprint off
  first, or press `crouch` after they land.

Frozen, the toggle press is ignored (`handle_frozen_movement()` forces `is_sprinting` false
anyway) and the toggle state is left untouched, so a pause does not silently disarm a run.

## The animation side

The slide state was reachable only from `Locomotion` (`Locomotion -> slide` on `is_sliding`,
priority 0). Coming down from a jump the tree is in `fall`, and on the landing frame it is
`fall` or `jump_land` depending on timing - neither of which had an `is_sliding` exit, so a
buffered slide would have routed `fall -> jump_land -> Locomotion -> slide` over three
stacked cross-fades and a frame or two of `jump_land` playing first.

`scripts/pilot9_build_scene.gd::_ensure_slide_state()` also writes:

| From | To | Expression | Priority | xfade |
|---|---|---|---|---|
| `fall` | `slide` | `is_sliding` | **0** | 0.1 |
| `jump_land` | `slide` | `is_sliding` | **0** | 0.1 |

Priority 0 puts each ahead of the plain-landing transition out of the same state
(`fall -> jump_land` and `jump_land -> Locomotion` are both the default priority 1), so on
the frame `is_sliding` flips true the tree goes straight to `slide` from wherever it is.
`jump -> slide` is deliberately **not** added: `is_sliding` cannot be true while
`is_on_floor()` is false, and the buffer is only spent once he lands, so the tree is never
in `jump` when it flips.

These are regenerated on every sync, like the rest of the `slide` state. Editing them in
the editor is wasted work.

## Decisions

- **The remembered press evaporates on a failed landing; it never becomes a crouch.** With
  sprint as a toggle a failed landing is a rare case (stick centred on touchdown, or still
  on cooldown from a previous slide), and dropping the press is still less surprising than
  landing crouched.
- **No timer, no rise/fall gate.** Argued above - the loosening is the whole point of this
  pass.
- **`can_buffer_slide` is a bool, not a dial.** There is nothing left to tune once the time
  window is gone; it is on, or it is off and the air press is a plain crouch toggle.
- **Sprint is a toggle on both keyboard and controller.** Argued above.
- **Grounded entry is untouched.** `_can_start_slide()`, `_start_slide()`, the curve, the
  cooldown, the steering - all exactly as `docs/specs/pilot9-slide.md` left them, except
  that its sprint condition now reads the toggle.

## Risks

1. **The landing frame's stick is what counts, not the press frame's.** Arm the buffer
   pushing forward, swing the stick to centred before touchdown, and the slide does not
   start (`_can_start_slide()` needs a heading). Correct, but it means the buffer is not a
   pure "it will happen" - the player can still talk themselves out of it in the air.
2. **An apex `crouch` press is now a slide on landing.** Intended (argued above), but a
   player used to `crouch` meaning "duck" may be surprised the first time a long fall ends
   in a slide. The tell is that it only happens with sprint toggled on.
3. **`fall -> slide` at priority 0 also fires for a *grounded* slide that clips a ledge.**
   If `is_sliding` is somehow still true as he leaves the floor and comes back within a
   frame, `fall -> slide` catches it instead of `fall -> jump_land`. Same outcome the old
   `fall -> ... -> slide` chain reached, one fade instead of three - an improvement, noted
   only so it is not a surprise.
4. **A stale sprint toggle.** Toggle sprint on, wander off without moving, come back much
   later and the first step is a sprint. `is_sprinting` still gates on actual movement so
   nothing happens while stationary, but the resumed gait may not be the one expected.

## What this does not do

- No proximity/height gate (argued above).
- No coyote time on the *other* side - a press a few frames *after* landing is just a
  slightly late grounded slide, and that already works.
- No buffered jump. Same idea, different move; not asked for.
- No change to what a slide *is* once it starts.
- No auto-clear of the sprint toggle on coming to a stop (risk 4). If play wants it, it is
  one line in `_update_sprint_toggle()`.

## Test coverage

`tests/test_pilot9_jump_slide.gd`, headless, no play:

- `fall -> slide` and `jump_land -> slide` exist, advance on `is_sliding`, and are
  `ADVANCE_MODE_AUTO` (nothing calls `travel()` for them).
- Each of those outranks the plain-landing transition out of its own state - the priority
  that makes a buffered slide skip `jump_land` rather than play it first.
- The controller exposes `can_buffer_slide` (default on) and `_slide_buffered` (starts
  false).
- The buffer does **not** lapse in the air - 30 airborne `_handle_crouch_and_slide()`
  frames leave a queued press still armed.
- `frozen` clears a queued buffer.
- `can_buffer_slide` is not in the builder's `SLIDE_BAKED` list.
- `sprint_toggled` exists and starts false, `_update_sprint_toggle()` exists, and
  `_apply_movement()` drives `is_sprinting` from `sprint_toggled` rather than from `Input`.
- `fall -> jump_land` and `jump -> jump_land` both need `is_on_floor() and not
  slide_pending()`, and `slide_pending()` exists on the controller and follows
  `_slide_buffered`.
- The `slide` state's blend tree is `Clip -> SlideSeek -> SlideScale -> output`, with
  `SlideSeek` an `AnimationNodeTimeSeek`.
- `pilot9_animation.gd`'s `SLIDE_SEEK` names the path the builder builds, and the
  AnimationTree exposes it.
- `slide_clip_time()` exists and reports `_slide_time`.
- `_sync_slide_clip()` seeks to `slide_clip_time()`, waits for `slide` to be the state
  playing, re-arms when it is not, and is actually called from `_drive_slide()`.

**What the headless tests cannot reach:** the happy-path landing consumption itself (needs
`is_on_floor()` true and a live `Input` state), and the toggle flip itself (needs a live
`Input` edge across a physics frame). Both are the user's on play: with sprint toggled on,
tap `crouch` any time during a sprint-jump and he should come down already sliding, no
fumbled crouch, no lost run-up - and letting go of the sprint button mid-jump must not
change that.

## The 2026-09-11 freeze

Raised on play, the day `slide_time_scale` went to 2.0: sliding out of a jump, pilot9
*sometimes* froze on a pose out of the middle of his slide entry - "frame 10 or 15" - and
held it for the rest of the slide, instead of the hold pose baked at `SLIDE_HOLD_FRAME`
(30). A grounded slide was fine. The faster clip did not cause it; it made an old lag
visible, because every frame the clip starts late is now two frames of clip.

### What was actually happening

The slide runs on two clocks - the controller's `_slide_time` and the state machine's own
playback of the clip - kept in step only by running at the same rate
(`docs/specs/pilot9-slide-rate.md`). Running at one rate is half of staying in step. The
other half is starting together, and **the state machine's clock starts whenever the machine
gets round to entering the state.**

Godot's state machine will not take any transition while a cross-fade is in progress. That
is what broke the buffered slide, in an order the player cannot control:

1. `move_and_slide()` puts him on the floor at the end of a physics frame.
2. The AnimationTree ticks on an idle frame - which very often falls *between* that physics
   frame and the next one - sees `is_on_floor()`, and starts a 0.2 s fade into `jump_land`.
   `is_sliding` is still false: the buffered press is spent at the top of the *next* physics
   frame.
3. That next physics frame starts the slide. `_slide_time` begins running at 2x.
4. `jump_land -> slide` is now eligible and cannot fire, because the fade from step 2 is
   still running. It waits it out - up to 0.2 s.
5. The clip finally starts, ~0.2 s (24 frames of clip) behind the controller. A quarter of a
   second after step 3, `_slide_time` reaches `slide_hold_time`, `_drive_slide()` writes a
   TimeScale of 0, and the clip freezes wherever it had got to.

"Sometimes" is step 2: with no idle tick in that window the machine goes straight
`fall -> slide` (priority 0) and everything is in step. Measured against the real engine,
not reasoned about - a throwaway probe of the same three states and fades reproduced both
orderings exactly.

### The fix, in two halves

**The landing yields.** `fall -> jump_land` and `jump -> jump_land` now advance on
`is_on_floor() and not slide_pending()`, where `slide_pending()` is the controller's
`_slide_buffered`. A landing that is about to become a slide no longer opens the fade that
would block it; `fall` holds for the one frame it takes the controller to start the slide
and the machine takes `fall -> slide` instead. Only that frame is affected - `slide_pending()`
is false on every ordinary landing, and false again the instant the press is spent or
dropped. The builder owns both transitions now (`_ensure_slide_state()`), so this is a
property of the generated scene rather than an editor edit.

**The clip is seeked onto the clock.** An `AnimationNodeTimeSeek` sits in the `slide` blend
tree between the clip and its TimeScale (`Clip -> SlideSeek -> SlideScale -> output`; a seek
is a clip *position*, so it reaches the clip whatever the scale is doing, including the 0 of
a hold). `pilot9_animation.gd::_sync_slide_clip()` writes `slide_clip_time()` into it on the
frame `slide` becomes the state playing. Whatever the machine got wrong about *when* to
start, the clip lands on the frame the body is actually travelling on.

One seek per entry, not one per frame: once seeked, the two clocks agree, and running at one
rate keeps them agreeing. A seek every frame would step the clip at the rate `_process` runs
at instead of letting it play - the stutter the TimeScale arrangement exists to avoid. The
flag re-arms whenever `slide` is not the state playing, so a slide the machine enters twice
is seeked twice.

Seeking to `_slide_time` is right even when the state opens *after* the hold has begun: the
controller freezes that clock at `slide_hold_time`, so a very late entry lands straight on
the hold pose.

Half one is the fix; half two is the one that does not depend on getting the timing right.
Both are cheap and they fail independently, which is the point - the second covers the frame
of lag the first still leaves, and any other way the state can arrive late.

### On play

Sprint, jump, tap `crouch` in the air, land. He should go into the slide with its entry
playing from the top, and should park on the same hold pose a grounded slide parks on -
every time, not sometimes. If a frozen pose ever looks like the middle of the entry again,
the clip is starting late by some route the seek is not seeing; the clock to print is
`slide_clip_time()` against `AnimationNodeStateMachinePlayback.get_current_play_position()`.
