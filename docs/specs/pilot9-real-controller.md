# Spec: pilot9 on Real Controller

> **Status:** agreed 2026-09-05, not yet built.
> **Scene:** `scenes/trial.tscn`. **Character:** `assets/pilot9.glb`.
> **Upstream:** [fdemir/real-controller](https://github.com/fdemir/real-controller) (MIT, Godot 4.6).

## Problem statement

Setsuna's locomotion is hand-animated. Every new move — slide, crouch strafe, a second idle —
costs a Blender session, and the 2026-09-03 `SETSUNA.glb` export showed what that dependency
does under pressure: nine clips shipped, five of the ones the animation tree was built around
disappeared, and `SLIDE` still has no clips at all, so C at a sprint ducks instead of sliding.
The movement code is not the bottleneck. The animation supply is.

The user's ask: adopt a movement system that **arrives with its animations**, so new moves come
from Mixamo rather than from Blender.

Two candidates were read end to end before choosing.

**AMS (`ywmaa/Advanced-Movement-System-Godot`)** — 603 stars, the obvious pick by reputation, and
rejected on the facts. Last commit **2024-10-03**; targets Godot 4.3 against this project's 4.6.2;
ships `debug_draw_3d`, a GDExtension compiled for 4.3, which `PoseWarping.gd` and
`PlayerController.gd` reference unconditionally. Decisively: its `Character.glb` was hand-reoriented
in Blender with **no BoneMap** — `Hips` rest rotation is `(0.013, -0.477, 0.013, 0.879)`, not a
Mixamo rest — so its 19 clips are welded to that one rig. Getting them onto pilot9 would mean
building retarget setups on both sides. Its genuinely good parts (`PoseWarping`, a
`SkeletonModifier3D` doing slope warping and foot IK — squarely relevant to a slope-traversal game)
remain liftable later, once bones are on the profile.

**Real Controller (`fdemir/real-controller`)** — chosen. MIT, actively maintained (Dec 2025), README
states Godot 4.6, and `character.fbx.import` carries this:

```
"PATH:Skeleton3D": { "retarget/bone_map": Object(BoneMap, "profile": SkeletonProfileHumanoid,
   "bone_map/Hips": &"B-hips", "bone_map/Spine": &"B-spine", "bone_map/Chest": &"B-chest", ... ) }
```

Its character is imported **through Godot's humanoid retargeting profile**. Its clips are therefore
authored against profile bone names on a profile-normalised rest — the standard any Mixamo rig can
be brought onto. That is the whole reason it wins: not its feature list, which is thinner than AMS's,
but that it speaks the language that makes future animation packs drop in.

## Decisions (from the user, 2026-09-05)

- **Successor, not an experiment.** If this works, pilot9 becomes the main character and Setsuna is
  left behind. No migration path is being designed for her — explicitly, "it's not gonna happen."
- **Nothing is deleted in this pass.** `scripts/player.gd`, `scenes/player.tscn`,
  `scenes/test_platform.tscn` and Setsuna are untouched. Their fate is decided after the user drives
  pilot9.
- **pilot9 stays a Mixamo rig.** Retargeting happens at import, not by re-rigging, so Mixamo clips
  for crouch/slide/dash can be added later through the same path.
- **Stock Real Controller feel.** None of `player.gd`'s dash, slide, double jump, apex-hang bands or
  slope pitch is ported on day one.
- **Blender fixes are acceptable; animating is not.** If the retarget comes out wrong, a Blender
  correction to pilot9 is fine. Hours of hand-animation is the thing being avoided.
- **Cel look off for the first look**, flipped on immediately after.
- **Spec first, then build, then the user plays it, then the worklog.**

## The rig problem

| | Real Controller's rig | pilot9 today |
| --- | --- | --- |
| Bone names | `Hips`, `Spine`, `Chest`, `LeftUpperArm` … (Godot humanoid profile) | `mixamorig:Hips`, `mixamorig:Spine`, `mixamorig:Spine1`, `mixamorig:LeftArm` … |
| Bone count | 56 (the full profile) | 25 — no fingers, no eyes, no jaw, **no `Root`** |
| Skeleton node | `GeneralSkeleton` | `Skeleton3D` (under `Armature`) |
| Armature transform | identity, metres | **scale 0.01 + 90° X rotation** |
| Hips rest | y = 0.90, `motion_scale` 0.9797 | z = −106.08 in armature space (~1.06 m); character is 1.95 m tall |
| Animations | 30 `.res`, tracks address `GeneralSkeleton:<profile bone>` | one clip, `Armature\|mixamo.com\|Layer0`, 0.833 s, in-place run |

Left alone, RC's clips do nothing on pilot9: the names don't match, and even renamed, the rest
orientations differ enough to mangle the pose.

**The fix — BoneMap at import.** Godot's retargeter renames mapped bones to profile names, normalises
the rest pose, and **renames the skeleton node to `GeneralSkeleton`** — which is exactly the node name
RC's track paths address. Both rigs end up speaking the profile, and the clips resolve.

### BoneMap for `assets/pilot9.glb.import`

| Profile bone | pilot9 bone | | Profile bone | pilot9 bone |
| --- | --- | --- | --- | --- |
| `Root` | *(empty — pilot9 has none)* | | `RightShoulder` | `mixamorig:RightShoulder` |
| `Hips` | `mixamorig:Hips` | | `RightUpperArm` | `mixamorig:RightArm` |
| `Spine` | `mixamorig:Spine` | | `RightLowerArm` | `mixamorig:RightForeArm` |
| `Chest` | `mixamorig:Spine1` | | `RightHand` | `mixamorig:RightHand` |
| `UpperChest` | `mixamorig:Spine2` | | `LeftUpperLeg` | `mixamorig:LeftUpLeg` |
| `Neck` | `mixamorig:Neck` | | `LeftLowerLeg` | `mixamorig:LeftLeg` |
| `Head` | `mixamorig:Head` | | `LeftFoot` | `mixamorig:LeftFoot` |
| `LeftShoulder` | `mixamorig:LeftShoulder` | | `LeftToes` | `mixamorig:LeftToeBase` |
| `LeftUpperArm` | `mixamorig:LeftArm` | | `RightUpperLeg` | `mixamorig:RightUpLeg` |
| `LeftLowerArm` | `mixamorig:LeftForeArm` | | `RightLowerLeg` | `mixamorig:RightLeg` |
| `LeftHand` | `mixamorig:LeftHand` | | `RightFoot` | `mixamorig:RightFoot` |
| | | | `RightToes` | `mixamorig:RightToeBase` |

Every remaining profile slot (fingers, eyes, jaw) is left empty. `HeadTop_End`, `LeftToe_End` and
`RightToe_End` have no profile home and stay as-is.

pilot9's own run clip does not survive retargeting and is **dropped**; RC's `run_forward` replaces it.

## What gets vendored

`addons/real-controller/`, copied verbatim and **never edited**, minus `example/scene.tscn` and the
2.5 MB `example.gif`. Roughly 1.2 MB:

| Piece | Notes |
| --- | --- |
| `animations/*.res` | 30 clips: `idle` · `walk_*` ×8 · `run_*` ×8 · `sprint_*` ×5 · `turn_left/right` · `jump_begin` · `jump` · `jump_land` · `fall` |
| `character.tscn` | 928 KB. Rig is **baked inline** (56-bone `GeneralSkeleton` + `HumanM_BodyMesh`), not an FBX instance |
| `character.fbx` + `.import` | Kept as the reference BoneMap and as the A/B control rig when something looks wrong on pilot9 |
| `character.gd`, `animation.gd` | 204 + 40 lines. Copied into `scripts/`, not run from here |
| `LICENCE` | MIT, retained for provenance |

There is no `plugin.cfg` in the upstream repo — despite the README, it is not an editor plugin and
there is nothing to enable in Project Settings.

The valuable, tedious part of `character.tscn` is its AnimationTree: a state machine
(`Locomotion / jump / fall / jump_land`) wrapping **9 `BlendSpace2D`s and 78 animation nodes** with
hand-placed blend points. It is preserved wholesale — the build swaps the model *underneath* it
rather than rebuilding it.

## Build

1. **Vendor** `addons/real-controller/` as above.
2. **Retarget** — write the BoneMap into `assets/pilot9.glb.import`, clear
   `.godot/imported/pilot9.glb-*` and `.godot/editor/pilot9.glb-folding-*`, reimport headlessly per
   `docs/reimport.md`. Keep the existing `uid://bjw3dhc2w6y4e`.
3. **`scenes/pilot9.tscn`** — copy of `character.tscn`; its baked `character` subtree replaced by
   the retargeted pilot9; `AnimationPlayer.root_node` and `AnimationTree.root_node` repointed;
   `CollisionShape3D` capsule resized from RC's ~1.75 m character to pilot9's 1.95 m.
4. **`scripts/pilot9.gd`** and **`scripts/pilot9_animation.gd`** — copies of `character.gd` and
   `animation.gd`, with the `Input.mouse_mode = MOUSE_MODE_CAPTURED` line in `_ready()` **removed**.
5. **Input map** into `project.godot` (below).
6. **`scenes/trial.tscn`** — instance `pilot9.tscn`; delete the fixed `Camera3D` (RC brings
   `CameraPivot / SpringArm3D / Camera3D`); repoint and **disable** `ApplyCelPilot9`.
7. **Tests** — `tests/test_pilot9_retarget.gd`, plus a headless boot of `trial.tscn`.

### Input map additions

`forward` W · `backward` S · `left` A · `right` D · `jump` Space · `sprint` Shift ·
`walk` Alt · `camera_mode_switch` V · `look_up/down/left/right` right stick.

Purely additive. `scripts/player.gd` reads **raw keycodes** (`Input.is_key_pressed(KEY_W)`), never
named actions, so Setsuna cannot be affected. No collision with the existing `pause`, `inventory`
or `ui_accept` bindings.

Note the scheme differs from Setsuna's: RC's default gait is a **run**, with Alt held to walk.

### Blast radius

| Change | In this pass |
| --- | --- |
| `project.godot` input map | **Yes** |
| `assets/pilot9.glb.import` | **Yes** |
| `run/main_scene` → trial | **No** — run trial with F6 |
| Physics interpolation project setting | **No** — it is global and would alter Setsuna and Exia. Revisit only if trial actually jitters |
| `Input.mouse_mode` ownership | **Stays with `scripts/ui/ui_manager.gd`.** Its own comment makes cursor state the thing it asserts; our script never touches it |

## Risks

1. **Silhouette.** The rest-fixer rotates source bones toward the profile's reference pose. pilot9's
   limbs are blockout boxes; a rotated bone takes its box with it.
2. **Height.** RC's `motion_scale` is 0.9797 against pilot9's ~1.06. Position tracks are scaled by
   `motion_scale`, so this may resolve itself — or the feet float or sink. **Expect a tuning pass,
   not a first-try fit.**
3. **Missing bones.** Finger, eye, jaw and `Root` tracks will not resolve. Console warnings are
   expected; the body still animates. The retarget test below distinguishes these known-absent bones
   from a genuine failure.
4. **Armature transform.** `apply_node_transforms` should bake out the 0.01 scale and 90° X rotation.
   If it does not, the agreed fallback is a Blender correction to pilot9 — applying scale/rotation on
   the armature and re-exporting — not a re-rig.
5. **The outline pass.** Every blockout box must stay 1.0-weighted to a single bone or the outline
   inks the surface as pen-scribble, and *that artifact only appears while animating*. pilot9 has
   never animated in this project, so its first motion under the cel material is also the first
   chance for this to show. Retargeting changes bone rests, not weights, so rigidity should survive —
   but this is why the cel look starts **off**.

Escalation, if import knobs (`fix_silhouette`, `apply_node_transforms`,
`normalize_position_tracks`, `overwrite_axis`, hand-edited BoneMap) run out: a Blender fix is fine
by default. Re-skinning pilot9's boxes onto RC's own rig is a **joint decision only** — it would
cost the Mixamo pipeline, which is the reason this approach was chosen.

## Verification

`tests/test_pilot9_retarget.gd` asserts, against `scenes/pilot9.tscn`:

- the skeleton node is named `GeneralSkeleton`;
- every profile bone the BoneMap claims is present on it;
- for all 30 clips, **every track path resolves to a real bone** — failing loudly with the list of
  orphans, minus the known-absent set;
- every clip has non-zero duration (`docs/reimport.md` records 0.0-length clips as a real failure
  mode here).

The silent failure this targets: an animation whose tracks resolve to nothing plays without error.
No crash, no dialog — pilot9 stands in T-pose while the state machine transitions happily around him.

**What automated checks cannot establish:** whether pilot9 looks right, whether the blend spaces feel
good, whether the feet meet the floor, whether the outline behaves on a retargeted rig. Those are the
user's to judge on play. Passing tests are not evidence of a good result.

## Not in this pass

- **Dash, slide, crouch, double jump, apex-hang gravity.** They have no clips in RC's set. They land
  with the Mixamo animations, not before them.
- **Speed retune.** RC ships 2.5 walk / 5.0 run / 8.0 sprint against `player.gd`'s 6.0 / 9.0. Stock
  is deliberate. If 5 m/s feels like wading, note that the 8-direction blend spaces are authored
  against RC's speeds, so retuning is its own pass — not a constant edit.
- **AMS's `PoseWarping`** (slope warping, foot IK). Liftable later now that bones are on the profile;
  relevant to a slope-traversal game.
- **Setsuna's retirement.** Decided after the user drives this.
- **Licence check.** RC's clips come from Kevin Iglesias' *Basic Motions Free*
  (`kevdev.itch.io/basic-motions-free`). Commercial terms are **unread**. Worth settling before
  shipping anything, not before building.
