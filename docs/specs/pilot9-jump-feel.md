# Spec: the jump stops being floaty

> **Status:** built 2026-09-10, height revised to 2.3 m the same day, **unplayed**.
> 409 tests pass headless.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Touches:** `scripts/pilot9.gd` only - `_handle_gravity_and_jump()`, the `Movement`
> export group, two new statics and four new members. No rebuild, no bake, no animation
> change, no new input action, **no change to `project.godot`**.
> **Follows:** `docs/specs/pilot9-real-controller.md`, which set `jump_velocity: 6.0` against
> the stock Godot gravity and never revisited either number.

## Problem statement

Nothing in `project.godot` overrides gravity, so `get_gravity()` in
`_handle_gravity_and_jump()` returns Godot's default **9.8 m/s2** - Earth. Against
`jump_velocity: 6.0` that gives:

| | now |
|---|---|
| Time to apex | **0.61 s** |
| Apex | **1.84 m** |
| Airtime, flat ground | **1.22 s** |
| Apex over his own height (capsule 1.96 m) | 0.94x |

**The height is right and the time is wrong.** Jumping just under your own head is a sane
parkour number, and it is the number `climb_band_min/max` (0.9 - 1.9 m) and every lip in the
map were tuned against. But 1.22 seconds is a *long* time to be a passenger, and a double
jump taken at apex is **2.1 seconds and 3.67 m** - he is airborne for two full seconds.

Real-world gravity is almost never the right game gravity. It was never chosen here; it was
inherited.

There is a second cause, and it is not a number. **Every pilot9 jump is the same jump.** Tap
or hold, he leaves the floor at 6.0 m/s and traces the identical 1.84 m arc. A player with no
authority over the arc experiences the airtime as something happening *to* them, which is
most of what "floaty" actually names.

## The rule

**Specify the jump by what you can see - how high, and how long to the top - and derive the
physics from it.** Height and airtime become independent dials instead of two things fighting
over one gravity constant. This is the reparameterisation from Kyle Pittman's GDC talk
*Math for Game Programmers: Building a Better Jump*, and it is the spine of this pass:

```
jump_velocity = 2 * jump_height / jump_time_to_apex
jump_gravity  = 2 * jump_height / jump_time_to_apex^2
```

Set `jump_height: 1.85` and `jump_time_to_apex: 0.38` and the derived pair is **9.74 m/s off
the floor against 25.6 m/s2 of gravity**. Same apex as today, rise cut from 0.61 s to 0.38 s.
*(The height was revised to 2.3 m the same day - see the revision below. Everything from here
to that section describes the pass as first specced.)*

On top of that spine, four rules:

**1. He falls harder than he rises.** Fall gravity is `jump_fall_multiplier` (1.9) times rise
gravity. Near-universal - Mario, Celeste, Hollow Knight, Ori, Sonic all do some version. The
descent is where float is actually *felt*: a rise reads as commitment, a slow fall reads as
swimming.

**2. Letting go cuts the jump.** While rising with `jump` not held, upward speed is clamped to
`jump_cut` (0.4) of `jump_velocity`. A tap is a hop, a hold is the full arc.

**3. Gravity relaxes at the top.** Inside +/- `jump_apex_speed` (1.5 m/s) of the apex, gravity
is scaled by `jump_apex_scale` (0.6). Celeste's half-gravity trick. It costs ~0.06 s and buys
the part of the arc you actually aim from.

**4. He stops accelerating downward at `max_fall_speed`** (28 m/s), reached 8.1 m into a drop.

And two rules that are not about weight at all but become necessary because of it:

**5. Coyote time** - `coyote_time` (0.1 s) after leaving the floor, a `jump` press still counts
as a floor jump.

**6. Jump buffer** - `jump_buffer_time` (0.1 s) before landing, a `jump` press is remembered and
spent on the touchdown frame.

Those last two are not garnish. Halving the airtime halves the margin on every edge-launch and
every land-into-jump, and forgiveness is what keeps a fast jump from reading as a punishing
one. Celeste ships 0.1 s of each and is not a floaty game.

### What it comes to

| | now | after |
|---|---|---|
| Rise | 0.61 s | **0.39 s** |
| Fall | 0.61 s | **0.28 s** (0.32 s with the apex hang) |
| **Airtime** | **1.22 s** | **0.72 s** |
| Apex | 1.84 m | **1.88 m** |
| Double-jump apex | 3.67 m | **3.76 m** |
| Tap hop | *not possible* | **~0.5 - 1.0 m** |

*(Built 2026-09-10. Integrated through the real functions at 60 Hz, `jump_height: 1.85` gave an
apex of 1.95 m and an airtime of 0.7333 s - discrete Euler and the apex hang both overshoot the
analytic prediction slightly.)*

### Revised 2026-09-10: `jump_height` 1.85 -> 2.3

Asked for more height before the play session, on the numbers alone. The shipping arc is now:

| | value |
|---|---|
| Launch speed | **12.11 m/s** |
| Rise / fall gravity | **31.86 / 60.53 m/s^2** |
| Apex | **2.42 m** |
| Tap hop apex | **0.62 m** |
| Airtime | **0.7333 s** - unchanged |
| Terminal velocity at | **6.8 m** into a drop (was 8.7 m) |

**The airtime did not move, and neither did the gaps.** That is a property of the
reparameterisation rather than a coincidence: rise time is `jump_time_to_apex` by construction
and fall time is `t_apex / sqrt(fall_multiplier)`, and there is no height in either. Raising the
jump buys reach upward and gives back none of the float. `jump_time_to_apex` is the *only*
dial that changes how far a running jump carries.

The one leak is the apex hang. `jump_apex_speed` is an absolute m/s band, so a shorter jump -
which is a weaker gravity - dwells in it longer and picks up more hang: about 50 ms across the
1.0 - 2.3 m range. Harmless here, and fenced by a test that says what to do if it ever stops
being harmless (scale the band off `jump_velocity` instead of dialling it in m/s).

**What is preserved is the clock, and only the clock.** The apex went 1.84 m -> 2.42 m, so
anything deliberately placed just out of jumping reach needs re-checking - the metroidvania
"visible but impossible" routes especially, since 0.6 m of extra reach is exactly the kind of
margin those are authored on.

### What is NOT preserved: horizontal distance

**This was missed when the spec was first written and is the most consequential thing in it.**

Horizontal jump distance is airtime x speed, and nothing else. Cutting the airtime by 40% cuts
every gap he can cross by 40%, at every speed:

| | before | after |
|---|---|---|
| Gap at run (5.0 m/s) | ~6.1 m theoretical, ~5 m usable | **~3.7 m theoretical, ~3 m usable** |
| Gap at sprint (8.0 m/s) | ~9.8 m theoretical, ~7 - 8 m usable | **~5.9 m theoretical, ~4.5 m usable** |

Anything he **crosses** is now 40% out of reach, and any gap already authored against the old
numbers has to be re-measured or he cannot make it. (Anything he **climbs** was unaffected as
this section was first written; the 2.3 m revision above then moved it 0.6 m the other way.)

This is inherent to the change rather than a bug in it - there is no way to halve the airtime
and keep the distance without making him faster horizontally. The three ways out, none of
them taken here:

1. **Re-author the gaps.** Correct, and cheapest while the maps are still blockout.
2. **Raise `sprint_speed`.** Changes the run as well as the jump; a bigger decision than this
   pass.
3. **Air speed above ground speed** - a horizontal kick on the jump frame. New mechanic, new
   spec, and it fights `air_momentum_brake`.

`docs/game-overview.md` carries the corrected numbers.

## Why the gravity is local and `project.godot` is not touched

The obvious move is `physics/3d/default_gravity: 25.6`. It is wrong twice over.

`_apply_slide_bonus()` reads `get_gravity().length()` too (`pilot9.gd:1485`), feeding
`_slope_accel()`. `slide_slope_accel: 1.0` is documented as *"real physics - about 4.9 m/s2
down a 30-degree grade"*, and that number is what the whole slide pass was tuned against.
Raising the project default makes every slide **2.6x steeper** as a side effect of a jump
change.

And EXIA, Setsuna, and every RigidBody in the world share that setting. A pilot's jump is not
grounds for re-weighting the mech.

So: `jump_gravity` is pilot9's own, `_handle_gravity_and_jump()` is its only reader, and
`get_gravity()` survives untouched at line 1485 doing the slide's job.

The cost is real and worth naming: **pilot9 stops honouring `Area3D` gravity overrides.** No
such area exists in the project today. If a low-gravity zone is ever wanted, this is the line
that has to change.

## What changes

### `scripts/pilot9.gd`

`jump_velocity` stops being an export and becomes a derived read-only property. It has no
override in `pilot9.tscn`, and its only reader outside this file is
`tests/test_pilot9_climb.gd:667` through `get()`, which a getter satisfies. The three
`velocity.y = jump_velocity` sites are untouched.

```gdscript
# --- Movement group, replacing `jump_velocity` ---
@export_range(0.2, 5.0, 0.05) var jump_height: float = 1.85
@export_range(0.05, 1.5, 0.01) var jump_time_to_apex: float = 0.38
@export_range(1.0, 4.0, 0.05)  var jump_fall_multiplier: float = 1.9
@export_range(0.0, 1.0, 0.05)  var jump_cut: float = 0.4
@export_range(0.0, 6.0, 0.1)   var jump_apex_speed: float = 1.5
@export_range(0.1, 1.0, 0.05)  var jump_apex_scale: float = 0.6
@export_range(1.0, 100.0, 0.5) var max_fall_speed: float = 28.0
@export_range(0.0, 0.5, 0.01)  var coyote_time: float = 0.1
@export_range(0.0, 0.5, 0.01)  var jump_buffer_time: float = 0.1

var jump_velocity: float:
    get: return 2.0 * jump_height / jump_time_to_apex
var jump_gravity: float:
    get: return 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)

var _coyote_left: float = 0.0
var _jump_buffered: float = 0.0
```

The two rules that are arithmetic are **static functions taking everything they need**, the
way `_slope_accel()` already is, so a `--script` run can drive them without a tree:

```gdscript
## Multiplier on `jump_gravity` for one frame. Rising is 1.0, falling is the fall
## multiplier, and either one is relaxed inside the apex band.
static func _gravity_scale(vy: float, fall_mult: float, apex_speed: float,
        apex_scale: float) -> float:
    var scale := 1.0 if vy > 0.0 else fall_mult
    if absf(vy) < apex_speed:
        scale *= apex_scale
    return scale

## The jump cut. A *state* test on the button, not an edge: a tap whose press and release
## land on the same physics frame still cuts, and no call ordering can eat it.
static func _cut_rise(vy: float, held: bool, cut_speed: float) -> float:
    if held or vy <= cut_speed:
        return vy
    return cut_speed
```

Inside `_handle_gravity_and_jump()`, the airborne/grounded split grows the timers, and the
press handling grows two branches:

- **airborne** - gravity times `_gravity_scale()`, floored at `-max_fall_speed`, then
  `_cut_rise()`; `_coyote_left` and `_jump_buffered` both tick down by `delta`.
- **grounded** - `_air_jumps_left` refills as it does now, `_coyote_left` refills to
  `coyote_time`, and a live `_jump_buffered` is **spent here**, through the same three lines
  as a fresh floor jump (stand up, `_end_slide()`, `velocity.y = jump_velocity`).
- **the press, on the floor or inside coyote** - the existing floor branch, with
  `_coyote_left = 0.0` added.
- **the press, airborne with an air jump left** - unchanged, plus `_coyote_left = 0.0`.
- **the press, airborne with none left** - `_jump_buffered = jump_buffer_time`.

`_coyote_left = 0.0` on *every* jump taken is the load-bearing line. Without it the 0.1 s of
coyote outlives the floor jump that used it, and a second press 80 ms later takes a free
second jump that never touches `_air_jumps_left`.

The buffer arms **only** when there is no air jump to spend. With `air_jumps: 1` that reads
as: first press leaves the floor, second press is the double jump, third press near the
ground waits for it. The air jump is always the more immediate answer and always wins.

`frozen` and the mantle entry both clear `_jump_buffered` and zero `_coyote_left`, matching
what `_slide_buffered` already does on a freeze.

### `docs/game-overview.md`

Line 77 of the stats table (`Jump apex | 1.84 m | jump_velocity: 6.0`) is now wrong in both
columns.

## Decisions

| | Taken | Over |
|---|---|---|
| How the jump is specified | **Height + time to apex**, physics derived | Tuning `jump_velocity` against a gravity nobody chose. The two dials then fight. |
| Where gravity lives | **On pilot9** | `project.godot`, which is also the slide's gravity and the mech's. |
| Fall multiplier | **1.9x** | Symmetric gravity. The descent is where float is felt. |
| Jump cut | **Velocity clamp** at 0.4x | Extra gravity while rising unheld - smoother, but there is no room for smooth inside a 0.39 s rise. |
| Cut tested as | **Button state** | `is_action_just_released()`, which a same-frame tap and the call ordering can both defeat. |
| Apex band | **1.5 m/s at 0.6** | Celeste's 0.5. At our weights the wider band gives back 0.15 s of the 0.5 s we just saved. |
| Mantle-exit jump | **Obeys the cut** | A `_jump_cut_exempt` flag. One rule, no extra state - see risk 1. |
| Buffer vs air jump | **Air jump wins** | Buffering a press that has a double jump available, which would swallow it. |
| Coyote after an air jump | **None** | Coyote is the floor's grace. He left the floor a while ago. |
| Keeping `jump_velocity` | **As a derived property** | Deleting it and rewriting three assignment sites and a climb test. |

## Risks

1. **The mantle-exit jump can come out short.** `_climb_jump_buffered` holds a press made
   during an uncancellable mantle; if the player let go before the exit, the cut fires and
   they get a 0.5 m hop off a press they thought they had banked. The fix if QA hits it is a
   one-frame cut exemption on that path, deliberately not built yet.
2. **`air_momentum_brake` is about to do half as much.** It is 40 m/s2 of horizontal braking
   and airtime is dropping from 1.22 s to 0.72 s, so a stickless fall drifts further before
   touchdown than it does today. **Unchanged in this pass on purpose** - it is a tuned number
   the jump has no business editing blind. First thing to watch in play; 55 - 60 is the guess
   if it needs one.
3. **The animation may not keep up.** Transitions into `fall` carry 0.2 - 0.3 s crossfades
   (`pilot9_build_scene.gd:437`, `:668`). Against a 0.39 s rise the jump clip barely
   establishes before it starts blending away. Cosmetic, unfixable headlessly, and only a
   play session can say whether it reads as a jump or a twitch.
4. **A buffered jump and a buffered slide can land on the same frame.**
   `_handle_crouch_and_slide()` runs first, so the slide starts and the jump immediately
   `_end_slide()`s it - burning the 0.4 s cooldown on a slide nobody saw. The ordering is
   pre-existing and deliberate (`pilot9.gd:701`); the jump buffer just makes it reachable
   without frame-perfect input.
5. **0.73 s is a guess with arithmetic behind it, not a felt number.** Every dial here is an
   export for exactly that reason.
6. **`max_fall_speed: 28` now bites 6.8 m into a drop rather than 8.7 m**, because the
   2.3 m jump raised the fall gravity to 60.5 m/s^2. The map has lips at 8.6 m and 13.3 m, so
   more of its real drops are now spent at a constant speed - which is the one place the fall
   stops gaining weight. **Unchanged on purpose**, same argument as `air_momentum_brake`; 34
   would restore the old 8.7 m threshold if a long drop reads as floaty at the bottom.
7. **Every authored gap is now 40% too wide** - see the section above. The single biggest
   consequence of this pass and the one most likely to look like a bug in play: a jump that
   used to clear something no longer does, and nothing about the jump *feels* wrong when it
   happens.

## What this does not do

- **No change to `project.godot`**, so the slide's slope gravity, EXIA and every RigidBody
  are untouched.
- **No change to the slide, the crouch, the sprint, the FOV, the mantle geometry or the
  camera.**
- **No change to horizontal air control.** `air_momentum_decay` stays 0.0 and
  `air_momentum_brake` stays 40.0 - see risk 2.
- **No change to `air_jumps`**, the `air_jumped` signal, or the animation tree.
- **No new input action.** Coyote, the buffer and the cut all read the existing `jump`.
- **Nothing for Setsuna.** `scripts/player.gd` is untouched.

## Test coverage

`tests/test_pilot9_jump_feel.gd`. The two statics carry most of it:

- `_gravity_scale()`: rising is 1.0, falling is the multiplier, both are scaled inside the
  apex band, and the band is symmetric about zero
- `_gravity_scale()` at `apex_scale: 1.0` and `apex_speed: 0.0` reduces to plain asymmetric
  gravity - the hang is switch-off-able
- `_cut_rise()`: held is a no-op, released above the cut speed clamps, released below it is a
  no-op, and a falling velocity is never touched
- the derived pair: `jump_velocity` and `jump_gravity` reproduce `jump_height` and
  `jump_time_to_apex` when run back through `v^2/2g` and `v/g`
- the shipping numbers, as a regression fence: apex within 1 cm of 1.88 m and airtime within
  10 ms of 0.72 s, integrated frame by frame at 60 Hz through the real functions
- `max_fall_speed` clamps a long integrated fall and does not clamp a short one
- the timers, driven directly: `_coyote_left` decrements airborne and refills grounded;
  `_jump_buffered` decrements and lapses; a jump zeroes `_coyote_left`
- the buffer arms only with `_air_jumps_left == 0`, as a source assertion, because `Input`
  cannot be driven from a `--script` run - the way `test_pilot9_sprint_fov.gd` asserts
  placement
- `get_gravity()` still appears at the slide's call site and no longer appears in
  `_handle_gravity_and_jump()`, as a source assertion - this is the whole "don't break the
  slide" claim and it is worth a test

**Whether 0.72 s feels right is QA, and so is every other word in this document.** The tests
fence the arithmetic and the wiring; they say nothing about weight.
