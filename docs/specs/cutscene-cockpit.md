# Cutscene shot 2: cockpit

2026-10-14. Grilled with the user, then built the same day. The second shot of the opening
cutscene: pilot9 sitting in the ship's cockpit. The cockpit is Gundam-style: the whole cockpit is
one screen, a sphere around the pilot, and the only thing inside it is a floating seat. The seat
is modelled from the user's black-and-white line sketch (a Gundam seat with arm consoles, a tall
headrest, boxy pods behind it and an instrument block in front of the knees). The anime still
supplied with it gives the colours.

**This is a blockout.** The seat is boxes and cylinders, the pose is bone rotations, and the camera
does not move. What shows on the screen sphere (re-entry fire) and any motion come later.

## Decisions

- **Framing: copy the sketch.** Same camera direction (high, from the pilot's front-left, looking
  down about 35 deg), same distance (the whole seat in frame), static. No push-in. It is not a
  close-up.
- **Pose: upright, both hands on grips.** Back and head against the backrest, thighs about level,
  shins down and forward to a footrest, forearms along the arm consoles, each fist on a grip. The
  sketch has a stick on one console only; a matching grip is added on the other. Looks straight
  ahead.
- **What survives from the sketch: everything attached to the seat.** Seat, backrest and
  headrest, the two side pods behind, both arm consoles with grips, the leg/footrest panel and the
  instrument block in front of the knees (round gauge + two dials, mounted on the seat so it floats
  with it). Dropped: the flat screen, the wall consoles, the vent, the floor. The sphere replaces
  them.
- **Screen sphere: about 4 m radius**, centred a little above the seat. Its inside is unlit and dark
  blue-black, with faint latitude/longitude panel seams glowing soft cyan. It is a placeholder "live
  feed"; the fire becomes this surface's texture later. No cel shading and no ink on it.
- **Truly floating.** No arm or mount. A chunky base block under the seat so it is not hollow from
  above.
- **Light:** neutral-white key from upper front-left (the camera side), cyan ambient standing in
  for the screen's glow, so shadows lean teal. Swapping the ambient to orange later relights the
  shot for the fire.
- **Scene:** its own scene, `scenes/cockpit.tscn`, root node `Cockpit`. Watched with F6. Plays on
  load, **5 s** static hold, emits `finished`, R restarts, Esc quits. Not chained to shot 1 yet.
  It has an AnimationPlayer `shot` animation, empty for now, ready for motion later.
- **Pilot:** the regular `assets/pilot9.glb`, a plain instance (no controller, state machine, VFX or
  camera rig). Pilot cel material through ApplyStylized like trial.tscn. Rim light kept. **No
  staff.**
- **Seat colours: the anime still's palette** in the cel material with ink. Pale mint-grey shell
  (seat body, consoles, pods, base), tan-brown cushions, red-orange trim, near-black grips, a dark
  instrument block with cyan-glowing gauge faces.

## Build plan

- `scenes/cockpit.tscn`: `Cockpit` (script) / WorldEnvironment / Key (DirectionalLight3D) /
  ScreenSphere / Seat (generated) / Seat/Pilot (pilot9.glb) with a SeatedPose modifier on its
  skeleton / Camera3D / ApplyCelPilot / AnimationPlayer.
- `scripts/cutscene/cockpit.gd`: play on ready, `finished`, R / Esc, rim light on the pilot.
- `scripts/cutscene/cockpit_seat.gd` (`@tool`): builds the seat parts from a table at load. Every
  part carries a second, welded-normal surface with the outline material, so box corners ink
  without gaps. It also holds the pose targets (hip point, the two wrist targets on the grips, the
  two foot targets on the footrest) in seat space, exported, so the pose follows the seat.
- `scripts/cutscene/seated_pose.gd` (`@tool` SkeletonModifier3D): solves the seated pose from the
  seat's targets every skeleton update, starting from rest. It sets the hips at the hip point with
  the backrest's recline, does two-bone IK for each leg (knee pole forward) and each arm (elbow pole
  out and down), keeps the feet flat, and pitches the neck to bring the face level. A pure `solve()`
  so tests can check it without rendering.
- `shaders/cockpit/screen_sphere.gdshader` (removed in the cleanup below).
- `tests/test_cutscene_cockpit.gd`: covers 5 s timing and autoplay, `finished`, the camera not
  changing over the shot, the seat and the pilot's head in frame, wrists on their grip targets and
  feet on the footrest, hips on the seat, and everything inside the sphere.
- `tests/_probe_cockpit_shot.gd`: a windowed screenshot to compare against the sketch.

## Built

2026-10-14, files as planned. Numbers, all editable:

- Seat space: origin under the pan, +Z his facing, +X his left. Pan cushion top 0.48 m, backrest
  recline 12 deg (`recline_degrees` on the seat, drives the backrest and his torso together),
  console tops 0.67 m at x = +/-0.37, grips at (+/-0.4, 0.75, 0.4), centred on the control boxes (moved 2026-10-14), footrest about 0.13 m.
- Pose targets on `Seat` (hip / wrists / feet, seat space). The SeatedPose modifier re-solves from
  rest every update, so moving a target or the seat in the editor moves him. Poles: knees
  (0, 1, 1), elbows (+/-1, -1, -0.4).
- Sphere r = 4 m at (0, 0.9, 0), 15 deg panels, seams `line_strength` 0.22 / `glow_strength` 0.05.
  First pass at 0.55 / 0.12 read as a bright grid, not "faint".
- Key light white from (0.6, 0.8, 0.5) (front-left, high), ambient cyan (0.35, 0.78, 0.9) x 0.18.
  At 0.35 the mint shell washed out to white-cyan. Shell was mint (0.5, 0.64, 0.58); 2026-10-14 changed to dark grey-blue
  (0.28, 0.33, 0.41), dark parts (0.18, 0.22, 0.28).
- Camera fixed at azimuth 75 deg from his facing toward his left, 35 deg down, 2.75 m from
  (0, 0.8, 0), fov 40. 2026-10-14: replaced by the user's editor screenshot - 48 deg toward his left of
  straight-on, 40 deg down, 1.65 m from (0, 0.62, 0.05), fov 70 (the editor's), matched by probe shots. In the sketch the instrument block is at the left of frame, the seat pan in
  the middle and the pods at the right; this matches that.
- Gotcha: a .tscn `Transform3D(...)` lists the basis by ROWS, not by axis vectors. Writing axis
  columns turned the first camera sideways.
- Tests: `tests/test_cutscene_cockpit.gd` (13). `tests/_probe_cockpit_shot.gd` saves the shot plus
  a side and a front debug view for judging the pose.

## Cleanup: glass screen + detailed seat

2026-10-14, grilled with the user after looking at the first build, then built. The user wanted the
sphere gone as a hologram ("a clear screen, like glass") and the seat cleaned up and detailed so it
does not look AI-made, from the sketch.

### Decisions

- **Screen = a Blender-style UV-sphere wireframe** (from the user's screenshot): light-grey thin lines,
  32 segments x 16 rings with the pole fans, back half visible, no faces, no glow. Radius stays 4 m and
  the camera stays **inside** it, so it is the backdrop. The seam/grid shader is gone.
- **Background flat dark grey** (a little darker than Blender's #3d3d3d), **ambient neutral** grey
  instead of cyan. Key light unchanged.
- **Seat stays procedural in Godot** (not a Blender GLB): a bevelled-mesh builder replaces the plain
  primitives.
- **Rebuilt part by part to the sketch's silhouette**: three distinct back pods, a puffy two-pad
  backrest in a shell tub with wings, a separate headrest on a neck with two face screws, a deep pan
  cushion with a rolled front, long consoles with handset-shaped end caps, a slotted button strip by
  one stick only, a chunky tilted instrument block (cross-hatched gauge, two dials, keys) on a pedestal,
  a stepped plinth and leg step with round buttons. Core dimensions (pan, consoles, grips) kept.
- **Detail = construction + hardware as geometry, sketch density, asymmetric where the sketch is**:
  varied bevels, darker-mint seams and plates, piped cushions, screws, grille slots, ports, buttons.
  No wear, decals or cables.
- **Palette kept, red used sparingly**: mint shell, one darker mint for seams/plates, tan cushions with
  dark-tan piping, red only on the headrest strips, one pod band and the grip buttons (plus one leg
  button), near-black hardware, cyan gauges.
- **Camera untouched; pose targets only as the new seat needs.**

### Built

- `scripts/cutscene/seat_mesh.gd` (`SeatMesh`): `rounded_box(size, radius, bevel, opts)` (cube grid
  projected onto a rounded box, bevel samples spaced by tan so the corner is even in angle; options
  `taper` / `shear` / `puff` / `subdiv` blend in bottom to top, normals carried through by the
  Jacobian's inverse transpose), `rounded_cylinder` / `lathe`, `facing(dir)`. Smooth analytic normals,
  so every edge catches a cel highlight; box-projected UVs for the painted patches.
- `scripts/cutscene/cockpit_seat.gd`: the part table, split into base / pan / back / pods / consoles /
  instruments. Structural parts are inked; hardware (screws, slots, seams, plates, buttons) is not,
  because the outline is a fixed pixel width and would swallow a 1 cm part.
- `scripts/cutscene/wire_sphere.gd` (`WireSphere`, `@tool`): `radius`, `segments`, `rings`,
  `line_color` (0.78 grey), PRIMITIVE_LINES, unshaded. Background `Color(0.17, 0.17, 0.17)`, ambient
  white x 0.18.
- Probe fixes: the headrest's red side cheeks read as big red slabs, now thin strips down its front
  edges; the headrest dropped 5 cm onto a shorter neck (it floated above his head); the red pod band
  moved from the centre pod (it poked out as a stray red stub) to the near pod.
- Pose targets did not need to move: wrists, feet and hips land on the new grips, footrest and
  cushion as before.
- Tests: the sphere check reads `WireSphere.radius`; new `test_screen_is_a_grey_wireframe`.

## Re-entry fire on the screen

2026-10-14, grilled with the user, then built. The pilot and the ship are entering Earth's atmosphere; the
screen sphere shows the plasma round the nose. "Some 2D effect magic", the camera never moves.

### Decisions

- **The fire lives on the screen**: the outside feed, painted on the inside of the sphere by a 2D noise
  shader in the sphere's own coordinates. No particles, no volumes.
- **The wireframe stays, dimmed** to faint dark seams in front of the fire, so it still reads as a glass display.
- **Airflow over a ball**: a hot point just off screen left (his front-right, near the nose); flames fan out
  from it along the great circles, curve round the sphere and meet again at its antipode just off screen
  right (his back-left). Screen left-to-right is nose-to-tail.
- **Anime cel fire**: hard bands, white-hot / orange / red / dark red, tongues stretched along the flow,
  flickering edges. No soft gradients, no ink.
- **Wall to wall with gaps**: thickest and hottest on the left, breaking into dark red-black gaps to the right.
- **Steady and fast**: full strength from frame 0, roughly a tongue every half second, the whole 5 s.
- **Relight**: orange ambient plus a warm fill from the hot side that flickers with the fire. Key unchanged.

### Built

- `shaders/cockpit/reentry_fire.gdshader`: unshaded, cull_front. Per fragment: angle from the source
  (`theta`, along the flow) and azimuth round it (`phi`). Noise is sampled at
  `(cos phi, sin phi) * across_scale, theta * along_scale - TIME * flow_speed * along_scale`, so it is
  seamless round the source and scrolls away from it. A slow domain warp makes tongues lick, a small fast layer
  flickers the edges, heat cools by `cooling` over PI. Bands at `thresholds` (0.80 / 0.62 / 0.45 / 0.30).
  First pass at across 3.2 / along 1.6 read as lava camouflage blobs; across 9 / along 0.9 reads as streaks.
- `scripts/cutscene/reentry_fire.gd` (`ReentryFire`, `@tool`): builds the inward sphere (r 4.05, just
  outside the 4 m wire), `source_direction` (-0.7, -0.1, 0.71) sphere space, `flow_speed` 0.8 rad/s,
  `flicker_amount` 0.08, `fill_light`, `fill_energy` 0.9. One `flicker_at(t)` (three sines) feeds the shader's
  `flicker` and the fill's energy. The screen gets half of it: every band edge moves with it, so full strength
  pumped the whole field.
- `scenes/cockpit.tscn`: `ScreenFire` (same centre as `ScreenSphere`), `FireFill` directional light
  (1, 0.5, 0.18), aimed from the hot point at the sphere centre on ready. Wire `line_color` (0.07, 0.02, 0.015).
  Ambient (1, 0.45, 0.15) x 0.3.
- The source angle: about 65 deg left of the camera's view puts its antipode just off the right edge
  (worked out from the camera transform), so the true antipodal flow fits the shot.
- Tests: `test_screen_is_a_grey_wireframe` -> `test_screen_is_a_dim_wireframe`; new
  `test_fire_flows_left_to_right_round_the_sphere`, `test_fire_lights_the_cockpit`.

### Turned to the seat

2026-10-14, after the first look: "rotate it so it's lined up with pilot and his seat... the fire needs to be
going up and to the right." `source_direction` (-0.7, -0.1, 0.71) -> **(-0.3, -0.3, 1.0)**: the hot point is now
ahead of the seat (17 deg to his right, 17 deg low), off screen lower left; its antipode is just past the top
right corner. The streaks run diagonally up-right, parallel to the seat's nose-to-tail axis in the shot's
perspective. Test now checks lower-left source, upper-right sink, upward flow and the source ahead of the seat.

## Atmosphere pass: shake, holograms, life

2026-10-14, grilled with the user, then built. "Make it FEEL like he's entering the atmosphere": the seat
shakes, he gets knocked about on it, hologram panels float in front of him, and the cockpit flickers with life.

### Decisions

- **The seat shakes; the camera barely trembles** (a tenth of the seat's motion). The screen sphere and fire
  stay still: they are the outside view, not hardware.
- **Buzz + jolts.** A constant fine buzz (about 5 mm / 0.4 deg, 15-20 Hz, noisy) all shot, plus three jolts at
  **1.2 / 2.9 / 4.1 s**, medium / small / big: a kick of about 3 / 2 / 5 cm and 1.5 / 1 / 3 deg that settles in
  about 0.3 s. The jolt times are method keys on the `shot` animation, so they can be dragged in the editor.
  Each jolt flares the fire and pulses the fill light.
- **Pilot: hands and feet pinned** (the IK targets ride the seat), **spine and head on springs**: a small
  extra wobble in the buzz; on a jolt thrown opposite the kick, up to about 1.5x it at the head, then back
  with an overshoot.
- **Hologram panels: an arc of four** round the front of the seat, chest to eye height, 0.5-0.8 m out,
  angled at him. The front-left one (camera side) is the biggest and faces the camera; the others read as
  glowing slivers.
- **Look: the user's green reference.** Translucent dark-green fill, bright mint outline and soft glow,
  chamfered corners, thin-line UI (round gauges, segmented arcs, small bars, rows of pseudo-text, grid ticks),
  mixed sizes, a wide curved console strip low down. Clean, no heavy scanlines.
- **Red only on the jolts**: one or two warning elements (WARNING block, heat arc) flash red on each jolt and
  fade back to green. Every jolt also glitches the panels (a sideways tear and flicker for a frame or two).
- **Live re-entry readouts**: the front-left panel has an attitude horizon that tilts with the shake and kicks
  on the jolts, plus altitude and speed counting down; a heat panel with a segmented arc that creeps up and
  spikes on jolts; a radar with a sweep over the Florida landmass (shot 1's target); the low curved strip
  scrolls log rows and jitters bar graphs. No real words except WARNING.
- **Panels ride the seat on a small spring lag**: they trail the seat by a few cm on a jolt, then catch up.
- **Life**: the seat's gauges, dials and console buttons blink and pulse, with a red lamp that flashes on the
  jolts; a spark burst from a console seam on the big jolt; a second, softer orange fire light that drifts
  across him and the seat.
- **No sound** (the project has none yet). Shot stays 5 s, panels on from frame 0. The shake is
  deterministic (a pure function of the shot time), so R replays it exactly and tests can sample it.

### Built

2026-10-14. Numbers, all editable:

- `scripts/cutscene/cockpit_shake.gd` (`CockpitShake`): the pure motion. Buzz = three sines per axis at
  15.3 / 17.9 / 19.7 Hz. A jolt is a damped sine normalised to peak 1.0 (`kick_shape`): peaks in ~40 ms,
  swings back ~20 %, gone by `settle` (0.3 s). Seat rotates round (0, 0.5, 0). Each jolt's direction and tilt
  axis come from a table by index (mostly up, each to a different side). The body uses the same shape over
  2x settle, the panels over 1.4x (so they trail). `flash` = exp(-s/0.4), `glitch` = first 0.07 s, `flare` =
  strength x exp(-s/0.25).
- `scripts/cutscene/cockpit_reentry.gd` (`CockpitReentry`, node `Reentry`): reads the `jolt(strength)` method
  keys off the `shot` track (1.2 s 0.6, 2.9 s 0.4, 4.1 s 1.0) and applies everything each frame from the shot
  time (`apply(t)`). Tunables are exports (buzz mm/deg, kick cm/deg, settle, camera share 0.1, body throw 1.5).
  Also owns the lamps (`ButtonSlots0-6` twinkle green, handset windows pulse, gauge and dials pulse,
  `GripButtonL` flashes red on jolts; `LegButtonL2` was a second alarm lamp until 2026-10-26), the `FireDrift` omni (drifts round (-0.5, 0.9, 1.3),
  flickers, pumps on jolts) and the spark burst (70 streaks from the camera-side console seam, on the
  strongest jolt only).
- `SeatedPose` gained `body_sway` (spread Spine 0.4 / Chest 0.3 / UpperChest 0.3, applied before the arm IK so
  the hands stay on the grips) and `head_sway` (on the Head after the neck's level-out). The throw uses an
  effective spine lever of 0.3 m: at the torso's 0.55 m the head only moved ~0.7x the kick.
- `ReentryFire.flare`: adds 0.35 x flare to the screen's flicker and (1 + 0.8 x flare) to the fill.
- Holograms: `scripts/cutscene/cockpit_holo.gd` (`CockpitHolo`, node `Holo`, builds the four from a table),
  `holo_panel.gd` (`HoloPanel`: SubViewport + quad or bent strip, 1200 px/m), `holo_display.gd`
  (`HoloDisplay`: the 2D drawing per kind), `shaders/cockpit/holo_panel.gdshader` (translucent, glitch tear).
  Panels (seat space): Horizon 0.36x0.24 at (0.44, 1.0, 0.44) facing the camera; Heat 0.2 at (0.1, 1.3, 0.56);
  Radar 0.22 at (-0.38, 1.12, 0.5); Log 0.6x0.12 bent 50 deg at (0, 0.92, 0.6).
- Probe fixes: first pass the fill (alpha 0.45) washed into the fire and the three head-facing panels showed
  the camera mirrored edges. Fill now dark green at 0.72, lines thicker, and those panels turn
  `camera_turn` 0.45 of the way from his head toward the camera. Sparks doubled in size and count to read.
  Altitude digits shrunk off the descent bar.
- Tests: `test_camera_does_not_move` -> `test_camera_only_trembles`; 11 new (jolt track, buzz vs kick and
  settle, determinism, hands/feet pinned mid-jolt, head thrown and overshooting, panels trailing, panels in
  frame and clear of his face, readouts and red/glitch timing, flare/lamp/sparks, drifting light). Probe
  (`tests/_probe_cockpit_shot.gd`) now saves frames at 0.6 s, 1.24 s and the big jolt with sparks.

### 2026-10-14: panels face him

- Every panel (Horizon included) now faces his head; `camera_point` / `camera_turn` are gone. From the shot
  camera they read mirrored or edge-on, which is intended: they're his displays, not the player's.
  `test_panels_read_the_descent` checks each panel's face is within 0.97 of his Head bone.

## Ending: warning swipe and push

2026-10-14, grilled with the user after "looks great". On the big (third) jolt a red warning panel
pops up just above the Horizon panel; he backhands it away with his left hand, puts the hand back on
the stick and pushes both sticks forward.

### Decisions

- **Shot 5 s -> 7 s.** The jolts stay at 1.2 / 2.9 / 4.1 s.
- **4.1 s, with the big jolt: the WARNING panel** snaps open from a horizontal line in about 0.12 s with
  the glitch tear and a flash (the other panels' red flash fires too). Placed from the user's drawing:
  in front of his left chest, just above the Horizon panel. About 0.3 x 0.2 m, the same chamfered
  holo family but **red**: a big hazard triangle with "!" blinking about 3 times a second, "WARNING",
  a hazard-stripe strip along the bottom, rows of pseudo-text.
- **It faces his head like the others**, so from the shot it reads mirrored. Accepted.
- **He glances at it**: the head snaps toward it (about 0.15 s), a slight look down; the torso turns
  about 5 deg with the arm. Eyes back front as the hand returns. The jolt springs stay on top.
- **Left hand, backhand flick outward to his left**: about 4.4 s the hand leaves the stick, about
  4.6-5.1 s the flick. The panel slides off sideways toward the camera side, stretching, tearing and
  fading, contact to gone about 0.25 s. The rig has no finger bones, so it is the fist turned palm-out.
  His right hand stays on its grip.
- **About 5.1-5.6 s the hand goes back onto the left grip**; head back to front.
- **About 5.7 s, push**: both grips tilt forward about 20 deg on their base pivots over about 0.4 s
  (ease in) and hold; the wrists ride with them; he leans about 6 deg into it.
- **The ship answers about 0.2 s later**: fire flow about 1.5x and hotter to the end, seat buzz up
  about 30 %, the readouts jump (speed climbs, the descent bar drops faster). Camera unchanged.
- **Hold to 7 s**, then `finished`.
- **Editing**: two draggable method keys on `shot`, `warning()` at 4.1 and `push()` at about 5.7;
  every timing in between is an export. All of it is a pure function of the shot time (R replays it,
  tests sample it).

### Built

2026-10-14. Numbers, all editable:

- `scripts/cutscene/cockpit_beats.gd` (`CockpitBeats`): the ending as pure functions of shot time, beside
  CockpitShake. `warning_open` / `warning_gone` / `warning_offset`, `left_wrist(t)` (rest -> contact at the
  panel's inner edge, 4 cm in front of its face -> 0.4 m past its centre outward, ease-out -> 3 cm hang ->
  back with a 5 cm arc), `glance` / `head_look` (yaw and pitch from his head to the panel), `body` (5 deg
  turn while looking, 6 deg lean on the push), `push` / `stick_angle`. Outward = seat +X flattened into the
  panel's plane.
- Timings (exports on `Reentry`, "Ending" group): react 0.3, reach 0.22, flick 0.25, hang 0.15, hand back
  0.45, push 0.4, stick 20 deg, lean 6 deg, turn 5 deg, answer delay 0.2, flow 1.5x, heat 0.45. With the
  keys at 4.1 / 5.7: hand off 4.4, contact 4.62, panel gone 4.87, hand back on the grip 5.47, glance back by
  5.37, sticks forward 5.7-6.1, ship answers 5.9-6.25.
- `shot` animation: length 7.0, a second method track on `Reentry` with `warning()` at 4.1 and `push()` at
  5.7 (empty methods; read on ready like the jolts).
- WARNING panel: `CockpitHolo.WARNING` at seat (0.3, 1.22, 0.37), 0.3 x 0.2 m, worked out by casting the
  user's drawn box through the shot camera at about 0.95 m depth. Built with the others but kept out of
  `panels` and hidden until its key. `HoloDisplay.Kind.WARNING`: red glass and line, blinking triangle
  (3 Hz), WARNING, pseudo-text, marching hazard stripes. `HoloPanel` gained `open_amount` (glass y scale),
  `fade` (shader opacity), `stretch` (x scale, 1 -> 1.6 on the way out) and `extra_glitch` (tears while it
  opens and leaves).
- Sticks: `Grip`, `GripHead`, `GripButton`, `GripTrigger` on each side turn round X at the boot
  (grip + (0, -0.075, -0.015)). `SeatedPose` gained `left_wrist_shift` / `right_wrist_shift` (seat-space
  transforms on the wrist targets): the push's stick turn, times the swipe's offset on the left.
- Answer: `CockpitShake.surge(t)` (from push + 0.2, eased over 0.35 s, held) scales the buzz by 1.3 and
  drives `ReentryFire.speed_scale` and extra `flare`. The fire's scroll is now an integrated `flow_phase`
  uniform, so the speed change does not jump the flames. `HoloDisplay.speed_at` / `altitude_at` take the
  surge time: speed climbs 0.6/s, altitude drops an extra 2800/s, the descent bar drops.
- Departure: the glance looks slightly **up**, not down. The panel is at about head height (1.22 m vs his
  head at 1.15 m), so the head aims at it truthfully.
- Tests: 5 s -> 7 s, finished at 7; 6 new (keys off the track, pop/flick/gone, placed above Horizon and
  facing him, left swipe and return with the right hand still, glance, push + answer). Probe adds
  `end_warning / end_reach / end_flick / end_follow / end_back / end_push / end_front_flick`.

### Retime: pauses before the swipe and the push

2026-10-14, grilled after "the swipe looks really good but the timing is off": the warning popped and he
swiped it almost at once, and he pushed the sticks the instant his hand was back.

- **Pause before the swipe: react 0.3 -> 1.0 s.** The glance still snaps to the panel straight away; he
  holds the look for about three blinks, then the hand leaves the stick. Hand off 5.1, contact 5.32, panel
  gone 5.57, glance back by 6.07, hand on the grip 6.17.
- **Pause before the push: `push()` key 5.7 -> 6.67** (0.5 s after the hand is back). Sticks forward
  6.67-7.07, ship answers 6.87-7.22.
- **Shot 7 s -> 8 s**, keeping the same 1.3 s hold after the push; `finished` at 8.
- Both pauses are still holds: no fidget, the shake and fire carry them. Jolts unchanged at 1.2 / 2.9 / 4.1;
  the swipe motion itself unchanged.
- Tests and probe times shifted; two new checks that the hand and panel are untouched mid-pause (5.05 s).

### Startle "!"

2026-10-15, grilled: a funny beat to show the warning spooked him.

- **Look:** a flat, white, chunky "!" with a thick black ink outline (anime / Metal Gear alert), square to the
  camera. White, not yellow (yellow is lost in the orange fire) and not red (it would fight the WARNING).
- **Timing:** appears with the head snap (warning + `glance_delay`, 4.18 s), pops in over 0.1 s overshooting
  to 1.3x with a 4 cm hop, holds, then **hard cut** 0.55 s after appearing (4.73 s), well before the hand
  leaves the stick at 5.1.
- **Place:** off the Head bone in seat space, up and out to **his right** (away from the warning), about
  0.2 m tall, top leaning 12 deg away from his head on screen. Follows his head and the seat shake.
- **No body flinch** (the big jolt already throws him), no sound (the cutscenes have none yet).

Built: `CockpitBeats.startle_visible` / `startle_scale` / `startle_bounce`; `CockpitReentry` builds a
`Startle` Label3D on the seat (fallback font emboldened 0.2 - skinnier on 2026-10-15, was 1.2 - size 96, outline 20, no depth test) and places it
in `apply()`. `SeatedPose.head_position` (seat space, set each skeleton update) is the anchor; before the
first update it falls back to `beats.head_point`. Exports in the "Ending" group: `startle_pop` 0.1,
`startle_hold` 0.55, `startle_overshoot` 1.3, `startle_height` 0.2, `startle_offset` (-0.3, 0.16, 0.05),
`startle_bounce` 0.04, `startle_tilt_degrees` 12. Placement from probe shots (`startle_pop.png` 4.22 s,
`startle_hold.png` 4.5 s); test `test_startle_mark_pops_by_his_head`.

2026-10-15: the WARNING panel's word ran its G off the panel's edge (13 _u at h * 0.92 is wider than the
room left). `HoloDisplay._fit_size` now shrinks it to fit `w - x - 10 _u`.

## Re-entry read: wake, space, dropouts, the push

2026-10-16, grilled with the user: "does our cockpit fire scene look good? ... bring it up a notch." The fire
filled the whole sphere at nearly the same heat (cooling 0.4 over PI), so it read as sitting in a fireball,
not falling into an atmosphere; nothing said Earth; nothing said screen. And the push lean (6 deg, with the
sticks) was too small to see from the high camera.

### Decisions

- **Front-heavy with a wake.** A white-hot core with a ragged shock-front edge at the nose; streaks fan out
  from it and thin out; the rear third of the sphere (the shot's upper right) breaks into torn gaps that open
  and close as the streaks pass. Flow speed and jolt flares unchanged.
- **The hot point just inside the lower-left corner**, about 12 % in from both edges, so the core is in
  frame: blinding fire lower left, him in the middle, the opening to space upper right.
- **Through the gaps: space and Earth's limb.** Black, a few hard white stars (still: the ship's attitude
  does not change), and the thin cel-banded atmosphere edge in shot 1's blue-white halo palette, crossing
  the wake. Earth below the limb is dark blue with pale cloud patches. Glimpses only, never a clean window.
- **Panel dropouts on the jolts.** A panel = one box of the 32 x 16 wire sphere. On each jolt 3-6 panels in
  frame glitch for 2-4 frames each: black, flat cyan (no signal), or their slice of the picture shifted out
  of place; hard cut back. Clean between jolts.
- **The push: the fire swallows the wake.** When the ship answers the push, the core spreads out of the
  corner, the streaks thicken and the gaps to space close over about 0.5 s; a dropout burst (8 panels) on
  the push itself. The shot ends in solid fire.
- **A steady pale-blue rim from the wake**: a weak directional light from the upper right, one hard cel band
  on his back edges and the seat. Fades out with the gaps on the push. The warm fill from the nose stays.
- **The push lean, three beats**: wind-up 0.3 s before the key, leaning to 18 deg with the head tucked
  about 8 deg; the sticks snap forward over 0.25 s (was 0.4) and the lean goes to 22 deg; when the ship
  answers, G pushes him back to 12 deg over 0.3 s, held to the end. The `push()` key stays at 6.67; the
  wind-up spends 0.3 s of the 0.5 s pause after the swipe. Nothing else moves.

### Built

2026-10-16. Numbers, all editable:

- `shaders/cockpit/reentry_fire.gdshader`: the picture is now `feed(n)`. Core: white inside `core_radius`
  0.2 rad, edge ragged by 35 % (noise round the source). Cooling goes with the angle squared (`cooling` 1.0
  at PI) plus `front_heat` 0.12 fading by 0.9 rad, so the front stays hot and the tail drops away. Wake: from
  `wake_start` 1.7 to `wake_full` 2.2 rad off the source, the coldest gaps (`heat < 0.30 - 0.12 - 0.25 *
  (1 - wake)`) show `outside(n)`; other gaps keep the dark gap colour. Outside: Earth centre `earth_dir`
  (0, -1, 0), limb at `limb_angle` 1.4 rad, bands outward 0.012 / 0.022 / 0.035 rad (limb white, halo
  (0.45, 0.85, 1.0) as shot 1, deep blue), Earth dark blue with pale fbm clouds, stars in 70-per-radius cells
  at 1.2 %. `swallow` 0..1: core x1.5, +0.35 heat ramping in from 1.0 rad to the wake (the front does not
  wash out), wake mask off.
- Dropouts: `drops[8]` (segment, ring, kind, seconds), `drop_count`, `drop_age`. The fragment works out its
  WireSphere panel (longitude round +Y from +X, rings from the top pole); kind 0 black, 1 `no_signal`
  (0.25, 0.85, 0.95), 2 the feed slid 0.6 panel sideways and 0.35 down.
- `ReentryFire`: `source_direction` (-0.524, -0.646, 0.556) = the shot camera's ray through NDC (-0.76,
  -0.76). `swallow` (setter pushes it to the shader and the rim at once), `rim_light` / `rim_energy` 0.9
  (x (1 - swallow), hidden at 1), `set_drops()`, `GRID_SEGMENTS` / `GRID_RINGS` 32 / 16, `MAX_DROPS` 8.
- `CockpitShake.swallow(t)`: from `surge_time` (push + 0.2) eased over `swallow_ramp` 0.5 s, held.
- `CockpitReentry`: "Dropouts" exports (jolts 3-6 panels for 2-4 frames, push 8 for 2-5, NDC margin 0.85,
  `seat_ndc_x` (-0.5, 0.55) skipped because the seat hides them). `drop_events` built on ready from the jolt
  and push keys, picked from panel centres in frame, seeded per event (R replays the same panels).
  "Ending": `push_duration` 0.4 -> 0.25; `lean_degrees` replaced by `windup` 0.3 / `windup_lean_degrees` 18
  / `push_lean_degrees` 22 / `pushback` 0.3 / `pushback_lean_degrees` 12 / `head_tuck_degrees` 8.
- `CockpitBeats`: `answer_time`, `lean(t)` (wind-up smooth, drive with `push()`, ease-out press back),
  `wind_up(t)`; `head_look` adds the tuck.
- `scenes/cockpit.tscn`: `WakeRim` directional light (0.55, 0.8, 1.0), from behind him and a little above
  (0.05, 0.3, -0.95), no specular, no shadow; wired as `ScreenFire.rim_light`.
- Departure: the rim is subtle in the shot. The camera sees his front-left, so a grazing light from behind
  only catches the far edges; 2.0 energy lit the tops white and was rejected in an A/B.
- Tests: `test_fire_flows_left_to_right_round_the_sphere` hot point "ahead" 0.8 -> 0.4 (it is ahead and low
  now); new `test_hot_core_just_inside_the_lower_left_corner`, `test_fire_swallows_the_wake_on_the_push`,
  `test_jolts_drop_panels_in_frame`, `test_push_lean_winds_up_drives_and_presses_back`. Probe adds
  `drop_jolt1 / drop_push / lean_windup / lean_drive / swallow_half / swallow_full / end_side_lean`.

### Revision: no Earth, fire from ahead

2026-10-16, after the first look: "since he's flying at the planet, I don't think you could see it from this
angle. Remove it. Just space in the background ... I don't like the white in the bottom, it makes it look
like the flame is not coming from in front of pilot. Move the middle of the fire back to in front of pilot."

- **Earth's limb removed**: the wake shows black space and stars only. The `earth_*`, `limb_*`, `band_widths`,
  `halo`, `deep_blue` uniforms are gone.
- **The hot point is back at (-0.3, -0.3, 1.0)** (the 2026-10-14 "Turned to the seat" direction): ahead of the
  seat, off screen left. No white core in frame; the streaks run up-right along the seat and the wake opens
  wide on the upper right and right. Everything else (core, cooling, wake, swallow, dropouts, rim, lean)
  unchanged.
- Tests: `test_hot_core_just_inside_the_lower_left_corner` -> `test_hot_core_in_front_of_him_off_screen`;
  the "ahead of the seat" check back to 0.8.

## Guard flinch on the warning

2026-10-16, user: "have pilot's left arm guard himself when the warning panel pops up and the exclamation
mark pops up ... raise his arm up to his chest, shoulder area, like he's trying to block something."

### Decisions

- **With the head snap and the "!"** (warning + 0.08 s), the left hand leaves the stick and the forearm
  snaps up in front of his left chest/shoulder, between him and the WARNING: wrist about shoulder height,
  elbow down and out (the arm's usual pole), forearm up like a block. Snap in about 0.12 s, ease out, a
  small overshoot so it reads as a flinch.
- **He holds the guard through the stare**, and the backhand starts *from the guard* (guard -> panel's inner
  edge -> flick -> hang -> back to the stick). No trip back to the stick between the guard and the swipe.
  Every swipe timing unchanged (hand off the guard at 5.1, contact 5.32, gone 5.57, on the grip 6.17).
- Right hand stays on its grip. The glance, "!", panel and push are unchanged.

### Built

2026-10-16. `CockpitBeats.guard(t)`: from the head snap (warning + 0.08 = 4.18 s) ease-out to 1.1 over
`guard_in` 0.12 s, settling back to 1.0 over another 0.12 s, held. `left_wrist(t)` before the swipe is
rest -> `guard_point` by `guard(t)`; the reach then leaves from `guard_point`. Exports on `Reentry`
("Ending"): `guard_point` (0.26, 1.0, 0.2) seat space (shoulder height, 0.38 m in front of the shoulder, short
of the WARNING), `guard_in`, `guard_overshoot` 0.1. The arm's usual elbow pole puts the elbow down and out,
forearm up. A first try at (0.2, 1.12, 0.12) put the fist at his face (read as covering it) and was lowered.
Tests: new `test_left_arm_guards_when_the_warning_pops`; `test_left_hand_swipes_then_returns` samples rest at
4.1 and expects the guard (not the grip) at 5.05. Probe adds `guard_snap / guard_hold / guard_side /
guard_front / guard_reach`.
