# Spec: Zone-Based Open World Map System

## Problem Statement

Mech Delivery Prototype currently has no map, terrain, or level structure — just a player, a pilotable mech (Exia), and a skybox in an empty scene. The game's core pitch is an open-world, Souls/Elden Ring/Hollow Knight-style world full of secrets, shortcuts, and hidden areas, but the actual gameplay is a walking-sim/cargo-delivery loop where Exia is the only thing that can carry cargo. Without a defined map structure, there's no way to know how big to build areas, how they connect, how exploration rewards (shortcuts, secrets) tie back into delivery gameplay, or whether a hand-modeled open world will even run at a playable frame rate.

## Solution

Build the world as a set of discrete, hand-modeled Blender zones (~1100m across each) connected through a central hub, in the mold of Dark Souls rather than a seamless Elden Ring-style world. Exia is the player's only means of moving cargo — walking-sim gameplay *is* piloting Exia across difficult terrain (slopes, ledges, narrow paths) between the hub and delivery destinations. The player can dismount Exia to squeeze through gaps Exia can't fit through, in order to reach secrets and unlock shortcut gates that collapse the return trip through a zone on future deliveries. Every zone (and the hub) is built against one shared scene contract, loaded through one `ZoneManager` system, so the amount of bespoke per-zone code stays minimal. Performance is handled with standard Godot tooling (occlusion culling, mesh LOD, budgeted geometry) rather than custom streaming, since each zone is scoped to stay small enough to hold fully in memory.

## User Stories

1. As a player, I want to pilot Exia out of the hub toward a delivery destination, so that I can complete a cargo delivery mission.
2. As a player, I want each zone to be traversed primarily by carefully navigating terrain (slopes, ledges, narrow routes) rather than fighting enemies, so that the "walking simulator" identity of the game comes through.
3. As a player, I want cliffs and slopes to be genuinely challenging to cross with Exia, so that route-finding and careful movement are the core gameplay skill.
4. As a player, I want to be able to dismount Exia at any time, so that I can explore on foot.
5. As a player, I want some gaps and passages to be too narrow for Exia but passable on foot, so that dismounting is meaningfully rewarded with access to areas Exia can't reach.
6. As a player, I want to find hidden doors, keys, and chests while exploring on foot, so that exploring off the critical path feels worthwhile.
7. As a player, I want zones to loosely follow a linear critical path, so that I always have a legible sense of "forward progress" even in a large hand-built space.
8. As a player, I want progressing through a zone to unlock a shortcut gate back toward an earlier point (or the hub), so that repeat deliveries to a zone I've already explored take less time.
9. As a player, I want shortcut gates to stay unlocked permanently once opened, so that my exploration progress isn't lost between delivery runs.
10. As a player, I want to orient myself across an 1100m zone using visible landmarks (distinctive structures, terrain silhouettes) rather than a minimap or waypoint marker, so that navigation itself is part of the exploration challenge.
11. As a player, I want a loading transition when moving between the hub and a zone (or between zones), so that each space can be fully built and loaded without needing seamless streaming.
12. As a player, I want the hub to be a walkable, dismount-friendly space (garage/depot), so that I have a low-stakes area to explore on foot between deliveries.
13. As a developer, I want every zone scene to expose the same entry point, exit/hub-transition trigger, and shortcut gate structure, so that the loading and shortcut-unlock systems don't need bespoke per-zone code.
14. As a developer, I want a single system tracking which shortcut gates are unlocked per zone, so that unlock state persists correctly across zone loads and future save/load.
15. As a developer, I want each zone's geometry to fit inside a defined performance budget (polygon count, texture memory), so that a fully-loaded 1100m zone stays performant without needing chunk streaming.
16. As a developer, I want occlusion culling set up per zone (using terrain features like cliffs and ridgelines as natural occluders), so that off-screen geometry doesn't cost render time.
17. As a developer, I want mesh LOD generated for zone geometry on import, so that distant terrain renders cheaper without manual LOD authoring.
18. As a developer, I want a clear scale reference (Exia's collision footprint vs. the player's) while blocking out terrain in Blender, so that mech-passable routes and dismount-only gaps are sized correctly from the start.
19. As a developer, I want the hub to be the fixed center of the zone graph (hub-and-spoke), so that new zones can be added later without redesigning existing connections.
20. As a player, I want cargo to only be deliverable while it's loaded on Exia, so that route planning and terrain navigation are meaningful even before any combat or other systems exist.

## Implementation Decisions

- **World structure**: discrete zone scenes connected by loading transitions (no seamless/streamed open world). A central **Hub** scene is the fixed anchor; every zone connects back to the Hub (hub-and-spoke), not directly to each other.
- **Zone scale**: each zone targets roughly 1100m across, hand-modeled in Blender by the developer (no procedural or heightmap-based terrain generation).
- **Zone scene contract**: every zone (and the Hub) is built as a scene rooted in a standard `Zone` structure exposing:
  - One entry `Marker3D` (where the player/Exia spawns when entering from the Hub or a previous zone).
  - One exit/hub-transition trigger (returns to the Hub or advances to the next connected zone).
  - Zero or more `ShortcutGate` nodes, each with a stable, zone-scoped ID.
- **Zone loading**: a single `ZoneManager` (or `SceneTransition`) autoload owns loading/unloading zone scenes and driving the loading-screen transition. It only needs to know the shared `Zone` contract, not per-zone specifics.
- **Shortcut persistence**: a single save-state system tracks unlocked `ShortcutGate` IDs, keyed by zone ID. Once a gate is unlocked, it stays unlocked for the rest of the playthrough (and should persist across a future save/load system, even though full save/load is out of scope for this spec).
- **Zone shape/pacing**: zones are linear-ish (a critical path from entry to exit), with room for optional off-path detours to reach secrets/chests. Shortcut gates are placed to skip already-traversed sections of that critical path on return visits, not to open entirely new routes.
- **Traversal identity**: Exia is the only entity that can carry cargo; delivery missions require Exia to physically reach the destination. Dismounted, on-foot movement exists for squeezing through gaps Exia's collision footprint can't fit through, for walking around the Hub, and (later, out of scope for this spec) for combat.
- **Terrain difficulty model**: no dedicated "climb" action. Vertical/steep terrain (slopes, ledges, switchbacks) is challenging via footing, slope angle, and balance while Exia is piloted across it — not via wall-climbing mechanics.
- **Scale reference for blockout**: Exia's collision footprint is 1.6m (W) × 3.6m (H) × 1.2m (D); the on-foot player capsule is 0.8m diameter × 1.8m tall. Mech-passable routes should stay meaningfully wider than 1.6m (comfortable margin: 3m+); dismount-only gaps should be narrower than Exia's 1.6m width so only the on-foot player fits through.
- **Navigation**: no minimap, compass, or waypoint marker. Orientation relies on visually distinctive landmarks placed along and visible from the critical path, so blockout work should deliberately shape silhouettes/sightlines toward key landmarks, not just carve a corridor.
- **Performance strategy**: each zone is fully loaded into memory at once — no chunk streaming, no LOD/visibility-range system beyond what's listed below. Performance is kept in budget through:
  - `OccluderInstance3D` occlusion culling, using cliffs/terrain as natural occluders.
  - Godot's automatic mesh LOD generation on import.
  - A defined (to be set once blockout geometry exists) polygon and texture memory budget per zone.

## Testing Decisions

This spec covers world/level structure, not gameplay logic, so most validation is playtest- and profiling-based rather than automated unit testing:

- **Zone contract conformance**: the `ZoneManager` should be exercised against at least two different zone scenes (including the Hub) to confirm it only relies on the shared entry/exit/`ShortcutGate` contract, with no zone-specific branching creeping into the loader.
- **Shortcut persistence**: the shortcut-unlock save-state system should be testable in isolation — given a zone ID and gate ID, confirm unlock state is set and read back correctly, independent of any specific zone's geometry. This is the one piece of this spec with real "business logic" worth a focused test, since it will need to interact with a future save/load system.
- **Performance validation**: once a zone blockout exists, profile it in Godot with occlusion culling and LOD enabled vs. disabled to confirm culling is actually reducing draw calls/triangles as expected for that zone's geometry, and confirm frame time stays in budget with the zone fully loaded.
- **Traversal/pacing validation**: playtest a full zone traversal (entry to exit) to sanity-check that the ~1100m scale and terrain difficulty produce the intended pacing, and that landmark placement is sufficient to navigate without a waypoint.
- No prior art exists in this codebase yet for either automated tests or a save-state system — this will be the first of both.

## Out of Scope

- The Blender terrain blockout itself (this spec defines constraints for it; the modeling work happens separately).
- Combat and enemies.
- A full save/load system (only the shortcut-unlock persistence piece is addressed here, as it's required for the shortcut feature to make sense).
- Any climbing mechanic (grapple, handholds, etc.) — terrain difficulty is handled entirely through slope/footing.
- A minimap, compass, or waypoint/quest-marker system.
- Procedural or streamed/chunked terrain generation.
- Zone-to-zone direct connections that bypass the Hub.
- Cargo/inventory systems beyond "cargo exists on Exia and must reach the destination."
- Specific delivery mission content/design (what's being delivered, why, mission structure) — this spec only covers the map/traversal substrate those missions will run on.

## Further Notes

- This spec captures the outcome of a design discussion (2026-08-26) working through the open-world map structure question raised for this prototype. Reference games discussed: Dark Souls (zone structure/shortcuts), Elden Ring (ruled out — seamless streaming is disproportionate for a solo project), Hollow Knight (ruled out — implies a 2D pivot), Death Stranding (terrain-as-obstacle traversal model, landmark-based navigation).
- The project is solo-developed with all terrain hand-modeled in Blender, which was a deciding factor in choosing modest per-zone scale and a fully-loaded (non-streamed) performance strategy over a larger or more technically complex world.
- Concrete polygon/texture budgets aren't set numerically yet since no blockout geometry exists to calibrate against — revisit once the first zone blockout is in and profiled.
