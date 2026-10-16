# pilot9 - run arm swing

Status: built 2026-10-06.

## Ask

User, 2026-10-06: walk and sprint are loved, the run (moving without sprinting) is not - "all it
needs is for the arms to not swing so far back". Swing less, legs unchanged, arms still in time
with the legs: "when the arms usually wouldve hit their apex, that needs to still be the apex".

## Decisions (grilled 2026-10-06)

- **Whole arc, evenly** - both the forward and the back peak pull toward the middle of the swing
  by the same fraction. Not back-only (that reads as reaching forward).
- **Keep 0.7 of the swing** (`RUN_ARM_SWING` in `scripts/pilot9_build_scene.gd`).
- **Every run clip.** The user chose "all four" thinking there were four; RC actually ships eight
  (`run_forward`, `run_backward`, `run_left`, `run_right` and the four diagonals). All eight are
  scaled so a pivot - when the sideways clips blend in - never flares the arms back out.
- **Joints:** `LeftShoulder`/`RightShoulder`, `LeftUpperArm`/`RightUpperArm`,
  `LeftLowerArm`/`RightLowerArm`. Hands and fingers keep their full motion. Legs, hips, spine,
  head untouched key for key.
- Walk and sprint clips are not touched.

## How

"The middle of the swing" is each joint's **average rotation over the cycle** (normalised
quaternion mean, sign-aligned). Every rotation key `q` becomes `mean.slerp(q, 0.7)`: the joint's
angular distance from the middle shrinks to 0.7 along the same great arc, so the key with the
largest swing before is still the largest after - the apex stays on its frame. Key times are not
touched.

The RC clips are `.res` files in `addons/real-controller/animations/`, shared with anything else
that uses the addon, so they are never edited. The builder (`_ensure_run_arm_swing`) loads the
pristine addon file each run, duplicates it, scales the arm tracks, and puts the copy in pilot9's
own library under the same name - inlined into `scenes/pilot9.tscn` like the GLB clips. Because it
always starts from the addon file, re-running the builder never compounds the scale. The blend
spaces still ask for `run_forward` etc., so nothing in the tree changes.

The math lives in `scripts/arm_swing.gd` (`scale_swing`) so the test can run it on the
source clips directly.

## Staff drawn

The held-item override still owns the right arm while running (docs/specs/pilot9-held-item.md),
so drawn, only the left arm shows the reduced swing. Sheathed, both do.

## Tests

`tests/test_pilot9_run_arm_swing.gd`: for every run clip in pilot9's library -
- every non-arm track is identical to the addon source, key for key;
- each scaled arm track's angular distance from the mean is 0.7 of the source's at every key;
- the key of maximum swing is the same key before and after (apex on the same frame);
- key times unchanged; walk and sprint clips are still the addon's own resources.
