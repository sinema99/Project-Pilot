# pilot9 tredge (the blizzard walk)

Grilled 2026-10-14. When pilot9 is out in the Ichi blizzard (on the walk from his parked ship to
the building), he can only tredge: a slow, hunched, high-knee wade into the wind, the staff held
up as a torch in his right hand and his left forearm across his face. Everything else is locked
until he is under cover again. The staff's light was added the same day ("Staff light" below).

## When it is on

- **Outside = the roof map.** The test is `Storm.is_sheltered()` at his chest (1.3 m above his
  origin). That is the same roof map that keeps the snow out of the building
  ([ichi-snowstorm.md](ichi-snowstorm.md), "Snow shelter"), so he tredges wherever snow falls
  on him, and walks normally under the building's roof or the ship's hull (the `storm_roof`
  boxes). Nothing is placed by hand.
- **Only where a `Storm` node exists**, which today is only Ichi. Trial, the test platform and
  the cutscenes are untouched. Storm joins the group `storm` so pilot9 can find it.
- **Debounce 0.25 s.** He has to be covered (or exposed) for 0.25 s before the switch flips, so
  the edge of an overhang cannot flicker it.
- **It starts only from plain locomotion.** If he becomes exposed mid-dash, mid-wall-run,
  mid-mantle, mid-vault, mid-climb, mid-slide or on a rail, the tredge waits for that move to
  end. A crouch is cleared on the way in.
- Headless there is no roof map (`roof_height` is -INF everywhere), so a Storm reads as exposed
  everywhere. Tests force the switch instead (below).

## Locked while tredging

Sprint (the toggle is cleared and held off), the walk toggle, jump, double jump, crouch, slide,
dash, wall-run, wall climb, mantle, vault, rail grind and switch, reflect (left mouse / right
shoulder) and equip/holster (R). The camera and the pause menu stay free. The lock lifts the
instant the tredge switches off. The pose blend-out does not hold it.

Walking off an edge while tredging still falls (the `fall` state plays). He is still tredging
when he lands, so nothing unlocks mid-air.

## The staff

- **Ichi opens with it in hand.** If the tredge is on from the first tick, the staff snaps
  drawn and the pose snaps to full with no blend-in.
- **Stepping out holstered** (say he walks back out of the building) plays the ordinary draw
  (`EquipAnim`, ~0.37 s) automatically. He keeps tredging through it, and the torch arm fades in
  once the draw has settled.
- **Stepping inside** gives normal control back. The staff stays in his hand and R holsters it
  as usual.
- **Torch grip.** While the torch arm is up, the staff slides 0.4 m along its own +Y in his
  fist (`tredge_grip_slide`). He holds it low on the shaft, the top end stands well above his
  head, and the bottom end stays clear of his rising knee. The future light goes on the staff's
  +Y end.

## Movement

- **1.5 m/s** (`tredge_speed`), against walk's 2.5.
- **Gusts dip it to ~60%** (`tredge_gust_slow` 0.4) at a gust's peak. The gust is the storm's
  own curve, `storm_gust_peak()` in `shaders/storm/storm_gust.gdshaderinc`, mirrored in GDScript
  as `Storm.gust_peak()` on the same clock as the shader's `TIME`. The stagger therefore lands
  on the same beat as the whiteout. There is no sideways shove: the gust never pushes him off
  the line the stick is steering.
- **Always facing travel, one clip.** Pulling back turns him round. He never strafes or backs
  up.
- **Half turn speed** (`tredge_turn_scale` 0.5 of `rotation_speed`).

## The clip: `tredge`

A new pilot9-only clip baked by `scripts/pilot9_build_scene.gd` from RC's `walk_forward`, which
it reads every time and never writes. Walk is untouched. The bake is legs only
(`scripts/tredge_bake.gd`):

- **Shorter stride.** The thigh's swing is scaled to 0.86 around its cycle mean, using the
  run-arm-swing helper on `UpperLeg`.
- **High knees.** Through the swing phase (the knee more than a third of the way from its
  straightest to its deepest bend) the knee bends up to 14° more and the thigh lifts up to 10°
  more. Measured on the rig, the foot's peak goes from 0.20/0.22 m to 0.29/0.31 m (+9 cm), and
  the stride from 0.89 m to 0.80 m. In stance both extras are zero, so planted feet are
  untouched. A first pass at 25°/18° lifted the foot 17 cm, which was too much.
- **Wider stance.** Each thigh is turned 3° outward the whole cycle, about 5 cm per foot, with
  the foot turned back level.

The `tredge` state is a blend tree: `idle` and the `tredge` clip (through a TimeScale) in a
Blend2. `pilot9_animation.gd` drives the blend by his speed and plays the cycle at
`0.7 × speed / 1.5`, so the feet stay planted through the gust dips too. Transitions:
Locomotion ↔ tredge 0.5 s on `is_tredging`, `jump_land` → tredge, and tredge → fall when he
leaves the floor.

## The pose layer

`scripts/tredge_pose.gd` is a SkeletonModifier3D added after every other arm modifier, with
weight easing 0 → 1 over 0.5 s each way. Everything below is in his own frame, so it holds at
any heading:

- **Hunch.** 18° forward across Spine/Chest/UpperChest (0.35/0.35/0.3), plus 10° more on the
  neck and head (head down) and the shoulders rolled 8° in.
- **Lantern arm (right).** Two-bone IK, using the slide hand's twist-aware fold, puts the wrist
  0.32 m ahead of the right shoulder, 0.06 m out and 0.22 m below it, with the elbow down and
  out. The hand then turns so the staff stands up, tipped 10° forward and 8° out. The target is
  in his frame, not the chest's, so the light stays steady while the torso rocks. A small bob
  (±1.5 cm) rides the step cycle.
- **Shield arm (left).** IK puts the wrist just in front of his face (0.2 m ahead of the head,
  0.1 m to his right, at eye level), with the elbow out to the left and down. The forearm lies
  across his eyes.
- **Braced idle.** Standing still the same layer sits over `idle`. Gusts still rock him.
- **Gust stumble.** A damped spring follows the gust peak and overshoots, giving a jolt and a
  wobble. It pitches him back up to 5° and rolls him up to 6° away from the wind's side, plus a
  small head nod.
- **Draw handover.** While the equip animation plays, the lantern arm's weight drops to 0 so
  the draw is visible. The staff's grip slide follows the same weight.

## Testing

**F6** cycles AUTO → FORCED ON → FORCED OFF → AUTO in any scene, printing the mode to the
console. Tests set the same override (`Pilot9Tredge.Mode`). The camera is unchanged.

## Tunables

These are pilot9 exports in the `Tredge` group: `tredge_speed`, `tredge_gust_slow`,
`tredge_turn_scale`, `tredge_clip_rate_at_speed`, `tredge_blend_time`, `tredge_debounce`,
`tredge_speed_rate`, `tredge_grip_slide`. The pose angles and IK targets are exports on the
`TredgePose` modifier (under `GeneralSkeleton`), so they can be tuned live in the remote
inspector. The bake's numbers are consts at the top of `scripts/tredge_bake.gd`, so retuning
those means re-running the builder.

## Built (2026-10-14)

All in one session, straight after the grill. Differences from the plan above:

- **No momentum while tredging.** `momentum_decay` is 0, so a lower target speed never takes
  speed off him. Without a change, neither the gust dip nor a run carried out of the building
  would ever slow him. While tredging on the floor his speed eases toward the tredge's at
  `tredge_speed_rate` (6 m/s²) instead. That's 1.5 → ~1.05 m/s at a gust's peak in the probe.
- **Braced idle has no hip drop.** Lowering the hips without bending the knees would sink his
  feet into the snow. Standing still is the hunch, both arms and the gust on top of `idle`.
- **The arm IK refines the elbow numerically.** The forearm isn't square to its hinge (the
  lower arm's +X), so the slide hand's projected fold left the lantern wrist 2.4 cm short. A
  few Newton steps on the shoulder-to-wrist distance land it exactly. The elbow's bend sign is
  read from the incoming pose, so the left (mirrored) arm folds the right way too.
- `sprint_toggled` gained one writer, the tredge lock in `_update_sprint_toggle()`, and
  `tests/test_pilot9_sprint_stop.gd` counts six now.
- The builder drops `pilot9_animation.gd` from the scene without failing if that script
  doesn't parse. A rebuild with a parse error in it writes a pilot9.tscn with no animation
  driver, so check for `SCRIPT ERROR` in the builder's output.

Tests: `tests/test_pilot9_tredge.gd`. The full suite passes (1176 tests). The look was
checked with `tests/_probe_tredge_shot.gd` (windowed, in Ichi): idle and walking from the side,
the front three-quarter and behind. Not yet played.

## Staff light (2026-10-14)

Grilled after the first look ("the new trudge animation looks fantastic"). The staff becomes
his light source in the storm.

- **Grip high on the shaft.** `tredge_grip_slide` -0.4: the staff slides *down* through his
  fist, so his fist is 3/4 of the way up the 1.6 m staff and 0.4 m stands above it.
- **Arm out farther and higher.** `lantern_offset` (-0.08, -0.05, 0.45): the wrist 0.45 m
  ahead of the right shoulder, 0.05 m below it, 0.08 m out. Elbow still a little bent.
- **Only while tredging.** The ball and its light fade with the torch arm (`pose.lantern`), so
  they come and go with the arm over 0.5 s and are absent through the draw and inside.
- **The ball.** `scripts/staff_light.gd`, built by `pilot9_tredge.gd` as `Tredge/StaffLight`
  (top-level). An unshaded pale orange (`#FFD2A0`) sphere of 0.07 m radius, its centre 0.12 m
  above the staff's top end (the top of the staff's mesh bounds), no outline. It floats �1 cm
  over 1.5 s and chases the tip at `follow_rate` 25/s, so it lags a touch. The core scales in
  with the fade.
- **The halo.** A 0.35 m additive billboard (`shaders/staff_light_halo.gdshader`). Ichi has no
  bloom, and the environment's glow stays off.
- **The light.** An OmniLight3D, the same colour, range 6 m, energy 1.5 (1.3 since the retune), shadows on. A slow
  �5% flicker (three incommensurate sines) and a 15% dip at a full gust stumble.
- **The storm reacts.** `storm_torch_pos`, `storm_torch_color`, `storm_torch` (strength, flake
  reach 3 m, fog glow radius 1 m) and `storm_torch_fog` (0.6) are project shader globals,
  read by `shaders/storm/storm_torch.gdshaderinc`. Flakes within 3 m take the colour and
  brighten (`storm_snow.gdshader`). The fog pass adds a warm haze where a view ray passes close
  to the ball, cut off by any surface in front of it, over sky pixels too
  (`storm_fog.gdshader`). Strength 0 changes nothing.
- **No toggle.** Every number is an export on `Tredge/StaffLight` (plus the two pose ones above).

### Built (2026-10-14)

- **The light's pool is smooth, not banded.** The cel shader folds a point light's ATTENUATION
  into its colour (the fix for the hard disc under the spark lights), so the omni's falloff and
  its shadow come out as a soft wash, not a two-tone pool.
- **In the probe the light is subtle by day.** Ichi's whiteout is bright, so the ball, halo and
  haze read clearly, but the warm wash on the snow and the ship is faint. Raise `energy` if it
  wants more.
- The staff's bottom end lands ahead of his planted foot in the side view and clears the knee,
  so the tilt is unchanged.

### Retune (2026-10-14, after the user's first look)

- **Bottom end out.** `lantern_tilt_out` +8 -> -16: the top tips in toward his head, so the
  bottom points out away from his legs (matched to the user's sketch from behind; -8 only read
  as upright).
- **Ball in line with the staff.** It sits `gap` past the top end along the staff's own axis,
  and floats along that axis, not world up. The follow lag is gone. It is placed on the staff
  skeleton's `skeleton_updated`, after the hand socket, so it is never a frame behind.
- **A smidge dimmer.** `energy` 1.5 -> 1.3, `halo_intensity` 0.8 -> 0.7, `fog_glow` 0.6 -> 0.5.

Tests: `test_pilot9_tredge.gd` (the grip slides down, the light follows the arm, the ball sits
`gap` past the top end in line with a tilted staff, flicker bounds and gust dip). Full suite passes (1179). Probe shots
from `tests/_probe_tredge_shot.gd` checked. Not yet played.
