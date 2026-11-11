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

## Revision 3 (grill, 2026-10-29)

A structure pass: more detail on the building, every piece thought out and there for a reason
(nothing random). The user also flagged the left tower: its knoll (ground at -15 m) swallowed the
shaft, so it sat entirely in the mountain. **Nothing already built is removed**; this pass only adds
and fixes the left tower's ground.

| # | Area | Decision |
|---|------|----------|
| R3-1 | Left tower | The knoll goes. The front slope keeps falling, the footing lands **120-150 m below the deck** in the forest with a small cleared apron, a long ribbed shaft rises out of the trees. The cap stays where the frame has it. |
| R3-2 | Access | One **enclosed skybridge** from the Lower deck's left chamfer into the tower shaft at deck level: a boxed truss about 12 m deep, a dark glazed strip, snow on top, the comms cable tray under it, one pier into the trees if the span is over ~150 m. No road spur. |
| R3-3 | Fascias | **Glazing where people are** (lifts revision 2's "no windows" only for this): Mid and Tier1 get a continuous recessed glazed band under a deep overhang lip, mullions every 6 m lined up with the 48 m bays; Lower only a crew-room strip on the corner by the hangar mouth; the Right extension stays blank with louvre panels at the radiators. Daytime: glass is unlit dark steel-blue. |
| R3-4 | Apron | **Two parked craft** on the pads (30-40 m, dark, snow on their backs, static - parked is not traffic), **3 maintenance sheds** along the back edge against the Mid wall with doors to the lane, a **cargo staging yard** by the hangar mouth (containers in 2-3 stacks, plowed rows), **2 elevator heads** where the deck reaches the levels below. Everything else under snow. |
| R3-5 | Centre tiers | The crown is **base command**: a level glazed band and a louvred **plant enclosure** on its roof. The Mid/Tier1 rails become **skylight strips** over the ops floors on the 46 / 36 m grid, bare of snow (heat from below). One cleared **walkway** from the elevator heads across Mid to the crown. |
| R3-6 | Right extension | A **substation** where the power cut leaves (fenced transformer yard, switch house, the line's first gantry on the deck edge); **lattice pylons** every ~250 m down the cut with three sagging wires into the mist; a **fuel farm** (4 squat tanks in a low bund wall) at the extension's apron end, a pipe rack along the duct to the apron. |
| R3-7 | Towers | Centre is **flight control**: the raked, outward-leaning glazed cab ring under its cap. 8 radial **brackets** under every cap's skirt back to the shaft (the overhang is carried). A **service ring** with a door only where a bridge or deck meets a shaft. Comms / pad / exhaust / sensor stay. |
| R3-8 | Legibility | **Ink by size**: massing (decks, towers, bridge, crown, tanks) keeps its crease ink; small parts (containers, sheds, mullions, brackets, pylons, rails) read by tone only; wires thin dark lines, no ink, fading with the haze; nothing under ~4 px at its distance. |
| R3-9 | Rule | Nothing removed. Every new part names its job in a code comment; a part that can't name one isn't built. |

### Built (revision 3)

Built 2026-10-29 the same day over four probe passes; final frame `docs/specs/cutscene-arrival-r3.png`.

- **Left tower:** the knoll row is out of `HILLS`. That alone left the ground at -84 m: the tower is on
  the ridge's 160 m flat shelf. So the crest's two left points move back (CREST v 57/58 -> 53) and the
  tower stands on the front slope, ground -118 m (ring -75..-152). The shaft and a plinth under the
  footing go down to the lowest ground round it, so the downhill side doesn't float. Its apron is the
  existing tower clearing.
- **Skybridge** (`_build_skybridge`): from the Lower outline's nearest point to the shaft. The span is
  only ~45 m, so there's no pier. 14 m wide, 12 m deep, floor one storey (15 m) under the deck top,
  glass strip, a diagonal per 10 m bay, cable tray 2 m under it. It lands on the shaft's service ring.
- **Glazing:** DECKS `glazing`. `band` (Mid, Tier1, Tier2): glass from 0.26 to 0.74 of the thickness,
  recessed 4 m, a 2.5 m overhang lip, 2.2 m mullions 8 to a 48 m bay. `corner` (Lower): up to 96 m of
  strip on the hangar's corner side. `louvres` (Right): a 52 m dark panel with slats over the
  radiators, and the streaks now run down from it. Glass (0.24, 0.32, 0.42); the first, darker
  (0.12, 0.16, 0.21) couldn't be told from the dark recesses.
- **Apron:** craft 36 m, a lofted six-sided hull, wings, fins, legs, snow on the back and wings, nose
  toward the next lane point. Sheds 44 x 26 x 12 m against Mid's front wall. Container yard: 2 x 4
  blocks of 6, stacked 2-3 (seed 2329), three tones, bare tops, plowed under. The pad lift sits by
  pad 0. The lift core stands against Mid's front wall from the Lower roof to Mid's roof + 8 m, with
  a walkway (6 m, plowed) to a door in Tier1's wall. Skylights keep clear of both.
- **Centre tiers:** the ops housings are now skylights (1.6 m, glass top, bars every 6 m, no drifts).
  The plant enclosure on the crown is a 7 m louvred box with a dark open top.
- **Plant deck:** substation yard 68 x 36 m at the cut (fence, 3 transformers, switch house), and a
  24 m gantry on the edge. Pylons every 250 m (38 m, braced lattice), wires sagging 3%. Fuel farm: on
  the duct's far side from the substation, the back side's only clear spot (Mid overhangs the rest).
  The first 60 m bund didn't fit, so it's 48 m with 9 m tanks. The pipe rack runs toward the apron
  until it meets Mid.
- **Towers:** the control skirt is 1.3x taller, glass, with 32 mullions. Brackets: 8 fins (seam tone,
  0.03 R thick). Light fins in wall tone read as windows on every tower, which hid the control cab.
  The outpost's towers skip brackets and rings (under a pixel at 7 km).
- **Ink:** `fine_*` materials have no crease pass; massing, glass and craft keep it.
- Tests: `test_arrival_structure_pass` (left tower ground, skybridge, pylons, fuel farm, ink split);
  13 arrival tests pass.
- **Still open:** the hill behind the Lower deck still pokes through its roof (kept: nothing removed
  this pass). The left tower's footing on the slope reads as a white pedestal.

## Revision 4 (grill, 2026-10-30)

From the user's marked-up frame of revision 3: the hill pokes through the Lower deck's roof, the
left tower's foot still reads badly on the slope, and so does the white S-curve under it; "fix the
mountain, make it look better"; the left cloud bank wanted on the right too; and a giant spire coming
out of the ground, centre back, running off the top of the frame. Rev 3's rule stands: **nothing
already built is removed**, only moved, reshaped or added.

| # | Area | Decision |
|---|------|----------|
| R4-1 | Hill through the deck | Keep the snow hill (`HILLS[0]`), **move it back and tighten its radius** so it rises fully behind the deck's left half. No general clamp under the decks. |
| R4-2 | Left tower foot | The white flared footing and snow apron become a **dark stepped bastion**: a retaining plinth in the foundation's dark ribbed material, stepping down the slope, its downhill face a wall. Only a thin drift line on top; the trees come right up to the wall. |
| R4-3 | The S-curve | It is the access road's switchback, bloated by snow on the flats. Make it **read as a road**: constant narrow cleared width, a dark cut bank uphill, a plowed berm line downhill, trees tight to both edges. |
| R4-4 | The mountain | **Shape over decoration**: one or two spurs running down from the base toward the camera with a gully between them; the forest tone follows the slope's light (sunlit faces a step lighter, shaded darker) so the landform reads through the trees; **exposed rock bands** where it is steepest (under the deck foundation, below the tower bastion). |
| R4-5 | Right clouds | A **sibling bank, not a mirror**: 4-5 metaball heaps across the user's outline, stepping back to front, the back one wrapping the sister outpost's peak foot (as the left bank wraps the far tower), the lowest just behind the Right deck's back edge, deeper than the left bank so it stays behind RightTower. The existing mist sheets stay as its lower edge. |
| R4-6 | Spire | An **ancient built thing that has pushed up through the ground**: dark, tapered, faceted, plainly built but older and far bigger than the base (no windows, no human-scale detail). Uneven hexagonal section, slight taper, long grooves, ledge bands holding snow; inked; the haze lifts it with height. Off the top of the frame. |
| R4-7 | Spire's foot | About **3.5 km** out, ~350 m across, in the gap between CentreTower and RightWide. The land under it is raised into a **heaved shelf above the cloud sea**: tilted slabs, cracks running out, broken snow; the sea breaks round the shelf's edges. |
| R4-8 | Spire's life | **Inert**: no light, no motion; only spindrift streaming off its ledges. The base's beacons stay the only life. |

### Built (revision 4)

Built 2026-10-30 over three probe passes; frame `docs/specs/cutscene-arrival-r4.png`. Hill moved to
1600 m / radius 240. LeftTower `bastion = 2.6` (3 octagonal tiers, 0.62-1.0 of 88 m, plowed tops,
drift lines, seam ribs). Road rounded (4 Chaikin passes), mesh `Road` (plowed surface, seam cut bank,
snow berm). SPURS (two spurs + a gully) and ROCK_BANDS (under the foundation, plus one under the
bastion); forest floor lit step at normal . sun 0.355 (the front slope is backlit, ~0.3-0.4).
Five right bank heaps. `ArrivalSpire` (scripts/cutscene/arrival_spire.gd, node Spire): hex shaft,
85 m ledge sections, grooves, 22 slabs; mesa shelf radius 240 with torn flanks, 11 cracks (clear map
B), three cloud heaps hiding the shelf's lower cliffs, spindrift off the ledges. Tests:
`test_arrival_revision_4`; **one check still fails** (the bastion's downhill clearing check) and was
not chased down tonight.

## Revision 4b (grill, 2026-10-30)

The user on the rev 4 spire: "not what I wanted": it should be **farther away**, and **no rock
mountain at its base**. This is an explicit exception to rev 3's "nothing built is removed": the
shelf, its slabs, its cracks and its cloud heaps go.

| # | Area | Decision |
|---|------|----------|
| R4b-1 | Distance | **Real size kept, pushed to ~11 km** (from 3.5 km), still at u 52 in the CentreTower / RightWide gap. About a third as wide on screen (~3.4% of the frame); still off the top. |
| R4b-2 | No rocks | The mesa shelf, the 22 slabs, the 11 cracks (clear map B) and the three shelf cloud heaps are removed. |
| R4b-3 | Foot | It stands on a **low flat snowfield** ~1.5 km across, ~30 m above the cloud sea: soft snow edges into the cloud, no cliffs, no exposed rock; the sea laps it. A thin drift where shaft meets snow. |
| R4b-4 | Detail | **Scaled to read at distance**: ledge sections ~200 m (about 6 bands in frame), grooves ~20 m. Same hexagon, taper, snow ledges, tone steps and spindrift. |
| R4b-5 | Haze | **Full haze**, like the far range. Ink fade pushed past 12 km. |

### Built (revision 4b)

Built 2026-10-30; frame `docs/specs/cutscene-arrival-r4b.png`. `SPIRE` at 11000 m, v 20.4 (the foot
lands 28 m above the sea at -470), frame-top radius 125. The snowfield is ArrivalLand's `_field`,
laid after the gullies so it stays level: flat 400 m, then a 500 m shoulder at grade 0.07 (open
snow: normal y ~0.998, under the forest rule's bar) into the cloud, then falling away under it; its
outline lobed +-25% (three sines on the angle). The first pass, a plain 750 m disc, read as a plate
and was ~2.6 km across. ArrivalSpire: sections 200 m, ledge step 0.08, grooves 20 m, a `Drift` skirt
at the foot, crease fade 14-20 km; no `Slabs`. Spindrift cards 1300 x 90 m. Removed: `_build_cracks`,
the crack channel in `_fill` / `_stroke`, the shader's `crack_dark`, `SPIRE_HEAPS`. Under the full
haze the grooves and spindrift barely read, and the shaft is near the far range's tone; it reads by
silhouette. Tests: `test_arrival_revision_4` checks the distance, the snowfield's height over the sea,
that it is open snow, no slabs, the drift, and 4-8 bands in frame; the arrival suite passes (the
bastion clearing check passes now too).

## Revision 5 (grill, 2026-10-30)

The user: the base has been **abandoned for 200 years**: nobody works or lives there, it has grown
over and is falling apart, "not completely destroyed", "a little more overgrown than destroyed".
Reference: an overgrown brutalist skyline (ivy sheets down every facade, broken tops, rebar, trees on
the roofs; the towers still stand). The parked craft, the landing pads and the blinking red beacons
go: an explicit exception to rev 3's "nothing built is removed". Everything else built is kept,
ruined in place. Composition, camera, terrain, forest, clouds and spire stay.

| # | Area | Decision |
|---|------|----------|
| R5-0 | Removed | The parked craft, the pads, rings, taxi lane and pad markings, the RightWide's landing ring, every beacon (the outpost's too) and the steam plume. Nothing is plowed any more. |
| R5-1 | Climate | **Snow stays**: the overgrowth is cold-climate. Conifer scrub and spruce on the roofs, dark moss / lichen-ivy hanging down the walls, one step greener than the spruce teal so it parts from the trees, snow sitting on top of it. |
| R5-2 | Towers | Two take silhouette damage, the rest edge wear. **RightTower** (exhaust): about a third of the cap's rim gone in one jagged stepped wedge, rebar out of the break, the stacks snapped short, no steam. **LeftTower** (comms): the mast snapped halfway, the top leaning off it, the dish torn down onto the cap. **Centre / RightWide / FarTower**: a few bites out of the rims, a fallen bracket or two, the glazing empty black holes (a few panes left in the control cab). **Outpost**: its tallest cap broken. Nothing topples. |
| R5-3 | Roofs | Trees **where 200 years of needles and grit collected**: dense along the foot of every wall, in the deck's corners and chamfers, in lines along the structural joints (cracks). Saplings up to ~15 m on the oldest patches, low dark scrub round them. About **30-40% of the Lower deck**, ~15% of the upper tiers, open snow roof between. **One collapse hole** in the Lower deck, ~40-60 m across where the second pad was: broken slab edge with rebar, dark inside, trees growing up out of the level below. |
| R5-4 | Walls | **Curtains from every overhang**: under each tower cap, every deck edge, the bastion and foundation tops, uneven tongues (short fringes to 40-80 m) in vertical strips that follow the ribs. About 40-50% of the tower shafts, 25-30% of the fascias; the left tower (nearest) carries the most. Growth also **climbs ~20 m up from the forest** onto every footing and wall. Rust and water **streaks** down the bare wall between the curtains. |
| R5-5 | Equipment | Ruined, not removed: the skybridge sags, its glass gone, the cable tray dropped at one end; sheds' roofs fallen in on two, doors gone; containers toppled and rusted, snow on them, scrub between; lift heads rusted; skylights glass-less dark slots with saplings; the plant enclosure's louvres half gone; substation overgrown, its fence half down; one fuel tank crumpled, the rest rust-streaked; pylons stand but most wires are down; the **road and the power cut are grown back** into faint scars (younger, lower trees on snow; the road keeps its cut bank); the hangar mouth's orange faded to rust, growth over its lip; formerly heated surfaces (radiators, skylights) carry snow. |
| R5-6 | Atmosphere | Same clear day and sun. The concrete **warms to a weathered grey**, the haze starts a little closer. **8-12 birds** circle out of the left tower's broken cap and drift across the deck, the only life. Spindrift also off the broken tower edges. The spire stays inert. |
| R5-7 | Edges | Light: **3-5 spalled bites per deck** (5-15 m) with dark ribs exposed, a couple of **dropped fascia panels** (dark gaps on the seam line), a **rubble talus** under the bigger bites (snowed over, saplings in it), one **sagging slab** on the right extension. The foundation is cracked but whole. |

### Built (revision 5)

Built 2026-10-30 over four probe passes; frame `docs/specs/cutscene-arrival-r5.png`.
- **Removed:** `PADS`, `LANE`, `CRAFT_LENGTH`, the craft, the plowed / accent materials, every
  beacon (`arrival_beacon.gdshader` deleted), the plume card. What the apron needed survives as
  `ArrivalShot.HANGAR`, `LIFT_SITE` and `HOLE`. The Lower deck's roof is `apron`.
- **Decks (ArrivalBase):** `BITE_COUNT` bites per deck (Lower 5, Right 4, tiers 3) on edges facing
  the camera, 6-16 m wide, 5-12 m deep, the roof and upper fascia cut away (`_bitten`, broken faces
  in seam via `_walls_split`), a dark floor at the groove, rebar; the Right deck's first bite is the
  sagging slab (dropped 3.5 m, still snowed). Rubble talus under bites over 11 m. `DROPPED_PANELS`
  (Lower 2, Right 1, Mid 1). Glazed bands are black, a third of the mullions gone. The hole: 15-point
  ragged ring at radius 25 (0.72-1.12), a lighter 3 m slab edge over a dark 20 m shaft, rebar, one
  slab hanging in; the roof is capped round it in two halves (`_cap_holed`).
- **Towers:** `wear` in TOWERS. `_cap_cuts` / `_layer_cuts` cut each cap layer (step, rim, gap,
  lower rim) with the same jagged line at stepped depths. RightTower `broken`: wedge at 0.3 rad,
  2.1 rad wide, inner 0.28 / 0.42 / 0.5 / 0.56 of the cap (rim ~third gone); the first pass faced
  the camera and barely changed the silhouette, so it sits on the cap's right now. Stacks inside it
  gone, the rest snapped short. LeftTower `snapped`: mast broken at half height, the top leaning off
  it with a yardarm, the dish lying on the rim. Others `bitten`: 2-3 bites 0.84-0.9 deep, one bracket
  fallen. Control cab: glass on 2 of 8 faces. Outpost: tallest cap broken.
- **Equipment:** sheds 2 and 3 roofless (inner walls, dark floor, trees); containers 1-2 high, rust /
  steel, a quarter of the tops lying askew; skylights dark slots, two bars in three gone; plant
  louvres half down; substation fence half down, transformers rust; one fuel tank crumpled, rust on
  the rest; pipe rack span 4 fallen; only power spans 1 and 4 strung, others one wire hanging to the
  ground; skybridge sags 3 m, one glass pane a side, tray torn at 72% and hanging 26 m; road surface
  snow, no berm; bastion tops snow. Walls `C_WALL` (0.45, 0.43, 0.4), rust `C_RUST`.
- **Growth (`ArrivalGrowth`, scripts/cutscene/arrival_growth.gd, node Growth after Forest):** roof
  samples every 5 m scored by shelter (wall feet 32 m, corners 60 m, edge, joint lines every bay 80 m
  in, round roof blocks, hole rim) + noise; the best 35% (low decks) / 15% (tiers) grow: three dark
  scrub mounds each (`_mound`, no snow: the snow-tipped spruce squashed into scrub read white) and
  one or two spruce 3-15 m by age. Tree slots (hole 16 trees 16-27 m, sheds, skylights, yards), rubble
  saplings, scrub on the caps. Curtains on `ArrivalBase.walls`: strips 4-9 m in Markov runs (stay
  0.75), 45% fringes 3-12 m / 55% tongues 14-80 m, snow along the top; climbing 70% up to ~20 m.
  Moss (0.2, 0.31, 0.19): the first, darker green read as grey streaks. The strips' ragged edges fill
  about two thirds, so the listed covers are over the spec's (shafts 0.6, left 0.75, fascias 0.38).
  Streaks rust / water on 35% of bare stretches. Road: young trees 4-9 m across its cleared width
  every 2.5 m (75%); the power cut 4 a row every 6 m (80%).
- **Atmosphere:** birds in ArrivalShot (`bird_*` exports, `bird_at`): 10 dark billboard Vs wheeling
  on a 40 m circle that drifts from 30 m over the left cap to over the Lower deck through the hold;
  haze_start 1100 m (from 1400). Spindrift card off the broken cap (`break_spots`).
- Tests: `test_arrival_abandoned`, `test_arrival_overgrown`, `test_arrival_birds` (the beacon and
  roof-jobs tests went). The arrival suite passes. Load time unchanged (~8.5 s, the land dominates).

## Revision 5b (2026-10-30)

The user on rev 5: "I want moss and shrubbery on the building, but trees would not grow on the
building." **No tree stands on the structure**: roof patches, the collapse hole, the roofless sheds,
skylights, yards, tower caps and talus that fell onto a lower deck grow only scrub; the moss
curtains, climbing growth and streaks are unchanged. Trees stay where they stand on the land: talus
on the ground, the grown-back road and power cut.

Built 2026-10-30; frame `docs/specs/cutscene-arrival-r5b.png`. ArrivalGrowth: roof samples grow 3
scrub mounds (4 past age 0.45), 2-6 m tall by age (`scrub_height`; `tree_height` gone); `tree_slots`
grow scrub capped at 6 m; ground talus saplings sit on the land at their own spot (they had been
lifted to the pile's centre height on slopes). Counters `roof_clumps` / `slot_clumps`.
`test_arrival_overgrown` checks every tree stands within 2 m of the land.

## Revision 6 (grill, 2026-11-02)

Cleanup only, from the user's frame: "some of the moss hanging isn't lined up, remove the birds,
fine tune this scene, don't add anything, just clean up what we have." Grilled 7:

| # | Area | Decision |
|---|------|----------|
| R6-1 | Moss | Hanging growth only starts at a real ledge and lies on what it hangs on. Shafts: strips only in the bays between the 16 ribs (they stand ~0.13 sr proud and cut the strips into slivers). Cap rims: the fringe stops at the lower rim's foot (below it the skirt pulls in and strips hung in the air). Skybridge: follows its sag. Deck fascias unchanged. |
| R6-2 | Cloud opacity | Both banks ~50%, each fading as one sheet (no heap's edge showing through the one in front). |
| R6-3 | Left bank | Down level with the right bank (top ~13% down the frame): the left range shows, the far tower's cap clear with cloud round its shaft, the low heap at the deck line behind the near tower. The right bank stays put. |
| R6-4 | Scrub | No halos (shadows off), a step greener but darker than the moss, dense patches thinned ~a third. |
| R6-5 | Far snow | Same snow/dark balance, but big calm shapes instead of flecks; the near slopes unchanged. |
| R6-6 | Fog smears | Left-valley mist card removed (the lowered bank covers it); the other mist sheets get a hard cel edge, still translucent; the bank's soft fade against the far tower sharpened. |
| R6-7 | Birds | Gone (code, exports, tests). |

### Built (revision 6)

Built 2026-11-02; frame `docs/specs/cutscene-arrival-r6.png`.

- **Moss:** `_tower_growth` splits each shaft face at the ribs crossing it (rib half width + 0.6 m
  clear, bays under 3 m dropped) and tags walls `kind` (`shaft` / `rim`) + `tower`; rim faces end at
  `y_low` (were `y_low - 0.1 r`). Skybridge faces hang from the roof edge (`y1 + 0.8`, was
  `y1 - sag`) down to 15 m under the floor (was 30) with a `sag` key; ArrivalGrowth drops each
  strip's top by `sag * sin(pi f)`. The shafts carry visibly less moss now (the bays are narrow).
- **Clouds:** banks use `shaders/cutscene/arrival_cloud_bank.gdshader` (`depth_draw_always`, drops
  pixels under half alpha); both cloud shaders include `arrival_cloud.gdshaderinc`. ArrivalClouds
  mirrors each bank card's `sorting_offset` inside the banks' distance range so they draw nearest
  first, so only the front heap survives per pixel. Bank opacity 0.5, soft depth 60 m (was 150).
  Left bank cards +12 v. Mist softness 0.04 (was 0.25), the [4, 52] mist card gone.
- **Scrub:** C_SCRUB (0.13, 0.22, 0.15) (was (0.1, 0.17, 0.13)); 3 / 2 mounds a roof sample (was
  4 / 3); the Scrub MultiMesh casts no shadow. The halos were mostly the environment glow blooming
  the roof snow over the dark clumps: `glow_hdr_threshold` 4.0 (was 1.5), which crisps every
  bright/dark edge in the frame.
- **Far snow:** the flecks behind the deck were forest-floor holes, not the snow line (debug-coloured
  to find them). ArrivalLand now stores a broad normal per vertex (`broad`, measured `broad_reach`
  100 m out; packed in COLOR.gb for the shader). Past `broad_fade` (1800-2400 m, beyond the base, so
  the near slopes are untouched) the snow line and the forest read it, the gully/ridge snow terms
  fade out, and the snow jitter fades over 1500-2400 m (was 2000-6000). Out to `flat_forest_fade`
  (3500-5000 m) flats keep their forest (`flat_k`), else the bowl behind the deck went white; past
  it the far valleys' flats are open snow again. ArrivalForest reads the same (`far_ny`, `flat_k`).
- **Not changed, now visible:** the lowered bank uncovers the avalanche chutes on the left slopes
  (the thin white diagonals by the near tower's mast and at the left edge). Existing terrain, kept.
- Tests: `test_arrival_moss_lines_up` (shaft bays clear of every rib, rim fringes no deeper than
  the rim stack, skybridge sag); `test_arrival_birds` replaced by `test_arrival_no_birds`. Arrival
  suite passes; the full suite's only failures are the 2 old test_ichi_parked_ship ones.
