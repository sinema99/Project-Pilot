# Spec: pilot9's wall-run

> **Status:** specified 2026-09-19, built 2026-09-21, **cleanup pass specified and built
> 2026-09-23; every pass played 2026-09-28 - feels good.** The cleanup pass is a Titanfall-fidelity rewrite of the attach, the wall-jump and the
> bound - see *Cleanup pass, 2026-09-23* at the bottom for exactly what changed and why. Every
> number is a starting guess exposed as an `@export_range`.
> **Scene:** `scenes/pilot9.tscn`. Tested in `scenes/trial.tscn`.
> **Character:** `assets/pilot9.glb` - `P_wall-runR` (wired 2026-09-21, **retired 2026-09-26**:
> the run plays the ground `sprint_forward` cycle leaned 30° off the wall - see *Sprint cycle on
> the wall, 2026-09-26*, specced and built that day, played 2026-09-28).
> **Reference:** Titanfall 2, named by the user as the target feel - **"as close to Titanfall as
> possible"** (2026-09-23), wherever that does not break the grid.
> **Touches:** `docs/specs/pilot9-jump-grid.md` (the wall-run gets a grid of its own, measured
> against that one), `docs/specs/pilot9-dash.md` (the two air verbs), `docs/specs/pilot9-climb.md`
> (the mantle handoff), `docs/specs/pilot9-movement-reset.md` (why nothing global is retuned).

## Problem statement

`docs/game-overview.md` promises four movement techs. Double jump and air dash are built.
Wall-run was chosen over rail grind as the cheaper of the remaining two: every wall already
qualifies, detection is two rays, and there is no level pipeline to build.

The first build (2026-09-21) played badly in two ways, reported 2026-09-23:

1. **Attaching is clunky.** Grabbing a wall mid-jump zeroes `velocity.y`, so his jump stops
   dead mid-rise and he is welded flat.
2. **He cannot jump off the wall.** The wall-jump was built, but two things undo it within a
   frame: he **instantly re-grabs the wall he just left** (after one frame of a 3.5 m/s kick he
   is ~6 cm off the face, well inside the 0.8 m probe, and his travel still passes the attach
   angle), and **the stick overwrites the kick** (`_apply_movement()` assigns air heading
   straight from the stick, so holding forward along the wall erases the push-off).

The user wants wall-to-wall: jump from a left wall to a right wall and back, down a corridor.

## The rule

**Airborne, moving along a near-vertical face, he sticks to it and runs at sprint speed -
finishing the jump he was on, then level, then drooping, for about three seconds.** Jump kicks
him off toward the opposite wall of a 6 m corridor. He can chain walls without limit; **each
chained wall-jump is half the height of the last**, and only the ground resets it.

Horizontal traverse only. No vertical up-run: it overlaps the mantle, which already reaches a
lip at 4.9 m off a single jump and 7.9 m off a double.

## The grid

pilot9's jump is *chosen*, in whole metres (`docs/specs/pilot9-jump-grid.md`). The wall-run gets
two numbers of its own.

**Along a wall: 15 m.** Every wall-run is brought up to `wall_run_speed` (7.5 m/s, sprint) and
held there for `wall_run_flat_time` (2.0 s). His entry speed no longer matters - a jog-speed
catch is lifted to a sprint by the wall itself, which is the Titanfall feeling, and a fast one is
not added to. `wall_run_distance()` is therefore one number:

| | |
|---|---|
| any entry | 7.5 m/s × 2.0 s = **15 m** |

(The old 10 m run-speed row is gone. The dash still clamps to `sprint_speed` on exit, so a dash
into a wall-run is still **25 m**.)

**Across a corridor: 6 m.** One wall-jump crosses a 6 m wall-to-wall gap and arrives at the
far wall at the top of its jump, 0.6 s after leaving - see *The wall-jump*. 6 m sits on the jump
grid's own 3 / 6 / 9.

> **9 m is the widest gap without wall-run. 15 m of wall, then a 9 m sprint jump, is 24 m. A
> 6 m corridor can be chained forever.**

## Rise, then flat, then droop

**The user's call: keep the grid.** The vertical has three phases, and the clock
(`_wall_run_time`) starts at attach for all of them:

1. **Rise.** If he is rising at attach, **his `velocity.y` is kept** and falls under his normal
   jump gravity (`jump_gravity`, through `_gravity_scale()`, exactly as any jump). He finishes
   the arc he was on and levels at its apex. A jump pressed beside a wall reaches its full 3 m
   and then runs; a grab mid-jump carries on to wherever that jump would have peaked. **This
   costs no height**: he never goes above the apex of a jump he already took.
2. **Flat.** Once `velocity.y` reaches zero - or at attach, if he was **falling** (the fall is
   caught) - `velocity.y` is held at 0 until `_wall_run_time` reaches `wall_run_flat_time`.
3. **Droop.** Past `wall_run_flat_time`, a fraction of `jump_gravity`: `wall_run_droop_gravity`
   0.35 over the 0.8 s tail is ~1.9 m. The droop is information - the player sees the run
   ending instead of being dropped by a clock.

The rise spends some of the flat clock. It does not touch the grid: horizontal speed is 7.5 m/s
throughout, so 2.0 s is 15 m whether it was spent rising or level.

A rise that is still going when the flat clock runs out keeps its own gravity rather than
switching to the droop - it is already coming down faster than the droop would take it.

## The numbers

All `@export_range` on `pilot9.gd`.

| Knob | Start | |
|---|---|---|
| `can_wall_run` | `true` | |
| `wall_run_speed` | **7.5 m/s** | **New.** The floor every wall-run is brought up to. Sprint speed, so the grid is 15 m |
| `wall_run_speed_ramp` | **0.25 s** | **New.** How long a slow catch takes to reach `wall_run_speed` |
| `wall_run_flat_time` | 2.0 s | Unchanged. Makes 15 m |
| `wall_run_droop_time` | 0.8 s | Unchanged |
| `wall_run_droop_gravity` | 0.35 | Unchanged |
| `wall_run_min_speed` | 4.0 m/s | Unchanged. Still the anti-drift gate - the floor lifts a *run*, not a drift |
| `wall_run_wall_angle` | 15° | Unchanged |
| `wall_run_attach_angle` | 60° | Unchanged |
| `wall_run_head_on_angle` | 30° | Unchanged |
| `wall_run_detach_angle` | 45° | Unchanged |
| `wall_run_probe_reach` | 0.8 m | Unchanged |
| `wall_jump_kick` | **8.5 m/s** | Was 3.5. Crosses a 6 m corridor by the apex - see *The wall-jump* |
| `wall_jump_chain_decay` | **0.5** | **New.** Replaces `wall_runs_per_flight`. Each chained wall-jump's *height* is this times the last's - see *The bound* |
| `wall_jump_steer_back_ramp` | **0.4 s** | **New.** How long pulling back toward the wall just left takes to win - see *Air control after a wall-jump* |
| `wall_jump_coyote_time` | **0.15 s** | **New.** See *Wall coyote* |
| `wall_run_camera_roll` | 12° | Unchanged |

**`wall_runs_per_flight` is deleted.** Nothing replaces it as a count.

## Attach and detach

**Attach is automatic.** Every gamepad face button is taken, and the mantle set the precedent.

The gates:

1. **Airborne.**
2. **`_horizontal_speed()` ≥ `wall_run_min_speed`.**
3. **The face is near-vertical** - normal within `wall_run_wall_angle` of horizontal.
4. **Travelling along the face, not into it** - `|theta − 90°| ≤ wall_run_attach_angle`, theta
   between travel and the normal.
5. **Not moving away from the face** - `travel · normal ≤ 0`. **New, and it is the re-grab
   fix.** Straight off a wall-jump his travel is ~41° off the normal it just left, which passes
   gate 4; this is what refuses it. It is **not** a lockout: the 180 back onto the same wall
   still attaches, because turning back means moving toward it. (Replaces the old budget gate.)
6. **Not dashing.**

The camera-redirected head-on attach (below) keeps its own gate set: 1, 2, 3, 6, and its own
angle test. It cannot be moving away from a wall it is running dead into, so it needs no gate 5.

**Entry.** `_start_wall_run()` stores the normal, takes the tangent (travel projected onto the
wall plane), and **keeps only the along-wall part of his speed**. The component into the wall
is dropped - otherwise arriving off a wall-jump at 7.5 along + 8.5 in would start the next run
at 11.3 m/s, and chains would snowball. That along-wall speed then ramps to `wall_run_speed`
over `wall_run_speed_ramp` if it is below it; if it is above (it cannot be off a dash, which
clamps to sprint), it is held.

`velocity.y` is **not** zeroed at attach if positive - see *Rise, then flat, then droop*.

Detach, five ways:

| Trigger | Result | Wall coyote? |
|---|---|---|
| Timer expires (`flat + droop`) | Falls normally | Yes |
| **Jump** | The wall-jump | No - he already jumped |
| **The wall ends** (probe finds nothing) | Detaches keeping all velocity - the free launch off the end of a wall | Yes |
| **Stick past `wall_run_detach_angle` off the face** | Lets go | Yes |
| **Crouch** | **Lets go. New - it was swallowed.** Titanfall's drop-off, and the one players reach for; stick-away is fiddly with the camera rolled. The press is **consumed**: it does not also arm a slide or a landing crouch | Yes |

Dash and mantle also end a run (see below) and do not open the coyote window.

The attach and detach angles stay deliberately different numbers. **Do not collapse them.**
Neutral stick keeps him attached.

## Camera-redirected head-on attach

Added 2026-09-19. Running straight at a wall has no tangent in his own travel, and
`_probe_wall()`'s sideways rays skim the face. A forward ray (`_probe_wall_ahead()`) catches the
wall; within `wall_run_head_on_angle` of dead-on, `_camera_wall_run_tangent()` projects the
camera's look direction onto the wall plane and that becomes the run direction. Look right, run
right. Looking dead into the wall too gives no redirect, and he hits it.

Unchanged by the cleanup pass except that `_wall_run_head_on_gates()` loses its budget argument.

## The wall-jump

| Component | Value |
|---|---|
| Vertical | `jump_velocity` scaled for the chain - **3.0 m on the first**, see *The bound* |
| Along-wall | Preserved - whatever the run was carrying (7.5 m/s) |
| Away-from-wall | **`wall_jump_kick`, 8.5 m/s** along the stored normal |

**The launch is fixed**, not aimed by the stick (the user's call). ~49° off the face at 7.5 m/s
along it. Expressiveness comes from steering after the launch, not at it.

**Why 8.5.** His jump is `jump_velocity` 10 m/s up under `jump_gravity` 16.7 m/s², apex at
0.6 s. For the chain to feel good he reaches the far wall **still rising or at the apex**, so
*Rise, then flat* carries him into a level run rather than slapping him into the wall on the
way down. His capsule and the 0.8 m probe remove ~1 m of the 6 m gap; ~5 m in 0.6 s is 8.5 m/s.
Arriving at ~49° off the new face passes gate 4's 60°.

## Air control after a wall-jump

Today the stick owns his air heading outright (`velocity.x = heading.x * kept`), so a stick held
forward along the corridor erases the kick the next frame. A plain ramp back to that does not
fix it - a stick held along the wall has no away-from-wall component, so ramping toward it
bleeds the 8.5 m/s to zero and he drifts ~1.7 m and never arrives. So the rule is:

**The push survives unless you pull against it.** For the wall-jump's flight, his velocity is
split against the normal he left (`_wall_jump_normal`):

- **Along the wall:** the stick has **full authority immediately**, through the ordinary air
  movement. Speed up, slow down, curve with the corridor.
- **Away from the wall:** held at `wall_jump_kick`, **unless the stick points back toward the
  wall he left** (stick · normal < 0). Only then does the stick take it over, blending from 0 to
  full authority across `wall_jump_steer_back_ramp` (0.4 s) of pulling back. That is the
  deliberate 180 onto the same wall, and it still lands.
- Holding forward, holding along the wall, or letting go all cross the 6 m corridor as designed.

The protection ends when he **attaches to a wall, lands, dashes, or after `jump_air_time`
(1.2 s)**. Then he is back to ordinary air control.

## Wall coyote

For `wall_jump_coyote_time` (0.15 s) after any detach except a wall-jump, a dash or a mantle,
**jump is a wall-jump** off the stored normal, counted in the chain decay, and **it does not
spend the double jump.** Running off the end of a wall and pressing a beat late is the most
common input at chain speed, and without this it silently becomes a double jump (or nothing).

The cost, taken knowingly: inside that 0.15 s, jump cannot mean "double jump straight up".
Same shape as the ground's own `coyote_time`.

## The bound

**The double jump is refilled only by the ground.** Titanfall refills it on the wall; here that
makes every corridor an elevator (+3 m per touch, forever). Unchanged.

**The old bound was a count** (`wall_runs_per_flight` = 2), and in a 6 m corridor that is wall
A, jump, wall B, jump, fall - not Titanfall. **The new bound is on height, not on walls.**

**Wall-runs are unlimited. Each chained wall-jump's height is `wall_jump_chain_decay` (0.5) times
the one before**: 3, 1.5, 0.75, 0.375 m... reset to full on every grounded frame, beside
`_air_jumps_left`. Height is `v²/2g`, so the launch speed is `jump_velocity * sqrt(decay^n)`,
`n` being wall-jumps already taken this flight (`_wall_jumps_taken`).

The series sums to **3 / (1 − 0.5) = 6 m** - exactly the ceiling the old spec promised
maps, **"wall-run contributes at most +6 m of vertical per flight"**. It still holds, and it now
holds with no limit on walls. Every hop's climb is at most its own jump height, because
*Rise, then flat* never takes him above an apex he did not already earn.

What it plays like in a 6 m corridor: hop 1 arrives at its apex (+3 m); hop 2 (1.5 m, 7.1 m/s)
peaks at 0.42 s and arrives falling, caught ~1.2 m up; hop 3 arrives level; from hop 4 on each
arrives a little lower than it left. **A long canyon run slowly sinks** - you keep going by
travelling, not by climbing, which is the Titanfall rhythm.

The 180 onto the same wall is a chained hop like any other and decays the same way. The wall
coyote's jump counts too.

## The mantle handoff

**Superseded 2026-09-23** - see *Mantle vs wall-run* at the bottom. The original text: the
travel-aimed probe cannot misfire sideways during a run, still sees an inside corner ahead of
him, and a second ray along `-_wall_normal` lets him mantle onto the top of the wall he is on.
A mantle ends the run and does not open the wall coyote.

## The dash

Unchanged.

| Case | Behaviour |
|---|---|
| Dash pressed mid-wall-run | Dash wins; the run ends, no wall coyote |
| Wall-run attempted during a dash | Refused (gate 6) |
| Dash ends against a wall | No wall-run - velocity was into the face (gate 4) |
| Dash ends alongside a wall, still fast | Wall-run may start - the 25 m traverse |

A dash also ends the wall-jump's push protection.

## The animation

`P_wall-runR` is a real run cycle (2026-09-21 re-export), wired as `wall_run` by
`_ensure_wall_run_state()` in `scripts/pilot9_build_scene.gd`; the tree picks it off
`is_wall_running`. The mesh roll was removed 2026-09-23 - the clip poses him on the wall.
Only a right-side clip exists: a left wall mirrors `character/Armature` via
`_mirror_model_for_wall_run()` (`scale.x = -1`), latched at attach from `_wall_on_right_of()`,
snapped rather than eased, restored by `_end_wall_run()`. A real `wall_run_l` would replace it.

The wall-jump plays the ordinary jump clip off `is_jumping`. Nothing new.

## The camera

`wall_run_camera_roll`, 12°, toward the wall, eased at `camera_transition_speed`. In a chain the
roll swings from one side to the other through level on each hop; at 8.0 that is ~0.3 s of
swing inside a 0.6 s hop, which should read as one motion. **Watch for it in play** - if it
lurches, the roll wants its own faster ease during a chain. Not pre-solved.

Known risk, unchanged: on a concave corner `_camera_obstruction_length()` may shorten the arm
against the wall he is on while the camera rolls.

## The UI

Unchanged: `WALL-RUN` is a `BASE_KIT` row bound to `can_wall_run`; `TECH` holds rail grind only.

## Shape of the code

State, beside the dash's and the slide's:

```gdscript
var is_wall_running: bool
var _wall_normal: Vector3
var _wall_run_time: float
var _wall_run_direction: Vector3
var _wall_run_speed: float        # ramps to wall_run_speed, see _start_wall_run()
var _wall_run_leveled: bool       # NEW - rise finished; flat hold owns velocity.y from here
var _wall_jumps_taken: int        # NEW - replaces _wall_runs_left; zeroed on the ground
var _wall_jump_normal: Vector3
var _wall_jump_buffered: bool
var _wall_jump_push_time: float   # NEW - seconds left of push protection, 0 = none
var _wall_jump_steer_back: float  # NEW - seconds the stick has pulled back toward the wall
var _wall_coyote_left: float      # NEW - seconds of wall coyote left
```

| Function | Change |
|---|---|
| `_wall_run_gates()` | Budget argument replaced by the away-from-face test (gate 5). Still static and pure |
| `_wall_run_head_on_gates()` | Budget argument dropped |
| `_start_wall_run()` | Keeps only the along-wall speed; does not zero a rising `velocity.y`; no budget spend |
| `_apply_wall_run_velocity(delta)` | Now takes `delta`. Speed ramp, then rise / flat / droop |
| `_handle_wall_run()` | Crouch detach; opens the wall coyote on the qualifying exits |
| `_take_wall_jump()` | Chain-scaled vertical, 8.5 kick, starts push protection, increments `_wall_jumps_taken` |
| `_apply_movement()` | While push protection is live, re-imposes the away-from-wall component after the ordinary air step - see *Air control after a wall-jump* |
| `_handle_gravity_and_jump()` | Wall coyote takes the press ahead of the air jump; ground resets `_wall_jumps_taken` |
| `_handle_crouch_and_slide()` | While wall-running, crouch ends the run instead of being swallowed, and the press is consumed |
| `wall_jump_height_for(n, height, decay)` | **New, static, pure.** The chain's nth height |
| `wall_jump_chain_ceiling(height, decay)` | **New, static, pure.** `height / (1 - decay)` - the +6 m |
| `wall_run_distance()` | Now `wall_run_speed * wall_run_flat_time`, no speed argument |

Frame order unchanged: `_handle_wall_run()` after `_handle_dash()`, before
`_handle_gravity_and_jump()`.

## Tests

`tests/test_pilot9_wall_run.gd`, headless. Replaces the budget tests; keeps the rest.

- **The grid.** `wall_run_distance() == 15.0`.
- **The gates**, pure: every one of the six, and specifically **gate 5 refuses travel ~41° off
  the normal moving away** (the re-grab case) while **gate 4 alone would have accepted it** -
  the regression that eats the jump.
- **The 180 still attaches:** travel back toward the same normal passes.
- **The corridor.** With the shipping jump, 8.5 m/s kick and ~1 m of capsule-plus-probe, a
  wall-jump covers the 6 m gap by `jump_time_to_apex`.
- **The chain.** `wall_jump_height_for()` gives 3, 1.5, 0.75; `wall_jump_chain_ceiling()` is
  **6.0**, and the first 20 heights sum under it. This is the assertion that protects the maps;
  if someone sets the decay to 1.0, this is what fails and says why.
- **The speed floor.** A slow entry ramps to `wall_run_speed`; the into-wall component of an
  arrival does not carry into the run speed.
- **`can_wall_run = false`** refuses every entry. The mirror and side tests stay.

Push protection, the rise and the wall coyote need a running frame and real collision; they are
checked in play, not headless.

## Test geometry

`scenes/trial.tscn`'s `Blockout`. Add **two 20 × 6 × 1 walls, 6 m apart face to face** - the
chain test - beside the existing wall-run geometry. A wall with its top at 2.5 m is the
mantle-handoff test.

## Deferred

- **Double jump refilled on the wall.** Titanfall's rule; rejected here because it is an
  elevator. Reopening it means re-deriving the ceiling.
- **Aimed wall-jump launch** (stick picks the angle). Considered, rejected for the fixed launch
  - it makes the 6 m corridor a promise only at one angle.
- **The camera roll swing during chains** - see *The camera*.
- **The concave-corner camera lurch.**
- **Curved and faceted walls.**
- **The camera roll as a settings slider.**
- **Vertical wall-run.** Cut, not merely unbuilt.

## Cleanup pass, 2026-09-23

Decided in a grilling session with the user, target "as close to Titanfall as possible":

| # | Was | Now |
|---|---|---|
| 1 | Attach zeroes `velocity.y` - dead stop mid-jump | Rise under jump gravity to the apex, then flat, then droop. Falls still caught |
| 2 | Entry speed preserved (10 / 15 m grid) | Floor to 7.5 m/s over 0.25 s; along-wall part only. Always 15 m |
| 3 | Re-grabs the wall just left | Gate 5: never attach to a face he is moving away from |
| 4 | Kick 3.5 m/s (~3 m gap) | 8.5 m/s, 6 m corridor, fixed launch angle |
| 5 | Stick erases the kick next frame | Push survives unless pulled against; pull-back ramps over 0.4 s; ends on attach / land / dash / 1.2 s |
| 6 | 2 wall-runs per flight | Unlimited; wall-jump height ×0.5 per chain; +6 m ceiling unchanged |
| 7 | Late jump off a wall's end = double jump | 0.15 s wall coyote, does not spend the double jump |
| 8 | Crouch swallowed | Crouch drops him off; press consumed |

Order: spec (this), build, **the user plays it**, worklog.

### Built, 2026-09-23

All eight rows above, as written, plus one thing the spec did not have:

**The let-go lockout.** Gate 5 refuses a face he is moving *away* from, but a crouch drop-off
or a timed-out run leaves him still travelling *along* the face - so every gate passes and he
re-grabs the same wall the very next frame (the old per-flight budget used to hide this).
So the let-go detaches - timer, crouch, stick-away, wall end - lock out that one face
(`_wall_lockout_normal` / `_wall_lockout_point`, compared as a plane by `_same_wall()`). The
lock clears on a wall-jump (including the wall coyote's), on attaching any other face, and on
the ground. The deliberate 180 after a wall-jump is unaffected.

Other notes from the build:

- Crouch is read in `_handle_wall_run()`, not `_handle_crouch_and_slide()`; the latter still
  returns early while wall-running, which is what consumes the press.
- The push protection strips the away-from-wall component *before* the ordinary air step and
  puts it back after - otherwise the step reads the kick as carried speed and folds it into
  his along-wall heading (~11 m/s along the corridor instead of 7.5).
- The mantle entry also closes the wall coyote and the push.
- **Stale elsewhere:** the jump grid platform (`scripts/jump_grid.gd`,
  `docs/specs/pilot9-jump-grid-platform.md`) still builds a RUN wall-run rung at
  `speed × flat_time` = 10 m. Every run is 15 m now, so that rung measures nothing real. Left
  as-is (it goes through the static `wall_run_distance_for()`); it wants its own pass.
- Test geometry: `scenes/trial.tscn` → `WallRunTest` - two 20 × 6 × 1 walls with faces 6 m
  apart at x −79.5..−59.5, z 14..20, and a 10 m wall with its top at 2.5 m at x −50, z 17.

## Mantle vs wall-run, 2026-09-23

User report after the cleanup pass: *"mantling and wall run are fighting each other."*

### Why they fought

1. **The top of the wall he is on steals every low run.** The mantle is automatic and its
   `-_wall_normal` ray fires every wall-running frame. The band is 0.9-1.9 m of lip over his
   feet, so on any wall under ~5 m the lip enters the band during the rise and the run is
   converted into a mantle the player never asked for. The 2.5 m `WallRunTest` wall cannot be
   run at all.
2. **Sometimes it does, sometimes it doesn't.** That ray is `climb_probe_reach` (0.6 m) long,
   but a run holds him wherever he attached, up to `wall_run_probe_reach` (0.8 m) out. Close
   attaches mantle, far ones do not - on the same wall.
3. **The "ahead" probe is aimed along his mesh, not his run.** During a run the mesh turns
   toward the stick, so steering even slightly into the wall swings that ray onto the face he
   is running on - a second route to (1).
4. **Head-on at a reachable ledge, the wall-run grabs first.** `_handle_wall_run()` runs ahead
   of the mantle probe, so the camera-redirected head-on attach (or an angled attach at a
   short wall) starts a run, mirrors the model, and the mantle rips him off it a frame later.

### How other games split it

- **Apex Legends / Titanfall 2** (same movement lineage): a mantle needs forward input into
  the wall; the pull finishes even if forward is released. Running *along* a wall never
  mantles by itself - you steer into it.
- **The general rule** (Mirror's Edge, Apex, Titanfall): the approach decides. Into a ledge
  you can reach = mantle. Along a wall = wall-run. Once running, a mantle is an *intent*, not
  a proximity accident.

### The rule, ours

| # | Situation | Result |
|---|---|---|
| 1 | Airborne, not running, a ledge in range along his facing | Mantle, **before** any wall-run attach is considered (priority flipped) |
| 2 | Wall-running, a ledge ahead **along the run** (inside corner) | Mantle - it is head-on to that wall |
| 3 | Wall-running, stick steered **into** the wall (the into-wall half of the existing `wall_run_detach_angle` cone) and the top of this wall is in the band | Mantle onto it |
| 4 | Wall-running, stick into the wall, no ledge in range | Still rising on the attach jump: **held** - the run keeps him, the mesh does not turn into the face, and (3) takes the lip the frame the rise carries it into the band (2026-09-24). Levelled: the stick detach lets go (and the normal airborne mantle can still catch the lip once he is facing it) |
| 5 | Wall-running, stick along the wall | Never mantles. Runs the full 15 m on a 2.5 m wall |
| 6 | Crouch pressed on the frame of (3) | Drop-off wins; no mantle |

The run-top ray uses `max(climb_probe_reach, wall_run_probe_reach)` so it reaches every
distance a run can hold him at. No new dials: (3)'s cone is `wall_run_detach_angle`.

Shape of the code: the mantle trigger moves out of `_handle_gravity_and_jump()` into its own
`_handle_mantle_trigger()`, called in `_physics_process()` after the dash and **before**
`_handle_wall_run()`. The grace clearing (`_coyote_left`, `_jump_buffered`) moves into
`_start_climb()`. A `jump` on the entry frame is still buffered for the exit, as before.

Checked headlessly: the pure intent test (`_steers_into_wall()`), and source order. Checked in
play only: everything that needs a real wall - the 2.5 m wall now runs, steering in mantles.

## Facing locked to the wall, 2026-09-24

User ask: once a run starts, he stays parallel to the wall - moving the camera must not rotate
him on it. The mesh used to lerp toward the camera-relative stick like any other airborne
frame, so a camera nudge swung him off the face.

- For the whole run the mesh yaw is **welded** to `_wall_run_direction` (fixed at attach, the
  heading the velocity already runs along) - the same weld the slide and the climb use. No
  lerp, so any off-parallel facing at attach snaps flat on the attach frame.
- It ignores the stick entirely, including a centred stick and a stick into the wall (row 4
  of "The rule, ours" - that exception is now covered by the weld).
- First person is unaffected (the rotation function already returns early there).
- Ends with the run: on detach, wall-jump or mantle, normal turn-to-face takes over again.

## No wall-run at the top of a wall, 2026-09-24

> **Sideways half superseded 2026-09-24** by *Staying on the wall* (1): the refusal now applies
> to the head-on attach only.

User ask: you cannot wall-run at the top of a wall, so the mantle has a clean activation
point and the two stop fighting.

- **Rule:** a wall-run attach (sideways or camera-redirected head-on) is refused whenever a
  mantle could take this wall's lip from where he is: `_probe_ledge()` aimed into the face,
  at the run-top reach `max(climb_probe_reach, wall_run_probe_reach)`. Same band, same
  headroom test, as the mantle, so "reachable top" means one thing everywhere. No new dials.
- **What happens instead:** nothing forced. He stays airborne beside the wall; the ordinary
  airborne mantle takes the lip the moment he faces it (stick into the wall turns him).
- **Supersedes row 5** of "The rule, ours" for short walls: a 2.5 m wall caught with its top in
  the band is now a mantle, not a 15 m run. A run caught *below* the band on a taller wall is
  unchanged - rows 2-4 still govern a top that the rise carries into the band mid-run.
- `can_climb = false` switches the gate off (no mantle, so nothing to reserve the top for).

## Staying on the wall, 2026-09-24

User report after playing: **"it keeps dropping me mid-run."** Four causes found in the code,
each able to end or refuse a run without the player asking. All four fixed together; the user
chose all four. Target unchanged - Titanfall, grid wins.

| # | Was | Now |
|---|---|---|
| 1 | A sideways attach is refused whenever the wall's top is in the mantle band - on any wall under ~5 m the top third of the jump arc is dead, and running along the wall he is not facing it, so the mantle does not fire either: nothing happens | The top-of-wall refusal applies to the **head-on attach only**. Alongside a short wall he runs; steering in (row 3 of *The rule, ours*) takes the lip |
| 2 | The stick detach reads the camera-relative stick - holding forward while looking >45° off the run (at the next wall, say) lets go | The stick is read in the **run's frame**: forward is along the run whatever the camera does. Only a deliberate strafe away lets go |
| 3 | Every let-go locks that wall out until the ground - one accidental drop and the wall is gone | Lockout by cause: timer and crouch as now, stick let-go for 0.3 s, wall ended none |
| 4 | Nothing holds him to the wall: he runs a fixed tangent at whatever distance he attached (up to 0.46 m off the face), and one torso ray must keep hitting - a seam, a slight angle, a window, or rising past a short wall's top ends the run | A pull holds him at a fixed distance; the run follows gentle turns in the face; a second, low ray keeps the run alive where the torso ray finds a gap |

### 1. Short walls run

- `_wall_top_in_mantle_reach()` is called from the **head-on** branch of `_handle_wall_run()`
  only. The sideways branch attaches regardless of where the top is.
- **Why this is not undoing "No wall-run at the top of a wall":** that rule was asked for so
  the mantle has a clean activation point. Head-on at a reachable lip it still does - the
  airborne mantle runs first and the head-on attach still refuses. Alongside a wall the
  activation point is *steering in*, which already mantles off a run. What the 09-24 rule
  added alongside a wall was a dead zone, not a mantle. **Supersedes that section's sideways
  half.**
- The rise past the top is handled by (4)'s low ray, not by the refusal.

### 2. The stick in the run's frame

- For the length of a run, the stick is converted with the run's axes, not the camera's:
  stick-forward is `_wall_run_direction`, stick-right is the run's right. New
  `_wall_run_stick()` replaces `_travel_direction(stick)` in **both** places that read it
  during a run - the detach in `_handle_wall_run()` and the steer-in in
  `_try_mantle_off_wall_run()`.
- The cones are unchanged: past `wall_run_detach_angle` away from the wall lets go, past it
  into the wall is steering in. So: forward, back, or centred - stays on. Strafe toward the
  wall - steer in (mantle / reach for the top). Strafe toward open space - let go.
- **Departure from what was pitched:** the diagnosis offered "let go only when forward is
  released". Not taken - a resting thumb on a pad centres the stick, and that is one more
  mid-run drop, which is the complaint. Centred stick already stays on today; it still does.
- **The cost, stated:** looking *at* the wall and pushing forward runs along it rather than
  steering in. Steering in is a strafe toward the wall. That is the Titanfall trade: the
  camera is free during a run.
- The camera roll, the welded mesh facing and first person are untouched.

### 3. Lockout by cause

| Let-go | Lockout on that face |
|---|---|
| Timer | Until ground or wall-jump (as now - otherwise the timer means nothing) |
| Crouch | Until ground or wall-jump (as now - it is a deliberate drop) |
| Stick strafe away | **`wall_run_regrab_delay`, 0.3 s**, then free. Without any, gate 5 lets his unchanged along-wall velocity re-grab next frame; after it, steering back onto the wall re-attaches |
| Wall ended | **None.** The same plane further on - past a doorway, a gap between panels - is a new run |

Wall coyote opens on all four, as now.

### 4. Held to the wall

- **Hold distance:** capsule radius + `WALL_RUN_HOLD_MARGIN` (0.05 m) = 0.39 m from the face to
  his centre. Read from the collision shape, not a dial.
- **Pull:** each run frame, the probe's hit distance `d` gives a velocity along `-_wall_normal`
  of `(d - hold) / wall_run_pull_time` (0.1 s). Perpendicular to the run, so the 15 m grid is
  untouched. No snap at attach - the pull closes the gap in ~0.2 s, and a pop of up to 0.4 m
  sideways would read as a glitch. **Departure from the pitch**, which said "snap".
- **Follow:** each run frame, when the wall-side probe's normal is within
  `wall_run_follow_angle` (20°) of `_wall_normal`, `_wall_normal`, `_wall_point` and
  `_wall_run_direction` are re-taken from it (direction re-projected, speed kept). Seams,
  slightly angled panels and gentle curves carry him along. A sharper turn is the wall ending
  - an outer corner still launches him off the end. The side (`_wall_run_right`) and the mirror
  never change mid-run.
- **Sustain probe:** fired toward the wall side only (the side latched at attach), at two
  heights: the torso ray (`WALL_RUN_PROBE_HEIGHT`, 1.0 m) and a low ray
  (`WALL_RUN_LOW_PROBE_HEIGHT`, 0.3 m). Follow and pull read whichever hits, torso first.
  - Both miss: the wall ended, as now.
  - Torso misses, low hits, **rising**: he has risen to the top of the wall - the rise ends
    here (`velocity.y = 0`, `_wall_run_leveled = true`) and the run carries on.
  - Torso misses, low hits, level: a window or gap at chest height - keep running.
- Reach stays `wall_run_probe_reach` (0.8 m), so with the hold at 0.39 m there is 0.41 m of
  tolerance for a face that steps back.

### New dials

| Dial | Default | |
|---|---|---|
| `wall_run_regrab_delay` | 0.3 s | (3) |
| `wall_run_pull_time` | 0.1 s | (4) |
| `wall_run_follow_angle` | 20° | (4) |

Constants: `WALL_RUN_HOLD_MARGIN` 0.05, `WALL_RUN_LOW_PROBE_HEIGHT` 0.3.

### Tests

Headless, pure, in `tests/test_pilot9_wall_run.gd`:

- `_wall_run_stick()`: forward with the camera turned 90° and 180° off the run is still
  along the run; strafe toward the wall passes `_steers_into_wall()`; strafe away passes the
  let-go cone; centred and back do neither. Both wall sides.
- The pull: zero at hold, toward the wall when farther, away when closer; perpendicular to
  the run direction.
- Follow: a normal 10° off is taken, 30° off is refused.
- Lockout by cause: stick let-go frees after `wall_run_regrab_delay`, timer and crouch do not,
  wall ended sets none.
- Source order: the sideways attach branch no longer calls `_wall_top_in_mantle_reach()`;
  the head-on branch still does.

With real walls, built in the test (a running frame and collision):

- Two collinear panels with a 1.5 m doorway between them: runs off the first, re-grabs the
  second.
- Two panels meeting at a 10° bend: one uninterrupted run.
- A 3 m wall caught on the rise: attaches, levels at its top, runs on.

Checked in play only: that the camera-free run feels like Titanfall, the pull does not read as
a tug, and steer-in is findable as a strafe.

Order: spec (this), build, **the user plays it**, worklog.

### Built, 2026-09-24

All four as specced. Notes:

- The let-go takes its cause: `_let_go_of_wall(WallLetGo.TIMER | CROUCH | STICK | WALL_ENDED)`;
  `_wall_lockout_time_for()` maps it, `_tick_wall_lockout()` counts the stick's 0.3 s down
  beside the other airborne timers.
- A sustain hit whose face turns more than `wall_run_follow_angle` counts as the wall ending
  (`WALL_ENDED`, no lockout), same as both rays missing.
- The dash out of a run still aims with the camera-relative stick - only the run's own reads
  (let-go, steer-in) moved to the run's frame.
- The real-wall tests step `_handle_wall_run()` + `_apply_wall_run_velocity()` and move him by
  velocity with no collision, so the pull alone has to hold him on the face.
- Suite: 661 tests pass. The headless run segfaults on exit after the leak report; it does so
  with the new tests switched off too, so it predates this pass.

## Sprint cycle on the wall, 2026-09-26

User call: *"our current wall run animation is kinda bad ... lets just take the normal sprinting
animation cycle and just use that as our wall running animation."* `P_wall-runR` is retired. This
section supersedes *The animation* above.

| # | What | Before | Now |
|---|---|---|---|
| 1 | The `wall_run` state's clip | `wall_run_r` (`P_wall-runR`) | **`sprint_forward`**, the same cycle the ground sprint plays, at authored speed |
| 2 | Left wall | Rig mirrored (`Armature.scale.x = -1`) | **No mirror.** The sprint cycle has no side, so both walls play it as-is. `_mirror_model_for_wall_run()` is deleted |
| 3 | Body pose | Upright, the clip posed him | **Upright, then leaned 30° away from the wall**: `character.rotation.z`, feet toward the face, head out into open air (the Titanfall look). Facing stays welded along the wall, unchanged |
| 4 | Lean easing | - | Eased in and out at `slope_align_speed` (10), the slope tilt's rate, through `_align_model_to_slope()`. A wall-to-wall chain swings through level on each hop |
| 5 | Tunable | - | **`wall_run_lean`, 30°**, `@export_range(0, 60)` |

Unchanged: the camera roll (12° toward the wall), the facing weld, the mantle's snap to level on
entry, the held staff staying off during a run (`item_holder.gd`'s `wall_run: false`).

`P_wall-runR` stays in the GLB but is no longer lifted into the library (`GLB_CLIPS` entry
commented out, like `P_sitting`). No `P_wall-runL` exists and none is needed.

**Watch for in play:** the lean pivots on `character`'s origin, so the feet stay put and the head
swings out. If his feet look like they float off the face, or clip into it, the fix is the hold
distance or a small sideways offset, not the angle.

## The wall hand, 2026-09-26

User call: *"make it so when pilot goes up to a wall run, whatever side the wall is on, have the arm
go back behind him (same as holding the staff) but dont put the staff in hand. This will make it
look like pilot is gliding his hand across the wall for support."*

| # | What | Now |
|---|---|---|
| 1 | Which arm | The arm on the **wall's side**: right wall, right arm; left wall, left arm. Read from `wall_run_on_right()`, latched at attach |
| 2 | The pose | The staff's running hold (`staff.tres` `hold_rotations`), copied into **`wall_hand_rotations`** on pilot9 (Wall Run group) so it can be tuned apart from the staff - and so it exists when he carries nothing |
| 3 | Left arm | Not authored. Mirrored at runtime from the right-arm rotations across the chest's left/right plane, using the rig's rest poses (the blockout skeleton is symmetric across X) |
| 4 | The staff | Untouched. Holstered stays on the back; the hold never draws it. If it is already drawn and the wall is on the right, the staff hand is the gliding hand |
| 5 | When | Only while `is_wall_running`. Fades in and out over 0.15 s, the staff hold's blend. A wall-to-wall chain fades one arm out as the other fades in |
| 6 | How | `scripts/wall_hand.gd`: two `ArmPoseModifier`s (the held item's, `scripts/items/arm_pose_modifier.gd`), one per arm, built at runtime like the item holder so a rig rebuild cannot drop them. Added after the item's modifier, so they win if both ever touch the same bone |

Rotations are parent-relative, so the arm rides the 30° lean: with the head leaned away from the
wall, the trailing hand drops toward the face.

**Watch for in play:** whether the hand actually reaches the wall. The staff pose was tuned to trail
a staff, not to touch a surface, so expect to open `wall_hand_rotations` in the remote inspector and
swing `RightUpperArm` further out toward the wall. Tune the right arm only - the left follows.

## Committed to the wall, 2026-09-27

User call: *"change wall run, so the only way for pilot to get out off a wall run is A. jumping and
B. the end of a wall/ when the wall run ends and pilot slide down."*

The run no longer lets go on input you did not mean as an exit. Detach is now:

| Trigger | Now |
|---|---|
| **Jump** | The wall-jump - unchanged |
| **The wall ends** (both probes empty, or the face turns past `wall_run_follow_angle`) | Detaches keeping all velocity - unchanged |
| **The run ends** (`flat + droop`) | He slides down the face through the droop, then falls - unchanged |
| Stick away from the wall | **Removed.** Any stick direction holds the run |
| Crouch | **Removed.** The press is still consumed while running, so it does nothing - it does not arm a slide or a landing crouch either |

Kept, because they are not the player bailing off the wall:

- **Mantle** - a ledge dead ahead along the run, or the top of this wall with the stick steered
  into it (row 3 of *Mantle vs wall-run*). That is climbing the wall, not leaving it. Say so if
  this should go too.
- Touching the floor, the dash, a freeze, a respawn - non-player or already-grounded endings.

Code: the `CROUCH` and `STICK` let-go causes are gone from `WallLetGo`, and with them the
`wall_run_regrab_delay` dial (it only timed the stick let-go's lockout). The "reaching for the top"
exception in the stick cone is gone - with no stick let-go there is nothing for it to except.
`wall_run_detach_angle` stays: it is still the steer-in cone for the top-of-wall mantle.
