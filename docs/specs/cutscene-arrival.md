# Cutscene shot 5: Arrival

The intro's last shot, after the flyover. The ship has come out of the storm. Locked camera on a clear,
bright, cold day over an alpine range, showing the base the pilot is flying to: a megastructure of
flat chamfered decks and mushroom towers built into a mountain ridge. The ship landing is a later
pass. This pass only locks in the shot's **shape and silhouette**: mountain, building, scene,
camera.

Reference: `docs/specs/cutscene-arrival-ref.png` (the user's photo, a Star Citizen frame). Grilled
2026-10-29.

## Decisions (grill, 2026-10-29)

| # | Question | Decision |
|---|----------|----------|
| 1 | Weather | **Out of the storm**: clear and bright, like the reference. The hard cut from the dark storm does the work. |
| 2 | Framing | **Match the reference's composition**: high 3/4 view looking down about 15°. Built from that one vantage; nothing outside the frustum. The ship will be small when it lands later (accepted). |
| 3 | Length | **10 s, then a 2 s fade to black** (12 s total), and the shot ends. |
| 4 | Life | Clouds + spindrift + tower beacons (traffic was offered, then dropped in Q5). |
| 5 | Traffic | **None.** The ship is the only thing that flies. |
| 6 | Detail | **Massing / silhouette only.** Support pillars under the deck count as silhouette. Roof clutter, decals, pad markings, windows go in a later detail pass. |
| 7 | Mountains | **Procedural heightmap generated in code**: ridged noise + hand-placed shapes (saddle under the deck, front drop, peak under the far tower, right valley), snow/rock/forest by slope and height, far ranges fade into haze. Seeded, all in one generator. |
| 8 | Forest | **Spruce, the descent's look** (#1f2e2a green, snow on the tiers), scattered by a slope/height mask with a treeline; densest under and around the deck. |
| 9 | Sun | **High, back-left**, like the reference: lit tops, facing walls in the cel shadow tone. Stack = `[DepthComposite, CinemaPost]` like the other shots, key light placed from the sun. |
| 10 | Scale | **Real megastructure**: main deck about 800 m, towers 120-180 m, far ranges 20-40 km. |
| 11 | Storm edge | **The reference's own clouds as the storm's tail**: a backlit bank pouring over the top-left ridge around the far tower, low mist in the right valley. Layered cards with a shader, not volumetrics. |
| 12 | Layout | **Exactly the reference's**: main deck complex (lower slab with a chamfered left end on pillars, raised stepped tier centre-right, extension off the right edge), left tower, centre tower, back-right pair (wide deck + smaller tower), far tower on a peak. Five towers. |
| 13 | Movie | **Standalone** (F6). Not in Intro_Movie's SHOTS. Same shot contract anyway (`autoplay`, `restart()`, `finished`, `$AnimationPlayer`, `apply(t)`). |

## Build plan

- `scenes/cutscene_arrival.tscn`, root `Arrival`, `scripts/cutscene/arrival.gd` (`ArrivalShot`).
- Camera is locked. Every placement goes through it: structures come from **screen tables** read
  off the reference (percent of frame across/down, plus a distance or a plane height), turned into
  world points by casting rays through the camera, the way the descent places things from its
  sketch. Retune by editing the tables.
- `ArrivalLand` (generated, no owner): a polar heightmap grid fanned out from the camera over the
  frustum (geometric rings, 250 m to 45 km), three surfaces sharing one vertex set (snow / rock /
  forest floor). Base = ridged-noise range. Near the base, the shape is pulled to the structures:
  ridge crest just under the decks, snow hill behind the deck's left half, a slope falling away in
  front, a valley behind on the right, a peak under the far tower.
- `ArrivalBase` (generated): decks = screen polygons on their top plane, extruded down, with a
  recessed underside band and pillars/fins down to the terrain along the visible edges. Towers =
  octagonal ribbed shaft + two-step mushroom cap (flared skirt, rim slab, upper step).
- `ArrivalForest`: MultiMesh spruce on forest-floor triangles near the base; beyond that the forest
  is only the dark terrain colour.
- Sky: own shader, blue zenith to pale horizon, thin high cloud, brighter toward the sun.
- Clouds, valley mist, spindrift: camera-facing noise cards, stepped cel tones, backlit, drifting on
  the shot clock (deterministic, so seeking shows the same frame).
- Beacons: HDR blinking points on the tower caps.
- Fade: full-screen black from 10 s to 12 s; `finished` at 12 s; holds black. R restarts, Esc quits.
- Probe: `tests/_probe_arrival_shot.gd` saves the frame and a 50/50 blend with the reference, so
  silhouettes can be lined up.

## Built

Built 2026-10-29, probe-matched against the reference over six passes (`tests/_probe_arrival_shot.gd`;
`beacons` holds every beacon lit). Tests: `tests/test_cutscene_arrival.gd`.

- **Camera:** 300 m over the deck plane at the origin, pitch -13.5°, vertical fov 32°, looking -Z.
  Picked so the reference's horizon (about 8% down) and the deck's front edge (about 65% down at
  ~900 m) land where the photo has them. `ArrivalShot.on_plane / at_distance / frame_point` are the
  frame-table helpers; tables: `DECKS`, `TOWERS`, `CREST`, `HILLS` in arrival.gd, cloud `CARDS` in
  arrival_clouds.gd.
- **Base** (`ArrivalBase`): five deck slabs (Lower, Right, Mid, Tier1, Tier2) stacked so each sits
  on the one below; pillars 7 m square every 22 m along every edge, down into the land. Towers: cap
  radius 64-160 m, rim 0.24 R, step 0.1 R at 0.6 R, skirt 0.25 R, 12 ribs. Crease ink fade pushed
  to 5-9 km on the base's own crease copy (the default 45-120 m drew nothing here).
- **Land** (`ArrivalLand`): 421k-vertex polar grid, 350 m to 45 km. Ridge shelf 160 m, front drop
  650 m over 1000 m, back drop 900 m over 1300 m; ranges valley -1200 m, tops -60 m near to +350 m by
  20 km, feature 6 km, kept off the base inside 0.6-2.6 km of the crest. Three hills: the snow hill
  behind the deck, the left tower's knoll, a small peak under the far tower.
- **Departure: the land has its own shader** (`shaders/cutscene/arrival_terrain.gdshader`) instead of
  three cel_ground surfaces. Per-triangle snow/rock/forest split made staircase edges. The shader
  uses the project's cel lighting include (same half-Lambert + diffuse curve, two tones) and picks
  the fill per pixel. The forest mask is one image shared by the shader and the CPU (`mask_at`).
- **Forest** (`ArrivalForest`): about 51k spruce to 3.2 km, 9-16 m tall. **Departure: smaller than
  real spruce, and tinted blue.** The reference's tree-to-deck ratio implies tiny trees, and the
  composite's haze barely reaches 1 km, so the descent green (#1f2e2a) read as ink blots. Now
  (0.14, 0.21, 0.24) with snow on the top tier only. Trees thin out over 0.14 of the mask past the
  forest floor's edge, so there's no hard rim; past 3.2 km the bare floor fades toward rock.
- **Clouds** (`ArrivalClouds`, `arrival_cloud.gdshader`): 5 bank cards, 3 mist, 4 spindrift. A noise
  blob inside a soft ellipse, 3 cel steps lit toward the sun, soft depth fade 120 m. The bank swallows
  the far tower's lower shaft.
- **Look:** exposure 0.8, sun 0.8 from heading 35° / elevation 48°, ambient (0.36, 0.42, 0.54), glow
  threshold 1.5 (only the beacons bloom). DepthComposite haze 0.5-22 km, sky taken as 5 km, near band
  off. CinemaPost is the shared resource.
- **Beacons:** 1.6 s period, lit 0.25 s, neighbours offset 0.61 s, HDR 14, 12 m dots.
- **Load:** builds in about 3.5 s.
- **Not matched yet (detail pass):** roof clutter, decals, deck colour variety, the mid ranges' rock
  streaks, the reference's darker overall grade.

## Revision 1 (grill, 2026-10-29)

The user played the first build: "looks good but lets refine it", with a marked-up screenshot. The
deck read as a table on stilts (a fence of 7 m pillars every 22 m along every edge, 100+ m tall),
the far ranges were busy grey noise, and the top right was empty.

| # | Question | Decision |
|---|----------|----------|
| R1 | Under the deck | **Copy the reference.** The land rises to the deck's underside; the pillar fence goes. Under the fascia: a dark recessed ribbed band, the forest slope climbing up into it. Short, dense supports only under the right extension, half hidden by trees and mist. |
| R2 | Clouds | **Sea of clouds.** The top-left bank (liked) carries on as a low backlit layer right across the far background, filling the valleys behind the back-right towers; only far peaks break through. |
| R3 | Top right | **Sister outpost**: a smaller copy (2-3 mushroom towers + a short deck) on a far peak about 8-12 km out, hazed pale, base sunk in the cloud sea, one beacon. |
| R4 | Building | **Silhouette massing now**: roof blocks and terraces, a rooftop "city" on the centre tier, layered tower caps (stacked bands, a dark gap, collars), thick deck fascias with a dark band under them. No windows, decals or markings. |
| R5 | Grade | **Match the reference**: more contrast, steel-grey building separate from the snow, deep teal forest, brighter sky by the sun, haze starting further out. |

### Built (revision 1)

Built 2026-10-29 the same day, four probe passes.

- **Into the mountain:** decks carry `legs` / `sink` / `roof` in DECKS. ArrivalLand pulls the land
  up under every deck with a `sink` (Lower 14 m, Right 34 m below the band) and lets it fall at
  `foot_grade` 0.75 from the **band's line** (the outline inset by `inset`), not the deck edge, so no
  flat shelf shows under the overhang. The foot is applied after the gullies so none cuts under a
  deck. `plinth` legs: a dark wall into the land with ribs every 26 m. The right extension keeps
  `pillars` (9 m, every 15 m) with a dark plinth behind them, so it isn't a see-through fence.
- **Fascia:** lit top, a 3 m dark groove from 0.45 to 0.6 of the thickness, lit bottom.
- **Roof massing:** seeded blocks lined up with each deck's longest edge (40-120 x 24-60 m, 3-9 m
  tall, 30% with a second step), kept off the rim and out from under higher decks; a two-step crown
  on Tier2. First try used many small blocks (34 on Lower): they read as toy clutter, so fewer and
  bigger.
- **Tower caps:** upper step, rim slab, dark gap (0.9 R), lower rim slab, skirt, collar; 16 ribs;
  four boxes on each rim.
- **Sea of clouds:** a `sea` cloud kind (the bank's look, wider noise), 8 cards 4-13 km out across
  the background. One sinks the outpost's foot.
- **Outpost:** `ArrivalShot.OUTPOST` (frame 83, 16 at 7 km): a 600 x 220 m chamfered deck and three
  towers (caps 80-150 m), one beacon on the tallest, on its own peak (a hill ArrivalLand adds just
  under the deck).
- **Grade:** roofs (0.86, 0.87, 0.89), walls steel (0.42, 0.43, 0.45), underside (0.08, 0.09, 0.11);
  snow (0.82, 0.85, 0.9), rock (0.3, 0.33, 0.38), forest floor (0.09, 0.16, 0.17), spruce
  (0.08, 0.16, 0.17), forest cover 0.36; ambient (0.3, 0.34, 0.41), sun 0.85, exposure 0.85, haze
  from 2.5 km at 0.5. Gentler forest slopes (max ny 0.99) were tried and dropped: they speckled the
  far ranges.
- Tests: the deck front is now under 45 m over the land; new outpost test.
- **Still open:** the far ranges along the horizon read as busy grey; the sky's top strip has faint
  vertical streaks (the sky shader's high cloud, unchanged by this pass).

## Revision 2 (grill, 2026-10-29)

A refine pass so the shot stops reading as generated. The rule for this pass: **no detail without a
reason**. Every piece answers "why is that there?" (load, use, weather, terrain), and nothing is
scattered for texture. The composition, the locked camera and the frame tables stay.

What the first two passes left (probe frame vs reference): the deck sat on a black comb of ribs with
the forest cut off against it, the snow/forest split was one noise mask (even white camo blobs), the
roof blocks were random rectangles, the five towers were copies, the far ranges one sawtooth row of
same-height peaks, the left-back tower stood on a smooth tree cone, the clouds were speckled cutouts
with a hard line where a card met the far tower, and the sky's top strip streaked.

| # | Area | Decision |
|---|------|----------|
| R2-1 | Grounding | The rib comb goes. A **stepped foundation wall** follows the slope down (deeper where the ground falls away), with a few deep **buttresses** where load lands, dark-recessed like the reference's undercroft. Every footprint gets a **cleared snow apron** (20-40 m, no trees: the construction clearing). Each tower gets a **flared footing** half-buried in drift. The deck's **cast shadow** lands on the forest and apron, with AO darkening at the joins. The right extension's pillars stand on a visible foundation strip, not over open snow. |
| R2-2 | Snow / forest | **Terrain decides it.** Treeline by altitude (dense low, thinning, gone above it); steep faces drop the trees for rock with snow on ledges; gentle flats are open meadows; **avalanche chutes** run straight downhill from ridges and gullies; ridgelines are blown clear; man-made clearings only around the base. Forest edges break up at tree scale, not as blobs. |
| R2-3 | Roofs | Few big pieces, each with a job. **Lower = landing apron**: 2-3 flush pads with rings and edge strips, a taxi lane, a **hangar mouth** cut into the fascia at the lane's end. **Centre tier = operations**: the stepped crown plus long shallow equipment housings on the building's grid. **Right extension = utilities**: one vent run along its spine and a radiator strip. **Snow drifts** on the windward side of every raised thing, deck edges rounded over with snow. No windows, no text decals. |
| R2-4 | Towers | One family, five jobs read in the cap silhouette: **Left = comms** (lattice mast + one dish), **Centre = control** (one continuous dark glazing band round the cap, cap a little taller), **RightWide = pad tower** (flat top, landing ring, clear rim), **RightTower = heat exhaust** (short stacks + a slow **steam plume** downwind), **FarTower = sensor** (radome). Shaft height and cap width +/-10% inside the reference's silhouettes. The rim boxes go. |
| R2-5 | Mountains | **Three depth layers** (mid 5-8 km, main 12-18 km, far line 25+ km), haze separating them. **One dominant massif** back left (behind the cloud bank), the rest stepping down with real gaps and saddles. Sharp main ridges with **spurs** into valleys (warped ridged noise). The tree cone under the left-back tower becomes a **ridge spur** with a rock face on its sun side, forest only on its lower flanks. Far layers draw simpler (two tones, little mottling). |
| R2-6 | Clouds | Cel steps kept, but **2-3 big smooth tone areas**, no speckle inside, edges built from round **lobes** (cumulus, not torn paper). Lit side toward the sun, shaded belly. **Soft intersections** (300-500 m) so the far tower and peaks stand *in* the bank. The sea of clouds **pools in valleys** with a flat top; peaks rise out of it. The sky streaks are fixed; high cloud thin and sparse. |
| R2-7 | Post | Aerial perspective is the depth cue: **haze from ~800 m to 0.7**, cool blue. **Near band on** (~0.75 over the foreground forest to ~1.2 km) to frame the bright building. **Wrap 0.5**. The arrival gets **its own CinemaPost** (`resources/cinema_post_arrival.tres`) so the other shots are untouched: **edge CA way down**, grain kept, a heavier vignette, a cold steel-blue grade with teal shadows. |
| R2-8 | Access | One **snowed-over switchback road** up the front slope through the forest to a **portal** in the foundation wall (a pale zigzag scar), and one straight **power-line cut** through the forest from the base down the right valley into the mist. No vehicles, no road lights. |
| R2-9 | Surface | Variety only where use explains it: **pads and taxi lane plowed** (darker clean deck with the markings), unused roof under full snow; fascias get **structural joints** at each bay (40-60 m), lined up with the buttresses; **streaks** only below the exhaust stacks, the radiators and the deck edges (drip lines); **one muted safety-orange accent** on the pad markings and the hangar mouth's edge. |

### Built (revision 2)

Built 2026-10-29 the same day over nine probe passes; final frame `docs/specs/cutscene-arrival-r2.png`.

- **Grounding** (`ArrivalBase._foundation`): the rib comb is gone. The plinth is a dark wall in
  48 m bays, each going down to its own lowest ground, with a snow-topped steel footing ledge that
  steps with the slope and a buttress every third bay where the drop is over 22 m. Fascia joints sit
  over the bays. Pillars stand on a stepped footing strip. Tower footings are steel frustums sized
  off the centre ground, half-buried in a drift ring. (A first footing was sized off the lowest
  ground around the tower and came out as giant white cones.) The sun's cast shadow was already
  landing under the deck; a shadow on/off diff showed it, so the contact shadow is the real one.
- **Clear map** (`ArrivalLand.clear`, 1536 x 1024 over 6 x 4 km): R = cleared (aprons 20 m past
  every deck edge and tower footing, the road 8 m, the power-line cut 16 m, avalanche chutes 10-36 m
  with a fanned runout), G = wall shade (30 m from the band line, darkens the land up to 0.55).
  Shared by the terrain shader and the forest.
- **Forest by terrain** (`forest_score`, same in GDScript and the shader): treeline 140 m with a
  260 m band, slope 0.58-0.998 normal y, bare on convex ridgelines (per-vertex convexity in vertex
  colour, signed), none on cleared ground; it has to beat a 16 m break-up noise, so edges are ragged
  at tree scale. The first treeline (60 m) and a "flats are meadows" rule left a snow plain in front
  of the deck (the ridge's flat shelf), so flats now carry forest unless dead level. Snow holds in
  gullies (concave lowers the snow line 0.14), wind scours ridges; the noise jitter is 0.03 and fades
  out by 6 km.
- **Chutes**: 18, from convex spots inside the forest (below treeline - 60 m), down the fall line
  with a little wander, 260-950 m long, at least 60 m of drop; none start at or run into the base.
- **Road / power cut**: the road leaves a portal at 0.62 along the Lower deck's front band edge (the
  edge nearest the camera: `offset_polygon` reorders vertices, so the table's edge index was dropped),
  40 m straight, then 4 switchbacks of 220 m across / 70 m down. The cut runs from the right
  extension's front edge off the frame's lower right (`POWER_CUT`); the spec said "down the right
  valley", but that valley is rock behind the base, where a clearing shows nothing.
- **Ranges** (`ranges_at`): three layers (6.5 / 15 / 30 km, half-widths 1.9 / 3.8 / 7 km, crests
  -450..150 / -50..600 / 200..1100 m) of warped ridged noise, crest height wandering along each, the
  massif +700 m at frame u 14 on the main layer; foothills to -450 m between. Gullies fade out 4-14 km.
- **Spur**: the far tower's hill is a ridge running 3.6 km toward frame (-25, 13) at 4.2 km (across
  the view; pointing it at the massif made it a pyramid end-on), climbing 520 m into the bank, the
  right flank half as wide.
- **Roofs**: pads (two, rings 3.5 m orange at r 40/44 m) and the taxi lane plowed (0.5 grey); the
  hangar mouth 70 m wide on the front fascia with an orange frame. Ops housings in rows on a 46 m
  (Mid) / 36 m (Tier1) grid, 130 / 80 m long, 4.5 m tall. Utilities: a 10 m duct with vent heads
  every 26 m, radiator plates every 6 m bare of snow, five streaks on the fascia below. Drifts on
  every windward (-x) face, including the upper tiers' walls onto the deck below; a snow cornice on
  every deck edge.
- **Towers**: comms (mast 1.1 R with two yardarms and the beacon on its tip, one dish on the rim),
  control (0.16 R dark glazing band), pad (flat top, plowed disc, orange ring), exhaust (five stacks,
  soot streaks on step and rim), sensor (radome 0.3 R on a drum); `vary` 0.85-1.1 on skirt/collar.
- **Clouds**: heaps are metaballs (lobes melt into one mass, lit from the field's slope, 3 tones,
  a thin backlit rim), kept inside the card. Single-lobe sphere shading read as snowballs. The sea
  is one level quad at -470 m from 2.4 to 42 km (pools in the valleys; the mid range and the outpost
  rise out of it); the old vertical sea cards are gone. Mist and the outpost's foot are soft streak
  sheets (lobed mist read as balloons). Bank soft depth 150 m (450 made it glassy over the tower).
  The steam plume rises in lobes over the stacks, leaning downwind. The sky's streaks were the cloud
  plane seen edge-on: the high cloud is now laid out by heading and elevation in a band.
- **Post**: DepthComposite haze from 1.4 km to 0.6, cool blue (0.64, 0.74, 0.88); 0.8 km / 0.7 (the
  grilled numbers) washed the towers out. Wrap 0.5. **Near band left off**: it is distance-based,
  and the foreground forest is *farther* than the deck's front edge (the slope falls away under it),
  so it would darken the building first; the foreground forest is already the darkest mass in the
  frame. `resources/cinema_post_arrival.tres`: contrast 1.12, saturation 0.92, teal shadows, cold
  highlights, CA 0.0003, vignette 0.5 from 0.4.
- Tests: four new (forest rule, apron/road, roof and tower jobs, own post); 12 arrival tests pass.
- **Still open**: the back slope behind the base still reads a little busy at 1.5-3 km; the left
  valley mist is a flat grey sheet.
