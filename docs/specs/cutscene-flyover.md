# Cutscene shot 4: flyover

2026-10-14. Grilled with the user from their Blender screenshot (camera tight behind the main
engine, building small below), then built the same day. A medium chase shot: the ship flies over
Ichi about 1000 ft up in the blizzard, the building drifts slowly left and down under it, and near
the end the ship starts to bank left. The cut lands mid-bank.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Ship | `sinestro_1.glb`, the in-flight Sinestro from shot 1, at scale 1.0 (the parked Sinestro2's size) |
| 2 | Scene | Standalone `scenes/cutscene_flyover.tscn`, root `Flyover`. Instances `OP_1` with Ichi's environment, sun and `Storm`. No Pilot9, no parked ship |
| 3 | Camera | Chase rig: flies with the ship on its straight, level flight line, tight behind the main engine, a little right of centre and above, looking forward and down. It does not roll with the bank |
| 4 | Camera sway | Slow wander (±0.4 deg, ±5 cm, 0.3-0.5 Hz) plus a faint buzz (a few hundredths of a degree). Independent of the ship, unchanged through the bank |
| 5 | Ship float | Bob ±0.15 m at 0.5 Hz, roll ±1.5 deg at 0.35 Hz, pitch ±0.7 deg at 0.6 Hz, yaw ±0.4 deg drift |
| 6 | Bank | Starts at 2.1 s with an ease-in (still accelerating at the cut): left wing down to ~20 deg at 3.0 s, nose 4 deg left, slides 0.6 m left of the camera's line |
| 7 | Height / speed | ~300 m (1000 ft) above the ground at 50 m/s. The building crawls about a third of the frame, left and down |
| 8 | Blizzard | Full Ichi flakes / wind / streaks around the ship. Fog pushed out so the ground and building read as a pale ghost (60-70% fogged); gusts thicken it until the building nearly vanishes. No ground drift (it lives 300 m below) |
| 9 | Engine glow | Hard cel glow discs in the main and both pod nozzles, plus an OmniLight in the main nozzle so passing flakes catch it |
| 10 | Ribbons | Shot 1's three trails. The main one passes under the lens, all three fade out near the camera, bend in the crosswind, and swing with the nozzles when the bank starts |
| 11 | Path | Heading over Ichi toward the parked-ship spot, passing right of the building. Building centre-left at 0 s, lower left at the cut; the bank reads as the start of the descent circle |
| 12 | Timing | 3.0 s, hard cut in and out. Opens mid-flight with the trails already streaming (pre-warmed), holds the 3.0 s mid-bank frame |

Not in it: sound, the pilot, landing gear, a camera roll.

## How it works

`scripts/cutscene/flyover.gd` (`FlyoverShot`). Everything is a function of the shot time, so
seeking or restarting shows the same frame:

- `flight_at(t)`: the straight, level flight line (start point + heading + speed). Holds for
  negative t too, which is how the trails pre-warm.
- `ship_at(t)`: flight line * bank (slide, yaw, roll) * float. The trails ask it about the past.
- `camera_at(t)`: flight line * the fixed chase offset * sway. Never sees the bank or the float.
- Trails: `IntroSpaceTrail` with two new knobs, both off by default so shot 1 is untouched:
  `wind` (m/s; trail points blow downwind, easing up to wind speed so the ribbon curves) and the
  trail shader's `near_fade_gone` / `near_fade_full` (camera distances it is gone at / whole from).
- Storm: Ichi's `Storm` node with only the fog distances changed and the drift off.

## Built

2026-10-14, framed from probe shots (`tests/_probe_flyover_shot.gd`) against the reference.
Tests: `tests/test_cutscene_flyover.gd`. Where it departs from the decisions above:

- **Height 450 m, speed 70 m/s** (not 300 m / 50 m/s). OP_1's building is ~170 m across, so at
  300 m it filled the frame. 450 m keeps it small, and 70 m/s gives the crawl (about 20% of the
  frame left and ~15% down over 3 s).
- **Flies north across the plateau toward the building**, which sits on the canyon's lip; the
  canyon beyond fogs out into a pale void top left. It does not head for the parked ship's spot
  (that is south of the building, behind the camera's view).
- **Ground past the map is painted, not built** (2026-10-14, replaced the snow skirt mesh,
  which still showed a line where it met the map). The camera never sees the horizon (38 deg
  down, fov 50), so everything that isn't map is the sky's lower half:
  - `shaders/cutscene/flyover_sky.gdshader` runs each below-horizon eye ray down to a flat plane
    at `ground_y` (0) and paints that spot as snow, with soft world-anchored mottle (4%, ~120 m
    patches) and the storm's fog at the plane distance. It's sky, so the ship's outline still
    draws over it and nothing slides as the camera moves or banks.
  - `shaders/cutscene/flyover_edge.gdshader` is a full-screen depth pass that fades the map's
    outer 80 m into the same paint (fully inside 25 m, deeper than the ragged edge's notches).
    West/east/south measure from the terrain's bounding box. North measures from the canyon
    lip, found per column from the mesh at load, because the canyon's walls fall away out of
    sight and the lip is the edge you see. Terrain below the plane (the canyon walls) is painted
    as the plane point behind it, at that distance, so it fogs the same. It also repaints sky
    pixels with exactly the sky's colour, which wipes the terrain's outline hull off them. It
    draws after the crease ink and fogs itself.
  - The ship (above 200 m) and the building (a per-cell height span baked from its mesh) are never
    painted, nor is anything within 6 px of them, so their outlines survive. Testing "above the
    terrain" instead failed at the lip: depth read back off the canyon wall at a grazing angle
    lands tens of metres off.
  - `ground_color` (0.325, 0.35, 0.415) was matched against the real terrain in a probe with
    fog off (106,114,136 vs 104,113,136 on screen).
  - Transparent draw order in this scene: storm fog -100, crease + edge pass 0 (the pass sorted
    100 m ahead of the camera so it lands after the crease), snow 1, trails 2, nozzle glows 3.
  - Side effect: the area above the map now reads as fogged ground (pale near-white). Before it
    was the sky's lavender ground colour, which didn't match the fog.
- **Fog** visibility 2400 m, gusts 1300 m, so the building comes through as a ghost at 600-900 m.
- **Wind flipped for this shot** (`wind_direction` (-0.94, 0.33)): it blows off the ship's right,
  so the near pod's trail blows out of frame instead of sweeping across it. Trails take half the
  wind (13 m/s) and the pod trails are half the main one's width.
- Camera: offset (-1.5, 6.5, -11.5) behind the nozzle, looking at (14.3, -12, 9) in the flight
  frame (about 30 deg left of the nose, 38 deg down), fov 50. Ribbons fade out 4-12 m from it.

## Speed lines + engine heat

2026-10-14. Grilled with the user after the first look: the snow blew across the ship's path
(the storm wind ran nearly sideways while the ship flies +Z), which read as wrong, and the
engines wanted more on top of the trails and glow discs.

| # | Topic | Decision |
|---|-------|----------|
| 1 | Snow | Streams straight back along the flight line, parallel to the trails, like speed lines: the storm wind becomes a headwind (nose to tail, world -Z) for this shot only. Density and gusts unchanged; Ichi gameplay untouched |
| 2 | Snow streaks | About 3 m (streak time ~0.12 s, was 0.04), this shot only: near flakes rake past as lines, far ones stay short dashes |
| 3 | Trails | Unchanged. They keep their own sideways wind |
| 4 | Heat shimmer | A soft, length-faded warp cone behind each nozzle: ~6 m on the main engine at full strength, ~3 m on each pod at half. No colour fringing, no blur. Drawn before the storm fog, so it bends the ground and building below while fog, snow and trails stay crisp over it |
| 5 | Embers | Small velocity-stretched sparks shed in world space from the nozzles: leave white-hot, cool to the engine cyan (0.55, 0.88, 1.0), fade. ~30-40 on screen from the main engine, a few from each pod. Pre-warmed, so the shot opens with them streaming |

Not in it: an exhaust plume / shock diamonds, pulsing thrust (offered, not picked).

### Built

2026-10-14, from probe shots (`tests/_probe_flyover_shot.gd`, plus `tests/_probe_flyover_fx.gd`
for effects on/off at fixed shot times with the snow hidden, since it runs on real time).

- **Snow**: on the scene's `Storm`, `wind_direction` (0, -1) (world -Z = nose to tail at heading
  0) and `streak_time` 0.12. No code change: the streaks are drawn along the wind, which now runs
  the way the camera sees them move. Trails keep their `wind` (-13.2, 0, 4.6).
- **Heat shimmer**: `shaders/cutscene/heat_shimmer.gdshader` on an open cone per nozzle, built by
  `FlyoverShot._build_shimmer()` as children of `Ship`, so it banks and floats with it. It starts at
  the glow disc's rim and flares `shimmer_flare` (3x) wider by its far end. It redraws the opaque
  screen copy nudged by drifting 3D value noise (in cone space, moving back at 9 m/s, on the shot
  clock), and the nudge fades in off the lip, dies out by the far end and softens at the cone's
  silhouette. render_priority -101. Strength 0.025 of the screen, pods at `pod_shimmer` (0.5).
  - 2026-10-14 "make it stronger": it was barely there at 0.005-0.025 because of the silhouette
    softening, not the strength. The chase camera looks almost straight down the cone, so its
    whole surface was "near edge-on" and smoothstep(0.05, 0.7) on |N.V| faded nearly all of it
    out. Now smoothstep(0.0, 0.2), and the length fade holds to half way (was 30%). The nacelle's
    rim now visibly melts and wobbles behind the exhaust. The crease ink is drawn after it
    (priority 0) and stays put, so the rim warps a little past its own ink line; read as heat, but
    it's the first thing to check if it looks glitchy.
  - **(First pass, before the fix below) It was subtle in this shot, by geometry.** The cone points almost straight at the camera, so
    most of what is behind it is the engine's own nacelle and the main trail (drawn later, on top).
    The fogged ground behind it is near-uniform pale, which no warp can visibly bend. What reads is
    the nacelle rim wobbling (seen in the on/off probe at 3.0 s). Whether the building's ghost
    visibly bends as it passes behind a cone is unchecked; `shimmer_strength` is the knob.
- **Shimmer OFF** (2026-10-14, user: "turn the shimmer off"): `shimmer_on` export on `Flyover`,
  default false, so no cones are built. The code and tuning stay; set it true to bring it back.
- **Embers**: `FlyoverEmbers` (`scripts/cutscene/flyover_embers.gd`, node `EngineEmbers`,
  render_priority 4, additive `shaders/cutscene/engine_embers.gdshader`). Rebuilt each frame from
  the shot time like the trails: ember n of nozzle k is born at (n + hash) / rate, starts at the
  nozzle with the ship's velocity plus a 12 m/s kick out of it and up to 9 m/s of spread, and is
  dragged toward the storm wind (exponential, 1.6/s). The streak runs along its camera-relative
  motion. 150/s from the main engine and 16/s per pod, life 0.27-0.45 s: about 65 alive and
  roughly 35-40 on screen. White-hot (HDR 3.0) for the first 30% of life, then cyan (1.6), fading
  from 50%.
  - 2026-10-14 "make the sparks smaller": width 0.09 -> 0.05 m, streak 0.025 -> 0.015 s of
    travel, min length 0.12 -> 0.08 m. Count unchanged.
- **Pod trails at half opacity** (2026-10-14, user: "same transparency as the main engine
  trail"). The main trail only looks see-through because of its near-camera fade (it passes
  4-12 m from the lens: ~0.75 at the nozzle down to ~0.2 at the frame's bottom); the pods stay
  past 12 m and drew at full 0.95. New `IntroSpaceTrail.nozzle_opacities` (per nozzle, carried in
  COLOR.a to engine_trail.gdshader; empty = 1, so shot 1 is untouched), set to (1, 0.5, 0.5) here.
- Transparent draw order now: shimmer -101, storm fog -100, crease + edge pass 0, snow 1,
  trails 2, nozzle glows 3, embers 4.

## Dead city + storm (2026-10-16)

Grilled with the user ("instead of the ichi scene building ... some destroyed building like in
descent scene ... instead of the blizzard, the storm that the ship just flew into in descent and
cockpit storm"). Story order is cockpit storm -> descent (the trail breaks out under the deck) ->
this shot, so the ship is under the deck, over the dead city the descent showed.

| # | Topic | Decision |
|---|-------|----------|
| 1 | Place | The descent's dead city. Ichi (`OP_1`, the canyon) is gone from this shot: generated snow ground, ruins and rubble |
| 2 | Hero ruin | A gutted high-rise skeleton: exposed floor slabs on bare columns, facade torn away down one side, top floors snapped off, snow on every slab. Built finer than the descent's 4 km boxes, since it is seen from ~600-900 m |
| 3 | Framing | Unchanged: 450 m, 70 m/s, same camera / sway / float / bank (20 deg left from 2.1 s). The skeleton (~60 x 60 m, ~220 m tall) takes OP_1's screen position (centre-left at 0 s, lower left at the cut, ship passing right of it); moved toward the flight line if needed to hold OP_1's screen size |
| 4 | Surroundings | A thin slice of the city: ~8-12 shorter ruins from the descent's kinds (snapped stumps, a toppled tower, a facade, a crane), rubble mounds, faint buried street lines on a grid. All fog off with distance so the skeleton stays the subject |
| 5 | Storm | The descent storm from inside, replacing the blizzard: dim slate-violet light, dark violet fog with a teal cast (the skeleton is a dark ghost, not a pale one), heavy snow with the cockpit-storm character (wind lanes, mixed specks / clumps) still streaming nose to tail as speed lines |
| 6 | Lightning | One main cyan double flicker at ~1.2 s, rimming the slabs and flooding the snow, dying over ~0.4 s; a faint far flicker at ~2.6 s in the bank |
| 7 | Ship | Engine glows + OmniLight kept. A faint cool-teal fresnel rim on the hull; the main flash pops the hull hard too |

Consequences: the painted ground plane stays (it is just the snow now, no map edge to hide) and
gains the street grid; the edge pass (`flyover_edge.gdshader`, lip + building textures) goes.
Trails, embers and the off-by-default shimmer are unchanged. Intro_Movie plays it as shot 4 with no
change there.

### Built

2026-10-16, tuned from probe shots (`tests/_probe_flyover_shot.gd`, now with a `nosnow` arg and
10 settle frames: at 4 the heavy snow made it grab stale frames with torn-looking trails).

- **City**: `FlyoverCity` (`scripts/cutscene/flyover_city.gd`, node `City`) extends `DescentLand`
  and reuses its ruin kinds and box helpers, overriding `_ready` to build only this slice. Hero at
  OP_1's old spot (`hero_at` (0, 0, 210), grid 12 deg), 60 m square, 220 m: a clad 20 m podium,
  a 5 x 5 column grid, 0.8 m slabs every 5 m (`STOREY`) with 0.5 m snow, spandrel bands on three
  sides torn at a ragged height per bay (lower toward the open -X side), slabs partial then
  missing above 72% (`break_start`), ragged columns poking past, one slab hanging off the break.
  Same screen size as OP_1 at the same spot, so it did not need moving. 11 neighbours from the
  `neighbours` table (hero-relative): snapped stumps, two facades, a crane, a toppled tower, a
  smaller skeleton, a setback; 16 rubble mounds within 420 m. `concrete_shade` 0.55 darkens the
  descent's concrete (made for 4 km of pale fog) so the ruins sit under the dark fog.
- **Ground**: the sky's painted plane stays, now `ground_color` (0.3, 0.31, 0.37), plus buried
  streets (`flyover_streets()` in flyover_ground.gdshaderinc): 110 x 130 m blocks on the hero's
  grid with the hero mid-block, 16 m troughs 12% darker, wobbly and patchy, gone by 700 m. The
  edge pass (`flyover_edge.gdshader`, lip and building textures) is deleted.
- **Storm**: fog `near_color` (0.07, 0.07, 0.11) / `far_color` (0.09, 0.12, 0.14), visibility
  2000 / gusts 1200. These globals are raw linear values: the old 0.36 showed as a pale
  near-white, so the numbers look far darker than they render. Sun (0.66, 0.66, 0.8) at 0.12,
  ambient (0.32, 0.33, 0.42); dark sky gradient (never in frame).
- **Snow**: Ichi counts, `fine_opacity` 0.5 so the city shows through. New opt-in Storm knobs
  (all 0 by default, Ichi untouched): `lane_amount` 0.8 m S-lanes over `lane_size` 40 m with the
  streaks following the bend, `clump_chance` 0.12 (3x wide, short), `shade_chance` 0.3 (flakes
  tinted `shade_color`). A per-flake lane phase made a chaotic cross-hatch; the lanes must be one
  coherent field.
- **Lightning**: `flash_at(t)`: hits at 1.2 s and 1.32 s (0.8), 0.02 s rise, 0.09 s decay, then
  0.25 at 2.6 s. Drives `FlashLight` (cyan directional travelling (-0.45, -0.45, -0.77), energy
  1.2 at full), lifts the fog globals 12% toward cyan and the painted ground 45%. First pass
  (energy 2.5, fog 35%) washed the whole frame out.
- **Hull rim**: the ship's cel materials' `fresnel` set to (0.42, 0.66, 0.7) at 0.3, lerping to
  cyan at 0.6 in the flash.
- Tests: `tests/test_cutscene_flyover.gd` (crawl test now on the hero's mid-height; new: no OP_1,
  city counts/kinds/heights, flash timing, dark fog + flash light, rim pop, snow knobs off by
  default). Suite: 1254 tests, only the 2 known test_ichi_parked_ship failures.

## Ground mist (2026-10-16)

User, after the dead city pass ("looks really good"): add fog so the ground / building
intersections are hidden. Built straight from that, probe-tuned.

- `shaders/cutscene/ground_mist.gdshader`, a full-screen depth pass (`GroundMist`, built by
  `FlyoverShot._build_mist()`, `mist_on`). Each pixel's world point gets mist by its height over
  the snow: `mist_density` 0.9 at the snow, squared falloff to nothing by `mist_height` 55 m, the
  top wobbling 15 m with the noise. Patches ~180 m across thin it by half (`mist_breakup`) and
  drift downwind at 6 m/s on the shot clock (seeks repeat). Sky pixels are run down to the painted
  plane, so the ground and the ruins' feet take the same mist. Colour (0.5, 0.54, 0.6), paler than
  the ground so it reads as mist; the storm's distance fog goes over it; the flash lifts it 50%
  toward cyan.
- Sorted like the old edge pass: priority 0, kept 100 m ahead of the camera (`MIST_SORT_DEPTH`) so
  it draws after the crease ink and softens the ink at the ruins' feet too. Draw order: shimmer
  -101, storm fog -100, crease + mist 0, snow 1, trails 2, glows 3, embers 4.
- First pass (45 m, 0.8, (0.42, 0.46, 0.52)) worked but read as softness, not mist.

## City detail pass (2026-10-16)

User, after the ground mist: "add another pass of details. city details ... make the city below the
ship look better, more believable". Grilled. The read before: about a dozen buildings on an empty
grey floor, no scale cue, one tone, nothing crossing the grid. Density and scale details in one pass.

| # | Topic | Decision |
|---|-------|----------|
| 1 | Scope | Density and scale details together |
| 2 | Packed city | Every block on the street grid (110 x 130 m) split into lots: ~60% gutted roofless shells and snapped stumps 15-50 m, ~25% collapsed lots (low heaps in the footprint), ~15% empty snow lots. Taller toward the hero; nothing new within ~110 m (half the hero's height) of it |
| 3 | Extent | To the fog, ~1.5 km round the hero; past ~800 m plain boxes, no detail; the painted streets reach as far |
| 4 | Scale details | Window holes in the material (dark rows, 4 m floors); snow-buried cars along the curbs and jammed at a few crossings; rooftop clutter (tanks, stair housings, AC boxes) on stumps with a top; snow drifts against the upwind walls burying the ground floors. No streetlights, signs or road markings (sub-pixel at ~0.6 m/px) |
| 5 | Highway | One elevated highway, ~25 m deck on ~20 m pillars, diagonal to the grid, ~200 m right of the hero on screen, one span snapped with its two ends dropped toward each other, stalled cars on the deck |
| 6 | Colour | Five tones within ~+-10% value (two cool concretes, warm stone, rust brick, dark weathered block), one per building; near-black windows; pale snow; the hero a touch lighter than the city |
| 7 | Landmarks | The 11 neighbours stay where they are, with the new tones and windows, the city packed round them. The 16 rubble mounds move into the streets and crossings. The toppled tower lies ACROSS a street |
| 8 | Mist | Lowered and thinned so the street detail shows: ~25 m, ~0.6, patches kept, tuned from probe shots |

Consequences: all in `FlyoverCity` and the flyover's own shaders, the descent untouched; one seed
keeps it the same every load; boxes merged per colour into raw arrays (thousands of boxes).

### Built

2026-10-16, tuned from probe shots (with and without snow).

- **Packed city** (`FlyoverCity._packed_city`): every block within `city_radius` 1500 m split into
  2-3 x 2-3 lots (jittered splits, 0.5-2 m party-wall gaps, `pavement` 3 m). ~2900 lots. Shells
  (`shell_chance` 0.35: four 1.2 m walls in 2-4 runs of ragged height, a run missing now and then,
  sometimes a piece of floor inside), stumps (0.25: solid, a sheared stub, rooftop clutter),
  collapsed (0.25: 3-6 tilted heaps, sometimes one wall fragment), the rest empty. Height
  `height_near` 50 -> `height_far` 15 by 1.2 km, x 0.55-1.1, on 4 m floors, 8-56 m. Lots skip
  `clear_radius` 110 m, the landmarks' keep-out circles and the highway. Past `detail_radius`
  800 m shells and stumps are one plain box and collapsed lots one heap.
- **Windows**: a 16 px tile (one `window_bay` 3.5 m x one `window_floor` 4 m, black hole in the
  middle half) on world-metre UVs that `_box` writes on vertical faces while `_windows` is on
  (packed walls, and the snapped / setback / facade landmarks; not the hero, crane, skeleton or
  toppled tower). DEPARTURE: the cel base shader's `base_texture` clamps (Godot's default), so the
  tile could not repeat there. New opt-in `tile_texture` in `cel-shader-base.gdshader` (repeat on,
  white by default, multiplied over the albedo on the raw UV); nothing else sets it. PixelLook does
  not carry it onto its twins (PIXEL is off by default).
- **Tones**: five (`TONES`), the hero `HERO_TONE` a touch lighter. DEPARTURE: `concrete_shade`
  0.55 -> 1.8. The storm fog swamps what the walls add: at 0.55 (and at 1.0) the windows and the
  tones did not show at all (a pure-red test proved both were there). At 1.8 the overall
  brightness barely moved, the windows read as dot grids and the brick shows rust. The hues were
  pushed further apart than "+-10%" for the same reason.
- **Drifts**: DEPARTURE: the big drift is in the LEE (-Z wall, the wind blows toward -Z), not
  upwind: snow piles up downwind of obstacles, and that is the side the camera sees. A small one
  banks the windward wall. Prisms (`_wedge`) in snow, detail range only.
- **Cars**: `_street_cars`, both kerbs of every street within `car_radius` 800 m, one per 6 m slot
  at `car_chance` 0.3, never across a crossing; `jam_count` 5 crossings with 8-14 cars at random
  yaw. Dark body + cabin + snow cap (thick on half). ~2600 in the streets.
- **Highway**: through hero-frame (0, 330) at 45 deg, 25 m deck at 20 m on pillars every 40 m
  with crossbeams, parapets and median, clipped to the city's circle (~3 km). ~750 stalled cars on
  the deck (6 lanes, 35% per 7 m slot). Snapped span at `break_along` -350 m (at 0 it hid under
  the wing pod): both halves tipped 18-28 deg toward the gap, cars slid toward the ends, heap
  below. In frame at the cut, right side.
- **Landmarks / rubble**: the 11 neighbours kept; the toppled tower moved to (55, 260), lying
  across the x = 55 street. Rubble mounds snapped onto street lines (30% crossings), 10-22 m.
- **Mist** 55 m / 0.9 -> 25 m / 0.6 (`mist_height`, `mist_density`); the ruins' feet still soften.
  **Streets**: block size and width now the city's (`FlyoverCity.street_block` / `street_width`),
  `street_radius` 700 -> 1500.
- **Mesh**: `_box` overridden to append to raw packed arrays per colour (taken out of the dict
  while appending, else every append copies), bottom faces dropped on upright boxes. ~870k verts in
  13 meshes; the build takes ~0.4 s.
- Tests: 4 new in `tests/test_cutscene_flyover.gd` (lot count, kinds, ~60% standing, reach, clear
  zone, taller near the hero, highway length + snapped span in frame at the cut + cars, window
  tile on every mesh). Suite: 1259 tests, only the 2 known test_ichi_parked_ship failures.

## Nozzle propulsion (2026-10-16)

Grilled with the user from a pixel-art reference (a thruster with a big soft white-blue bloom
at the nozzle, a cyan beam, a cloud of small white and cyan dot sparks around it, dark smoke).
The work is all at the nozzle, around the trail.

| # | Topic | Decision |
|---|-------|----------|
| 1 | Smoke | None |
| 2 | Trails | Unchanged: no jitter, no wobble. The existing streak embers (150/s main, 16/s per pod) and the pod glow discs also stay as they are |
| 3 | Bloom halo | Main engine only. A soft camera-facing halo ~5 m across (about 3x the nozzle), white-hot centre fading to pale cyan, sitting behind the existing 1.7 m disc (which stays the hard core). Flickers about +-8% in size and brightness several times a second. Size + brightness are exports |
| 4 | Dot sparks | A new layer, separate from the streaks. Small bright round dots in two sizes and two colours (white-hot, which catches the glow, and cyan). Born in a ring just outside the trail's edge near the nozzle, live ~0.15-0.3 s, wink out hard (no fade), drift back slowly relative to the ship so they hang around the engine on screen; about 1 in 6 is flung wider |
| 5 | Pods | Get dot sparks too, about a fifth of the main engine's count, smaller dots. No halo |
| 6 | Count | ~150/s from the main engine (~35 on screen), ~7 on screen across the pods. Rates are exports |
| 7 | Shape | Round, hard-edged, camera-facing discs (not the reference's pixel squares) |

Like the trails and streaks, both are functions of the shot time: seeking shows the same frame
and the shot opens with the sparks already crackling. The lightning flash doesn't touch them.

### Built

2026-10-16, from probe shots (`tests/_probe_flyover_shot.gd`).

- **Halo**: `MainHalo`, a unit QuadMesh built by `FlyoverShot._place_glows()` as a child of
  `Ship` on the main nozzle, scaled to `halo_size` (5 m). `shaders/cutscene/nozzle_halo.gdshader`
  turns it to the camera in the vertex shader (size from the node's scale), additive, no depth
  test (light spilling over the hull), falloff (1 - r)^3, white to (0.7, 0.93, 1.0) by half
  radius. Flicker = three summed sines at ~9 Hz on the shot clock, `halo_flicker` 0.08 of size
  and brightness. `halo_energy` 1.2. In the pale storm frame it reads mostly where it crosses the
  dark nacelle (whitening the end of it); against the sky it barely adds anything.
- **Dot sparks**: `FlyoverDotSparks` (`scripts/cutscene/flyover_dot_sparks.gd`, node `DotSparks`
  built by `_build_dots()`), `shaders/cutscene/dot_sparks.gdshader` (blend_mix, hard disc, white
  HDR 3.0 or cyan (0.2, 0.85, 1.0)). Kinematics in the SHIP frame (unlike the streak embers),
  so they hang by the engine: born on a ring 0.7-1.3 m off the nozzle's centre line (first probe
  had 0.45-0.95, most dots sat on the glow disc and vanished) up to 1 m behind the lip, drift
  back 5 m/s (+-30%) and out 1.2 m/s, 17% flung out at 5.4-9 m/s. Life 0.15-0.3 s, no fade.
  150/s main, 15/s per pod with `pod_scale` 0.65 on the ring, depth and size. Sizes 0.07 / 0.12 m
  (30% large), 50% white. ~35 alive on the main engine.
- Draw order now: shimmer -101, storm fog -100, crease ink + ground mist 0, snow 1, trails 2,
  halo 3, glow discs 4 (was 3), embers 5 (was 4), dot sparks 6.
- Tests: 2 new in `tests/test_cutscene_flyover.gd` (dots alive at 0 s + same after a seek + all
  near a nozzle in the ship frame; halo on the main nozzle at its size). Suite: 1261, only the 2
  known test_ichi_parked_ship failures.
