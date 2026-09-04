# Game Overview: Mech Delivery Prototype

> **Purpose of this document:** a fast onboarding brief so another person (or AI) can grasp
> what this game is, what exists in the codebase today, and where it's headed — without
> reading every script. For the detailed world/level design, see
> [specs/zone-based-map-system.md](specs/zone-based-map-system.md).

Last updated: 2026-08-27

---

## The Pitch

A third-person open-world **cargo-delivery game** built around piloting a mech across
difficult terrain. The world is a Dark Souls–style network of discrete, hand-modeled
zones connected through a central hub — full of secrets, shortcuts, and hidden areas.

There is no combat (yet). The core gameplay loop *is* traversal: carefully navigating
slopes, ledges, and narrow routes to carry cargo from the hub to a destination and back.
Reference points from the design discussion: **Death Stranding** (terrain as the obstacle,
landmark-based navigation), **Dark Souls** (zone structure and permanent shortcuts).

## Core Concepts

| Concept | Description |
|---|---|
| **Exia (the mech)** | The player's vehicle and the *only* thing that can carry cargo. Delivery missions require Exia to physically reach the destination. In-scene node name: `EXIA`. |
| **The pilot (on foot)** | The player character on foot. Can dismount Exia at any time to squeeze through gaps too narrow for the mech, reach secrets, and open shortcut gates. In-scene node name: `SETSUNA`. |
| **Zones** | Discrete, hand-modeled Blender levels (~1100m across), each fully loaded into memory — no streaming. Connected hub-and-spoke, never directly to each other. |
| **Hub** | The fixed center of the zone graph — a walkable garage/depot where the player explores on foot between deliveries. |
| **Shortcut gates** | Progressing through a zone unlocks a gate back toward an earlier point or the hub. Once opened, permanent — collapses the return trip on future deliveries. |
| **Navigation** | No minimap, compass, or waypoints. The player orients by distinctive landmarks placed along and visible from the critical path. |

## Traversal Model

- Movement is shared between the pilot and Exia: WASD relative to the camera, mouse-look,
  crouch, jump, with smooth turning toward the movement direction.
- Steep terrain is challenging through **footing, slope angle, and balance** — there is
  **no climb action**, no grapple, no handholds.
- Mech-passable routes are kept comfortably wider than Exia (3m+); dismount-only gaps are
  narrower than Exia's 1.6m width so only the on-foot player fits.
- **Scale reference:** Exia's collision footprint is 1.6m W × 3.6m H × 1.2m D; the on-foot
  player capsule is 0.8m diameter × 1.8m tall.

---

## What Exists in the Codebase Today

**Engine:** Godot 4.6, Forward+ renderer. Windows. Not currently under version control.

The game is an early prototype: a player, a pilotable mech, an HDRI night sky, and a first
**Hub blockout** (hand-modeled in Blender) dropped into the main scene. The zone/shortcut
systems from the spec are **not built yet**, and the hub itself is untextured greybox geometry.

### Scenes

| File | Contents |
|---|---|
| [scenes/main.tscn](../scenes/main.tscn) | The main scene. `HUB_blockout` instance (with a Y counter-offset — see worklog), the old 60×60m box `Ground` kept as a hidden-mesh fallback collider, one `DirectionalLight3D` (energy 0.15) with shadows, a `WorldEnvironment` with a `PanoramaSkyMaterial` night-sky HDRI (`qwantani_night_puresky_4k.exr`, energy 0.4) driving low sky ambient + reflections, plus instances of the player (`SETSUNA`) and mech (`EXIA`). |
| [scenes/player.tscn](../scenes/player.tscn) | On-foot player: `CharacterBody3D` + capsule collision (0.4m radius, 1.8m tall), an imported `setsuna.glb` model with an `AnimationPlayer` (IDLE / RUN START / RUN LOOP / JUMP), and a camera rig (`CameraPivot` → `CameraPitch` → `SpringArm3D` → `Camera3D`) — the spring arm (length 4, 0.3 sphere shape) pulls the camera in to stop it clipping through walls. |
| [scenes/mech.tscn](../scenes/mech.tscn) | Exia: `CharacterBody3D` with a 1.6×3.6×1.2 box collision, placeholder box-mesh body (torso, head, two legs), its own camera rig, a 5×4×5 `InteractionArea` (Area3D), an `ExitPoint` marker, and a `CanvasLayer` UI with a `PromptLabel`. |
| [scenes/Hub.tscn](../scenes/Hub.tscn) | Standalone scene for iterating on the hub map: `Node3D` "Hub" + `HUB_blockout` instance + `DirectionalLight3D` + `WorldEnvironment` (same night-sky HDRI). No player/mech. |

### Scripts

| File | Role |
|---|---|
| [scripts/player.gd](../scripts/player.gd) | On-foot controller. Camera-relative WASD movement (`SPEED` 6, `SPRINT_SPEED` 9, `CROUCH_SPEED` = `SPRINT_SPEED`), mouse-look with pitch clamp, jump (`JUMP_VELOCITY` 12.5, double jump), crouch toggle on **C** (lerps capsule height and mesh between 1.8m and 1.0m), dash on **Ctrl** (launches at `DASH_RISE_ANGLE` 30 above horizontal), sprint toggle on **Shift**. Sliding is the sprint's crouch: **C** while sprinting dives into a held slide at sprint speed, steerable, and holds until **C** stands you up or a jump/dash takes the body. `_ready()` excludes the player's own body from the camera spring arm. Animation: plays `RUN START` on the first frame of movement and queues `RUN LOOP` after it, `IDLE` when stopped; on the Space press it plays the one-shot `JUMP` front flip and holds its last frame until landing. `enter_vehicle()` / `exit_vehicle()` hide and freeze the pilot while driving and hand the camera back on exit. |
| [scripts/mech.gd](../scripts/mech.gd) | Exia controller. Same movement model as the player (`SPEED` 6, crouch lowers the camera 3.7m → 2.5m). `InteractionArea` detects any body with an `enter_vehicle` method and shows a prompt. **F** enters/exits; on enter, the pilot is passed in and Exia's camera becomes current; on exit, the pilot is released at `ExitPoint`. When unpiloted, Exia just decelerates and idles. |
| [scripts/hub_import.gd](../scripts/hub_import.gd) | `EditorScenePostImport` hook on `HUB_blockout.glb` (wired via its `.import`). On every (re)import: adds `create_trimesh_collision()` to each mesh (solid floor/walls/ramps), forces materials double-sided, and gives material-less surfaces a `(0.45, 0.45, 0.45)` greybox tone. Re-runs automatically on each Blender re-export. |
| [scripts/skybox.gd](../scripts/skybox.gd) | **No longer used** — the mesh sky dome it drove was removed from `main.tscn` when the HDRI panorama sky replaced it. Script + `skybox_anime_sky.glb` still on disk. |

### Assets

- `assets/setsuna.glb` — the on-foot player model "Setsuna" (Rigify metarig; IDLE / RUN START / RUN LOOP / JUMP animations).
- `assets/HUB_blockout.glb` — first hub blockout, hand-modeled in Blender. Untextured. Still has unapplied root scale + a large origin offset (see [worklog/2026-08-27.md](worklog/2026-08-27.md)).
- `assets/qwantani_night_puresky_4k.exr` — Poly Haven night-sky HDRI, used as the panorama skybox in `main.tscn` and `Hub.tscn`.
- `assets/skybox_anime_sky.glb` (+ `_0.jpg` texture) — the old sky dome mesh; **no longer referenced** by any scene.
- Exia is a placeholder primitive; no zone/terrain art beyond the hub blockout exists yet.

### Controls (current build)

| Input | Action |
|---|---|
| WASD | Move (relative to camera) |
| Mouse | Look |
| Space | Jump / double jump |
| Shift | Sprint (toggle) |
| C | Crouch (toggle) |
| Ctrl | Dash |
| F | Interact — enter / exit Exia; confirm in menus |
| Enter | Confirm in menus |
| P | Pause |
| Tab | Inventory |
| Esc | Close the open window |

---

## What's Designed But Not Built

From [specs/zone-based-map-system.md](specs/zone-based-map-system.md):

- **`ZoneManager` autoload** — loads/unloads zone scenes and drives the loading-screen
  transition, relying only on a shared `Zone` scene contract (one entry `Marker3D`, one
  exit/hub-transition trigger, zero or more `ShortcutGate` nodes with stable zone-scoped IDs).
- **Shortcut-unlock save-state system** — tracks unlocked gate IDs keyed by zone ID;
  permanent for the playthrough, designed to survive a future save/load system. This is the
  one piece with real "business logic" worth a focused test.
- **The Hub scene** and at least one **zone blockout** (hand-modeled in Blender).
- **Performance setup per zone** — `OccluderInstance3D` occlusion culling using cliffs as
  natural occluders, automatic mesh LOD on import, and a polygon/texture-memory budget
  (numbers TBD until a blockout exists to profile against).
- **Cargo** — only that "cargo exists on Exia and must reach the destination." No inventory
  system, no mission content, no economy.

### Explicitly Out of Scope (for now)

Combat and enemies · full save/load · any climbing mechanic · minimap/compass/waypoints ·
procedural or streamed terrain · zone-to-zone connections that bypass the hub ·
specific delivery mission design.

---

## Glossary of In-Project Names

- **Exia** — the mech (node `EXIA`).
- **Setsuna** — the on-foot pilot (node `SETSUNA`).
- **Zone** — one hand-modeled ~1100m level.
- **Hub** — the central garage/depot; fixed center of the hub-and-spoke zone graph.
- **Shortcut gate** — a one-time-unlock passage that shortens a zone's return trip.
- **Critical path** — the linear-ish route from a zone's entry to its exit; detours off it
  lead to secrets and chests.
