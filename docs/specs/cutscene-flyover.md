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
