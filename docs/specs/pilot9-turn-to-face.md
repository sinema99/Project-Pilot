# Spec: turn-to-face movement for pilot9

> **Status:** agreed and built 2026-09-06. Not yet played - the feel is unjudged.
> **Scene:** `scenes/pilot9.tscn`. **Character:** `assets/pilot9.glb`.
> **Follows:** `docs/specs/pilot9-real-controller.md`, which this deviates from on purpose.

## Problem statement

The crouch shipped on 2026-09-06 with one clip. `scripts/pilot9_build_scene.gd::_ensure_crouch_state()`
builds the `crouch` state as a single `AnimationNodeAnimation` playing `crouch_walk` (the Blender
action `P.crouchwalk`) through a TimeScale node. `Locomotion` next door has three BlendSpace2Ds fed
by RC's 8-direction clip set; the crouch has nothing of the kind, because Mixamo supplied one
crouched walk and it walks forward.

Crouched, pilot9 still *moves* in every direction - `_apply_movement` is direction-agnostic - so
strafing and backing up play a forward crouch walk over sideways motion. It reads as skating.

The obvious fix is four more Mixamo clips and a crouch blend space. The user proposed a different
one, and it is better: **stop strafing.** Turn the character to face wherever he is travelling. Then
he is always walking forward relative to his own body, one forward clip is correct in all
directions, and the same is true of every forward-only clip that arrives after it.

That is the trade this spec makes. It costs RC's backing-up and strafing, in exchange for the crouch
working today, a camera that can be left pointing anywhere, and a movement rule that does not need a
new clip per direction ever again.

## Decisions (from the user, 2026-09-06)

- **No auto-recenter.** This is the point of the change, and it is where "GTA camera" is a
  misleading name for it. GTA does turn-to-face *and* lazily swings the camera back behind the
  player, which is why you rarely see Franklin's face while running. Recentering would eat the
  run-toward-the-camera view within about a second of getting it. The camera holds whatever yaw it
  was left at - Zelda / Mario / unlocked Souls, not GTA.
- **Dial-a-pivot.** Turn on a dime at a tunable rate. No speed penalty on sharp turns, no
  turn-in-place clips in this pass. `rotation_speed` is the dial the user tunes on play.
- **No aim mode yet.** Not never - the seam stays in (see "The strafe seam").
- **No strafe modifier in v1.** Claude's call, argued below.
- **No first person.** `allow_camera_mode_switch` stays `false`; the FIRST_PERSON branch is left
  where it is rather than ripped out.
- **No crouch idle yet.** The user adds that clip later. The TimeScale stays and so does its rough
  edge - see "What this does not fix".

### On the strafe modifier (question 4, answered here rather than by the user)

The verb this change costs is inching backward while watching something: edging off a ledge,
retreating from a threat, lining up a drop. The cheap rescue was "hold `walk` to strafe
camera-relative" - the action is already bound and `can_walk` already exists.

Not doing it. It is a second control mode nobody asked for, hidden behind a key that already means
something else, and it re-opens the exact case the forward-only crouch clip cannot cover. Better to
ship one rule, find out on play whether the verb is actually missed, and add it deliberately if it
is. Adding it later is two lines *provided* the seam below exists, so this is a deferral and not a
door closing.

## The rule

**Third person, on input: the character mesh faces the direction it is travelling.**

`scripts/pilot9.gd::_handle_character_rotation()` currently lerps `character.rotation.y` toward
`camera_pivot.rotation.y + PI` whenever `input_dir != Vector2.ZERO`. The new target is the travel
direction:

```gdscript
var target := atan2(direction.x, direction.z)
character.rotation.y = lerp_angle(character.rotation.y, target, rotation_speed * delta)
```

This is a generalisation of what is there, not a replacement for it. `direction` is already
camera-relative (`_handle_movement_input` builds it from the camera basis), and for straight-forward
input `atan2(direction.x, direction.z)` evaluates to exactly `camera_pivot.rotation.y + PI` - which
is also the proof that the sign convention and the 180 degree basis baked into the `character` node
are being respected. Checked by hand at camera yaw 0 and at yaw PI/2 before writing this.

Everything else about the existing function stays:

- **Still gated on input.** Standing still he holds his last facing and the camera orbits freely
  around him. That gate was added for exactly this reason and it now matters more, because his
  facing is no longer recoverable from the camera's.
- **Still returns early in FIRST_PERSON.** Turn-to-face is meaningless there.
- **Still a `lerp_angle`.** `rotation_speed` (currently 10.0) is the pivot dial. A 180 at 10.0 lands
  in roughly a quarter second; expect to tune it on play, and expect a visible skate during the turn
  because velocity changes instantly and facing does not. That skate is what the blend-space change
  below exists to sell.

## What this does to the blend spaces

`scripts/pilot9_animation.gd` feeds all three locomotion blend spaces
`Vector2(player.input_dir.x, -player.input_dir.y)` - input space, forward at `(0, 1)`, which is where
`run_forward` and its siblings sit in all three (verified against `scenes/pilot9.tscn`).

Left alone, that input is now wrong: pressing left while the body has already turned left would ask
for `run_left` while he runs forward. The naive fix is to pin the blend to `(0, 1)` and let RC's 18
directional clips go dead.

**Do not pin it.** Feed the blend spaces the travel direction *in body space* instead. As built:

```gdscript
var b: Basis = player.character.transform.basis
return Vector2(-player.direction.dot(b.x), player.direction.dot(b.z)) * player.input_strength
```

Steady state the body is aligned with travel and this reads `(0, 1)` - pure `run_forward`, as
intended. Mid-pivot the body lags the heading, the blend swings sideways, and `run_left` /
`run_right` / `run_backward` play *during the turn*, giving the pivot a lean instead of a skate. The
clips keep earning their place, the degradation is graceful, and there is nothing to delete.

This is projection onto the body's own axes rather than the `angle_difference` / `Vector2.rotated`
form first drafted here. Same result, one fewer convention to be wrong about - and the sign it does
depend on was **measured, not derived.** A throwaway probe at three camera yaws established that
pilot9's mesh faces its local **+Z** while his local **+X** points to his **left** (the 180 degree
basis on the `character` node), so travel toward his right is `-basis.x` and hence the negation on
the X term. The same probe confirmed `atan2(direction.x, direction.z)` equals `camera_pivot.rotation.y
+ PI` for forward input, which is the equality the rotation change rests on. Both are now pinned by
`tests/test_pilot9_turn_to_face.gd`, because a flipped X leans him the wrong way through every turn
and reads on play as a bad blend space rather than as a wrong sign.

Local basis rather than global: only the mesh child ever rotates, never the CharacterBody, so they
agree - and the local one is readable outside the SceneTree, which is what makes the blend feed
testable headlessly.

One behaviour change rides along: the magnitude is `input_strength` (already clamped to 1) rather
than the raw `input_dir` length, so a keyboard diagonal lands on the unit circle where the clips sit
instead of `sqrt(2)` past it.

**A stale-state trap, found while building:** `handle_frozen_movement()` clears `input_dir` and
nothing else, so `direction` and `input_strength` keep last frame's values. Stock's input-space blend
went to idle for free; a body-space blend reading those two would march him on the spot while frozen.
`_travel_blend()` returns early on zero `input_dir` for exactly this, and a test holds it.

Also dead on arrival, and to be removed in the same pass: `is_moving_backward` and the `SpeedBlend`
target it gates in `pilot9_animation.gd`. There is no backward any more.

## The strafe seam

Both deferred features - a strafe modifier, and an aim mode later - are the same switch. Build the
rotation rule and the blend feed to branch on one boolean (`face_travel_direction`, defaulting
`true`), where `false` restores exactly today's behaviour: weld to camera-back, feed the blend spaces
input space. Nothing else in either file should know which mode is live.

That is the whole cost of keeping the door open, and it is why v1 can ship one rule without painting
itself into a corner.

## What this fixes for the crouch

All of the directional problem, and none of the standing-still problem.

Moving, the forward crouch walk becomes correct in every direction, because there is only one
direction now. No new clips, no crouch blend space, `_ensure_crouch_state()` untouched.

## What this does not fix

- **The crouch idle.** Stopped while crouched, `_drive_crouch` still eases the TimeScale to zero and
  he holds whatever mid-stride frame he stopped on, one leg out. Deferred by the user; it is one
  clip, and it is the most visible thing left once movement stops skating.
- **Crouch does nothing physically.** The capsule is still 1.9552 m tall and CameraPivot still sits
  at y=1.5, so he cannot fit under anything, break a sightline, or take cover. Crouch is a pose and a
  speed change. Making it a mechanic - shrink the capsule, drop the pivot, refuse to stand up under a
  low ceiling - is roughly 40 lines and is unrelated to which animation route won. Not scheduled.

## Tests

Built as `tests/test_pilot9_turn_to_face.gd` - 9 tests, headless, no play required. The scene is
driven without entering the SceneTree: the controller's `@onready` node references are wired by hand
and input state is set the way `_handle_movement_input` would have. What is asserted:

- Straight-forward input produces the same facing angle the old camera-back formula did. This is the
  regression that catches a sign flip in `atan2`.
- A travel direction 90 degrees off the body's facing produces a blend position with the correct X
  sign - turning right leans toward `run_right`, not `run_left`.
- Zero lag produces `(0, 1)` to within epsilon, so the steady state is genuinely `run_forward` and
  not a permanent slight strafe.
- `face_travel_direction = false` reproduces stock behaviour on both the rotation target and the
  blend feed, including for sideways input - an aim mode built on this flag inherits that fallback.
- FIRST_PERSON leaves the body facing untouched.
- Travel to the body's left asks for `run_left`, so the sign is pinned from both directions.
- Zero `input_dir` with a stale `direction` blends to idle (the frozen trap above).

**What automated checks cannot establish:** whether the pivot rate feels right, whether the lean
during a turn reads as intent or as a wobble, whether losing backing-up is missed, and whether
running at the camera is as good in play as it is on paper. Those are the user's on play.

## Not in this pass

- **Turn-in-place.** RC's `turn_left` / `turn_right` are in pilot9's animation library and wired into
  nothing. A reverse-while-stationary state built on them is the nicer version of the pivot; it waits
  until the dial has been tuned and the plain version judged.
- **Speed penalty on sharp turns.** The heavier GTA/RDR feel. Rejected for v1 in favour of the dial.
- **Strafe modifier and aim mode.** Deferred above; the seam is the deliverable instead.
- **Crouch idle, crouch blend space, and the crouch capsule/camera/ceiling mechanic.** All named
  above, none scheduled here.
