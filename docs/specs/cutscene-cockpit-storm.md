# Cutscene shot: cockpit storm

2026-10-15. Grilled with the user, then built the same day. A second shot inside the cockpit: pilot9
in the same floating Gundam seat inside the screen sphere (docs/specs/cutscene-cockpit.md), but the
outside feed is snow, not re-entry fire. The ship flies into the storm: the sphere reads soft
snowfall, then eases into a blizzard. In the story it comes before the descent shot, but it is not
wired into Intro_Movie (user: leave the movie and the sequence alone for now).

## Decisions

- **Own scene:** `scenes/cockpit_storm.tscn`, root node `CockpitStorm`. Reuses the fire shot's parts
  (seat, pilot, seated pose, wire sphere, holo panels, shake math, the shot script) as they are.
  None of the fire nodes. `scenes/cockpit.tscn` is untouched.
- **10 s.** Plays on load, emits `finished`, R restarts, Esc quits (the fire shot's `cockpit.gd`).
- **Camera: locked off.** No push-in, no tremor. In front of him and lower than the fire shot (which
  is high and to his left), close to the user's two editor screenshots: nearly head-on, a little to
  his left, looking down at the seat, the whole seat in frame, the new panel and the button strip on
  screen. Matched by eye; the exact editor view was never saved.
- **Screen: snow.**
  - 0-3 s soft snowfall: big slow flakes drifting back past him from the point dead ahead (behind
    the camera) toward the vanishing point behind his seat, with a little wobble.
  - 3-7 s the blizzard eases in (smooth ramp, not a slam). Full at 7 s, held to 10 s.
  - Blizzard: the same forward flow, much faster, flakes stretch into streaks, plus a strong
    crosswind that sweeps the field left to right across the frame.
  - Sky behind the snow: dusk, deep blue-grey at the top, paler grey-blue haze low (the cloud deck),
    flat cel bands. Washes up to a bright pale-teal whiteout with the blizzard. Flakes white with a
    pale-blue shadow tone.
- **Light follows the screen.** Soft phase dim and cool blue-grey, low contrast; the green holos are
  the brightest thing on him (green spill). Blizzard: the fill brightens to a flat teal-white, with
  gust flicker (brightness pulses with the streak density). Two lightning pops, about 7.5 s and
  9 s: a hard white flash on the sphere and on him.
- **Seat buzz ramps with the storm.** He stays relaxed: no tension, no lean, no thrown jolts. The
  buzz just carries him with the seat. He is an experienced pilot.
- **Beats** (right hand on his right, left hand on his left):

  | time | right hand | left hand | screen |
  |---|---|---|---|
  | 0-1.0 s | on stick | on stick | soft snow |
  | 1.0 s | | | a new route panel pops up above the narrow radar panel on his right |
  | 1.3-1.7 s | to the panel | flying | |
  | ~1.9 s | tap 1: top button fills, radar route bends | | |
  | ~2.4 s | tap 2: bottom button fills, panel flashes (confirm) | | |
  | ~2.7 s | | | panel folds shut |
  | 2.7-3.2 s | back on stick | | blizzard starts easing in at 3 s |
  | ~3.5-4.5 s | | presses 3 slots on the button strip, unhurried; each lights cyan and stays lit | |
  | ~5 s | | back on stick | |
  | 5-10 s | both on sticks, riding the buzz | | full blizzard at 7 s |

  His head turns toward the panel while he taps, then back to forward.
- **Route panel:** small, square, the same green holo style (mirrored to the camera like the others).
  Header bar, a small radar with a storm blob and a route line, two big rounded buttons stacked.
  No words.
- **End: hold** on the blizzard, no fade.

## Build plan

- `shaders/cockpit/snow_storm.gdshader`: on the inside of a sphere, like the fire. Flakes live in
  log-polar cells round the rear vanishing point (angle round it, log of the angle from it), so they
  shrink and slow into it with real perspective; three layers for depth. The flow source swings
  sideways with the storm (the crosswind). Sky in cel bands by height, gust haze bands, lightning.
  Driven entirely by uniforms (shot time, storm, integrated travel, flash), so a frame is pure in t.
- `CockpitSnow` (MeshInstance3D): builds the sphere, takes `storm`, `travel`, `flash`, `gust`.
- `StormBeats` (pure): the storm ramp and its integral, gusts, lightning, the route panel's open /
  taps / close, both wrist targets, the head turn, which strip slots are lit.
- `CockpitStormDriver` (the `Storm` node): applies StormBeats and CockpitShake (no jolts; the
  buzz ramp is CockpitShake's surge) to the seat, holo rig, pose, panel, strip lamps, lights, sky.
- `HoloDisplay.Kind.ROUTE`, and `CockpitHolo.with_route` (off in the fire shot).
- Tests: `tests/test_cutscene_cockpit_storm.gd`. Probe: `tests/_probe_cockpit_storm_shot.gd`.

## Built

2026-10-15, as planned. New: `scenes/cockpit_storm.tscn`, `shaders/cockpit/snow_storm.gdshader`,
`scripts/cutscene/{cockpit_snow,storm_beats,cockpit_storm_driver}.gd`,
`tests/test_cutscene_cockpit_storm.gd` (13 tests), `tests/_probe_cockpit_storm_shot.gd`. Changed:
`HoloDisplay` (+`Kind.ROUTE`, `route_taps`, `route_confirm`), `CockpitHolo` (+`ROUTE`, `with_route`,
off by default so the fire shot is unchanged). The root reuses `cockpit.gd` as is.

- **Camera:** eye (0.45, 1.12, 1.4) looking at (0, 0.88, 0.2), fov 70, never touched by the driver.
  Probe frames sit close to the user's screenshots (seat legs lower left, Heat gauge above his head,
  strip on the right).
- **Route panel:** (-0.44, 1.32, 0.38), 0.2 x 0.2 m, straight above Radar (first try at 1.37 m
  stretched his arm straight up). Faces his head like the rest, so from the shot it reads at an angle
  and mirrored, as in the user's drawing.
- **Strip:** he presses ButtonSlots 2, 0, 1 (the back half, behind the stick, so his fist clears it).
- **Buzz:** 1 mm / 0.08 deg calm, x3.5 at full storm (was x5), through CockpitShake's surge (no
  jolts). Head nod 0.35 deg at full storm only (was 0.5). Torso turns a quarter of his head's turn to the panel.
- **Light:** `StormFill` directional from the front, `HoloSpill` green omni at 0.2 (0.5 tinted him
  green), `Key`, fill and ambient all blended calm -> storm by the driver, white on lightning.
- **Snow:** three log-polar layers (90/54/30 cells round), one cruise speed (see the storm look
  revision below).
- Not yet played. The full suite's one failure (`test_ichi_parked_ship`, spawn facing/distance) is
  Ichi.tscn, changed outside this work.

## Revision 2026-10-15: storm look

Grilled with the user after their first look ("looks like he is speeding up and going into warp";
the vanishing point had drifted off to the right). Supersedes the screen and light bullets above
where they disagree. Arms, taps, panels, strip and camera unchanged.

- **Vanishing point directly behind him, fixed all shot.** The crosswind is gone. `StormBeats.ahead`
  = (0, 0, 1), his facing, so the point is straight back along seat -Z, level. Not behind his head
  from the camera's view (tried first, user: "directly behind pilot, not from the camera's
  perspective"); from the camera it lands just right of the headrest.
- **The ship never speeds up.** One cruise speed, `cruise_rate` 0.6 log-angle/s, 0-10 s (was 0.12 ->
  1.8). Flakes are short streaks all shot (`flake_width` 0.075 cells, `streak_length` 5 widths) and
  never stretch. The storm is heavier through more snow (density 0.22 -> 0.6), cloud bands and
  turbulence, never through speed.
- **Turbulence, not swirl.** The swirl round the vanishing point is gone. Gusts shove the flakes
  sideways (noise along the stream and in time, `turbulence` 1.1 cells at a full gust), so they
  swerve off their lines and straighten; the vanishing point never moves.
- **Calm into storm, colours from the descent shot.** 0-3 s the descent's calm: pale lavender sky
  (~0.85, 0.82, 0.9), light snow. 3-7 s a gradual darkening (no wall moment, user's pick) to the
  descent storm: slate-violet sky (0.36-0.6), dark violet cloud masses and grey-teal streaks
  streaming into the vanishing point. Flakes stay pale. Sampled from the user's two descent
  screenshots.
- **Cockpit darkens to about half.** Key, fill and ambient go from pale lavender to cool slate; the
  user asked for ~45% of calm, probes measure 50-60% on screen (the holos keep some of him lit).
  Lightning still lifts it all.
- Built and probe-checked (calm, ramp, full storm). Not yet played.

## Revision 2026-10-16: snow

Grilled with the user ("the snow is just going straight back ... all the flakes are uniform; I want
it to look like real snow, it flows in swirls and has little deviations"). Only the flakes change:
sky bands, cloud bands, lightning, the calm-to-storm colours, the cruise speed and the vanishing
point behind him stay as in the revision above. Seat, pilot, holos, camera untouched.

- **The hit is shown with near-field skimmers** (user's pick over turning the flight so the
  stagnation point is in frame, or real 3D particles behind an opaque screen). The point the ship
  flies at is behind the camera, so what we see is the stream along the sphere's sides and back.
- **Skimmers: hit, cling, slide, peel.** Big close flakes arrive near the frame edges, squash flat
  for a beat where they touch the glass, slide along the sphere on a curve (speeding up, stretching
  a little), then let go toward the vanishing point, shrinking away. Some break into 2-3 bits
  mid-slide. 3-6 on screen in the calm, a dozen plus in the full storm. Their size is fixed on the
  glass (they don't shrink with perspective until they peel).
- **Flake look: mixed cel flecks, no halo.** The lavender rim and the capsule shape are gone. Mostly
  tiny pure-white specks, some lumpy irregular clumps, a few bigger near tufts; hard edges. Far
  flakes smaller and fading toward the sky colour, near ones bright white. Each smears along its
  own path; only near fast ones get a visible tail. If white washes out on the calm lavender, a thin
  one-sided darker shade (never a ring).
- **Flow: layered wind.** The pull to the vanishing point is unchanged, but through (1) curving
  S-lanes, a flow field fixed on the sphere, so no flake travels straight; (2) small (fist-sized)
  eddies drifting down the stream that curl flakes part-way round, lazy and few in the calm,
  tighter and more frequent in the storm, peaking with gusts; (3) per-flake flutter and tumble, each
  its own rate and amount.
- **Patchy density.** Thick clumps and thin gaps drifting with the flow; gusts push thicker patches
  through. The storm ramp still sets the overall amount.
- **Head timing (same day, user nitpick).** He reacted to the route panel too fast: the look now
  starts 0.3 s after the pop (was 0.05) and turns over 0.45 s (was 0.3), done before the first tap.
  New: a small glance down and to his left (12 deg down, 9 deg left, `strip_look`) while the left
  hand presses the strip, not all the way to the buttons; in 0.1 s after the hand leaves, out 0.4 s
  after the last press.
