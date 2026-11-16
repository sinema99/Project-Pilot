# EXIA back panels

Grilled 2026-11-11 from two marked-up screenshots (side + back). Two white slabs float off the back
of EXIA's shoulders.

## Decisions

| Question | Answer |
|---|---|
| What they ride on | The chest bone `spine.003`, rigid. They follow the torso's lean and the gait's body bob, never the arms, and have **no motion of their own** (no hover, no sway). |
| Size / shape | Top level with the top of the shoulder armour, bottom just above the feet (about ankle height). Each about one pauldron wide, a clear gap between the two down the back. Thin flat slab, thickness ~1/10 of the width. |
| Tilt | Lean back like the drawing: top near the shoulder, bottom further out behind the legs, so the heels clear it. |
| Gap | Float off the back by about one panel width. |
| Look | Cel-shaded white with the ink outline, same material as the mech (`ApplyCelMech`), so AIRFRAME / RETRO treat them like the mech. |
| Toggle | None. Always on, they cast shadows. |

## Numbers

Measured from the skinned mesh at `MECH_standing` (mech body frame, metres, nose +Z, soles y = 0):
pauldrons top out at y ~ 8.0, span x +-2.6, their back faces sit at z = -2.12; the feet top out
at y ~ 0.46.

| | |
|---|---|
| Width | 1.0 m |
| Thickness | **1.0 m** (rev 2, was 0.7 in rev 1), grows backward from the front face |
| Centre x | +-1.75 m (inner edges +-1.25, a 2.5 m gap down the back) |
| Top / bottom | y 8.0 / **y 0.5** (rev 1) at `MECH_standing`, front edge |
| Gap | **0.05 m** off the body in the panels' lane (rev 3): front face at z = -1.20 |
| Tilt | **0 deg, vertical** (rev 2; 20 deg before). Length 7.5 m |

**Why 20 deg and not the drawing's ~13.** The sprint's back-kick carries a heel ~4.9 m behind the
mech at about 1.6 m up. A sweep over every clip (16 samples each), the panel riding the chest:
6 deg -1.37 m (heel through the slab), 10 -0.91, 14 -0.45, 18 +0.01, **20 +0.24**, 22 +0.47. 20 is
the first tilt with real clearance; the worst frame is the sprint's kick on both sides.

## Build

`scripts/mech_back_panels.gd`: the slab placement is written in the mech body frame
(`standing_transform(side)`). `mech.gd` `_ready` poses `MECH_standing`, reads the chest bone in the
body frame, and parents both slabs to a `BoneAttachment3D` on `spine.003` at
`chest^-1 * standing_transform`. So a re-export that moves the chest bone keeps the slabs where this
table puts them. The slabs are `BoxMesh`es under `Model`, so `ApplyCelMech` (which walks
`EXIA/Model`) dresses them and the looks pick them up with the rest of the mech.

Check: `tests/test_mech_back_panels.gd` (placement at `MECH_standing`, bone, no toggle).
Clearance: `tests/_probe_mech_panels.gd` (headless, every clip). Screenshots:
`tests/_probe_mech_panels_shot.gd` (windowed, the two drawing angles) -> `screenshots/mech-panels/`.

## Rev 1 (2026-11-12): thicker and in close

Grilled from a third marked-up screenshot (side view, red outline). The user: "the rectangle needs to
be thicker, and the rectangles are too far away".

| Question | Answer |
|---|---|
| Gap | Match the drawing: top almost touching the pauldrons' backs, **0.1 m** (was 1.0). |
| Thickness | Match the drawing: **0.7 m** (was 0.1), growing backward so the front face stays put. |
| Bottom | Match the drawing: **y 0.5**, just above the feet (was 1.0). |
| Tilt, width, spacing, top | Unchanged (the drawing's tilt measures ~20 deg). |
| Sprint heel | **Accepted clip.** With the panel in close, the sprint's back-kick heel goes into the panel's lower end on both sides. The user chose this over a ~28 deg tilt or a knee-high bottom. Probe: sprint **-0.61 m** (heel 6.9 m down the slab, both sides), run +0.56, every other clip >= +1.2. |

The 20 deg clearance table above is the rev 0 story (1 m gap); it no longer holds.

## Rev 2 (2026-11-12): square and vertical

Played rev 1: "why are they still so far away, and make them 1m thick just like the width".
The top already sat 0.1 m off the shoulders; it was the 20 deg tilt. Measured at `MECH_standing`
(body frame z): pauldron backs -2.12, heels -1.13, panel bottom at 20 deg -4.95, i.e. 3.8 m
behind the heels. The drawing's tilt read right only because its back foot was mid-kick.

| Question | Answer |
|---|---|
| Thickness | **1.0 m**, same as the width (square section), still grows backward. |
| Tilt | **Vertical** (offered 0 / 5 / 10 / keep 20). The bottom now sits at z -2.22, 1.1 m behind the standing heels. |
| Clipping | Accepted, now the run as well as the sprint. Probe: sprint -2.94, run -1.85 (the back foot pokes out the panel's far side), stops -0.21, jump_air +0.14, everything else >= +0.6. |

## Rev 3 (2026-11-12): against the body

"MOVE THEM CLOSER TO THE MECH." The 0.1 m gap was measured from the wrong surface: -2.12 is the
backpack between the slabs (|x| < 1.25). In the slabs' own lane (|x| 1.25..2.25) the body's back at
`MECH_standing` is: y 5-6 -1.15, y 6-7 -1.12, y 7-8 -0.89, legs -0.6..-1.1. So the slabs floated
a metre off the body. `SHOULDER_BACK` is now -1.15 and the gap 0.05: front face at z -1.20, flush
with the back from the side. Clipping goes up with it (not re-probed, accepted with rev 2).

## Rev 4 (2026-11-12): a pose per state

Grilled from three marked-up screenshots (running from the side, the parked kneel from behind, standing
from the side). "When mech is standing still and upright rotate them out like 10 degrees, rotate the
bottom out, keep the top. When idle and punching the ground, bring the top in and keep where the
bottom is. When running rotate out to like a 45 degree angle."

| Question | Answer |
|---|---|
| Which states | **Running = `Loco.RUN`** (run and sprint). **Standing = every other driven state** (`STAND`, `TURN`, `STOP`, `CROUCH`, `AIR`, `LAND`). **Kneel = parked, nobody driving**: the power-down (`MECH_idle`), the held crouch, and the boot-up (`MECH_launch`). |
| Angle against what | **The upright mech** (its body frame, rolled with the model's bank), not the chest. The slabs still ride the chest for position; only the tilt is held. So a torso leaning into the run does not add to the 45. |
| Standing | Hung from the **top front edge** (where rev 3 put it, riding the chest), bottom swung **10 deg** out. |
| Running | Same pivot, **45 deg** out. The run and sprint heels now clear the slabs. |
| Kneel | Stood on the **bottom front edge** (where the rigid rev 3 slab leaves it in the crouch), top folded in until the front face sits GAP (0.05 m) off the skinned body. **Fitted to the back, not a picked angle**: `tests/_probe_mech_panels_kneel.gd` sweeps the tilt. Left **45.3 deg**, right **50.6 deg** (the punch makes the crouch lopsided); the rigid slab sat at 31. |
| Moving between | Stand -> run **0.25 s**, run -> stand **0.4 s**, smoothstep, no overshoot. The kneel follows the power-down / boot-up clip on a smoothstep of the clip time (the chest's pitch follows that curve to within a degree), capped at 4 /s so a boot-up cut short by a movement key folds out instead of snapping. Between the two pivots the slab's transform is interpolated. |
| Unchanged | Size, the rev 3 placement as the reference, material, always on. |

### Build

`scripts/mech_back_panels.gd`: `posed(side, run, kneel, chest, chest_standing)` gives the slab in the
body frame; `kneel_target` and `step_run` are the two weights. `mech.gd` `_update_back_panels` runs in
`_process`, reading the chest from the skeleton's pose and the `driving` flag the physics step sets.
Check: `tests/test_mech_back_panels.gd` (rev 4 angles, pivots, weights, timings). Shots:
`tests/_probe_mech_panels_shot.gd` now has a `kneel` sheet and puts the run/sprint sheets in `RUN`.

## Rev 4b (2026-11-12): off the body getting in and out

Played: "the rectangle glitch through the body when getting into and out of the mech." Measured with
`tests/_probe_mech_panels_transition.gd`: through the power-down (getting out) the hunching back went
up to a full slab thickness into both slabs, and in the boot-up (getting in) the right shoulder block
rises through the top of the right slab. That happens with any tilt blend, because the body itself
moves back into the slabs.

Fix: each slab slides straight back along its own normal by a baked amount, `PUSH` in
`scripts/mech_back_panels.gd` (21 samples per clip per side, widened one sample each way). Peaks:
power-down ~1.7 m mid-clip, boot-up right 2.9 m for ~0.1 s (the shoulder), boot-up left 0.5 m. A rising
push applies at once; a dropping one (boot-up cut short) eases back at 8 m/s. Checked at 4x the table
resolution: closest body vertex +0.011 m, no clip. Re-bake with `-- bake` after a Mech_V1 re-export.

## Rev 4c (2026-11-12): the right panel's hop eased

"Make the right panel hop smoother." The boot-up's right push went 0.2 -> 2.9 m in ~0.05 s. The bake
now spreads every sample's need on a smoothstep, 0.2 s ahead and 0.35 s behind, finishing inside the
clip (so the held kneel keeps its fitted gap and the boot-up starts at 0), then widens it one sample.
Tables are 41 samples per clip (0.025 s) so the lerp follows the shoulder's fast rise. The right panel
now eases out over the boot-up's first 0.25 s and settles over ~0.5 s; the power-down's push rises and
falls the same way. Checked at 4x (160 per clip): closest body vertex +0.011 m.

## Rev 5 (2026-11-12): heavy storage, swinging on the shoulders

The slabs are going to be EXIA's **storage** (what goes in them and how you open them is a later,
separate spec). This pass makes them read as heavy boxes hinged to the shoulders. Grilled with the
user, every answer the recommended one:

1. **Hinge and motion.** Each slab is a pendulum on its top front edge (the existing hang point), its
   bottom swinging fore-aft. A damped spring driven by the mech's forward acceleration: it lags out
   on a start / speed-up and carries in on a stop. A turn swings it out a little (|lateral accel|).
   Every footfall thumps it, the heavy jump's take-off and landing more so (landing the most). Slow
   and heavy: ~1 s period, damping ratio 0.35 (one overshoot, then settled).
2. **Axis.** Fore-aft only: one shared hinge angle, added to the stand/run tilt. **One simulation
   drives both slabs**, so left and right always hold the same angle.
3. **Kneel angles matched.** Both kneel at 45.3 deg (was L 45.3 / R 50.6). The right slab sits ~5 deg
   off the back at the top in the parked kneel, nothing clips. The per-side `PUSH` stays: it slides,
   it never tilts.
4. **When.** Whenever the mech is driven, the jump included. It fades by `(1 - kneel)` through the
   power-down (the knelt pose is not hung from the top edge), is still when parked, and the spring is
   reset to rest once fully knelt, so the boot-up starts from rest.
5. **Limits.** Up to ~6 deg out, a cushioned soft cap ~3 deg in: past the cap a stiff spring with
   extra damping pushes it back, so a hard stop "thunks" against the back and comes off it. Hard
   clamp at 1.5x each cap as a safety.
6. **Storage.** Sway only. Nothing here may hold a slab off its pose for good (a future lid-open pose
   must own the slab without fighting a resting offset).
7. **No toggle.** Tunables are the `SWAY_*` constants in `scripts/mech_back_panels.gd`.

### Numbers

| | |
|---|---|
| Period / damping ratio | 1.0 s / 0.35 |
| Swing per m/s^2 forward accel (static) | 0.3 deg |
| Accel input | clamped +-20 m/s^2, low-passed 0.08 s (the instant STAND stop is one 540 m/s^2 tick) |
| Turn share | 0.15 of |speed x yaw rate|, outward |
| Footfall kick | 14 deg/s inward (sprint), x0.6 run (~1 deg bob, ~13 cm at the bottom) |
| Take-off kick | 18 deg/s inward |
| Landing kick | 25 deg/s inward x clamp(fall / 3 m, 0.5, 2) |
| Caps | 6 deg out / 3 deg in, cushion 600 1/s^2, cushion damping 24 1/s |

Sign: positive = bottom out (the stand/run tilt's sign). A vertical jolt (step, jump, landing) pulls
a tilted slab toward hanging straight, i.e. inward, and it springs back out past its pose.

## Rev 6 (2026-11-12): THE RULE - the top is a hinge on the shoulder

The user: "the top of the boxes should be the anchor. That's the hinge. It should always be in the
same place, relative to the shoulder. The bottom should be the part that gets moved around." Revs 4
and 4b broke this twice: the parked kneel stood each slab on its BOTTOM edge and folded the top in,
and `PUSH` slid whole slabs (top included) up to 2.9 m off the body. Grilled, every answer the
recommended one unless noted:

1. **Hinge.** Each box's top front edge (middle of it) rides its own shoulder bone: the side -1 box
   (`PanelL`, -X) on `shoulder.R`, the +X box (`PanelR`) on `shoulder.L`. The offset is measured once
   at `MECH_standing`, so standing looks unchanged. Each slab sits under its own `BoneAttachment3D`
   (`BackPanelsL` / `BackPanelsR`), so the hinge goes with the bone even a frame late.
2. **One angle.** Both boxes hold one angle, against the upright mech (not the bone's own tilt).
   It is the ONLY thing that changes, and only the bottom moves. No slide, no standing on the bottom.
3. **Parked = kickstand.** The bottom swings back until the LOWER box's bottom front edge sits on the
   ground (`kickstand_deg`, computed live from the lower hinge's height, ~38 deg when parked, both
   hinges at y 5.91). No box below the floor; the other would hover by the height difference (none at
   present: the parked shoulders are level).
4. **Getting in / out = baked clearance angle**, `CLEARANCE`, replacing `PUSH`: per 1/40 of
   `MECH_idle` / `MECH_launch`, the smallest shared angle at or above the pose angle that keeps the
   body out of BOTH boxes; eased like rev 4c. Rising applies at once, dropping eases at 120 deg/s.
5. **Sway.** Final angle = max(lerp(stand/run + sway, kickstand, kneel), clearance): the box swings
   freely but never in past the floor; sway fades out into the kickstand.
6. **Accepted clips (user, after the bake showed the conflicts).** Parked, the ground wins: at the
   kickstand the left box cuts the right upper arm and the right box the kneeling left leg (clearing
   them needed ~51 deg, bottoms ~1.2 m off the ground). Boot-up 0.15-0.33 s: the right shoulder swings
   out and the chest rises into the right box right at its hinge; no angle clears that, so it keeps
   the normal swing. The bake leaves out vertices weighted mostly to `upper_arm.R`, `forearm.R`,
   `hand.R`, `shin.L`, `foot.L`, `toe.L`, `toe.L.001`, and gives no floor to an unfixable moment.

Removed: `stand_on_bottom`, `KNEEL_TILT_DEG`, `kneel_tilt`, `PUSH`, `push_for`, the chest attachment,
and `tests/_probe_mech_panels_kneel.gd` (the kickstand is computed, not fitted). Re-bake
`CLEARANCE` with `tests/_probe_mech_panels_transition.gd -- bake` after a Mech_V1 re-export.
Check: `tests/test_mech_back_panels.gd` `test_rev6_the_hinge_never_leaves_its_shoulder...` drives
mech.gd's own update through standing, run, sprint, power-down, parked and boot-up and reads the
scene graph: every hinge stays within 1 mm of its shoulder offset and both boxes share the angle.

## Rev 7 (2026-11-12): running closer to the feet

"Everything on the storage boxes looks good. When the mech is moving though, they're too high up.
Bring them closer to the feet." Marked-up run screenshot: the red outline keeps the same hinge and
length, only swung less (~25 deg against the box's ~40 on screen). Under THE RULE the angle is the
only lever. Grilled, both answers the recommended one:

1. **Running angle (`RUN_TILT_DEG`, run and sprint): 45 -> 25 deg.** The bottom drops ~1 m and comes
   ~2 m forward, just behind the back foot. Everything else unchanged (stand 10, kickstand, clearance
   bake, sway, 0.25 / 0.4 s blends).
2. **Heel clip accepted, one angle for run and sprint** (not a split run 25 / sprint ~35).

Measured (boxes placed live with `place` at the swept angle, 32 samples per clip, sway left out;
closest body vertex to a box's front face, positive = clear):

| Angle | MECH_run | MECH_sprint |
|---|---|---|
| 15 | -1.17 (26/32 clipping) | -2.51 (32/32) |
| 20 | -0.55 (18/32) | -1.90 (30/32) |
| **25** | **+0.07 (clear)** | **-1.28 (24/32)** |
| 30 | +0.53 | -0.66 (16/32) |
| 35 | +0.54 | -0.04 (2/32) |
| 45 | +0.55 | +0.51 |

So at 25 the run clears (just), and the sprint's back foot sits up to 1.28 m inside the lower end of
the boxes (~7 m down from the hinge) for most of the cycle. Sprint 35 would nearly clear it, if the
user changes their mind on the split.
