# Spec: Setsuna's animation tree

> **Rebuilt 2026-09-03 for the `SETSUNA.glb` export.** The tree below is the second version.
> The first one was built against a set of fourteen clips with authored starts and ends
> (`RUN START/END`, `SPRINT START/LOOP/END`, `Jump_start`/`Jump_end`, `DASH_loop`). Once the
> transitions worked, the user deleted all of those in Blender and re-exported **nine** clips,
> every one of them prefixed `SET ` — so the crossfades on the transitions are now the *only*
> thing between any two clips, and there is nothing authored left to fall back on.
>
> The export's own name changed with it: her source file is `Documents/SETSUNA.glb`, not
> `Documents/Project_Pilot.glb`. The destination asset is still `assets/setsuna.glb`.
>
> The Problem statement below is kept as the record of why the tree exists at all.

## Problem statement

Setsuna has a full locomotion set — `IDLE`, `RUN START/LOOP/END`, `SPRINT START/LOOP/END`,
`DASH`, `DASH_loop`, `Jump_start`, `JUMP`, `Jump_end`, `Falling` — and the moves themselves feel
fine. What does not work is getting from one clip to the next. Every request to make a
transition smooth has failed, and the reason is structural, not a tuning miss.

`scripts/player.gd` hand-rolls a state machine directly on `AnimationPlayer`:

- Transitions are `anim_player.play(name, blend)` / `anim_player.queue(name)` /
  `anim_player.seek(0.0, true)` calls scattered through the `# --- Animation ---` block of
  `_physics_process`, chosen by a web of lagging booleans (`was_moving`, `stopping`, `landing`,
  `standing_up`, `was_dashing`, `was_landing`, `was_standing_up`).
- Those booleans are re-evaluated **every physics frame**, and more than one branch can call
  `play()` on consecutive frames. A crossfade started on frame *N* is stomped by a bare
  `play()` on frame *N+1* before it is visible. This is why adding a blend argument "does
  nothing".
- `anim_player.queue(next)` starts `next` with `playback_default_blend_time`, which is **0** and
  is never set. So `RUN START → RUN LOOP`, `Jump_start → JUMP`, `RUN END → IDLE` and every other
  queued hand-off is a hard cut by construction.
- `anim_player.seek(0.0, true)` — the `true` forces an immediate skeleton update — is called
  right after `play()` in `_start_jump_anim`, `_start_slide` and the dash block, which snaps the
  pose to frame 0 and discards any crossfade.

The fix is to stop hand-rolling it. Godot's `AnimationTree` with an
`AnimationNodeStateMachine` makes each transition an atomic object with its own `xfade_time`
that cannot be interrupted mid-blend by an unrelated branch, and a `BlendSpace1D` makes
run↔sprint a continuous slide with no transition at all.

## Scope

- **Setsuna only.** EXIA has the same disease (`mech.gd` uses the same `play()` / `queue()`
  pattern) but its clips are welded to the root-motion split in `mech.gd` — `_root_motion_step`
  reads `anim_player.current_animation` and `current_animation_position` every frame — and
  moving it onto `AnimationTree` means rewriting that section against
  `AnimationTree.get_root_motion_position()`. That is a separate pass with its own spec.
- **The nine clips that ship today**, all of them: `SET IDLE`, `SET RUN LOOP`,
  `SET CROUCH LOOP`, `SET CROUCH LOOP LEFT`, `SET CROUCH LOOP RIGHT`, `SET JUMP LOOP`,
  `SET Falling`, `SET DASH`, `SET embark`. Nothing is dropped at import except the `MECH.*`
  stowaways and the `PLACEHOLDER*` junk.
- **`SLIDE` has no clips and stays unanimated.** `_can_slide()` requires a `SLIDE START` that
  does not exist, so C at a sprint ducks instead of sliding. The slide's *movement* code is
  untouched and wakes up whenever clips for it appear.
- **`embark` stays scripted.** It is played forwards, backwards (`play_backwards`) and
  seeked to arbitrary frames, with physics disabled and the mech driving her whole transform.
  `AnimationTree` is bad at all three. The tree is switched **off** (`active = false`) for the
  whole embark → ride → disembark → exit sequence and the existing raw `AnimationPlayer` calls
  in `begin_embark` / `begin_unseal` / `begin_disembark` / `ride` run unchanged; it is switched
  back **on** in `exit_vehicle`.
- **No Blender work.** `SET IDLE` carries a slow breathing motion, so "always moving at rest"
  holds as soon as the machine is structured not to stop on a held frame. Pose-match touch-ups
  between specific clip pairs are logged as gaps, not done here.
- **Gameplay is untouched.** Every speed, `JUMP_VELOCITY`, `DASH_TIME`, `DASH_COOLDOWN`, the
  apex/gravity bands, `ROTATE_SPEED`, the collider heights — all stay exactly as they are. This
  pass changes only how the animation is delivered.

## The node graph

One `AnimationTree` node, added under `PlayerModel` as a sibling of `AnimationPlayer`:

```
AnimationTree
  anim_player            = ../AnimationPlayer
  callback_mode_process  = Physics        # player.gd drives it from _physics_process
  active                 = true
  tree_root              = AnimationNodeStateMachine  (below)
```

`tree_root` is an `AnimationNodeStateMachine` saved to
`resources/setsuna_locomotion_tree.tres` so the transition table lives in one file rather than
inline in the scene.

### States

Flat — every state is a sibling in the one state machine. **Six** states, down from eleven:
the whole start/end tier is gone because the clips it played are gone.

| State | Node type | Clip(s) | Loop | Notes |
|---|---|---|---|---|
| `IDLE` | `Animation` | `SET IDLE` | linear | Start node. The **only** resting state. |
| `RUN` | `TimeScale → Animation` | `SET RUN LOOP` | linear | `scale` = smoothed speed ÷ `RUN_CLIP_SPEED`, clamped `1.0 … 1.5` |
| `CROUCH` | `BlendSpace1D` | `SET CROUCH LOOP LEFT` @ -1, `SET CROUCH LOOP` @ 0, `SET CROUCH LOOP RIGHT` @ +1 | linear | axis = the crouch lean, off how hard she is turning, `sync = on` |
| `JUMP` | `TimeScale → Animation` | `SET JUMP LOOP` | linear | the whole airborne arc, played at `JUMP_CLIP_SCALE` = **2.0** |
| `FALL` | `Animation` | `SET Falling` | **ping-pong** | walked off a ledge. The clip does not loop cleanly, so it is played forwards and then backwards - see gap 1 |
| `DASH` | `TimeScale → Animation` | `SET DASH` | none | `scale` set per-dash by script |

**`RUN` is a rate, not a blend, now.** It used to be a `BlendSpace1D` between `RUN LOOP` at
6 m/s and `SPRINT LOOP` at 9. `SPRINT LOOP` no longer exists, so the one cycle is wrapped in an
`AnimationNodeTimeScale` and the gait change is its playback rate: `_anim_speed / RUN_CLIP_SPEED`
clamped to `[1.0, RUN_MAX_SCALE]`, which is exactly 1.0 at a run and 1.5 at a sprint. It is
never taken below 1.0 — under `SPEED` the only thing happening is a stop, and the crossfade owns
the body through that. Set `RUN_MAX_SCALE = 1.0` to pin the cadence and let a sprint simply
cover more ground per stride.

**`CROUCH` is one state covering both standing and walking crouched**, because all three crouch
clips are *static poses* rather than cycles — nothing in any of them moves over its own second.
`SET CROUCH LOOP` is the upright crouch; `SET CROUCH LOOP LEFT` and `SET CROUCH LOOP RIGHT` are
the same crouch leaning to one side (the feet 13 cm apart in Z, the chest swung 19 cm over). So
**the axis is her turn**: she banks into a corner for as long as she is coming round it, and
crouches upright the moment she is pointing where she is going.

| What she is doing | Pose | Axis |
|---|---|---|
| still, or creeping in a straight line (any of `W`, `A`, `S`, `D`) | `SET CROUCH LOOP` | 0 |
| coming round to the left | `SET CROUCH LOOP LEFT` | → -1 |
| coming round to the right | `SET CROUCH LOOP RIGHT` | → +1 |

What measures the turn is her **heading lag** — the angle from where she is pointing to the
direction the input is asking for. `rotation.y` chases that direction at `ROTATE_SPEED`, so the
lag *is* the turn rate divided by `ROTATE_SPEED`: it grows the harder she corners, it holds
while a mouse swing keeps dragging the target round, and it collapses to zero as she lines up.
Reading the lag rather than the per-frame yaw delta keeps the lean out of the movement block and
off the frame rate. `CROUCH_LEAN_ANGLE` (15°) is the lag that leans her fully over — about a
90°/s corner held, which a tapped direction change overshoots and saturates.

**The sign is the trap.** The lag carries the yaw's sign, which is *positive going left*: her
nose is local +Z, so her right is local -X, and swinging the forward vector that way **decreases**
`rotation.y`. The blend axis is signed the other way round (+1 is the right-hand pose), so
`_step_crouch_lean()` negates. Get it backwards and she banks out of every corner instead of into
it — which still looks like a deliberate animation, so `tests/test_setsuna_animation_tree.gd`
pins the sign rather than just the magnitude.

The axis is eased toward its target at `CROUCH_LEAN_SPEED` rather than written outright, because
these are held poses with nothing to fade them: written directly, they would pop. It has to
outrun the corner, though — a tapped turn is over in ~0.3 s at `ROTATE_SPEED = 10`, so a lean
speed under ~5 arrives after she has already straightened and the bank never shows. `sync = on`
keeps the three poses' playheads together, which costs nothing for static clips and matters if
they are ever animated.

**`JUMP` is the whole jump.** `Jump_start` and `Jump_end` are gone, so there is no wind-up state
to auto-advance out of and no landing state to clear: the launch is `travel("JUMP")` and the
landing is whichever ground condition comes true, over that transition's own crossfade. An air
jump re-travels to `JUMP` while already in it, which is a no-op on the animation — the double
jump re-pops her height without re-popping the flip.

**It runs at double speed.** The cycle is authored slower than her hops actually last, so at 1.0
a short hop showed maybe a third of it and read as a held pose rather than a move. `JUMP` is
wrapped in a `TimeScale` like `RUN` and `DASH`, but its rate is a constant — `JUMP_CLIP_SCALE`,
written once in `_ready()` rather than per frame. It cannot be fitted to the airtime the way
`DASH` fits its clip into `DASH_TIME`: `JUMP` is a loop she hangs in for as long as she is off
the ground, and that has no duration to divide by. Retune the const, not the clip.

`RUN` and `DASH` are the two `AnimationNodeTimeScale` states, which replaces
`anim_player.play(name, -1, custom_speed)`. `DASH`'s scale is `dash_clip_length / DASH_TIME`,
written to the tree before the `travel("DASH")` call so the state starts at the right rate on
its first frame.

## Transitions

Discrete events (jump, dash) are triggered by **`playback.travel()` calls from script**.
Everything continuous (starting to move, stopping, landing, falling off a ledge, changing gait)
is driven by **condition bools** set on the tree each frame. No transition uses a per-`play()`
blend argument — `xfade_time` on the transition is the single source of truth.

### Condition bools

`player.gd` writes these to `parameters/conditions/*` every physics frame, derived from three
facts: `is_on_floor()`, `direction.length() > 0.01`, and the crouch toggle.

| Condition | Meaning |
|---|---|
| `moving` | on the floor, a movement key held, **not** crouching |
| `not_moving` | on the floor, no movement key, **not** crouching |
| `crouching` | on the floor and crouching, moving or not |
| `off_floor` | `not is_on_floor()` |

Four bools, down from twelve, and the reason is worth writing down: **they are mutually
exclusive and exhaustive by construction.** Exactly one is true on any frame. A state-machine
transition can only AND its conditions, never negate one, so the negations are baked into the
bools themselves — `moving` carries "and not crouching" rather than the table carrying a
`not_crouching` row. That is what makes the one-live-exit invariant below true by inspection
instead of by a sweep, and it is why the old gait-qualified pairs (`moving_run` /
`moving_sprint`, the four `stopping_*` bools) are gone: sprint is no longer a clip choice, so
the tree does not need to know about it at all.

`landed` and `on_floor` went with `JUMP_END` and the short-hop row that used them.

### Transition table

Switch mode `Immediate` = the moment the condition is true. `At End` = waits for the current
clip to finish (auto-advance). `xfade` in seconds.

**Every row carries a real crossfade, and that is now load-bearing rather than polish.** With
the start/end clips deleted there is no authored motion between any two states — the xfade *is*
the transition. `tests/test_setsuna_animation_tree.gd::test_every_transition_crossfades`
asserts no row is ever zeroed out; `Start → IDLE` is the one exception, since there is no
outgoing pose to fade from on the first frame.

| From | To | Trigger | Switch | xfade |
|---|---|---|---|---|
| `Start` | `IDLE` | — | Immediate | 0.00 |
| `IDLE` | `RUN` | `moving` | Immediate | 0.18 |
| `IDLE` | `CROUCH` | `crouching` | Immediate | 0.15 |
| `IDLE` | `FALL` | `off_floor` | Immediate | 0.10 |
| `RUN` | `IDLE` | `not_moving` | Immediate | 0.18 |
| `RUN` | `CROUCH` | `crouching` | Immediate | 0.15 |
| `RUN` | `FALL` | `off_floor` | Immediate | 0.10 |
| `CROUCH` | `IDLE` | `not_moving` | Immediate | 0.15 |
| `CROUCH` | `RUN` | `moving` | Immediate | 0.18 |
| `CROUCH` | `FALL` | `off_floor` | Immediate | 0.10 |
| `JUMP` | `IDLE` | `not_moving` | Immediate | 0.20 |
| `JUMP` | `RUN` | `moving` | Immediate | 0.15 |
| `JUMP` | `CROUCH` | `crouching` | Immediate | 0.15 |
| `FALL` | `IDLE` | `not_moving` | Immediate | 0.12 |
| `FALL` | `RUN` | `moving` | Immediate | 0.12 |
| `FALL` | `CROUCH` | `crouching` | Immediate | 0.12 |
| `DASH` | `FALL` | `off_floor` | At End | 0.12 |
| `DASH` | `RUN` | `moving` | At End | 0.15 |
| `DASH` | `IDLE` | `not_moving` | At End | 0.15 |
| `DASH` | `CROUCH` | `crouching` | At End | 0.15 |
| every other state | `JUMP` | `travel("JUMP")` | Immediate | 0.05 |
| every other state | `DASH` | `travel("DASH")` | Immediate | 0.05 |

Notes on specific rows:

- **`Any State → JUMP` / `→ DASH`** carry the grounded jump, the air jump, the dash and the
  air-dash in one transition each. `travel()` is used rather than a condition bool so there is
  no one-frame race between "script set the flag" and "the tree happened to check". Godot 4.6's
  `AnimationNodeStateMachine` has no `Any State` node — `add_transition("Any", ...)` is rejected
  outright — so each is spelled out from every other state, five rows each. Neither list
  contains its own destination.
- **Neither `JUMP` nor `FALL` has an `off_floor` exit.** They *are* the airborne states; there
  is nowhere for `off_floor` to send them. The old table needed `FALL` kept off `Any State` for
  exactly this reason, and the new one gets it for free.
- **Landing is a transition, not a clip.** `JUMP → IDLE / RUN / CROUCH` replaces the whole
  `JUMP_AIR → JUMP_END → …` chain. `JUMP → RUN` is the old "she skips `RUN_START` because she is
  already at speed" behaviour, now trivially true because `RUN_START` does not exist.
- **`DASH`'s exits are all `At End`** so the dash clip (speed-scaled into `DASH_TIME`) always
  plays out. `DASH → FALL` is what `DASH → DASH_AIR` used to be: the sustain clip is gone, so an
  unfinished airborne dash hands over to the fall cycle instead.
- **An At End transition beats an Immediate one** — when two transitions out of one state are
  eligible on the same tick, Godot takes the `At End` one and drops the `Immediate` one,
  regardless of insertion order and regardless of `priority`. `DASH`'s four exits are all
  `At End` and mutually exclusive, so nothing can be swallowed; the invariant the table rests on
  is still **out of any state, at most one transition is ever eligible at once**, and
  `tests/test_setsuna_animation_tree.gd` sweeps every world state and asserts it.

## What player.gd feeds the tree

The `@onready`s:

```gdscript
@onready var anim_tree: AnimationTree = $PlayerModel/AnimationTree
@onready var _sm: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
```

`_ready()` sets the loop modes and the one playback rate that never changes
(`parameters/JUMP/TimeScale/scale` = `JUMP_CLIP_SCALE`). The `JUMP_START` TimeScale write it used
to carry went with the state.

Every `_physics_process`, **after `move_and_slide()`**. The spec originally said before it, on
the reasoning that the tree ticks during the physics step; it does, but Godot runs a child's
`_physics_process` after its parent's, so writing them at the end of this function still lands
them in the same step — and `is_on_floor()` only tells the truth about *this* frame afterwards.
Set beforehand, the frame she jumps still reports `on_floor` and the ground conditions would
pull her straight back out of `JUMP` before it drew a frame.

```gdscript
# condition bools - exactly one of the four is ever true
var grounded := is_on_floor()
var pressing := direction.length() > 0.01
var moving := grounded and pressing and not is_crouching
var stopped := grounded and not pressing and not is_crouching
anim_tree["parameters/conditions/moving"]     = moving
anim_tree["parameters/conditions/not_moving"] = stopped
anim_tree["parameters/conditions/crouching"]  = grounded and is_crouching
anim_tree["parameters/conditions/off_floor"]  = not grounded

# the run cycle's playback rate: 1.0 at a run, 1.5 at a sprint
var flat_speed := Vector2(velocity.x, velocity.z).length()
_anim_speed = move_toward(_anim_speed, flat_speed, ANIM_SPEED_LERP * delta)
anim_tree["parameters/RUN/TimeScale/scale"] = clampf(_anim_speed / RUN_CLIP_SPEED, 1.0, RUN_MAX_SCALE)

# the crouch lean, eased toward the corner she is coming round
var heading_lag := angle_difference(rotation.y, atan2(direction.x, direction.z)) if pressing else 0.0
anim_tree["parameters/CROUCH/blend_position"] = _step_crouch_lean(heading_lag, delta)
```

Standing still there is no direction to lag behind, hence the `pressing` guard and no lean. It is
written every frame rather than only while crouching, so the axis has already eased to the turn
she is actually in by the time `CROUCH` fades in again. `_step_crouch_lean()` is split out of
`_physics_process` so the mapping and its sign are under test: an axis that silently never leaves
0 is not an error anywhere, it just looks like a lean that was never wired.

Discrete events, at the existing call sites:

- grounded jump and air jump (`_start_jump_anim()`): `_sm.travel("JUMP")`.
- dash block: `anim_tree["parameters/DASH/TimeScale/scale"] = dash_anim_len / DASH_TIME`
  then `_sm.travel("DASH")`.

## What player.gd loses

*The record of the original migration off the hand-rolled state machine. What the 2026-09-03
re-export took out on top of this is in **What the re-export retired**, below.*

Deleted vars: `was_moving`, `was_crouching`, `was_standing_up`, `standing_up`, `stopping`,
`landing`, `was_landing`, `was_dashing`. (`was_moving` currently also feeds
`is_running` for `RUN_MODEL_LIFT` — see gaps.)

Deleted constants: `LOCOMOTION_BLEND`, `RUN_STOP_BLEND`.

Kept untouched: every gameplay constant, all dash/jump/slide *gameplay* state
(`dash_time_left`, `dash_cooldown_left`, `dash_dir`, `dash_queued`, `jump_queued`, `jumps_used`,
`jumping`, `sliding`, `crouching`, …), the `_ready()` `loop_mode` assignments (the tree
references the same `Animation` resources, so their loop modes still matter).

Deleted logic: the entire `# --- Animation ---` block of `_physics_process` (roughly lines
605–703 as the file stands) — the `moving`/`was_moving` bookkeeping, the `standing_up` /
`stopping` / `landing` one-shot guards, the `_gait_clip` `play`/`queue` ladder, the
`DASH_loop` hand-off, the `Jump_end` branch. Replaced by the ~15 lines above.

`_gait_clip()` stays only if slide/crouch still reference it; otherwise it goes too. (It is used
by the deleted block for `start_clip`/`end_clip` and nowhere else — expected to be removed.)

The embark path (`begin_embark`, `begin_unseal`, `begin_disembark`, `ride`, `enter_vehicle`,
`exit_vehicle`) gains two lines: `anim_tree.active = false` at the top of the first three,
`anim_tree.active = true` in `exit_vehicle` alongside the physics/collision re-enable. The raw
`anim_player` calls inside them do not change.

## Scene / resource changes

- `scenes/player.tscn`: the `AnimationTree` node under `PlayerModel`. **Unchanged by the
  rebuild** — the tree resource is swapped underneath it, and the 2026-09-03 export did not
  touch the mesh, the rig or the bone order, so the five `Screen*` `BoneAttachment3D`
  `bone_idx` values (`spine.002` 5, `thigh.L` 15, `thigh.R` 17) still hold.
- `resources/setsuna_locomotion_tree.tres`: the `AnimationNodeStateMachine` with the six states
  and the transition table above. `CROUCH`'s blend space runs `-1.0 → +1.0`, which is also the
  Godot default, so the `min_space` load-order trap the old `RUN` blend space had to work around
  does not bite here: a `.tres` restores `min_space` before `max_space` and `set_min_space()`
  clamps under whatever max is loaded at the time, and -1 is under the default 1.
- `tests/test_setsuna_animation_tree.gd`: pins the states, the clips, the transition table, the
  crouch blend space, the every-transition-crossfades rule and the one-live-exit invariant.
- `scripts/setsuna_import.gd`: the allow-list is the nine `SET ` clips. It also drops the
  `PLACEHOLDER*` actions that arrived with this export.

## What the re-export retired

`PLAY_RUN_END` is gone. It was a look toggle for "does the `RUN END` wind-down clip play when
she stops running" and it carried two parallel routes through the tree so the A/B could be run
without editing the transition table. The user answered the question in Blender instead: they
deleted `RUN END` along with every other start and end clip. With no clip there is nothing to
toggle, so the const, its four condition bools and its bypass rows all came out.

Gone with it: `RUN START`, `SPRINT START`, `SPRINT LOOP`, `SPRINT END`, `Jump_start`,
`Jump_end`, `DASH_loop`, `CROUCH START`, `CROUCH END`, `SLIDE START`, `SLIDE END`, and the
`JUMP_START_SPEED` const that scaled the jump wind-up.

**Sprint has no clip of its own any more.** It is still a gameplay gait — `SPRINT_SPEED`,
the Shift toggle, the crouch/slide pairing are all untouched — but on screen it is the run cycle
run 1.5× faster. If that reads wrong, `RUN_MAX_SCALE` is the knob.

**A raw `anim_player.play()` while the tree is active fights the tree**, so the crouch stand-up's
`play("CROUCH END")` was removed rather than left behind a dead `has_animation()` guard. The
slide's two raw calls are still there and still unreachable (`_can_slide()` requires a
`SLIDE START` that does not exist); they need routing through the tree before slide clips come
back. See gap 5.

## Known gaps (identified, not fixed here)

1. **`SET Falling` does not loop cleanly - faked with ping-pong.** Its first and last frames are
   ~29° apart across the legs and arms, so `LOOP_LINEAR` popped once a second on a long drop. It
   is a 1.0 s clip (it was 0.5 s before this export). `player.gd` now sets it to
   `Animation.LOOP_PINGPONG` instead of `LOOP_LINEAR`, alone among her clips: it plays forwards
   and then straight back down, so the only join left is the clip against its own mirror and the
   pose either end matches by construction. The drop reads as a 2.0 s cycle rather than a 1.0 s
   one with a hitch, and the motion is time-symmetric - watch in QA for the fall reading as a
   slow rock rather than a cycle. The real fix is still matching the two poses in Blender; when
   that lands, `tests/test_setsuna_animation_tree.gd` fails and says so, and the clip goes back
   into the `LOOP_LINEAR` list.
2. **`CROUCH_LEAN_ANGLE` is a feel number, not a measured one.** 15° of heading lag for a full
   bank was picked against `ROTATE_SPEED = 10`; retune it if the turn rate ever changes, and
   watch for her leaning on course corrections she isn't really turning through.
3. **The crouch poses are static.** All three are held poses, so a crouch walk has no footfalls
   and no secondary motion at all — no bob, no arm swing beyond what the lean carries. She
   slides along in a pose. If that reads as stiff, the fix is authoring, not tuning.
4. **Pose mismatches at specific joins.** Every join is now a raw crossfade, so this matters more
   than it did: `SET DASH`'s last frame vs `SET IDLE`'s first (52° apart), `SET JUMP LOOP` vs the
   ground clips. `xfade_time` blurs these; matching the poses in Blender is the real fix.
5. **Slide.** No clips, and `player.gd`'s slide block still calls `anim_player.play(...)`
   directly. Those calls no-op through `has_animation()` today, but they would fight the tree the
   moment `SLIDE *` clips reappear — route them through a state at that point.
6. **`RUN_MODEL_LIFT`.** The 8 cm model lift while running is still a step change
   (`player_model.position.y = RUN_MODEL_LIFT if is_running else 0.0`). With blended entries it
   should ease over the same window as the transition. Cheap follow-up: `move_toward` it toward
   the target each frame. Not blocking.
7. **The air jump does not restart the flip.** `travel("JUMP")` while already in `JUMP` is a
   no-op, so a double jump re-pops her height without re-popping the animation. Forcing a restart
   means `_sm.start("JUMP")`, which is a hard cut — exactly what the tree exists to avoid. Left
   as is until QA says the second hop looks dead.
8. **EXIA.** Same rebuild, separate spec, gated on this one landing.

## QA pass (manual — user drives)

Watch each of these for a hard cut. "Pass" = motion is continuous through the join. Every one of
these joins is a bare crossfade now, so this pass is the whole verification — there is no
authored transition left to carry a join that the xfade gets wrong.

- idle → run → idle (release mid-stride)
- run → sprint → run (toggle Shift while moving) — the cadence winds up rather than the clip
  swapping; watch the feet for skating at 1.5×
- **crouch: tap C from idle** → she settles into the upright crouch
- **crouch walk in a straight line** (any single key) → upright throughout, no drifting lean
- **crouch turn: hold `W`, then add `D`** → she banks right through the corner and comes back
  upright on the new heading. The same with `A` should bank her *left* — if either leans the
  wrong way the sign is inverted, not the tuning
- **crouch turn on the mouse** (hold `W`, swing the camera) → the bank holds for as long as you
  keep swinging, and deepens with how fast you swing
- **crouch S-bend** (weave left-right-left) → she rolls through upright between the two banks
  rather than snapping
- **crouch → stand while moving** (tap C at a walk) → straight into the run
- **run → crouch at speed** (tap C mid-stride)
- grounded jump: idle → `SET JUMP LOOP` → land → idle
- grounded jump while running → land still holding W (should pick `RUN` back up)
- double jump (air jump mid-rise and mid-fall) — the flip does not restart; is that visible?
- very short hop (tap Space) — `JUMP` in and straight back out over two 0.15–0.20 s fades
- dash on the ground → resolves to idle / to run
- dash into the air → `FALL` → land (the dash sustain clip is gone; does the hand-off read?)
- walk off a ledge (no jump) → `FALL` → land — **long drop: the ~29° pop should be gone; does the ping-pong read as a fall or as a rock back and forth?**
- dash → jump (air jump out of an air dash)
- embark: F into EXIA, full climb, canopy close — tree off, no regression
- disembark: F out, canopy open, climb down, control handed back — tree back on, `IDLE` resumes

## Sequence

Spec (this doc) → user review → build → user QA → worklog entry.
