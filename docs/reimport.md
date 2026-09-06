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

---

## Finally

Run the suite, then hand the build to the user to play (they do the QA):

```bash
"/c/Users/panac/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script tests/run_tests.gd
```

Use `--quit-after 120` instead of `--script` to boot the real project headlessly and
surface scene/script load errors.
