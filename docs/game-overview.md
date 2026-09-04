# Game Overview: Mech Delivery Prototype

> **Purpose of this document:** a fast onboarding brief so another person (or AI) can grasp
> what this game is, what exists in the codebase today, and where it's headed — without
> reading every script.

Last updated: 2026-09-04

---

## The Pitch

A third-person open-world **cargo-delivery game** built around piloting a mech across
difficult terrain. The world is intended as a Dark Souls–style network of discrete,
hand-modeled zones connected through a central hub — full of secrets, shortcuts, and
hidden areas.

There is no combat (yet). The core gameplay loop *is* traversal: carefully navigating
slopes, ledges, and narrow routes to carry cargo from the hub to a destination and back.
Reference points from the design discussion: **Death Stranding** (terrain as the obstacle,
landmark-based navigation), **Dark Souls** (zone structure and permanent shortcuts).

## Core Concepts

| Concept | Description |
|---|---|
| **Exia (the mech)** | The player's vehicle and the *only* thing that can carry cargo. Delivery missions require Exia to physically reach the destination. In-scene node name: `EXIA`. |
| **Setsuna (on foot)** | The player character on foot. Can dismount Exia at any time to squeeze through gaps too narrow for the mech, reach secrets, and open shortcut gates. In-scene node name: `SETSUNA`. |
| **Zones** | Discrete, hand-modeled Blender levels, each fully loaded into memory — no streaming. Connected hub-and-spoke, never directly to each other. *Not built.* |
| **Shortcut gates** | Progressing through a zone unlocks a gate back toward an earlier point. Once opened, permanent. *Not built.* |
| **Navigation** | No minimap, compass, or waypoints. The player orients by distinctive landmarks. |

## Traversal Model

- Movement is shared between Setsuna and Exia: WASD relative to the camera, mouse-look,
  with smooth turning toward the movement direction.
- Steep terrain is challenging through **footing, slope angle, and balance** — there is
  **no climb action**, no grapple, no handholds.
- Mech-passable routes are kept comfortably wider than Exia; dismount-only gaps are
  narrower than Exia so only the on-foot player fits.

---

## What Exists in the Codebase Today

**Engine:** Godot 4.6, Forward+ renderer. Windows. Under git version control.

The project was reduced to a single scene on 2026-09-04. Everything that exists is what
loads in **`scenes/test_platform.tscn`**, which is also the main scene: Setsuna and Exia
standing on a simple mesh platform under the cel-shaded art direction. The earlier hub,
desert, night and Moebius/Ghibli experiments were deleted — they remain recoverable from
the checkpoint commit that precedes the cleanup.

### Scenes

| File | Contents |
|---|---|
| [scenes/test_platform.tscn](../scenes/test_platform.tscn) | **Main scene.** `WorldEnvironment` (cel sky, flat ambient, filmic tonemap, light distance fog), a `Sun` `DirectionalLight3D` with shadows, the `test_platform.glb` map instance, a `WorldBoundaryShape3D` `Ground` 35m down as a catch-all floor, `SETSUNA` and `EXIA` instances, three `apply_stylized` applier nodes (ground / Setsuna / mech), and a disabled `PixelFilter` `CanvasLayer`. |
| [scenes/player.tscn](../scenes/player.tscn) | Setsuna: `CharacterBody3D` + capsule collision, the imported `setsuna.glb` model driven by an `AnimationTree`, a camera rig (`CameraPivot` → `CameraPitch` → `SpringArm3D` → `Camera3D`), and five `BoneAttachment3D` screen quads (health, stamina, dash, both thighs) driven by `setsuna_screens.gd`. |
| [scenes/mech.tscn](../scenes/mech.tscn) | Exia: `CharacterBody3D` wrapping the `Mech_V1.glb` model, its own camera rig plus a separate `HandoverCamera` for the mount transition, an `InteractionArea`, `ExitPoint` and `EmbarkPoint` markers, and a `CanvasLayer` prompt label. |
| [scenes/ui/](../scenes/ui/) | `ui_window.tscn` (the shared frame) and the two windows built on it: `pause_menu.tscn`, `inventory.tscn`. |

### Scripts

| File | Role |
|---|---|
| [scripts/player.gd](../scripts/player.gd) | On-foot controller. Camera-relative WASD (`SPEED` 6, `SPRINT_SPEED` 9), mouse-look with pitch clamp, jump (`JUMP_VELOCITY` 12.5, `MAX_JUMPS` 2) with a tunable apex-hang gravity band, dash (`DASH_SPEED` 18, 0.3s, 3s cooldown), sprint toggle, and a steerable slide. Animation runs through an `AnimationTree` state machine rather than direct clip calls. `enter_vehicle()` / `exit_vehicle()` hide and freeze the pilot while driving and hand the camera back on exit. |
| [scripts/mech.gd](../scripts/mech.gd) | Exia controller (`SPEED` 7). `InteractionArea` detects any body with an `enter_vehicle` method and shows the `F pilot` prompt. **F** enters/exits. Handles the authored embark: splits root motion off the hip bone so the mech's travel drives the body, carries Setsuna on the cockpit bone (`spine.003`) through the canopy close, and blends cameras over `HANDOVER_TIME`. |
| [scripts/map_import.gd](../scripts/map_import.gd) | `EditorScenePostImport` hook on `test_platform.glb` (wired via its `.import`). On every (re)import: adds `create_trimesh_collision()` to each mesh, forces materials double-sided, and gives material-less surfaces a `(0.45, 0.45, 0.45)` greybox tone. Re-runs automatically on each Blender re-export. |
| [scripts/setsuna_import.gd](../scripts/setsuna_import.gd) · [scripts/mech_import.gd](../scripts/mech_import.gd) | The equivalent import hooks for `setsuna.glb` and `Mech_V1.glb`. |
| [scripts/rendering/apply_stylized.gd](../scripts/rendering/apply_stylized.gd) | Walks a target subtree and applies a cel material per surface, optionally deriving each surface's colour from the imported material so a multi-material mesh keeps its palette. |
| [scripts/rendering/setsuna_screens.gd](../scripts/rendering/setsuna_screens.gd) | Drives the emissive screen quads on Setsuna's suit via `shaders/screen.gdshader`. |
| [scripts/rendering/pixelate.gd](../scripts/rendering/pixelate.gd) | Toggles/configures the optional full-screen pixelation filter. Off by default. |
| [scripts/ui/](../scripts/ui/) | `ui_manager.gd` is an autoload owning a small screen/action state machine; `ui_window.gd`, `pause_menu.gd`, `inventory.gd` are the windows it spawns. |
| [scripts/screenshot.gd](../scripts/screenshot.gd) | Autoload — **M** writes a debug screenshot to `screenshots/`. |

### Resources, shaders, assets

- `resources/cel_*.tres` — the cel material set (character, ground, sky, outline pass, and the
  shared `cel_diffuse_curve` wired in as a shader global).
- `resources/setsuna_locomotion_tree.tres` — Setsuna's `AnimationNodeStateMachine`.
- `resources/ui_theme.tres` — the single source of UI colours and sizes.
- `shaders/cel/` — third-party cel-shader base (see [ATTRIBUTION](../shaders/cel/ATTRIBUTION.md)),
  plus `outline.gdshader` and `vfx/sky.gdshader`. The `includes/` folder is required: those
  shaders pull it in with **relative** `#include` paths, so nothing references it by `res://`.
- `shaders/screen.gdshader`, `shaders/pixelate.gdshader` — suit screens and the optional filter.
- `assets/setsuna.glb`, `assets/Mech_V1.glb`, `assets/test_platform.glb` — the only three
  models in the project.

### Controls (current build)

| Input | Action |
|---|---|
| WASD | Move (relative to camera) |
| Mouse | Look |
| Space | Jump / double jump |
| Shift | Sprint (toggle) |
| C | Crouch / slide while sprinting |
| Ctrl | Dash |
| F | Interact — enter / exit Exia; confirm in menus |
| Enter | Confirm in menus |
| P | Pause |
| Tab | Inventory |
| Esc | Close the open window |
| M | Debug screenshot |

---

## What's Designed But Not Built

- **Zones and a `ZoneManager`** — loading/unloading zone scenes against a shared scene
  contract (one entry `Marker3D`, one exit trigger, zero or more `ShortcutGate` nodes).
- **Shortcut-unlock save state** — tracks unlocked gate IDs per zone; permanent for the
  playthrough. The one piece with real business logic worth a focused test.
- **A hub scene and any zone blockout** — none currently exist; `test_platform.glb` is a
  bare traversal testbed, not a level.
- **Cargo** — only the idea that cargo rides on Exia and must reach a destination. No
  inventory model, mission content, or economy.

### Explicitly Out of Scope (for now)

Combat and enemies · full save/load · any climbing mechanic · minimap/compass/waypoints ·
procedural or streamed terrain · zone-to-zone connections that bypass the hub ·
specific delivery mission design.

---

## Glossary of In-Project Names

- **Exia** — the mech (node `EXIA`).
- **Setsuna** — the on-foot pilot (node `SETSUNA`).
- **Zone** — one hand-modeled level. Not built.
- **Hub** — the intended central garage/depot. Not built.
- **Shortcut gate** — a one-time-unlock passage that shortens a zone's return trip.
