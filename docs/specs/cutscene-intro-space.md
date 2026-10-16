# Cutscene shot 1: intro space

2026-10-13. Grilled with the user, then built the same day. The first shot of the game's opening
cutscene: a snowy planet fills most of the frame, stars behind it, and the Vanguard flies in past
the camera and toward the planet. Composition is from the user's reference image (planet filling
the left of frame, its limb curving down the right side against a strip of stars, the ship seen
from behind, small, over the bright surface).

**This is a blockout.** Shot, movement and timing only. Effects come later (engine glow, bloom,
clouds, fades, sound).

## Decisions

- **Look: cel-shaded**, matching the game, not the photoreal reference. The ship keeps its
  cel material and ink outline (`cel_character.tres` through `ApplyStylized`, like trial.tscn).
- **Its own scene**, `scenes/cutscene_intro_space.tscn`. Watched with F6. Not wired into game
  start yet: the rest of the cutscene does not exist.
- **Planet: a sphere with a simple procedural shader.** 3D noise picks snow / pale glacier ice /
  dark blue ice-ocean / rusty rock bands (flat cel colour regions, not gradients), stepped light,
  a cyan atmosphere rim on the lit edge. No clouds, no extras. Tuned for this one camera angle and
  distance only; the camera never gets close.
- **Ship: `assets/vanguard_1.glb`.** Comes in from behind the camera, lower-left, sweeps past and
  flies away into the planet. We see its back. It ends small, left of centre, over the snow.
- **No effects yet.** No engine glow, no bloom.
- **Timing: 12 s.** 0-7 s planet and stars only. 7-12 s the ship flies past the camera and toward
  the planet (fast past the lens, easing out as it recedes).
- **Camera: a slow push-in** of about 4-5% of the distance to the planet over the 12 s with a
  small sideways drift, eased in and out. The planet turns slowly on its axis.
- **Framing and light as the reference.** Planet fills about the left 80% of the frame, the limb
  on the right against stars. Sun behind the camera and upper-left: the face is almost fully lit,
  a thin shadow sliver at the right limb.
- **Background: one procedural sky shader.** Simple stars (sharp points, two sizes, no twinkle)
  on near-black, a very faint blue-violet nebula haze.
- **Playback:** plays once on load and holds the last frame. R restarts, Esc quits. Emits
  `finished` at the end so later shots can chain off it. No HUD, mouse free.

## Build plan

- `scenes/cutscene_intro_space.tscn`: WorldEnvironment (sky shader), DirectionalLight3D sun,
  `PlanetTilt/Planet` (SphereMesh r = 1000 m about 1730 m from the camera), `CameraRig` +
  Camera3D, `ShipPath` (Path3D) / `ShipFollow` (PathFollow3D) / `Ship` (the GLB), `ApplyCelShip`,
  an AnimationPlayer with one `shot` animation holding every key so timing is tuned in the editor:
  camera position, planet rotation, ship visibility, ship path progress.
- `scripts/cutscene/intro_space.gd`: play on ready, `finished`, R / Esc.
- `shaders/space/planet_snow.gdshader`, `shaders/space/space_sky.gdshader`.
- `tests/test_cutscene_intro_space.gd`: timing, ship hidden then off-screen at 7 s, in frame and in
  front of the planet at 12 s, push-in amount, framing of the planet limb, finished / restart.

## Built

2026-10-13. Files as planned, plus `shaders/space/space_noise.gdshaderinc` (shared hash / value
noise / fbm) and `tests/_probe_intro_space_shot.gd` (windowed: seeks the shot to a list of times and
saves frames, `-- <out_dir> [t ...]`).

Numbers, all editable in the scene:
- Planet r = 1000 m, centre (-329, 0, -1695), tilted 18 deg on Z, turns 0.06 rad about its own Y
  over the shot. Camera fov 40, far 6000.
- Camera rig (0, 0, 0) -> (6, 1.5, -80), ease in-out (transition -1.6): about a 4.5% push-in.
- Ship path (Path3D, 2 points): (-4.2, -3.56, -36), 14 m behind the camera's 7 s position and to
  the lower left, -> (-13.4, 5, -200), about 120 m in front of the camera's end position, left of
  centre over the snow. `progress_ratio` 0 -> 1 from 7 s to 12 s, ease-out (transition 0.6): fast
  past the lens, slowing as it recedes.
- **The GLB's nose is +Z**, but PathFollow3D flies along -Z, so the `Ship` instance is turned 180
  deg under `ShipFollow`. Without that it flies backwards (we saw the intake cones head-on).
- Sun travels along (0.7, -0.3, -0.65), from behind the camera and to the upper left: lit face,
  a mid-tone band, a dark sliver at the right limb. The planet's light is scaled by its own
  `exposure` (0.33) because LIGHT_COLOR carries PI; the sun stays at 1.0 for the ship.

Departures from the grill: none. The planet's colour regions are flat (cel) noise bands with no
clouds; the atmosphere rim only shows on the lit side, so the right limb has none.

## Revision 2026-10-13: swoop entry, 3x speed

The user sketched a new entry over a probe frame (red line): the ship comes from behind the camera
at the upper left and sweeps across the planet in one clean arc, left to right, down to the lower
right. It also had to fly about 3x faster.

A first attempt hand-placed 6 points and flew the loop at the right end of the sketch as a hook;
it wobbled ("all over the place"). Rebuilt from the sketch itself:

- **The arc is traced from the drawing.** The red stroke was pulled out of the image and fitted
  with one quadratic Bezier (sketch px (225,290) -> control (820,690) -> (1300,740), within ~15 px
  of the stroke). Points along it are pushed out to depth 12 -> 200 m (linear) and become the
  Path3D, plus one start point 6 m behind the camera, up and left, so the ship enters through the
  upper-left corner. The loop and arrow at the right end of the sketch are read as "ends here",
  not flown.
- **ShipPath is a child of CameraRig**, in camera space, so the camera push-in cannot bend the
  arc on screen. tests/_probe_intro_space_path.gd prints the ship's screen path for overlaying on
  the sketch; it matched the red line end to end.
- **Bank**: constant left-wing-low roll, curve tilts 0, -0.15, then -0.3 rad.
- **Speed**: 7.0 -> 9.2 s over ~240 m, ~110 m/s (3x the old ~34 m/s), linear progress. The old
  ease-out stacked on perspective made the ship crawl for its last half second.
- **Shot is now 9.5 s**, not 12: the ship arrives at 9.2 s, so 12 s would hold a parked ship
  for ~3 s. The camera push-in and planet turn are rescaled to the 9.5 s.

## Revision 2: from the top-view sketch (2026-10-13)

The traced screen-space arc was still wrong: it started the ship almost directly behind the lens,
so it flew straight at the planet and then curved. The user drew a top (ortho) view: the ship
starts **off to the left of the camera, about level with it**, cuts across in front of the lens
heading right, then turns left into the planet, ending near the planet's right edge.

- The path is that drawing traced (stroke centreline, 8 points): sketch px -> metres at 0.54 m/px
  forward. Sideways it is scaled by 0.65, because the drawn camera cone is ~90 deg and the real
  horizontal FOV is ~66 deg, so the ship sits at the same place in the frame as in the drawn cone.
  Start (-74, 12, 1.6) in camera space, crosses the lens line ~50 m out at 7.75 s, widest at
  about ndc x 0.83 (8.35 s, briefly past the limb over the stars), ends (52, -39, -219), ndc
  (0.37, -0.49). Height (not in the top view) runs from 12 m above to 39 m below, smoothly.
- Seen in frame: enters from the left edge in profile ~7.5 s, crosses, turns away into the planet.
- Bank: left turn throughout, tilts 0, -0.2, -0.35, -0.55, -0.5, -0.3, -0.2, -0.1.
- 7.0 -> 9.4 s over ~290 m (~120 m/s), linear. Shot stays 9.5 s.
- tests/_probe_intro_space_path.gd also prints camera-space "L" lines for a top-view overlay.

## Revision 3: straight on to the planet, +3 s (2026-10-13)

User liked revision 2 but not the ending: the ship sank down the frame. Now, after the turn
(path point 5, about 8.6 s, ndc ~0.63), it flies **straight on**: same sideways heading as the
end of the turn, pitched so it holds its height on screen (ndc y -0.375 from ~8.9 s to the end).
It just shrinks, easing left toward ndc x ~0.2, out to 562 m (a speck over the rust patch). Bank
levels to 0 by then. Path points 0-4 are unchanged from revision 2; points 5-9 are the straight.
- ~635 m, 7.0 -> 12.2 s at the same ~122 m/s. Shot is now **12.3 s** (camera push-in and planet
  turn rescaled to it).

## Revision 4: one smooth path, still arcing at the end (2026-10-13)

User: "smooth out the arc", a jank about 3/4 through (the joint where the traced turn met the
straight in revision 3: heading and pitch changed abruptly there, with uneven point spacing),
and the end "flies flat at the planet"; it should keep arcing a little.

The path is no longer hand points. It is integrated from a turn rate (curvature) that is smooth
everywhere, and resampled every 10 m into the Path3D (65 points):
- curvature k(s) = 0.0005 + 0.01 * exp(-((s - 160) / 40)^2) rad/m: a soft bell for the main turn
  plus a small constant, so the ship never flies dead straight (~18 deg more turn over the tail).
  Start heading 54 deg right of forward, start (-74.4, 12, 1.6) in camera space. Fitted to the
  revision 2 traced top-view points, with the end at ndc x ~0.2 and a limit on time spent past
  the planet limb (it now only touches the limb briefly at ~8.5 s).
- descent slope 0.11 + 0.07 * exp(-s / 250) per metre: comes down from above the camera and
  settles at ndc y ~ -0.38, then rises very slightly (never sinks).
- bank = -(0.1 + 50 * (k - 0.0005)): -0.6 rad at the tightest point, -0.1 cruising.
- Same timing: ~640 m, 7.0 -> 12.2 s, shot 12.3 s.
- Generated by a throwaway script, so retuning means re-running the numbers, not editing points.
- **Bank hold (2026-10-13, user):** keep the tilt longer into the bend before levelling. Bank is no
  longer tied to curvature after the peak: it rises with the turn bell to -0.6 at s = 160 m, holds
  -0.6 to s = 220 m (~8.85 s), then eases to -0.1 with exp(-((s - 220) / 60)^2), level by ~9.8 s
  (was: unrolling from ~8.5 s, level by ~8.9 s). Path unchanged.
- **Bank to the end (2026-10-13, user):** "hold the tilt all the way until the end". The bank rises
  with the turn bell to -0.6 rad at s = 160 m (~8.4 s) and stays -0.6 to the end of the path; it no
  longer levels off.
- **Late left arc (2026-10-13, user):** "arc back a little left at the end". Curvature gains
  + 0.003 * smoothstep((s - 380) / 150) rad/m: from ~10.3 s the ship turns ~32 deg further left
  and ends just right of centre (ndc x 0.05, was 0.18). Everything before s = 380 m is unchanged.
- **Always arcing (2026-10-13, user):** "no straight, ship should always be arcing". Between the
  bend and the late arc the curvature had fallen to 0.0005 rad/m (~3 deg/s), which read as
  straight. The tail is now one function, replacing the separate constant + late arc: after the
  peak (s = 160 m) the bell eases into a steady left turn that tightens linearly from 0.0012 to
  0.002 rad/m by the end:
  k(s) = c(s) + (0.0105 - 0.0012) * exp(-((s - 160) / 40)^2), c(s) = 0.0012 + 0.0008 * (s - 160) / 480.
  Measured: never less than ~10 deg/s after the bend, rising to ~13.6 deg/s. Ends ndc x ~ -0.08
  (just left of centre); the end-position test now allows |x| < 0.2.

## Revision 5: from the 3D tube sketch (2026-10-13)

Grilled again. User: the arc "doesn't look real", "the turn is off". They redrew the flight as a
**tube** over the shot: the midline is where the ship is on screen, the tube's width is how big it
looks there. It comes in from off frame at the top left, sweeps down and right over the planet,
bottoms out over the rust continent (~80% across, ~75% down), then hooks hard up near the right
limb, shrinking to a speck at the tip (~73% across, ~53% down). Revision 4's curvature-integrated
path is gone.

Decisions:
- **The path is built from the tube**: midline traced as the screen position, width read as the
  ship's on-screen wingspan, so depth = 10.3 m * F / width. The 3D path falls out of that.
- **The hook is a turn away** from the camera: the ship turns and dives off over the surface toward
  the planet (going "up" the screen is perspective), not a pull-up.
- **Timing**: 7 s of empty planet, then a 5 s flyby (7.0 -> 12.0 s) at a **constant real speed**,
  so the on-screen slow-down is perspective. Shot stays 12.3 s (0.3 s hold on the speck).
- **Roll: top always aimed at the planet's centre** (automatic, not a fixed bank). Close in we see
  the ship's belly; it goes edge-on as it dives away.
- **Camera shake**: a small rotation rumble as it flies by, ~0.4 deg peak, smooth layered sines,
  7.0 -> peak 7.2 -> gone 7.8 s. Push-in and planet turn unchanged underneath.

### Built

- `tools/gen_intro_space_path.py` holds the tube's measured midline and widths (pulled from the
  sketch's three rails: silhouette top and bottom, plus the seam) and writes `Curve3D_ship` into
  the scene: Chaikin-smoothed midline, smoothed log-width, depth from width, a 3D smoothing pass,
  even 8 m spacing (so linear progress is constant speed), plus a lead-in carried back along the
  start direction until the whole ship is outside the frame (starts ~25 m out, ndc (-1.6, 2.0)).
  The closed hook stroke eases the width down to `TIP_W` = 5 px. A clearance clamp keeps the ship
  200 m off the surface along the line of sight (not reached at this scale).
- `tools/gen_intro_space_tilts.gd` (run after it) sets each point's tilt so the path's up points
  at the planet centre at the moment the ship is there (two passes; worst error 1.5 deg), and
  writes the tilts into the scene. Up can only be the planet direction slid off the nose, so
  up . to-planet is ~0.6 (the ship is diving at it), which is the most there is.
- **Planet scale 4x** (radius 4000 m, centre (-1316, 0, -6780), camera push-in (24, 6, -320),
  far 16000). At 1000 m the planet was too close for the tube: a 10.3 m ship a sixth of the
  frame wide puts the bottom of the curve 230 m out, and the 8 px tip would be 1650 m out, inside
  the planet, so the hook stalled and climbed at a fixed distance. The shader samples by direction,
  so scaling planet, distance and push-in together about the camera looks identical.
- Path: 330 points, ~2.6 km, ~525 m/s. Screen time splits as perspective dictates: the sweep from
  the corner to the bottom of the curve takes ~0.45 s (a whoosh, with the rumble), the hook
  ~4.5 s as it dives from ~250 m to ~2.5 km out. Altitude 2.6 km -> 0.5 km over the flight.
- Probe overlay (tests/_probe_intro_space_path.gd projected onto the sketch, wingspan circles):
  matches the tube's midline and width end to end.
- Shake: `shake_at(t)` in intro_space.gd (exports `shake_degrees`, `shake_start/peak/end`,
  `shake_hz`), applied to Camera3D rotation in `_process` from the animation position.
- Departure: if the sweep reads too fast, the knob is the progress key's transition (ease-out)
  or a slower entry; constant speed was the agreed call.

### Cleanup: one smooth arc (2026-10-13)

User: "looks really fucking good", but "make sure the ship is always arcing smoothly, and no weird
turns". Measured, the rev 5 path had single-point kinks (up to a 7 deg snap, roll jerking with them)
from smoothing a polyline, and the turn axis flipped twice (S-bends at ~7.1 s and 8-9 s), nearly
straight in between.

The path is no longer smoothed points. `gen_intro_space_path.py` now fits **one arc**: the ship
turns about a single fixed axis (so the path lies in one plane and cannot S-bend) at a turn rate
k(s) = exp(cubic), smooth and always positive. Start point, heading, plane, length and the cubic
are fitted (Nelder-Mead, ~2 min) to the tube's screen position and size, with the turn rate held
in [4, 60] deg/s (`TURN_MIN`, `TURN_MAX`) and penalised for changing fast (`TURN_EVEN`). The
off-frame lead-in is the same arc run backwards. Result:
- Turn rate 45 deg/s in the close sweep, easing to a steady 4-7 deg/s through the dive, one
  direction throughout (a pull up and to the left); roll rate -3 to -31 deg/s, no spikes.
- Worst screen distance from the tube's midline 26 px; the hook is a clean curl just inside the
  drawn one.
- ~2.27 km at ~453 m/s (constant), same 7.0 -> 12.0 s.
- New test `test_ship_always_arcs_one_way_without_kinks`: fixed turn axis, 2.5-70 deg/s, turn rate
  never jumps more than 25% per 0.02 s.

## Planet upgrade: a desolate future Earth (2026-10-13)

Grilled with the user. The blockout planet looked good as a base; this makes it cutscene ready:
depth, clouds, a readable ocean, mild mountains, and Earth's real continents, still in the cel
style. Detail only where the camera looks.

### Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Continents | **Mix**: real Earth coastlines (NOAA ETOPO1), our noise roughing coasts and land so it never reads as a map |
| 2 | Which face | **North America**. Pacific coast toward the left edge, Atlantic down the right limb |
| 3 | Climate | **Deep ice age**: ice sheet over Canada and the northern US, sea ice in the north, bare rust land to the south, open dark ocean. "To about the Great Lakes" |
| 4 | Destination | **Florida** sits under the end of the ship's dive. Present-day coastlines |
| 5 | Clouds | **Flat cel shell**: hard edges, one shadow step, cast shadows offset on the ground. ~30-40% cover: a storm comma over the ice front, streaky bands over the Atlantic, patches over the rust. **Florida stays clear.** Slow drift |
| 6 | Ocean | Stepped shelf bands (deep -> teal shelf -> pale coast), sea-ice fringe in the north, and a cel-stepped sun glint on water only, **cheated** onto the water near Florida |
| 7 | Mountains | Real elevation, masked to the ranges (Rockies, Sierra Madre, Appalachians), mild, shaded by a **relief-only raking light** from the upper left; snow caps on the high Rockies |
| 8 | Detail budget | One public-domain ETOPO1 crop of only the box the shot sees, baked to one ~2200x1200 texture. Outside the crop, the old noise planet (never on camera). No mesh trimming |
| 9 | Atmosphere | **Halo shell** behind the planet: 2-3 hard cyan bands fading into space on the lit limb, a thin dim band on the shadow side. Surface rim stays |
| 10 | House style | Painted value patches (planet-scale) in land, ice and cloud tones, cel scatter on the terminator and cloud-shadow edges. **No ink** (outlined coasts read as a political map) |

Defaults (not asked): no city lights or ruins; ship, path, timing, push-in, shake, sky and the
planet's 0.06 rad turn are untouched; every colour / level / width is a shader uniform.

### Build plan

- `tools/gen_planet_earth_frame.gd`: finds the surface point under the ship's speck at 12 s,
  rotates `PlanetTilt` so Florida is there with north (the spin axis) as close to the old tilt as
  possible, prints the lat / lon box the frame sees over the shot.
- `tools/gen_planet_earth.gd`: bakes the ETOPO1 crop to `assets/textures/planet_earth_na.png`
  (R signed-root elevation, G smoothed land height, B mountain mask). Imported lossless with
  mipmaps (`detect_3d/compress_to=0`: VRAM compression would wreck the elevation encoding).
- `shaders/space/planet_earth.gdshaderinc`: lat / lon, the texture lookup, the cloud field (shared
  by the ground shadows and the cloud shell).
- `shaders/space/planet_snow.gdshader`: Earth surface inside the crop, old noise outside.
- `shaders/space/planet_clouds.gdshader` on `PlanetTilt/Planet/Clouds`, `planet_halo.gdshader` on
  `PlanetTilt/Halo`.
- `intro_space.gd` drives the cloud drift from the shot time (seeking shows the same frame).

### Built

2026-10-13, same day. Files as planned. Numbers that matter (all uniforms, editable in the scene):

- **Orientation.** `gen_planet_earth_frame.gd` found the surface under the ship's speck at 12 s and
  set `PlanetTilt`'s basis so Florida (27.8 N, 81.7 W) is there. North (PlanetTilt +y, the spin
  axis) had to swing **38.8 deg toward the camera** from the old 18 deg tilt to fit Florida's
  latitude, so the planet's 0.06 rad turn is now a true eastward Earth spin. Visible box over the
  shot: 4.4 S - 48.1 N, 137.4 W - 37.3 W; the crop is 8 S - 52 N, 142 W - 32 W. Gotcha: `.tscn`
  writes `Transform3D` **row by row**; the first save wrote columns (the inverse rotation).
- **Data**: ETOPO1 ice surface from NOAA ERDDAP (`etopo180`, 3 arc-minute stride, 14 MB text, kept
  out of the repo), baked to `assets/textures/planet_earth_na.png` (2201x1201, 2 MB).
- **Ice sheet front at 39 N, not the Great Lakes**: the frame only reaches ~48 N (at the limb), so
  a Great Lakes front would barely show. 39 N is the real Laurentide maximum (the Ohio River), lobed
  +-2.5 deg, with a 1.3 deg pale glacier band inside it. The sheet is smooth (no relief).
- **Ocean**: abyss / shelf (< 190 m) / pale coast (< 28 m), coasts roughed by +-10 m of noise (45 m
  turned the shallow Bahamas banks into land). Sea ice from 41 N, packed by 50 N.
- **Land**: rust with darker rust and ochre zones (noise, 15 per unit sphere), snow above 2700 m.
- **Mountains**: relief masked to `smoothstep(0.2, 0.65)` of the mountain mask (plains and the
  Mexican plateau stay flat), 40x exaggerated, one dark and one light step under the relief light
  (-0.75, 0.6, 0.3), world space.
- **Clouds**: a 4012 m shell. Shapes are **stretched 2.4x east-west** (round fbm blobs read as
  more land from orbit), 0.17 per degree, `cloud_cover` -0.055, plus the storm comma (twirl + one
  spiral arm, 40.5 N 91 W, 7.5 deg) on the ice front, Atlantic bands (32 deg, west of 71 W), clear
  6.5 deg around Florida. **Departure:** cloud shading and cast shadows use the relief light, not
  the sun. The sun comes from nearly behind the camera, so a sun-offset shadow would sit hidden
  under its cloud. Shadow offset 0.009 (unit sphere), tone 0.68. Drift 0.35 deg east over the shot,
  driven by `intro_space.gd::cloud_drift_at(t)`.
- **Glint**: 26.6 N 84.6 W (inside the clear zone, off Florida's Gulf coast), core 0.9 deg, halo
  2.2 deg, emission 0.55.
- **Halo**: 4200 m shell, bands at 13 / 32 / 62% of the shell height (0.7 / 0.34 / 0.13).
  **Departure:** the only limb in frame is on the night side, so the halo stays day-bright for
  `day_reach` 0.45 past the terminator (twilight), then **thins into a crescent** (`night_thickness`
  0.3) instead of switching bands, which left a wedge-shaped glitch on the limb.
- **Style**: painted patches (the global PAINTED SHADING values, 30 per unit sphere, mixed 0.6) on
  land, ice and clouds, not open water; cel scatter strokes chip the terminator, the cloud shading
  edge and the cloud shadow edge. Both follow the game's toggles.
- **Bake in GDScript, not Python**: this machine's Python has no numpy, and Godot's `Image` does it
  in 6 s.
- 8.6 ms a frame at 1080p on the RTX 3060 (whole scene, last frame).
- Tests: Florida under the ship at 12 s, the turn is eastward about north, every pixel at 0 and
  12.3 s inside the crop, cloud shell / halo sizes, cloud drift shared by both materials, lossless
  import.

### Storm over Florida, the whole USA under snow (2026-10-13)

User: the ship should fly into the storm; the ship path is fine, change only the planet.

- **Storm** moved from the ice front (40.5 N 91 W) to Florida (27.8 N 81.7 W), right under the
  dive's end, strength 0.26 -> 0.36 so the core is solid cloud. The clear-sky hole over Florida is
  gone (`clear_lat_lon` / `clear_radius_deg` removed).
- **Ice sheet** no longer stops at 39 N: its front follows the US southern border (`US_BORDER`
  corners in planet_snow.gdshader, Gulf side at the Florida Keys' 24.3 N), pushed
  `ice_border_margin_deg` 1.0 into Mexico so no lobe bites the US, lobes 0.6 deg, glacier band
  0.6 deg. South of `ice_shelf_lat` (39 N) it covers land only, so the Gulf stays open water.
  Mexico stays rust. The Gulf glint now sits under the storm / ice and mostly doesn't show.

Follow-up (2026-10-14): "the whole USA" meant **the whole planet frozen over**. All land is now
`snow_color` (rust / ochre zones, snow caps and the border-following front are gone); the shelf
north of `ice_shelf_lat` 39 N is still frozen flat. The masked mountain relief now applies to all
land, so the ranges read through the snow; `relief_shadow_tone` 0.78 -> 0.68 because the shading
step is weaker on white than it was on rust. Oceans, sea ice, clouds and the Florida storm are unchanged.

## Effects pass (2026-10-14)

User: "a cool trail coming from the ship's engines streaking as it flies by", a moving storm with
small lightning, "make it look like a terrifying storm", plus whatever motion the scene is missing.
Grilled; everything below is a function of the shot time, so seeking / restarting shows the same
frame (same rule as the rumble and cloud drift).

### Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Scope | Engine trails, a living storm (spin + lightning), glow, re-entry heat on the dive, a hull glint at the flyby. No star twinkle, aurora or space dust |
| 2 | Trail look | Hard cel ribbon (white-hot core, cyan, dark blue edge), only the core blooms |
| 3 | Trail count / life | **2 ribbons, one per engine pod**, world space, **4 s life**, adjustable (`trail_life` = `EngineTrails.life`) |
| 4 | Trail ageing | **Spreads and dissipates**: core gone by ~0.3 s, pales to a broad light cyan, the old end breaks up in hard chunks (not a smooth fade) |
| 5 | Storm motion | **Slow believable spin**, ~12 deg counter-clockwise over the shot, eye a little faster than the edge. No boiling |
| 6 | Lightning look | **In-cloud flashes only**: hard-edged violet blobs with a white centre, flickering 2-3 times in ~0.2 s. No visible bolts |
| 7 | Lightning timing | ~1 per 2 s before the ship, **building** to ~4 / s by 12 s, chains between neighbours, and a **final sting**: one big flash where the ship is heading, dark again before the last frame |
| 8 | Re-entry heat | From 9 s to full at 12 s: stepped glow on the leading faces, a bow-shock rim shell, new trail segments go cyan -> orange |
| 9 | Hull glint | Hard white band sweeping across the hull in 0.15 s + a four-point star, at the real reflection time (cheat onto the rumble peak if it fell badly) |
| - | Glow (default) | Environment glow, HDR threshold 1.0: only effects brighter than white bloom, the planet stays crisp |

### Built

- **Trails**: `EngineTrails` (`scripts/cutscene/intro_space_trail.gd`, `shaders/space/engine_trail.gdshader`).
  An ImmediateMesh rebuilt every frame: 90 samples / s of trail, each asking
  `intro_space.gd::ship_model_at(tau)` where the ship was at past shot time tau. That reads the
  animation tracks (rig position, path progress) through a hidden second PathFollow3D, so the past
  is exact and seekable (test: matches the live ship within 5 cm). Ribbons face the camera; nozzles
  are the pod rims at (+-1.5, 1.12, -2.3) in model space. Width 0.6 m -> 2.6 m over the life
  (`spread_curve` 0.6), core 0.3 of the width for the first 0.075 of the life, `core_energy` 1.5,
  opacity in 4 hard steps, chunks from noise on emission time (so they stay where they were left)
  from 0.55 of the life. Heat per segment comes in as vertex colour.
  **Departure:** width_end is 2.6 m, not wider: anything more filled half the frame where the old
  swipe sits a few metres from the lens.
- **Storm spin** (replaced 2026-10-14, see "Eye spiral"): the whole storm used to turn 12 deg
  through `storm_spin` in `earth_storm_local()`. `storm_lat_lon` / `storm_radius_degrees` are now exports on the script, pushed
  to both materials on load (the shader default can't be read back headless).
- **Lightning**: `scripts/cutscene/intro_space_lightning.gd` builds a seeded schedule
  (`lightning_seed` 7, Poisson gaps, rate 0.5 -> 4.0 / s over 7-12 s, 30% chains, none after
  11.5 s); flashes sit on the eye wall (40%) or along the spiral arm (60%), radius 0.9-1.9 deg, in
  storm-local degrees. Each frame the 8 brightest go to the cloud shader's
  `flashes[8]`. Two hard tones; only the white centre crosses the glow threshold. The sting starts
  at 11.75 s (pulses 0 / 0.07 / 0.13 / 0.24 s, brightness 1.5, 2.6 deg), placed where the ship's
  nose ray meets the planet at that time; dark again by ~12.17 s.
- **Glow**: Environment glow on, additive, threshold 1.0, intensity 0.5.
- **Heat**: `ship_fx.gdshader` as material_overlay on every ship mesh (faces along the flight
  direction light in three hard bands that spread back as heat rises), `BowShock` (hemisphere over
  the nose, rim only, `bow_shock.gdshader`), and **`HeatGlow`**, an orange flare (the glint star
  shader, 40 m at full heat) on the nose. **Departure:** HeatGlow wasn't in the grill; past ~1 km
  the ship is a few pixels and the face glow and bow shock don't read without it.
- **Glint**: measured, the faces that mirror the sun into the camera are the ship's **back** faces
  (sun behind the camera, ship flying away), peaking at 7.20-7.24 s, right on the rumble peak, so
  no cheat: `glint_time` 7.2. The band sweeps side to side across the back (not nose to tail) and
  `GlintStar` (7 m, `glint_star.gdshader`) rides its centre.
- Tests: `test_trail_reads_the_ship_off_the_animation`, `test_two_trails_start_with_the_ship_and_last_their_life`,
  `test_storm_stays_still_and_only_the_eye_spiral_turns`, `test_lightning_builds_through_the_dive_and_ends_on_the_sting`,
  `test_heat_builds_through_the_dive`, `test_glint_flashes_once_at_the_flyby`, `test_only_hdr_effects_glow`.

## Eye spiral (2026-10-14)

User: the storm should not rotate; keep it where it is (it shapes the clouds), and instead put a
slowly spinning spiral layer on top of the round eye only (drawn in red on a screenshot).

- The storm field and its frame no longer turn: `storm_spin` is gone, `earth_storm_local()` is
  plain degrees east / north of the eye, the lightning frame is fixed.
- `planet_clouds.gdshader` draws one archimedean lane in `cloud_shade_color` on the cloud shell
  inside `eye_radius` 0.6 x `storm_radius_deg`: `eye_turns` 3.5 windings, arms trailing
  clockwise outward (northern hurricane), `eye_line_width` 0.13 of the winding gap with
  `eye_line_noise` 0.6 brush breakup, thinned to nothing at the centre and the rim.
- It turns counter-clockwise from above at `eye_spin_rate` 4 deg/s (export on intro_space.gd,
  `eye_spin_at(t)`, seekable), pushed to the cloud shell only as `eye_spin`.
- Test: `test_storm_stays_still_and_only_the_eye_spiral_turns`.

## Storm eye rebuild (2026-10-14)

User: "the storm looks terrible" - the flat white disc with a drawn spiral reads as a logo, the
violet lightning is a blob and only really starts when the ship comes in. Wanted: cool and
menacing, layered, built from the same twirled cloud noise as the outer arms (which looked right),
with a dark, hollow eye. Grilled; replaces "Eye spiral" (spiral, `eye_spin`, `eye_spin_rate` gone).

| # | Question | Decision |
|---|---|---|
| 1 | How the eye is hollow over snowy Florida | **Shadowed pit**: cloud shell paints a stepped inner wall + slate floor, eyewall shadow across it, dark whatever is below |
| 2 | Layers | Outer bands (unchanged), 3 inner rain bands, moat, eyewall, eye |
| 3 | Motion | Inner layers turn, outside still - **very subtle**: eyewall 1.5 deg/s, bands 0.75 deg/s CCW |
| 4 | Lightning colour | Cold electric white-blue: pale cyan glow, white core |
| 5 | Lightning shape | Lights the cloud's own shape + branching crawler veins on big flashes |
| 6 | Lightning timing | Steady from 0 s, building through the dive, ending on the sting |
| 7 | Eye size | 0.2 x storm radius, eyewall to 0.45 |

Built:
- `planet_earth.gdshaderinc::cloud_layers(e, out layer, out storm)` (`cloud_field` wraps it, so the
  surface's cloud shadows still match). Everything inside the storm is sampled at a point turned back
  by `storm_spin_at(sr)` (eyewall turn inside the moat, band turn out to 0.9, none past 1.3). The old
  solid `env` fill only applies past ~0.7 r now. Layers (`STORM_*`, heights in `storm_height`):
  eye < `storm_eye_radius` 0.2; eyewall < `storm_wall_radius` 0.45, rim bulging 0.3 where the bands
  meet it; rain bands past `storm_band_inner` 0.56 to `storm_band_outer` 1.05,
  `cos(3 * (angle + log r * 2.6))` (same pitch as the outer arm), `storm_band_fill` 0.55,
  `storm_band_tear` 0.9; the gap between is the moat; grey deck under it all to
  `storm_deck_radius` 0.9. Every edge is torn by the twirled noise plus a finer swirled octave.
- `planet_clouds.gdshader`: two extra layer samples per pixel, one away from the light (shaded edge)
  and one toward it (`storm_cast_offset` 0.006: a higher layer there casts a hard shadow). Deck
  grey-blue / shadow, storm shade on the bands and eyewall, white tops. Pit: inner wall face
  (`eye_wall_step` 0.3 of the eye) lit on the side facing the light, slate floor, near-black floor
  under the eyewall's shadow (`eye_shadow_reach` 0.11). `storm_opacity` 0.95, the pit fully solid.
- Lightning: `flash_color` pale cyan, white core. A flash lights each pixel by
  falloff x catch (bands / eyewall 1, deck `flash_deck_catch` 0.35, eye 0.15) x cloud density, so
  the lit patch is cut out by the bands' torn edges. Flashes above `crawler_level` 0.6 throw
  crawler veins (ridged noise seeded by the flash position, jittered to zig-zag, tapering to
  `crawler_reach` 2.4 radii; `crawler_energy` 3 so they bloom).
- Schedule: rate 2.5 / s from the first frame -> 6 / s over 7-11 s (exports
  `lightning_rate_early/late`, `lightning_ramp_end`); spots 45% eyewall, 45% along a rain band
  (turned with it, `build(..., band_spin_rate)`), 10% outer arm. Layout constants in
  `intro_space_lightning.gd` must match the shader defaults. Sting unchanged.
- Departures: the 6 / s late rate (grill said ~5): chained flashes pad the early rate, so 5 didn't
  read as a build. The deck catches less light than the bands, a choice made from probe shots.
- Tests: `test_storm_frame_is_still_and_only_the_inner_layers_turn`,
  `test_lightning_runs_the_whole_shot_builds_and_ends_on_the_sting` (from the first second, longest
  dark gap < 1.6 s).

## Ship swap: Sinestro shell (2026-10-14)

User: "replace the shell basically" - new Blender ship (3 engines) in place of Vanguard, path and rotation
untouched. Grilled:

| # | Decision | Answer |
|---|---|---|
| 1 | Size | Scaled 0.68 so the 15.2 m wingspan matches Vanguard's 10.3 m (the tube sketch's sizes still hold) |
| 2 | Pivot | Shifted so the hull centre sits where Vanguard's was (follow-space z +0.415) |
| 3 | Trails | Three, one per engine; centre trail 1.4x wider (its nozzle is ~1.4x the pods') |
| 4 | Asset | New file `assets/sinestro_1.glb`, cutscene only; `vanguard_1.glb` and the trial.tscn prop untouched |

### Built

- `Ship` = `sinestro_1.glb`, `Transform3D(-0.68 .. -0.68, origin z 2.215)` (180 deg turn kept). Path,
  progress keys, tilts, shake, timing unchanged.
- `EngineTrails.nozzles` (model space): main (0, 1.47, -3.72), pods (+-6.89, 1.47, -1.94), at the rims;
  `nozzle_widths` [1.4, 1, 1].
- BowShock / HeatGlow moved 0.81 m back (the new nose tip is that much shorter) and to y 1.0; glint band
  sweeps pod tip to pod tip (+-7.6, 1.47, -2.0). The extra `ship_sec2` slot is picked up by `ApplyCelShip`.
- Tests: `test_three_trails_start_with_the_ship_and_last_their_life` (+ centre wider),
  `test_ship_shell_matches_vanguards_size_and_centre`. Probe frames 7.05-11 s: three ribbons out of the three nozzles.

### Calmer camera (2026-10-14)

User: "too much camera movement or planet movement" (storm itself untouched). Measured over the
12.3 s: the push-in grew the planet 35.4 -> 37.3 deg (~5.5%) and the 0.06 rad planet turn slid the
storm ~0.08 screen units toward the limb. Both cut to 30%, **keeping the approved end frame**
(cutting from the start instead moved Florida 3.6 deg off the end of the dive):
- Camera rig **(16.8, 4.2, -224) -> (24, 6, -320)**, same ease: ~1.4% push-in.
- Planet turn **0.042 -> 0.06 rad** (0.018 over the shot).
- End frame identical to before, so the dive still ends in the storm eye over Florida. Ship path is
  camera-space and `ship_model_at` reads the rig track, so trail / sting / heat follow. Test now
  locks a 1-2% push-in.

## Title card: EARTH 2129 (2026-10-14)

Grilled with the user, built the same day. A movie title card in the bottom-left corner over the
empty-planet opening, wiped away by the flyby.

| # | Decision |
|---|---|
| 1 | **In**: "EARTH 2129" fades in 1.5 -> 3.0 s, after the planet has had a moment alone |
| 2 | **Out**: "the ship wipes away the letters". A fast left-to-right wipe 7.0 -> 7.3 s (rumble start to just past its 7.2 s peak), eased so it leaves fast, the direction the ship crosses the screen. The text shakes with the camera rumble while it goes |
| 3 | **Coordinates** under the title, DMS: `27°48'14"N  81°41'52"W`, under the storm eye over Florida where the dive ends |
| 4 | **Look**: Barlow Condensed (the menu font). Title SemiBold, caps, wide spacing, white 90%, ~6% of screen height. Coordinates Regular, 35% of the title size, same spacing. |
| 5 | **Staggered**: the coordinates fade the same way 0.6 s behind the title (2.1 -> 3.6 s) |

Built:
- `scripts/cutscene/intro_title_card.gd` (`IntroTitleCard`, a CanvasLayer): builds the two labels
  and the wipe shader in code; every tunable is an export on the `TitleCard` node in
  `scenes/cutscene_intro_space.tscn`, so `cutsceneintro.tscn` gets it too.
- **Departure:** the fades are functions of the shot time (exports), not keys in the `shot`
  animation, the same pattern as the rumble and every effect; seeking and R still show the right frame.
- `intro_space.gd` calls `update_card(t, shake_on_screen(camera.rotation))` each frame;
  `shake_on_screen` turns the rumble into a canvas-pixel offset (yaw -> x, pitch -> y, via the fov).
- The wipe uses SCREEN_UV with the block's left / right as screen fractions (FRAGCOORD would not
  match canvas units under canvas_items stretch at other window sizes).
- Coordinates 60% -> 75% opacity after probe frames (faint over the snow).
- **No dark backing.** A soft corner vignette was built for readability over the snow, then removed
  at the user's word ("get rid of the dark behind the text"). Don't add one back.
- **Smaller, on the water** (user drew the box): readability comes from placement instead. Title
  0.06 -> 0.04 of screen height, coordinates 0.35 -> 0.42 of the title, margins split into
  `margin_left` 0.13 / `margin_bottom` 0.07 (of screen height) so the whole block sits on the open
  Pacific off Baja, clear of the snow and the clouds, from fade-in to wipe (checked at 4.0 and 6.95 s).
- Tests: `test_title_card_fades_in_staggered_and_is_wiped_by_the_flyby`,
  `test_title_card_text_and_corner`, `test_title_card_shakes_with_the_camera`.

## Opening pan (2026-10-16)

Grilled with the user, built the same day. The shot now opens on empty space and tilts down onto
Earth; everything that was there before starts, unchanged, once the pan lands.

| # | Decision |
|---|---|
| 1 | **Prepended**: the old 12.3 s shot is untouched and starts when the pan lands. Shot ~17.3 s |
| 2 | **Path**: tilt straight down from above, so Earth rises in from the bottom edge (clear of the ship's left-side entry) |
| 3 | **Timing**: 1 s hold on stars + 4 s tilt |
| 4 | **Start angle**: ~65 deg up, pure space. Earth + halo reach ~39 deg above the view centre and the frame only 20 deg, so this is the first angle that shows no Earth at all |
| 5 | **Motion**: eased in and out, settles exactly on the old frame 0 (zero speed at the handoff, no bump into the push-in) |
| 6 | **During the pan**: ambient alive (twinkle, cloud drift, storm turn run on through it). Every timed beat (lightning, title, push-in, planet turn, ship, trail, rumble, heat, glint) waits and keeps its old timing from the handoff |
| 7 | **Open**: fades up from black over the 1 s hold |

Build: the `shot` animation is not touched. `intro_space.gd` keeps a shot clock that starts at
`-pan_length()` and runs the pan before the AnimationPlayer plays; the shot time `t` is negative
during the pan. Ambient functions (`cloud_drift_at`, `storm_spin_at`, twinkle) carry on into
negative time; the timed beats already read zero before their start. The tilt is a camera pitch
added under the rumble. Exports (`Opening pan` group): `pan_on`, `pan_hold`, `pan_tilt`,
`pan_start_degrees`, `pan_fade`. R and Intro_Movie restart from the black open.

**Retime (2026-10-16):** user: "WAY slower, like 3x". Tilt 4 -> 12 s (`pan_tilt`), hold and fade
unchanged at 1 s; the pan is now 13 s and the shot ~25.3 s.

### Crop widened for the pan (2026-10-16)

The tilt shows the planet up to ~85 N, 179 W-37 W (Alaska, the Canadian Arctic, Hudson Bay,
Greenland), all past the old 52 N / 142 W crop edge, so the old noise planet showed there as rust and
blue blobs. Re-downloaded a wider ETOPO1 crop (ERDDAP `altitude[(-8):3:(86)][(-180):3:(-32)]`,
2961 x 1881) and rebaked `planet_earth_na.png`; crop constants in planet_earth.gdshaderinc, the tool
comment and the tests updated. No shader logic changed: the existing latitude rules (ice shelf
north of 39 N, pack ice solid by 50 N, all land snow, relief on real ranges) cover the Arctic, and
the clouds now run on past 52 N. `test_the_frame_only_sees_the_baked_crop` now also checks pan frames.

## Title card retimed onto the pan (2026-10-16)

User: a 2 s pause between the pan settling and the title appearing; "have the title card appear right as the
camera is about to finish panning". First pass moved the title 2.5 s earlier (-1.0 s), which left the ship 7 s
after the pan ("the ship fly in is way too delayed"). Final: **the pan overlaps the shot by 2.5 s**
(`pan_overlap`): the shot clock starts while the camera is still tilting and the pan lands at shot time 2.5 s.
The title and everything else keep their old shot times (title 1.5 s, flyby 7 s), so the title starts 1 s
before the camera lands and the ship comes 4.5 s after it, the rhythm the shot had before the slower pan. The
push-in and planet turn (both at 30%) start under the last 2.5 s of the tilt. The pan is now 10.5 s before
frame 0 (1 s hold + 12 s tilt - 2.5 s overlap); the whole intro is 2.5 s shorter.
