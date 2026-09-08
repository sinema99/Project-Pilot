# Game Overview

> **Purpose of this document:** a fast onboarding brief so another person (or AI) can grasp
> what this game is, what exists in the codebase today, and where it's headed — without
> reading every script.

Last updated: 2026-09-08 — **rewritten in full.** The previous version (2026-09-04) described a
Death Stranding–style hub-and-spoke cargo game with no unlocks, no bosses, and a mech that
carried meaningful cargo. A design session on 2026-09-08 replaced all of it. Where this
document and any older spec disagree about *design intent*, this document wins.

---

## The Pitch

A **3D parkour action-platformer** with a mech. pilot9 runs, slides and mantles his way through
five dense, hand-built industrial districts; EXIA, his 8.5 m machine, walks the lanes below,
carrying the shipment that gives him a reason to be there.

The structure is **Titanfall's**: the mech operates in the open negative space between
structures, the pilot operates on the structures themselves. One set of geometry, two games.

The progression is **metroidvania**: four movement techs, each found inside a map, each tested by
that map's boss, each opening routes in maps already finished.

Reference points, in order of how much they matter: **Titanfall 2** (the two-body level grammar),
**Metroid / Zelda dungeons** (find the tech in the level, the boss demands it), **Dark Souls**
(folded space, permanent shortcuts, landmark navigation), **Death Stranding** (the delivery
framing, and only the framing).

## The Loop

1. Pick a contract from the **hub menu** — a 3D lowpoly diorama of all five maps, navigated by
   camera, not by driving.
2. Load into a map. EXIA carries the shipment; pilot9 rides in.
3. **Reposition, then run.** Drive EXIA to change the level — shove a container, drop a gantry,
   park it as a launch platform — then dismount and run the level you just changed.
4. Find the map's **movement tech**, three **chests**, and the route to the delivery point.
5. **Boss.** Its final phase demands the tech just found.
6. Back out to the hub. The trader now offers **timed contracts** back through that map — which
   play differently every time the kit grows.

---

## Decisions (agreed 2026-09-08)

| | Taken | Over |
|---|---|---|
| Genre | **Parkour action-platformer.** The delivery is framing | A strand game. Cargo affects nobody, so nothing fights the player's movement while loaded |
| Cargo | **Inert.** Rides visibly on EXIA's back, varies by mission, affects no system | Cargo that weighs on pilot9's kit, or on the mech's handling |
| Map grammar | **Titanfall stratification.** Open lanes for EXIA, structures for pilot9 | A 6 × 11 m mech corridor through every map — ~4,000 m² per map of geometry pilot9 cannot use |
| The mech's job | **Reposition the level, then run it.** Mobile platform + bulldozer | A vehicle driven from A to B. Driving is the weakest verb in the game |
| Overworld | **Cut.** A lowpoly 3D diorama of the five maps, navigated as a menu | A ~600 × 600 m drivable field. It had one real job — gating the mech booster — and that moved indoors |
| Hub | **Cut to a menu system** | A physical 3D garage |
| Fail state | **Falls and hazards kill. Respawn at a checkpoint.** No health bar | Combat (a second game, a second discipline, and an enemy-asset pipeline that does not exist), or a health bar (still available later; this does not foreclose it) |
| Bosses | **Machines that knock you off**, built from `Mech_V1` reskins. Five, all structurally different | Bespoke technology per boss. At most **one** may need engineering that does not already exist |
| Tech placement | **Found in the map, before the boss. The boss's final phase demands it** | Granted as a boss reward. The map should teach the verb; the boss should test it |
| Economy | **Cut.** No currency, no shop | A shop with nothing to sell: no combat, no health, no cargo systems, and stat boosts would destabilise every authored gap |
| Chests | **Cosmetics.** Three per map, fixed and countable | An uncountable scatter, or gameplay rewards there is no room for |
| Traders | **Timed delivery contracts** through maps already beaten | A shopkeeper. Contracts are replay value out of geometry already paid for |
| Ability list | **Four, capped.** A fifth was cut during the session | Open-ended unlocks. Seven verbs is ~15 meaningful pairwise interactions to tune |
| Grapple | **Cut. Replaced by rail grind** | A grapple is the only verb the level designer does not control — it lets the player leave any authored route with a sightline |

---

## Dimensions — the modeling reference

Every number below is measured from the project, not chosen. `project.godot` does not override
gravity, so all derivations use Godot's default **9.8 m/s²**.

| Thing | Value | Source |
|---|---|---|
| pilot9 body | **1.96 m tall, 0.68 m wide** | `pilot9.tscn` capsule |
| Walk / run / sprint | **2.5 / 5.0 / 8.0 m/s** | `pilot9.gd` |
| Mantle-able ledge | **0.9 – 1.9 m** | `climb_band_min` / `climb_band_max` |
| Mantle needs | **0.6 m lip depth, 2.0 m headroom** | `climb_probe_reach`, `climb_headroom` |
| Jump apex | **1.84 m** | `jump_velocity: 6.0` |
| Airtime | **1.22 s** | derived |
| Gap at run | ~6.1 m theoretical — **~5 m usable** | derived |
| Gap at sprint | ~9.8 m theoretical — **~7–8 m usable** | derived |
| EXIA body | **4 × 8.55 × 3 m** | `mech.tscn` `BoxShape3D_body` |
| EXIA speed | **7.0 m/s** — *slower than a sprinting pilot* | `mech.gd` |
| EXIA lane clearance | **≥6 m wide, ≥11 m tall** | body + margin |
| Air dash (planned) | **5.4 m** flat | Setsuna's `DASH_SPEED 18 × 0.3 s` |

**These are what is possible, not what is comfortable.** pilot9 was played on 2026-09-08 and
feels good; comfortable distances are a greybox finding, not a spreadsheet one.

### Map size

**150 × 150 m footprint, 40–50 m of vertical, 12–15 minutes on a first run.**

Two rules that make that size hold up:

- **Fold, don't sprawl.** Path length is not footprint. A box crossed three times at three heights
  beats a corridor three times as long, costs a third as much, and is what makes shortcuts and
  "that's where I was" possible.
- **2–3 impossible routes per map.** Every map ships with visible, reachable-*looking*,
  currently-impossible routes — a ledge too high, a gap too wide, a cable with no way onto it. The
  player must see what they cannot do yet, **from the wrong side.** This is what makes the
  metroidvania backtracking work, and retrofitting it produces obvious tacked-on locked doors.

Vertical is load-bearing, not flavour: falling is the only threat in the game. A flat map has no
teeth.

For scale, the largest environment ever built for this project is `test_platform.glb` at
**38.4 × 7.9 × 61.5 m, one mesh.** Map #1 is roughly ten times that footprint.

---

## Progression

pilot9 **starts with** run · sprint · walk · jump · crouch · slide (+ buffer, hold, land-slide) ·
mantle · turn-to-face · sprint FOV. All of it is built and played.

| Map | Tech found in the map | Boss shape | Engineering cost |
|---|---|---|---|
| **1** | **Double jump** — a flag; already built | **Chase.** A machine that never stops | Lowest. A kill volume on a path |
| **2** | **Air dash** — Setsuna's numbers already exist | **Collapsing arena.** The floor leaves | Low. Timers + animated geometry |
| **3** | **Wall-run** | **Puzzle-boss.** Three phases; reach the weak point, it reconfigures the arena. Its hull is the wall | Medium |
| **4** | **Rail grind** | **Climb the giant.** Cables on the machine | **High — the one new system** |
| **5** | — (**mech booster** pays off here) | **Gauntlet.** A clean run demanding all four verbs | Lowest. Pure geometry |

Cost climbs as skill climbs; the finale is the cheapest map in the project and should be built
with no trader, no branches and no secrets. The two free unlocks are deliberately first — two full
maps of progression before a single new movement system is written.

**Scope-safety on the bosses:** a boss may **hold still, or move on a simple path, during the
phases it is climbed**, reconfiguring the arena only between phases. That removes nearly all of
the moving-collision problem while keeping the spectacle.

**The mech booster** gates a lane route inside a late map that the base machine cannot cross —
the overworld ravine it was designed for no longer exists.

---

## Scope discipline

Three commitments made during the session, recorded because they are the ones most likely to slip:

1. **Build map #1 completely. Play it. Write down how many hours it took. Do not model a polygon
   of map #2 until that number exists.** The whole plan costs `5 × T` and **T is unknown.** If T is
   frightening, **cut map count, not map quality** — three excellent maps ship; five mediocre ones
   do not.
2. **Greybox before detailing.** Box soup, no materials, full scale, in Blender.
   `scripts/map_import.gd` runs `create_trimesh_collision()` on every mesh at import, so a greybox
   is playable the moment it lands. Map #1 is the first map ever built, in a grammar never used —
   detailing a badly-shaped map is the most expensive mistake available.
3. **Open maps are harder to author than corridors.** A bowl with no direction is where solo
   projects die. The mitigations are already in the plan: EXIA's lanes read as roads and roads read
   as direction, and the no-minimap rule forces distinctive landmark silhouettes.

The diorama menu is a model of all five maps and therefore a **late** task. It is also the fun kind
of work. It must not jump the queue.

---

## What Exists in the Codebase Today

**Engine:** Godot 4.6, Forward+ renderer. Windows. Under git version control.
**Main scene:** still `scenes/test_platform.tscn` (`project.godot:14`) — `trial.tscn` runs with F6.

### Characters

| | State |
|---|---|
| **pilot9** | **The main character.** Built on [Real Controller](https://github.com/fdemir/real-controller) (MIT), retargeted onto Godot's humanoid profile so Mixamo clips drop in through the import path. Nine specs between 2026-09-05 and 2026-09-07: retarget, jump-slide, climb/mantle, slide, slide-crouch, slide-hold, sprint-FOV, turn-to-face, mech-mount. **Played 2026-09-08 — feels good.** |
| **EXIA** | The mech. Pilotable, with an authored embark for Setsuna and a cut-based board for pilot9. Node name `EXIA`. |
| **Setsuna** | **Superseded.** Hand-animated, kept and maintained but not the direction. Her dash (`DASH_SPEED 18`, 0.3 s, 3 s cooldown) is the reference for pilot9's air dash. |

### Scenes

| File | Contents |
|---|---|
| `scenes/trial.tscn` | **The active testbed.** pilot9 on `TrainingV.glb`, plus `EXIA` and a cel applier. No catch-all floor. |
| `scenes/test_platform.tscn` | Main scene. Setsuna + EXIA on `test_platform.glb` under the cel look, `WorldEnvironment`, `Sun`, a `WorldBoundary` floor 35 m down, three cel appliers, a disabled `PixelFilter`. |
| `scenes/pilot9.tscn` | pilot9: `CharacterBody3D`, retargeted `GeneralSkeleton`, Real Controller's `AnimationTree` (9 `BlendSpace2D`s, 78 nodes), camera rig. Capsule 1.96 m. |
| `scenes/player.tscn` | Setsuna. |
| `scenes/mech.tscn` | EXIA: body box `4 × 8.55 × 3`, `InteractionArea` `12 × 9 × 12`, two cameras, `ExitPoint`, `EmbarkPoint`, prompt label. |
| `scenes/ui/` | `ui_window.tscn`, `pause_menu.tscn`, `inventory.tscn`. |

### Scripts

| File | Role |
|---|---|
| `scripts/pilot9.gd` | The controller. Movement, jump/double jump, crouch, slide (+ buffer, hold, land-slide), mantle, turn-to-face, sprint FOV, `enter_vehicle` / `exit_vehicle`. **Ability gates already exist as exports** — `can_slide`, `can_buffer_slide`, `can_hold_slide`, `can_climb`. Wiring those to save flags is how progression gets built. |
| `scripts/pilot9_animation.gd` | Writes blend positions into the tree. |
| `scripts/pilot9_build_scene.gd` | Builds `pilot9.tscn` from the retargeted GLB + Real Controller's tree. |
| `scripts/mech.gd` | EXIA. `SPEED 7.0`, F to board. Duck-typed pilot contract (`has_method`), the authored embark, `seat_follow()` / `ride()` bone-carry, camera handover over `HANDOVER_TIME`. **`seat_follow()` is the machinery a shoulder-platform would reuse.** |
| `scripts/player.gd` | Setsuna's controller. Reads raw keycodes, so it cannot collide with pilot9's input map. |
| `scripts/map_import.gd` | `EditorScenePostImport` on `test_platform.glb`: trimesh collision on every mesh, double-sided materials, greybox tone on material-less surfaces. **The greybox pipeline.** |
| `scripts/setsuna_import.gd` · `scripts/mech_import.gd` | The equivalents. |
| `scripts/rendering/apply_stylized.gd` | Walks a subtree applying cel materials, optionally deriving colour per surface. **The cosmetic-recolour path.** |
| `scripts/rendering/setsuna_screens.gd` · `pixelate.gd` | Suit screens; optional pixel filter (off). |
| `scripts/ui/` | `ui_manager.gd` autoload + windows. Owns `Input.mouse_mode`. |
| `scripts/screenshot.gd` | **M** writes to `screenshots/`. |

### Assets

`pilot9.glb` · `Mech_V1.glb` · `setsuna.glb` · `test_platform.glb` (38.4 × 7.9 × 61.5 m) ·
`TrainingV.glb` (2 × 0.4 × 2 m tile). All characters are untextured blockouts.

### Tests

22 headless suites under `tests/`, run via `tests/run.ps1`. Twelve cover pilot9 alone.

---

## What's Designed But Not Built

- **Every map.** Zero exist. This is the entire remaining project.
- **The four techs** — double jump is a flag away; air dash has Setsuna's numbers; wall-run and rail
  grind are unwritten.
- **The mech's two verbs** — shoulder platform (reuses `seat_follow()`) and bulldozer set pieces.
- **Fail state** — kill volumes, checkpoints, respawn. **Nothing in the game damages the player
  today** (`player.gd:159` says so in as many words), and pilot9 has no health field at all.
- **Bosses**, all five.
- **The hub menu and the diorama.**
- **Traders, contracts, chests, cosmetics, shortcut gates, and the save state behind them.**

### Explicitly Out of Scope

Combat and enemies · a currency or shop · stat upgrades of any kind · a drivable overworld ·
cargo that affects any system · a fifth movement tech · minimap / compass / waypoints ·
procedural or streamed terrain · a grapple.

---

## Glossary

- **pilot9** — the player character on foot. The main character.
- **EXIA** — the mech (node `EXIA`).
- **Setsuna** — the superseded first character.
- **Map** — one of five hand-modeled 150 × 150 m districts. The game.
- **Lane** — the open ground EXIA moves through. Negative space; costs nothing to author.
- **Structure** — the buildings pilot9 plays on. Positive space; where all the work goes.
- **Tech** — one of the four unlockable movement verbs.
- **Contract** — a timed delivery run through a beaten map, offered by its trader.
- **Diorama** — the lowpoly 3D model of all five maps that serves as the map-select menu.
