# Spec: pilot9's land-and-slide buffer

> **Status:** built 2026-09-06; **loosened 2026-09-06** after the first read of the feel -
> see "The 2026-09-06 loosening" below. The revised feel is unjudged.
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

**What the headless tests cannot reach:** the happy-path landing consumption itself (needs
`is_on_floor()` true and a live `Input` state), and the toggle flip itself (needs a live
`Input` edge across a physics frame). Both are the user's on play: with sprint toggled on,
tap `crouch` any time during a sprint-jump and he should come down already sliding, no
fumbled crouch, no lost run-up - and letting go of the sprint button mid-jump must not
change that.
