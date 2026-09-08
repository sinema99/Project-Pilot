# Spec: pilot9's slide (and the climb clip, imported and parked)

> **Status:** built 2026-09-06; **trimmed and made steerable 2026-09-06** after the first
> play - see "The 2026-09-06 feel pass" below. The revised feel is unjudged.
> **Superseded in part 2026-09-07** by `docs/specs/pilot9-slide-hold.md`, which parks the
> clip on its frame-30 pose instead of playing it straight through. The entry, the bake, the
> steering and the run-out are all as described here; what changed is that there is now an
> unbounded hold between the run-in and the run-out, and that the `slide` state has a
> TimeScale after all. Both places that matter below say so.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb` (export of 2026-09-06 17:58).
> **Follows:** `docs/specs/pilot9-real-controller.md`, `docs/specs/pilot9-turn-to-face.md`.

## What arrived

Two new Blender actions rode in on `PILOT9.glb`, alongside the three already there:

| Imported name | Length | Source (from `~/Downloads`) | This pass |
|---|---|---|---|
| `P_slide` | 1.550 s | `Running Slide.fbx` | **wired**, cut to 1.250 s - the feature below |
| `P_climbing` | 1.150 s | `Braced Hang To Crouch.fbx` | **imported, unwired** - by the user's instruction |

Neither was exported **In Place**, which `docs/reimport.md` step 8 asks for. For the climb that
is correct and wanted. For the slide it turned out to be the better input too - see below - so
nothing needs re-exporting.

## The thing that shapes the whole design: the slide is a root-motion clip

`P_slide` is not a pose cycle. Its `Hips` position track walks **+7.796 m forward over 1.55 s**,
and the shape of that walk is the animation. As authored - the cut at frame 75 lands inside the
last row, at 1.25 s:

| Window | Hips Y | Forward speed | What he is doing |
|---|---|---|---|
| 0.00 - 0.13 s | 0.88 -> 0.81 | 8.0 - 8.4 m/s | running in, feet planted |
| 0.13 - 0.37 s | 0.81 -> 0.23 | 8.4 -> 6.1 m/s | dropping into the slide |
| 0.37 - 0.87 s | 0.23 -> 0.42 | 6.1 -> 3.4 m/s | on the ground, decelerating |
| 0.87 - 1.15 s | 0.42 -> 0.64 | 3.4 -> 2.2 m/s | pushing back up, slowest point |
| 1.15 - 1.55 s | 0.64 -> 0.88 | 2.2 -> 5.0 m/s | back on his feet, running out |

That is a complete verb with its own entry and exit, not a loop to be held. It also means the
clip already knows the answer to the only question that makes a slide look good or bad:
**how fast the body should be moving at each instant.**

Two windows have planted feet - the run-in and the run-out - and those are the only two where a
speed mismatch shows as skate. The 1.0 s in between is a body sliding on the floor, where any
speed reads fine. So the cheap version (enter at sprint speed, apply a friction constant) would
look acceptable, and the exact version costs about thirty lines. Taking the exact version.

## The rule

**Sprint + `crouch` on the ground starts a slide.** It runs to completion, steerable but not
cancellable, travelling exactly the distance curve the clip was authored with, and hands back to
normal locomotion standing up and moving.

> **2026-09-07:** it no longer runs to completion on its own. It stops on the clip's frame 30
> and holds there until `crouch` is pressed again (which plays out the run-out) or `jump` is
> pressed (which cancels it outright). The distance curve still drives every part of the clip
> that plays; the hold simply inserts flat-speed travel between the two halves of it. See
> `docs/specs/pilot9-slide-hold.md`.

No new input action: `crouch` already exists and is already the crouch toggle. Pressed at a
sprint it means slide; pressed at any other time it still means crouch. The press is consumed
by whichever one claims it, never both.

> **2026-09-06:** `sprint` is now a **toggle**, not a hold (`sprint_toggled`, flipped in
> `_update_sprint_toggle()`), so "at a sprint" here means the toggle is on. Motivated by and
> detailed in `docs/specs/pilot9-jump-slide.md`.

## Where the motion comes from

The clip cannot simply be played with its root motion left in. Two reasons, and the second is
fatal on its own:

1. The `CharacterBody3D` would not move - only the mesh would - so the collision capsule would
   stay 7.8 m behind him for the length of the slide.
2. **A root-motion track cannot be cross-faded.** Every transition in this state machine is an
   `xfade`, and blending a `Hips` sitting at +7.68 m against a run clip's ~0 m drags the mesh
   backwards through the whole exit fade. Godot's `AnimationTree.root_motion_track` would solve
   both, but it strips the named track from *every* clip in the tree - the bob and sway would go
   out of all 29 of RC's.

So the builder splits the clip in two, at build time, from the same source data:

- **The pose** goes in the library with its `Hips` Z **locked to its first key** - an ordinary
  in-place clip that cross-fades like every other. X and Y are untouched, so the hip drop that
  sells the slide and the lateral sway both survive.
- **The travel** is baked into a `Curve` on the controller (`slide_motion`), normalised on both
  axes: time fraction in, distance fraction out. `slide_duration` and `slide_distance` come
  across with it - **1.250 s** and **6.462 m** after the trim below; 1.550 s and 7.796 m as
  authored.

`scripts/pilot9.gd::_apply_slide_velocity()` then differentiates that curve each physics frame
and drives `velocity` with it. Feet and floor agree at the run-in and the run-out because the
number driving the body is the number the animator authored, not a guess that resembles it.

`slide_scale` is the dial: 1.0 is the clip as trimmed, and it multiplies distance without
touching duration, so raising it makes the slide longer *and* faster over the same 1.25 s.

### This is all regenerated

`GLB_CLIPS`, the Z-lock, the curve and the whole `slide` state are owned by
`scripts/pilot9_build_scene.gd` and rewritten on every sync, in **both** builder modes. Editing
any of them in the editor is wasted work. `slide_scale` is the exception - the builder never
writes it, so a value tuned in the inspector survives a swap (but not a `--fresh`).

## Decisions

- **~~Locked heading.~~ Steered heading.** *(Reversed 2026-09-06 - see the feel pass below.)*
  The direction is captured on entry from the **mesh's facing**, then turned by the stick at the
  ordinary `rotation_speed`. One heading and one lerp: `_steer_slide()` turns it,
  `_apply_slide_velocity()` drives the body along it, `_handle_character_rotation()` writes the
  mesh onto it. Stick centred, it holds.
- **Jump cancels it.** Pressed mid-slide, jump wins: the slide ends and the leap plays. This is
  three lines and it is the difference between a move and a 1.25 s cutscene. The same priority
  rule the crouch already needed applies - `slide -> jump` must outrank `slide -> Locomotion`,
  because cancelling clears `is_sliding` on the same frame the jump launches, so both exits go
  live at once and the leap would otherwise play as a stand-up.
- **Leaving the floor ends it.** Slide off a ledge and the slide stops; `fall` takes over and
  gravity is the only thing left driving him.
- **~~It ends standing, not crouched.~~ It hands off into a crouch.** *(Reversed 2026-09-07 -
  see `docs/specs/pilot9-slide-crouch.md`.)* `crouch` out of the hold ends the slide on the
  press, from the held floor pose, and `slide -> crouch` blends that straight into the crouch
  - the run-out is not played on the shipping path. `jump` out is now the only exit that ends
  standing. Entering a slide still clears `is_crouching`; it is set again only at the exit.
- **A cooldown, 0.4 s.** Without one, sprint on and `crouch` tapped re-enters on the frame it
  exits and he never stands up.
- **No slide from a standstill or a walk.** Sprint on, on the floor, with movement input. The
  clip opens at 8 m/s; starting it from rest would snap him forward.
- **The climb stays unwired.** The user's call, and correct - the map has no ledge to climb. It
  is imported and asserted so the day it is wanted the clip is known-good rather than a fresh
  import problem. See below.

## The climb clip, and what wiring it will cost

`P_climbing` is in the library as `climb_up`, `LOOP_NONE`, unwired - the same parking spot
`sit_down` has occupied since the crouch pass. Its root motion is left **intact**, on purpose:
that motion is the feature, not a nuisance to be stripped.

The measurement worth not re-deriving: its `Hips` rises **+1.782 m** and moves **+0.484 m
forward** over 1.15 s. So it is a mantle onto a ledge roughly 1.8 m above the feet, landing
about half a metre in from the lip - and that fixes the level geometry it will demand, whenever
the map grows something to climb.

Wiring it is a bigger job than the slide, and not because of the animation:

- It needs **detection** - a ledge probe (a forward ray at chest height that misses, over a
  downward ray that hits a walkable top) run while airborne and rising.
- It needs the body **driven along a path**, not by velocity: a mantle is a scripted 1.15 s
  translation with collision effectively suspended, because the capsule has to pass through the
  space the ledge occupies. Nothing in this controller does that yet.
- The same no-cross-fade rule applies, so its Z **and Y** would both want locking and baking the
  way the slide's Z was - two curves rather than one, or one `Curve3D`.

None of that is speculative work worth doing before there is a ledge to test against.

## The 2026-09-06 feel pass

Two changes after the first play, both against the same complaint - the slide takes the game
away from you for its length.

### The clip is cut to its first 75 of 93 frames

The last 18 frames are the tail of the run-out: he is upright and simply running, and the player
is watching an animation finish rather than playing. Cutting them ends the slide 1.250 s in -
about 0.3 s earlier - and the exit is the part that reads as responsiveness.

`_trim_slide()` in the builder does it, before `_ensure_slide_motion()` reads anything, so the
duration, the distance and the curve are all measured against the shortened clip and cannot
disagree with what plays. Trimmed: **6.462 m over 1.250 s** - an average of 5.17 m/s, up from
5.03.

Two details that cost more than they look:

- **Moving `Animation.length` is not a cut.** Godot's interpolation ignores keys past the length
  rather than clamping to it. The GLB is sampled at 30 Hz, so the last key inside a 1.25 s cut
  sits at 1.20 s and every sample from there on returns it: a frozen 0.05 s tail on a cut made
  specifically to remove a tail, and the baked curve flattens with it and stops the body dead as
  his feet come down. Measured cost: 6.262 m instead of 6.462 m. So the boundary pose is sampled
  first, the keys past the cut dropped, and that pose re-keyed exactly on the new end.
  `test_the_trimmed_slide_animates_all_the_way_to_its_new_end` holds it from both sides - every
  track's last key on the length, and the curve's last segment not flat.
- **Frames are quoted at 60 fps; the exporter sampled at 30.** `Animation.step` reads 0.0333 and
  the action is 93 frames long over 1.55 s; both are true. `SLIDE_SOURCE_FPS` is the only place
  the two meet, and it exists so `SLIDE_KEEP_FRAMES` can be typed as Blender shows it.

### The slide steers

The locked heading was wrong, and for a reason the original argument had backwards: committing
to a line is the feel of the verb only when the player picked the line. At 8 m/s entry the
commit is made before he can see where it goes, so a miss reads as the controls having been
taken away rather than as a bad call.

It now turns exactly as a run turns - same stick, same `rotation_speed`, same lerp - and that
equality is the design rather than an approximation of it:

- The lerp is on the **heading**, not on the mesh. `_handle_character_rotation()` then *writes*
  the mesh onto the heading instead of chasing it with a second lerp. Two lerps in series would
  halve the turn rate, so it would not be "normal", and would leave the mesh pointing somewhere
  the body is not - which is skate for as long as his feet are planted.
- The entry heading comes off the **mesh's facing**, not the stick. Entering mid-turn the two
  differ, and since the mesh is now welded to the heading, taking the stick's would snap his
  body round on the entry frame.
- A centred stick leaves the heading alone. Letting go does not straighten him out, and the
  run-out - planted feet - does not swing.
- First person is the one place `_steer_slide()` runs and the weld does not: nothing drives
  `character.rotation` there, which is why the steering call sits outside that mode gate in
  `_physics_process` and the entry falls back to the stick.

What this does not become: the body is still driven entirely by the baked curve, so steering
changes where he goes and never how fast. No air control, no speed gained by turning.

## Risks

1. **The clip's own timeline and the controller's timer are separate clocks.** The state machine
   advances the clip; `_slide_time` advances in `_physics_process`. Both are real time from the
   same frame, so they cannot drift by more than a frame - but a `TimeScale` node or a paused
   tree would desync them silently.

   **2026-09-07:** there *is* a `TimeScale` in the `slide` state now, and this risk is the
   reason it is only ever written 0.0 or 1.0. Both clocks stop and start on the same flag, so
   a hold of any length costs no drift; a *rate* other than 1 is still forbidden. See
   `docs/specs/pilot9-slide-hold.md`.
2. **The entry cross-fade eats the first 0.15 s of the run-in**, which is the part with the
   fastest planted-foot motion. It comes from a sprint at a matching 8 m/s, so it should read;
   if it does not, the fade is the dial, not the curve.
3. **`slide_distance` is baked from the export.** Re-authoring the action changes how far he
   travels, silently and correctly. If the *feel* was tuned via `slide_scale` against the old
   distance, that tuning is now against a different number. `SLIDE_KEEP_FRAMES` compounds it:
   it is a frame count, so a re-authored action is still cut at frame 75, which may no longer
   be where the run-out begins.
4. **8 m/s is faster than anything else he does**, and the slide holds it into geometry a run
   would have been steered around. Nothing here changes collision; `move_and_slide` stops him
   at a wall and the clip keeps playing against it. Acceptable, and visible only if the level
   has tight cover. Steering makes this reachable on purpose rather than only by accident.

## What this does not do

- ~~No slide-to-crouch.~~ *Added 2026-09-07 - `docs/specs/pilot9-slide-crouch.md`.* A slide
  now hands off into the `crouch` state - `crouch` out of the hold ends it pose-to-pose off
  the held frame. There is still no crouch-idle, so he lands on the crouch WALK cycle through
  its TimeScale exactly as the `crouch` toggle already does.
- No slide under low geometry. There is no crouch-height collider - the capsule is full height
  throughout - so the one thing a slide is traditionally *for* is not available yet.
- No slide cancel except by jumping. Steering is not a cancel. (2026-09-07: `crouch` now ends
  the hold too, but by playing the run-out rather than by cancelling - jump is still the only
  way out that skips it.)
- No dive, no slide-jump momentum carry.

## Test coverage

`tests/test_pilot9_slide.gd`, pointed at the seams that fail silently:

- Both clips lifted out of the GLB, with the right loop modes and plausible lengths.
- Every `slide` track resolves to a real bone on the retargeted rig.
- The `slide` clip's `Hips` Z **is** locked (the pose is in place) and `climb_up`'s **is not**
  (its root motion is still there to be used).
- The clip is cut - measured against the raw GLB rather than a literal - and every track ends
  **on** the new length, which is the frozen-tail trap above.
- The steering, four ways: it reaches the stick, it holds when the stick is centred, it turns at
  exactly the rate `_handle_character_rotation` turns a run at, and the mesh is never off the
  heading by more than a rounding error while it does. Plus the entry taking the facing rather
  than the stick.
- The baked curve exists, is monotonic, spans 0..1 on both axes, and its distance and duration
  match the clip they came from.
- The `slide` state exists and plays `slide`. (2026-09-07: it is now the clip through a
  `SlideScale` TimeScale, and the assertion moved to the shape of that blend tree - risk 1.)
- The transitions and their priorities, including `slide -> jump` outranking `slide -> Locomotion`.
- The controller exposes `is_sliding` - an `advance_expression` naming a property that does not
  exist never fires and never complains, which is how the crouch broke once already.
- `climb_up` is in the library and **not** in the state machine.
