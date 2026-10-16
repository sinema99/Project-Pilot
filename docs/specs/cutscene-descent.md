# Cutscene shot 3: descent

2026-10-14. Grilled with the user from their line sketch, then built the same day. The third shot
of the opening cutscene: a wide, locked-off long shot of the snowy surface under the storm. The
ship is never shown. A blue trail drops out of the cloud deck top right and arcs down and left
to the middle of the frame, as if the ship had just punched through the storm. It leads into
Ichi, so the weather is Ichi's blizzard.

**This is a blockout.** The mountains, ruins and cloud deck are generated shapes aimed at this one
camera. Their backs are never seen.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | The end of the line | The ship keeps flying its arc. The head of the trail reaches the sketch's **Finish** at 5.0 s and the shot cuts there. The arc drifts slightly away from the camera, so it flattens toward the horizon the way the sketch does |
| 2 | Trail life | **It stays.** At 5 s the whole line from Start to Finish is visible. The oldest end (near the clouds) has spread, paled and started breaking up, but it is still there |
| 3 | Trail look | **Shot 1's ribbon**, shown as one ribbon since the three engines blend together at this distance. White-hot core, cyan, dark blue edge (no re-entry orange), plus a small glowing white star at the head where the ship would be |
| 4 | Camera | **Locked off.** Not moving for 5 s, no shake |
| 5 | Weather | **Ichi's `Storm` node**, with the same flakes, wind, gusts, drift and fog colours. Only the fog distance is pushed out, so the landscape fades by depth instead of whiting out. Gust whiteouts still pass, just thinner |
| 6 | Clouds | **Dark cel cloud deck** seen from below. 3 hard tones with a lumpy underside, and its front edge is the sketch's lumpy cloud line. Cyan lightning flickers inside it, and the first and biggest flash lights the spot where the trail breaks out. Flashes briefly light the whole landscape |
| 7 | Ruins | **One dead city, abandoned 100+ years** (cleanup, below). Replaces the sketch's 6 evenly spaced clusters |
| 8 | Bottom corners | **Close mountains as Hollow Knight-style silhouettes**, the sketch's size and placement with craggy edges, hung on the camera (cleanup, below) |
| 9 | Silhouette look | Flat near-black with a cool tint (`#0a0d12`). No shading, no ink, no snow, untouched by fog. Blizzard flakes blow across in front of them |
| 10 | Mountains | **Two generated cel ranges**, snow with rock on the steep faces. The near range follows the sketch's ridge line and reads pale grey in the fog; a taller far range behind it is a ghost |
| 11 | Light | **Ichi's** dim, cold overcast: sun 0.18 and Ichi's colours. The trail and the lightning are the brightest things in the frame |
| 12 | Pacing | 0-0.6 s establishing beat (landscape, blizzard, cloud deck). At 0.6 s the big flash and the trail punches out of the deck, fast and steep, then eases level into Finish at 5.0 s |

Not in it: sound (the project has none), the ship mesh, camera shake.

## Layout

Everything is placed **from the sketch**. The sketch is 1906 x 847 px. A sketch pixel maps to the
same fraction of a 16:9 frame (`ASPECT`), and a ray through it is pushed out to a chosen distance.
So the composition follows the drawing at any distance, and moving one sketch point moves that
piece of the world.

- **Camera:** (0, 1.7, 0) looking down -Z, vertical fov 40 deg, pitched up so the horizon sits
  at the sketch's horizon (64% down the frame, about 6 deg of pitch).
- **Cloud deck:** base at 500 m. Its front edge is the sketch's cloud line, put on the deck's
  base plane, about 1.2-1.5 km ahead. The deck fans back from the edge toward the camera over
  the top of the frame. Underside billows hang down a few tens of metres.
- **Trail path:** one fitted Bezier along the sketch's blue line (was Catmull-Rom; see Cleanup). It starts inside the deck (above
  the base, behind the edge) and breaks out at the edge, about 1.35 km away at 500 m. It then
  drifts away to about 1.8 km while it drops to about 250 m. A real dive pulling level, carried
  on leftward.
- **Head timing:** progress along the arc is `u + k(u - u^2)` on `u = (t - t0) / (5 - t0)`, with
  `k = 0.6`. That is 1.6x the average speed at the start and 0.4x at the cut, so it is still
  flying when the shot ends. `t0` is solved so the head is exactly at the breach at 0.6 s.
- **Ruins:** one city 2.5-6 km out (was 6 clusters; see Cleanup).
- **Mountains:** the near range at about 7.5 km, its ridge heights read off the sketch's ridge
  line. The far range is at about 12.5 km, taller, peeking over the near range's low points.
- **Snow field:** one flat plane at y = 0, 40 km across, with a StaticBody3D so the Storm's roof
  bake gives the drift a ground.
- **Silhouettes:** (now hung on the camera 3 m out; see Cleanup) two flat polygons from the sketch's bottom-corner lines, about 25 m from the
  lens, extended past the frame edges so no wider window shows their ends.
- **Fog:** `visibility` 14 km, `gust_visibility` 9 km. That gives ruins about 30% fogged, the
  near range about 75% (pale grey), and the far range about 95% (a ghost).

## Build plan

- `scenes/cutscene_descent.tscn`, root `Descent`: WorldEnvironment (Ichi's sky, ambient and
  filmic tonemap, plus shot 1's glow so only the trail core and the head star bloom) / Sun
  (Ichi's) / FlashLight (cyan, downward, energy driven by the lightning) / Camera3D / Storm /
  Land (generated) / CloudDeck / Trail (IntroSpaceTrail) / HeadStar (glint_star billboard) /
  AnimationPlayer with an empty 5 s `shot`.
- `scripts/cutscene/descent.gd` (`DescentShot`): plays on load, holds the last frame, emits
  `finished`, R restarts, Esc quits. It owns the sketch tables and the `sketch_*` helpers.
  Every effect is a function of the shot time (the head, trail, flashes and flash light), so
  seeking shows the same frame.
- `scripts/cutscene/descent_land.gd` (`DescentLand`): builds the snow field, ruins, two
  mountain ranges, silhouettes and cloud deck mesh from the shot's sketch helpers at load.
  Children have no owner, so nothing is saved into the .tscn.
- `shaders/cutscene/cloud_deck.gdshader`: unshaded, billow displacement, 3 hard tones,
  and lightning as up to 8 `(x, z, radius, brightness)` flashes in stepped cyan rings.
- Reuses shot 1's `IntroSpaceTrail` (one nozzle at the head), `engine_trail.gdshader`,
  `glint_star.gdshader` and the `IntroSpaceLightning.Flash` pulse shape. Reuses Ichi's `Storm`.
- Tests: `tests/test_cutscene_descent.gd`. Probe: `tests/_probe_descent_shot.gd` (windowed screenshots).

## Built

2026-10-14. Built as above, with these departures found from probe screenshots:

- **The trail draws from the breach on**, not from inside the deck. The wide ribbon poked a cyan
  chip through the billows above the edge. The head still flies from inside the deck, so the speed
  profile and timing are unchanged.
- **The big flash starts at 0.52 s**, peaking just before the punch at 0.6 s, so the flash leads the
  eye to the spot.
- Snow field colour `(0.95, 0.94, 0.96)`. The first pick, a bluer white, read as a frozen lake
  under Ichi's blue ambient.
- `flash_light_energy` 0.22. At 0.6 a flash turned the whole field cyan-white.
- Mountain noise is gentler (larger features, +-9%). The first pass crowned the ridges with tiny spikes.
- `storm.gd`: `visibility` / `gust_visibility` take `or_greater`, so a scene can set kilometres.

## Cleanup

2026-10-14, grilled with the user from a screenshot of the first build. Mountains, clouds,
lightning, weather, camera and timing were kept as they were.

| # | Topic | Decision |
|---|-------|----------|
| 13 | Trail shape | **One smooth arc, no squiggles.** The Catmull-Rom through 9 hand-copied sketch points is replaced by one cubic Bezier (`TRAIL_ARC`) fitted to them (4.7 px RMS) with a convex control polygon, so it bends one way only. Its start is 60 m inside the deck, its end is Finish, and the breach is where it crosses the deck base (`breach_point()`, within 8 px of the sketch's). The head still reaches Finish at 5.0 s |
| 14 | Trail width | **2 m at the head to 9 m at the old end** (was 5 to 24 m): about 2 px and 9 px at 1080p. No thinner, or it shimmers |
| 15 | City layout | **One city instead of 6 clusters.** A dense downtown of about 22 ruins at sketch x 300-900 (`CITY_CORE`), tallest at its middle (up to 300 m); mid-rise sprawl at x 900-1550 (`CITY_SPRAWL`), 35-100 m, crowding toward downtown and thinning out right; 4 lone outliers at the edges (`CITY_OUTLIERS`). Depth 2.5-6 km, so the fog gives 3-4 layers of grey. All on one street grid turned 10-20 deg off the view axis, each building a few degrees off true. Skyline stays well under the trail |
| 16 | Ruin kinds | **All seven**, snapped towers and skeleton frames most common: snapped (jagged stubs of lost floors, sometimes a hanging section, some tipped 4-9 deg); skeleton (clad base, bare floor slabs every 15 m on columns, top floors half gone); a leaning pair (12-18 deg, the leaner's top corner resting on its neighbour); setback landmarks (3 tiers + bent antenna); half-standing facades (ragged strips, floor-high holes); one toppled tower lying across the snow in 3 pieces; a crane with a snapped, drooping jib. Snow-drifted rubble mounds all through. Snow on every top, ledge, break and slab |
| 17 | Corner mountains | **Hung on the camera** as flat shapes 3 m in front of the lens (`SILHOUETTE_DEPTH`), so they stay locked to the frame wherever the shot is instanced and flakes nearer than 3 m still blow across them. Same size and placement as the sketch, with 2-3 sharp peaks and rocky notches, sloping toward the centre |

Why the corners went missing: the user ran the shot through the root `descent.tscn`, a wrapper that
instances it moved by (-0.49, 0, 1.79). The camera pins its own global transform, but the
silhouettes were world geometry 4 m from the lens, so they moved with the wrapper and left the frame.

Built the same day. The city's boxes are merged into one mesh per colour (`DescentLand._box`
appends to a SurfaceTool), since the city is hundreds of boxes. Tests: one-way bend, width,
every ruin kind present, downtown denser and taller than the sprawl, depth spread, skyline under
Finish, silhouettes on the camera and pinned when the shot is moved.

## Retime (2026-10-14)

| # | Question | Answer |
|---|---|---|
| 18 | Ship speed | **Shot is 10 s, not 5.** The head reaches Finish at 10.0 s (was 5.0 s); the breach stays at 0.6 s, so the trail covers the same arc in 9.4 s instead of 4.4 s (about 2.1x slower). Trail `life` 6.5 -> 14 s so the whole line is still there at the cut at the same relative age. The later lightning flashes are spread over the longer shot (2.80 / 2.88 / 5.20 / 7.00 / 8.10 s); the breach flash is unchanged |
| 19 | Ship speed, again | **Half that speed: shot is 20 s.** Finish at 20.0 s, breach still 0.6 s, so the arc takes 19.4 s (about 4.4x slower than the original 5 s). Trail `life` 28 s. Flashes at 5.60 / 5.68 / 10.40 / 14.00 / 16.20 s. The head is already moving inside the deck when the shot opens (`start_time` < 0), hidden until the breach |

## Eye of the storm (2026-10-14)

Grilled with the user: the blizzard hid the scene. The shot is now in the calm eye of the storm.

| # | Question | Answer |
|---|---|---|
| 20 | Snow | **Light snowfall, not the blizzard.** Same `Storm` node, retuned on this shot's instance only (Ichi untouched): wind 0.4 m/s with `fall_ratio` 3 (about 1.2 m/s down, nearly vertical), `streak_time` 0.03 so flakes are round, not rain streaks, no gusts (`gust_amount` 0, `gust_visibility` = `visibility` so the fog wall never pulses), drift off (`drift_opacity` 0). Flakes cut to about 15-20%: fine 3500, near 300, near flakes thinner (0.045 m) and fainter (0.5) so nothing big crosses the lens. The 14 km haze stays |
| 21 | Trail | **No change.** Lighter snow should let it read; revisit only if it still gets lost |
| 22 | Clouds | **Subtle but real movement, on the shot clock** (seek / R give the same frame). The billow pattern turns slowly around the eye (a pivot over the camera) at about 3 m/s at the deck's front edge (`cloud_edge_speed`), and churns in place, one full reshape about every 10 s (`cloud_churn`). The lightning rings already follow the billows, so they move with them; flash timing and look unchanged |
| 23 | Snow amount | **Double it**, same fall and size: fine 7000, near 600 |
| 24 | Cloud edge | **Fades into the sky.** The dark tones clashed with the pale sky at the deck's front edge. Toward the edge the deck mixes smoothly to `edge_color` (matched to the fogged sky in probe shots) over `edge_fade` 0.55 of its depth (UV.y), ragged by the billows (`edge_ragged` 0.35) so thick lumps hold their tone further out and wisps fade first |
| 25 | Cloud speed | **3x slower**: turn 1 m/s at the deck edge (`cloud_edge_speed`), churn 0.033 (a reshape about every 30 s). 3 m/s / 0.1 shifted way too fast in play |
| 26 | Cloud mist | **The edge's mist over the whole deck** (user loved the soft fade). Wisps of `edge_color` up to `mist_amount` 0.6, in fbm patches `mist_size` 260 m across (15-100% strength) that churn with the billows; thin cloud takes more. Dark cloud shows between the wisps; the edge still fades fully; lightning draws on top |

## Storm side (2026-10-14)

Grilled with the user. The left of the frame becomes the storm the trail is heading into (their
reference: a supercell shelf cloud over a prairie, drawn in our cel style), the corners become real
terrain, the open field gets a few wrecks, and the lightning is toned down.

| # | Question | Answer |
|---|---|---|
| 27 | Existing lightning | **50% opacity.** The cyan rings in the deck mix in at half strength (`flash_opacity` 0.5 on the deck shader, cloud tones show through) and `FlashLight` is halved with it. The breach flash too, so everything stays in proportion |
| 28 | Background strikes | **Real visible bolts**, not sheet lightning: jagged cyan lines with a white-hot core and 1-2 short forks, dropping from the cloud through the band of sky above the mountains. About 10 km out, so their tops hide behind the deck and their feet behind the near ridge. They flicker over a few frames on the existing pulse shape (`IntroSpaceLightning.Flash`) |
| 29 | Strike timing | **About 7 strikes, none in the first 2 s** (the breach owns the opening). Two or three fire under the existing deck flashes (5.6 / 10.4 / 16.2 s); the rest are standalone with a small glow lit in the deck at their top; one double strike. Spread over the whole width. A table (`bolt_table`) like `flash_table` |
| 30 | Corner mountains | **Real 3D terrain** replaces the black silhouettes, covering the same screen shapes (the old polygons' top edges are now the ridge lines). Same snow-on-flats / rock-on-steeps cel look as the background ranges, a shade darker, craggy. Still hung on the camera (the wrapper scene moves the shot). A camera at 1.7 m sees ground this low on screen only a few metres away, so they are snowy outcrops 2-10 m from the lens, shaped like mountains |
| 31 | Blur | **Real camera depth of field**, near blur at moderate strength: the corners are soft but read as snowy mountains. The near snow at the bottom centre softens too (and close flakes), like a long lens focused on the city. Distance and amount are on the camera's `CameraAttributesPractical` |
| 32 | Wrecks | **6 lone wrecks, 300 m to 2 km out**, getting smaller toward the city, spread out (no clusters), clear of the corners (`FIELD_WRECKS`) |
| 33 | Wreck look | **The city's concrete blocks**, sunk 30-60% into the snow and tilted 10-35 deg each a different way: 3 snapped towers, 1 tipped nearly onto its side, 1 floor-slab skeleton leaning out, 1 with only its top floors poking out at an angle. A snow drift banked on each one's low side |
| 34 | Storm wall | **The deck bends down on the left** (`SHELF_LINE`): its front edge pushed out to about 3 km and its lip brought down to just above the left ridge, curving back up to today's cloud line by the centre (near Finish), so the trail flies into the mouth of the storm. Between the lip and the overhead deck it climbs in **4 stepped bands** (risers face the camera). The right side is unchanged. Same billow turn/churn |
| 35 | Snow curtain | **A dark curtain under the wall, about 6 km out, behind the city**: downtown stands in front of it, it mostly hides the left mountains, and it thins out toward the centre. Streaky, two hard alpha tones, fogged like the land. Left bolts fire behind it and light it from within |
| 36 | Wall colour | **Teal-grey tint** on the shelf: dark undersides near today's tone, risers lighter, pale teal on each band's lip; fades back to today's colours as the deck rises to the right |

Built 2026-10-14, tuned from probe screenshots (`tests/_probe_descent_shot.gd`, now with three bolt frames):

- **Corners** sit at a distance set per column from how low their ridge is (`0.55 x` the distance where
  the ground itself shows at that screen height, at most `CORNER_DISTANCE` 6 m). A fixed 6 m left the
  lower slope unreachable, and it went flat as pale slabs. `corner_snow_threshold` 0.45, so they are
  mostly snow with rocky crags. Lens: near blur `CameraAttributesPractical` 26 m / 14 m transition /
  amount 0.16, so everything within 12 m is fully blurred.
- **Wrecks** lean across the view, left and right in turn, with +-30 deg of jitter. Leaning toward or
  away from the lens hid the slant. They use their own lighter concrete (`C_WRECK_CONCRETES`), since
  the city's tones are made for 3-6 km of fog. The nearest one is 40 m long.
- **Storm wall**: the lip is at 3.2 km, about 240 m up on the left, climbing in 4 bands to the deck base.
  Riser 45% of each band. Deck mesh 440 x 160. The band tones follow the smooth billows only, since the
  fine detail sawed their edges. Edge fade on the wall is 0.35 of the flat deck's and mist 0.45.
- **Curtain**: `shaders/cutscene/snow_curtain.gdshader`, 6 km out, alpha 0.95 / 0.8 in two tones,
  fogged at 0.4 of the storm fog. Bolts at x < `CURTAIN_END_X` glow in it.
- **Bolts**: `scripts/cutscene/descent_bolts.gd` + `shaders/cutscene/bolt.gdshader`, 8 rows (7 strikes,
  one a double) in `bolt_table`, opacity 0.8, haze 0.4.

| # | Question | Answer |
|---|---|---|
| 37 | Corner mountains | **Removed** (2026-10-14, user's call after seeing them): no silhouettes and no corner terrain. Nothing hangs on the camera now. The lens's near blur stays, softening the near snow and close flakes |
| 38 | Curtain opacity | **Half** (2026-10-14): alpha 0.475 / 0.4 in its two tones (was 0.95 / 0.8) |

## Ruined interior (2026-10-14)

Grilled with the user from a rough idea sketch (placement explicitly NOT to be copied). The camera
is standing inside a destroyed building, looking out; what is close to the lens is near-black, in the
Hollow Knight manner. The two earlier corner passes failed as symmetric masses in both bottom
corners, so this frame is asymmetric and leaves both bottom corners open.

| # | Question | Answer |
|---|---|---|
| 39 | Where | **Ground floor, camera unchanged.** The view out is untouched; the ruin is built around the existing camera and rides it (the `descent.tscn` wrapper moves the shot) |
| 40 | Inside read | **A broken ceiling edge across the top**: thickest top-left (about 8-15% of frame height), crumbling thinner to the right and breaking off at about 70-75% across in snapped rebar. The top-right stays open for the breach |
| 41 | Bottom | **One leaning snapped pillar at the right edge**, cut by the frame, leaning 10-15 deg inward, its broken top with rebar at about 50-60% frame height (below the trail). **A thin ragged floor-slab lip** along the bottom, under 6% of frame height. No corner mounds |
| 42 | Hanging | **One busted pipe** at about 25-35% across, torn loose and bent, its open end hanging to about 35-40% down the frame. **A bundle of 3-4 sagging wires** at about 50-60% across, plus one snapped end dangling lower, all left of the trail's Finish |
| 43 | Tone | **Flat near-black `#0a0d12`**, unshaded, unfogged, no outline. During lightning (deck flashes and bolts) a thin cool-teal rim lights its edges, then it drops back to black |
| 44 | Motion | **Subtle**: wires sway out of phase, the pipe swings 1-2 deg slowly, and every few seconds a thin sift of snow trickles off the ceiling's broken edge. Nothing reacts to the breach |
| 45 | Focus | **Near depth of field off**, so the silhouettes (and the thin wires and rebar) stay razor-sharp |
| 46 | Rim strength | **Subtler** (2026-10-14, user: liked the lightning on the pipe "but not so much"): rim colour from bright cyan to a muted slate teal (0.4, 0.55, 0.6), `rim_energy` 1.0 -> 0.45. The breach flash now shows as a dim edge line, not an outline |
