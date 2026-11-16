# hub2 final pass — audit

2026-11-15. Grilling in progress; nothing built. Ask: take hub2 as close to game-ready as possible.
It should read as an abandoned futuristic cargo facility (Tarkov-like: busy, believable, wrecked), with
openable doors and rubble you jump over, and must not hurt load time or frame rate.

## What is in place (measured 2026-11-15)

Probe: `tests/_probe_hub2_audit.gd` (windowed, eye-height shots in D, B, C, A; RTX 3060).

| Thing | Where it comes from | Count |
|---|---|---|
| Map shell | `assets/hub2.glb`, scale 0.6, ~1 km tall | 1 |
| Wall/floor wear | `Hub2Wear` swaps glb meshes for baked `assets/hub2_wear/*.res` + 690 decals | - |
| Dressing | `tools/gen_hub2_dressing.gd` -> `scenes/hub2_dressing_src.tscn` -> bake -> `scenes/hub2_dressing.scn` (75 MB) | ~4,700 nodes |
| Containers | `CargoContainer` | **1,914** (A 1,470 · B 439 · C 5) |
| Racking | Hub2Prop RACKING | A 858 · C 49 |
| Pipe runs | `Hub2PipeRun` | **290, every one a straight 2-point segment** |
| Moss / tufts | Hub2Prop | 465 / 415 |
| Pallets / totes | Hub2Prop | 411 / 191 |
| Lamps | high-bay 92, bulkhead 61, flood 23 | 176 |
| Crates | wood/metal, A 102 · B 64 · Halls 43 · C 17 | ~230 |
| Machinery | 6 cranes, forklifts, reach stacker, scissor lifts, dock doors | ~30 |
| Doors | none in hub2; `SlidingDoor` (blockout, slides up on `activate()`) exists in trial | 0 |
| Roof hangar door | specced, not built (`hub2-roof-door.md`) | - |

Perf at eye height: 41-91 fps, 0.75-3.9 M triangles, 19-860 draw calls (B yard and A worst).
First frame ~5 s after F6.

## Problems seen

1. **Pipes go nowhere.** Every run is one straight segment along an edge; no elbows into walls, no
   source (pump, tank, manifold) or sink (machine, floor penetration). Bundles stop dead mid-wall.
2. **Scatter reads as AI.** Tufts, moss blobs and lone crates spread evenly over open floor with no
   cause (no crack, no leak, no light); crates sit in loose grids in the middle of C's floor.
3. **Clipping.** A container stacks interpenetrate (A_across shot); the bake only warns on overlap.
4. **Containers are toy-like.** Saturated primary blues/oranges, clean, all closed, all the same 20 ft
   box. A is meant to be "the dump" but reads as neat stacks. 1,914 is also the main triangle cost.
5. **Big empty floors.** B's front half and A's floor are bare tile to the far wall; D (spawn shaft) is
   bare. Nothing at eye level to look at or move around.
6. **Nothing tells a story.** No sign of why it was abandoned: no barricades, no collapse, no
   evacuation mess, no broken lighting rigs, no blocked routes.
7. **No interaction.** No doors, no blocked halls, no jump-over obstacles; routes are wide-open boxes.
8. **Lamps** hang in an even ceiling grid with chains through nothing in B (B's ceiling is ~50 m up).
9. **Overgrowth** is the same moss blob/shrub everywhere, green on a blue-lit floor, no water source.

## Map facts for the build (ray survey 2026-11-15, `tools/survey_hub2_map.gd`, `tools/survey_hub2_openings.gd`)

| Space | Floor y | Extent (world) | Notes |
|---|---|---|---|
| B yard | 21.78 | x -162..-58, z -159..53 | ceiling 69.3; slanted west wall (x -151 at floor, leans out); exits only east at z -132.5..-125 and -44..-36.5 (8 x 7.3 m) |
| B west ramp pits | 21.8 -> 14.1 | x -170..-151; z -141..-122, -93..-74, -32..-13, 14..33 | 20 m wide sloped pits running under the west wall to a dead end. **Not rooms.** |
| B round pits | 4.95 | 6 x ~12 m octagons at x -133/-116/-98, z -153 and +46 | 17 m deep, open in B's floor |
| B balcony | 43.56 | x -71..-60, z -83..-24 | open to B on its west side; joins E's south cross corridor |
| D shaft | bottom -93.9 | x -12..12, z -181..11 | roof 58.1; side galleries at 21.78 (x -21..-12, 12..21) and 43.56 (same x), open to the shaft; bridges across at z -133..-126 and -44..-37 (deck tops 21.8, upper N bridge 43.6); north end z -148..-190 drops into A |
| Spawn platform | 29.04 | x -11..11, z 12..93 | roof 80.6; N edge open onto the shaft; east edge drops 7.2 m to a 21.78 passage (x 12..20, z 12..28) into the east gallery; side windows to the void at z 42..66 |
| Mid cross corridors | 21.78 | z -133..-125 and -44..-37, x -58..42 | 8 x 7.3 m |
| East corridor | 30.8 (ramps) | x 34.5..42.6, z -133..-37 | ramps 21.8 -> 30.8 at both ends |
| C link | 30.95 | x 42.5..69, z -114..-103 | 11.5 x 7.3 m |
| C dock hall | 30.95 | x 69.4..112.4, z -136..-82 | ceiling 47; one entrance (link, west wall); south dock ledge 38.2 at z -87..-82 is 7.3 m up with no way up, then a ramp to the plant room |
| Plant room (E room) | 43.56 | x 81..119, z -68..-19 | 15.4 high; west door to E south corridor (z -44..-36.5); north ramp from C's ledge; 12 m opening in the east wall onto the void |
| E galleries | 43.56 | as D galleries | cross corridors z -135..-126 (to a NW overlook x -42..-30 open to the void) and z -45..-39 (B balcony <-> plant room) |
| A hall | -272.77 | x -104..104, z -434..-114; south bay x -40..40 to z -470 | ceiling ~-173; walls have pilasters at z -423..-400, -365..-342, -311..-288, -237..-213, -157..-134 making 10 m deep recesses between them. **No enclosed bays exist.** |

Everything between the tubes and halls is void (outside). Corridor roofs (y 29.04) and A's roof slab
(y -164) are outside surfaces: never dress them.

**Adaptations forced by the geometry** (same intent as the decisions below):
- B's four rooms are built as **prefab cabins / sheds on B's floor** along the west wall, between the
  ramp pits. The ramp pits become vehicle ramps to a sealed lower level (jammed blast door at each
  bottom; one flooded, one with a loader that rolled down, one a sheltered scavenger camp).
- A's "10 bays" become the **recesses between the pilasters**: roll-up shutters in the back wall
  (sealed, some buckled) and two walk-in cold-store cages built inside recesses.
- The pilot's capsule does not shrink when crouching, so **no crouch-under gaps**: jammed doors leave
  a ~1 m side squeeze gap instead; blockage 3 keeps climb-over plus a side squeeze.
- C's 7.3 m dock ledge gets a steel stair so C and the plant room actually connect.

## Decisions

1. **Strip and re-dress.** All generated dressing (A/B/C/Halls groups in `hub2_dressing_src.tscn`) is
   removed. The prop library (`Hub2Prop`, `CargoContainer`, `Hub2Crane`, `Hub2PipeRun`) is kept and
   extended. Every area is re-dressed from hand-placed layouts where each object has a reason to be
   there. Target is ~600-900 placed objects for the whole map instead of ~4,700.
2. **Story: evacuated in a hurry -> scavenged for years -> structure failing.** Every messy object comes
   from one of three layers:
   - *Evacuation:* vehicles abandoned mid-task, container left hanging on a spreader, dropped pallets,
     a terminal still on an alarm screen, a lowered checkpoint shutter.
   - *Scavengers:* containers pried open and emptied, crates smashed, sandbag/container barricades at
     choke points, a camp (fire, bedrolls), spray-paint marks and arrows.
   - *Decay:* collapsed ceiling + pipes in halls (the jump-over rubble), a fallen crane girder, leaks
     with moss/growth only under them, dead lights.
3. **Area jobs.** D = freight spine (ceiling rail + one stalled carrier, catwalks on the low bridges,
   spawn-end checkpoint). B = container yard (rows with aisles, 2 gantry cranes, one with a hanging
   container, crane booth, charging bay, main scavenger camp). C = dock + inspection (dock doors,
   inspection tables, scanner arch, foreman office with a door, racking, opened goods). E = service
   halls (doors, a plant/pump room most pipes trace back to, lockers, collapse rubble, barricades).
   A = deep storage the spine dumped into (fallen-container pile under the shaft, crushed/split boxes,
   heavy growth only in the light column; the rest dark and sparse).
   **Inside-the-map rule (user):** every placed object is checked by a test, not by eye: floor hit
   straight below, ceiling hit straight above with a downward-facing normal (a ray that reaches sky
   means outside), and within the area's measured extents. The last pass dressed A's outside roof; a
   test failure blocks the bake.
4. **Performance budget + build rules.** Probe at fixed eye-height spots in every area (RTX 3060,
   vsync off, held camera): >= 100 fps, < 1 M triangles in view, < 400 draw calls, first frame < 3 s
   after F6. Over budget = cut objects until it passes.
   - Occlusion culling ON (project setting + baked `OccluderInstance3D` from the map's walls/floors).
   - Everything ships pre-built: meshes saved as resources, repeats as MultiMesh, nothing generated at
     load. Moving parts (doors) are small scenes.
   - Small clutter has a visibility range (~25-40 m).
5. **Doors: F to open, three types, no keys.** Uses the existing interaction panel (OPEN / CLOSE),
   F toggles, stays where left. Personnel swing doors (~1 x 2.2 m, 0.5 s, swing away from the
   player) in halls/offices/plant room; roll-up shutters (~1.5 s) at C docks and the D checkpoint;
   unpowered sliding blast doors that do NOT open, some jammed part-open (crouch-slide gap, squeeze
   gap). Doors that can't open look welded/sandbagged/blocked by a container. ~12-18 doors. Collision
   + hinge/slide, no physics.
6. **~6 blockages, each from the story, each passable with an existing move** (pilot: jump 3.0 m,
   vault ~1.1 m tall / <=0.7 m deep, mantle, crouch-slide):
   1. hall near spawn, ceiling panel + pipe collapse -> vault (~1 m x 0.6 m)
   2. E corridor to C, sandbag/crate barricade -> vault or step-up
   3. E corridor, big slab/rebar/cable-tray collapse -> climb over (~2-2.5 m) or crouch-slide gap
   4. B-E link, blast door jammed ~1 m open -> crouch-slide
   5. plant room access, burst pipe + fallen cabinet -> vault
   6. B aisle, toppled container -> mantle (~2.6 m) or go around
   Never a trap, main route always open. Rubble kit: slab chunks, rebar, ceiling panels, cable tray,
   broken pipe, debris; each pile hand-composed of 5-12 pieces; a few simple box colliders per pile.
7. **Side spaces get jobs + doors** (from `hub2-plan.png`; each one is ray-verified as enclosed before
   it is dressed):
   - B west bays: 1 crane control + yard office (terminal bank, one on an alarm screen, yard-map board);
     2 vehicle workshop (forklift on a lift, tool walls, drums, shutter); 3 lockers + break room
     (pried lockers, vending machine, scavenger use); 4 generator room (dead generator, fuel tanks,
     cable trays to B's crane rails).
   - D north room: security checkpoint (scanner gate, guard booth + shutter, emptied weapon rack,
     last-stand sandbags).
   - High east room: plant/pump room, the source of the main pipe network (pumps, tanks, manifolds)
     feeding E, then down into B and C. Open-roof box above it: roof cooling vents, fans, ducts, snow.
   - A's 10 bays: cold storage; 8 shuttered (some buckled), 2 open (one flooded + overgrown, one with a
     scavenger body + gear).
   - **Pipes always have two ends (see 7 above):** plant room / generator room -> consumer (crane, dock, machine,
     floor penetration). No free-standing segments.
8. **"Used future" (EARTH 2329), industrial first, dead sci-fi on top.** Mag-rail carrier stalled on
   D's ceiling rail; 20 ft / 40 ft / reefer containers + sealed hard-shell cargo pods; forklifts become
   cargo loaders (squat, legged or tracked, cab cage) + a powered loader exoframe slumped in a charging
   cradle; drone racks with dead quad drones; CRTs stay; dead holo-sign emitter rings, 1-2 flickering
   floor-projected bay numbers, LED strips with dead sections; hex blast doors, keypad panels dark or
   smashed; one operator logo + stencil scheme (company name, bay codes). All PS1 low-poly, vertex colour.
9. **Colour + wear.** ~60 % of containers/pods in the operator livery (faded oxide red, white stencils,
   logo); the rest 3-4 other lines in muted navy / olive / grey-white / faded mustard. No saturated
   colour except safety (hazard stripes, fire red, loader orange). Vertex-colour wear: rust streaks
   from roof edges and castings, grime toward the floor, sun-fade on top faces near the open roof,
   chipped doors/edges, water stains under leaks, soot near fires. ~30 % containers open/pried with
   walk-in empty interiors (floor + interior collision); dented walls, a crushed corner, one burnt
   shell. Scavenger spray-paint set (arrows, X = emptied, skull = danger, tallies) only on things they
   touched.
10. **Lighting: power is out, light only from sources with a reason.** Daylight through roof gaps /
    broken skylights; emergency battery circuit (a few red/amber bulkheads + beacons at exits and
    checkpoints, 2-3 flickering); scavenger light (B campfire, locker-room work lamp, chem-light trail,
    camp string light); live machines (powered terminals, one flickering bay projection, a sparking
    junction box); A's light column. High-bay lamps stay as dark fixtures, some fallen/smashed or
    hanging on one chain, only where a ceiling is close enough to hang from; B (~50 m ceiling) uses
    gantry-mounted floods instead. Darker overall, navigate pool to pool. Existing lamp-pool system +
    <= 6 shadowed real lights on screen.
11. **Roof hangar door: keep, pre-bake it.** It IS built (`RoofDoor` node, `hub2_roof_door.gd`) but cuts
    the roof, builds the frame/leaves/snow mesh and bakes the cover map in code on every F6. Move all of
    that offline: the hole goes into the wear bake + collision once, frame/rails/leaves saved as meshes,
    cover map saved as a texture; runtime only runs the falling-snow shader. Story: jammed open by the
    power cut, leaves intact, snow on the bridges below. Add a smaller broken skylight over B as B's
    daylight source.
12. **No loot in this pass** (user: "dont worry about loot yet"). No `WorldItem`s placed in hub2.
13. **Build it all in one go, no stops for approval.** Hand-placed real nodes in
    `scenes/hub2_dressing_src.tscn`, one group per area/room, objects named for their reason; no scatter
    generator. Pre-bake checks as a test: inside-map rays, no overlapping collision (hard fail), pipes
    have source + destination, blockages passable, perf budget. Order: D -> E halls/plant/blockages ->
    C -> B + side rooms -> A -> roof door pre-bake. Fixed eye-height screenshots per area, reviewed
    critically (clipping, floating, no-reason placement) and fixed before moving on.

## Built (2026-11-15) — not yet played, uncommitted

- `tools/layout_hub2.gd` writes 815 hand-placed objects into `scenes/hub2_dressing_src.tscn` and refuses
  to save on any collision overlap, box cutting into the map, or object under open sky (A's shaft
  mouth excepted). Last run: 0 problems. Bake: `tools/bake_hub2_dressing.gd` (doors stay live).
- New kit: `Hub2Piece` (+ `hub2_piece_build.gd`, `hub2_piece_build2.gd`, ~65 kinds), `Hub2Door`
  (swing / shutter on F, jammed blast). 14 doors. All 6 blockages built (vault ridge, sandbag
  barricade, slab collapse, jammed blast door 1 m squeeze, burst header, toppled 20 ft).
- Perf (held camera, 3060): 159-205 fps everywhere; dressing costs 0.2-0.6 ms. Baked scene 25 MB (was 75).
- NOT done: roof door pre-bake (still built at load), B skylight hole (frame only, no light), occlusion
  culling, splitting the map wear mesh (~680k tris, ~3 ms; puts 3 views over the 1 M triangle budget).
- Known failing: `test_the_baked_dressing_matches_its_source` (source 859 box shapes vs bake 844).
