# Spec: pilot9's dash

> **Status:** specified 2026-09-17, built and played the same day. **The ink streak was
> replaced on 2026-09-19** - the single 0.35 m ribbon became a bundle of 5-7 thin manga speed
> lines sized in pen-weight pixels. See *The ink streak*, below; that section is current and
> the rest of this header is about the movement. Retuned after the play
> session - see [worklog/2026-09-17.md](../worklog/2026-09-17.md). The numbers and the
> shadow cue described below are the *original* proposal; where the build now differs, a
> note says so inline. **Direction retuned again 2026-09-18**, before a second play session:
> the locked-heading design was reversed in favour of live left/right steering - see
> *Direction*, below.
> **Speed and duration retuned again 2026-09-18**, after the direction retune above: the user
> liked the timing and feel but wanted the whole dash twice as fast - `dash_time` halved from
> 0.5 s to 0.25 s and `dash_speed` doubled from 20.0 to 40.0 m/s in the same move, so distance
> (`dash_speed * dash_time`) is unchanged at 10.0 m. Everywhere below that still says 0.5 s /
> 20.0 m/s is the pre-retune number; the numbers table and *The 9.0 m collision* section carry
> the current values. **Exit eased the same day**, after the same play session, **then un-eased
> later the same day** - see *The exit*, below. `_apply_dash_exit_ease()` briefly bled
> `dash_speed` off over `dash_exit_ease_time` (0.5 s) instead of handing straight back to
> `_apply_movement()`, to stop him carrying `dash_speed` forever whenever the stick stayed
> pointed the way he was already dashing. The user then asked for the speed to be gone the
> instant he reappears, not visibly draining after - the ease is reverted,
> `dash_exit_ease_time` is gone, and the forever-carry case it was added for is back until
> something else addresses it. **The forever-carry case is then addressed, later the same
> day, without reintroducing an ease:** `_end_dash()` clamps whatever he is actually carrying
> DOWN to `sprint_speed` if it is over that, along his real travel heading - the same
> instant-clamp pattern the slide entry already uses for `_slide_reference_speed`, not a
> blend over time, and downward only so a dash cut short against a wall is not shoved back up
> to speed. He reappears already at sprint speed, never carrying dash speed for even one
> frame; ordinary momentum decay takes it from there. See *The exit*, below.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Reference:** `scripts/player.gd` - Setsuna's dash, the only dash in this project that was
> ever actually played and tuned. Her numbers are inherited here, her structure mostly is not.
> **Touches:** `docs/specs/pilot9-slide-hold.md` (a third exit from the hold),
> `docs/specs/pilot9-jump-grid.md` (the 9.0 m collision, below),
> `docs/specs/pilot9-movement-reset.md` (why nothing global is retuned).

## Problem statement

pilot9 has no dash. He never has - `scripts/pilot9.gd` has never contained one, and the
"implement the dash again" in the request is remembering Setsuna's, in `player.gd`, which is a
different character on a different controller.

What exists instead is a set of promises. `docs/game-overview.md` lists **air dash** as the
tech found in map 2 and pre-computes its reach at 5.4 m. `scripts/ui/tabs/tab_abilities.gd`
already renders an `AIR DASH - Found in map 2` row, hardcoded to `LOCKED`. Neither is backed
by a line of code.

And there is no dash **clip**. pilot9's GLB carries four authored actions - `P_crouchwalk`,
`P_sitting`, `P_slide`, `P_climbing` - plus the Real Controller locomotion set. Nothing else.
Every other verb in his kit was built around a clip that already existed; this one has none,
and waiting for one blocks the feature on a Blender session.

**The idea this spec is built on (the user's, 2026-09-17): don't animate the dash. Hide him.**

## The rule

**pilot9 vanishes, travels 9 m dead flat in a quarter second, and reappears.** A black ink
streak is drawn where he went, and his shadow keeps running along the floor the whole time.

The absence of a clip stops being a gap to fill and becomes the feature. There is no pose to
blend into, no pose to blend out of, no TimeScale to fit a clip into a window, and no entry in
the state machine - the three things that made the slide and the climb expensive. The
`AnimationTree` is not consulted at all.

## The numbers

All three are `@export_range` on `pilot9.gd`, not `const`. Setsuna's are consts; pilot9's
entire kit is exported and tuned in the inspector while playing, and the dash is not going to
be the exception in a feature whose numbers are explicitly guesses.

| Knob | Start | Where it comes from |
|---|---|---|
| `dash_speed` | ~~18.0~~ ~~20.0 m/s~~ **40.0 m/s** | Setsuna's `DASH_SPEED`, bumped snappier after the 2026-09-17 play session, then doubled 2026-09-18 alongside the `dash_time` halving below - same distance, twice the speed. |
| `dash_time` | ~~0.5 s~~ **0.25 s** | The user's call, 2026-09-17, halved 2026-09-18 for a snappier feel. Setsuna's is 0.3 s. |
| `dash_cooldown` | **1.5 s** | Chosen against his 1.2 s airtime - see *Availability*. Untouched by the 2026-09-18 retune. |

Distance is ~~9.0 m~~ **10.0 m** (`dash_speed * dash_time`), exposed as `dash_distance()`
alongside the existing `jump_distance()`. The move off 9.0 m is a side effect of the speed
bump, not a retune of `dash_time` - see *The 9.0 m collision* below, which this move resolves
in the direction it already flagged as preferable.

### The 9.0 m collision (resolved by the retune)

`pilot9-jump-grid.md` pins gap widths at exactly **3 / 6 / 9 m** for walk / run / sprint, and
`tests/test_pilot9_jump_grid.gd` asserts those round numbers themselves so that moving one
forces somebody to re-measure the map. **The dash originally landed on 9.0 m exactly** - the
same number as the sprint jump.

This was recorded, not resolved, at spec time. It was defensible: the dash is flat where the
jump arcs, takes 0.25 s where the jump takes 1.2 s, and *chained onto a jump roughly doubles his
reach to ~18 m*, which is the actual map-2 unlock. But a 9.0 m dash across a 9.0 m gap lands
precisely on the lip, and in a repo that builds gaps to measured numbers, exact equality is the
one value you do not want.

**The 2026-09-17 speed bump moved distance to 10.0 m, off the lip**, which is the outcome this
section already flagged as preferable to exact equality. It was a side effect of making the
dash snappier, not a deliberate fix aimed at this collision - worth recording so the next
person who touches `dash_speed` knows 10.0 m is load-bearing for the same reason 9.0 m was
flagged as a problem, not an arbitrary number to round back down.

**The dash numbers therefore stay out of `test_pilot9_jump_grid.gd`.** That test earns its
keep by failing only when something settled has moved; pinning three numbers that are expected
to change after one play session trains the reader to ignore it. If 9.0 m survives QA it gets
promoted into the grid, and *that promotion is the moment it becomes a map measurement.*

## Motion

**Flat. Gravity is suspended for the window.** He travels a level line and resumes falling the
frame it ends.

The dash bypasses `_apply_movement()` while it runs, exactly as the slide does through
`_apply_slide_velocity()`. That pattern already exists; the dash is its second user.

### Why flat, and why not Setsuna's rise

Setsuna launches along `DASH_RISE_ANGLE 30`, setting `velocity.y` once and letting gravity bend
the line over. Copied onto pilot9 that is `18 * tan(30) = 10.39 m/s` - **more than his entire
jump velocity of 10.0 m/s.** Every ground dash would launch him higher than pressing jump does.

The alternative - leave gravity running - is worse in the other direction. His gravity is
16.67 m/s^2 (`jump_height 3.0` over `jump_time_to_apex 0.60`), so half a second of it is a
**2.1 m drop from standstill, and ~7 m if he is already falling at speed.** A dash that loses
7 m of height is a dive.

Both of those are "identical code, two different moves". The user's requirement was that the
dash **function the same in the air and on the ground**, and flat-with-gravity-suspended is the
only one of the three that delivers that as the player feels it rather than as the code reads.

It also makes the ink streak a straight horizontal segment in every single case.

**What flat costs:** the dash never gains altitude. It is a gap-crosser, not a way up. Ledges
out of reach of a double jump stay out of reach.

### Direction

**Steerable left/right for the whole window, instant response, no lerp.** Retuned 2026-09-18:
the original design locked the heading at launch with no steering at all; the user tried it,
changed their mind, and asked for free horizontal control while the dash runs, with the one
piece that was never up for debate - no altitude change - untouched. Vertical still cannot
move: gravity stays suspended and `_apply_dash_velocity()` still pins `velocity.y = 0.0` every
frame, exactly as before. Only the horizontal heading is now live.

The heading is the stick direction, camera-relative (`direction`), falling back to whatever
heading he already had when the stick is centred - the same fallback Setsuna's dash uses at
launch, now applied every frame instead of once. `_steer_dash()` reads it each physics frame,
after `_handle_movement_input()` has run, and writes `_dash_direction` straight from it with no
smoothing. Backwards, sideways and diagonal dashes are all available, and the player can move
between them mid-window.

`character.rotation.y` is **welded** to `_dash_direction` every frame in
`_handle_character_rotation()`, not just at launch - joining the climb and the slide as a weld
case there, except re-applied continuously instead of once.

An instant yaw snap is normally exactly what `rotation_speed 10.0` exists to prevent. Here it
is free, every frame, for the same reason it was free at launch under the old design: **he is
invisible for the entire window, so the snap happens behind the curtain.** He vanishes facing
one way, can change heading as many times as the player likes while nobody is watching, and
reappears already oriented down whatever heading he was on when the window closed - no lerp to
watch and no facing pop, because there is nothing on screen for a lerp to smooth in the first
place.

### The exit

**Nothing special** - the dash stops driving velocity and `_apply_movement()` resumes outright
the next physics frame, the same frame `_restore_from_dash()` makes him visible again. Whatever
speed he is carrying when the dash ends is whatever `_apply_movement()`'s ordinary momentum
branch decides to do with it from there.

**Briefly eased instead, for part of one day.** After the 2026-09-17 play session he was found
to carry `dash_speed` forever if the stick stayed pointed the way the dash was already heading,
because `momentum_decay` is 0.0 at the 5d65b07 neutral baseline - correct for its actual job
(carrying speed through a jump is the whole point) but wrong for a speed he never earned by
moving his feet. `_end_dash()` briefly armed `_apply_dash_exit_ease()`, a fourth speed knob
(`dash_exit_ease_time`, 0.5 s) that drove velocity in `_apply_movement()`'s place and blended
`_horizontal_speed()` at the moment the dash ended down to whatever `_apply_movement()` would
ask for that same frame - unconditionally, with no regard for stick agreement.

**Reverted the same day.** The user's call: the dash speed should be gone the instant he
reappears, not visibly draining over half a second after. `_apply_dash_exit_ease()`,
`dash_exit_ease_time`, and the `_dash_exit_ease_*` state it kept are all deleted; `_end_dash()`
goes back to just clearing `is_dashing` and restoring visibility, with nothing left to hand
velocity off to except the next `_apply_movement()` call.

**Addressed later the same day, without touching `momentum_decay` / `momentum_brake`.** Those
two stay off-limits - `pilot9-movement-reset.md` closed that door on purpose for every landing,
slide exit and ledge run-off, not just the dash. Instead `_end_dash()` reads
`_horizontal_speed()` (what he is actually carrying, post `move_and_slide()`) and, only if it
is over `sprint_speed`, clamps it straight down to `sprint_speed` along that same real
heading - one comparison and one assignment, no timer, no fourth speed knob. The forever-carry
case is gone: he can never reappear carrying more than sprint speed, whether the stick agreed
with the dash's heading or not.

This is deliberately an instant clamp, not a blend - the same objection that killed
`_apply_dash_exit_ease()` (visibly draining half a second after reappearing) would apply just
as much to a slower version of this fix. The difference from the ease is *what* it snaps to:
the ease blended toward whatever `_apply_movement()` would have asked for that frame
(potentially all the way down to `speed` or even `crouch_speed`); this snaps to `sprint_speed`
specifically and then lets `_apply_movement()`'s ordinary momentum branch (and
`sprint_toggled`, already forced on) take it from there.

**Downward only.** The clamp compares against `_horizontal_speed()`, not `dash_speed`, and
only fires above `sprint_speed`. A dash cut short by `_check_dash_blocked()` is already near
zero when `_end_dash()` runs for it - the clamp's condition simply does not trigger, so a
blocked dash is never shoved back up to sprint speed into whatever just stopped him.

## Availability

**Two limiters, both applied. The air charge can only ever subtract.**

1. **`dash_cooldown`, 1.5 s, measured from the press** - not from the end of the dash, so the
   constant means what it says. Runs on the ground and in the air alike.
2. **One air charge**, spent by a dash *launched* while airborne, refreshed on `is_on_floor()`.

### Why both

The cooldown alone looks sufficient: 1.5 s against a 1.2 s single-jump airtime already gives
exactly one dash per jump. But **a double jump stretches airtime to ~2.4 s**, which fits two
dashes comfortably - the case the user closed explicitly ("only one dash in the air, whether
they use it before or after the double jump").

The charge is not redundant with the cooldown, it is **robust against it.** `dash_cooldown` is a
slider that is going to get dragged around during QA. Tuned down to 0.8 s one evening, a
cooldown-only rule silently reopens double-air-dashing; the charge holds the line no matter
what the number becomes. The rule the user stated is enforced by the rule, not by the tuning
happening to be large enough.

### Two edge cases, settled

- **Spent based on where he was at launch.** A ground dash that carries him off a ledge -
  which it will, since gravity is suspended and the line is flat - leaves the air charge
  intact. He started it on the floor.
- **Refreshed on `is_on_floor()`**, which covers landing and finishing a mantle onto a ledge.

### Jump

**Jump and dash never touch each other.** Dashing neither spends nor refreshes an air jump, and
`jump` is not readable during the dash at all.

The second half of that is a deliberate break with precedent. The slide's rule is that `jump`
"is the one exit never taken away"; the dash takes it away. The user's call, and the
consequence is the sharpest cost in this design:

> **The dash is 0.25 s of zero control, while invisible, endable only by the timer or by
> hitting something.** Mistime one off a ledge and you watch nothing happen for a quarter
> second, in a game where falling is the only threat.

That is what makes it a commitment rather than a get-out-of-jail button. It is also the single
thing most likely to feel bad on the play session, and it is the first thing to revisit if it
does.

Refusing jump also closes a strong unintended tech: with gravity suspended, jumping out of the
middle of a dash would give a full 10 m/s launch from a body hanging level in the air - height
reachable no other way. Whether that is a loss is a QA question.

## Camera

**Added 2026-09-18, after the retune above - not part of the original play session. Reworked
the same day, before ever being played, once a fixed-rate version was found by inspection to
have a bug - see *Why not a fixed catch-up rate* below. Retuned again 2026-09-19, after the
first play session with the dash: the user liked the dash itself but wanted the camera to
"flow more" - wait longer before it starts catching up, and catch up a bit slower once it
does. See *Delay and duration, decoupled from `dash_time`* below.**

Every other frame in this project welds `CameraPivot`'s position to pilot9's, exactly, in
`_process()` - see the comment there. The dash is the one exception: `_start_dash()` sets
`_camera_dash_lag_active` and captures `_camera_dash_lag_start` (wherever the rig already was -
it was hard-welded right up to that frame, so this is free), and while the flag is true
`_process()` blends position from that start toward the live weld target through
`_camera_dash_lag_position()` instead of snapping onto it every frame.

**The point of it:** he is invisible for the window (see *The look*, above), so there is
nothing to watch leaving the frame - but the camera's anchor can still be left behind while its
aim does not move, so the ink streak grows out toward the edge of a shot that has not followed
it yet, and the shot glides back onto him as the dash's own window closes. Never a cut - the
blend weight is `smoothstep`, so both ends are eased and the close is as smooth as the open.

**Originally tied to `dash_time`, not to a rate.** `_camera_dash_lag_elapsed` ticks up in real
seconds from 0.0 at launch, and `_camera_dash_lag_position()` blended by `elapsed / dash_time` -
at `elapsed >= dash_time` the blend weight was exactly 1.0 and the result exactly the target, no
matter where the target was, which is what guaranteed the rig was back on him within the dash's
own window rather than however long a rate happened to take.

### Delay and duration, decoupled from `dash_time`

**Retuned 2026-09-19, after the first play session with the dash.** The user liked the dash
itself but wanted the shot to "flow more" - the camera should wait longer before it starts
catching up, and catch up a bit slower once it does. Tying the glide's own length to `dash_time`
(0.25 s, already snappy by design) left no room to slow it down without also retuning the dash,
so the catch-up now has two knobs of its own:

- `camera_dash_lag_delay` (default **0.05 s**) - real seconds after launch during which the
  rig holds exactly at `_camera_dash_lag_start` while the live weld target keeps moving. This is
  the "waits" half: `_camera_dash_lag_position()` pins its blend weight at 0.0 for `elapsed <
  delay`, so the gap opens before the glide even starts.
- `camera_dash_lag_time` (default **0.3 s**, was implicitly `dash_time`'s 0.25 s) - how long the
  glide itself takes once the delay has elapsed. Slightly longer than before on purpose - "catch
  up a bit slower".

The window `_camera_dash_lag_active` stays true for is now `delay + duration` (0.35 s at the
defaults) rather than `dash_time` (0.25 s) - longer than the dash itself, so the shot is
sometimes still visibly gliding onto him for a beat after he has already reappeared. That is the
point, not a bug: the exact-convergence property below still holds regardless of how long
`delay + duration` runs, so this does not reintroduce the permanent-offset bug the rate-based
version had - it just moves the deadline further out.

Both ends of the glide are still exact, the same guarantee as before: `elapsed <= delay`
reproduces the launch position bit for bit, `elapsed >= delay + duration` lands exactly on
`target` no matter where the target is by then, which is what lets `_process()` hand back to the
plain hard weld with nothing left to snap into place.

No knob here is tied to `dash_speed` or `dash_time` anymore. Retuning the dash's own length no
longer retunes the catch-up with it - a deliberate reversal of the original design's "the two
must never drift out of sync" reasoning, because the user's ask was specifically to pull them
apart.

### Why not a fixed catch-up rate

The first build of this (see the commit this section replaces) drove the gap with a clamped
exponential lerp, the same shape `_camera_length_step()` uses for the wall-collision zoom, at a
fixed `dash_camera_catchup_speed`. That has a real bug: a first-order chase after a target
moving at constant velocity never fully closes the gap - its steady-state error is proportional
to the target's speed - so as long as the player kept holding a direction after the dash ended,
the camera stayed visibly behind, and only caught up once they let go and pilot9 slowed to a
stop. **The dash felt like it left a permanent camera offset behind it that only resolved on
its own schedule, not the dash's.**

`_camera_dash_lag_position()` fixes this by blending toward the LIVE target with a weight
driven by elapsed real time against `camera_dash_lag_delay + camera_dash_lag_time`, rather than
by a rate chasing a live position gap. That end of the blend is exact by construction - weight
1.0 always lands on wherever the target currently is, moving or not - so the fix is not a bigger
rate, it is not using a rate at all for the deadline. This property is what made the
2026-09-19 retune (above) safe: pulling `delay` and `duration` out to their own knobs, and even
letting their sum run past `dash_time`, does not reopen the permanent-offset bug, because
nothing here is rate-based to begin with.

### Blocked mid-dash

`_check_dash_blocked()` still calls `_end_dash()` early and still zeroes `_dash_time_left` -
untouched by this. `_camera_dash_lag_elapsed` is deliberately a separate clock, ticked in
`_process()` off wall-clock time rather than borrowed from the dash's own countdown, precisely
so a wall stopping the dash early does not also truncate the camera's remaining catch-up budget
into a snap. A dash cut short partway through still leaves the rig its full
`camera_dash_lag_delay + camera_dash_lag_time` window to wait, then glide, onto wherever he
actually stopped - visible slightly before the camera has fully resettled, which is a fine trade
against the alternative of a pop the instant he hits something.

**Does not touch rotation.** Mouse look is exactly as responsive mid-dash as it has always
been - only the rig's anchor point is blended, never its aim.

**Not asserted beyond the arithmetic.** `_camera_dash_lag_position()` is pure and pinned in
`tests/test_pilot9_dash.gd`, the same way `_camera_length_step()` is pinned in
`tests/test_pilot9_camera_collision.gd` - including a regression test standing in for the
still-moving-target bug above. The flag, the elapsed clock, and the feel of the trail itself
all live in `_process()`, a drawn-frame callback no headless run ticks - see *What cannot be
checked headlessly* below. **This has not been played yet.**

## Interactions

| Verb | Result | Why |
|---|---|---|
| **Crouch** | Dash wins. Clears `is_crouching`, then dashes. | What Setsuna does, and free here: **pilot9's collider never resizes.** The capsule is 1.955 m whether he stands, crouches or slides - `collision_shape` is only ever *disabled* (mantle, EXIA boarding), never shrunk. There is no stand-up clearance problem in this controller to worry about. |
| **Slide**, including the hold | Dash wins. `_end_slide()`, then dashes. | Slide-cancel-into-dash is real tech and cannot be exploited: the dash is a flat 18 m/s regardless of carried speed, and the exit hands straight to the momentum brake. It **converts** speed, it does not stack it. It also gives the hold - where he currently sits frozen on a pose until `crouch` or `jump` - a third exit. |
| **Mantle / climb** | Blocked. | The climb is a scripted position lerp **with the collider disabled**. A dash fired mid-mantle flings a collider-less pilot 9 m through geometry. Not a design choice. |
| **Frozen** (EXIA, menus) | Blocked. | Same class. `_handle_crouch_and_slide()` already bails on `frozen`; the dash does the same. |

### Blocked mid-dash

**The dash cuts the instant he is actually blocked.** After `move_and_slide()`, compare the
horizontal magnitude of `get_real_velocity()` against the `dash_speed` he demanded; a small
fraction of it means he is stuck. End the dash, he reappears where he stopped.

This is not a polish item, it is load-bearing. Without it, the naive implementation produces
**an invisible pilot pinned motionless against a wall for up to a quarter second**, reappearing
exactly where he already was - which is the most common thing that will happen in a tight
parkour map, and which reads as a bug rather than a move.

One velocity comparison catches walls, corners, slope shoulders and ceilings without any normal
math.

**No cooldown refund.** A refund would make *dash into a wall* the fastest way to reset the
cooldown, and with no HUD (see below) the player cannot see a refund happen - they would only
notice the dash is sometimes ready early and never learn why.

## The look

Originally two cues, chosen because they **cover each other's blind spots**, at no cost in
assets. **The shadow cue was cut on the 2026-09-17 retune** - see the subsection below for what
it was and why it went. The ink streak is now the only cue.

### He goes shadows-only, not invisible (cut 2026-09-17)

> **This cue no longer exists.** `_hide_for_dash()` now sets `visible = false` on every mesh
> instead of `cast_shadow = SHADOWS_ONLY`, so the dash is a clean vanish with no shadow running
> along the floor. Kept below for the record of what was tried and why it was cut - a plain "we
> removed it" note would lose the reasoning if the shadow cue is ever reconsidered.

Every `MeshInstance3D` under `character/` was set to `cast_shadow = SHADOWS_ONLY` for the
window, reached through the existing static `apply_stylized.collect_meshes()`. Body gone, cel
outline gone (it is a `next_pass`, so it goes with the colour pass) - but his shadow kept
tearing across the floor at dash speed.

`docs/cel-look-rollout.md` puts the sun at a low sunset angle, so that shadow was long and
raking. It was the most legible "something fast just went through here" signal available, it
was drawn by the renderer already running, and it was unmistakably him - his real silhouette in
his real pose, which carries more character than any trail can.

**Its limitation was honest: over a gap there is no floor to catch it.** Mid-air dashes across
open space fell back to the streak alone, which is exactly where the dash is most dramatic -
and that inconsistency (a cue that only sometimes shows up, depending on what's underfoot) is
the likeliest reason it read as unwanted noise on the play session rather than as a second cue
reinforcing the first.

**Restore now returns each mesh to its *original* `visible` value, captured on the way
in - not blanket-set to `true`.** Same rule the cast_shadow version followed, carried over so a
mesh authored hidden is not permanently changed by its first dash.

**The `AnimationTree` keeps running** on the hidden skeleton. It is a quarter second of wasted
work; switching it off leaves the state machine stale and pops him back in the wrong pose,
which is the one visual artifact this design cannot absorb.

### The ink streak

**A bundle of 5-7 thin manga speed lines, camera-facing, growing behind him.**

> **Replaced the single ribbon on 2026-09-19.** The dash shipped with one black stroke 0.35 m
> wide, tapering to a point at the tail. The user liked it and wanted it pushed: thinner lines,
> more of them, reading as manga speed lines rather than as one slab. The old ribbon's
> behaviour - world-space, path-following, camera-facing, growing, lingering - is kept whole;
> what changed is that there are now several strokes instead of one and they are sized like pen
> marks instead of like objects. The single-ribbon build is at commit `a3a4723`.

- An `ImmediateMesh` rebuilt each physics frame from his sampled positions over the window,
  **one surface per line** - the strokes carry different alphas on the same frame (see the
  staggered fade below) and a triangle strip cannot break between them without degenerate
  stitching, which at these widths would be visible.
- Unlit, **pure black** - `outline_color` is `Color(0,0,0,1)` and every object in this game is
  inked in it. Black strokes drawn in the same pigment as the rest of the frame read as part of
  the drawing. White would read against more backgrounds but would introduce a value that
  exists nowhere else in the palette and would look borrowed.
- **World-space, not screen-space.** A screen-space overlay is the literal manga device and it
  was considered and rejected: it ignores occlusion, and it would fire identically whether he
  dashes the full 10 m or slams a wall at 2 m. This is still the first VFX in the project and
  still the pattern-setter for wall-run, rail grind and every boss after it, and that pattern
  should be one that knows about the world.
- **The lines converge on him.** Offsets are full at the tail and shrink to `streak_converge`
  (0.25) of themselves at the head, so the bundle splays open behind him and pinches where it
  meets his body - which is "coming out of him" stated as geometry. Not all the way to a point:
  at zero the strokes merge into a blob exactly where the eye is looking.
- **Centred on his chest**, `streak_anchor_height` (1.1 m) above the sampled path. `_dash_points`
  samples `global_position`, which is his **feet** - the collision capsule sits 0.978 m above
  it - so the original ribbon was in fact a stripe at ankle height. Without the anchor the
  bundle converges on his ankles.
- **Offsets sit on an ellipse** around the path, `streak_spread_side` (0.30 m) across and
  `streak_spread_vert` (0.70 m) tall, so the lines go up and down as well as left and right.
  A flat row is a comb the moment the camera is above it. Sized against his collision capsule
  (radius 0.34) so the whole bundle stays inside his silhouette: the user's call, 2026-09-19 -
  the lines are supposed to come out of him, not pass him.
- **Each line is a spindle**: thin, swells, thin, fattest at `streak_swell_bias` (0.65) along
  its own length. That is the shape a pen leaves when it lands, presses and lifts, and it is
  the single cheapest thing that makes a row of quad strips read as drawn rather than extruded.
  Past 0.5 puts the mass near him, where the flick leaves it.
- **Pen weight is in pixels, not metres** - roughly 1 px to 3 px, against the 4 px
  `outline_width` and the 2 px `crease.gdshader` line. This is the one thing about the original
  ribbon that was simply wrong: every other ink in this game is pixel-constant and says so
  (`crease.gdshader`: *"constant in pixels, not in metres, at any resolution and any
  distance"*), and the streak alone was measured in metres. It is also the one that could not
  survive thinning - a 2.5 cm hairline goes sub-pixel as soon as the camera pulls back, and
  seven of them shimmering in and out for 0.4 s is a rendering fault, not an effect. **Clamped**
  by `streak_max_width` (0.12 m), because a pen weight is a fixed *angular* size and a camera
  on top of the bundle would otherwise resolve 3 px into a slab.
- **Weights and lengths are spread and then shuffled**, by two independent permutations. Lines
  get weights spaced evenly across `[streak_weight_min_px, streak_weight_max_px]` and lengths
  spaced across `[streak_length_min, 1.0]`, so the bundle always contains both light and heavy
  strokes and always ends ragged. Sampling either at random would let a dash come up with seven
  near-identical lines - a comb - which is the one outcome the bundle cannot have. Two
  permutations rather than one, or thickness would be tied to length forever.
- **Reseeded on every launch**, so no two dashes draw the same bundle and the effect does not
  go stale over a play session.
- **Grows as he travels**, rather than being drawn full-length at launch. A dash cut short by a
  wall must produce short lines, not 10 m ones hanging through the geometry he hit.
- Lingers **~0.15 s** after he reappears, then fades **staggered** - thinnest strokes wink out
  first, heaviest last, by `streak_fade_stagger` (0.5) of the curve. Seven lines dimming in
  unison look like a texture fading; dropping away one at a time looks like ink, and it keeps
  the silhouette strong right to the end instead of dissolving into mush. This matters more
  than it sounds: he is *invisible* for the whole 0.25 s travel, so the linger is the only part
  of the effect where there is a character on screen at all. The money frame is pilot9
  reappearing with seven strokes converging into his chest.
- **Camera-facing is not optional.** A flat strip seen edge-on is one pixel wide, and dashing
  toward or away from the camera is precisely when it would be edge-on.

#### The boil, built and shipped off

`streak_boil` re-randomises the offsets on a `streak_boil_hz` (12 Hz) clock while the streak is
alive, the way cel animation on 2s wobbles. It is **off by default and that is the
recommendation**, not an oversight.

The streak lives `dash_time + DASH_STREAK_LINGER` = 0.4 s, which is five frames at 12 Hz. Boil
reads as *hand-drawn* when there are a couple of seconds of it; at five frames the eye has no
time to build the pattern and it reads as flicker or as a rendering fault - the worst failure
available to a cue whose entire job is to be read instantly. It is the one place in this effect
where "fancy" and "reads as speed" pull against each other.

Built anyway, behind the toggle, because boil is the project's whole art direction and that is
worth seeing in play rather than arguing about in a document. The user's call, 2026-09-19:
build it, ship it off, judge it in play.

#### Every number is exported

`streak_line_count`, the two spreads, the anchor, the converge fraction, the two pen weights and
their clamp, the swell bias, the minimum length, the fade stagger and the three boil knobs are
all `@export`, in a `Dash Streak` group. Same reasoning as `dash_speed` and `dash_time` before
them: a bundle's look is found by tuning it while playing, not by picking values in a file. This
is the knob set, and finding the good values on it is the play session's job.

### Why the two cues paired (historical - the shadow cue is cut)

Black reads strongly against the bright sunset sky and lit ground and weakly against dark
shadowed ground - which was exactly where his own raking shadow was most visible. Bright
background, the streak carried it. Dark background, the shadow carried it. With the shadow cue
gone, the streak's weak case (a dash over dark ground) has no second cue backing it up - worth
watching for if streak legibility becomes a complaint now that it is carrying the whole look
alone.

### There is no HUD

`scripts/ui/ui_manager.gd` is explicit: *"AN EMPTY STACK MEANS GAMEPLAY: nothing drawn, no
dim."* The only thing that draws during play is the interaction prompt. Setsuna had a dash-ready
light on her backpack screen (`setsuna-screens.md`); pilot9 has nowhere to put one.

**The cooldown and the air charge are therefore learned by feel or not at all.** That is the
reason `dash_cooldown` was picked against his airtime rather than for its own sake: at 1.5 s
against a 1.2 s jump the rhythm is "jump, dash, land", which is a pattern a player can
internalise without being shown a number.

## Input

A new `dash` action in `project.godot`:

| Device | Binding |
|---|---|
| Keyboard | **Right mouse button**, plus **Ctrl** as a second event on the same action |
| Gamepad | **Left trigger** (axis 4) |

**Not one action in this project currently uses a mouse button.** There is no combat and no
aiming, so the entire mouse is free - unusual, and worth spending. The right hand is already
there, RMB is a zero-travel press, and a dash wants to be instant. Ctrl rides along so the
Setsuna muscle memory still works and there is a keyboard-only option.

On the pad, dash on LT against sprint on RT is a symmetry players read without being told. The
shoulders were unavailable regardless - `tab_prev` and `tab_next` hold both.

Read with `Input.is_action_just_pressed("dash")` inside `_physics_process`, the way pilot9
reads `jump` and `crouch` - **not** through the `_unhandled_input` queue Setsuna uses. His
`jump_buffer_time` is 0.0 at the neutral baseline, and giving the dash a queued, buffered input
would make it the only verb in his kit with a buffer - a movement-assist decision 5d65b07
closed.

## Gating

`can_dash: bool = true`, exported. On by default.

`tab_abilities.gd` gains one `BASE_KIT` row, `["DASH", "can_dash", ...]`, read live off the
export by `_reads_true()`. **The `AIR DASH - Found in map 2` row in `TECH` is left exactly as
it is.**

This mirrors the file's existing treatment of the double jump, which is listed **twice** - once
in `BASE_KIT` reading `air_jumps` live, once in `TECH` as "Found in map 1". The file already
says: *the verb is built and on for testing; the fiction of finding it is separate.* Gating the
dash behind map 2 would gate it behind nothing, because map 2 does not exist.

## Tests

`tests/test_pilot9_dash.gd`, in the house style - **silent-failure seams only**, nothing that
recomputes arithmetic it just performed.

- `InputMap.has_action("dash")`.
- **The `BASE_KIT` row string matches the real property name.** `_reads_true()` looks the
  property up by string; a rename on either side renders the row permanently `LOCKED` with
  nothing in the log. This is the same class of failure `CROUCH_SCALE` and `SLIDE_SCALE` exist
  to catch.
- The exported knobs exist with the expected defaults (40.0 / 0.25 / 1.5) and `can_dash` is true.
- `dash_distance()` returns **9.0**.
- **The availability predicate as a pure function** over `can_dash`, cooldown remaining, air
  charge, `is_on_floor()`, `is_climbing` and `frozen` - this is where the both-limiters rule and
  all four blocked states are actually pinned.
- The air charge: spent at launch only when airborne, refreshed on floor.
- **The hide/restore round-trip**: every mesh reaches `SHADOWS_ONLY`, and restore returns each
  one to the value it had *before*, not a blanket ON.
- **The streak bundle's geometry**, which is the bulk of it: one line per configured count,
  every line a spindle thin at both ends, pen weight constant in pixels (twice the camera
  distance is twice the width in metres) and clamped in close, the bundle wider at the tail
  than at the head, nothing drawn down at his feet, a spread of weights and a spread of
  lengths, fade floors running thinnest-first, the same seed rebuilding the same bundle and a
  different seed a different one, the boil moving nothing while it is off and something while
  it is on. Plus the degenerate cases: zero points, one point (a dash blocked on its first
  frame), a dash that never moved, and a one-line bundle.
- **Steering**: a held stick moves `_dash_direction` (and the welded mesh) onto it with no lag
  and no lerp, a centred stick holds whatever heading was already running, and the vertical
  component stays exactly zero regardless of what the stick asks for.

### What cannot be checked headlessly, and will not be claimed

The feel. Whether the vanish reads as a dash or as a dropped frame. The streak's appearance.
The shadow cue. The blocked-dash cut, which needs real collision. The input press itself, which
needs a running frame and a body resting on a collider - the same wall
`test_pilot9_double_jump.gd` and `test_pilot9_jump_slide.gd` both hit. The camera catch-up's
feel is the same class of gap - whether the trail reads as flow or as the shot just lagging -
see *Camera*, above.

**The play session is the acceptance test.** Passing tests here mean the wiring is not silently
broken; they say nothing about whether the dash is any good.

## Risks to watch on the play session

1. **The 0.25 s of zero control.** The likeliest complaint, and the design's sharpest edge. See
   *Jump* above.
2. **Ground dash-spam.** The ground dash was argued against during scoping and the user
   overruled it deliberately - 9 m in a quarter second may make run / sprint / slide decorative
   for crossing floors, and the optimal way over any surface may become dash on cooldown.
3. **9.0 m landing exactly on the 9.0 m sprint gap lip.** Harmless on the flat test platform,
   dicey the moment gaps are built to measurement. See *The 9.0 m collision*.
4. **Ink streak legibility against dark ground, now sharper.** No longer backstopped by the
   shadow cue, which was cut on the 2026-09-17 retune - the streak is the only visual cue the
   dash has. The 2026-09-19 bundle makes this *worse before it is judged*: seven hairlines are
   a weaker silhouette than one 0.35 m slab was, and keeping a reduced centre stroke as
   insurance was offered and declined - the user's call, and the right one for the look, since
   a bundle with a dominant member is not a bundle. If the dash goes illegible over dark
   ground, the first knobs to reach for are `streak_weight_max_px` and `streak_line_count`.
5. **Carrying `dash_speed` forever with the stick held the way he was already dashing.** The
   exit-ease that fixed this was built and reverted the same day, 2026-09-18 - see *The exit*.
   Un-fixed on purpose; watch for it on the play session.

## Deliberately not built

- **No dash clip, no state machine entry, no TimeScale.** The whole point.
- **No dash VFX beyond the line bundle** - no particles, no camera shake, no FOV punch. A sprint FOV
  boost already exists (`sprint_fov_boost`); whether the dash wants its own is a question for
  after the first play, not before.
- **No sound.** The project has none yet.
- **No cooldown indicator.** Nowhere to put one - see *There is no HUD*.
- **No wall-dash, no dash-jump, no dash cancel into slide.** Map 3 and 4 tech; not this.
