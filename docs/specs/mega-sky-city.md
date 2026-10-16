# Mega sky city

2026-10-16. Grilled with the user from two images: their outline over the intro planet and a hazy
reference shot of giant platforms in the sky with pillars hanging under them. A floating city,
raised thousands of feet above the frozen ground, shows up in two cutscene shots:

- **Shot 1 (intro space):** a grey cluster of rectangular platforms over a large part of the USA, seen
  from orbit (revision 2; it was a hex-tiled slab).
- **Shot 3 (descent):** the same city far off on the horizon, as a flat 2D silhouette in the haze.

The city is dead: no lights and no motion.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Planet: border | **The user's outline traced as a lat / lon polygon** (`CITY_OUTLINE` in `shaders/space/planet_city.gdshaderinc`), **snapped to whole hexes**. A hex is city when its centre is inside the polygon, so the edge is stair-stepped |
| 2 | Planet: tile size | **About 1.5 deg flat-to-flat** (about 150 km), roughly 18 x 10 tiles across the outline. **Thin dark seams** between hexes and a **slight per-tile grey variation** (3 shades) |
| 3 | Planet: alive or dead | **Dead, plain grey.** It takes the same cel light bands, painted patches and cloud shadows as the land. No glow |
| 4 | Planet: height | **The lift is cheated** with the relief light (the one the cloud shadows use): a **darker lip** inside the edges that face away from the light, and a **cast shadow** on the snow beyond them. Mountains and snow under the city are covered |
| 5 | Planet: layering | Inside the planet surface shader: **over the snow, under the cloud shell**, so clouds and their shadows still pass over it |
| 6 | Descent: placement | **The user's band**: from the left edge to about 62% across the frame, just above the far mountain tops (sketch px x 0-1190, y 353-427). **Behind the storm wall and the snow curtain**, so the left end is half-buried and it shows clearer to the right |
| 7 | Descent: pillars | **Platform undersides inside the band. Pillars, tanks and struts hang below it**, fading into the haze and running down behind the far ridge |
| 8 | Descent: look | **A 2D card of 3 flat silhouette layers in this shot's fog tones**: the front layer is a muted slate, the back layers fade toward the sky colour. Underside detail: stepped blocks, girders, hanging tanks, struts, long thin rails across the sky, like the reference |
| 9 | Descent: lightning | **None.** Flashes and bolts do not light it (unshaded, fog-free card). Bolts draw in front of it |
| 10 | Descent: motion | **Static** |

## Planet layout (shot 1)

The outline was traced in the shot's t = 0 frame, then unprojected through the shot camera onto
the sphere. The storm eye checked out within 0.6 deg. It runs from Nebraska / Kansas east to
Virginia, south to East Texas and west to West Texas / New Mexico:

| lat | lon | | lat | lon |
|-----|-----|-|-----|-----|
| 41.0 | -100.0 | | 32.7 | -95.7 |
| 39.3 | -99.5 | | 31.7 | -100.6 |
| 39.1 | -94.7 | | 30.6 | -104.7 |
| 41.4 | -91.7 | | 30.9 | -106.4 |
| 40.6 | -84.8 | | 33.4 | -106.8 |
| 38.3 | -79.9 | | 34.9 | -105.4 |
| 36.6 | -80.2 | | 36.3 | -102.4 |
| 36.8 | -83.8 | | 38.4 | -105.9 |
| 34.5 | -88.9 | | 39.8 | -103.2 |

The layout lives in degrees, with longitude squeezed by cos(35.5 deg) so platforms are square at the
city's middle latitude. Tunables are uniforms in the `City` group of `planet_snow.gdshader`.

## Revision 2: platforms instead of hexes (shot 1)

2026-10-16, grilled from the descent shot: the hexes did not match the descent card's separate flat slabs.
Rows 1 and 2 above are replaced by these; rows 3-5 still hold (dead grey, lip + cast shadow off the relief
light, over the snow and under the clouds).

| # | Topic | Decision |
|---|-------|----------|
| R1 | Shape | **A cluster of separate rectangular platforms**, snow showing between them, all inside the traced outline (its edge is now ragged and blocky, not stair-stepped hexes) |
| R2 | Scale | **4-6 large anchors (300-500 km long) + 25-40 smaller platforms (60-200 km)**, covering about half the outline |
| R3 | Axis | **One shared east-west axis**; about 1 in 5 small platforms is turned 90 deg (long north-south). No free rotation |
| R4 | Rails | **8-12 thin straight rails** on the axis or across it: short ones over the gap between two facing platforms, 2-3 long ones through most of the city. A little darker than the platforms, no shadow |
| R5 | Stacking | **Two levels**: some anchors carry a smaller raised block, lighter than the platform, with its own lip and a short shadow onto the platform |
| R6 | Surface | **Plain flat grey**, one of 3 tones per platform, no seams or panel lines |
| R7 | Layout | **Generated from a seed** by `tools/gen_planet_city.py`, baked as constant arrays (`CITY_PLATFORMS`, `CITY_TOPS`, `CITY_RAILS`) between the GENERATED markers in the include. Tweaks: edit the tool's numbers / seed and re-run |

Built 2026-10-16: seed 7 gives 39 platforms (5 anchors), 2 raised blocks, 11 rails (3 long), 49% cover.
Probe-checked at 0 and 12 s. Tuned from the first probe: small platforms chunkier (1.0-2.4 deg long) with wider
gaps (0.3-0.75 deg), because at the old lip width the slivers were mostly lip; lip 0.006 -> 0.004, ground
shadow 0.011 -> 0.008, rails lightened (they read as black ink). The hex tunables (`city_hex_deg`, `city_seam`,
`city_seam_color`) are gone; new ones: `city_top_lift`, `city_top_shadow_offset`, `city_rail_color`,
`city_rail_deg`.

## Revision 3: city texture (shot 1)

2026-10-16. The user liked the revision 2 layout but the flat grey did not say "giant city". Asked how to
get that, chose **rooftop blocks + a few towers with long shadows**, and said keep them **tiny, the camera is
in orbit**. Lights stay out (the city is dead). Replaces R6 (plain flat grey).

| # | Topic | Decision |
|---|-------|----------|
| T1 | Rooftop blocks | A fine block grid on the shared axis over every platform and raised block, **a few pixels per block from orbit** (0.1 deg pitch). Lighter streets, a wider boulevard every 7th street, 4 block tones, empty lots thinning toward platform edges, darker cores |
| T2 | Districts | Each square between boulevards gets a tone shift and a block size (1x, 2x or 3x), so the grid doesn't read as graph paper |
| T3 | Towers | **10 tiny towers** (about 3 px), the brightest thing on the city, each casting a **long thin shadow** away from the light, over platforms and onto the snow. The scale cue |

Towers come from `tools/gen_planet_city.py` (`CITY_TOWERS`) on their own random stream, so the revision 2 layout
did not move. Built 2026-10-16, probe-checked at 0 / 12 s. The first tower shadows (0.016 long, 1x wide) were
invisible; now 0.03 long and 1.6x wide. Tunables: `city_blocks_on`, `city_block_deg`, `city_street`,
`city_street_lift`, `city_boulevard_every`, `city_block_shade`, `city_empty_edge`, `city_core_dark`,
`city_district_shade`, `city_tower_color`, `city_tower_shadow`, `city_tower_shadow_width`.

## Revision 4: a real city layout (shot 1)

2026-10-16. The user liked the block size, but "EVERYTHING is a grid": they wanted deviation, small flat
areas, roundabouts, a real city layout. The block pitch (0.1 deg) and towers are unchanged.

| # | Topic | Decision |
|---|-------|----------|
| L1 | Merged blocks | Inside a district, 25% of street lines drop out, so neighbouring blocks merge into longer, uneven ones |
| L2 | Diagonal avenues | Half the platforms get one road-tone avenue 25-55 deg off the axis, near the middle |
| L3 | Roundabouts | 20% of boulevard crossings are a ring road (1.5 blocks out) around a darker island |
| L4 | Plazas | 30% of districts hold a flat lighter 2-3 block plaza, half with a small monument block in the middle |
| L5 | Open districts | 6% of districts are left flat and open |
| L6 | District sizes | 70% 1x blocks, 25% 2x, 5% 3x (was 55 / 30 / 15) so the fine grain the user liked dominates |

Probe: first pass (40% merge, 35% roundabouts, light islands) made the blocks coarser and the roundabouts
read as solid discs in a repeating row; pulled back to the numbers above. Tunables: `city_merge`,
`city_diagonal_share`, `city_roundabout_share`, `city_roundabout_blocks`, `city_plaza_share`,
`city_open_share`, `city_plaza_lift`.

## Descent layout (shot 3)

`DescentSkyCity` (`scripts/cutscene/descent_sky_city.gd`, node `SkyCity`) generates the card at
load from a seed, in sketch pixels like the rest of the shot. Every rect becomes a quad pushed out
through `DescentShot.sketch_point`. The three layers sit 20-22 km out, beyond both mountain ranges
(so the ridges hide the pillar feet) and inside the camera's 30 km far plane. The material is
unshaded and fog-free, so the tones are exactly the ones set on the node. Pillars blend toward the
sky colour as they go down, which is the haze.

## Built

2026-10-16. Built both shots and checked them against probe screenshots
(`tests/_probe_intro_space_shot.gd`, `tests/_probe_descent_shot.gd`).

## Revised: farther and less boxy

2026-10-16, grilled from a probe screenshot: the descent card read too close and too noticeable,
and the shapes were "JUST boxes".

| # | Topic | Decision |
|---|-------|----------|
| 1 | Distance | **Haze plus a modest shrink.** Every layer sits paler than the far ridge (front 0.70, back 0.79 against a sky of about 0.84). Slab widths, slab thickness and leg widths go to **60%**, and gaps shrink to match. The band and placement are unchanged |
| 2 | Diagonals | **Hulls + bracing + a little A-frame**. No roofline pieces or spires |
| 3 | Hull | **Faceted, 2 tiers with a random lean**: angle in, a flat ledge, angle in again, one side steeper than the other per platform. Replaces the stepped blocks |
| 4 | Sky rails | **Kept, front two layers only**, hazed 65% toward the sky and shortened to run between platforms (260-520 px) |
| 5 | Height | **Tops stay on the same line**, so legs are longer and thinner. **One fewer leg per platform** (1-2), placed on the outer parts where the hull has tapered away. The haze ends at y 490 (was 540) |
| 6 | Details | **Chamfered octagon tanks**, max 1 per platform. **About 1 in 4 platforms stands on an A-frame pair** leaning in 8-12 deg. Knee braces on most legs, and **an X-truss between the pair on about 1 in 3 platforms** |
| 7 | Colour (later the same day) | **The whole city is one flat colour**, the old back layer's (0.79, 0.785, 0.85), circled by the user. That covers every layer, the legs (no haze fade) and the rails. `city_color` on the node; `haze` and `rail_haze` are kept but set to 0 |
| 8 | Size (later the same day) | **The whole card at 70%** (`city_scale`), shrunk toward mid band on the tops' line (sketch 535, 353). Legs still end at DRAPE_END_Y behind the ridges. Now ends about 52% across |

## Revision 5: unfinished outposts (shot 1)

2026-10-16, grilled from an editor screenshot of the planet. The user loves the mega city: it stays exactly as
it is (seed 7, same outline) as **the main central city**. Around the rest of the USA go **smaller cities that
were started and never finished**. Planet only.

| # | Topic | Decision |
|---|-------|----------|
| O1 | Unfinished look | **Each outpost fades built core -> bare deck -> open frame**, like construction that stopped partway across |
| O2 | Count and size | **Tiered: 4 almost-towns** (3-5 platforms, the biggest about 2.5 deg) **+ about 12 lone slabs** (0.6-1.5 deg) |
| O3 | Placement | **On real cities.** Almost-towns: **Seattle, Los Angeles, New York, Minneapolis**. Lone slabs jittered 0.5-1.2 deg off Portland, San Francisco, San Diego, Phoenix, Salt Lake City, Boise, Detroit, Boston, Houston (+ backups Las Vegas, Spokane, Billings). **2 deg clear gap** around the mega city's outline and **nothing within 9 deg of the storm eye**, so Chicago, Denver, Albuquerque, El Paso, Atlanta and New Orleans drop out |
| O4 | Rails | **Short internal rails inside the almost-towns, plus a stub rail** (1-3 deg) from each almost-town and about 1 in 3 lone slabs, **aimed at the mega city and stopping in mid-air** |
| O5 | Descent shot | **Untouched** |
| O6 | Built core | **The mega city's rooftop blocks** (`city_roof`), **plus one tower per almost-town**. Lone slabs get no tower |
| O7 | Frame | **A girder grid every ~0.4 deg** (4 blocks), girders thinner than a rail, platform outline kept. Snow shows in the cells; the girders cast thin shadow lines onto the snow |
| O8 | Fade | About **35% built / 25% bare / 40% frame** per platform (+-15%). **Almost-towns are dense in the middle and skeletal at the edges**: the central platform fades radially, the outer ones fade away from the town centre and are mostly frame. Lone slabs fade along a random axis direction, **about 1 in 3 is frame-only** |
| O9 | Abandoned | **Patchy snow drifts on the bare deck and frame**, more toward the frame end. Built cores and the mega city stay clean |

Layout: `tools/gen_planet_city.py` runs an outpost pass on its own random stream (seed + 200), so the mega city
is byte-identical, and bakes `OUTPOST_PLATFORMS` (rects), `OUTPOST_FADE` (fade direction, built end, bare end;
direction (0, 0) = radial), `OUTPOST_TOWERS` and `OUTPOST_RAILS`. The built / bare boundary is stepped on the
block grid with a little jitter so it reads as ragged construction, not a ruler line. Toggle `outposts_on`.

Built 2026-10-16: 4 towns (Seattle 5, LA 3, New York 5, Minneapolis 4) + 12 lone slabs = 29 platforms, 4
towers, 22 rails. Atlanta / New Orleans dropped for the storm, Albuquerque / El Paso for the gap; Las Vegas,
Spokane and Billings filled in. Probe at 0 / 9 s. First pass: the towns read as tangled scaffolding with thick
black bars, because the radial built core was only ~16% of the central platform and the deck took a lip
wherever it met the frame. Now cores are built to 0.55-0.68 radially (bare to 0.8-0.9), outer town platforms
built 0.1-0.3, 1 in 5 frame-only, and the lip is on the platform's outer edge only. Seattle sits at the top-left
frame edge at t = 0; New York is foreshortened near the limb.

### Mexico (later the same day)

The user loved the result ("looks fantastic") and asked for **the same thing over Mexico**. Same rules, scaled to
its size: **2 almost-towns, Mexico City and Guadalajara, + 6 lone slabs** (Monterrey, Chihuahua, Hermosillo,
La Paz, Torreon, Oaxaca; Veracruz dropped for the storm, Culiacan / San Luis Potosi / Acapulco are backups).
`REGIONS` in the tool runs Mexico after the USA on the same stream, so the USA layout did not move. Now 43
platforms, 6 towers, 32 rails. Both towns sit near the bottom of the t = 0 frame, clear of the title card.

## Descent card lowered (2026-10-16)

User: the city in the back sits "way too high for being that far away". The whole card now sits
**40 sketch px lower** (`city_drop` on `DescentSkyCity`, applied after `city_scale`). Its hulls now
sit just above the far ridge and the mist band, and the legs still end at `DRAPE_END_Y` behind the
ridges. The test's band-top check allows for the drop.

## Revision 6: Canada (2026-10-16)

Grilled from a pan frame of the planet: "continue the sky mega city throughout all the open space in Canada".
Same unfinished-outpost idea as revision 5, denser, spread north into the empty space the opening pan shows.
Planet only.

| # | Topic | Decision |
|---|-------|----------|
| C1 | Kind | **Unfinished outposts, denser than the USA.** The mega city stays the only finished city |
| C2 | Placement | **5 almost-towns: Calgary, Winnipeg, Montreal, Yellowknife, Churchill** (Toronto skipped, too close to New York / Detroit). **18 lone slabs** off Whitehorse, Inuvik, Fort McMurray, Saskatoon, Regina, Thunder Bay, Quebec City, Halifax, Goose Bay, Iqaluit, Rankin Inlet, Cambridge Bay, Baker Lake, Kuujjuaq, Prince George, Fort Nelson, Moosonee, Gander (backups Dawson City, Resolute, Chibougamau). **2 deg clear of every USA / Mexico outpost** (`CA_GAP`). Hudson Bay and the Arctic channels are snow, so slabs can sit on them |
| C3 | Rails | **Stubs aim at the mega city** as before, **plus near-miss pairs**: two towns each run a rail at the other on one axis line, stopping 1-1.5 deg apart. A pair stub replaces a town's home stub when both point the same way |
| C4 | Size | **Grows with latitude**: x1 to 55 N, x1.5 by 70 N (`CA_GROW`), so the limb squash doesn't eat the far north. **No frame-only lone slabs above 60 N** |
| C5 | Twist | **Less finished farther north**: built share x1 at 52 N down to x0.3 at 62 N, bare end down to x0.65, outer town platforms up to +50% frame-only (`CA_NORTH*`) |
| C6 | Rest | Revision 5 rules: fades, one tower per town, internal rails, snow drifts. Canada runs last in `REGIONS`, so the mega city, USA and Mexico arrays are unchanged (checked by diff: only appended rows) |

Built 2026-10-16: all 5 towns (Calgary 5, Winnipeg 5, Montreal 5, Yellowknife 3, Churchill 3) and all 18 lone slabs
placed with no backups needed; pairs Calgary-Yellowknife and Winnipeg-Churchill (Yellowknife-Churchill dropped: their
platforms share no axis line). Totals 82 outpost platforms, 11 towers, 61 rails. Probe at -5 / -3 s (the pan, which
is where Canada shows; at 0 s it is above the frame): the north reads as a thin build-out of girder frames, the
southern towns as built as the USA ones, the two pairs as long north-south rails with a gap.
