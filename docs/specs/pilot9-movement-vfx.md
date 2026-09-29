# Spec: pilot9's movement effects

> **Status:** specced and built 2026-09-28. **Played 2026-09-28 - feels good.** Every number below is a starting
> dial, not a promise.
> **Scene:** `scenes/pilot9.tscn`. **Touches:** `scripts/pilot9.gd`, new `scripts/pilot9_vfx.gd`,
> `scripts/settings.gd`, `scripts/ui/tabs/tab_settings.gd`.

## The ask

"Some cheap 2d effect ... something to give the movement a little spice." The player named
rail sparks and a wind push under a jump, and asked for more ideas. Agreed in a grilling
session the same day; every decision below is one the player made.

## Style

**Classic game particles** - glowing sparks, soft dust, smooth 60 fps. Not ink. Offered were
ink everywhere (matching the dash streak), classic particles, or ink with glowing sparks; the
player picked classic. The dash's manga speed lines stay ink for now and are the one effect in
the other language - revisit after play.

**No image files.** Every particle's image is built in Godot: `GradientTexture2D` radial
gradients for puffs and rings, a stretched gradient quad for sparks and wind streaks. If the
dust ends up reading generic, a drawn puff is a one-texture swap.

## Scope

**In:** four effects - rail grind sparks, a ground-jump dust puff, a double-jump air burst,
landing dust.

**Out, second pass:** slide/skid dust, wall-run scuffs, bounce pad pop, mantle/vault hand puffs.
Also out: wall jumps, rail jumps, the bounce pad launch, the climb/vault jump. The four above
cover every way he leaves or hits a surface, so tuning is one family (burst at the contact,
fade out); the second pass reuses its parts.

## 1. Rail grind sparks

- **Stream:** orange-yellow sparks from his feet the whole ride, sprayed BACKWARD along the
  rail (against his travel), fanning up and out a little, falling under gravity. World space,
  so a fast ride leaves a trail.
- **Gear:** the shower is denser and longer (faster sprays) at the rail-sprint gear (20 m/s)
  than the grind gear (15 m/s). Driven off the live ride speed, so the gear ease is a ramp,
  not a switch.
- **Catch burst:** a heavy one-off shower on landing on a rail, then the stream.
- **Switch burst:** a smaller burst when a rail switch lands on its new rail. (Not both: the
  switch landing gets the switch burst, not the catch burst.)
- **Light:** a small flickering orange `OmniLight3D` at his feet while grinding, no shadows -
  on the cel shader it lands as a hard band on his shins and the rail.

## 2. Ground-jump dust

A low ring of soft grey-brown dust spreading flat along the floor from his feet, ~0.3 s. It
stays where he left. Only on a jump taken ON the floor - a coyote jump is already off the edge
and gets nothing (dust in mid-air reads as a bug).

## 3. Double-jump air burst

No dust - nothing mid-air to kick up. A pale white-blue ring expanding flat under his feet
plus a few short wind streaks shooting downward, ~0.4 s, left behind where he jumped. Bigger
than the ground puff. Different in kind so the two read apart at a glance: dust means he
pushed off the ground, wind means he pushed off nothing.

## 4. Landing dust

The ground-jump dust effect, driven off **the landing dip's speed curve** so the dust and the
camera agree:

- the dip's speed anchors, normalised: 0 below `landing_dip_min_speed` (5 m/s), 0.5 at a full
  jump's landing speed (10 m/s today), 1.0 at `max_fall_speed` (28 m/s);
- **0:** nothing - hops and step-downs stay clean;
- **up to 0.5:** two small puffs squirting out left and right of his facing, growing to full;
- **above 0.5:** the side puffs plus a ring of puffs spreading wider and lingering longer as
  it climbs to 1.0.
- **Landing into a slide:** the dust skews backward, trailing opposite his travel.
- **Rail landings:** sparks, not dust (the rail catch is already out of the dip's scope).
- **Bounce pad:** a pad launch on touchdown cancels the dust, same as the dip.

The dust does not depend on CAMERA MOTION - it has its own switch.

## Switch

**MOVEMENT EFFECTS - OFF / ON, default ON**, directly under CAMERA MOTION in the settings
screen. Off stops all four effects and the spark light. No per-effect toggles in the menu.

## Tuning

All dials are `@export`s on the pilot, in a "Movement Effects" group, the same place the dash
streak's live. The particle systems are built in code in `_ready()` (like the dash streak), so
a rebuild of `pilot9.tscn` cannot lose them.

## Shape of the code

- `scripts/pilot9_vfx.gd` (`Pilot9Vfx`, a `Node3D` child built by the pilot) owns every
  particle system, texture and the light. Its interface is five calls - `ground_jump(feet)`,
  `double_jump(feet)`, `land(feet, strength, facing, skew)`, `rail_contact(feet, backward,
  heavy)`, `grind(active, feet, backward, gear)` - and it reads its dials off the pilot.
- Bursts are one-shot `GPUParticles3D`s spawned `top_level` at the contact and freed on
  `finished`. The grind stream is one persistent emitter with `local_coords` off.
- `pilot9.gd` only decides WHEN: the floor jump, the double-jump branch, the landing hand-off
  (resolved at the end of the frame so a slide started on landing is visible), the rail catch
  and the switch landing, and a per-frame grind update.

## Can't be checked headlessly

How any of it looks. The tests fence the gating (switch off, coyote jump, rail landings, the
dust curve) and that the grind stream and light follow the ride. The look is the play session.

---

# Pass 2

> **Status:** grilled, specced and built 2026-09-28. **Played 2026-09-28 - feels good.** Every number is a
> starting dial (`vfx_*` exports). Same style (classic
> particles, no image files), same switch, same "the pilot says when, `Pilot9Vfx` says how".

## The ask

"Some sort of effect for sliding, which we could just re-use the sparks from rail grind for. I
want some sort of wind effects coming from behind pilot whenever he is going faster than sprint
speed ... so the player will know when they are going fast." Plus whatever else. Agreed in a
grilling session the same day.

## Scope

**In:** speed wind, slide sparks, wall-run scuffs, the wall-jump kick, mantle/vault hand taps,
sprint kicks.

**Out:** the bounce pad pop (offered, declined), a sprint-stop skid (fires on every stop -
noise), screen-edge anime speed lines (competes with the dash's), per-footstep wall puffs (needs
foot tracking for a small effect).

## 5. Speed lasers

Tells the player "fast" apart from "back at sprint". **Revised 2026-09-28 (grilled):** the
ankle ribbons are scrapped for white laser bolts shooting out of his back - the reference was a
plane with white streaks firing off behind it, not constant trails but bolts.

- **Trigger (unchanged):** horizontal speed (`velocity` flattened - a straight-down fall is the
  landing dip's job). On above **8.5 m/s**, off below **8.0** (`sprint_speed` is 7.5; the gap
  stops it flickering right at sprint). Eases in over ~0.15 s (the rate climbs).
- **Everywhere:** ground, air, rails, slides, the rail-jump carry.
- **The dash stops new bolts** - the afterimages own that half-second - but bolts already in
  flight finish; nothing vanishes. It picks back up after.
- **Shape: a flaring cone, empty in the middle.** Bolts fire from a ring (0.35 m radius) round
  his chest (1.2 m up), 0.35 m behind his back, at a random angle each, and fly backward flaring
  **15 deg** outward at the on-speed, **20 deg** at full. From the chase cam they point in at
  him from the screen edges like the reference, and pass BESIDE the camera, not into it.
- **The lens is kept clear:** a bolt whose flight would come within **0.6 m** of the camera
  (riding along at his velocity) is re-rolled to another angle; after 8 tries it is skipped.
- **"Backward" is his travel, not his facing** - wall runs, sideways drift and rail curves all
  stream opposite to where he is actually going.
- **Fired, a bolt stays in the world** - it does not swing with him; carve a turn and the live
  bolts stay on their old line.
- **A bolt:** spawns as a sliver, flies back at ~16 m/s, stretches to full length over the first
  40% of its ~0.25 s life, fades in fast and out over the back half. A spindle - pointed at both
  ends, widest and brightest in the middle - pure white, unshaded, added on so it glows. Each
  gets a random width, length, speed, life and brightness so they do not look stamped.
- **Scales with speed:** at 8.5 m/s a trickle of ~6 bolts a second, ~1.5 m long, fainter; at
  20 m/s (rail sprint, max slope slide) a barrage of ~25 a second, ~4 m long, brighter, the cone
  a little wider.
- **Opacity: 25%** (`vfx_laser_color` alpha 0.25, was 0.9) - retuned after play 2026-09-28;
  the brightest bolt at full speed peaks there, slower and dimmer ones sit below it.
- **Settings:** under the existing MOVEMENT EFFECTS row; no new row.
- **History - don't go back to any of these:** a tube of particle streaks round his body
  ("weird", in the camera's way); a ring of 5 trails at chest height (a rigid cage, seen end-on
  from the chase cam); a single chest trail (points at the lens, shrinks to a stub); two ankle
  ribbons (played fine, replaced by the lasers 2026-09-28 for the look). The lasers beat the
  end-on problem by flaring: nothing travels down the camera's line.

## 6. Slide sparks

- **The grind stream's builder, a second instance** of it, at his leading foot (ahead of his
  feet along his travel), sprayed backward.
- **Density and spray speed follow slide speed**, as grind follows gear: 3 m/s is the thin end,
  `slide_max_speed` (20) the heavy end. **Stops below 3 m/s** so the slow tail doesn't sputter.
- **Entry burst:** a light one-off shower when a slide starts.
- **Light:** the grind's flickering orange foot light, dimmer (its own light, `vfx_slide_light_scale`).
- **Every floor sparks**, slope auto-slides included (the fastest, so the heaviest).

## 7. Wall-run scuffs

- **Dust, not sparks** - sparks mean metal and friction now; shoes on a wall are a push.
- **A thin continuous dust trail** off the wall at his foot height, world-space, drifting out
  from the face - a faint line along the wall behind him.
- **Start puff** on the wall where he attaches.
- **Fades through the droop** - the last `wall_run_droop_time` thins it to nothing.

## 8. Wall-jump kick

- The ground-jump dust ring turned flat onto the wall face (spreading along it), plus a puff
  sprayed out along the wall normal. ~0.3 s, left on the wall.
- **At the last wall contact, foot height** - a coyote wall jump (up to 0.15 s after leaving)
  puts it on the wall where he was, not in the air where he is.
- **Same size every jump** - a shrinking puff would read as broken; the arc shows the decay.
- Only real wall jumps (a live run's press and the wall coyote).

## 9. Hand taps

- A tiny dust tap under each hand on the lip/top, spreading flat along it. ~0.25 s, the
  smallest effect in the set.
- **Mantle:** on its entry frame (the snap that puts his hands on the lip).
- **Vault:** on the frame the clip crosses `vault_plant_time`, at the detected top point.
- Nothing on hand release; the vault's touchdown is the normal landing dust.
- Hand positions are the lip/top point spread either side of his facing, not read off bones.

## 10. Sprint kicks

Floor only, at most one every **0.5 s** (shared between both).

- **Sprint start:** `is_sprinting` goes false -> true on the floor. A short backward dust kick.
  A slide counts as sprinting for this edge (coming out of one is not a start), and the air
  keeps the edge's memory, so landing already sprinting is not a start either.
- **Hard turn:** at 80 % of `sprint_speed` or above, both now and 0.2 s ago, his travel
  direction has swung more than **100°** in that window. A dust skid thrown along his OLD
  direction (the outside of the turn).
- No stop skid.

## Switch and dials

All under **MOVEMENT EFFECTS**. The new dials are `vfx_*` exports in the same "Movement
Effects" group.

## Shape of the code

New `Pilot9Vfx` verbs: `lasers(active, chest, backward, strength, ease, travel, eye, delta)` (was `wind(...)` off the ankles until the 2026-09-28 laser revision), `slide(active, foot,
backward, strength)`, `slide_start(foot, backward)`, `wall_run(active, foot, normal, fade)`,
`wall_attach(foot, normal)`, `wall_jump(foot, normal)`, `hand_taps(points)`,
`sprint_kick(feet, dir)`, `skid(feet, dir)`. The persistent streams and lights carry a
`persistent` meta so the tests' burst sweep leaves them alone. `pilot9.gd` decides when, in one
per-frame `_update_movement_vfx()` plus the one-shot hooks (`_start_slide`, `_start_wall_run`,
`_take_wall_jump`, `_start_climb`, the vault's plant crossing in `_apply_vault_motion`).

## Built

2026-09-28, `tests/test_pilot9_movement_vfx_2.gd`. Departures and details worth knowing:

- **The slide's entry burst also honours the 3 m/s cutoff** - an auto-slide starting from
  nearly nothing would otherwise burst sparks the stream then refuses.
- **The lasers are CPU bolts drawn into one ImmediateMesh, not GPU particles** (2026-09-28;
  the grilling said particles). Same look, but the dummy renderer runs no particles, so the
  tests could not have seen a bolt - and the camera-clear rule needs each bolt's line at fire
  time anyway. Each bolt is a camera-facing strip of 7 stations rebuilt each frame; a handful
  are ever alive at once.
- **The cone is squashed vertically** (`LASER_SQUASH` 0.7) so the low bolts stay out of the
  floor and the high ones do not tower over his head.
- **His vertical speed counts at half** (`LASER_VERTICAL`) in "backward", so a steep fall aims
  the cone up only partly.
- Dials: `vfx_laser_on_speed` / `_off_speed` / `_full_speed` / `_fade_in` (the old wind trigger,
  renamed), `vfx_laser_color`, `_rate_min` / `_rate_max`, `_length_min` / `_length_max`,
  `_width`, `_lifetime`, `_speed`, `_flare_min` / `_flare_max`, `_ring_radius`, `_behind`,
  `_chest_height`, `_camera_clear`, `_min_opacity`. Every `vfx_wind_*` dial, `_wind_feet()` and
  `WIND_FEET_BONES` are gone; `_wind_latch` / `_wind_strength` are `_laser_latch` / `_speed_ramp`.
- **The wall-jump kick off a live run uses the previous frame's contact** (the run ends before
  the jump is spent) - a few centimetres, not visible.
- The hard turn keeps only FAST floor frames in its history, so a reversal that dips through
  zero still compares the fast frames either side of it.
- Hand-tap spread is a constant (`HAND_TAP_HALF_SPREAD`, 0.2 m either side), not the bones.

## Can't be checked headlessly

The look. The tests fence the lasers' hysteresis, ease-in and dash exception (no new bolts,
live ones fly on), that bolts start behind his chest and flare 10-21 deg off straight back, that
more speed fires far more, that no bolt comes within the clear zone even with the camera dead on
the firing line, that bolts run out after their life, the slide spark cutoff,
the wall-jump kick's coyote placement, the sprint-kick edge, the turn window and the cooldown,
and the switch.
