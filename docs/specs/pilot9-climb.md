# Spec: pilot9's ledge mantle

> **Status:** agreed 2026-09-07, not yet built.
> **Scene:** `scenes/pilot9.tscn`, played in `scenes/trial.tscn`.
> **Character:** `assets/pilot9.glb` (export of 2026-09-06 17:58).
> **Map:** `assets/TrainingV.glb`.
> **Follows:** `docs/specs/pilot9-slide.md` (the root-motion bake pattern this reuses) and
> `docs/specs/pilot9-turn-to-face.md` (the facing model the entry snap writes into).

## Problem statement

`climb_up` (Blender action `P.climbing`, from Mixamo *Braced Hang To Crouch*) has been in the
AnimationPlayer library since the crouch pass — `LOOP_NONE`, ~1.15 s, root motion **intact**,
wired into nothing. The slide spec parked it deliberately: "the map has no ledge to climb", and
wiring it "needs ledge detection and a body driven along a path with collision suspended,
neither of which this controller has."

The map now has a ledge. `assets/TrainingV.glb` replaced the flat `Ground` in `trial.tscn` with
a four-step staircase of increasing heights. One of those steps is mantle height. This pass
builds the detection and the path-driven motion the slide spec said it would need, and turns
`climb_up` into a verb.

### The clip

The first frame is a **fingertip catch at near-full overhead extension** — both arms up, elbows
barely bent, body hanging, knees tucked. Not a braced hang (which sits tight to the wall, hands
at forehead height). There is **no approach and no reach** before it, and **no hang-and-hold**:
the clip opens on the catch and goes straight into the pull-up to a crouch on top.

So the "grab" is not animated. The mechanic sells it by **snapping** pilot9 to this pose at the
detected lip and then playing the pull. That snap is a feature, not a compromise — it is what
makes the hands meet the edge every time.

Root motion as authored, measured off the clip: **+1.782 m up, +0.484 m forward over 1.15 s** —
a ledge about 1.8 m above the feet at the catch, landing about half a metre in from the lip.

## The target ledge, and a scale bug in the map

`assets/TrainingV.glb` is one node `Plane.001` carrying scale **36.1356**, holding one mesh
whose raised primitive is four separate blocks. Their mesh-local heights, scaled by the node:

| Block | Height |
|---|---|
| shell 2 | **1.84 m** |
| shell 0 | 4.19 m |
| shell 3 | 8.56 m |
| shell 1 | 13.33 m |

**shell 2 is the mantle target.** The other three are walls — their tops are far outside the
detection band (below) and never offer a mantle.

The catch: `trial.tscn` instances `TrainingV` with an **extra 1.7574× scale** on the node,
which pushes every block to 1.76× the numbers above (shell 2 → 3.23 m, out of reach). That
1.7574 is a stray — an "apply scale" that did not take in Blender before export, so the factor
is still live on the GLB node and the `trial.tscn` instance was scaled to compensate for a
different asset. **This pass sets the `TrainingV` instance in `trial.tscn` to scale 1.0.** The
GLB keeps its 36.1356× node scale; that is the only scale, and shell 2 lands at 1.84 m.

Fixing it on the Godot side rather than re-exporting is the user's call (2026-09-07): it
unblocks the build now and does not touch the asset. A clean re-export with the scale applied
would make the `trial.tscn` change a no-op, which is fine.

## The rule

**Airborne, near a qualifying ledge → mantle. Automatic, no button.**

Changed 2026-09-07 from the original rule, a deliberate `jump` press. The ledge probe now runs
every airborne frame and a qualifying lip in range starts the mantle with no input. The cost the
press was avoiding is real: shell 2 is ~9 m wide, and a jump up alongside its face now grabs the
lip whether or not the player wanted it. The user takes that trade for a mantle that never has
to be timed.

The probe runs **before** the jump-press handling in `_handle_gravity_and_jump()`, so a `jump`
pressed on the frame a mantle begins is buffered for the exit rather than spent as an air jump.
`jump` with no ledge in range is unchanged: floor jump, or double jump.

It runs to completion. **Not cancellable** — collision is off and he is on a scripted path over
an edge, so there is no safe point to release him. A `jump` pressed during the mantle is
**buffered** and fired on the first frame after the endpoint snap and collision restore, so
chaining climb → jump stays responsive (the same courtesy the land-and-slide buffer gives).

It hands back to `Locomotion` standing up, a beat before the clip ends.

## Detection

Two raycasts, run every airborne frame from `pilot9.gd`. RC-style, and the approach the slide
spec anticipated. Every number here is a tunable starting value.

1. **Forward ray** — from the capsule centre at **y ≈ 1.4 m**, along his facing, length
   **≈ 0.6 m** (grab reach past the capsule radius). Must hit a static body. Its hit normal is
   the wall normal — used by the entry snap for facing.
2. **Down ray** — from **0.4 m past** the forward hit (into the platform), starting **2.3 m**
   above his feet, length **≈ 1.0 m**. Must hit a surface whose normal is within **~30°** of
   straight up, at a height **1.5–2.1 m** above his feet. That hit point is the **lip**.
3. **Headroom ray** — from the projected landing point (lip + 0.484 m in from the edge),
   straight up **≈ 2.0 m**. If it hits anything, **the mantle is refused** — planting him
   standing inside a ceiling is an ugly failure. Nothing is above shell 2, so this never fires
   in `trial.tscn`; it is there for the first real level.

**Any static collider qualifies.** There is no "climbable" collision layer and no tag — the
**1.5–2.1 m height band is the filter**. In `TrainingV` the only lip that lands in the band is
shell 2's. A real level that needs to exclude some in-band geometry adds a layer and a mask
check then; deferring, not closing.

The qualify-a-hit predicate is pure math (`1.5 ≤ h ≤ 2.1` and `normal.dot(UP) > cos(30°)`) and
is unit-tested as such.

## Where the motion comes from

The clip cannot be played with its root motion left in, for the two reasons the slide spec
lays out — only the mesh would move while the capsule sat still, and **a root-motion track
cannot be cross-faded** (it drags the mesh across the whole entry and exit fade). The slide
solved this by baking `Hips` **Z** to a normalised `Curve` and locking Z in the library copy.
The mantle is the same trick on **two axes**.

### The bake — `_ensure_climb_motion()` in the builder

Reads `climb_up`'s `Hips` position track and writes, onto `scripts/pilot9.gd`:

- **`climb_motion`** — a `Curve3D` (or a pair of `Curve`s, Y and Z), **normalised on every
  axis**: time fraction in, distance fraction out, spanning 0..1. Linear tangents, like
  `slide_motion` — a curve that overshoots between samples is a body that lurches.
- **`climb_rise`** — the clip's total `Hips` Y travel, **+1.782 m** as authored. The scale
  `climb_motion`'s Y is normalised by.
- **`climb_reach`** — the clip's total `Hips` Z travel, **+0.484 m**. Scales the forward axis.
- **`climb_duration`** — the clip's raw (authored) length, ~1.15 s.
- **`climb_speed`** — how much faster than authored the whole mantle plays. **1.5** (user,
  2026-09-07). Applied to *both* clocks (see "Two clocks, again"), so the one number is the
  only place the pace lives.

Then **locks `climb_up`'s `Hips` Z *and* Y to their first key** in the library copy — X is
kept (lateral sway on the pull-up). What is left is an ordinary in-place clip that cross-fades
like every other.

`SLIDE_BAKED`'s discipline applies: `Object.set()` drops an unknown property silently, so every
write is read back and a missing property on the `pilot9.gd` side fails the build loudly.

The build **fails** if the clip carries less than ~1.0 m of Y travel — i.e. if `P.climbing`
comes back exported In Place. There is nothing to fall back on.

### The playback — `_apply_climb_motion()` in `pilot9.gd`

Position-driven, not velocity-driven — a mantle is not physics. Each physics frame while
`is_climbing`:

- advance `_climb_time` by `delta * climb_speed`;
- `u = _climb_time / climb_duration`;
- sample `climb_motion` at `u` → a normalised `(_, y, z)` in 0..1;
- the world offset from the entry position is
  `up * (y_norm * _climb_detected_rise) + facing * (z_norm * climb_reach)`, where
  **`_climb_detected_rise` is the actual lip height above his feet at the catch** (1.5–2.1 m),
  not the baked `climb_rise`. Scaling Y to the detected height is what lands his feet on the
  platform wherever in the band the ledge sat — the baked `climb_rise` is only the
  normalisation scale, the same role `slide_distance` plays for the slide.
- set `global_position` to `_climb_start_position + offset`. **`move_and_slide()` is not
  called** these frames — the mantle short-circuits the normal movement/rotation path in
  `_physics_process` the way `frozen` already does.

`_climb_time >= climb_duration` ends it.

### Two clocks, again

The state machine plays `climb_up` on its own clock; `_climb_time` runs in `_physics_process`.
They agree because **both run at `climb_speed` off real time** — the clip is compressed to
`climb_duration / climb_speed` by the `climb` state's **custom timeline**
(`use_custom_timeline` + `stretch_time_scale` + `timeline_length`), and `_climb_time` advances
by `delta * climb_speed`. The one factor, baked once, drives both.

**There is still no `TimeScale` *node* in the `climb` state**, deliberately — a `TimeScale`
would compress only the clip and the curve driving the body would know nothing about it, which
is exactly the silent desync the slide's risk 1 warns about. The custom timeline does the
compression *inside* the plain `AnimationNodeAnimation`, and the test pins
`timeline_length == climb_duration / climb_speed` so the two halves cannot drift apart on a
re-sync. `climb_speed` is **baked, not a live dial**, for the same reason.

There is deliberately **no `CLIMB_KEEP_FRAMES` trim** (the slide cuts its run-out tail at frame
75). The mantle's tail is the stand-up, which is worth keeping — the "beat early" hand-off is
done by the exit xfade eating it under the fade, not by cutting keys. Named so nobody adds a
trim expecting the slide's treatment.

## The entry snap

On trigger, before the clip plays, **instantly** (not blended — a 1–2 frame blend here shows
as a slide toward the wall):

- **Position.** Set `global_position` so `climb_up`'s frame-1 hands sit at the detected lip.
  The offset from the clip's frame-1 `Hips` to the hand contact point is **measured off the
  clip**, in profile-bone space after retarget, and baked by the builder alongside the curve —
  not guessed. `_climb_start_position` is stored here for `_apply_climb_motion()`.
- **Facing.** Snap `character.rotation.y` to face the wall — the heading opposite the forward
  ray's hit normal, projected to the ground plane. `_facing()` in `pilot9.gd` is the inverse
  of the rotation target and the frame both live in, so this is one `atan2` of the wall
  normal. The slide's `_slide_direction` discipline applies: while `is_climbing`,
  `_handle_character_rotation()` writes the mesh straight onto this heading and nothing else
  points him anywhere.
- **Velocity.** Zeroed. Incoming horizontal and vertical speed are discarded — the snap has
  already placed him.

## Collision

The `CollisionShape3D` (a sibling of the controller, resized by the builder) is **disabled for
the mantle's duration** and restored on the exit frame. Disable via `set_deferred("disabled",
true)` — the toggle happens inside physics processing. `pilot9.gd` gains a node reference to it
(`@onready var collision_shape`).

On exit, **hard-snap `global_position` to the computed endpoint** — lip + `climb_reach` in
along his facing, feet at lip height — so a frame of curve drift cannot leave him half in the
floor. Restore collision on the same frame. Zero velocity.

## The animation side — `_ensure_climb_state()` in the builder

A new `climb` state: a **plain `AnimationNodeAnimation`** playing `climb_up`, mirroring
`_ensure_slide_state()`, with its **custom timeline** set to `climb_up.length / climb_speed`
and `stretch_time_scale` on — so the clip plays `climb_speed`× faster without a `TimeScale`
node (the two-clocks argument above).

The controller exposes **`is_climbing`**, read by the tree through `advance_expression` exactly
like `is_sliding`. No new signal — the mantle is entered by the controller flipping the flag,
not by a clip-restart from a listener (the double jump's mechanism). `is_climbing` is gated so
it cannot be true unless `is_on_floor()` was false at trigger.

Transitions, regenerated on every sync:

| From | To | Expression | Priority | xfade |
|---|---|---|---|---|
| `fall` | `climb` | `is_climbing` | 0 | 0.08 |
| `jump` | `climb` | `is_climbing` | 0 | 0.08 |
| `climb` | `Locomotion` | `not is_climbing` | 0 | ~0.20 |

- **Entry from both `fall` and `jump`.** The trigger is airborne; depending on timing the tree
  is in `jump` (still rising) or `fall` (past apex). A fingertip catch is usually near or past
  apex, so `fall` is the common path, but a mantle that starts off a still-rising jump needs
  the `jump` edge too.
- **Near-hard entry cut (0.08 s).** The entry snap has already teleported him to the lip and
  faced him at the wall. A longer fade blends the previous airborne pose across that teleport
  and reads as a lurch.
- **One exit, to `Locomotion`.** No `climb -> fall` (collision is off, he cannot leave the
  floor mid-mantle). No `climb -> jump` (not cancellable — the buffered jump fires from
  `Locomotion` after the state exits). The ~0.20 s exit xfade eats the last ~0.15 s of the
  clip so he finishes standing up under player control rather than watching it.
- **No `Locomotion -> climb`** — airborne-only trigger, so the tree is never in `Locomotion`
  when `is_climbing` flips.
- **No `jump_land -> climb`** — it would only matter if a mantle triggered on the exact frame
  he would otherwise touch down, which airborne-plus-a-ledge-in-range makes vanishingly rare.
  Added only if play produces a stuck frame of `jump_land`.

## `frozen` mid-mantle

`frozen` **ends the mantle immediately** — snap to the endpoint, restore collision, clear
`is_climbing`, drop any buffered jump. Landing him safely on top beats dropping him mid-arc
with collision off. Same reasoning as the slide ending itself on `frozen`.

## Decisions (from the user, 2026-09-07)

- **shell 2 (~1.84 m) is the one climbable ledge.** The other three blocks are walls, out of
  scope this pass.
- **Fix the scale on the Godot side** — `TrainingV` instance to 1.0 in `trial.tscn` — rather
  than block on a re-export.
- **Trigger is automatic** — airborne with a ledge in probe range, no button (changed
  2026-09-07 from a deliberate `jump` press). Airborne only — no mantle from the ground.
- **Baked `Curve3D`, mirroring the slide.** Not a linear lerp — the pull-over-the-top arc is
  the feature.
- **The mantle plays 1.5× faster than authored** (`climb_speed`, 2026-09-07). Baked, applied
  to the clip (via the `climb` state's custom timeline) and the path (via `_climb_time`)
  together — never a `TimeScale` node.
- **Collision off for the mantle, hard endpoint snap, zero velocity in and out.**
- **Instant entry snap** — position so frame-1 hands meet the lip, mesh yaw to the wall.
- **Exit to `Locomotion` a beat early. Not into `crouch`** — being dumped into a crouch after
  every climb reads as a bug.
- **Not cancellable; jump buffered** through the mantle.
- **Headroom probe in.** `frozen` handling in.
- **First person left working** — the mantle is position-driven and the mesh-yaw write is
  harmless with nothing rendering the mesh. No special-casing.

## Risks

1. **Two clocks, now both scaled.** `climb_up` on the state machine's clock, `_climb_time` in
   `_physics_process`. Both run at `climb_speed` off real time — the clip via the `climb`
   state's custom timeline, the path via `delta * climb_speed`. They cannot drift more than a
   frame *as long as the two scalings match*: a `TimeScale` node (compresses only the clip),
   a hand-edited `timeline_length`, or a `climb_speed` the tree was not rebuilt against would
   part them silently. Mitigation: `climb_speed` is baked from one const, and the test asserts
   `timeline_length == climb_duration / climb_speed`. (Slide risk 1, tightened.)
2. **The entry snap is a teleport.** If the frame-1-hands-to-`Hips` offset is wrong, the catch
   does not line up with the visible lip and it reads as a pop. The offset is **measured off
   the clip in profile-bone space**, not eyeballed, and the builder bakes it so a re-export
   re-derives it.
3. **Collision is off for ~1.15 s.** Anything that would have blocked him — a moving platform,
   another body, a wall he was shoved into — is ignored for the mantle's length. Acceptable in
   a static trial; a hazard to revisit on a live level.
4. **The two-axis lock is new surgery.** The slide only locked Z. If the Y-lock is done wrong
   the pull-up either keeps its rise (the mesh floats up out of the capsule during the exit
   fade) or the bake reads a flattened curve and the body does not rise at all. The test
   checks both the lock and the curve's Y span.
5. **Re-authoring `P.climbing` silently re-derives the arc, the rise and the reach.** Correct —
   the bake follows the clip. But `+1.782 m` up / `+0.484 m` in is the **level-design
   contract**: geometry built against the old numbers is wrong after a re-export that moves
   them. `climb_rise` / `climb_reach` are rewritten every sync; do not hand-tune them.
6. **The detection band is the only filter.** Any static collider with an up-facing top at
   1.5–2.1 m offers a mantle. On a real level with in-band geometry that should not be
   climbable, this is a false positive until a climbable layer is added. shell 2 is the only
   thing in band in `TrainingV`.
7. **`climb_up`'s `Hips` X is kept unlocked** (sway). If a re-export gives it a large lateral
   drift that does not return to zero, the pull-up ends offset sideways from the endpoint the
   snap computed. The endpoint hard-snap covers the final frame; a big mid-clip X excursion
   would still show.
8. **Automatic means unwanted grabs.** With no press to withhold, any airborne moment with
   shell 2's lip in the 0.9–1.9 m band starts a mantle — including a jump the player meant to
   land on top of the block, or one along its ~9 m face. This is the cost the original
   deliberate-press rule was paying to avoid. Tighten `climb_band_min` / `climb_band_max` or
   `climb_probe_reach` if it fires too eagerly on play.

## What this does not do

- **No hang.** No hanging on the lip, no wait, no shimmy along a ledge. The clip has no hang
  and this pass adds none.
- **No climb-down or drop-over.** One direction: up.
- **No ledge-to-ledge chaining.** Each mantle ends in `Locomotion`; a second one is a fresh
  jump and a fresh detection.
- **No low vault.** Waist-height obstacle traversal is a different clip and a different feel.
- **The three tall blocks are not climbable.** 4.2 / 8.6 / 13.3 m — walls.
- **No capsule shrink, no crouch idle.** Unrelated, unscheduled (as the crouch and slide specs
  already say).
- **No climbable-surface layer or tag.** Any collider in the band works; a real level adds the
  layer when it needs to exclude something.
- **No prompt.** The mantle fires automatically near a ledge, but nothing marks which geometry
  is climbable — a player still learns it by jumping near a wall. Acceptable for a trial scene.
- **No knife-edge landing check.** The forward+down probe confirms an edge, not that the top is
  wide enough to stand on. shell 2 is ~9 m wide. A second down-probe at the landing point is
  the cheap add if a real level has narrow tops.
- **No mantle from the ground.** Airborne trigger only.

## Test coverage

`tests/test_pilot9_climb.gd`, headless, no play — pointed at the seams that fail silently.

- `climb_up` is in the library, `LOOP_NONE`, ~1.15 s, and every track resolves to a real bone
  on the retargeted rig.
- `climb_up`'s `Hips` **Z and Y are both locked** to their first key (the pose is in place),
  and **X is not** (the sway survives). This is the inverse of the old
  `test_the_climb_clip_keeps_its_root_motion` — see below.
- `climb_motion` exists, is a normalised curve spanning 0..1 on each axis, is monotonic on Y
  (a mantle only goes up), and its endpoints agree with `climb_rise` / `climb_reach`.
- `climb_rise` ≈ 1.78 m and `climb_reach` ≈ 0.48 m, within a wide tolerance — a tight one just
  breaks on the next re-export.
- `climb_duration` matches `climb_up`'s raw length exactly (the two-clocks seam).
- `climb_speed` > 1, and the `climb` state's `timeline_length` equals
  `climb_duration / climb_speed` with `use_custom_timeline` and `stretch_time_scale` set —
  the two clocks are sped up by the same factor (risk 1).
- The `climb` state exists, plays `climb_up`, and is a plain `AnimationNodeAnimation` (no
  `TimeScale` node — the speed-up is the custom timeline, risk 1).
- The three transitions exist, fire on the right expressions, are `ADVANCE_MODE_AUTO`, and
  `fall -> climb` / `jump -> climb` are priority 0.
- The controller exposes `is_climbing` (starts false) — an `advance_expression` naming a
  property that does not exist never fires and never complains, which is how the crouch broke
  once.
- `frozen` clears `is_climbing`.
- The qualify-a-hit predicate: a mock hit at h = 1.8 m with an up normal qualifies; h = 1.2 m,
  h = 2.6 m, and a 45°-tilted normal at h = 1.8 m each do not.
- The headroom probe: with a blocker above the projected landing point, the mantle is refused.
- `climb_up` **is** now in the state machine (inverse of the old
  `test_the_climb_clip_is_imported_but_not_wired`).

### Two assertions leave `tests/test_pilot9_slide.gd`

This pass invalidates two tests that guarded `climb_up`'s parked state:

- `test_the_climb_clip_keeps_its_root_motion` (asserts `Hips` Z still travels) — **removed**;
  its inverse ("Z and Y are locked") is in the climb test.
- `test_the_climb_clip_is_imported_but_not_wired` (asserts no `climb` state) — **removed**;
  its inverse is in the climb test.

`test_the_climb_clip_is_lifted_out_of_the_glb` (library presence, loop mode, length) stays —
it is still true and not climb-pass-specific.

**What automated checks cannot establish:** whether the catch snap reads as a grab or a
teleport, whether the arc visibly clears the lip, whether the exit stand-up is smooth, whether
timing the `jump` near the apex feels like skill or like fighting the controls, and whether
losing the double jump to a mantle you did not want is annoying near the wide face of shell 2.
Those are the user's on play — jump at shell 2 in `trial.tscn` and mantle up.

## Build order

1. **`trial.tscn`** — `TrainingV` instance scale → 1.0. Reimport `TrainingV.glb`
   (`map_import.gd` gives it trimesh collision) per `docs/reimport.md`.
2. **`scripts/pilot9.gd`** — detection probes, `_handle_climb()`, `_apply_climb_motion()`, the
   entry snap, `is_climbing`, the buffered jump, the `collision_shape` reference and toggle.
   The ledge probe runs every airborne frame in `_handle_gravity_and_jump()`, ahead of the
   jump-press handling.
3. **`scripts/pilot9_build_scene.gd`** — `_ensure_climb_motion()` (bake the `Curve3D` + rise +
   reach + hand offset + `climb_speed`, lock Z and Y), `_ensure_climb_state()` (state +
   transitions + the clip's custom timeline at `climb_up.length / CLIMB_SPEED`). Add the baked
   property names to the read-back guard list. `GLB_CLIPS` already carries `P_climbing`.
4. **`scripts/pilot9_animation.gd`** — expected no change (plain state, like the slide). Noted
   so its absence from the diff is not a surprise.
5. **Rebuild** `scenes/pilot9.tscn` — `godot --headless --path . --script
   scripts/pilot9_build_scene.gd` (swap mode; the state is builder-owned and survives
   `--fresh`).
6. **Tests** — `tests/test_pilot9_climb.gd`; delete the two assertions from
   `tests/test_pilot9_slide.gd`; run the suite.
7. **`docs/reimport.md`** — a section 11 for the climb, next to the slide's section 10.
8. Hand to the user to play. Worklog after. Nothing committed until it is driven.
