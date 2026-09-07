# Re-importing Setsuna and the Mech

> **Purpose:** the repeatable steps for pulling a re-exported GLB from Blender into the
> Godot project. Do this from the command line — a headless reimport is faster than the
> editor and does not leave stale cached imports behind.

Last updated: 2026-09-06

---

## Why not the editor

The slow way is opening the Godot editor and letting it re-scan on focus (or re-dragging
the GLB in), then fixing bone indices and the animation tree by hand in the GUI. It is
slow and it silently keeps stale `.godot/imported/` caches. Always clear the cache and
reimport headlessly instead.

**Godot binary** (not on PATH — note the `.exe` *directory* holding the real binary):

```
C:\Users\panac\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe
```

---

## Setsuna

**Source:** `C:\Users\panac\Documents\SETSUNA.glb`
(*not* `Project_Pilot.glb` next to it — that is the old export.)
**Destination:** `assets/setsuna.glb` (holds `uid://c5g0ht33rb6mh`, referenced by `player.tscn`).

### 1. Swap the asset and reimport

```bash
cp /c/Users/panac/Documents/SETSUNA.glb assets/setsuna.glb
rm -fv .godot/imported/setsuna.glb-* .godot/editor/setsuna.glb-folding-*
"/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path . --import
```

Keep `assets/setsuna.glb.import` — it holds the uid and the `import_script/path`.

### 2. Inspect the new export first

Parse the GLB JSON chunk before trusting anything: scene roots, node names, mesh names,
animation names **and their durations**, skin weights. Never blind-copy.

- **Duration 0.0 means an unfinished clip**, not a held pose (Blender bakes every frame).
  Exception: the three crouch clips are 1.0 s of identical keys — a deliberate held pose.
  Check for motion, not just length.

### 3. Check skin weights

Every one of her ~11 disconnected boxes must be weighted **1.0 to a single bone**. If a
box is split across bones it shears when the rig moves and the Moebius outline pass inks
the whole surface (reads as pen scribble, only while animating). Rest pose stays clean, so
it never reproduces on a frozen model.

Check per *shell*, not per vertex: weld positions, union-find over triangles, then count
distinct `JOINTS_0[0]` per shell. Blender's *Limit Total = 1* does **not** fix this — it
is per-vertex. The box must be selected with `L` and assigned wholly to one vertex group.

### 4. Update the `KEEP` allow-list

`scripts/setsuna_import.gd` is the GLB's `import_script/path`; it deletes every clip not
named in `KEEP`. Two kinds of stowaway ride along:

- **`MECH.*`** — EXIA shares her Rigify metarig bone names, so the mech's clips export
  retargeted onto her rig.
- **`PLACEHOLDER*`** — dead actions renamed in Blender. Some carry real motion, so "it has
  motion" is not a test for "it is hers". The `SET ` prefix is the user's marker for hers.

**KEEP as of the 2026-09-03 export (9 clips, the whole set):** `SET IDLE` (1.0),
`SET RUN LOOP` (1.0), `SET CROUCH LOOP` / `SET CROUCH LOOP LEFT` / `SET CROUCH LOOP RIGHT`
(1.0 each), `SET JUMP LOOP` (0.5), `SET Falling` (1.0), `SET DASH` (1.0), `SET embark` (2.0).

The `START`/`END` transition clips were all deleted in Blender once crossfades worked — do
not wire or expect them.

### 5. Re-check the BoneAttachment3D bone indices

Five screen quads in `scenes/player.tscn` hang off bones by `bone_name`, but the `.tscn`
also stores a `bone_idx` that is written last and wins. Godot orders bones depth-first,
roots in child order.

Current, unchanged since 2026-09-01: `spine.002` **5**, `thigh.L` **15**, `thigh.R` **17**.
Confirm by loading the imported scene and printing `Skeleton3D.get_bone_name(i)`.

Only matters after a body rebuild — an animation-only re-export cannot move these.

### 6. Re-measure `STAND_HEIGHT` (rebuilds only)

`STAND_HEIGHT` in `scripts/player.gd` is `1.6725` (not the raw mesh top of `1.79`).
`_physics_process` rewrites the capsule and debug mesh from it every frame. Re-measure
**only after a rebuild that changes her silhouette**; `CROUCH_HEIGHT` stays `1.0` (it is
the gap she can duck under, not a fraction of her).

### 7. Rewire the animation tree (only if states changed)

`resources/setsuna_locomotion_tree.tres` (an `AnimationNodeStateMachine` on the
`AnimationTree` under `PlayerModel`) owns her skeleton; `player.gd` only feeds it. Spec:
`docs/specs/setsuna-animation-tree.md`. Six states: `IDLE`, `JUMP`, `FALL`, `RUN`
(TimeScale), `DASH` (TimeScale), `CROUCH` (BlendSpace1D over the three poses).

`SET embark` is the exception — driven directly by the vehicle handover with
`anim_tree.active = false` for the whole climb/ride/disembark; `exit_vehicle()` switches
it back on.

---

## Mech (EXIA)

**Source:** `C:\Users\panac\Documents\Mech_V1.glb`
**Destination:** `assets/Mech_V1.glb`, wrapped by `scenes/mech.tscn`, instanced as node
`EXIA` in `scenes/test_platform.tscn`.

### 1. Swap the asset and reimport

```bash
cp "C:\Users\panac\Documents\Mech_V1.glb" assets/Mech_V1.glb
rm -fv .godot/imported/Mech_V1.glb-*
"/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path . --import
```

### 2. Re-check `_subresources` in `assets/Mech_V1.glb.import`

The Blender action names carry no `.loop` suffix, so two loop-mode overrides live here:

- `MECH_idle` → `{"settings/loop_mode": 0}` (None — a power-down that must END and hold its crouch)
- `MECH_standing` → `{"settings/loop_mode": 1}` (Linear — a single held pose that loops only
  so `current_animation` keeps naming it)

`MECH.walk.loop` loops on its own; Godot's `use_name_suffixes` eats the `.loop` and renames
it `MECH_walk`. Likewise `MECH.walk.start` → `MECH_walk_start`, `MECH.turning.L` →
`MECH_turning_L`, `MECH.turning.R` → `MECH_turning_R`.

### 3. Check the import script keeps the right clips

`scripts/mech_import.gd` deletes everything not named `MECH_*` (the export carries ~14–23
stowaways — every action in the blend, retargeted onto the mech because it shares Setsuna's
Rigify bone names). Confirm the kept count still matches `EXPECTED_CLIPS` in
`tests/test_mech.gd` (**8** as of 2026-09-02).

**The clips chain by pose:**

```
MECH_idle (crouched end) -> MECH_launch (crouched -> standing) -> MECH_standing
MECH_walk_start -> MECH_walk
```

`MECH_turning_L` / `MECH_turning_R` are imported but unplayed — foot shuffles on the spot,
no yaw reaches the skeleton. `MECH_power_off` is imported but not wired into `mech.gd`.

### 4. Check the armature yaw FIRST

Read `skeleton.get_parent().transform.basis` and take `.get_euler()`.
**`basis.get_scale()` hides a rotation** — it returns magnitudes.

- If the euler is **still +90° Y**: the export is yawed a quarter turn (one `+90°` on the
  `metarig_001` node — the bones and clips are all built around a +Z nose). `scenes/mech.tscn`'s
  `Model` carries a `-90°` counter-rotation:
  `Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, 4.213517, 0.00112, 0)` (row-major: row0, row1,
  row2, origin).
- If the euler is **0**: the yaw was fixed in Blender. Delete the counter-rotation and put
  `Model` back to an identity basis: `Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ~0, 0)`.
  Two tests fail together the day this lands and say so:
  `test_the_model_faces_the_way_the_mech_walks` and `test_the_export_is_still_yawed`.

### 5. Re-measure geometry from the SKINNED mesh

`MeshInstance3D.get_aabb()` returns bind-pose bounds, and `global_transform * get_aabb()`
double-counts the armature scale (~1.73× too big). Pose the skeleton at `MECH_standing`,
then skin the vertices by hand:
`skel.global_transform * (bone_global_pose[b] * skin.get_bind_pose(b) * v)` summed over weights.

Current size: **8.40 m tall, 7.62 m across, 4.15 m deep** (soles at y = -6.609584), 26 bones.
The `metarig_001` node carries a `1.7267632` scale — this is how the mech reaches 8.4 m, and
it means **bone units are not metres**. Root motion converts via `mech.gd::travel_scale_for()`;
without it the mech moonwalks through every boot-up. Applying the scale in Blender would make
this a no-op.

Retune `scenes/mech.tscn` and the tables in `docs/specs/exia-pilot.md` if the geometry moved.
Neither 2026-09-02 re-export changed the geometry, scale, or travel numbers, so the collider,
interaction box, exit point, camera pivot and spring arm have not needed retuning.

### 6. Re-derive the mount mark if the mech moved in the blend

`EmbarkPoint` in `scenes/mech.tscn` is derived, not eyeballed — Setsuna's `embark` clip was
authored against the mech where it stands in the shared blend. The mark is a `-90°` yaw at
mech-local `(4.213517, 0, 0)`:
`Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, 4.213517, 0, 0)`.

**`4.213517` is the armature node's own Z translation**, so an export that moves the mech in
the blend moves the mark by exactly that number. `_mount_position()` then subtracts the
`MECH_idle` power-down travel (~2.17 m along the nose) so she is not placed on the front of
the chest. `scenes/mech_v2.tscn` carries an inherited copy — check that one by eye.

Three checks confirm the fit after a re-export: `embark`'s first spine frame is
bit-identical to `IDLE`'s; her spine ends at mech-local `(-0.024, 6.216, 0.954)` (a cockpit
on the centreline); her spine's final rotation is `+90°` (0 in mech space — facing out over
the nose).

---

## pilot9 (Real Controller successor)

**Source:** `C:\Users\panac\Documents\PILOT9.glb` (Mixamo blockout, 25 bones, `mixamorig_*`).
The user renamed it to caps on 2026-09-06; `sync_pilot9.ps1`'s default source path still
finds it, Windows paths being case-insensitive.
**Destination:** `assets/pilot9.glb` (holds `uid://bjw3dhc2w6y4e`). Wrapped by
`scenes/pilot9.tscn`, driven by `scripts/pilot9.gd`. Full rationale:
`docs/specs/pilot9-real-controller.md`.

Unlike Setsuna and the Mech, pilot9 is **retargeted at import** onto Godot's humanoid
profile so RC's 30 Mixamo clips (in `addons/real-controller/animations/`) play on him
unedited. That retarget is driven entirely by `_subresources` in
`assets/pilot9.glb.import`.

### 1. Sync — one command

```powershell
powershell -File tools/sync_pilot9.ps1        # add -Play to launch scenes/trial.tscn after
```

That copies `C:\Users\panac\Documents\pilot9.glb` in, clears the import cache, reimports,
swaps the rig into `scenes/pilot9.tscn`, reports the skin weights and runs the suite. The
long way is below if you need to do a step by hand.

```bash
cp /c/Users/panac/Documents/pilot9.glb assets/pilot9.glb
rm -fv .godot/imported/pilot9.glb-* .godot/editor/pilot9.glb-folding-*
GODOT="/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script scripts/pilot9_build_scene.gd
```

**The rebuild is not optional** — see step 4. Reimporting alone leaves the previous rig in
`pilot9.tscn` and the export looks like it failed.

Keep `assets/pilot9.glb.import` — it carries the uid **and the BoneMap**. A reimport that
loses that file drops the retarget silently (skeleton stays `Skeleton3D`, bones stay
`mixamorig_*`, `motion_scale` stays `1.0`, and every RC clip plays on nothing). Only ever
delete `.godot/imported/`; `sync_pilot9.ps1` refuses to run if the `.import` is gone.

### 2. The BoneMap key is the whole trick

The retarget block lives under:

```
_subresources = { "nodes": { "PATH:Armature/Skeleton3D": { "retarget/bone_map": Object(BoneMap, ...) } } }
```

**`PATH:Armature/Skeleton3D`, not `PATH:Skeleton3D`.** The bare-name key that RC's
`character.fbx.import` uses does not match a glb whose skeleton sits under an `Armature`
node — the import runs, reports nothing, and simply doesn't retarget. Map targets are the
**underscore** names (`mixamorig_Hips`), Godot 4.6's `naming_version=2` form — not the
`mixamorig:Hips` colon form.

### 3. Confirm the retarget actually landed

`tests/test_pilot9_retarget.gd` asserts all of it, but by hand the tells are: the skeleton
node is renamed **`GeneralSkeleton`** (`unique_name_in_owner` on), the 22 mapped bones are
renamed to profile names (`Hips`, `Spine`, `LeftUpperArm`, …), `motion_scale` is ~`1.06`,
and the `Armature` node's `0.01` scale + 90° X rotation is baked out to identity. The 3
`*_End` leaf bones and the below-profile toes keep their `mixamorig_` names — expected.

### 4. `scenes/pilot9.tscn` is generated — always rebuild it

RC's clips address the skeleton as `%GeneralSkeleton` (a scene-unique name), which only
resolves if the skeleton node is **owned by pilot9.tscn** — so the rig is baked into that
scene, not instanced. The mesh, skin and materials are **inlined** for the same reason: an
`ExtResource` into `res://.godot/imported/pilot9.glb-<hash>.scn` breaks when the hash
changes on the next reimport. Which means the scene holds its own copy of his geometry and
weights, and **a Blender change does not reach the game until the builder re-runs.**

`scripts/pilot9_build_scene.gd` has two modes:

| | What it does | When |
| --- | --- | --- |
| **swap** (default) | Loads the existing `pilot9.tscn` and replaces only the `character/Armature` subtree | Every re-export. Weight, mesh and rig tweaks |
| **fresh** (`-- --fresh`) | Rebuilds from RC's `character.tscn` — capsule from `PILOT_HEIGHT`, `root_node`s repointed, scripts reattached, rig `y` offset zeroed (RC's `-0.8` was for its own mesh) | Re-basing on a new Real Controller, or starting over |

**Swap preserves what you tuned in the editor; fresh discards it** — including clips added
to the AnimationPlayer library and states added to the AnimationTree. Anything that must
survive a `--fresh` belongs in the builder script, not in the editor.

Both modes print the measured mesh height next to the capsule's, and say so if they have
drifted apart. Neither resizes the capsule in swap mode — that is deliberate, so a
re-export cannot silently undo a collider you tuned by hand.

### 5. Check the skin weights

```bash
python tools/check_weights.py               # defaults to assets/pilot9.glb
python tools/check_weights.py --strict      # exit 1 if any shell spans >1 bone
```

Reports, per connected shell (the island you select in Blender with `L`), how many bones
drive it. Reads the glb container directly, so it works on a Blender export before it is
copied into `assets/`.

**pilot9 is smooth-weighted, and that is settled.** As of the 2026-09-06 export, 40 of his
41 shells span two or more bones — he came off Mixamo's auto-rigger, which paints smooth
weights. Setsuna's 1.0-to-a-single-bone rule (her step 3) is **hers alone**: confirmed
2026-09-06, the outline does not scribble on pilot9 and he is not to be re-weighted for
it. The spec's Risk 5, which asserted that rule for him, was a carried-over assumption.

The count went 40 → 41 on the 2026-09-06 arm/shoulder re-weight. That is the material
split, not a weighting accident: three slots mean a mesh that used to import as one
primitive can now import as two, and this script counts shells per primitive.

So this check is not a gate. It is for catching an *unintended* weight change between
exports — compare the shell counts against the previous run, not against zero.

### 6. Input map

`project.godot`'s `[input]` carries `forward/backward/left/right/jump/sprint/walk/crouch/`
`camera_mode_switch/look_*` for pilot9. Additive — `scripts/player.gd` reads raw keycodes,
so Setsuna is untouched.

`crouch` is **C** (physical keycode, so it survives a non-QWERTY layout) and **controller
B** (`JOY_BUTTON_B`, index 1). `ui_cancel` is on the same pad button; harmless while the
trial carries no UI, but the day a pause menu lands there, back-out and crouch fire
together and one of them has to move.

### 7. Material slots

**As of the 2026-09-06 export he has three: `main`, `secondary`, `scarf`** — flat colours,
no textures. Before that he exported with *no* material at all, and Godot's importer
handed every surface the same default white `StandardMaterial3D`.

Nothing needs wiring for this. `ApplyCelPilot9` in `scenes/trial.tscn` runs
`scripts/rendering/apply_stylized.gd` with `derive_from_surfaces = true`, which walks every
surface, reads the Blender slot name and its `albedo_color`, and stamps a duplicate of
`resources/cel_character.tres` carrying that colour. One cel material per slot, minted per
pass, so adding a fourth slot in Blender is a re-export and nothing else.

Two things to know when a slot is added or renamed:

- The colour crosses over **untouched**. The importer has already sRGB-encoded glTF's
  linear `baseColorFactor` and the shader's `source_color` uniform expects exactly that
  encoding. Converting it again washes everything out. Check against the export's own
  `baseColorFactor`, never by eye.
- A slot needing more than a colour (a heavier `dot_density`, a raised `shadow_floor`) goes
  in `slot_overrides` on that node, keyed by the trimmed slot name. A hand-authored
  material there wins over the derived one.

A slot with no usable imported material falls back to the base swatch and says so with a
`push_warning`. Seeing that for pilot9 means the export lost its materials again.

### 8. Adding a clip

There are two routes in, and **which one you want depends on where the clip was authored**.

#### Route A — authored in Blender, riding in on pilot9.glb (the usual one)

This is what the user does: download the Mixamo FBX, import it into `PILOT9.blend`, rename
the action, export. The clip arrives inside `pilot9.glb` and is retargeted by the same
BoneMap as the rig, which means **its track paths come out addressing
`%GeneralSkeleton:<ProfileBone>` already** — identical to what RC's own clips address. No
rewriting, no `.res`, no second `.import` to keep in sync.

The catch is that `scenes/pilot9.tscn` only takes `character/Armature` from the GLB and
drops its AnimationPlayer, so the clip has to be lifted across. `GLB_CLIPS` at the top of
`scripts/pilot9_build_scene.gd` is that list, and `_ensure_glb_clips()` runs it in **both**
builder modes, so a clip added there survives a `--fresh`:

```gdscript
const GLB_CLIPS := {
	"P_crouchwalk": {"as": &"crouch_walk", "loop": Animation.LOOP_LINEAR},
	"P_sitting":    {"as": &"sit_down",    "loop": Animation.LOOP_NONE},
}
```

Adding one is a single row. Three things to get right:

1. **The key is the imported name, not the Blender action name.**
   `nodes/use_name_suffixes` rewrites `P.crouchwalk` as `P_crouchwalk` (same rule that
   turns the mech's `MECH.walk.loop` into `MECH_walk`). Confirm it in the Import dock's
   Advanced panel — that is the part that varies. A key that matches nothing fails the
   build loudly and prints the names the GLB does carry.
2. **Set `loop` deliberately.** The importer defaults *every* clip to `LOOP_NONE` no matter
   what it contains, so a cycle that is not listed as `LOOP_LINEAR` plays once and freezes
   mid-stride.
3. **Tick In Place on Mixamo** for anything locomotive. The code moves the body. Check it
   by reading the Hips translation track's first and last key — equal means in place.
   `P.crouchwalk` is (its hips return to within 0.4 mm), and it loops well: worst
   first-vs-last bone rotation across the whole clip is 1.9°.

   **The exception is a one-shot verb with its own speed curve**, where the root motion is
   worth more than the convenience — a slide, a mantle, a dodge. `P.slide` came in
   *without* In Place, and its 7.8 m of Hips travel is now what drives the body; see
   section 10. If you take that route the clip still has to be locked in place before it
   reaches the state machine, because **a root-motion track cannot be cross-faded** — it
   drags the mesh across the whole fade. The builder does both halves.

#### Route B — a Mixamo FBX dropped straight into the project

Only worth it when the clip is not going through Blender at all.

1. **Download** as **FBX Binary**, **Skin: Without Skin**, 30 FPS (matching
   `animation/fps=30`), **In Place** ticked for anything locomotive.
2. Drop it in, e.g. `assets/anim/crouch_idle.fbx`. Godot 4.6 imports FBX natively via
   ufbx; no FBX2glTF. (RC's own `character.fbx` proves it works in this project.)
3. **Copy the `retarget/bone_map` Object** out of `assets/pilot9.glb.import` into the new
   `.fbx.import`'s `_subresources`. The *key* differs: a Mixamo FBX has no `Armature`
   wrapper, so it is **`PATH:Skeleton3D`**, exactly as in
   `addons/real-controller/character.fbx.import` — not pilot9's
   `PATH:Armature/Skeleton3D`. Wrong key, and the import runs, reports nothing, and does
   not retarget.
4. **Save the clip as a `.res`** so the library can reference it:

   ```
   "animations": { "mixamo_com": { "save_to_file/enabled": true,
     "save_to_file/path": "res://assets/anim/crouch_idle.res",
     "settings/loop_mode": 1 } }
   ```

   Mixamo names every clip `mixamo.com`; confirm the imported name in the Import dock's
   Advanced panel before typing the key — that is the part that varies.
5. **Register it** in the AnimationPlayer library. That library is a `SubResource` inside
   the *generated* `pilot9.tscn`, so an entry added in the editor survives a swap but not
   a `--fresh`. Put it in `scripts/pilot9_build_scene.gd` to make it permanent.

#### Either way, the clip still does nothing until it is wired

A clip in the library needs an AnimationTree state and code in `scripts/pilot9.gd` asking
for it. Steps above are minutes; this is the actual feature.

Check duration and track resolution afterwards — `tests/test_pilot9_retarget.gd` already
fails loudly on a zero-length clip or a track that resolves to no bone, which is the
silent failure worth fearing: the state machine transitions happily while pilot9 stands in
T-pose.

### 9. The crouch

Built 2026-09-06 on `P.crouchwalk`. `scripts/pilot9_build_scene.gd::_ensure_crouch_state()`
owns the whole graph, so it is rebuilt on every sync and an editor edit to it will not
survive — change the builder, not the scene.

**Toggle, not hold.** `crouch` flips `pilot9.gd::is_crouching`, and the AnimationTree reads
that property *directly* through `advance_expression` (`advance_expression_base_node` is
the controller). That is the seam to be careful with: **an expression naming a property
that does not exist never fires and never complains.** Renaming `is_crouching` breaks the
crouch silently.

**The state is a TimeScale, because there is no crouch idle.** pilot9 has a crouch *walk*
and nothing to stand still in, so the `crouch` state is a two-node blend tree — the clip
through an `AnimationNodeTimeScale` — and `scripts/pilot9_animation.gd::_drive_crouch()`
eases the scale to 0 when he is not moving. He holds the pose he stopped on instead of
marching on the spot. **A Mixamo "Crouch Idle" would let this become a real blend and the
TimeScale can go the day it exists.** Same silent-seam warning: `AnimationTree.set()` on a
parameter path that does not exist is a no-op, not an error, so the path is a `const` on
both sides and `tests/test_pilot9_crouch.gd` asserts the two still meet.

Transitions, and why the priorities:

| From | To | Expression | Priority |
| --- | --- | --- | --- |
| `Locomotion` | `crouch` | `is_crouching` | 1 |
| `crouch` | `jump` | `velocity.y > 0` | **0** |
| `crouch` | `fall` | `not is_on_floor() and velocity.y <= 0` | 1 |
| `crouch` | `Locomotion` | `not is_crouching` | 2 |
| `jump_land` | `crouch` | `is_crouching` | **0** |

Pressing jump while crouched **stands him up and jumps** — `pilot9.gd` clears
`is_crouching` and sets `velocity.y` on the same frame, because there is no crouch-jump
clip and a dead jump key reads as broken input. That makes `-> jump` and `-> Locomotion`
both eligible on that frame, so jump has to outrank the stand-up or the leap plays as a
stand-up. `jump_land -> crouch` exists because `jump_land`'s only other exit needs
`velocity.length() > 0.2`; without it, landing still while crouched strands him standing.

`crouch_speed` is **1.6 m/s** (below `walk_speed`'s 2.5), and crouching suppresses both
`is_sprinting` and `is_walking` so `pilot9_animation.gd` stops feeding the walk/run blends
underneath the state. The number is matched by eye against the clip's own cadence — change
one without the other and he skates or moonwalks.

**Not done, and deliberately:** the capsule does not shrink. Crouching is a pose and a
speed right now, not a duck-under-geometry mechanic, and there is nothing in
`scenes/trial.tscn` low enough to duck under. `pilot9_build_scene.gd` never resizes the
capsule in swap mode by design, so that work belongs in the builder's `PILOT_HEIGHT` path
whenever it is wanted.

`P.sitting` imports alongside as `sit_down` (`LOOP_NONE`) and is **deliberately unwired** —
it is the climb-into-the-cockpit clip for a mech handover that does not exist yet.

**`AnimationTree.deterministic` has to stay ON, and a GLB clip is why.** Real Controller
ships the tree with it *off*, which is not Godot's default. Off, a bone whose blend weight
reaches zero — meaning no playing clip animates it — keeps whatever value it last held
instead of returning to rest. That is harmless while every clip animates the same bones,
which is true of RC's own 27 and stopped being true the moment `crouch_walk` arrived out of
`pilot9.glb`: it rotates `UpperChest` ~22° and no RC clip touches that bone. Standing up
blended the crouch out of every shared bone and left `UpperChest` at its crouched angle —
**pilot9 walked away from every crouch tilted forward, permanently, until the scene
reloaded.** `pilot9_build_scene.gd::_ensure_deterministic_blending()` now turns it back on
in both modes, and `tests/test_pilot9_crouch.gd` asserts the invariant (any track missing
from some clip is only safe under deterministic blending). The cost: while crouched, bones
the crouch clip does not animate — both wrists — sit at rest rather than freezing on the
pose idle left them in. Expect the same trap from every future mixed-source clip; it is not
crouch-specific.

### 10. The slide, and the clip that drives it

Built 2026-09-06 on `P.slide`. Full rationale in `docs/specs/pilot9-slide.md`; this is the
part that matters when a re-export lands.

**`crouch` pressed at a sprint means slide, not crouch.** One key, one decision point
(`pilot9.gd::_handle_crouch_and_slide()`), and the press is never spent twice. Jump cancels
a slide; leaving the floor ends one; there is a 0.4 s cooldown. **It steers** — the stick
turns a slide at the same `rotation_speed` a run turns at.

**The clip is cut to its first 75 of 93 frames** by `_trim_slide()`, before anything else
reads it. The tail it removes is the end of the run-out, where he is already upright and
just running; cutting it hands control back ~0.3 s earlier, which is the whole of the
change in feel. Two things about that cut:

- It is **not** just `Animation.length`. Godot's interpolation ignores keys past the length
  rather than clamping to it, so moving the length alone leaves every track holding its
  last in-range key — a frozen tail on a cut made to remove one, silently costing 0.2 m of
  travel. The boundary pose is sampled first, the keys past it dropped, and the pose
  re-keyed exactly on the new end.
- Frame numbers are quoted at **60 fps** (Blender's timeline, hence `SLIDE_SOURCE_FPS`),
  not the 30 Hz the exporter sampled at. Both describe the same clip.

**Nothing in the code says how fast it goes.** The clip was exported *without* In Place, so
its `Hips` walk +6.462 m over the trimmed 1.250 s — and the shape of that walk is the
animation: in at ~8 m/s with his feet planted, down to 2.2 m/s on the floor, back up and
running out.
`_ensure_slide_motion()` bakes that into a normalised `Curve` on the controller
(`slide_motion`, plus `slide_duration` and `slide_distance`) and
`pilot9.gd::_apply_slide_velocity()` differentiates it each frame. The two windows with
planted feet are the only two where a speed mismatch shows, and both are exact because the
number driving the body is the animator's own.

**Then the clip is locked in place** — Z only, so the hip drop and the sway survive. This is
not optional: every transition in the state machine is an `xfade`, and a `Hips` sitting at
+7.68 m blended against a run clip's ~0 drags the mesh backwards through the whole exit
fade. `AnimationTree.root_motion_track` would handle both jobs and strips the named track
from *every* clip in the tree, so the bob would go out of all 29 of RC's. Not worth it.

Consequences worth knowing before the next export:

- **Re-authoring the action silently changes how far he slides.** That is correct — the
  bake follows the clip. But `slide_scale`, the one dial meant to be tuned in the
  inspector, is then tuned against a different distance.
- **`SLIDE_KEEP_FRAMES` is a frame count, not a fraction.** Re-author the action longer or
  shorter and the cut still lands on frame 75, which may no longer be the end of the
  run-out. The builder leaves a clip already at or under the cut alone rather than padding
  it back out.
- `slide_scale` is the **only** slide property the builder does not write, so it survives a
  swap (not a `--fresh`). `slide_motion` / `slide_duration` / `slide_distance` are
  rewritten on every sync; editing them by hand is wasted work.
- The builder **fails the build** if the clip carries less than 0.5 m of travel — i.e. if
  it comes back exported In Place. There is nothing sensible to fall back on.
- There is no `TimeScale` in the `slide` state, on purpose. The state machine plays the
  clip on its own clock and `_slide_time` runs in `_physics_process`; they agree only
  because both are real time.
- `_slide_direction` is the single heading a slide has: `_steer_slide()` turns it,
  `_apply_slide_velocity()` drives the body along it, and `_handle_character_rotation()`
  writes the mesh straight onto it. One lerp end to end — a second one anywhere in that
  path halves the turn rate and opens a gap between where he points and where he goes.

Transitions, and why the priorities:

| From | To | Expression | Priority |
| --- | --- | --- | --- |
| `Locomotion` | `slide` | `is_sliding` | **0** |
| `fall` | `slide` | `is_sliding` | **0** |
| `jump_land` | `slide` | `is_sliding` | **0** |
| `slide` | `jump` | `velocity.y > 0` | **0** |
| `slide` | `fall` | `not is_on_floor() and velocity.y <= 0` | 1 |
| `slide` | `Locomotion` | `not is_sliding` | 2 |

Same argument as the crouch's: cancelling into a jump clears `is_sliding` on the frame it
launches, so `-> jump` and `-> Locomotion` are both eligible and the leap has to win.

`fall -> slide` and `jump_land -> slide` are the **land-and-slide buffer**
(`docs/specs/pilot9-jump-slide.md`): a `crouch` press made any time in the air is held
(`_slide_buffered`, no timer) and spent on the landing frame, when the tree is in `fall` or
`jump_land`. Priority 0 puts each ahead of its plain-landing sibling (`fall -> jump_land`,
`jump_land -> Locomotion`, both default priority 1) so the slide is entered in one fade
rather than after a frame of `jump_land`. No `jump -> slide` — the buffer is only spent once
`is_on_floor()`, so `is_sliding` can never be true in `jump`. `can_buffer_slide` is the
on/off switch and, like `slide_scale`, is never written by the builder. Note `sprint` is a
toggle (`sprint_toggled`), so the buffer's sprint condition is the toggle, not a held key.

`P.climbing` imports alongside as `climb_up` and used to sit here unwired, its root motion
left intact for whoever built the mantle. That is section 11.

### 11. The ledge mantle, and why its numbers are not the clip's

Built 2026-09-07 on `P.climbing`. Full rationale in `docs/specs/pilot9-climb.md`; this is
the part that matters when a re-export lands.

**`jump` pressed airborne with a ledge in probe range means mantle, not double jump.** The
check is intercepted ahead of the air-jump branch in `pilot9.gd::_handle_gravity_and_jump()`,
so a mantle costs no air jump and the same press away from a wall is still the double jump.
It runs to completion — **not cancellable**, because his collision shape is off and he is
being written along a path over an edge. A `jump` pressed during one is buffered and fired
on the frame after the exit snap.

**The map had to be fixed first.** `scenes/trial.tscn` was instancing `TrainingV` at an
extra **1.7574×** on top of the GLB node's own 36.1356, which put every block at 1.76× its
authored height and the one mantle-height step (**1.84 m**, "shell 2") at 3.23 m — out of
reach. The instance is scale **1.0** now. The 1.7574 was an "apply scale" that did not take
in Blender before export; a clean re-export with it applied makes that line a no-op.

**The clip is taken apart the way the slide is, on two axes instead of one.**
`_ensure_climb_motion()` bakes `Hips` Y and Z into a pair of normalised `Curve`s
(`climb_motion_y` / `climb_motion_z`) and then locks **both** axes to the first key. X is
kept — it is the lateral sway on the pull-up. The reason is the slide's: a root-motion track
cannot be cross-faded, and every transition in this state machine is an xfade.

Two things here are **not** in the slide, and both are easy to get wrong silently:

- **`motion_scale`.** The retargeter divides every position track by
  `Skeleton3D.motion_scale` (**1.0608** on this rig) and `AnimationMixer` multiplies it back
  on playback. Metres therefore need the multiply. The `Hips` track reads +1.782 m of rise;
  the mesh actually rises **+1.890 m**. (The slide's bake does **not** apply this — see the
  note at the end of this section.)
- **The clip's own travel is not what the body should travel.** FK'd on frame 1, his hand
  contact sits **1.583 m** above his origin; FK'd on the last frame his soles sit **0.259 m**
  above it. So a catch that puts his hands *on* the lip and a landing that puts his soles
  *on* the top are **1.324 m** apart — not the 1.890 m the `Hips` walk. Driving the authored
  rise finishes him about a third of a metre in the air with his hands floating over the lip
  through the middle of the pull.

  So the distances are derived from the two poses that touch geometry, and the authored
  travel is kept only for its **shape** (the curves) and for `climb_inset`. Same discipline
  as the slide — drive the body from the animator's own numbers — applied to the two frames
  that actually matter.

What is baked onto `scripts/pilot9.gd`, all rewritten on every sync:

| Property | Value today | What it is |
| --- | --- | --- |
| `climb_motion_y` / `climb_motion_z` | 65 points each | the arc, normalised 0..1 on both axes |
| `climb_duration` | 1.150 s | the clip length; the two-clocks seam |
| `climb_rise` | 1.324 m | metres the body rises, hands-on-lip to soles-on-top |
| `climb_reach` | 1.104 m | metres the body travels forward over the same span |
| `climb_inset` | 0.514 m | how far in from the edge he lands — the level-design contract |
| `climb_hand_offset` | (-0.036, 1.583, 0.593) | frame-1 hand contact in his own frame; the entry snap subtracts it from the lip |
| `climb_foot_offset` | (-0.048, 0.259, 0.002) | last-frame ground contact; the exit snap subtracts it from the landing point |

**The curves are deliberately not clamped to 0..1.** `climb_motion_y` peaks at **1.066** —
that is him pulling *over* the lip before settling onto it — and `climb_motion_z` dips to
**-0.234** at the start, the swing back before the pull. `Curve`'s default value range is
0..1 and would flatten both into a lift on rails, so the bake widens it to -1..2.

Consequences worth knowing before the next export:

- **Re-authoring `P.climbing` re-derives the arc, the rise, the reach and both contact
  offsets.** That is correct — the bake follows the clip. But `climb_inset` is the level
  contract: geometry built against 0.51 m of top is wrong after a re-export that moves it.
  Do not hand-tune any of the eight baked properties; `CLIMB_BAKED` overwrites them.
- The builder **fails the build** if the clip carries less than 1.0 m of rise — i.e. if it
  comes back exported In Place. There is nothing to fall back on.
- There is no `TimeScale` in the `climb` state, on purpose, and no tail trim either. The
  slide cuts its run-out at frame 75; the mantle's tail is the stand-up and is worth
  keeping, so the "hands back a beat early" is done by the 0.2 s exit xfade eating it.
- **The detection band is the only filter** — no climbable layer, no tag. Any static
  collider with an up-facing top between `climb_band_min` (0.9 m) and `climb_band_max`
  (1.9 m) above his feet offers a mantle. In `TrainingV` that is shell 2 and nothing else,
  until a double jump puts him within 1.9 m of the 4.19 m block's top.
- **`climb_probe_height` must stay below `climb_band_min`.** The forward ray has to pass
  *under* the lip it is looking for; cast at or above it, it sails over the top of every
  wall in range and nothing is ever climbable. Silent when broken, so
  `tests/test_pilot9_climb.gd` asserts it.
- The probe numbers (`can_climb`, the band, the ray heights, the slope cutoff, the headroom)
  are inspector dials the builder never writes, like `slide_scale`.

Transitions, and why so few:

| From | To | Expression | Priority | xfade |
| --- | --- | --- | --- | --- |
| `fall` | `climb` | `is_climbing` | **0** | 0.08 |
| `jump` | `climb` | `is_climbing` | **0** | 0.08 |
| `climb` | `Locomotion` | `not is_climbing` | 0 | 0.20 |

Both airborne states enter it: depending on where in the arc the press lands the tree is in
`jump` (still rising) or `fall` (past apex). The 0.08 s entry is near-hard on purpose — the
snap has already teleported him to the lip and turned him to the wall, and a longer fade
blends the old airborne pose across that teleport and reads as a lurch. There is exactly one
exit: no `climb -> fall` (collision is off, he cannot leave the floor mid-mantle) and no
`climb -> jump` (not cancellable; the buffered jump fires from `Locomotion` afterwards).

**Known, not fixed: the slide's bake does not apply `motion_scale`.** `slide_distance` is
6.462 m off the raw `Hips` track while the mesh actually travels 6.462 × 1.0608 = 6.855 m,
so the slide under-travels its own animation by ~6%. It is a one-line change in
`_ensure_slide_motion()`, but it moves the distance the feel was tuned against (and
`slide_scale` with it), so it is left for a pass that can be played rather than folded into
this one.

---

## Finally

Run the suite, then hand the build to the user to play (they do the QA):

```bash
"/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script tests/run_tests.gd
```

Use `--quit-after 120` instead of `--script` to boot the real project headlessly and
surface scene/script load errors.
