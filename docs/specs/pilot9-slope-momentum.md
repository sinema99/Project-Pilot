# Spec: slopes as momentum

> **Status:** built 2026-09-08, **played the same day**. The slopes read right; the stop did
> not - `momentum_brake` below is the answer to that play and was played 2026-09-28 - feels good.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-slide.md`, `docs/specs/pilot9-slide-hold.md` and
> `docs/specs/pilot9-slide-crouch.md`. The slide's entry, its clip, its steering and its
> exits are unchanged; what changes is the **speed** it runs at and what happens to that
> speed afterwards. *(The exits did change afterwards -
> `docs/specs/pilot9-slide-stand.md`, 2026-09-09 - and for this spec's reason: a slide that
> ended in a crouch handed the speed built here straight back.)*
> **Serves:** `docs/game-overview.md` - the parkour direction. A slope was scenery; this
> makes it one of the four techs' fuel.

## Problem statement

The slide holds a **constant** horizontal speed - `_slide_hold_speed`, measured off the clip
and then flat forever, "no friction, no gravity term, by the user's call"
(`pilot9-slide-hold.md`). Three things follow from that, and all three are wrong for a
parkour platformer:

1. **A slope gives nothing.** `move_and_slide()` projects a constant horizontal velocity
   down a grade, so a descent covers ground at `speed / cos(theta)` along the surface and
   the same metres per second across the map. A 30 degree ramp is worth 15% and it is worth
   it only while you are on it. There is no reason to seek a slope out.
2. **He does not stay on the grade.** `floor_snap_length` is Godot's default 0.1 m. At the
   slide's ~8 m/s one frame is 0.13 m of horizontal travel, which on any grade past 37
   degrees drops him further than the snap can reach - so he leaves the surface at the crest
   and finishes the ramp as a series of little airborne hops, each one of which ends the
   slide (`_handle_crouch_and_slide` ends a slide the moment `is_on_floor()` goes false).
   That is the literal "does not slide down slopes nicely".
3. **Speed cannot be banked.** `_apply_movement()` hard-assigns `velocity.x/z` from the stick
   every frame, so whatever a slide reached is deleted on the frame it ends - in mid-air
   included. Jumping out of a fast slide launches him at walking pace.

## The rule

**Gravity accelerates a slide down a slope, friction bleeds that gain back off on the flat,
and what he has when the slide ends stays with him.**

Four parts, in the order the player meets them.

### 1. He sticks to the grade

`floor_snap_length` is set to `FLOOR_SNAP_LENGTH` (0.5 m) in `_ready()` - the same value and
the same reason as `player.gd`, which has had it since Setsuna's first build. 0.5 m covers a
frame's drop at 20 m/s on a 45 degree face, which is the steepest thing Godot will still call
a floor at the default `floor_max_angle`.

`floor_constant_speed` stays **false** (the default), and that is load-bearing rather than
inherited. False means Godot moves him the full horizontal distance each frame and lets the
snap find the surface below, so a descent is *faster along the ground* than the same speed on
the flat; true would hold his surface speed constant and hand the descent back to nothing.

Nothing else about the body changes. `floor_max_angle` is left at 45 degrees, so anything
steeper than that is a wall he falls off rather than a ramp he rides.

### 2. Gravity drives the slide

A slide's horizontal speed is now

```
speed = <what the clip says> + bonus
```

where `<what the clip says>` is exactly what it was - the differentiated `slide_motion` curve
during the run-in and run-out, `_slide_hold_speed` during the hold - and `bonus` is a single
scalar in m/s carried along `_slide_direction`. **The clip's own numbers are untouched**, so
a slide on flat ground is the slide that was built, frame for frame, and every existing
assertion about it still holds.

The bonus integrates, every grounded slide frame:

```
bonus += (g * sin(theta) * cos(theta) * dot(heading, downhill) * slide_slope_accel) * delta
bonus -= slide_friction * delta          # toward zero, never through it
```

- `g * sin(theta)` is the acceleration along the surface; the extra `cos(theta)` projects it
  back onto the horizontal, which is the frame the whole slide is computed in.
- `dot(heading, downhill)` is the grade **he is actually travelling on**, +1 straight down a
  fall line, 0 along a contour, -1 straight up. So the player carves for speed with the same
  stick that steers the slide, and pointing uphill costs.
- The horizontal component of a floor normal points **downhill** - the same fact
  `player.gd::_slope_pitch()` is built on.
- Friction touches **only the bonus**, and this is the whole of the answer to "does a slide
  decay". On the flat, `bonus` is the only thing decaying and it decays to zero, leaving the
  constant, unending hold the user asked for in `pilot9-slide-hold.md` exactly as it was. A
  long flat after a ramp is a slow bleed back to the clip's speed, not a stop.
- Total speed is clamped to `slide_max_speed` and to zero from below.

Airborne frames add nothing. A slide that leaves the floor is over anyway.

**The stall exit.** Sliding up a grade the bonus goes negative and the total speed falls. At
`SLIDE_STALL_SPEED` (1.5 m/s) the slide ends itself into a crouch - the same ending
`crouch` gives from a hold, and for the same reason: there is no run-out worth playing at
1.5 m/s, and the alternative is him creeping up a hill on his back indefinitely.

### 3. Steep ground slides him whether he asked or not

Standing on a floor steeper than `slide_auto_angle` (35 degrees) starts a slide, pointed
straight down the fall line, with no press and no sprint required. He cannot stand back up on
it: while the floor under a slide is that steep, `crouch` is refused and the stall exit is
suppressed. `jump` still leaves - it is the one exit that is never taken away.

The stall exit being suppressed leaves one case to answer: steered *up* a steep face, he runs
out of speed on ground he is not allowed to stand on. He does not stop there and he is not
held there - his heading is re-pointed down the fall line and the bonus is reset, and he
**slips back down**. Holding him would be a trap (`jump` his only way off a face he is
standing still on); ending the slide would restart it one frame later.

The cooldown does not apply to an automatic slide. It exists to stop a player re-entering a
slide on the frame it ends, and refusing this one would only leave him standing on a face he
is supposed to be unable to stand on.

The band is therefore `slide_auto_angle` (35) to `floor_max_angle` (45): shallower is a ramp
he can run up, steeper is not a floor at all. Both ends are dials.

### 4. The speed leaves with him

`_apply_movement()` stops hard-assigning the horizontal velocity in the one case where doing
so throws speed away. When his horizontal speed is **above** what the stick is asking for, it
is not replaced - it is **decayed toward** it:

```
if current > target:  current -> max(target, current - decay * delta)
else:                 stock Real Controller, unchanged
```

steered by `direction` when there is stick input and by his existing heading when there is
none, so a stop happens along his own line rather than snapping to a stick that is not there.
What it costs him depends entirely on the rate, and there are three of those:

- `momentum_decay` (12 m/s^2) on the floor, and only while he is **driving into** the
  momentum. 18 m/s back to a sprint's 8 is 0.8 s.
- `momentum_brake` (60 m/s^2) on the floor the moment he stops asking for the speed: stick
  released, stick pushed across or against his travel, or crouched. From the 20 m/s cap that
  is 0.2 s and 2.8 m of skid before ordinary locomotion has the frame back.
- `air_momentum_decay` (0) off the floor, while he is still driving into it. Nothing takes
  speed off him in the air; a jump out of a fast slide is the payoff the whole feature exists
  for.
- `air_momentum_brake` (40 m/s^2) off the floor the moment he stops asking, on the same three
  triggers as the ground brake. **Added 2026-09-09**, and the one part of this spec written
  after a play rather than before one - see the section below.

The two ground rates are the whole answer to a controller that feels like ice, and they were
**not** in the first build - one rate was, and one play was enough to find it
(2026-09-08: *"pilot9 slides around too much coming to a stop"*). The rule they encode:

> Momentum is speed the player is still asking for. `momentum_decay` is what carrying it
> costs; `momentum_brake` is what giving it up costs, and it is five times as much.

The rate is interpolated across the agreeing half of the dot product between the stick and
his travel and is flat at the brake across the whole disagreeing half - sideways brakes as
hard as fully backwards. A graded answer to "I am pushing away from where I am going" is
exactly the vagueness the complaint was about.

Below the target this is the stock code path untouched, so ordinary walking, running,
sprinting, crouching and stopping are byte-for-byte what they were.

**This also fixes a standing oddity nobody had named.** `_apply_movement()` computes
`is_sprinting` with an `is_on_floor()` term, so an airborne pilot9's `current_speed` is the
plain 5 m/s `speed` - meaning a sprint jump *dropped* him from 8 m/s to 5 the moment he left
the ground. With no air decay he now keeps the 8.

## Dials

All new, all in the inspector, all with the shipping defaults below.

| Property | Default | What it does |
| --- | --- | --- |
| `slide_slope_accel` | 1.0 | Multiplier on the physical gravity term. 1.0 is real physics; 0.0 is the old flat slide. |
| `slide_friction` | 2.0 m/s^2 | How fast slope-gained speed bleeds off. Only ever touches the bonus. |
| `slide_max_speed` | 20.0 m/s | Ceiling on a slide's total horizontal speed. 2.5x sprint. |
| `can_auto_slide` | true | The steep-ground slide, off switch included. |
| `slide_auto_angle` | 35 deg | Steeper than this and he cannot keep his feet. |
| `momentum_decay` | 12.0 m/s^2 | What carrying speed costs on the floor - stick driving into his own travel. |
| `momentum_brake` | 60.0 m/s^2 | What giving it up costs - stick released, across, against, or crouched. |
| `air_momentum_decay` | 0.0 m/s^2 | What carrying speed costs in the air. Zero: no air friction at all. |
| `air_momentum_brake` | 40.0 m/s^2 | What giving it up costs in the air. 0.0 restores the old carry-forever fall. |

`SLIDE_STALL_SPEED` (1.5 m/s) and `FLOOR_SNAP_LENGTH` (0.5 m) are constants, not dials -
neither is a feel decision.

## Why the bonus is a separate scalar

The obvious implementation is to integrate `_slide_hold_speed` itself. It was rejected for a
reason worth writing down: the clip's speed is *measured* off `slide_motion`, and the run-in
and the run-out are the two windows where his feet are planted and a mismatch between the
animation and the floor shows as skate (`pilot9-slide.md`). Keeping the gravity term as a
separate addend leaves those measurements intact and makes the slide on flat ground provably
the same slide - `_apply_slide_velocity()`'s curve arithmetic is not touched at all, and the
seam identity `pilot9-slide-hold.md` proves still holds with the bonus at zero.

It also means one number describes the whole feature: `_slide_bonus` is the metres per second
the *terrain* gave him, and it is the thing to print when this is being tuned.

## What this does not do

- **No slope effect on running.** Only the slide accelerates. Running up a hill is as fast as
  running along a flat, exactly as before.
- **No slope pitch on the model.** Setsuna tips into a grade (`player.gd::_slope_pitch`);
  pilot9 does not, here or before. Worth doing, separately.
- **No wall running, no ground pound, no dive.** The other techs in the overview are their
  own builds.
- **No speed-dependent camera.** The FOV still keys off the sprint toggle only, so a 20 m/s
  slide looks like an 8 m/s one. Likely to want revisiting after a play, and a one-line
  change if so.
- **Nothing for Setsuna.** `player.gd` is untouched.

## Test coverage

`tests/test_pilot9_slope_momentum.gd`. The physics is factored into static, pure functions
precisely so it can be tested without a physics world - `is_on_floor()` cannot be made true
headlessly, which is why the existing slide tests all run with no floor under them:

- `_slope_accel()`: zero on the flat, positive downhill, negative uphill, zero along a
  contour, equal to `g sin cos` at 30 degrees, scaled by `slide_slope_accel`, and safe on a
  degenerate normal.
- `_stepped_bonus()`: gains, decays toward zero, never decays *through* zero, and friction
  and gravity compose.
- `_capped_slide_speed()`: the ceiling and the floor.
- `_decayed_speed()`: over-speed decays at the rate, under-speed is left alone, and the decay
  never undershoots the target.
- `_momentum_rate()`: driving into it pays `momentum_decay`, letting go pays `momentum_brake`,
  across and against both pay the full brake, and a half-agreeing stick pays between the two.
  Plus the feel guard it exists for: a released stick at the speed cap skids under 3 m.
- `_is_auto_slide_slope()`: the angle band, both edges.
- Integration, with no floor: a held slide's speed is still flat, and `_apply_movement()`
  leaves a 20 m/s airborne pilot9 *holding the stick* at 20 m/s instead of assigning him 5.
- The air brake, also through `_apply_movement()`: a released stick bleeds but keeps its own
  heading, a walk off a lip drifts under 0.5 m before the fall is vertical, a held stick still
  pays nothing, a stick across his travel brakes, and `air_momentum_brake` 0.0 restores the
  old behaviour exactly.

## The air brake (2026-09-09)

Everything above was written before the feature was built. This section was written after it
was played, which is why it is the only part of the spec that quotes a complaint:

> *"when pilot9 is falling, pilot falls in a direction instead of falling straight down when
> no direction input is given. i need pilot to be able to fall down long pipes in a straight
> line"*

The rule at the top of this spec - *momentum is speed the player is still asking for* - had
been applied to the floor and only half-applied to the air. On the floor a released stick pays
`momentum_brake`; in the air it paid `air_momentum_decay`, which is 0.0, so it paid **nothing**
and a walk off a lip flew sideways for the whole descent. A vertical shaft is the shape that
makes that unplayable: the drop is only as wide as the pipe, and any horizontal speed at all
puts him in the wall.

Two changes, both in `_apply_movement()`:

1. **The airborne sprint floor now needs a stick behind it.** `target` was
   `max(demanded, min(carried, sprint_speed))` on every airborne frame, so with no stick the
   target was his own current speed and there was nothing for any rate to decay *toward*. It
   is a floor under a *request*; with no request the target is the 0 the stock assignment
   would have written.
2. **The brake became a pair, like the drive rate already was.** `_momentum_rate()` is now fed
   `air_momentum_decay` / `air_momentum_brake` off the floor and `momentum_decay` /
   `momentum_brake` on it, instead of the airborne case collapsing both into one number.

What this does *not* touch is the payoff: a held stick still pays `air_momentum_decay`, still
0.0, so a slide jump driven forward carries every metre per second it earned. The brake is the
answer to letting go, and letting go is what falling down a pipe is.

40 m/s^2 rather than the ground's 60 because the air should read as slightly looser than the
floor, and because 40 is already short enough to be invisible at the speeds a fall starts
from: a released 5 m/s walk-off is over in 0.125 s and 0.31 m, a released 8 m/s sprint in
0.2 s and 0.8 m. The full 20 m/s cap takes 0.5 s and 5 m, which is a slide jump visibly
coasting out rather than stopping in mid-air.

The existing `tests/test_pilot9_slide*.gd` are the regression net for "the flat slide did not
change" and are expected to pass **unmodified**, with one exception:
`test_the_hold_speed_does_not_change` is re-worded, not re-scoped - it asserted flatness *and*
the old reason for it ("no gravity term, by the user's call"), and that reason is what this
spec replaces.
