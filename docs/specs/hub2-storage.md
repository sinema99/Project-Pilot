# hub2 storage facility dressing

2026-11-14. Grilled with the user (13 questions). Builds on [hub2.md](hub2.md),
[hub2-industrial.md](hub2-industrial.md), [hub2-ps1-mood.md](hub2-ps1-mood.md) and
[cargo-container.md](cargo-container.md).

Ask: hub2 is an abandoned storage facility. Arrange cargo containers in the big rooms, more pipes
across the corners of halls and rooms, machinery (roof cranes and other storage equipment), crates
(some neat, some messy), computers built into the walls, overgrowth.

## Map facts (ray-cast survey, Map scale 0.6)

Plan image: [hub2-plan.png](hub2-plan.png) (1 px = 1 m, split by height band).

| Label | What | Extent (world) | Floor y |
|---|---|---|---|
| A | **WRONG, see "Room A correction" below.** The -164 surface is A's ROOF (outside the map). Real A: enclosed hall under it | x -95..95, z -446..-112 | -273 |
| B | tall hall west of the spawn shaft (ceiling ~ y 69) | x -162..-58, z -158..54 | ~ 18 |
| C | smaller low-ceiling room east of the shaft (ceiling ~ y 47) | x 69..113, z -136..-80 | ~ 37 |
| D | open central shaft + spawn platform | x -12..12, z -181..94 | 29 |
| E | high corridors | see plan, y 40..120 | various |

Exact floors, walls and ceilings are read by the generator with rays, not from this table.

## Decisions

1. **Rooms dressed:** A, B and C, plus the halls (D/E) for pipes, wall kit, lamps and light overgrowth.
2. **A is reachable one way.** `kill_height` -30 -> -300 (below the deepest pit). No lift, ramp or
   stairs: the player drops in and cannot climb back out. Deliberate. No fall damage exists.
3. **Built in code, PS1 style.** Every prop is a `@tool` script building one ArrayMesh: vertex colours,
   flat normals, no textures/UVs, low poly (pipes 6-8 sides), drawn with the PS1 surface look (vertex
   snap, affine, stepped shading) and cut into AIRFRAME pixels like `CargoContainer`. Each family has
   a preset dropdown. Box collision on anything walked into; hanging/thin detail has none.
4. **Weathering in vertex colours.** Grime darkening toward the bottom, rust on edges/corners, faded
   paint, extra verts only where colour changes. `CargoContainer` gains `wear` (0..1, default 0, hub2 sets
   it worn). Props are not touched by the hub2 wear shader or the decal bake.
5. **Generator writes real nodes.** `tools/gen_hub2_dressing.gd` writes instanced props into
   `scenes/hub2.tscn` under `Dressing/A`, `Dressing/B`, `Dressing/C`, `Dressing/Halls`, from per-room
   layout tables plus seeded scatter (deterministic). Re-running replaces a room's group, so once the
   user hand-edits a room it is no longer regenerated. The `CargoContainers` staging slab and its 10 test
   containers are removed.
6. **Real-world placement, not parkour.** Nothing is tuned for jumps or routes.
7. **Containers.**
   - B: the main yard. Neat grid rows stacked 1-3 high, ~4 m forklift aisles, painted bay lines. A few
     slightly askew, one or two top boxes slid half off.
   - A: the dump. Containers that fell down the cylinder: toppled, tilted, on sides/ends, piled around the
     cylinder base. One neat block left near a wall.
   - C: 4-6 along the walls, one stacked; floor kept for crates and machinery.
   - Palette mostly muted (rust, blue, grey, brown, teal), a few loud landmarks (orange, yellow).
8. **Machinery (all static).**
   - B: 2 overhead bridge cranes on wall runway rails, one with a container spreader hanging on cables;
     reach stacker; 2 forklifts; fuel/charging station; pallet racking on a short wall.
   - A: big polar crane on a ring rail high on the cylinder wall, hook down, dangling cable; crushed
     forklift under fallen containers; toppled scissor lift.
   - C: smaller bridge crane; roll-up dock doors with dock levellers; scissor lift; pallet jacks;
     racking with crates; workbench corner.
   - Halls: electrical cabinets, junction boxes, fire hose reels, extinguishers. No vehicles.
9. **Pipes.** The generator finds real concave wall-ceiling edges (and wall-wall corners for vertical
   drops) in the map mesh and runs bundles of 1-4 parallel pipes (0.15-0.6 m) on brackets every ~3 m,
   flanges at joints, elbows at turns, occasional valve wheel / gauge. Colour coded: red fire, yellow gas,
   green-grey water, plain steel; weathered. A few broken runs (one sagging off its brackets, one snapped
   stub). ~60-70 % of eligible corners. The flat pipe decals from the wear pass are removed.
10. **Crates.** Static, box collision, not the trial carry crates. Types: wooden slat crate, metal
    box/locker (grey/olive), plastic stacking tote, shrink-wrapped pallet load. Neat: on racking, pallet
    stacks of 2-4 along walls and bay lines. Messy: toppled stack across an aisle, crates knocked off
    racking, one broken open, loose ones dumped in hall corners. A: the most chaotic, mixed into the
    container wreck and spilled from a split container.
11. **Wall computers.** Walls cannot be cut, so "built in" = thick bezel mounted flush, screen and
    keyboard recessed inside it. 90s industrial terminal: CRT in steel bezel, keyboard shelf, status lamps,
    conduit up to the ceiling pipes. Banks of 2-4 at the B crane control post, the C dock office wall and
    a few hall junctions; singles elsewhere. ~1 in 4 powered: flickering green or amber scrolling garbage
    text + blinking cursor in a small stepped-pixel shader; the rest dark glass, the odd one cracked.
    Decoration only.
12. **Overgrowth.** Solid low-poly vertex-colour geometry (no alpha cards): hanging vines (chains of
    bent strips + leaf blobs) from pipes, girders and ledges; moss patches on floors, container tops,
    wall bases, creeping up walls; grass/weed tufts in corners and along wall bases; lumpy shrubs.
    A only: 2-3 small gnarled trees (one out of a split container) and grass patches on the open floor.
    Density: A heavy; B medium (openings, leaking pipes, over crane girders); C light; halls sparse.
    Static, no wind. No collision except tree trunks.
13. **Light fixtures, pools follow them.** High-bay hanging lamps on a ceiling grid in B and C,
    floodlights on crane girders, caged bulkheads over doors and in halls. ~1 in 3 dead (dark, glass
    gone), one or two hanging crooked on one chain. The generator writes each lit lamp's position,
    colour and radius into a list the PS1 pool code reads; pools in dressed rooms come from that list.
    The hashed random pools stay only where the generator does not dress (far A, the cylinder). No
    real-time lights.

## Engineering notes (not grilled)

- **Perf:** every prop gets `visibility_range_end` just past the fog's full distance (95 m), where
  it is fully fogged anyway. Many small props of one family may be merged per room if node count costs.
- **Lamp list:** a uniform array if it fits; otherwise a small data texture.
- **Tests:** `tests/test_hub2_dressing.gd` (kill height, groups exist, no staging slab, lamp list
  populated, props inside their room bounds and on a floor, prop scripts build non-empty meshes).
  Visuals checked with probe screenshots per room.

## Built (2026-11-14)

Files: `scripts/props/prop_kit.gd`, `hub2_prop.gd`, `hub2_prop_build.gd`, `hub2_crane.gd`, `hub2_pipe_run.gd`,
`hub2_lamp_pools.gd`, `shaders/hub2_crt.gdshader`, `tools/gen_hub2_dressing.gd`, `scripts/cargo_container.gd` (wear).
Re-run the generator after a hub2.glb re-export or a table change:
`godot --headless --path . --script tools/gen_hub2_dressing.gd` (then the wear bake if the glb changed).

Deviations from the grill:
- A's polar crane: A is not a closed room; the "cylinder" is a tower hanging ~15 m over a pit. The ring is bracketed
  onto the tower's wall and carries a slewing jib reaching out over the yard (a full-span bridge would go through it).
- The hashed random pools were already OFF (2026-11-13), so "random pools stay in undressed areas" means: no pools
  there. Fixture pools are downlight only.
- B's racking: none fitted along the north wall's free spots after the service kit; racking is in C (9 bays).
- B's high-bays hang from a 47 m roof on <= 6 m chains, so their pools reach the floor with a bigger radius.

Status: built 2026-11-14, probe-shot (B yard + service end, C, A heaps + crane, hall pipes); tests green.

## Review fixes (2026-11-14)

Grilled with the user after a probe tour (`tests/_probe_hub2_tour.gd`), before they had looked at it.
1. **Fixture pools on floors only** (`shaders/hub2_ps1.gdshaderinc`, `up = smoothstep(0.55, 0.85, n.y)`): they
   painted flat ovals on walls in B, C and the spawn corridor.
2. **B's middle column line is kept** (two bridge cranes cannot each span the 104 m hall). The reach stacker
   moved out of it to x -126. `_prop` now warns when a fixed-spot prop overlaps an already-placed prop box
   (props only; wall kit touches the map on purpose). Last run: 1 overlap, a spilled crate.
3. C's diagonal is map geometry (wear-shaded), left as is.
4. **Floor scuffs** were broken 1 px near-black strands, alpha-cut, so they read as black slashes; now two
   unbroken 2 px tyre marks in a dark floor grey (`hub2_decal_atlas.gd` `SCUFF`). Re-baked.
5. **A's polar ring**: deep plate girder (web + flanges + rail), triangle brackets every 8 m that run 12 m back
   into the tower wall (`bracket_in` past the wall on purpose: the tower's radius varies).
6. **A landing**: `A_LANDING` (the D-shaft drop, ~ (0, -164, -150)) is kept clear of wreck piles, and a
   9-container pile with a split container, tree and spilled crates sits beside it at (-32, -164, -152).
7. **Wall moss** was a round disc on the wall (read as a green ball); now a low ragged band on the floor line with
   a floor fringe.
8. **Perf: no merge.** A runtime per-40 m-cell mesh merge was built and measured (`tests/_probe_hub2_perf.gd`,
   held camera, vsync off): draws 592 -> 99 but triangles doubled and every view got slower (B aisle
   123 -> 98 fps). Unmerged: B 123-154 fps, C 185, A landing 196, spawn 198 on an RTX 3060. The earlier "71 fps"
   came from a probe that moved the camera every 40 frames. Removed.

## Room A correction (2026-11-14, specced, then BUILT same day)

The user found A's dressing on the OUTSIDE of the map (editor shot: polar ring round a column standing on a stepped
slab, sky all round). The first survey read "rays up hit sky" as "open overhead" instead of "this is outside".
Re-surveyed with layered down-rays and inward-facing hit normals (Map scale 0.6):

- **y -164 is A's roof slab**, open sky above. Everything built for A sits on it: wreck piles, trees, floor plants,
  container moss, the polar crane + its vines and floodlights, the neat 3x3 block, crushed forklift, scissor lift.
- **Real A** is an enclosed hall under the slab: floor **y -273**, ceiling -164 / -173, walls all round,
  x -95..95, z -446..-112 (the south end narrows; a bay reaches z ~ -471). Arched openings in the side walls
  (the plan's olive notches). Bare. Floor already carries the wear pass (tiles + decals).
- **The "tower" is the big cylinder: a hollow ~80 m shaft** (wall 38-46 m from (0, y, -230)), capped at y 164,
  open at the bottom into A's ceiling. Its only side opening faces +Z (north, toward D) between y ~0 and ~56.
  From there the pilot falls ~300 m to A's floor. Kill height -300 is below -273, no fall damage.
- The user's in-play shot of real A ([hub2-a-reference.webp](hub2-a-reference.webp)) is the target look: dark, the
  existing blue fog, no sky, tiled floor, arches.

### Decisions (grilled 4 + sign-off)

1. **Remove everything on the roof.** Nothing generated may sit above y -173 inside ROOM A's rect.
2. **Rebuild A on the real floor (-273)** with the original brief (container dump, crushed forklift, toppled
   scissor lift, crates, overgrowth), corrected as below. Real-world placement still; not parkour.
3. **Way in unchanged: one-way drop.** Walk off D through the shaft's north opening and fall into A. No lift, no
   stairs, no way back. Must be proven by a walk probe from spawn (see Tests); if the opening is not walkable or
   the pilot dies, stop and report, don't patch around it.
4. **Look: as the reference shot.** Dark, same fog, no sky light.
5. **One light column down the shaft.** A faint, cold column of light falls from the shaft onto the floor under
   its mouth (only "natural" light in A): a dim additive column + a large cold floor pool via the fixture list.
6. **Overgrowth = an island in that light.** Grass, moss, shrubs and the 2-3 gnarled trees (one out of the split
   container) only in the lit patch under the shaft. Elsewhere light: moss on container roofs and wall bases,
   vines off the ring. The old "heavy, open sky" density is dropped.
7. **Polar ring hangs from the ceiling round the shaft mouth** (not bracketed into a tower wall: there is none
   below -164). Hangers up into the ceiling, slewing jib out over the hall, hook down, dangling cable.
   4 floodlights on it, 1 lit.
8. **Lamps:** a couple of caged bulkheads over the arched openings, mostly dead; lit ones feed floor pools as in B/C.
9. **Dump layout:**
   - Main heap under the shaft mouth, offset SOUTH (containers fell down the shaft), lit by the column.
   - **Landing strip kept clear**: ~30 m wide, round (0, -273, -190), the north side of the shaft where a D drop lands.
   - The fresh pile beside it: split container, tree, spilled crates.
   - Smaller piles thinning out toward the dark walls: one under the hook, crushed forklift, toppled scissor lift.
   - The neat 3x3 block by the east wall.

### Engineering notes (not grilled)

- `tools/gen_hub2_dressing.gd`: A floor -273; `ROOM_A`, `PIT_CENTRE` (-> shaft axis ~(0..4, -273, -230)),
  `TOWER_RING`, `A_LANDING`, `A_LANDING_PILE` re-derived from the new survey; `_floor()` probes must start
  under the -164/-173 ceiling or they land on the roof. Polar crane type needs a ceiling-hung mode in
  `hub2_crane.gd`. Header comment line 7 ("floor -164, central pit to -273") is wrong; fix it.
- Re-run the generator for A only (B, C, Halls untouched).
- Tests (`tests/test_hub2_dressing.gd`): every Dressing/A prop is below y -173 and has a ceiling over it (up-ray hits);
  nothing in Dressing/A on the roof slab; landing strip clear of props; kill height still < -273.
- Walk probe: from spawn, walk into the shaft's north opening, fall, assert the pilot ends on A's floor alive.
- Probe shots: from the landing looking at the lit heap, and one across the dark hall.

### Built (2026-11-14)

`tools/gen_hub2_dressing.gd` `_room_a()` rewritten on the real floor (`A_FLOOR` -273, `SHAFT_AXIS` (4,-273,-232), `A_LANDING`,
`A_MAIN_HEAP`, `A_ISLAND`, `A_ARCH_Z`); the roof dressing is gone. New: `Hub2Prop.Kind.LIGHT_SHAFT` (faint additive cold column,
appended to the enum so saved kinds keep their ints) + `Hub2Prop.pool_tint` (cold floor pool via the fixture list),
`Hub2Crane.hang_up` (ceiling-hung polar ring, rod hangers + anchor plates). Ring r 55 round the mouth, top flange y -181, hook 60 m
down. Overgrowth only in the lit island + a little moss at wall bases/container roofs/ring vines; 3 trees (2 island, 1 out of the
split container). 12 caged bulkheads at the arches, 2 lit. Tests: `test_room_a_is_dressed_under_its_roof_not_on_it`; hub2 tests green
(23 tests). Probe shots: landing, heap, across the hall, crane, up the shaft.

Findings:
- **The drop is not a plain walk from spawn.** D is a vertical chasm: spawn platform y 29 (z 18..90), then walls down to a pit at
  y -94 (z -6..-150), with a far ledge at y 0 (z -174..-180) that is the shaft's north opening. Walking north off that ledge falls
  to A's floor (-272.8) alive (`tests/_probe_hub2_drop.gd`, lands near (4,-273,-237) with forward held). Reaching the ledge from the
  spawn needs the D crossing (parkour); I did not prove a route.
- The pilot with no steering lands mid-mouth, not on the north-rim landing strip; the strip is just kept clear.
- The light column's first pass was too opaque (a glass tube); brightness cut ~3x. Judge it in play.
- Re-running the generator with a compile error in a dependency wipes B/C/A (groups are removed before the match fails); fixed by
  re-running. Don't commit a half-run scene.

## Room A storage hall (2026-11-14, grilled 8 + built, probe-shot, tests green, not played)

User's note after the correction build: A had floating crates and two trees, and should be the MAIN STORAGE HALL for cargo
containers, with the middle open for a giant boss fight, walls lined with shelves / crates / cranes, and a massive sealed hangar
door at the south bay. Supersedes the "dump" layout of the correction above (heaps, crushed forklift, scissor lift, trees, ring
crane are gone).

### Decisions

1. **Door:** the south bay (back wall z -471.2, x +-39, ceiling 54.7 m above the floor). Sealed twin-leaf hangar door, never opens,
   no hatch, no glow behind. The seam is the user's drawing: straight down from the top just left of centre, a diagonal step at
   mid height (44.6 % to 58.9 % of the way down), straight down to the floor just right of centre. Hazard chevrons both sides of the
   seam and a slanted band along the bottom, header box, jambs, floor track, ribs, rust streaks, two dead beacons. A slab behind
   the leaves fills the bay's back wall, which steps back 3.3 m toward its sides.
2. **Open middle:** |x| < ~63 (116-130 m wide, the whole length) is bare: no containers, crates, vehicles, plants taller than
   ankle height. Left in it: the cold light column and its pool, flat moss and grass tufts under it, dashed yellow bay lines at
   u = 63.4. The landing strip is inside it.
3. **Neat storage, mostly orderly:** a few top containers slid or askew, a few leaning racks, loose crates in the aisles.
4. **Bands along both long walls**, wall outward: pallet racking (runs of 5-9 bays, 4-8 m gaps), a 4 m aisle, container block A
   (4 rows, 3-6 high), a 4 m aisle, container block B (3 rows, 1-3 high). Blocks are 4 containers long with 9 m cross gaps holding
   pallet stacks and crate clusters. Forklifts, a reach stacker and pallet jacks parked in the aisle and alcoves.
5. **Cranes:** the polar ring and its 60 m hook are removed. `Hub2Crane.Type.WALL`: one runway girder per long wall at 76 m,
   gusset brackets at the pillars, three cantilever jibs each (reach 34 m, never over the middle), hooks parked 22-36 m up, a
   floodlight under each jib tip (one lit per wall, 26 m pool).
6. **Light column + island:** kept, island thinned to moss and short grass. No trees, no shrubs.
7. **Fit to the mesh:** every placement is ray-checked against hub2.glb (wall x per z, floor flat within 0.3-0.4 m, whole-stack box
   clear of the map and of everything placed). The hall's side walls alternate pillar faces at |x| 94 and recesses at 104.
8. **Defaults:** the dead bulkhead lamps on the pillars stay (now both sides), only A regenerated.

### Built

`tools/gen_hub2_dressing.gd` `_room_a()` + `_a_band` / `_a_stack` / `_a_cranes` / `_a_door` / `_a_bay_lines`;
`Hub2Prop.Kind.HANGAR_DOOR` (appended to the enum; `length` = door height, `Hub2PropBuild.hangar_seam_x`, no visibility range);
`Hub2Crane.Type.WALL` (+ `bridge_zs`, `trolley_xs`, `hook_drops`, `bracket_zs`). Counts: ~1470 containers, 156 racking bays,
~800 crates / pallets / totes. Perf (tests-of-record style probe, vsync off): A views 129-136 fps vs B aisle 124.
Tests: no trees/shrubs, middle open, containers stacked not floating, ground props rest on the floor, wall cranes + sealed door,
seam shape.

**Gotcha, cost real time:** bake with a WINDOW (`godot --path . --script tools/bake_hub2_dressing.gd`, no `--headless`). A headless
bake saves every container MultiMesh with an EMPTY transform buffer (dummy renderer) and all instanced containers, in B too,
render as nothing. The generator can run headless; the bake cannot.
