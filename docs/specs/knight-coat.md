# Knight boss - moving coat

Status: specced and built 2026-11-09 (grill of 5, every recommendation taken). Not yet played.

The Knight's long pleated robe (docs/specs/knight-boss.md) was a rigid bell on his hips: he floats,
so his legs barely move and the coat never did. User: "it needs to be moving. even just a little,
it just cant be STATIC." This pass makes the coat and the sash tails move, always.

## Decisions

1. **Idle + reactive.** A low idle billow so the coat is never static, plus reactive motion on
   top: it trails his drift, kicks on the laser recoil, drags down on the smash rise, streams on the
   dive, slaps out on the impact, and settles with one or two overshoots (underdamped, not jelly).
2. **Coat bones + spring code.** 8 two-bone chains added to his skeleton in code, one down each
   pleat ridge (waist -> knee row -> hem). The robe, its inside and its crease ink are weighted to
   the two nearest chains, so ink and outline move with it for free. Springs in code drive the
   chains from his motion and a noise billow. No SoftBody / physics cloth (the poncho was 6-8 ms
   and was scrapped).
3. **Sizes.**
   - Idle: the hem travels ~5-8 cm (world, at his 1.5x) as a wave running round the coat about
     every 3 s; less up the coat, still at the sash.
   - Drift: the hem trails up to ~20 deg behind his motion (4 m/s strafe).
   - Big moves: flare up to ~40 deg (hard cap) - recoil, rise, dive, impact.
4. **The sweep moves into the bones.** The mesh is modelled hanging straight. The drawing's sweep
   to his left is the chains' resting target while he is dormant (the drawing pose looks as
   approved, plus the idle billow), and it eases to a neutral hang over the 1.5 s wake. After that
   any sweep comes from his motion.
5. **Sash tails move too.** One spring bone each, lighter and quicker than the coat.

## Technical defaults (stated in the grill, not objected to)

- **Legs.** The old weighting (hips at the waist giving way to the thighs, and the near shin
  below the knee) becomes part of each chain's target: a chain follows the thigh on its side by up
  to half, the lower segment the shin a little - so the panels still part when his legs pose.
- **No clipping.** The motion part of a chain may swing in toward his legs by only a few degrees.
- **No menu toggle.** It's how he looks. Tunables are an export group ("Coat") on KnightBody.
- **Gravity.** The coat hangs partly toward world down (30%) when he pitches, capped with the rest.

## Built

- `scripts/boss/knight_body.gd`
  - `_add_coat_bones()` (before `_build`, so the Skin binds them): `CoatU0..7` (parent Hips, at the
    waist on each ridge), `CoatL0..7` (parent CoatU, at the knee row), `SashTail0/1` (parent Hips,
    at each tail's top). Their global rest bases are identity, so a chain's pose is a model-space
    rotation. `show_pose` / `show_blend` leave them alone (`coat_first`).
  - `_robe()` weights: the two nearest chains by angle round the robe axis, upper -> lower across
    the knee row. The sash tails blend Hips -> their bone down their length.
  - `_robe_point(..., swept)`: the mesh is built with `swept = false`; the swept points only feed
    the dormant targets.
  - `tick_coat(delta)` in `_physics_process` (callable by probes/tests that step by hand): samples
    the hips' world velocity / acceleration / yaw rate in his hips frame, builds each segment's
    spring target (dormant sweep x `coat_sweep`, legs, gravity), and integrates a 2D tilt spring per
    segment against equilibrium shifts from drag (velocity), kick (acceleration), swirl (yaw rate)
    and the idle billow. Caps: dynamic tilt soft-saturates at `coat_cap_deg`, inward at
    `coat_inward_deg`. A jump over 5 m in a tick (reset / teleport) zeroes the motion history.
  - `coat_sweep_target`: 1 dormant, 0 awake; `coat_sweep` follows it over `coat_sweep_time`.
- `scripts/boss/knight_brain.gd`: entering WAKE sets the target to 0, `reset()` back to 1 (snaps).
- Tests: tests/test_knight_body.gd (bones, weights, dormant sweep, idle never static, drift trail,
  caps, handoff). Look: tests/_probe_knight_moves.gd steps the coat with the brain.
