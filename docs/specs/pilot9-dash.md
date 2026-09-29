# Spec: pilot9's dash

> **2026-09-28: THE VANISH IS RETIRED.** He now stays visible for the whole dash, running the
> ground sprint cycle at speed, and leaves a Sandevistan trail of flat cyan-to-green afterimages
> (the Cyberpunk: Edgerunners look). The manga speed lines are removed; the last build with them
> is commit `c36e25e`. Grilled and decided the same day, ten decisions, all recorded in
> *The afterimages* below, which replaces *The ink streak*. Wherever older text below says he is
> invisible, hidden, or that there is no clip or state for the dash, it is history: there is now
> a `dash` state, and nothing is hidden. The movement (speed, time, steering, exit, camera lag,
> FOV kick) is unchanged.
>
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

**Current (2026-09-28): pilot9 sprints 10 m in a quarter second, fully visible, and every
~1.6 m he leaves a frozen afterimage of the pose he was in.** See *The afterimages*. The
original rule, kept for the record:

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

**Current since 2026-09-28: the afterimages.** He stays visible and the trail is made of him.
History: the dash shipped with two cues, a shadow running along the floor while he was hidden
and a black ink streak. The shadow cue was cut on 2026-09-17. The streak became a bundle of
manga speed lines on 2026-09-19 (commit `c36e25e` is the last build with it) and was removed
on 2026-09-28. The full reasoning for both lives in git history; this section only describes
what exists now.

### The afterimages

The Sandevistan trail from Cyberpunk: Edgerunners: a row of copies of him, each frozen in the
pose he had at that spot, in a flat colour, while he runs on in full colour. Decided in a
grilling session on 2026-09-28; each numbered point below is one of those decisions.

1. **He stays visible.** `_hide_for_dash()` / `_restore_from_dash()` and the per-mesh
   visibility cache are gone. The copies need a real pose to freeze, and a hidden pilot9 has
   none.
2. **Pose: the ground sprint cycle, forced, sped up.** A new `dash` state in the
   AnimationTree plays `sprint_forward` (the same clip the wall-run uses) through a TimeSeek
   and a TimeScale. The scale is `dash_anim_speed` (**2.5x**), so the 0.25 s window runs about
   one full stride and every ghost has different legs. It runs in the air as well: an air dash
   is him running on nothing, which is exactly what the reference shows. Each dash starts from
   the same clip time, `dash_anim_phase`, so the leg pattern of the trail is the same every
   time and can be tuned.
3. **Ghost look: a flat, unlit single-colour fill, with the ink outline kept but tinted
   a darker shade of the fill.** *(2026-09-28: now 50% see-through - see the note after 5.)* No lighting bands, no rim light, no shadow, and not
   see-through while alive. Two shaders: `shaders/cel/vfx/afterimage.gdshader` (fill) with
   `afterimage_outline.gdshader` as its `next_pass` (the same inverted-hull push as
   `outline.gdshader`, same global `outline_width`). The colour is an `instance uniform`, so all
   ghosts share one material.
   **Colour runs cyan at his heels to green at the tail:** the newest ghost is
   `afterimage_head_color`, the oldest one `afterimage_max_count - 1` steps back is
   `afterimage_tail_color`. The colour goes by rank from the newest, recomputed as ghosts spawn,
   so a dash cut short at 2 ghosts still has cyan next to him rather than two green ones. The
   ink is the fill times `afterimage_line_darken` (0.45).
4. **Count: by distance, one every `afterimage_spacing` (1.6 m), at most
   `afterimage_max_count` (6).** The first is dropped at the launch point; a full 10 m dash
   leaves ghosts at 0, 1.6 ... 8.0 m, and he reappears at 10 m. Distance, not time, so a dash
   stopped by a wall leaves only the ghosts it actually earned. At 40 m/s he moves 0.67 m per
   physics tick, so a ghost is placed at the exact crossing distance along that tick's segment
   rather than at the tick's end, or the gaps would alternate between 1.33 and 2.0 m.
5. **Lifetime: hold, then clear tail to head.** Every ghost stays fully solid until the dash
   ends. Then the oldest starts to go first and each one after it follows, the whole trail
   gone `afterimage_clear_time` (0.35 s) after he reappears. Each ghost's own fade lasts
   `afterimage_fade_time` (0.12 s); the gap between one ghost's start and the next is whatever
   is left, `(clear - fade) / (count - 1)`. **The fade is a dissolve, not alpha**: a screen-space
   hash throws away more and more pixels, so the ghost stays opaque, writes depth and never
   needs sorting against its neighbours. A transparent fade would have the overlapping copies
   show through each other, which is the translucent option that was turned down.

   **2026-09-28, 50% opacity (user request):** fill and ink are now drawn at
   `afterimage_opacity` (0.2 since 2026-09-28 - 0.5 still blocked the camera; instance uniform `ghost_opacity`). The "no show-through" rule
   survives: two depth-only passes (`afterimage_depth.gdshader`, `afterimage_outline_depth.gdshader`,
   render priority -1) lay down every ghost's depth before any ghost's colour, so a ghost blends
   only its front surface over the world - never its own limbs, and never the ghost behind it.
   Known cost: transparent things (particles) directly behind a ghost are hidden, not tinted.
6. **The speed lines are removed** - the exports, `_streak_bundle()`, `dash_streak.gdshader` and
   their tests. The ghosts are the trail now, and black lines through the cyan would muddy both.
7. **Camera lag and FOV kick are unchanged.** Known limit: the camera sits behind him and most
   dashes go away from it, so a dead-straight dash shows the ghosts stacked in depth, mostly
   covering each other. Sideways and diagonal dashes look like the reference. A small camera
   rise during the dash to look down the trail was offered and held back until the play session
   says straight dashes read as a blob.
8. **What is copied: body plus staff, nothing else.** Every visible `MeshInstance3D` under
   `character` - that includes the held item, which rides under his skeleton. Skinned meshes are
   frozen by giving each ghost **its own skeleton with his pose copied onto it** (see *Frozen
   skeletons, not baked meshes*, below - the original bake lagged every dash); a non-skinned one
   (the staff) just shares its mesh. Materials, the rim-light overlay and the movement VFX
   (which are not under `character`) are not copied.
9. **Setting: MOVEMENT EFFECTS.** Off, no ghosts - the dash is him sprinting very fast, with
   the FOV kick and camera lag still there. The streak ignored the setting because it was the
   only sign of where an invisible pilot9 went; that reason is gone.
10. **Switch in: hard cut. Switch out: ~0.1 s blend.** `_start_dash()` calls
    `playback.start(&"dash")`, seeks to `dash_anim_phase` and `advance(0)`s the tree, the same
    hard-cut pattern the mantle uses - so the first ghost, dropped the same tick, is already
    the sprint pose and not half of whatever he was doing. The exits are 0.1 s transitions to
    `jump` / `fall` / `Locomotion`, all gated on `not is_dashing`.

**Also changed by "he is visible now":** the heading is still welded to `_dash_direction`
every frame, so a hard keyboard turn mid-dash is an instant yaw snap on a visible body. Kept on
purpose - player control beats clip fidelity on pilot9 - but it is on the risk list.

**Where it lives:** `scripts/pilot9_afterimage.gd` (`Pilot9Afterimage`) owns the ghosts - how
they are made, coloured and faded. `pilot9.gd` only says *when* (launch, each tick of the dash,
the end, boarding), the same split as `pilot9_vfx.gd`. The ghosts are `top_level` children of
it, so they stay put in the world while he runs on.

#### Every number is exported

`dash_anim_speed`, `dash_anim_phase`, `afterimage_spacing`, `afterimage_max_count`, the head /
tail colours, `afterimage_line_darken`, `afterimage_clear_time` and `afterimage_fade_time`, in
an `Afterimage` group. Same reasoning as every other dash number: found by tuning in play.

#### Built (2026-09-28) - where the build differs from the points above

- ~~The launch ghost is one drawn frame late~~ and ~~the bake cannot run headless~~ - both were
  properties of the bake, and went with it (see below).
- `pilot9.tscn` was rebuilt with `scripts/pilot9_build_scene.gd` to add the `dash` state.

#### Frozen skeletons, not baked meshes (2026-09-28)

**Why:** the first build froze each ghost with `bake_mesh_from_current_skeleton_pose()`, and
the dash lagged on every use. Measured windowed (`tests/_probe_dash_lag.gd`): pilot9 is 12
skinned meshes, about 58k vertices, and the bake reads each one back from the GPU, skins it on
the CPU and uploads a new mesh - about **27 ms per ghost**, six ghosts in a quarter second. Dash
frames averaged 12.5 ms with a 42 ms worst against 5.5 / 6.1 ms with the ghosts off.

**What replaces it:** each ghost is a `Skeleton3D` of its own, carrying a copy of every skinned
`MeshInstance3D` that **shares his mesh and skin** and points at that skeleton instead of his.
Freezing a ghost is copying his bone poses onto its skeleton; the GPU skins it exactly as it
skins him, and a skeleton nobody changes is not re-skinned. Prototyped in
`tests/_probe_frozen_skeleton.gd`: 0.03 ms to pose and show a ghost, no frame spikes with six on
screen, 1.9 ms to build six.

1. **A pool, built once.** `afterimage_max_count` ghosts are built when the pilot is set up and
   hidden. A dash takes them in order, a clear hides them and hands them back - nothing is
   created or freed while he dashes. The pool is rebuilt (at the next launch, not mid-dash) if
   the set of meshes under `character` changed - a different held item - or
   `afterimage_max_count` was retuned.
2. **The pose is read from `skeleton_updated`.** His final pose, with the staff-hold and
   wall-hand modifiers applied, is snapshotted on his skeleton's `skeleton_updated` signal, and
   only while a dash is live. A ghost dropped on a physics tick gets the latest snapshot: the
   pose last drawn, the same one-frame staleness the bake had.
3. **The launch ghost waits for the first snapshot after the hard cut**, not for a drawn frame.
   The cut's `advance(0)` has set the sprint pose on the tree but his skeleton has not
   re-emitted yet, so a launch-tick snapshot would still be whatever he was doing. It is placed
   back at the launch point, as before.
4. **The staff and anything else non-skinned** is still a plain copy sharing its mesh, placed
   at its own world transform, and has its mesh re-pointed on each drop so a swapped item shows.
5. **Headless now gets real poses.** A snapshot is plain scene-side bone data, so the tests can
   check that a ghost's skeleton carries his pose - which the bake could never show them.

The look, spacing, colour, clear and dissolve are unchanged.

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
- ~~The hide/restore round-trip~~ - gone with the vanish, 2026-09-28.
- **The afterimages (2026-09-28):** the spacing crossings (a ghost at 0 and at every multiple of
  `afterimage_spacing`, placed at the exact crossing along a tick's segment, capped at the max
  count), the colour by rank (newest = head colour, `max_count - 1` back = tail colour), the
  tail-to-head clear (the oldest starts first, all fully solid at the moment the dash ends, all
  gone at `afterimage_clear_time`), the `dash` state and its TimeScale / TimeSeek parameter
  paths existing in `pilot9.tscn` (the same silent-rename seam as `CROUCH_SCALE`), and a ghost
  from the real scene carrying the afterimage material and no shadow. Since the frozen-skeleton
  rebuild: the launch ghost waits for a snapshot, a dropped ghost's skeleton carries his bone
  poses, its skinned copies share his mesh and skin, and a clear returns ghosts to the pool
  rather than freeing them.
- ~~The streak bundle's geometry~~ - removed with the streak, 2026-09-28.
- **Steering**: a held stick moves `_dash_direction` (and the welded mesh) onto it with no lag
  and no lerp, a centred stick holds whatever heading was already running, and the vertical
  component stays exactly zero regardless of what the stick asks for.

### What cannot be checked headlessly, and will not be claimed

The feel. Whether the afterimages read as Sandevistan, and how the stacked trail looks on a
straight dash. (Historical: whether the vanish read as a dash, the streak's appearance.)
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
4. **Straight-ahead dashes stack the ghosts in depth** (2026-09-28). The camera is behind him,
   so a trail going straight away from it is mostly one cyan shape. First fix to reach for: a
   small camera rise during the dash (held back, see *The afterimages* point 7).
5. **Carrying `dash_speed` forever with the stick held the way he was already dashing.** The
   exit-ease that fixed this was built and reverted the same day, 2026-09-18 - see *The exit*.
   Un-fixed on purpose; watch for it on the play session.
6. **Yaw snaps are now visible** (2026-09-28). The heading still welds to the stick each frame;
   a keyboard 90 degree turn mid-dash pops his body round. Kept for control.
7. **The bake cost.** `bake_mesh_from_current_skeleton_pose()` skins on the CPU; six of them per
   dash spread over 0.25 s. If a dash hitches, this is the first suspect.

## Deliberately not built

- ~~No dash clip, no state machine entry, no TimeScale.~~ Reversed 2026-09-28: there is a `dash`
  state playing the sprint cycle, because the afterimages need a pose. Still no authored dash clip.
- **No dash VFX beyond the afterimages** (was: the line bundle) - no particles, no camera shake, no FOV punch. A sprint FOV
  boost already exists (`sprint_fov_boost`); whether the dash wants its own is a question for
  after the first play, not before.
- **No sound.** The project has none yet.
- **No cooldown indicator.** Nowhere to put one - see *There is no HUD*.
- **No wall-dash, no dash-jump, no dash cancel into slide.** Map 3 and 4 tech; not this.
