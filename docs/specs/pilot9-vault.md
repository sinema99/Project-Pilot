# Spec: pilot9's vault

> **Status:** agreed 2026-09-27 (grilled); built 2026-09-27, played 2026-09-28 - feels good. See *Built* at the end.
> **Scene:** `scenes/pilot9.tscn`, played in `scenes/trial.tscn`.
> **Clip:** Mixamo *Jumping* - `~/Downloads/Jumping.fbx` (downloaded 2026-09-27 19:16).
> **Test bed:** a new vault lane on the jump grid platform (`scripts/jump_grid.gd`).
> **Follows:** `docs/specs/pilot9-climb.md` (the path-driven, hand-pinned bake this reuses) and
> `docs/specs/pilot9-slide.md` (root motion baked to curves, clip locked in place).

## Problem statement

pilot9 has no answer to a waist-high obstacle. Running into a crate just stops him, jumping
clears it with a floaty hop, and the mantle only fires in the air for lips 0.9-1.9 m above his
feet. In a parkour game a low wall should be something you go over at full speed.

The user downloaded a vault from Mixamo and asked for it to be wired **without a Blender pass**.
Every clip pilot9 has so far arrived inside `pilot9.glb` as a `P.`-prefixed Blender action. This
is the first to come straight from an FBX.

## The clip

Measured in a scratch Godot project (Godot 4.6.2 FBX import, no retarget), before any decision
was taken:

- **Skeleton:** standard Mixamo, 25 bones, `mixamorig_*` names - **identical** to the names
  `assets/pilot9.glb.import`'s BoneMap already maps. No mesh in the file.
- **One clip,** `mixamo_com`, **1.2 s**, 21 tracks. **Not In Place.**
- **Hips travel:** 5.37 m forward (Z -0.07 → 5.30), Y 0.80 → peak 1.58 → 0.92. That is
  **4.47 m/s**, close to pilot9's run (5.0).
- **It is a real hand-plant vault.** Both wrists plant at **y ≈ 1.10-1.20 m, z ≈ 2.7-3.0 m** and
  hold there from **~0.55 s to ~0.75 s** (46-62 % of the clip) while the feet swing over at
  ~1.7-2.0 m. Authored obstacle top ≈ **1.05 m** (wrist height less a palm).
- **Takeoff** ~0.15 s (right toe leaves the ground). **Touchdown:** left toe ~0.9 s, right ~1.1 s.
- **Opens mid-stride** (left toe up behind, right foot planted), so it is built to be run into.

These are source-rig numbers (Mixamo figure: HeadTop 1.81 m, Hips rest 1.06 m). The builder
re-measures everything on the **retargeted** clip on pilot9's skeleton; the spec numbers are
for orientation, the baked numbers are the truth.

## The rule

**On the ground, press `jump` with a qualifying obstacle ahead → vault instead of jumping.**

- `jump` with no qualifying obstacle is the normal jump, unchanged.
- **Ground only.** The air belongs to the mantle and the double jump.
- A slide's jump-cancel is a grounded `jump` press, so it vaults when an obstacle qualifies.
- Off switch: `can_vault: bool = true`.
- Chosen over automatic-on-contact (user, 2026-09-27): the player stays in charge. Running into a
  box without pressing anything stops you, and pressing jump always does *something*. This is the user's 2026-09-10
  stance that player control beats animation fidelity.

## What qualifies

Checked once, on the press frame, from `pilot9.gd`. **Every number is a tunable starting value**
and gets an `@export` in a new `Vault` group.

| Check | Value | Export |
|---|---|---|
| Near face ahead of his feet | **0.5-3.0 m** | `vault_reach_min`, `vault_reach_max` |
| Top height above his feet | **0.5-1.3 m** | `vault_band_min`, `vault_band_max` |
| Approach off square | **≤ 45°** | `vault_max_angle` |
| Top depth (near face to far edge) | **≤ 1.5 m** | `vault_max_depth` |
| Top surface slope | ≤ 30° (same as the mantle's lip) | `vault_max_top_slope` |
| Landing floor below start height | within **3.0 m** down, not more than 0.3 m up | `vault_max_drop` |

### The probes

1. **Face ray** - from **0.3 m** above his feet (under `vault_band_min`, the same reason the
   mantle's ray sits under its band), along his **facing**, length `vault_reach_max` + capsule
   radius. Must hit a static body. The hit distance, minus the capsule radius, must be in the
   reach window. The hit normal is the **face normal**. The angle between `-normal` and his facing
   must be ≤ `vault_max_angle`.
2. **Top ray** - straight down from `vault_band_max + 0.3` m above his feet, **0.15 m past** the
   face along `-normal`. It must hit an up-facing surface in the height band. That hit is the
   **top edge**: the point the hands will be pinned to.
3. **Depth rays** - down rays stepped along `-normal` from the top edge, every 0.25 m out to
   `vault_max_depth + 0.25`. The first one that misses the top (no hit, or a hit more than 0.3 m
   below it) marks the **far edge**. If every step still hits the top, it is **too deep → normal
   jump**. Too-deep geometry is a platform you jump onto, and at 3.0 m his jump clears a 1.3 m
   box easily.
4. **Landing ray** - down from the projected landing point (far edge + the clip's post-plant
   travel, measured by the bake), looking for a floor within `vault_max_drop` below his start
   height and no more than 0.3 m above it. Missing, or too high, → normal jump.
5. **Clearance** - a capsule shape-test at the **apex** (over the top edge, feet at top + the
   clip's baked foot clearance) and at the **hand-release pose**. Either one overlapping → normal
   jump. This keeps him from vaulting into a ceiling, a second wall right behind the first, or a
   top that turns out wider than the depth rays saw.

Any static collider qualifies. There is no vaultable layer, just like the mantle. The height,
depth and angle checks are the filter.

The qualify decision is pure math over the probe results (band, angle, depth, drop) and is
unit-tested as such, separately from the raycasts.

## Motion

Same shape as the mantle: the clip's Hips travel is baked into curves, the clip is locked in
place, and the controller drives the body along the curves.

### Entry

- **Facing snaps to `-normal`**, straight across the obstacle whatever the approach angle, written
  into the turn-to-face model the same way `_start_climb()` writes the wall normal.
- The travel direction for the whole vault is `-normal`, flattened.
- **Short 0.1 s cross-fade in**, not the mantle's hard cut. The clip opens mid-stride and he is
  arriving from a run, so a fade reads as continuous where a cut would pop. (The mantle hard-cuts
  because its first frame is a hang it has to snap to. This one does not.)

### Speed

- **Entry speed** `v` = his horizontal speed along the travel direction on the press frame,
  floored at **run speed** (`speed`, 5.0). From a standstill or a walk it plays at run pace,
  because a slowed version of a mid-stride clip looks like wading.
- **Time scale** = `v / clip_speed`, where `clip_speed` is the baked authored travel ÷ duration
  (~4.47 m/s). At sprint (7.5) that is ~1.68×, a ~0.72 s vault.
- **Exit speed = entry speed** along the travel direction. `sprint_toggled` is left alone, so a
  sprint that was on stays on. The vault never costs momentum.

### Path

The bake splits the clip at the **hand plant** (the first frame both wrists are down and
stationary):

- **Run-up (clip start → plant): warped.** Horizontal travel is remapped so that at the plant
  frame the hands are exactly on the detected **top edge**. The authored run-up covers ~2.7 m, so
  a press at 2.5 m plays close to as authored, and a press at 0.5 m squashes it into a short hop
  onto the hands.
- **Plant → release: hands pinned.** Same method as the mantle's `_climb_path()`: the path is
  anchored to the wrists, not the Hips, so retarget sag cannot lift the hands off the top.
- **Release → end: as authored,** scaled only by the time scale.
- **Height:** the Y curve is scaled by `detected_top / authored_top`, so a 0.5 m wall gets a
  flatter arc and a 1.3 m wall a taller one. The hands meet the top at every height in the band.
  (The mantle does the same with `_climb_detected_rise`.)

### Collision

- **Off from the press to hand release.** He is on a scripted path over an edge, exactly the
  mantle's reason.
- **On from hand release to the end.** The rest of the curve is fed through `move_and_slide()`.
  After release he is past the top (the clearance check proved the release pose is clear), so
  anything unexpected (a cancel, a lower landing than predicted) is ordinary physics.

### Exit

- Hands back to `Locomotion` on touchdown after release (`is_on_floor()`), or at the clip's end,
  whichever comes first, carrying the exit speed as horizontal velocity.
- If the landing is lower than the start (a vault off an edge), the clip's end hands off to
  `fall` instead, and gravity takes over from there at the exit speed.

## Control

| Window | `jump` | `crouch` | Stick |
|---|---|---|---|
| Press → hand release (~62 %) | **buffered** | buffers a slide | ignored |
| Release → touchdown | **cancels now**, full floor jump | buffers a slide | ignored |
| On exit | buffered press fires on the release frame | slide if `_can_start_slide()` | normal |

- A buffered `jump` fires **on the release frame**, not the landing, so you can go straight into
  a jump over the next gap. A jump cancelled out of the vault spends the **floor jump**. The double
  jump stays available, so a vault → jump → double jump chain works.
- The crouch buffer uses the same rules as the land-and-slide buffer (`_slide_buffered`). It is
  spent on the exit frame, and it only slides if `_can_start_slide()` agrees.
- **No steering.** You go straight over, like the mantle.
- Dash during a vault: **refused** (a scripted path, the same treatment as the mantle).

## Animation

- **New state `vault`**, owned by the builder (`_ensure_vault_state()`), like `climb`. Editor
  edits to it are wasted work.
- The controller sets `is_vaulting` and drives the clip's playback position from its own
  normalised vault time, so the time scale and the warp stay in step with the body.
- **Staff hold:** nothing to do. `ItemHolder.ARM_OVERRIDE_STATES` is an allow list and `vault`
  is not on it, so the drawn arm lets go for the vault automatically.
- **Camera:** sway and the landing dip are left as they are. If the release → touchdown part
  registers as a landing through `is_on_floor()`, the dip fires like any other landing. The build
  confirms whether it does, and reports rather than forcing it.

## The asset pipeline (no Blender)

1. **Copy** `~/Downloads/Jumping.fbx` → `assets/pilot9_vault.fbx`. The downloaded original stays
   in Downloads.
2. **`assets/pilot9_vault.fbx.import`** gets the BoneMap from `assets/pilot9.glb.import` verbatim
   (same `SkeletonProfileHumanoid`, same `mixamorig_*` targets). The subresource key is the
   **FBX's** skeleton path. The scratch import put the `Skeleton3D` at the scene root's direct
   child `Skeleton3D`, not `Armature/Skeleton3D`. The GLB gotcha in `docs/reimport.md` applies in
   reverse: the wrong key **silently no-ops**. The build verifies the retarget happened by
   checking that the imported track paths read `%GeneralSkeleton:<ProfileBone>` /
   `Skeleton3D:<ProfileBone>`, not `mixamorig_*`.
3. **Builder:** a new `FBX_CLIPS` entry, lifted by a loader beside `_ensure_glb_clips()`:
   `"res://assets/pilot9_vault.fbx"` → clip `mixamo_com` → `vault`, `LOOP_NONE`. If the
   retargeted tracks do not already address `%GeneralSkeleton`, the loader rewrites the node
   path. This is the one thing the GLB route got for free.
4. **`_ensure_vault_motion()`** bakes, onto `scripts/pilot9.gd` (all `BAKED`, never hand-edited):
   - `vault_motion_y`, `vault_motion_z`: normalised Hips travel curves, three segments as in *Path*.
   - `vault_duration`, `vault_travel`, `vault_clip_speed`.
   - `vault_plant_time`, `vault_release_time`: normalised, measured off the wrists.
   - `vault_top_height`: authored top (wrist height at plant less a palm offset).
   - `vault_plant_reach`: Hips-start → hands, horizontal.
   - `vault_post_travel`: hands → landing, used by the landing ray.
   - `vault_foot_clearance`: lowest toe height above the top while over it.
   Then it locks the clip's Hips X/Z (and Y, as the mantle does).
5. `docs/reimport.md` gets a section: "adding a clip from a loose FBX" (steps 1-3), so the next
   Mixamo download does not need Blender either.

## Test bed: the vault lane

Generated by `scripts/jump_grid.gd` like everything else on the platform, placed beside the
existing rows (exact placement decided at build).

- **Thin walls, 0.4 m deep,** at **0.5 / 0.7 / 0.9 / 1.1 / 1.3 m**: every step of the band, one
  lane each, each with a run-up long enough to reach sprint (≥ 8 m) and a landing strip.
- **Control 1:** a **1.5 m** thin wall. Jump press → normal jump → mantle.
- **Control 2:** a **1.1 m block, 3.0 m deep.** Jump press → normal jump, lands on top.
- Heights labelled in the platform's existing marker style, warm ramp, same as the pillars.
- The vault dials (`vault_band_min/max`, `vault_max_depth`) feed `_read_dials()`, so the lane
  moves when they do, per the platform's "measures the controller, not a copy of it" rule.

## Tests (`tests/test_pilot9_vault.gd`)

- **Qualify predicate** (pure): the band edges (0.49 / 0.5 / 1.3 / 1.31), angle 44° / 46°, depth
  1.5 / 1.75, drop 3.0 / 3.1, landing 0.3 above / 0.4 above.
- **Bake:** curves present, `vault_plant_time` < `vault_release_time`, release in ~0.55-0.70,
  clip locked (Hips X/Z constant in the library copy), `vault` state exists in the tree.
- **Retarget:** the `vault` clip's tracks address `%GeneralSkeleton`, not `mixamorig_*`.
- **Real vaults, headless**, over each of the five lane heights at walk / run / sprint:
  - ends past the wall, on the floor, not inside it;
  - exit speed == `max(entry, speed)` within 0.1 m/s;
  - wrists within 3 cm of the top edge through plant → release (the mantle hand probe's standard,
    loosened for the warp).
- **Controls:** the 1.5 m wall does not vault. The deep block does not vault. Pressing 3.5 m out
  does not vault. Approaching at 50° does not vault.
- **Buffers:** jump pressed before release fires on the release frame. Crouch while sprinting
  exits into `slide`.
- **Staff:** drawn staff, the arm target is 0 while in `vault`.
- The existing suite stays green (the normal jump and the mantle are unchanged when nothing
  qualifies).

## Out of scope

- **Vaulting onto** a deep top: it is a normal jump, and that is deliberate (Q3).
- **Vaulting in the air.** The mantle owns the air.
- **Steering** during the vault.
- **Other vault styles** (kong, lazy, speed vault variants). One clip, one vault.
- **A vaultable layer / tag / prompt.** Deferred, not closed, same as the mantle.
- **A Blender pass** on the clip. If it ever gets one, the FBX route gives way to a `P.vault`
  GLB action and the loader entry is deleted.

## Risks

1. **The 0.5 m-press squash may look bad.** Remapping ~2.7 m of run-up into 0.5 m at run pace
   makes a very compressed hop. The fix is a dial: raise `vault_reach_min`. Judged on play.
2. **FBX retarget may not land on `%GeneralSkeleton` directly.** The GLB path got that for free
   because the clips were baked into the rig's own import. Handled in pipeline step 3 (path
   rewrite); flagged because it is the one untested link in "no Blender".
3. **Figure scale.** The Mixamo source figure (1.81 m) is shorter than pilot9 (1.96 m). The
   retargeter's `scale_base_bone: Hips` rescales the position track, and all baked numbers are
   measured post-retarget, so the band and the plant height are in pilot9's metres. Worth a check
   that the authored top reads ~1.1 m on him, not ~1.0.
4. **Band edge at 1.3 m.** A top between 1.3 and ~1.5 m gets a normal jump, and the airborne
   mantle catches it only if it enters the mantle's 0.9-1.9 m band on the way. At 3.0 m jump
   height it does, but a 1.3-1.4 m top may read as "vault refused" rather than "mantle". Judged
   on the 1.3 lane and the 1.5 control.
5. **Mid-stride entry at a standstill.** Floored at run pace, the vault from a standstill starts
   mid-stride out of idle. The 0.1 s fade softens it; if it still pops, the fallback is (C) from
   Q4: require run speed.

## Files

1. `assets/pilot9_vault.fbx` + `.import` (new).
2. `scripts/pilot9_build_scene.gd`: `FBX_CLIPS`, the FBX loader, `_ensure_vault_motion()`,
   `_ensure_vault_state()`.
3. `scripts/pilot9.gd`: the `Vault` export group, `_probe_vault()`, the qualify predicate,
   `_try_start_vault()` (checked first on a grounded `jump` press in
   `_handle_gravity_and_jump()`), `_apply_vault_motion()`, the buffers, dash refusal.
4. `scenes/pilot9.tscn`: regenerated by the builder.
5. `scripts/jump_grid.gd`: the vault lane.
6. `tests/test_pilot9_vault.gd` (new).
7. `docs/reimport.md`: "adding a clip from a loose FBX".

## Built (2026-09-27)

Everything above, with these departures and findings. Numbers are measured on pilot9's rig.

**The retarget just worked.** The FBX's `.import` takes the GLB's BoneMap under
`"PATH:Skeleton3D"`, and the clip arrives addressing `%GeneralSkeleton:<ProfileBone>` directly -
no path rewrite was needed (risk 2 closed). `_ensure_fbx_clips()` still refuses a `mixamorig_*`
track and rewrites a non-`%GeneralSkeleton` path, in case a later download differs.

**The bake (risk 3 closed):** authored top **1.08 m** on pilot9, clip speed **4.33 m/s** (5.20 m
over 1.2 s after the pin), takeoff 9 %, plant 46 %, release 61 %, touchdown 72 %.

**The hands do not plant together** - the one real departure from *Path*. On this rig the left
wrist goes down at 46 %, the right 0.07 s later and **0.38 m further along**, and the left lifts
at 54 % while the right stays down to 60 %. Both-wrists-still only overlaps for 3 % of the clip,
so "pin the wrists' midpoint" was replaced by **pin whichever wrist is down**, weighted to the
slower one where both are (`_vault_plant_window()` / `_vault_pin_weight()` in the builder).
The point put on the detected top is the midpoint of the two plant positions, placed at half
the top's depth (clamped to keep both hands on it): on the lane's 0.4 m walls the left wrist
lands 1 cm in from the face and the right 38 cm in. Measured on the drawn pose: a planted wrist
moves at most **1.6 cm**, and sits within **1.9 cm** of a palm (5 cm) over the top.

**Y after the release.** The Hips Y lock eases off between the release and the touchdown, so from
the touchdown on the clip's own Hips Y plays and his feet are on his origin; the path's height
correction eases out over the same stretch, so he always comes down at his start height.

**The effective depth limit is ~0.7 m, not 1.5.** `vault_max_depth` is still 1.5 and the predicate
still passes 1.5 (tested), but the release clearance check refuses anything deeper than ~0.7 m:
the clip lets go ~0.9 m past its hands with his origin ~0.5 m below the top, so on a deeper top
the capsule would be inside it. Sweep at 1.1 m, sprint: 0.4-0.7 vault, 0.8 / 1.0 / 1.5 jump.
If deeper tops should vault, that is a different clip (or a stretched plant), not a dial.

**Exit on touchdown or a missed floor.** Past the touchdown with no floor under him he hands to
`fall` right there rather than at the clip's end, so a vault off an edge does not hover at his
start height for the last ~0.2 s of the clip.

**Controller details the spec did not name:**
- The clip is seeked from `pilot9.gd::_process()` at the **interpolated** vault time, not the
  physics tick. Seeked from the tick, the pose ran up to one tick ahead of the drawn
  (physics-interpolated) body: 0.12 m of hand slide at a sprint.
- Floor snap is off from the release to the exit. No `move_and_slide()` runs before the release,
  so the body still believed it was standing where he pressed, and the first one after snapped
  him 0.5 m (`FLOOR_SNAP_LENGTH`) straight onto the floor.
- The height band has 5 mm of give: his feet ride the floor ~1 mm up, and the 0.5 m lane measured
  0.499 and fell off the edge.
- The apex clearance test is a 1.0 m capsule (he goes over tucked), not his 1.96 m one; the
  release test uses his own capsule.

**Camera:** the landing dip fires on **some** vaults and not others. The touchdown counts as a
landing, and the dip then goes by the capsule's downward speed against `landing_dip_min_speed`
(5 m/s) - and that speed is the post-release chase dropping the capsule onto the floor, which
varies with wall height and pace (2.3-9.2 m/s measured). It fired at 0.9 and 1.1 m at a sprint
and at 1.3 m walking or running; not on the 0.5 and 0.7 m walls (the release there is already
at floor level, so there is no airborne frame to land from). Reported, not forced - suppressing
it for vaults (or always firing a fixed small one) is a one-line call for play.

**Test bed:** a `Vaults` row on the jump grid past the rails, flush with their floor: the band in
four steps (0.5 / 0.7 / 0.9 / 1.1 / 1.3 at the shipping dials), a 1.5 m wall labelled JUMP and a
1.1 m block `vault_max_depth` x 2 deep labelled TOO DEEP. 10 m run-up, 6 m landing, 0.4 m walls.

**Tests.** `tests/test_pilot9_vault.gd` covers the predicate edges, the bake, the retarget, the
state and its parameter paths, the path maths, the staff and the dash. Real vaults need frames,
which the suite's runner does not give, so they are in **`tests/_probe_vault.gd`** (exits 1 on a
fail): all five lane heights at walk / run / sprint (past the wall, on the floor, exit speed =
max(entry, run) within 0.1 m/s, wrists within 3 cm), the four controls, a 40 degree approach,
the buffered jump (fires on the release frame), the jump cancel after it, crouch into a slide,
and the same over the real jump grid's lanes.

```bash
"/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --fixed-fps 60 --path . --script tests/_probe_vault.gd
```

**Not checkable headlessly:** how the 0.5 m squash looks (risk 1), whether the 0.1 s fade in from
a standstill pops (risk 5), and whether the staggered hand plant reads right.
